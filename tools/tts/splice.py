#!/usr/bin/env python3
"""Поправка САМО на едно изречение в одобрено парче (11.10.2026).

Поправка в думата иначе генерира наново ЦЯЛОТО парче (~500 знака) и гласът
чете различно и съседните изречения. Тук се генерира само изречението (със
съседния текст за интонацията), а одобреният звук се реже по границите от
подравняването и изречението се вмъква на мястото на старото.

    python3 splice.py razgovori c13 'неурее' 25abf8ee79b32d3dd3ed

Резултатът ляга в кеша под ключа на НОВИЯ текст на парчето, тъй че
`eleven.py razgovori c13` после го взима оттам, без заявка. Отделно:
review/splice_<беседа>.mp3 — само парчето, за слушане преди качване.

⚠ Шевът: паузата между изреченията остава колкото е била в одобрения звук.
Не се ли хареса — изтрий новия кеш файл (името се изписва) и всичко е
каквото беше.
"""
import hashlib
import json
import subprocess
import sys

import eleven as E

LEAD = 0.04      # секунди преди първия знак на новото изречение (за атаката)


def main():
    book, chap, needle, old = sys.argv[1:5]
    ch = next(c for c in json.loads((E.WORK / f'{book}_marked.json').read_text())
              if c['file'] == chap)
    for bl in ch['blocks']:
        parts = E.chunks_of(bl)
        for ci, (text, base, items) in enumerate(parts):
            for si, (a, b, _, _) in enumerate(items):
                if needle in text[a - base:b - base]:
                    return splice(book, chap, bl, parts, ci, si, old)
    sys.exit('няма такова изречение')


def splice(book, chap, bl, parts, ci, si, old):
    text, base, items = parts[ci]
    a, b = items[si][0] - base, items[si][1] - base
    sent = text[a:b]
    oal = json.loads((E.CACHE / f'{old}.json').read_text())
    opcm = (E.CACHE / f'{old}.pcm').read_bytes()
    ot = ''.join(oal['chars'])
    # Границите в стария текст се намират по НАЧАЛОТО и КРАЯ на съседите,
    # които не са пипани.
    before, after = text[:a], text[b:]
    assert ot.startswith(before) and ot.endswith(after), 'съседите са се сменили'
    oa, ob = len(before), len(ot) - len(after)
    print('старо:', repr(ot[oa:ob]))
    print('ново: ', repr(sent))
    prev_t = ' '.join(p[0] for p in parts[:ci]) + ' ' + text[:a]
    next_t = text[b:] + ' ' + ' '.join(p[0] for p in parts[ci + 1:])
    k = E.key()
    budget = {'reserve': 2000, 'spent': 0}
    npcm, nal = E.synth(k, bl['speaker'], sent, budget, prev_t.strip(), next_t.strip(), bl['kind'])
    print(f'изпратени знаци: {budget["spent"]}')

    R = E.RATE
    def smp(sec): return int(round(sec * R)) * 2
    # Стария звук: до края на последния знак преди изречението + паузата до
    # началото му (такава, каквато е била); след него — от края на
    # изречението нататък.
    lead_old = oal['start'][oa] - (oal['end'][oa - 1] if oa else 0.0)
    cut_a = oal['end'][oa - 1] if oa else 0.0
    cut_b = oal['end'][ob - 1] if ob < len(ot) else len(opcm) / 2 / R
    n0 = max(nal['start'][0] - LEAD, 0.0)
    head = opcm[:smp(cut_a)] + E.silence(max(lead_old - LEAD, 0.0))
    if ob < len(ot):
        n1 = nal['end'][-1]
        mid = npcm[smp(n0):smp(n1)]
        tail = opcm[smp(cut_b):]
    else:                       # последното изречение — опашката е новата
        mid, tail = npcm[smp(n0):], b''
    pcm = head + mid + tail
    t_mid = len(head) / 2 / R - (n0 - 0)
    shift_after = (len(head) + len(mid)) / 2 / R - cut_b
    starts = oal['start'][:oa] + [t + t_mid for t in nal['start']] + \
        [t + shift_after for t in oal['start'][ob:]]
    ends = oal['end'][:oa] + [t + t_mid for t in nal['end']] + \
        [t + shift_after for t in oal['end'][ob:]]
    al = {'chars': list(text), 'start': starts, 'end': ends}
    assert len(starts) == len(text)

    s = E.settings(bl['speaker'], bl['kind'], text)
    h = hashlib.sha1(json.dumps([E.VOICES[bl['speaker']]['voice_id'], E.MODEL, s, E.SEED, text],
                                ensure_ascii=False).encode()).hexdigest()[:20]
    (E.CACHE / f'{h}.pcm').write_bytes(pcm)
    (E.CACHE / f'{h}.json').write_text(json.dumps(al, ensure_ascii=False))
    print(f'кеш: {h} (изтрий го, ако шевът се чува)')
    out = E.HERE / 'review' / f'splice_{chap}.mp3'
    subprocess.run(['ffmpeg', '-v', 'error', '-y', '-f', 's16le', '-ar', str(R), '-ac', '1',
                    '-i', '-', '-c:a', 'libmp3lame', '-b:a', '64k', str(out)], input=pcm, check=True)
    old_mp3 = E.HERE / 'review' / f'splice_{chap}_staro.mp3'
    subprocess.run(['ffmpeg', '-v', 'error', '-y', '-f', 's16le', '-ar', str(R), '-ac', '1',
                    '-i', '-', '-c:a', 'libmp3lame', '-b:a', '64k', str(old_mp3)], input=opcm, check=True)
    print(f'за слушане: {out}  (старото: {old_mp3.name})')


if __name__ == '__main__':
    main()
