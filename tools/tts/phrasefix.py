#!/usr/bin/env python3
"""Много изрази наведнъж в одобрените записи (12.11.2026) — phrasesplice.py
за цял списък и по няколко израза в едно парче.

    python3 phrasefix.py <снимка> <поправки.py> <папка за слушане> [--dry]

<снимка> — json „беседа|блок|парче“ → текстът на одобрения запис (виж
work/snap_*.json). <поправки.py> дава FIXES = [(парче, израз в правилото,
нов израз, бележка)] и in_audio(парче, израз) → изразът, както е в записа.
Правилата в INSERT_FIX трябва вече да дават новия текст — проверява се.

За всеки израз се генерира САМО той (текстът около него се праща за
интонацията), изрязва се в средата на паузите и заменя стария с 15 ms
преливане и изравнена сила. Резултатът ляга под ключа на парчето с новия
текст, тъй че eleven.py после го взима без заявка. За слушане —
<папка>/NN_staro.mp3 и NN_novo.mp3 (+ spisak.json)."""
import array
import importlib.util
import json
import math
import sys
from pathlib import Path

import eleven as E
from splice_many import cache_key, mp3

R = E.RATE
snap_p, fixes_p, out_dir = sys.argv[1:4]
dry = '--dry' in sys.argv
spec = importlib.util.spec_from_file_location('fixes', fixes_p)
F = importlib.util.module_from_spec(spec)
spec.loader.exec_module(F)
snap = json.loads(Path(snap_p).read_text())
ch = {c['file']: c for c in json.loads((E.WORK / 'razgovori_marked.json').read_text())}
out = Path(out_dir)
out.mkdir(parents=True, exist_ok=True)


def cut(al, a, b):
    s = (al['end'][a - 1] + al['start'][a]) / 2 if a > 0 else max(al['start'][0] - 0.03, 0)
    e = (al['end'][b - 1] + al['start'][b]) / 2 if b < len(al['chars']) else al['end'][-1] + 0.05
    return int(round(s * R)), int(round(e * R))


def rms(x):
    return math.sqrt(sum(v * v for v in x) / max(len(x), 1))


by_chunk = {}
for n, (k, o, new, note) in enumerate(F.FIXES, 1):
    by_chunk.setdefault(k, []).append((n, F.in_audio(k, o), new, note))

k_api = None if dry else E.key()
budget = {'reserve': 500, 'spent': 0}
listing = []
for key, fixes in by_chunk.items():
    f, bi, ci = key.split('|')
    bl = ch[f]['blocks'][int(bi)]
    cur = snap[key]
    target = E.chunks_of(bl)[int(ci)][0]
    al = json.loads((E.CACHE / f'{cache_key(bl, cur)}.json').read_text())
    pcm = array.array('h', (E.CACHE / f'{cache_key(bl, cur)}.pcm').read_bytes())
    assert ''.join(al['chars']) == cur, key
    fixes.sort(key=lambda x: cur.index(x[1]))
    for n, old, new, note in fixes:
        assert cur.count(old) == 1, (key, old)
        i = cur.index(old)
        if dry:
            budget['spent'] += len(new)
            cur = cur[:i] + new + cur[i + len(old):]
            continue
        fp, fal = E.synth(k_api, bl['speaker'], new, budget, cur[:i], cur[i + len(old):], bl['kind'])
        fp = array.array('h', fp)
        a0, b0 = cut(al, i, i + len(old))
        a1, b1 = cut(fal, 0, len(new))
        b0, b1 = min(b0, len(pcm)), min(b1, len(fp))   # краят на парчето
        piece = fp[a1:b1]
        g = rms(pcm[a0:b0]) / max(rms(piece), 1)
        piece = array.array('h', (max(-32768, min(32767, int(v * g))) for v in piece))
        x = min(int(0.015 * R), len(piece) // 2, (b0 - a0) // 2)
        for j in range(x):
            piece[j] = int(piece[j] * j / x + pcm[a0 + j] * (1 - j / x))
            piece[-1 - j] = int(piece[-1 - j] * j / x + pcm[b0 - 1 - j] * (1 - j / x))
        d = (len(piece) - (b0 - a0)) / R
        off = a0 / R - a1 / R
        mp3(pcm[max(a0 - 5 * R, 0):b0 + 3 * R].tobytes(), out / f'{n:02d}_staro.mp3')
        pcm = pcm[:a0] + piece + pcm[b0:]
        mp3(pcm[max(a0 - 5 * R, 0):a0 + len(piece) + 3 * R].tobytes(), out / f'{n:02d}_novo.mp3')
        al = {'chars': list(cur[:i] + new + cur[i + len(old):]),
              'start': al['start'][:i] + [t + off for t in fal['start']] + [t + d for t in al['start'][i + len(old):]],
              'end': al['end'][:i] + [t + off for t in fal['end']] + [t + d for t in al['end'][i + len(old):]]}
        cur = cur[:i] + new + cur[i + len(old):]
        ctx = cur[max(0, i - 60):i + len(new) + 40]
        listing.append({'n': n, 'chunk': key, 'speaker': bl['speaker'], 'note': note, 'ctx': ctx})
        print(f'{n:02d} {key} {note}', flush=True)
    assert cur == target, f'{key}: правилата дават друг текст'
    if not dry:
        h = cache_key(bl, cur)
        (E.CACHE / f'{h}.pcm').write_bytes(pcm.tobytes())
        (E.CACHE / f'{h}.json').write_text(json.dumps(al, ensure_ascii=False))
if dry:
    print(f'--dry: {len(F.FIXES)} израза, ~{budget["spent"]} знака')
else:
    (out / 'spisak.json').write_text(json.dumps(sorted(listing, key=lambda x: x['n']), ensure_ascii=False, indent=1))
    print(f'изпратени знаци: {budget["spent"]}; кредити: {E.remaining(k_api)}')
