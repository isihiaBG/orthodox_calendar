#!/usr/bin/env python3
"""Кратък ИЗРАЗ от ново генериране в одобрен запис (13.10.2026).

    python3 phrasesplice.py <беседа> <блок> <парче> <стар израз> <нов израз> <име>

Генерира се САМО изразът (текстът отпред и отзад се праща за интонацията,
не се плаща), изрязва се в средата на паузите около него и заменя стария с
15 ms преливане и изравнена сила. Одобреният текст е от снимката
work/snap_20261013.json; резултатът ляга под ключа на парчето С НОВИЯ
израз. За слушане — review/izraz_<име>.mp3. Като yearsplice.py, но общо."""
import array, json, math, sys
import eleven as E
from splice_many import cache_key, mp3

chap, bi, ci, y_old, y_new, name = sys.argv[1:7]
R = E.RATE
ch = {c['file']: c for c in json.loads((E.WORK / 'razgovori_marked.json').read_text())}
bl = ch[chap]['blocks'][int(bi)]
cur_txt = json.load(open(E.WORK / 'snap_20261013.json'))[f'{chap}|{bi}|{ci}']
al = json.loads((E.CACHE / f'{cache_key(bl, cur_txt)}.json').read_text())
pcm = array.array('h', (E.CACHE / f'{cache_key(bl, cur_txt)}.pcm').read_bytes())
cur = ''.join(al['chars'])
assert cur == cur_txt and cur.count(y_old) == 1
i = cur.index(y_old)
new = cur[:i] + y_new + cur[i + len(y_old):]
import os
if not os.environ.get('MEZHDINNO'):   # междинна стъпка при няколко израза в едно парче
    assert new == E.chunks_of(bl)[int(ci)][0], 'новият текст на парчето не съвпада с правилата'
fp, fal = E.synth(E.key(), bl['speaker'], y_new, {'reserve': 20, 'spent': 0},
                  cur[:i], cur[i + len(y_old):], bl['kind'])
fp = array.array('h', fp)


def cut(al, a, b):
    s = (al['end'][a - 1] + al['start'][a]) / 2 if a > 0 else max(al['start'][0] - 0.03, 0)
    e = (al['end'][b - 1] + al['start'][b]) / 2 if b < len(al['chars']) else al['end'][-1] + 0.05
    return int(round(s * R)), int(round(e * R))


a0, b0 = cut(al, i, i + len(y_old))
a1, b1 = cut(fal, 0, len(y_new))
piece = fp[a1:b1]
rms = lambda x: math.sqrt(sum(v * v for v in x) / max(len(x), 1))
g = rms(pcm[a0:b0]) / max(rms(piece), 1)
piece = array.array('h', (max(-32768, min(32767, int(v * g))) for v in piece))
x = int(0.015 * R)
for k in range(x):
    piece[k] = int(piece[k] * k / x + pcm[a0 + k] * (1 - k / x))
    piece[-1 - k] = int(piece[-1 - k] * k / x + pcm[b0 - 1 - k] * (1 - k / x))
out = pcm[:a0] + piece + pcm[b0:]
d = (len(piece) - (b0 - a0)) / R
off = a0 / R - a1 / R
nal = {'chars': list(new),
       'start': al['start'][:i] + [t + off for t in fal['start']] + [t + d for t in al['start'][i + len(y_old):]],
       'end': al['end'][:i] + [t + off for t in fal['end']] + [t + d for t in al['end'][i + len(y_old):]]}
h2 = cache_key(bl, new)
(E.CACHE / f'{h2}.pcm').write_bytes(out.tobytes())
(E.CACHE / f'{h2}.json').write_text(json.dumps(nal, ensure_ascii=False))
mp3(out[max(a0 - 6 * R, 0):b0 + int(d * R) + 4 * R].tobytes(), E.HERE / 'review' / f'izraz_{name}.mp3')
mp3(pcm[max(a0 - 6 * R, 0):b0 + 4 * R].tobytes(), E.HERE / 'review' / f'izraz_{name}_staro.mp3')
print(name, '→', h2, f'усилване {g:.2f}', ''.join(fal['chars']))
