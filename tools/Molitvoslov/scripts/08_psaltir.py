"""Таб „Псалтир" → work/psaltir.json (в същия вид като kanonnik.json).

    бг   24_Псалтир_BG.pdf — превод ОТ ЦЪРКОВНОСЛАВЯНСКИ, т.е. по Септуагинта
         (рядкост: обичайният бг превод е по масоретския текст)
    цс   псалмите — от вградената Библия (bible.db, utfcs), стих по стих;
         молитвите след катизмите и началото/краят — от 24_Псалтир_ЦС.pdf

⚠ Цс текстът на псалмите НЕ се взима от PDF-а: там номерът на стиха стои в
полето до РЕДА, а стихът почва някъде насред него — границата не може да се
възстанови. В Библията стиховете са разделени и номерацията е същата
(Септуагинта), тъй че двата езика се подреждат по номер.
⚠ При 30 от 151 псалма деленето на стихове се разминава с 1–3 — затова
единицата е ПСАЛОМЪТ (двете колони вървят една до друга), а не стихът.
⚠ Молитвите след катизмите ги има само на цс — бг Псалтирът ги няма.
"""
import html
import json
import os
import re
import sqlite3
import sys

sys.path.insert(0, os.path.dirname(__file__))
import pdf_ucs  # noqa: E402
import psaltir_bg  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
W = os.path.join(ROOT, 'work')
BIBLE = os.path.join(ROOT, '..', '..', 'assets', 'db', 'bible.db')
CS_PDF = os.path.join(ROOT, 'input', 'newBooks', '24_Псалтир_ЦС.pdf')
BG_SRC = ('Текстът на български е по Септуагинта, като е преведен от '
          'църковнославянски език от инок Евтимий (Хинов).')
CS_SRC_PS = 'https://azbyka.ru/biblia/?Ps.1&utfcs'
CS_SRC_PR = 'Псалтирь (цс), молитвите след катизмите'

# Катизмите — първият псалом (редът е 1…151, последната свършва със 151).
START = [1, 9, 17, 24, 32, 37, 46, 55, 64, 70, 77, 85, 91, 101, 105, 109, 118, 119,
         134, 143, 152]
ORD_BG = ['първа', 'втора', 'трета', 'четвърта', 'пета', 'шеста', 'седма', 'осма',
          'девета', 'десета', 'единадесета', 'дванадесета', 'тринадесета',
          'четиринадесета', 'петнадесета', 'шестнадесета', 'седемнадесета',
          'осемнадесета', 'деветнадесета', 'двадесета']
UNITS = 'аввгдєѕзиѳ'
CS_D = ['', 'а', 'в', 'г', 'д', 'є', 'ѕ', 'з', 'и', 'ѳ']
CS_T = ['', 'і', 'к', 'л', 'м', 'н', 'ѯ', 'ѻ', 'п', 'ч']


def cs_num(n):
    """Число с цс букви и титла: 11 → а҃і, 21 → к҃а, 118 → р҃иі."""
    h, t, u = n // 100, n // 10 % 10, n % 10
    s = ('р' if h else '')
    if t == 1:
        s += CS_D[u] + 'і'
    else:
        s += CS_T[t] + CS_D[u]
    return s[0] + '҃' + s[1:] if s else ''


def verse_html(n, text):
    return '<span class="rubric">%d</span> %s' % (n, html.escape(text, quote=False))


def cs_verses(db, ps):
    rows = db.execute("SELECT verse, text FROM verses WHERE lang='utfcs' AND book='Ps' "
                      "AND chapter=? ORDER BY ord", (ps,)).fetchall()
    return [(int(v), t.strip()) for v, t in rows if v.isdigit()]


def psalm_unit(db, ps, p):
    """Един псалом: надписание (указание), после стиховете с номерата им."""
    bg, csl = [], []
    if p['head']:
        bg.append({'kind': 'rubric', 'html': html.escape(p['head'], quote=False)})
    for v in sorted(p['verses']):
        t = p['verses'][v]
        if v == 1 and p['head_is_v1'] and not t:
            continue                      # стих 1 Е надписанието
        if t:
            bg.append({'kind': 'verse', 'html': verse_html(v, t)})
        for after, kind, txt in p.get('breaks', []):
            if after == v:
                bg.append({'kind': 'rubric', 'html': 'Слава:' if kind == 'slava'
                           else html.escape(txt, quote=False)})
    cs = cs_verses(db, ps)
    for v, t in cs:
        # Надписанието: стих 0, или стих 1, щом почва с „Ѱало́мъ"/„Въ коне́цъ".
        head = v == 0 or (v == 1 and p['head_is_v1'] and len(cs) > 1)
        if head:
            csl.append({'kind': 'rubric', 'html': html.escape(t, quote=False)})
        else:
            csl.append({'kind': 'verse', 'html': verse_html(v, t)})
        # ⚠ Същите прекъсвания и в цс — след СЪЩИЯ стих (номерацията е обща).
        for after, kind, txt in p.get('breaks', []):
            if after == v:
                csl.append({'kind': 'rubric', 'html': 'Сла́ва:' if kind == 'slava'
                            else 'Среда̀.'})
    return {'title_csl': None, 'title_bg': 'Псалом %d' % ps,
            'title_cs': 'Ѱало́мъ %s' % cs_num(ps), 'csr': [], 'bg': bg, 'csl': csl,
            'sources': [BG_SRC]}


def cs_heads(doc):
    """(стр., y, вид, №) на заглавията „Каѳі́сма…" и „По N-й каѳі́смѣ"."""
    out = []
    for pno in range(len(doc)):
        for bl in doc[pno].get_text('dict')['blocks']:
            for ln in bl.get('lines', []):
                sp = ln['spans']
                if not any(s['color'] != 0 for s in sp):
                    continue
                t = pdf_ucs.bare(''.join(pdf_ucs.ucs.decode(s['text']) for s in sp))
                size = max(s['size'] for s in sp)
                if size >= 19 and t.startswith('Каѳісма'):
                    out.append((pno, ln['bbox'][1], 'kath'))
                elif t.startswith('По ') and 'каѳісмѣ' in t:
                    out.append((pno, ln['bbox'][1], 'after'))
                elif t.startswith('По совершенїи'):
                    out.append((pno, ln['bbox'][1], 'end'))
                elif t.startswith('Разꙋмно да бꙋдетъ') and size >= 19:
                    # ⚠ Само заглавието (20 pt) — същият ред стои и в
                    # съдържанието на книгата, откъдето влизаше целият указател.
                    out.append((pno, ln['bbox'][1], 'begin'))
    return out


def prayers_after(doc, heads, k):
    """Молитвите след катизма k — от „По k-й каѳі́смѣ" до следващата катизма."""
    after = [h for h in heads if h[2] == 'after'][k - 1]
    nxt = next((h for h in heads if (h[0], h[1]) > (after[0], after[1])
                and h[2] in ('kath', 'end')), None)
    last = nxt[0] if nxt else len(doc) - 1
    return [r for r in pdf_ucs.lines(doc, after[0], last)
            if (r[0], r[5]) >= (after[0], after[1] - 1)
            and not (nxt and (r[0], r[5]) >= (nxt[0], nxt[1] - 1))]


def cs_blocks(ls):
    """Редове → блокове (един раздел, без деление на единици)."""
    us = pdf_ucs.units(ls, indent=(95, 115))
    blocks = []
    for u in us:
        if u['title']:
            blocks.append({'kind': 'rubric', 'html': html.escape(u['title'], quote=False)})
        blocks.extend(u['blocks'])
    return [b for b in blocks if b['html'].strip() and '____' not in b['html']]


def main():
    db = sqlite3.connect(BIBLE)
    bgk = psaltir_bg.parse(os.path.join(ROOT, 'input', 'newBooks', '24_Псалтир_BG.pdf'))
    doc = pdf_ucs.open_doc(CS_PDF)
    heads = cs_heads(doc)
    out = []

    # Начало — как се почва четенето (само цс).
    begin = next(h for h in heads if h[2] == 'begin')
    first = next(h for h in heads if h[2] == 'kath')
    ls = [r for r in pdf_ucs.lines(doc, begin[0], first[0])
          if (r[0], r[5]) < (first[0], first[1] - 1)
          and (r[0], r[5]) > (begin[0], begin[1] + 35)]   # без 2-рия ред на заглавието
    out.append({'sec': 300, 'tab': 'psaltir', 'title_bg': 'Преди четене на Псалтира',
                'title_csl': 'Разꙋ́мно да бꙋ́детъ, ка́кѡ подоба́етъ ѻ҆со́бь пѣ́ти ѱалти́рь',
                'csr_source': None, 'csl_source': CS_SRC_PR,
                'units': [{'n': 0, 'title_csl': None, 'title_bg': None, 'title_cs': None,
                           'csr': [], 'bg': [], 'csl': cs_blocks(ls), 'sources': []}]})

    for k in range(1, 21):
        units = []
        items = bgk[k]
        i = 0
        for kind, val in items:
            if kind == 'psalm':
                ps = START[k - 1] + i
                i += 1
                units.append(psalm_unit(db, ps, val))
            elif units:
                if kind == 'slava':
                    # „Слава:" — край на стихия; в двете колони.
                    units[-1]['bg'].append({'kind': 'rubric', 'html': 'Слава:'})
                    units[-1]['csl'].append({'kind': 'rubric', 'html': 'Сла́ва:'})
                else:
                    if not re.search(r'[^\W\d_]', val):
                        continue          # показалец на бележка под линия
                    units[-1]['bg'].append({'kind': 'rubric',
                                            'html': html.escape(val, quote=False)})
                    # ⚠ В 1-вата катизма бг изписва славословието ЦЯЛО („Слава
                    # на Отца…"), а не „Слава:" — това е първата стихия и цс
                    # оставаше без своята „Сла́ва:" (бележка на потребителя).
                    if val.startswith('Слава на Отца') and not any(
                            b['html'] == 'Сла́ва:' for b in units[-1]['csl']):
                        units[-1]['csl'].append({'kind': 'rubric', 'html': 'Сла́ва:'})
        assert START[k - 1] + i == START[k], (k, i)
        pr = cs_blocks(prayers_after(doc, heads, k))
        units.append({'title_csl': None, 'title_bg': 'Молитви след %s катизма' % ORD_BG[k - 1],
                      'title_cs': 'По %s-й каѳі́смѣ' % cs_num(k), 'csr': [], 'bg': [],
                      'csl': pr, 'sources': []})
        for n, u in enumerate(units):
            u['n'] = n
        a, b = START[k - 1], START[k] - 1
        rng = 'псалом %d' % a if a == b else 'псалми %d–%d' % (a, b)
        out.append({'sec': 300 + k, 'tab': 'psaltir',
                    'title_bg': 'Катизма %s (%s)' % (ORD_BG[k - 1], rng),
                    'title_csl': 'Каѳі́сма %s' % cs_num(k),
                    'csr_source': None, 'csl_source': CS_SRC_PS, 'units': units})
        print('  катизма %2d  псалми %3d–%3d  молитви: %d блока' % (k, a, b, len(pr)))

    end = next(h for h in heads if h[2] == 'end')
    ls = pdf_ucs.lines(doc, end[0], len(doc) - 1)
    out.append({'sec': 321, 'tab': 'psaltir', 'title_bg': 'След прочитане на Псалтира',
                'title_csl': 'По соверше́нїи же нѣ́коликихъ каѳі́смъ, и҆лѝ все́й ѱалти́ри',
                'csr_source': None, 'csl_source': CS_SRC_PR,
                'units': [{'n': 0, 'title_csl': None, 'title_bg': None, 'title_cs': None,
                           'csr': [], 'bg': [], 'csl': cs_blocks(ls), 'sources': []}]})
    json.dump(out, open(os.path.join(W, 'psaltir.json'), 'w', encoding='utf-8'),
              ensure_ascii=False, indent=1)
    print('→ work/psaltir.json')


if __name__ == '__main__':
    main()
