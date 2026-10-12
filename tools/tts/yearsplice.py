#!/usr/bin/env python3
"""Само ГОДИНАТА от кратко генерирана фраза в одобрен запис (13.10.2026).

    python3 yearsplice.py <беседа> <блок> <парче> <стар израз> <нов израз> <име>

Генерира се само „през <нов израз> година“ (с текста отпред и отзад за
интонацията — той не се плаща), изразът се изрязва в средата на паузите
около него и се слага на мястото на стария. Силата се изравнява.
Резултатът ляга под ключа на парчето С НОВИЯ израз (INSERT_FIX го прави
такъв), плюс review/godina_<име>.mp3 за слушане."""
import array, json, math, sys
import eleven as E
from splice_many import cache_key, mp3

chap, bi, ci, y_old, y_new, name = sys.argv[1:7]
R = E.RATE
ch = {c['file']: c for c in json.loads((E.WORK / 'razgovori_marked.json').read_text())}
bl = ch[chap]['blocks'][int(bi)]
cur_txt = E.chunks_of(bl)[int(ci)][0]
h = cache_key(bl, cur_txt)
al = json.loads((E.CACHE / f'{h}.json').read_text())
pcm = array.array('h', (E.CACHE / f'{h}.pcm').read_bytes())
cur = ''.join(al['chars'])
assert cur == cur_txt and cur.count(y_old) == 1
i = cur.index(y_old)
phrase = 'през ' + y_new + ' годи' + E.A + 'на'
prev, nxt = cur[:cur.rindex('през', 0, i)], cur[i + len(y_old) + len(' годи́на'):]
fp, fal = E.synth(E.key(), bl['speaker'], phrase, {'reserve': 20, 'spent': 0}, prev, nxt, bl['kind'])
fp = array.array('h', fp)
ft = ''.join(fal['chars'])
fi = ft.index(y_new)


def cut(al, a, b):
    """Средата на паузите около знаците [a, b)."""
    s = (al['end'][a - 1] + al['start'][a]) / 2
    e = (al['end'][b - 1] + al['start'][b]) / 2
    return int(round(s * R)), int(round(e * R))


a0, b0 = cut(al, i, i + len(y_old))
a1, b1 = cut(fal, fi, fi + len(y_new))
piece = fp[a1:b1]
rms = lambda x: math.sqrt(sum(v * v for v in x) / max(len(x), 1))
g = rms(pcm[a0:b0]) / max(rms(piece), 1)
piece = array.array('h', (max(-32768, min(32767, int(v * g))) for v in piece))
x = int(0.010 * R)
for k in range(x):                      # преливане в двата шева
    piece[k] = int(piece[k] * k / x + pcm[a0 + k] * (1 - k / x))
    piece[-1 - k] = int(piece[-1 - k] * k / x + pcm[b0 - 1 - k] * (1 - k / x))
out = pcm[:a0] + piece + pcm[b0:]
d = (len(piece) - (b0 - a0)) / R
new = cur[:i] + y_new + cur[i + len(y_old):]
# Знаците на израза — по новия запис, отместени към мястото му.
off = a0 / R - a1 / R
nal = {'chars': list(new),
       'start': al['start'][:i] + [t + off for t in fal['start'][fi:fi + len(y_new)]]
                + [t + d for t in al['start'][i + len(y_old):]],
       'end': al['end'][:i] + [t + off for t in fal['end'][fi:fi + len(y_new)]]
              + [t + d for t in al['end'][i + len(y_old):]]}
h2 = cache_key(bl, new)
(E.CACHE / f'{h2}.pcm').write_bytes(out.tobytes())
(E.CACHE / f'{h2}.json').write_text(json.dumps(nal, ensure_ascii=False))
s0 = max(a0 - 6 * R, 0)
mp3(out[s0:b0 + int(d * R) + 3 * R].tobytes(), E.HERE / 'review' / f'godina_{name}.mp3')
print(name, '→', h2, f'усилване {g:.2f}', f'фраза: {ft}')
