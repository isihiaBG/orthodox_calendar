#!/usr/bin/env python3
"""Израз от пауза до пауза наново в одобрения запис (13.11.2026).

    python3 redo_spans.py <поправки.py> <папка за слушане> [--dry]

phrasefix.py сменя само думата и реже в средата на течащата реч — там,
където гласът не спира, шевът се чува (ехо, удвоен звук, „чупене“; автора,
13.11.2026). Тук се генерира наново целият израз между две истински паузи
(тишина ≥ 120 ms) и се вмъква в тишината, без преливане върху реч.

<поправки.py> дава SNAP (json „беседа|блок|парче“ → текстът на записа сега)
и JOBS = [(етикет, парче, израз в новия текст, израз в записа или None,
{'speed': …, 'keep': True})]. 'keep' — вариант за избор: само за слушане,
пази се в work/<етикет>.pcm, не ляга в кеша. Ново темпо — само за израза."""
import array
import importlib.util
import json
import math
import shutil
import sys
from pathlib import Path

import eleven as E
from splice_many import cache_key, mp3

R = E.RATE
W = int(.01 * R)
fixes_p, out_dir = sys.argv[1:3]
dry = '--dry' in sys.argv
spec = importlib.util.spec_from_file_location('fixes', fixes_p)
F = importlib.util.module_from_spec(spec)
spec.loader.exec_module(F)
snap = json.loads(Path(F.SNAP).read_text())
ch = {c['file']: c for c in json.loads((E.WORK / 'razgovori_marked.json').read_text())}
out = Path(out_dir)
out.mkdir(parents=True, exist_ok=True)


def rms(x):
    return math.sqrt(sum(v * v for v in x) / max(len(x), 1))


def silences(x, need=12, thr=40):
    e = [rms(x[t:t + W]) for t in range(0, len(x) - W, W)]
    res, s = [], None
    for n, r in enumerate(e + [1e9]):
        if r < thr and s is None:
            s = n
        elif r >= thr and s is not None:
            if n - s >= need:
                res.append((s * W, n * W))
            s = None
    return res


def voice_of(x):
    """Гласът без тишината отпред и отзад."""
    s = silences(x, need=3)
    a = s[0][1] if s and s[0][0] == 0 else 0
    b = s[-1][0] if s and s[-1][1] >= len(x) - W else len(x)
    return a, b


def synth(k, bl, text, budget, prev, nxt, speed):
    if speed is None:
        return E.synth(k, bl['speaker'], text, budget, prev, nxt, bl['kind'])
    orig = E.settings
    E.settings = lambda *a, **kw: {**orig(*a, **kw), 'speed': speed}
    try:
        return E.synth(k, bl['speaker'], text, budget, prev, nxt, bl['kind'])
    finally:
        E.settings = orig


by_chunk = {}
for job in F.JOBS:
    by_chunk.setdefault(job[1], []).append(job)
k_api = None if dry else E.key()
budget = {'reserve': 500, 'spent': 0}
listing = []
for key, jobs in by_chunk.items():
    f, bi, ci = key.split('|')
    bl = ch[f]['blocks'][int(bi)]
    cur = snap[key]
    target = E.chunks_of(bl)[int(ci)][0]
    h0 = cache_key(bl, cur)
    al = json.loads((E.CACHE / f'{h0}.json').read_text())
    pcm = array.array('h', (E.CACHE / f'{h0}.pcm').read_bytes())
    assert ''.join(al['chars']) == cur, key
    jobs.sort(key=lambda j: cur.index(j[3] or j[2]))
    for lab, _, new, old, opt in jobs:
        old = old or new
        assert cur.count(old) == 1, (key, old)
        i = cur.index(old)
        j = i + len(old)
        sil = silences(pcm)
        ta, tb = al['start'][i] * R, al['end'][j - 1] * R
        pre = [s for s in sil if s[0] < ta + .15 * R]
        post = [s for s in sil if s[1] > tb - .05 * R]
        v0 = max(pre, key=lambda s: s[0])[1] if pre else voice_of(pcm)[0]
        v1 = min(post, key=lambda s: s[0])[0] if post else voice_of(pcm)[1]
        print(f'{lab} {key}: {v0 / R:.2f}–{v1 / R:.2f} s, {len(new)} зн. «{new}»', flush=True)
        if dry:
            budget['spent'] += len(new)
            if not opt.get('keep'):
                cur = cur[:i] + new + cur[j:]
            continue
        fp, fal = synth(k_api, bl, new, budget, cur[:i], cur[j:], opt.get('speed'))
        fp = array.array('h', fp)
        n0, n1 = voice_of(fp)
        piece = fp[n0:n1]
        g = rms(pcm[v0:v1]) / max(rms(piece), 1)
        piece = array.array('h', (max(-32768, min(32767, int(v * g))) for v in piece))
        x = int(.005 * R)
        for q in range(x):
            piece[q] = int(piece[q] * q / x)
            piece[-1 - q] = int(piece[-1 - q] * q / x)
        res = pcm[:v0] + piece + pcm[v1:]
        d = (len(piece) - (v1 - v0)) / R
        off = (v0 - n0) / R
        al2 = {'chars': list(cur[:i] + new + cur[j:]),
               'start': al['start'][:i] + [t + off for t in fal['start']] + [t + d for t in al['start'][j:]],
               'end': al['end'][:i] + [t + off for t in fal['end']] + [t + d for t in al['end'][j:]]}
        mp3(res[max(v0 - 4 * R, 0):v0 + len(piece) + 2 * R].tobytes(), out / f'{lab}_novo.mp3')
        mp3(pcm[max(v0 - 4 * R, 0):v1 + 2 * R].tobytes(), out / f'{lab}_predi.mp3')
        listing.append({'lab': lab, 'chunk': key, 'text': new, 'd': round(d, 2)})
        if opt.get('keep'):
            (E.WORK / f'{lab}.pcm').write_bytes(res.tobytes())
            (E.WORK / f'{lab}.json').write_text(json.dumps(al2, ensure_ascii=False))
            continue
        pcm, al, cur = res, al2, cur[:i] + new + cur[j:]
    assert cur == target, f'{key}: правилата дават друг текст\n{cur}\n{target}'
    if not dry:
        h = cache_key(bl, cur)
        for ext in ('pcm', 'json'):
            bak = E.WORK / f'redo_{h0}.{ext}'
            if h == h0 and not bak.exists():
                shutil.copy(E.CACHE / f'{h0}.{ext}', bak)
        (E.CACHE / f'{h}.pcm').write_bytes(pcm.tobytes())
        (E.CACHE / f'{h}.json').write_text(json.dumps(al, ensure_ascii=False))
if dry:
    print(f'--dry: {len(F.JOBS)} израза, ~{budget["spent"]} знака')
else:
    (out / 'spisak.json').write_text(json.dumps(listing, ensure_ascii=False, indent=1))
    print(f'изпратени знаци: {budget["spent"]}; кредити: {E.remaining(k_api)}')
