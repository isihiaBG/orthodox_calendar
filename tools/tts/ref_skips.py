"""Препратките към Писанието в скоби в записите на „Разговори…“ →
assets/speech/ref_skips.json: отрязъци (от, до) в секунди, които плейърът
прескача при изключена настройка „Препратките към Писанието“ (30.10.2026).

Звукът НЕ се пипа — режат се само времената. Вътре в изречение границите
идват от подравняването в кеша на ElevenLabs (без нова заявка) и се наместват
по самия звук до началото на паузата; препратка, която е цяло изречение —
от паузата преди него до следващото. Отрязъците са вързани за версията на
записа (v / lv от assets/audio_index.json): друга версия — без прескачане,
пусни скрипта наново.

    python3 tools/tts/ref_skips.py
"""
import json, re, sys
from pathlib import Path
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import eleven as E

REF = r'(?:[1-4]\s*)?[А-ЯЁ][а-яё]{1,7}\.?\s*\d{1,3}(?:\s*[:,]\s*\d{1,3})?(?:\s*[-–—,]\s*\d{1,3}(?:\s*:\s*\d{1,3})?)*(?:\s*гл\.)?'
ONLY = re.compile(r'^\s*(?:(?:ср|срв|вж|виж)\.?\s*)?' + REF + r'(?:\s*[;,]\s*(?:(?:ср|срв|вж|виж)\.?\s*)?' + REF + r')*\s*$')

chapters = json.loads((E.WORK / 'razgovori_marked.json').read_text())
out = {}
for c in chapters:
    f = c['file']
    if f == 'notes': continue
    try: fin = json.loads((E.OUT / 'razgovori' / f'{f}.json').read_text())
    except FileNotFoundError: continue
    fs = fin['sents']
    # (p, s) → индекс в окончателния
    fidx = {}
    for i, s in enumerate(fs): fidx.setdefault((s['p'], s['s']), []).append(i)
    res = []
    for pi, bl in enumerate(c['blocks']):
        text = bl['text']
        found = []
        for k, (a, b, shown, notes) in enumerate(bl['sents']):
            sh = list(re.finditer(r'\(([^()]*)\)', shown))
            tx = list(re.finditer(r'\(([^()]*)\)', text[a:b]))
            for j, m in enumerate(sh):
                if not ONLY.match(m[1]): continue
                if len(sh) != len(tx): print('⚠ скобите не съвпадат', f, shown[:60]); break
                found.append((k, m[0], a + tx[j].start(), a + tx[j].end()))
        if not found: continue
        sp, pos = E.spoken(bl)
        parts = E.chunks_of(bl)
        for k, ref, ms, me in found:
            a, b, shown, notes = bl['sents'][k]
            fi = fidx.get((pi, shown), [None])[0]
            if fi is None: print('⚠ няма в окончателния', f, ref); continue
            if shown.strip().rstrip('.').strip() == ref:
                res.append({'s': fi, 'whole': True, 'ref': ref, 't': fs[fi]['t'], 'e': fs[fi]['e']}); continue
            sa, sb = pos[a], pos[b]
            ptxt, base = [(t, base) for t, base, items in parts if base <= sa < base + len(t)][0]
            try:
                audio, al = E.synth(None, bl['speaker'], ptxt, {'reserve': 0, 'spent': 0}, '', '', bl['kind'])
            except SystemExit:
                print('⚠ няма кеш', f, ref); continue
            i0 = ms - 1
            while i0 > a and text[i0] == ' ': i0 -= 1
            i1 = me
            while i1 < b and text[i1] == ' ': i1 += 1
            ts = E.char_time(al, sa - base); te = E.char_time(al, sb - base - 1, end=True)
            r0 = E.char_time(al, pos[i0] - base, end=True) if i0 >= a else ts
            r1 = E.char_time(al, pos[i1] - base) if i1 < b else te
            ft, fe = fs[fi]['t'], fs[fi]['e']
            res.append({'s': fi, 'ref': ref, 'x0': round(ft + r0 - ts, 3), 'x1': round(ft + r1 - ts, 3),
                        'drift': round((fe - ft) - (te - ts), 3), 'tail': round(te - r1, 3),
                        'ctx': shown})
    out[f] = res

# ── наместване по звука ───────────────────────────────────────────────────
import array, subprocess
SR, W, Q = 8000, 0.02, 60

def env(f):
    p = array.array('h', subprocess.run(['ffmpeg', '-v', 'error', '-i', str(E.OUT / 'razgovori' / f'{f}.mp3'),
                                         '-f', 's16le', '-ac', '1', '-ar', str(SR), '-'],
                                        capture_output=True, check=True).stdout)
    n = int(W * SR)
    return [int((sum(v * v for v in p[i:i + n]) / n) ** 0.5) for i in range(0, len(p) - n, n)]

def quiet_from(e, t, back=0.15, ahead=0.6):
    """Началото на първата пауза около t."""
    i = int((t - back) / W)
    while i < int((t + ahead) / W):
        if e[i] < Q and e[i + 1] < Q:
            return round(i * W, 3)
        i += 1
    return None

ROOT = HERE.parent.parent
idx = json.loads((ROOT / 'assets/audio_index.json').read_text())['books']['assets/chitalnya/razgovori.epub']['parts']
res = {}
for f, r in out.items():
    if not r:
        continue
    e = env(f)
    fin = json.loads((E.OUT / 'razgovori' / f'{f}.json').read_text())['sents']
    xs = []
    for x in r:
        if x.get('whole'):
            i = x['s']
            prev = fin[i - 1]['e'] if i > 0 else 0
            a = max(prev + 0.05, x['t'] - 0.25)
            b = fin[i + 1]['t'] - 0.05 if i + 1 < len(fin) else x['e']
        else:
            a, b = quiet_from(e, x['x0']), quiet_from(e, x['x1'])
            if a is None or b is None or b <= a:
                print('⚠ без пауза', f, x['ref'])
                continue
        xs.append([round(a, 3), round(b, 3)])
        print(f, f'{a:8.2f}–{b:8.2f}', x['ref'])
    res[f] = {'v': idx[f]['v'], 'lv': idx[f].get('lv'), 'x': xs}
(ROOT / 'assets/speech/ref_skips.json').write_text(
    json.dumps({'assets/chitalnya/razgovori.epub': res}, ensure_ascii=False, separators=(',', ':')))
print(sum(len(v['x']) for v in res.values()), 'отрязъка')
