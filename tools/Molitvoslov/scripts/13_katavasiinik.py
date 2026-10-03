#!/usr/bin/env python3
"""Катавасийник (PDF, Ucs) → work/katavasiinik.json, таб „Богослужебни".

Изворът: input/newBooks2/Katavasiinik.pdf (psaltbg.blogspot.com).

⚠ ДЕЛЕНИЕТО СЛЕДВА СЪДЪРЖАНИЕТО НА КНИГАТА (стр. 103–107) — всеки негов
ред е един раздел, а групите му са групите в съдържанието. Страницата е само
ориентир: разделът почва от ЗАГЛАВИЕТО си на тази страница (`TOC` по-долу —
препис от съдържанието, сверен ред по ред).

⚠ Само Ucs шрифтовете минават през ucs.decode. Цифрите (дати, „Глас 4",
номера на стихове) са в Georgia/Times/Izhitsa — декодирани като Ucs, те
стават букви.

⚠ Българските бележки са набрани със СЛАВЯНСКИЯ шрифт — „ѧ", „ꙋ", „Ѻ"
стоят вместо „я", „у", „О". Връщат се само в думи БЕЗ надредни знаци (в
заглавията) и в абзаци, които са почти изцяло без тях (бележките);
славянският текст не се пипа.
"""
import html
import json
import re
import sys
from pathlib import Path

import pymupdf

import ucs
from pdf_ucs import MARKS, bare, runs_html

HERE = Path(__file__).resolve().parent
PDF = HERE.parent / 'input' / 'newBooks2' / 'Katavasiinik.pdf'
W = HERE.parent / 'work'
SRC = 'https://psaltbg.blogspot.com/2015/09/blog-post_77.html'
BOOK = 'Катавасийник'
FIRST_SEC = 4001
FIRST_PAGE, LAST_PAGE = 7, 102       # номерата в книгата (от 1)
RED = 0xff0000
UNKNOWN = {}

G_OBSHTI = 'Общи катавасии през годината'
G_MES = 'Катавасии по месецослова'
G_POST = 'Катавасии по Постния триод'
G_CVET = 'Катавасии по Цветния триод'
G_POLI = 'Полиелейни псалми'
G_VEL = 'Величания с избрани псалми по месецослова и Триода'
G_VEL_O = 'Величания общи'

# (група, заглавие, страница, начало на заглавния ред в текста — голо, без знаци)
TOC = [
    (G_OBSHTI, 'Отверзу уста моя', 7, 'Ѿверзꙋ ѹста моѧ'),
    (G_MES, '8 септември — Рождество на Пресвета Владичица наша Богородица и Приснодева Мария', 9, '8 септември'),
    (G_MES, '14 септември — Въздвижение на Честния и Животворящ Кръст Господен', 10, '14 септември'),
    (G_MES, '21 ноември — Въведение в храма на Пресвета Владичица наша Богородица и Приснодева Мария', 12, '21 ноември'),
    (G_MES, '25 декември — Рождество по плът на Господа Бога и Спасителя наш Иисуса Христа', 15, '25 декември'),
    (G_MES, '6 януари — Свето Богоявление на Господа Бога и Спасителя наш Иисуса Христа', 19, '6 ꙗнꙋари'),
    (G_MES, '2 февруари — Сретение на Господа и Спасителя наш Иисуса Христа', 24, '2 феврꙋари'),
    (G_MES, '25 март — Благовещение на Пресвета Владичица наша Богородица и Приснодева Мария', 26, '25 март'),
    (G_MES, '6 август — Свето Преображение на Господа Бога и Спасителя наш Иисуса Христа', 28, '6 авгꙋст'),
    (G_MES, '15 август — Успение на Пресвета Владичица наша Богородица и Приснодева Мария', 30, '15 авгꙋст'),
    (G_POST, 'Неделя на блудния син', 35, 'Неделѧ на блꙋдниѧ син'),
    (G_POST, 'Неделя Месопустна', 37, 'Неделѧ Месопꙋстна'),
    (G_POST, 'Неделя Сиропустна', 39, 'Неделѧ Сиропꙋстна'),
    (G_POST, 'Първа неделя на Великия пост — на Православието', 41, 'Първа неделѧ на Великиѧ пост'),
    (G_POST, 'Неделя Кръстопоклонна', 43, 'Неделѧ Кръстопоклонна'),
    (G_POST, 'Лазарова събота', 45, 'Лазарова Събота'),
    (G_POST, 'Вход Господен в Иерусалим — Неделя Ваия', 47, 'Вход Господен в Иерꙋсалим'),
    (G_POST, 'Свети и Велики Четвъртък', 49, 'Свети и Велики Четвъртък'),
    (G_POST, 'Света и Велика Събота', 51, 'Света и Велика Събота'),
    (G_CVET, 'Света и Велика Неделя Пасха', 54, 'Света и Велика Неделѧ Пасха'),
    (G_CVET, 'Сряда на четвърта седмица — Преполовение', 56, 'Срѧда на четвърта седмица'),
    (G_CVET, 'Четвъртък на шеста седмица — Възнесение Господне', 58, 'Четвъртък на шеста седмица'),
    (G_CVET, 'Неделя Петдесетница', 59, 'Неделѧ Петдесетница'),
    (G_POLI, 'Псалом 134', 64, 'Псалом 134'),
    (G_POLI, 'Псалом 135', 66, 'Псалом 135'),
    (G_POLI, 'Псалом 136', 68, 'Псалом 136'),
    (G_VEL, '8 септември — Рождество на Пресвета Богородица', 70, '8 септември'),
    (G_VEL, '14 септември — Въздвижение на Честния Кръст Господен', 71, '14 септември'),
    (G_VEL, '21 ноември — Въведение на Пресвета Богородица в храма', 73, '21 ноември'),
    (G_VEL, '25 декември — Рождество на Господа нашего Иисуса Христа', 75, '25 декември'),
    (G_VEL, '6 януари — Богоявление Господне', 77, '6 ꙗнꙋари'),
    (G_VEL, '2 февруари — Сретение Господне', 78, '2 феврꙋари'),
    (G_VEL, '25 март — Благовещение на Пресвета Богородица', 80, '25 март'),
    (G_VEL, 'Неделя Ваия (Връбница)', 82, 'Неделѧ Ваиѧ'),
    (G_VEL, 'Томина неделя', 84, 'Томина неделѧ'),
    (G_VEL, 'Възнесение Господне', 85, 'Възнесение Господне'),
    (G_VEL, 'Неделя Петдесетница', 87, 'Неделѧ Петдесетница'),
    (G_VEL, '24 юни — Рождение на св. Иоан Кръстител', 89, '24 юни'),
    (G_VEL, '29 юни — Свети първовърховни апостоли Петър и Павел', 90, '29 юни'),
    (G_VEL, '6 август — Преображение Господне', 92, '6 авгꙋст'),
    (G_VEL, '15 август — Успение на Пресвета Богородица', 93, '15 авгꙋст'),
    (G_VEL, '29 август — Отсичане главата на св. Иоан Кръстител', 94, '29 авгꙋст'),
    (G_VEL_O, 'На мъченик', 96, 'На мъченик'),
    (G_VEL_O, 'На светител', 98, 'На светител'),
    (G_VEL_O, 'На преподобен', 99, 'На преподобен'),
    (G_VEL_O, 'На Ангелите', 101, 'На Ангелите'),
]

# Заглавията на групите в самия текст — те са в съдържанието, не в раздел.
GROUP_LINES = {'КАТАВАСИИ', 'ѺБЩИ КАТАВАСИИ ПРЕЗ ГОДИНАТА', 'Катавасии по месецослова.',
               'КАТАВАСИИ ПО ПОСТНИѦ ТРИОД.', 'КАТАВАСИИ ПО ЦВЕТНИѦ ТРИОД', 'ПОЛИЕЛЕИ',
               'Полиелейни псалми.', 'Величаниѧ с избрани псалми по месецослова и',
               'Триода.', 'Величаниѧ общи.'}

# Над кой раздел стои и заглавието на групата си — (горе, долу), центрирани.
HEAD_OVER = {'Псалом 134': ('ПОЛИЕЛЕЙ', 'Полиелейни псалми')}

BG_MAP = str.maketrans({'ѧ': 'я', 'Ѧ': 'Я', 'ꙋ': 'у', 'Ꙋ': 'У', 'ѻ': 'о', 'Ѻ': 'О',
                        'ꙗ': 'я', 'Ꙗ': 'Я', 'ѹ': 'у', 'Ѹ': 'У'})


def bg_words(s):
    """„ѧ/ꙋ/Ѻ" → „я/у/О" в думите без надредни знаци (българските)."""
    return re.sub(r'[^\s<>]+', lambda m: m.group(0) if MARKS.search(m.group(0))
                  else m.group(0).translate(BG_MAP), s)


def is_bg_para(h):
    words = re.sub(r'<[^>]+>', ' ', h).split()
    words = [w for w in words if re.search(r'[^\W\d_]', w)]
    if not words:
        return False
    return sum(1 for w in words if MARKS.search(w)) <= len(words) * 0.5


def page_lines(doc):
    """Всички редове [(стр., x, заглавие, runs, сурово)] — без номерата на страниците."""
    out = []
    for pno in range(FIRST_PAGE - 1, LAST_PAGE):
        rows = {}
        for bl in doc[pno].get_text('dict')['blocks']:
            for ln in bl.get('lines', []):
                if ln['bbox'][1] < 50:
                    continue
                for s in ln['spans']:
                    t = s['text']
                    if 'Ucs' in s['font']:
                        for c, n in ucs.unknown_chars(t).items():
                            UNKNOWN[c] = UNKNOWN.get(c, 0) + n
                        t = ucs.decode(t)
                    rows.setdefault(round(ln['bbox'][1]), []).append(
                        (s['bbox'][0], s['color'] == RED, s['size'], t, s['bbox'][2]))
        for y in sorted(rows):
            raw = sorted(rows[y])
            sp = []
            for i, (x0, r, sz, t, x1) in enumerate(raw):
                if i and x0 - raw[i - 1][4] > 2 and not t.startswith(' ') \
                        and not raw[i - 1][3].endswith(' '):
                    t = ' ' + t
                sp.append((x0, r, sz, t))
            text = ''.join(t for *_, t in sp)
            if not text.strip():
                continue
            vis = [(r, sz) for _, r, sz, t in sp if t.strip()]
            heading = all(r for r, _ in vis) and max(sz for _, sz in vis) >= 20 \
                and not re.match(r'\s*\d+\.', text)
            out.append((pno + 1, sp[0][0], heading, [(r, t) for _, r, _, t in sp], text,
                        max(sz for _, sz in vis)))
    return out


def is_song(text):
    b = bare(text)
    return 'Пѣснь' in b or 'Гласъ' in b or b.startswith('Псалом')


def verse_html(h):
    """„1. Рабѝ…" — номерът и първата буква червени, както в книгата.

    ⚠ В PDF-а номерът ту е червен, ту черен, а с него понякога е слята и
    буквицата (`<span>1. Ѿ</span>`) — затова таговете в началото се махат и
    номерът и буквата се слагат наново.
    """
    m = re.match(r'((?:<[^>]+>|\s)*)(\d+\.)', h)
    if not m:
        return h
    rest = h[m.end():]
    # Таговете до края на първата буква (с надредните ѝ знаци) отпадат.
    k = re.search(r'[^\W\d_][̀-ͯ҃-҉ⷠ-ⷿ꙯-ꙿ]*', re.sub(r'<[^>]+>', lambda t: '\0' * len(t.group(0)), rest))
    if not k:
        return h
    head = re.sub(r'<[^>]+>', '', rest[:k.end()]).lstrip()
    tail = re.sub(r'^</span>', '', rest[k.end():])
    return '<span class="rubric">%s</span> <span class="rubric">%s</span>%s' % (
        m.group(2), head, tail)


def link_next_feast(out):
    """„гледай по-долу на 14 септември" (8.IX) → връзка, която ОТВАРЯ
    раздела за Въздвижение на мястото на текущия (`molgo:`), а не в панел
    отдолу: читателят продължава там и в 8.IX няма какво да се връща.
    (Указание на потребителя, 03.10.2026.) Адресът е по ИМЕ — както
    вътрешните препратки в Часослова."""
    target = next(s for s in out if s['title_bg'].startswith('14 септември'))
    n = 0
    for s in out:
        for u in s['units']:
            for b in u['csl']:
                h = re.sub(r'(гледай по-долу на 14 септември)',
                           r'<a href="molgo:%s/%s" class="rubric">\1</a>'
                           % (BOOK, target['title_bg']), b['html'])
                if h != b['html']:
                    b['html'] = h
                    n += 1
    if n != 1:
        sys.exit('⚠ Катавасийник: очаквана 1 препратка към 14 септември, има %d' % n)


def main():
    doc = pymupdf.open(PDF)
    ls = page_lines(doc)

    # Началото на всеки раздел — индексът на заглавния му ред.
    starts, pre, ends, i = [], [], [], 0
    for grp, title, page, anchor in TOC:
        # ⚠ „Ѿве́рзꙋ ѹ҆ста̀ моѧ̑..." е с червена буквица и черно продължение,
        # тоест не е изцяло червен ред — затова не се иска `heading`.
        while i < len(ls) and not (ls[i][0] >= page
                                   and bare(ls[i][4]).startswith(anchor)):
            i += 1
        if i == len(ls) or ls[i][0] > page + 1:
            sys.exit('⚠ няма заглавие „%s" на стр. %d' % (anchor, page))
        # ⚠ Бележка под заглавието на ГРУПАТА („След всеки стих от
        # полиелейните псалми…") стои ПРЕДИ заглавието на първия раздел —
        # тя е негово начало, не опашка на предния.
        j = i
        while starts and j - 1 > starts[-1] and not (ls[j - 1][2] and ls[j - 1][4].strip()
                                                    in GROUP_LINES):
            j -= 1
        pre.append(list(range(j, i)) if starts and j - 1 > starts[-1] else [])
        ends.append(j - 1 if pre[-1] else i)
        starts.append(i)
    starts.append(len(ls))
    ends = ends[1:] + [len(ls)]

    out = []
    for k, (grp, title, page, _) in enumerate(TOC):
        # заглавният ред е в `title`
        # ⚠ „Псалом 134." (само той) остава В ТЕКСТА като заглавие на своята част —
        # след бележките над него, както в книгата (указание на потребителя).
        own = starts[k] if title == 'Псалом 134' else starts[k] + 1
        chunk = [ls[q] for q in pre[k]] + ls[own:ends[k]]
        units = [{'title': None, 'blocks': []}]
        para = None
        in_title = True             # заглавните редове на самия раздел
        prev_note = False

        def flush():
            nonlocal para
            if para:
                h = runs_html(para)
                if re.match(r'(?:<span class="rubric">)?\d+\.', h):
                    h, kind = verse_html(h), 'text'
                else:
                    kind = 'text'
                if is_bg_para(h):
                    # ⚠ Българските бележки са УКАЗАНИЯ — винени и по-дребни,
                    # както в другите книги (указание на потребителя), макар в
                    # книгата да са черни с червена буквица.
                    h, kind = bg_words(h), 'rubric'
                if h:
                    units[-1]['blocks'].append({'kind': kind, 'html': h})
            para = None

        for pno, x, heading, runs, text, size in chunk:
            t = text.strip()
            if heading and t in GROUP_LINES:
                continue
            if heading:
                # Дата + име на празника = заглавието на раздела. Бележките
                # (кегел 22) не са част от него.
                if in_title and not is_song(t) and size >= 23:
                    continue
                flush()
                if is_song(t):
                    units.append({'title': bg_words(re.sub(r'\s+', ' ', t)), 'blocks': []})
                else:               # бележка насред раздела („Тоѧ псалом се пее…")
                    note = html.escape(bg_words(re.sub(r'\s+', ' ', t)), quote=False)
                    bl = units[-1]['blocks']
                    if prev_note and bl:        # бележка на два реда = един абзац
                        bl[-1]['html'] += ' ' + note
                    else:
                        bl.append({'kind': 'rubric', 'html': note})
                    prev_note = True
                continue
            prev_note = False
            in_title = False
            new = text.startswith('  ') or re.match(r'\s*\d+\.', text)
            if new or para is None:
                flush()
                para = []
            elif para and para[-1][1].rstrip().endswith('-') \
                    and re.match(r'\s*[^\W\d_]', ''.join(t2 for _, t2 in runs)):
                # Пренесена дума („пра́зд-|нство") — тирето отпада.
                r0, t0 = para[-1]
                para[-1] = (r0, t0.rstrip()[:-1])
                runs = [(runs[0][0], runs[0][1].lstrip())] + runs[1:]
            elif para and not para[-1][1].endswith(' '):
                para.append((False, ' '))
            para.extend((r, t2) for r, t2 in runs)
        flush()
        # Червени редове, продължили предния абзац без нов ред („(три́жды)"),
        # и празните блокове се сливат/махат.
        units = [u for u in units if u['blocks'] or u['title']]
        # Заглавието на групата над първия ѝ раздел (указание на потребителя).
        if title in HEAD_OVER:
            units[0]['title'] = HEAD_OVER[title][1]
            units.insert(0, {'title': HEAD_OVER[title][0], 'blocks': []})
        out.append({'sec': FIRST_SEC + k, 'tab': 'bogosluzhebni', 'book': BOOK, 'grp': grp,
                    'title_bg': title, 'title_csl': None, 'csr_source': None,
                    'csl_source': SRC,
                    'units': [{'n': j, 'title_csl': u['title'], 'title_bg': None,
                               'title_cs': None, 'csl': u['blocks'], 'csr': [], 'bg': [],
                               'sources': []}
                              for j, u in enumerate(units)]})
    link_next_feast(out)
    if UNKNOWN:
        print('  ⚠ непознати означения', UNKNOWN)
    (W / 'katavasiinik.json').write_text(json.dumps(out, ensure_ascii=False, indent=1),
                                         encoding='utf-8')
    print('→ work/katavasiinik.json: %d раздела, %d песни/части, %d блока' % (
        len(out), sum(len(s['units']) for s in out),
        sum(len(u['csl']) for s in out for u in s['units'])))


if __name__ == '__main__':
    main()
