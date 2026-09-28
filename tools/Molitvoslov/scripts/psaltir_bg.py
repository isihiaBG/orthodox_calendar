"""Бг Псалтир (PDF, превод от църковнославянски, т.е. по Септуагинта) →
{катизма: [(„slava"|псалом N, …)]}, стих по стих.

Измерено в PDF-а (PyMuPDF):
    Cambria 8        номер на стих (горен индекс)
    Cambria 12       текстът
    Antiqua Italic   16 „Катизма N"; 14 надписание / „Слава:"; 9 — номер 1
                     пред надписанието (тогава надписанието Е стих 1)
    Palatino         бележките под линия и показалците им — отпадат
    Times New Roman  номерът на страницата (9) и титулната страница
"""
import re

import pymupdf

PDF = '../input/newBooks/24_Псалтир_BG.pdf'


def spans(doc):
    for pno in range(len(doc)):
        for bl in doc[pno].get_text('dict')['blocks']:
            for ln in bl.get('lines', []):
                for s in ln['spans']:
                    yield pno, ln['bbox'][1], s


def parse(path=PDF):
    """⚠ Нов псалом НЕ се познава по надписанието (при 14 от тях числото не е
    накрая или надпис няма), а по СТИХ 1 — редът в Псалтира е 1…151."""
    doc = pymupdf.open(path)
    kath, cur_k = {}, None
    psalm, verse, pend_head, n_psalm = None, None, [], 0
    buf = []
    capture = False

    def head_text():
        return re.sub(r'\s+', ' ', ' '.join(buf)).strip()

    def flush_italic():
        nonlocal buf, capture
        if not buf:
            return
        t = head_text()
        buf = []
        m = re.match(r'^(Слава[:.…]*(?:\s*и сега…\s*Алилуя…)?)\s*(.*)$', t)
        if m:
            kath[cur_k].append(('slava', m.group(1)))
            if m.group(2):
                pend_head.append(m.group(2))   # надписанието на следващия
        elif t in ('Среда', 'Среда.'):
            kath[cur_k].append(('rubric', t))
        elif re.match(r'^Катизма', t):
            pass
        else:
            pend_head.append(t)

    def new_psalm(head_is_v1):
        nonlocal psalm, n_psalm
        n_psalm += 1
        psalm = {'n': n_psalm, 'head': ' '.join(pend_head).strip(), 'verses': {},
                 'head_is_v1': head_is_v1}
        pend_head.clear()
        kath[cur_k].append(('psalm', psalm))

    for pno, y, sp in spans(doc):
        f, sz, t = sp['font'], round(sp['size']), sp['text']
        if 'Palatino' in f or ('Times' in f and 'Italic' not in f):
            continue
        if 'Italic' in f and re.match(r'\s*Катизма', t):
            flush_italic()
            m = re.search(r'(\d+)', t)
            cur_k = int(m.group(1)) if m else (1 if 'първа' in t else 2)
            kath.setdefault(cur_k, [])
            continue
        if cur_k is None:
            continue
        if 'Italic' in f and sz == 9 and t.strip().isdigit():
            d = int(t.strip())
            if d > 1 and capture:
                # „…псалом Давидов, ²когато влезе при него пророк Натан…" —
                # надписанието обхваща и стих 2; той отива при стиховете.
                verse = d
                psalm['verses'][d] = ''
                capture = 'verse'
                continue
            flush_italic()
            new_psalm(True)               # надписанието е стих 1
            verse = 1
            psalm['verses'][1] = ''
            capture = True
            continue
        if 'Italic' in f and sz < 13 and 'Times' not in f:
            # Курсивна дума насред стиха (добавка на преводача) — част от него.
            if psalm is not None and verse is not None:
                psalm['verses'][verse] += t
            continue
        if 'Italic' in f and 'Times' in f:
            # Славословието след псалмите на 1-вата катизма — указание.
            kath[cur_k].append(('rubric', t.strip()))
            continue
        if 'Italic' in f:
            if capture == 'verse':
                psalm['verses'][verse] += t
                continue
            if capture and sz >= 12:      # текстът на същото надписание
                psalm['head'] = (psalm['head'] + ' ' + t).strip()
                continue
            buf.append(t)
            continue
        capture = False
        flush_italic()
        if 'Cambria' in f and sz <= 8 and t.strip().isdigit():
            v = int(t.strip())
            # ⚠ Нов псалом — САМО ако пред него стои надписание (всеки псалом
            # в тази книга има такова; номерът на стиха не е надежден — на места
            # се връща назад насред псалма). Често стих 1 Е надписанието и
            # не носи номер — тогава текстът почва от 2.
            if psalm is None or pend_head:
                new_psalm(v != 1)
            verse = v
            psalm['verses'][verse] = ''
            continue
        if 'Cambria' in f and psalm is not None and verse is not None:
            psalm['verses'][verse] += t
    flush_italic()
    for items in kath.values():
        for kind, p in items:
            if kind == 'psalm':
                for v in p['verses']:
                    p['verses'][v] = re.sub(r'\s+', ' ', p['verses'][v]).strip()
    return kath


if __name__ == '__main__':
    k = parse()
    RANGES = {1: (1, 8), 2: (9, 16), 3: (17, 23), 4: (24, 31), 5: (32, 36), 6: (37, 45),
              7: (46, 54), 8: (55, 63), 9: (64, 69), 10: (70, 76), 11: (77, 84), 12: (85, 90),
              13: (91, 100), 14: (101, 104), 15: (105, 108), 16: (109, 117), 17: (118, 118),
              18: (119, 133), 19: (134, 142), 20: (143, 151)}
    for kn, items in sorted(k.items()):
        ps = [p for kind, p in items if kind == 'psalm']
        a, b = RANGES[kn]
        print(kn, 'OK' if len(ps) == b - a + 1 else 'РАЗЛИКА %d срещу %d' % (len(ps), b - a + 1))
        print(kn, [ (p['n'], re.search(r'(\d+)\D*$', p['head']).group(1) if re.search(r'\d', p['head']) else '-') for p in ps])
