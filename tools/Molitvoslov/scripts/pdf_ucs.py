"""PDF книга в старото кодиране Ucs (шрифтове Irmologion) → единици с блокове.

Ползва се за „Канонник" (вертоград, 840 стр.) и за Псалтира на цс.

Устройството на страницата, измерено с PyMuPDF (не гадано):

    y < 35                  жива колонтитула (името на раздела) — отпада
    шрифт Arial             номерът на страницата — отпада
    червено, ≥ 20 pt        заглавие на раздел или на ден
    червено, 16 pt, само    центрирано заглавие („Пѣ́снь а҃.", „Конда́къ")
    x ≈ 62                  начало на абзац (отстъп)
    x ≈ 43                  продължение на абзаца
    червено, 12 pt          етикет в началото на абзаца („І҆рмо́съ:", „Припѣ́въ:")

⚠ Червената ПЪРВА буква на абзаца НЕ се пази като указание: четецът сам
оцветява първата главна буква на всеки цс абзац (`_redFirst`). Иначе би се
удвоила.
⚠ Цветът и размерът идват от PDF-а — pdftotext ги губи. Затова е PyMuPDF.
"""
import html
import re

import pymupdf

import ucs

MARKS = re.compile('[̀-ͯ҃-҉ⷠ-ⷿ꙯-ꙿ]')
CS_DIGIT = {'а': 1, 'в': 2, 'г': 3, 'д': 4, 'є': 5, 'ѕ': 6, 'з': 7, 'и': 8, 'ѳ': 9}


def bare(t):
    """Без надредните знаци — за сравнения."""
    return MARKS.sub('', t or '').strip()


def song_no(title):
    m = re.match(r'Пѣснь\s+(\S)', bare(title))
    return CS_DIGIT.get(m.group(1)) if m else None


def lines(doc, first, last):
    """Страници [first, last] (индекси от 0) → редове (стр., x, big, heading, runs).

    runs: [(червено, текст)] в Unicode. `heading` — целият ред е червен.
    """
    out = []
    for pno in range(first, last + 1):
        rows = {}
        for bl in doc[pno].get_text('dict')['blocks']:
            for ln in bl.get('lines', []):
                if ln['bbox'][1] < 35:
                    continue
                for s in ln['spans']:
                    if 'Arial' in s['font']:
                        continue
                    rows.setdefault(round(ln['bbox'][1]), []).append(
                        (s['bbox'][0], s['color'] != 0, s['size'], s['text']))
        for y in sorted(rows):
            sp = sorted(rows[y])
            text = ''.join(t for *_, t in sp)
            if not text.strip():
                continue
            vis = [(r, sz) for _, r, sz, t in sp if t.strip()]
            heading = all(r for r, _ in vis) and max(sz for _, sz in vis) >= 15
            big = max(sz for _, sz in vis) >= 19
            runs = []
            for i, (_, r, sz, t) in enumerate(sp):
                dec = ucs.decode(t)
                # Червена буквица (една буква в началото на абзаца) — не е указание.
                initial = r and i == 0 and not heading and len(bare(dec)) <= 1
                runs.append((r and not initial, dec))
            out.append((pno, sp[0][0], big, heading, runs))
    return out


def runs_html(runs):
    """Парчетата на абзаца → html; червените етикети стават span.rubric."""
    parts, red = [], []
    for is_red, t in runs:
        if is_red:
            red.append(t)
            continue
        if red:
            parts.append('<span class="rubric">%s</span>' % html.escape(''.join(red).strip(), quote=False))
            parts.append(' ')
            red = []
        parts.append(html.escape(t, quote=False))
    if red:
        parts.append(' <span class="rubric">%s</span>' % html.escape(''.join(red).strip(), quote=False))
    out = re.sub(r'\s+', ' ', ''.join(parts)).strip()
    # Пренесена дума („ѳесв- і́тѧнина") — сливане.
    return re.sub(r'(?<=[^\W\d_])- (?=[^\W\d_])', '', out)


BOUNDARY = [
    ('song', lambda b: song_no(b)),
    ('kondak', lambda b: b.startswith('Кондакъ')),
    ('ikos', lambda b: b.startswith('Ікосъ') or b.startswith('Iкосъ')),
    ('sedalen', lambda b: b.startswith('Сѣдаленъ')),
    ('prayer', lambda b: 'млтв' in b.lower().replace(' ', '')[:12] or b.startswith('Молитва')),
]


def boundary(title):
    b = bare(title).replace('҆', '')
    for kind, test in BOUNDARY:
        v = test(b)
        if v:
            return kind, (v if kind == 'song' else None)
    return None


def units(ls):
    """Редове → [{title, key, blocks}]. Ключът е ('song', N) или (вид, след песен N)."""
    res = [{'title': None, 'key': ('intro', 0), 'blocks': []}]
    para, head = None, []
    last_song = 0
    counters = {}

    def flush_para():
        nonlocal para
        if para:
            h = runs_html(para)
            if h:
                kind = 'refrain' if re.match(r'<span class="rubric">(Припѣ́въ|Запѣ́въ)', h) else 'text'
                res[-1]['blocks'].append({'kind': kind, 'html': h})
        para = None

    def flush_head():
        nonlocal head, last_song
        if not head:
            return
        title = re.sub(r'\s+', ' ', ' '.join(head)).strip()
        head = []
        b = boundary(title)
        if b:
            kind, n = b
            if kind == 'song':
                last_song = n
                key = ('song', n)
            else:
                counters[(kind, last_song)] = counters.get((kind, last_song), 0) + 1
                key = (kind, last_song, counters[(kind, last_song)])
            res.append({'title': title.rstrip(':'), 'key': key, 'blocks': []})
        else:
            res[-1]['blocks'].append({'kind': 'rubric', 'html': html.escape(title, quote=False)})

    for pno, x, big, heading, runs in ls:
        text = ''.join(t for _, t in runs).strip()
        if heading and big:
            flush_para()
            flush_head()
            continue            # заглавието на раздела/деня се дава отвън
        if heading and not re.match(r'^\[', text):
            flush_para()
            # „Гла́съ ѕ҃. Пѣ́снь а҃." — песента почва своя единица, дори да е
            # на един ред с предходното заглавие.
            m = re.search(r'\s(Пѣ́снь\s)', text)
            if m and not head:
                head.append(text[:m.start()].strip())
                text = text[m.start(1):]
            elif m:
                head.append(text[:m.start()].strip())
                text = text[m.start(1):]
            if boundary(text):
                flush_head()
            head.append(text)
            continue
        flush_head()
        if para is None or 52 <= x <= 75:
            flush_para()
            para = []
        elif para:
            para.append((False, ' '))
        para.extend(runs)
    flush_para()
    flush_head()
    if not res[0]['blocks']:
        res.pop(0)
    return res


def open_doc(path):
    return pymupdf.open(path)


# ─── Паралелно издание: цс вляво, бг вдясно (Великият канон, 2013) ──────────
# ⚠ Текстът е центриран, не двустранно подравнен — началото на абзаца НЕ
# личи по отстъпа. Личи по ПРАЗНИНАТА над него: редът е през ~17 pt, а между
# абзаците има ~33. Заглавията (≥ 16 pt, изцяло червени) делят единиците.
COL_SPLIT = 205
PAR_GAP = 25


def _col_lines(doc, col):
    out = []
    for pno in range(len(doc)):
        rows = {}
        for bl in doc[pno].get_text('dict')['blocks']:
            for ln in bl.get('lines', []):
                x0 = ln['bbox'][0]
                if (x0 < COL_SPLIT) != (col == 0):
                    continue
                for s in ln['spans']:
                    if s['size'] < 11:          # номерът на страницата
                        continue
                    rows.setdefault(round(ln['bbox'][1]), []).append(
                        (s['bbox'][0], s['color'] != 0x231f20, s['size'], s['text'],
                         'Ucs' in s['font']))
        for y in sorted(rows):
            sp = sorted(rows[y])
            vis = [(r, sz) for _, r, sz, t, _ in sp if t.strip()]
            if not vis:
                continue
            runs = []
            for i, (_, r, sz, t, u) in enumerate(sp):
                dec = ucs.decode(t) if u else t
                initial = r and i == len(sp) - 2 and not sp[i + 1][1] and len(bare(dec).strip()) <= 1
                if r and i + 1 < len(sp) and not sp[i + 1][1]:
                    # „Припѣ́въ: П|оми́лꙋй" — буквицата е залепена за етикета
                    lab = dec.rstrip()
                    if len(bare(lab)) and len(bare(lab.split()[-1])) <= 1 and ':' in lab:
                        head, cap = lab[:lab.rstrip().rfind(' ')], lab.split()[-1]
                        runs.append((True, head))
                        runs.append((False, ' ' + cap))
                        continue
                runs.append((r and not initial, dec))
            # ⚠ Последното поле: първото парче е червено (буквица или етикет) —
            # само по него личи нов абзац в началото на страница.
            out.append((pno, y, all(r for r, _ in vis), max(sz for _, sz in vis), runs,
                        sp[0][1]))
    return out


def _col_units(ls, is_cs):
    """Една колона → [(вид, заглавие, [блокове])] по дни: {ден: единици}."""
    days, cur_day, units = [], None, None
    para, prev = None, None
    cont_day = False

    def flush():
        nonlocal para
        if para and units is not None:
            h = runs_html(para)
            if h:
                all_red = all(r for r, t in para if t.strip())
                if all_red:
                    kind = 'rubric'
                    h = re.sub(r'</?span[^>]*>', '', h)
                elif re.match(r'<span class="rubric">(Припѣ́въ|Запѣ́въ|Припев)', h):
                    kind = 'refrain'
                else:
                    kind = 'text'
                units[-1]['blocks'].append({'kind': kind, 'html': h})
        para = None

    for pno, y, red, size, runs, red0 in ls:
        text = ''.join(t for _, t in runs).strip()
        if red and size >= 17:                   # ден
            flush()
            b = bare(text).replace('҆', '')
            is_day = re.match(r'(Въ?|Во) (понедѣльникъ|вторникъ|средꙋ|четвертокъ)'
                              r'|(В|Във) (понеделник|вторник|сряда|четвъртък)', b)
            if prev and prev[2] and prev[3] >= 17 and prev[0] == pno and cont_day:
                days[-1]['title'] += ' ' + text
            elif not is_day:
                cont_day = False                 # корица на деня — не е текст
                units = None
            else:
                cont_day = True
                units = [{'title': None, 'blocks': []}]
                days.append({'title': text, 'units': units})
            prev = (pno, y, red, size)
            continue
        if red and size >= 15.5:                 # песен / кондак
            flush()
            units.append({'title': text.rstrip('.').strip(), 'blocks': []})
            prev = (pno, y, red, size)
            continue
        if units is None:
            prev = (pno, y, red, size)
            continue
        new = (para is None or prev is None or prev[0] != pno and red0
               or prev[0] == pno and y - prev[1] > PAR_GAP)
        if new:
            flush()
            para = list(runs)
        else:
            para.append((False, ' '))
            para.extend(runs)
        prev = (pno, y, red, size)
    flush()
    return days


def parallel(path):
    """→ [{'title_cs', 'title_bg', 'units': [{title_cs, title_bg, csl, bg}]}]."""
    doc = pymupdf.open(path)
    cs, bg = _col_units(_col_lines(doc, 0), True), _col_units(_col_lines(doc, 1), False)
    res = []
    for dc, db in zip(cs, bg):
        us = []
        for uc, ub in zip(dc['units'], db['units']):
            us.append({'title_cs': uc['title'], 'title_bg': ub['title'],
                       'csl': uc['blocks'], 'bg': ub['blocks']})
        res.append({'title_cs': dc['title'], 'title_bg': db['title'], 'units': us,
                    'counts': [(len(a['blocks']), len(b['blocks']))
                               for a, b in zip(dc['units'], db['units'])],
                    'n_units': (len(dc['units']), len(db['units']))})
    return res
