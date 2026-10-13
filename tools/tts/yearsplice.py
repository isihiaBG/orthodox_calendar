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
# По избор: цялата фраза за генериране (тогава БЕЗ контекст — отделно
# изречение, както го предложи авторът: „Хиля́да … годи́на.“).
alone = sys.argv[7] if len(sys.argv) > 7 else None
# „Прецизният“ изрез (от края на предишната дума + тишина) е само за цялата
# година; за част от нея — шев по средата между думите с преливане.
precise = bool(alone) and y_new.startswith('хиля')
R = E.RATE
ch = {c['file']: c for c in json.loads((E.WORK / 'razgovori_marked.json').read_text())}
bl = ch[chap]['blocks'][int(bi)]
# Одобреният текст — от снимката отпреди поправките (след INSERT_FIX
# chunks_of вече дава новия).
cur_txt = json.load(open(E.WORK / 'snap_20261013.json'))[f'{chap}|{bi}|{ci}']
h = cache_key(bl, cur_txt)
al = json.loads((E.CACHE / f'{h}.json').read_text())
pcm = array.array('h', (E.CACHE / f'{h}.pcm').read_bytes())
cur = ''.join(al['chars'])
assert cur == cur_txt and cur.count(y_old) == 1
i = cur.index(y_old)
phrase = alone or 'през ' + y_new + ' годи' + E.A + 'на'
prev, nxt = cur[:cur.rindex('през', 0, i)], cur[i + len(y_old) + len(' годи́на'):]
if not alone and not y_new.startswith('хиля'):   # само част от годината —
    # фразата е генерирана с цялата година (вариант C); контекстът — същият.
    # ⚠ Достроява се ЦЯЛАТА година — иначе текстът се разминава с кеша на C и
    # се генерира наново (струваше ~25 кредита на 13.10.2026).
    full = y_new
    if not full.startswith('де' + E.A + 'вестотин'):
        full = 'де' + E.A + 'вестотин ' + full
    phrase = 'през хиля' + E.A + 'да ' + full + ' годи' + E.A + 'на'
    import hashlib
    _s = E.settings(bl['speaker'], bl['kind'], phrase)
    _h = hashlib.sha1(json.dumps([E.VOICES[bl['speaker']]['voice_id'], E.MODEL, _s, E.SEED, phrase],
                                 ensure_ascii=False).encode()).hexdigest()[:20]
    assert (E.CACHE / f'{_h}.pcm').exists(), f'фразата не е в кеша — няма да се плаща: {phrase}'
    prev = cur[:cur.rindex('през', 0, i)]
    nxt = cur[i + len(y_old) + len(' годи́на'):]
if alone:
    prev, nxt = '', ''
fp, fal = E.synth(E.key(), bl['speaker'], phrase, {'reserve': 20, 'spent': 0}, prev, nxt, bl['kind'])
fp = array.array('h', fp)
ft = ''.join(fal['chars'])
fi = ft.lower().index(y_new.lower())


def cut(al, a, b):
    """Средата на паузите около знаците [a, b)."""
    # ⚠ Изразът може да е в самото начало/край на фразата — тогава „съседен
    # знак“ няма (индекс -1 сочеше КРАЯ на фразата и се чуваше само опашката).
    s = (al['end'][a - 1] + al['start'][a]) / 2 if a > 0 else max(al['start'][0] - 0.03, 0)
    e = (al['end'][b - 1] + al['start'][b]) / 2 if b < len(al['chars']) else al['end'][-1] + 0.05
    return int(round(s * R)), int(round(e * R))


a0, b0 = cut(al, i, i + len(y_old))
# ⚠ В ОДОБРЕНИЯ запис изрязът почва още от края на предишната дума — в
# средата на паузата оставаше началото на старото „х“ (автор, 13.10.2026).
if precise:
    a0 = int(round((al['end'][i - 2] + 0.01) * R))
a1, b1 = cut(fal, fi, fi + len(y_new))
piece = fp[a1:b1]
rms = lambda x: math.sqrt(sum(v * v for v in x) / max(len(x), 1))
g = rms(pcm[a0:b0]) / max(rms(piece), 1)
piece = array.array('h', (max(-32768, min(32767, int(v * g))) for v in piece))
x = int(0.010 * R)
# Паузата пред годината — същата като в одобрения, но от ТИШИНА (старият
# изрез вече почва от края на предишната дума). Без преливане отпред.
gap = int(round((al['start'][i] - al['end'][i - 2] - 0.01) * R)) - int(round(0.03 * R))
pre = array.array('h', [0] * max(gap, 0) if precise else [])
x2 = int(0.015 * R)                     # по-дълго преливане насред речта
for k in range(x if precise else x2):   # влизане на новия израз
    piece[k] = int(piece[k] * k / (x if precise else x2)) if precise else \
        int(piece[k] * k / x2 + pcm[a0 + k] * (1 - k / x2))
for k in range(x):                      # преливане в края
    piece[-1 - k] = int(piece[-1 - k] * k / x + pcm[b0 - 1 - k] * (1 - k / x))
fade = int(0.008 * R)                   # краят на „през“ — без щракване
head = pcm[:a0]
if precise:
    for k in range(fade):
        head[-1 - k] = int(head[-1 - k] * k / fade)
piece = pre + piece
out = head + piece + pcm[b0:]
d = (len(piece) - (b0 - a0)) / R
new = cur[:i] + y_new + cur[i + len(y_old):]
# Знаците на израза — по новия запис, отместени към мястото му.
off = (a0 + len(pre)) / R - a1 / R
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
