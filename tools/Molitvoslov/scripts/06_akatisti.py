"""Акатистите → work/akatisti.json (в същия вид като aligned.json).

    цс с граждански шрифт   „Канонник или полный молитвослов" (.epub)
    бг                      pravoslavieto.com/molitvoslov/akatistnik/

⚠ ТРЕТИ ЕЗИК: `csr` — църковнославянски с ГРАЖДАНСКИ шрифт (с ударения).
„Канонник" не е в истински цс шрифт, а точно това е вариантът, който
потребителят искаше като възможност („цс с граждански шрифт").

⚠ ПОДРАВНЯВАНЕТО Е ПО НОМЕР НА КОНДАКА/ИКОСА, не по гадаене: „Кондак 5" ↔
„Конда́к 5" и в двата извора. Канонът (песни 1–9) и молитвите накрая са само
в цс — бг извор ги няма.

⚠ Акатистът в „Канонник" е ЦЯЛО ПОСЛЕДОВАНИЕ: песни 1–6 на канона, кондаците
и икосите, песни 7–9, молитвите. Вечерните стихири отпреди него (отделни
файлове в книгата, index_split_010 и 012) НЕ влизат — те са за общественото
богослужение, не за четенето у дома.

Размекта в „Канонник":
    <p class="paragraph"><span>Конда́к 1</span></p>   етикет → нова единица
    <span>Ирмо́с:</span> …                            указание насред текста
    <span>В</span>збра́нной                           червената начална буква —
                                                      СЛИВА се с думата (четецът
                                                      сам оцветява първата буква)
"""
import html
import json
import os
import re
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
W = os.path.join(ROOT, 'work')
KANONNIK = os.path.join(ROOT, 'input', 'Канонник или полный молитвослов.gen.epub')
KANONNIK_URL = 'https://azbyka.ru/otechnik/Pravoslavnoe_Bogosluzhenie/kanonnik-ili-polnyj-molitvoslov/'

# Откъде е заглавието на акатиста, ако не е от главата с текста.
TITLE_FILE = {101: 'index_split_010.xhtml', 102: 'index_split_012.xhtml'}

# (id, файл в Канонник или None, бг страница или None, бг заглавие)
AKATHISTS = [
    (101, 'index_split_011.xhtml', None,
     'Акатист към нашия Господ Иисус Христос'),
    (102, 'index_split_013.xhtml', 'akatistnik__Presveta_Bogoroditsa',
     'Акатист към Пресвета Богородица'),
    (103, 'index_split_021.xhtml', 'akatistnik__sv_Nikolaj',
     'Акатист към свети Николай Чудотворец'),
    (104, None, 'akatistnik__Slava_Bogu_za_Vsichko',
     'Благодарствен акатист „Слава Богу за всичко“'),
    (105, None, 'akatistnik__Bog',
     'Акатист към Всемогъщия Бог (когато ни сполети печал)'),
]

ACUTE = '́'
RE_P = re.compile(r'<(h2)[^>]*>(.*?)</h2>|<p class="paragraph">(.*?)</p>', re.S)
RE_LABEL = re.compile(
    r'^(Пе́?снь|Пе́снь|Конда́?к|Кондак|И́?кос|Ико́с|Икос|Моли́?тва|Молитва|Кано́н)\b', re.I)


def plain(s):
    return html.unescape(re.sub(r'<[^>]+>', '', s)).strip()


def key_of(label):
    """„Конда́к 5, гла́с 8:" → ('kondak', 5); „И́кос 1" → ('ikos', 1)."""
    t = label.replace(ACUTE, '').lower()
    m = re.match(r'(кондак|икос)\s+(\d+)', t)
    return (('kondak' if m.group(1) == 'кондак' else 'ikos'), int(m.group(2))) if m else None


# Печатни грешки в „Канонник" — поправят се ТУК, не в базата, за да оцелеят
# при пресглобяване. Двойките са дословни (с ударенията).
CSR_ERRATA = [
    # Кондак 1 на акатиста към Богородица: „ти" (на Тебе), не „и"
    # (забелязано от потребителя, 28.09.2026).
    ('воспису́ем и раби́', 'воспису́ем ти раби́'),
]


def csr_html(inner):
    """Абзац от Канонник → html с винени указания; началната буква се слива."""
    inner = re.sub(r'^\s*<span>([^<]{1,2})</span>', r'\1', inner)
    inner = re.sub(r'<span>(.*?)</span>', r'<span class="rubric">\1</span>', inner, flags=re.S)
    inner = re.sub(r'<(?!/?span\b)[^>]+>', '', inner)
    inner = re.sub(r'\s+', ' ', inner).strip()
    for wrong, right in CSR_ERRATA:
        inner = inner.replace(wrong, right)
    return inner


def parse_kanonnik(fname):
    z = zipfile.ZipFile(KANONNIK)
    t = z.read(fname).decode('utf-8')
    units, cur = [], None
    for m in RE_P.finditer(t):
        if m.group(1):                      # <h2> — заглавието на главата
            continue
        inner = m.group(3)
        # ⚠ Етикетът може да е и В НАЧАЛОТО на абзаца, последван от текста
        # („<span>Конда́к 2:</span> Ви́дя вдови́цу…" — акатистът към Иисус
        # Христос). Тогава абзацът се дели: етикетът → нова единица, остатъкът
        # → нейният първи блок.
        lead = re.match(r'\s*<span>([^<]*)</span>\s*(\S.*)$', inner, re.S)
        if lead and RE_LABEL.match(plain(lead.group(1))) and key_of(plain(lead.group(1))):
            label = plain(lead.group(1))
            cur = {'title': label.rstrip(':'), 'key': key_of(label), 'blocks': []}
            units.append(cur)
            cur['blocks'].append({'kind': 'text', 'html': csr_html(lead.group(2))})
            continue
        whole = re.fullmatch(r'\s*<span>(.*?)</span>\s*', inner, re.S)
        if whole and RE_LABEL.match(plain(whole.group(1))):
            cur = {'title': plain(whole.group(1)).rstrip(':'), 'key': key_of(plain(whole.group(1))),
                   'blocks': []}
            units.append(cur)
            continue
        if cur is None:
            cur = {'title': None, 'key': None, 'blocks': []}
            units.append(cur)
        if whole:
            cur['blocks'].append({'kind': 'rubric', 'html': plain(whole.group(1))})
        else:
            cur['blocks'].append({'kind': 'text', 'html': csr_html(inner)})
    return units


RE_BG_LABEL = re.compile(r'^(?:Статия [а-я]+,?\s*)?(Кондак|Икос)\s+(\d+)\s*$')
RE_BG_STATIA = re.compile(r'^Статия [а-я]+,?\s*$')


def parse_bg(page):
    blocks = json.load(open(os.path.join(W, 'bg_pages', page + '.json'), encoding='utf-8'))
    units, cur, last_kondak = [], None, 0
    for b in blocks:
        if b['kind'] == 'head':
            continue
        t = b['text']
        m = RE_BG_LABEL.match(t)
        if m or RE_BG_STATIA.match(t):
            if m:
                kind = 'kondak' if m.group(1) == 'Кондак' else 'ikos'
                n = int(m.group(2))
            else:
                # ⚠ „Статия четвърта," без номер — това е икосът след последния
                # кондак (у акатиста на Богородица липсва „Икос 10").
                kind, n = 'ikos', last_kondak
            if kind == 'kondak':
                last_kondak = n
            cur = {'key': (kind, n), 'title': '%s %d' % ('Кондак' if kind == 'kondak' else 'Икос', n),
                   'blocks': []}
            units.append(cur)
            continue
        if cur is None:
            cur = {'key': None, 'title': None, 'blocks': []}
            units.append(cur)
        # ⚠ Печатна грешка в извора: цифрата „0" вместо буквата „О" в
        # началото на кондак 13 на св. Николай („0, пресвети и пречудни…").
        t = re.sub(r'^0, ', 'О, ', t)
        cur['blocks'].append({'kind': b['kind'], 'text': t})
    return units


def main():
    out = []
    for sid, kfile, bgpage, title_bg in AKATHISTS:
        csr = parse_kanonnik(kfile) if kfile else []
        bg = parse_bg(bgpage) if bgpage else []
        bg_by_key = {u['key']: u for u in bg if u['key']}
        bg_url = ('https://www.pravoslavieto.com/molitvoslov/akatistnik/%s.htm'
                  % bgpage.split('__', 1)[1]) if bgpage else None
        units = []
        if csr:
            used = set()
            for u in csr:
                b = bg_by_key.get(u['key']) if u['key'] else None
                # ⚠ Кондак 1 се повтаря накрая („И па́ки конда́к 1-й") — бг
                # текстът отива само при ПЪРВОТО срещане.
                if b and u['key'] in used:
                    b = None
                if b:
                    used.add(u['key'])
                units.append({'title_csl': u['title'], 'title_bg': b['title'] if b else None,
                              'csr': u['blocks'], 'bg': b['blocks'] if b else [],
                              'sources': [bg_url] if b else []})
            missing = [k for k in bg_by_key if k not in used]
            if missing:
                print('  ⚠ %d: бг без цс двойка: %s' % (sid, missing))
        else:
            for u in bg:
                units.append({'title_csl': None, 'title_bg': u['title'], 'csr': [],
                              'bg': u['blocks'], 'sources': [bg_url]})
        for i, u in enumerate(units):
            u['n'] = i
        title_csl = None
        if kfile:
            # ⚠ Заглавието на акатиста стои в ПРЕДИШНАТА глава на книгата
            # (вечерните стихири), а главата с текста започва с канона —
            # взето оттам, заглавието беше „Кано́н благода́рный…".
            z = zipfile.ZipFile(KANONNIK)
            tfile = TITLE_FILE.get(sid, kfile)
            h = re.search(r'<h2[^>]*>(.*?)</h2>', z.read(tfile).decode('utf-8'), re.S)
            title_csl = plain(h.group(1)) if h else None
        out.append({'sec': sid, 'tab': 'akatisti', 'title_bg': title_bg, 'title_csl': title_csl,
                    'csr_source': KANONNIK_URL if kfile else None, 'units': units})
        paired = sum(1 for u in units if u['bg'] and u['csr'])
        print('  %d  единици %3d  (цс %3d · бг %3d · двойки %2d)  %s' % (
            sid, len(units), sum(1 for u in units if u['csr']),
            sum(1 for u in units if u['bg']), paired, title_bg))
    json.dump(out, open(os.path.join(W, 'akatisti.json'), 'w', encoding='utf-8'),
              ensure_ascii=False, indent=1)
    print('→ work/akatisti.json')


if __name__ == '__main__':
    main()
