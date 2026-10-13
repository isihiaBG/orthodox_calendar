#!/usr/bin/env python3
"""Една ДУМА (основата ѝ) от един запис на няколко места в други (13.10.2026).

    python3 transplant.py <източник: кеш> <поз. в източника> <дължина> <цел: кеш:поз …>

Взема знаците [поз, поз+дължина) от източника — от средата на паузата пред
думата до края на последния знак (окончанието на източника НЕ се взема) — и
ги слага на мястото на същия брой знаци във всяка цел; окончанието на целта
(„-ът“) остава нейно. Шевове с 10 ms преливане, силата — изравнена.
⚠ Пише ВЪРХУ кеша на целта (ключът — същият текст); копие се пази в
work/backup_transplant/. Авторът: „П10 е единственото правилно — наслагай
го навсякъде“ (про̀мисъл от c03)."""
import array, json, math, shutil, sys
import eleven as E

R = E.RATE
src_h, sp, n = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
# По избор: SRC_END=<секунди> — точният край на думата в източника, измерен
# по спектъра (разбивката по знаци е приблизителна: в c03 „-а“ почва при
# 8,02 s, а разбивката казва 8,046 — и гласната влизаше; автор, 13.10.2026).
import os
SRC_END = float(os.environ['SRC_END']) if os.environ.get('SRC_END') else None
BK = E.WORK / 'backup_transplant'
BK.mkdir(exist_ok=True)


def load(h):
    return json.loads((E.CACHE / f'{h}.json').read_text()), array.array('h', (E.CACHE / f'{h}.pcm').read_bytes())


def bounds(al, p, n, tail_word_end):
    """Начало — средата на паузата пред думата; край — края на последния знак
    (+ до средата на паузата, ако думата свършва там)."""
    s = (al['end'][p - 1] + al['start'][p]) / 2 if p > 0 else al['start'][p]
    q = p + n
    if tail_word_end and q < len(al['chars']):
        e = (al['end'][q - 1] + al['start'][q]) / 2
    else:
        e = al['end'][q - 1]
    return int(round(s * R)), int(round(e * R))


_fresh = set()
sal, spcm = load(src_h)
word = ''.join(sal['chars'][sp:sp + n])
low = lambda c: c.lower()
for tgt in sys.argv[4:]:
    th, tp = tgt.split(':')
    tp = int(tp)
    al, pcm = load(th)
    tw = ''.join(al['chars'][tp:tp + n])
    strip = lambda w: ''.join(c for c in w if c not in '́̀').lower()
    assert strip(tw) == strip(word), f'{th}:{tp} — „{tw}“ не е „{word}“'
    for ext in ('pcm', 'json'):
        if not (BK / f'{th}.{ext}').exists():
            shutil.copy(E.CACHE / f'{th}.{ext}', BK / f'{th}.{ext}')
    # наново — от оригинала, не върху предишния опит. ⚠ САМО първия път за
    # този запис в пускането: няколко места в ЕДИН запис — второто иначе
    # тръгваше пак от оригинала и изтриваше първото (13.10.2026, c05).
    if os.environ.get('FROM_BACKUP') and th not in _fresh:
        _fresh.add(th)
        al, pcm = json.loads((BK / f'{th}.json').read_text()), array.array('h', (BK / f'{th}.pcm').read_bytes())
    q = tp + n
    ends = q >= len(al['chars']) or not al['chars'][q].isalpha()   # цялата дума ли е
    a0, b0 = bounds(al, tp, n, False)   # паузата след думата остава на целта
    a1, b1 = bounds(sal, sp, n, False)
    if SRC_END:
        b1 = int(round(SRC_END * R))
    # ⚠ БЕЗ „въздух“ от източника след думата — там вече е следващият звук.
    piece = spcm[a1:b1]
    # По избор: PITCH=<полутонове> — леко вдигане/сваляне на тона на
    # пренесеното (rubberband, без промяна на скоростта; автора, 13.10.2026:
    # „тембърът е забележимо по-нисък").
    if os.environ.get('PITCH'):
        import subprocess
        r = 2 ** (float(os.environ['PITCH']) / 12)
        out_b = subprocess.run(['ffmpeg', '-v', 'error', '-f', 's16le', '-ar', str(R), '-ac', '1', '-i', '-',
                                '-af', f'rubberband=pitch={r:.5f}', '-f', 's16le', '-ar', str(R), '-ac', '1', '-'],
                               input=piece.tobytes(), capture_output=True, check=True).stdout
        piece = array.array('h', out_b)
    rms = lambda x: math.sqrt(sum(v * v for v in x) / max(len(x), 1))
    g = rms(pcm[a0:b0]) / max(rms(piece), 1)
    piece = array.array('h', (max(-32768, min(32767, int(v * g))) for v in piece))
    x = int(0.010 * R)
    for k in range(x):
        piece[k] = int(piece[k] * k / x + pcm[a0 + k] * (1 - k / x))
        piece[-1 - k] = int(piece[-1 - k] * k / x + pcm[b0 - 1 - k] * (1 - k / x))
    out = pcm[:a0] + piece + pcm[b0:]
    d = (len(piece) - (b0 - a0)) / R
    off = (a0 - a1) / R
    st = al['start'][:tp] + [t + off for t in sal['start'][sp:sp + n]] + [t + d for t in al['start'][q:]]
    en = al['end'][:tp] + [t + off for t in sal['end'][sp:sp + n]] + [t + d for t in al['end'][q:]]
    al = {'chars': al['chars'], 'start': st, 'end': en}
    (E.CACHE / f'{th}.pcm').write_bytes(out.tobytes())
    (E.CACHE / f'{th}.json').write_text(json.dumps(al, ensure_ascii=False))
    print(f'{th}:{tp} „{tw}“ ← „{word}“  сила ×{g:.2f}  {d * 1000:+.0f} ms')
