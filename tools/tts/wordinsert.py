#!/usr/bin/env python3
"""Една дума от НОВО генериран запис в ОДОБРЕН запис (12.10.2026).

    python3 wordinsert.py <одобрен кеш> <нов кеш> <думата в одобрения> <думата в новия>

Новият кеш е генериран с поправената дума; резултатът ляга под НЕГОВИЯ
ключ, но е одобреният звук с подменена само тази дума — останалото
изречение не мърда. Шевовете са в средата на паузите около думата."""
import array
import json
import sys

import eleven as E

appr, fresh, w1, w2 = sys.argv[1:5]
R = E.RATE


def smp(t):
    return int(round(t * R)) * 2


def load(h):
    return json.loads((E.CACHE / f'{h}.json').read_text()), (E.CACHE / f'{h}.pcm').read_bytes()


aal, ap = load(appr)
fal, fp = load(fresh)
at, ft = ''.join(aal['chars']), ''.join(fal['chars'])
assert at.count(w1) == 1 and ft.count(w2) == 1
ai, fi = at.index(w1), ft.index(w2)
assert at[:ai] == ft[:fi] and at[ai + len(w1):] == ft[fi + len(w2):], 'разликата не е само в думата'


def span(al, i, n):
    a = (al['end'][i - 1] + al['start'][i]) / 2 if i else 0.0
    j = i + n
    b = (al['end'][j - 1] + al['start'][j]) / 2 if j < len(al['chars']) else al['end'][-1]
    return a, b


aa, ab = span(aal, ai, len(w1))
fa, fb = span(fal, fi, len(w2))
F = int(0.004 * R)


def fade(b, inn):
    x = array.array('h', b)
    for q in range(min(F, len(x))):
        g = q / F
        if inn:
            x[q] = int(x[q] * g)
        else:
            x[-1 - q] = int(x[-1 - q] * g)
    return x.tobytes()


pcm = fade(ap[:smp(aa)], False) + fade(fade(fp[smp(fa):smp(fb)], True), False) + fade(ap[smp(ab):], True)
d = (fb - fa) - (ab - aa)
j = ai + len(w1)
al = {'chars': list(ft),
      'start': aal['start'][:ai] + [t - fa + aa for t in fal['start'][fi:fi + len(w2)]] + [t + d for t in aal['start'][j:]],
      'end': aal['end'][:ai] + [t - fa + aa for t in fal['end'][fi:fi + len(w2)]] + [t + d for t in aal['end'][j:]]}
assert len(al['start']) == len(ft)
(E.CACHE / f'{fresh}.pcm').write_bytes(pcm)
(E.CACHE / f'{fresh}.json').write_text(json.dumps(al, ensure_ascii=False))
print('ok', round(d, 3))
