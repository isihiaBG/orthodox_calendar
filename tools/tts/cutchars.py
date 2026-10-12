#!/usr/bin/env python3
"""Изрязва знаци от ОДОБРЕН запис — без кредити (13.10.2026).

    python3 cutchars.py <беседа> <блок> <парче> <снимка.json> <стар низ> <нов низ>

Старият низ трябва да е еднозначен в парчето, а новият — същият без
едно парче знаци („…възде́йствието на Бо́…“ → „…възде́йствие на Бо́…“). Звукът се реже
по разбивката по знаци, с 8 ms преливане; резултатът ляга под ключа на
НОВИЯ текст на парчето, за да го вземе `eleven.py` без заявка."""
import array, json, sys
import eleven as E
from splice_many import cache_key, mp3, clip

chap, bi, ci, snapf, w_old, w_new = sys.argv[1:7]
R = E.RATE
snap = json.load(open(snapf))
ch = {c['file']: c for c in json.loads((E.WORK / 'razgovori_marked.json').read_text())}
bl = ch[chap]['blocks'][int(bi)]
new = E.chunks_of(bl)[int(ci)][0]
old = snap[f'{chap}|{bi}|{ci}']
h_old, h_new = cache_key(bl, old), cache_key(bl, new)
al = json.loads((E.CACHE / f'{h_old}.json').read_text())
pcm = array.array('h', (E.CACHE / f'{h_old}.pcm').read_bytes())
cur = ''.join(al['chars'])
assert cur == old and cur.count(w_old) == 1, 'старият низ не е еднозначен'
pre = 0                                     # общо начало и край на двата низа
while pre < len(w_new) and w_old[pre] == w_new[pre]:
    pre += 1
suf = len(w_new) - pre
assert w_old[len(w_old) - suf:] == w_new[pre:], 'новият низ не е старият без парче'
n0 = cur.index(w_old)
i = n0 + pre                                # първият изрязан знак
j = n0 + len(w_old) - suf                   # първият запазен след тях
assert cur[:i] + cur[j:] == new, 'разликата не е само в изрязаното'
a, b = int(round(al['start'][i] * R)), int(round(al['start'][j] * R))
x = int(0.008 * R)
head, tail = pcm[:a], pcm[b:]
for k in range(x):                          # преливане
    g = k / x
    head[a - x + k] = int(head[a - x + k] * (1 - g) + tail[k] * g)
out = head + tail[x:]
d = (b - a + x) / R
nal = {'chars': al['chars'][:i] + al['chars'][j:],
       'start': al['start'][:i] + [t - d for t in al['start'][j:]],
       'end': al['end'][:i] + [t - d for t in al['end'][j:]]}
(E.CACHE / f'{h_new}.pcm').write_bytes(out.tobytes())
(E.CACHE / f'{h_new}.json').write_text(json.dumps(nal, ensure_ascii=False))
p = E.HERE / 'review' / 'popravki'
p.mkdir(exist_ok=True)
n = cur.index(w_old)
mp3(clip(pcm.tobytes(), al, max(n - 60, 0), min(j + 20, len(cur))), p / f'cut_{chap}_staro.mp3')
mp3(clip(out.tobytes(), nal, max(n - 60, 0), min(i + 20, len(new))), p / f'cut_{chap}_novo.mp3')
print('готово:', h_old, '→', h_new, f'изрязани {d * 1000:.0f} ms')
