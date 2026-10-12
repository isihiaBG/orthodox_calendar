#!/usr/bin/env python3
"""Поправки по изречение — наведнъж, за всички променени парчета (12.10.2026).

Като splice.py, но:
  • сам намира кое е променено: сравнява парчетата с една снимка отпреди
    поправките (json: „беседа|абзац|парче“ → текст за гласа);
  • старият кеш е онзи с ключа на СТАРИЯ текст на парчето;
  • в едно парче може да има няколко променени изречения — вмъкват се
    едно по едно, отляво надясно, всяко в звука на предишното.

    python3 splice_many.py razgovori <снимка.json> [беседа …]

Резултатът ляга в кеша под ключа на НОВИЯ текст на парчето; `eleven.py`
после го взима без заявка. За слушане: review/popravki/ (старо и ново на
всяко изречение) и review/popravki/index.json.
"""
import difflib
import hashlib
import json
import subprocess
import sys

import eleven as E
from splice import LEAD

R = E.RATE
OUT = E.HERE / 'review' / 'popravki'


def cache_key(bl, text):
    s = E.settings(bl['speaker'], bl['kind'], text)
    return hashlib.sha1(json.dumps([E.VOICES[bl['speaker']]['voice_id'], E.MODEL, s, E.SEED, text],
                                   ensure_ascii=False).encode()).hexdigest()[:20]


def smp(sec):
    return int(round(sec * R)) * 2


def map_pos(cur, new, p):
    """Позиция в новия текст → в текущия (по еднаквите участъци)."""
    if p >= len(new):
        return len(cur)
    for tag, i1, i2, j1, j2 in difflib.SequenceMatcher(None, cur, new, autojunk=False).get_opcodes():
        if tag == 'equal' and j1 <= p <= j2:
            return i1 + (p - j1)
    raise ValueError(f'границата {p} не е в непроменен участък')


def mp3(pcm, path):
    subprocess.run(['ffmpeg', '-v', 'error', '-y', '-f', 's16le', '-ar', str(R), '-ac', '1',
                    '-i', '-', '-c:a', 'libmp3lame', '-b:a', '64k', str(path)], input=pcm, check=True)


def clip(pcm, al, a, b):
    """Изречението [a, b) с малко отпред и отзад — за слушане."""
    t0 = max(al['start'][a] - 1.2, 0.0)
    t1 = min(al['end'][b - 1] + 0.8, len(pcm) / 2 / R)
    return pcm[smp(t0):smp(t1)]


def splice_one(cur, cpcm, cal, sent, oa, ob, bl, prev_t, next_t, budget):
    """Заменя cur[oa:ob] със sent → (текст, pcm, подравняване)."""
    k = E.key()
    npcm, nal = E.synth(k, bl['speaker'], sent, budget, prev_t.strip(), next_t.strip(), bl['kind'])
    lead_old = cal['start'][oa] - (cal['end'][oa - 1] if oa else 0.0)
    cut_a = cal['end'][oa - 1] if oa else 0.0
    cut_b = cal['end'][ob - 1] if ob < len(cur) else len(cpcm) / 2 / R
    n0 = max(nal['start'][0] - LEAD, 0.0)
    head = cpcm[:smp(cut_a)] + E.silence(max(lead_old - LEAD, 0.0))
    if ob < len(cur):
        mid, tail = npcm[smp(n0):smp(nal['end'][-1])], cpcm[smp(cut_b):]
    else:
        mid, tail = npcm[smp(n0):], b''
    pcm = head + mid + tail
    t_mid = len(head) / 2 / R - n0
    shift = (len(head) + len(mid)) / 2 / R - cut_b
    text = cur[:oa] + sent + cur[ob:]
    al = {'chars': list(text),
          'start': cal['start'][:oa] + [t + t_mid for t in nal['start']] + [t + shift for t in cal['start'][ob:]],
          'end': cal['end'][:oa] + [t + t_mid for t in nal['end']] + [t + shift for t in cal['end'][ob:]]}
    assert len(al['start']) == len(text)
    return text, pcm, al


def main():
    dry = '--dry' in sys.argv
    args = [x for x in sys.argv[1:] if x != '--dry']
    book, snap = args[0], json.loads(open(args[1]).read())
    only = set(args[2:])
    total = 0
    chapters = {c['file']: c for c in json.loads((E.WORK / f'{book}_marked.json').read_text())}
    OUT.mkdir(exist_ok=True)
    prev = json.loads((OUT / 'index.json').read_text()) if (OUT / 'index.json').exists() else []
    index = []
    budget = {'reserve': 150, 'spent': 0}
    print('кредити преди:', E.remaining(E.key()))
    for name, old in snap.items():
        chap, bi, ci = name.split('|')
        if only and chap not in only:
            continue
        bl = chapters[chap]['blocks'][int(bi)]
        parts = E.chunks_of(bl)
        new, base, items = parts[int(ci)]
        if new == old:
            continue
        h_old = cache_key(bl, old)
        if not (E.CACHE / f'{h_old}.pcm').exists():
            print(f'⚠ {name}: няма стария звук ({h_old}) — пропуснато')
            continue
        h_new = cache_key(bl, new)
        if (E.CACHE / f'{h_new}.pcm').exists():
            print(f'{name}: вече е направено ({h_new})')
            continue
        cal = json.loads((E.CACHE / f'{h_old}.json').read_text())
        cpcm = (E.CACHE / f'{h_old}.pcm').read_bytes()
        cur = ''.join(cal['chars'])
        assert cur == old, f'{name}: кешът не е стария текст'
        for a, b, _, _ in items:
            a, b = a - base, b - base
            assert cur[:a] == new[:a]
            ob = map_pos(cur, new, b)
            if cur[a:ob] == new[a:b]:
                continue
            prev_t = ' '.join(p[0] for p in parts[:int(ci)]) + ' ' + new[:a]
            next_t = new[b:] + ' ' + ' '.join(p[0] for p in parts[int(ci) + 1:])
            if dry:
                total += b - a
                print(f'{name}: {b - a} зн. — {new[a:b][:70]}')
                cur = cur[:a] + new[a:b] + cur[ob:]
                continue
            old_clip = clip(cpcm, cal, a, ob)
            old_txt = cur[a:ob]
            print(f'{name}\n   старо: {cur[a:ob]}\n   ново:  {new[a:b]}')
            cur, cpcm, cal = splice_one(cur, cpcm, cal, new[a:b], a, ob, bl, prev_t, next_t, budget)
            n = len(prev) + len(index) + 1
            mp3(old_clip, OUT / f'{n:02d}_staro.mp3')
            mp3(clip(cpcm, cal, a, b), OUT / f'{n:02d}_novo.mp3')
            index.append({'n': n, 'chunk': name, 'speaker': bl['speaker'],
                          'old': old_txt, 'new': new[a:b]})
        assert cur == new, f'{name}: след вмъкванията текстът не съвпада'
        if dry:
            continue
        (E.CACHE / f'{h_new}.pcm').write_bytes(cpcm)
        (E.CACHE / f'{h_new}.json').write_text(json.dumps(cal, ensure_ascii=False))
        print(f'   кеш: {h_new}   (изпратени досега: {budget["spent"]})')
    if dry:
        print('общо знаци:', total, '; кредити сега:', E.remaining(E.key()))
        return
    (OUT / 'index.json').write_text(json.dumps(prev + index, ensure_ascii=False, indent=1))
    print('изпратени знаци:', budget['spent'], '; кредити след:', E.remaining(E.key()))


if __name__ == '__main__':
    main()
