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


BG_ERRATA = [('Радвай сети', 'Радвай се ти'), ('радвй се', 'радвай се'),
             ('радавй се', 'радвай се'), ('радай се', 'радвай се'),
             ('радвай се.гръме', 'радвай се, гръме'), ('сетлина', 'светлина'),
             ('лъч затези', 'лъч за тези'),
             ('славимтъй: Радвайсе, избавителюотвечнотоубожество;',
              'славим тъй: Радвай се, избавителю от вечното убожество;')]
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
        # ⚠ Още печатни грешки в извора — без тях възгласите не се разпознават
        # и икосът не се дели на редове като в цс (намерени 28.09.2026).
        for wrong, right in BG_ERRATA:
            t = t.replace(wrong, right)
        # OCR брак: „ь" вместо „ъ" („мъртьвците", „застьпнико"). В
        # българския „ь" стои САМО пред „о", тъй че правилото е безопасно.
        t = re.sub(r'ь(?!о)', 'ъ', t)
        cur['blocks'].append({'kind': b['kind'], 'text': t})
    return units


CSL_PATH = os.path.join(W, 'akatisti_csl.json')
MISMATCH = []


# Началото на всеки ред-възглас в икосите: „Ра́дуйся…" / „Иису́се…"
# (цс с граждански шрифт) и „Радвай се…" (бг) — след край на изречение.
RE_CHAIRE = re.compile(
    r'(?<=[:.!;,]) (?=(?:[Рр]а́дуйся|[Рр]адуйся|[Рр]адвай се|Иису́се|Иисусе)'
    r'(?!\s*!)(?![,!]?\s+и\s+со\s))')
# ⚠ Вторият възглас от двойката е с МАЛКА буква („…: ра́дуйся, е́юже…").
# ⚠ Нито „ра́дуйся, и со безпло́тным…" (Икос 1 към Богородица в Канонника).
# ⚠ „ра́дуйся!" вътре във въведението („рещи Богородице: ра́дуйся!") НЕ е
# ред-възглас — затова не се реже, ако подир думата стои удивителна.


def split_like(blocks, target):
    """Един слят абзац с възгласите → по ред на възглас, КАКТО Е в цс шрифт.

    ⚠ Канонникът (и бг изворът) пестят място и сливат целия икос в един
    абзац, а цс шрифтът дава всеки „Радуйся"/„Иисусе" на свой ред с червена
    буква — двата езика вървяха с различни височини и зееха. (Указание на
    потребителя, 28.09.2026: навсякъде като в цс шрифт.)
    ⚠ Приема се САМО ако броят редове излезе точно колкото в цс шрифт;
    иначе абзацът остава, какъвто е — по-добре слят, отколкото насечен
    на грешни места."""
    if len(blocks) >= target:
        return blocks, False
    out = []
    for b in blocks:
        if b.get('kind') != 'text':
            out.append(b)
            continue
        key = 'html' if 'html' in b else 'text'
        parts = [x.strip() for x in RE_CHAIRE.split(b[key]) if x.strip()]
        # ⚠ Всеки ред-възглас е с ГЛАВНА буква, както в цс шрифт — инак
        # вторият от двойката („радвай се…") остава без червена буква.
        parts = parts[:1] + [x[:1].upper() + x[1:] for x in parts[1:]]
        out += [dict(b, **{key: x}) for x in parts]
    # ⚠ Допуска се разлика до ДВА реда: Канонникът е изпуснал по някой
    # възглас (Икос 1 и 5 към Иисус Христос, Икос 2 към Богородица). Там
    # редовете пак са ред по ред — по-добре почти изравнени, отколкото слят
    # абзац срещу четиринайсет реда.
    if len(out) > len(blocks) and abs(len(out) - target) <= 2:
        return out, len(out) == target
    return blocks, False


# Възгласът преди всеки кондак и икос в бг акатиста към св. Николай.
RE_BG_HINT = re.compile(r'^(Светителю отче Николае, моли Бога за нас\.)\s*(.*)$', re.S)


def split_hints(blocks):
    """„Светителю отче Николае, моли Бога за нас. Ти изгря…" → възгласът се
    МАХА, а стихът остава.

    ⚠ Такъв възглас се казва на КАНОНИТЕ, не на акатистите — в бг извора
    (pravoslavieto.com) е грешка на съставителя. (Решение на потребителя,
    28.09.2026; първо беше отделен като посивена подсказка.)"""
    out = []
    for b in blocks:
        m = RE_BG_HINT.match(b.get('text', '')) if b.get('kind') == 'text' else None
        if m:
            if m.group(2).strip():
                out.append(dict(b, text=m.group(2).strip()))
        else:
            out.append(b)
    return out


def attach_csl(sid, units):
    """Цс шрифтът (06b_akatisti_csl.py) → поле `csl` на единиците.

    ⚠ ПО ВИД И НОМЕР, не по ред — цс страницата няма канона. Каквото няма
    двойка в Канонника (тропарът; Икос 9 при акатиста към Иисус Христос, който
    Канонникът е изпуснал), влиза като НОВА единица на мястото си."""
    if not os.path.exists(CSL_PATH):
        return
    data = json.load(open(CSL_PATH, encoding='utf-8')).get(str(sid))
    if not data:
        return
    for u in units:
        u.setdefault('csl', [])
    by_key = {}
    for u in units:
        k = key_of(u['title_csl'] or '')
        if k and k not in by_key:
            by_key[k] = u
    prayers = [u for u in units if (u['title_csl'] or '').replace(ACUTE, '').startswith('Молитва')]
    rubric = lambda t: {'kind': 'rubric', 'html': t}
    k13 = by_key.get(('kondak', 13))
    for cu in data['units']:
        key = tuple(cu['key']) if cu['key'] else None
        if cu['repeat'] and k13 is not None:
            # Повторените накрая Икос 1 и Кондак 1 — целите, при Кондак 13.
            k13['csl'] += [rubric(cu['title'])] + cu['blocks']
            continue
        target = None
        if key and key[0] in ('kondak', 'ikos'):
            target = by_key.get(key)
        elif key and key[0] == 'prayer':
            target = prayers[key[1] - 1] if key[1] <= len(prayers) else None
        if target is not None:
            target['csl'] = cu['blocks']
            target['title_cs'] = cu['title']
            n = len(cu['blocks'])
            for lang in ('csr', 'bg'):
                if target.get(lang):
                    target[lang], ok = split_like(target[lang], n)
                    if len(target[lang]) != n:
                        MISMATCH.append((sid, cu['title'], lang, len(target[lang]), n))
            continue
        new = {'title_csl': None, 'title_cs': cu['title'], 'title_bg': None,
               'csr': [], 'bg': [], 'csl': cu['blocks'], 'sources': []}
        if key and key[0] == 'troparion':
            units.insert(0, new)
        elif key and key[0] == 'ikos':
            prev = by_key.get(('kondak', key[1]))
            units.insert(units.index(prev) + 1 if prev else len(units), new)
            by_key[key] = new
            # ⚠ Печатна грешка в Канонника (акатистът към Иисус Христос):
            # Икос 9 стои ВЪТРЕ в Кондак 9, с етикет „Пе́снь 9:" вместо
            # „И́кос 9:". Блокът се премества тук, без грешния етикет.
            if prev is not None:
                for b in list(prev['csr']):
                    m = re.match(r'(?:<span class="rubric">)?Пе́снь \d+:(?:</span>)?\s*(.*)$',
                                 b['html'], re.S)
                    if m and b['kind'] == 'text':
                        prev['csr'].remove(b)
                        new['csr'].append({'kind': 'text', 'html': m.group(1)})
                        new['title_csl'] = 'И́кос %d' % key[1]
        else:
            units.append(new)


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
        attach_csl(sid, units)
        for u in units:
            u['bg'] = split_hints(u['bg'])
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
        csl_src = None
        if os.path.exists(CSL_PATH):
            csl_src = (json.load(open(CSL_PATH, encoding='utf-8')).get(str(sid)) or {}).get('source')
        out.append({'sec': sid, 'tab': 'akatisti', 'title_bg': title_bg, 'title_csl': title_csl,
                    'csr_source': KANONNIK_URL if kfile else None,
                    'csl_source': csl_src, 'units': units})
        paired = sum(1 for u in units if u['bg'] and u['csr'])
        print('  %d  единици %3d  (цс %3d · бг %3d · двойки %2d)  %s' % (
            sid, len(units), sum(1 for u in units if u['csr']),
            sum(1 for u in units if u['bg']), paired, title_bg))
    for m in MISMATCH:
        print('  ⚠ %d %-14s %-3s редове %2d, в цс шрифт %2d' % m)
    json.dump(out, open(os.path.join(W, 'akatisti.json'), 'w', encoding='utf-8'),
              ensure_ascii=False, indent=1)
    print('→ work/akatisti.json')


if __name__ == '__main__':
    main()
