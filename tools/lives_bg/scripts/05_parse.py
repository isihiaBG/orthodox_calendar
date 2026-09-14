#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Разчита свалените страници и сглобява по ЕДНО четиво на светия.

Вход:  `cache/` (свалено от 04_fetch.py)   — мрежата НЕ се пипа
Изход: `work/parsed/<key>.json` + отчет `work/parse_report.md`

⚠ Този скрипт се пуска МНОГО ПЪТИ, докато формата се уталожи. Затова не тегли
нищо и не пише в базата — двете скъпи стъпки стоят от двете му страни.

## Какво сглобява

Една страница често носи НЯКОЛКО жития на един светия. При Онуфрий Габровски
са три — „Кратко животоописание", „Житие на св. Онуфрий Габровски" и „Житие и
страдание…". Те стават раздели на ЕДИН текст, а не отделни записи: за
читателя това е един светия, а трите четива са различно подробни разкази за
него.

⚠ ЙЕРАРХИЯТА В ИЗВОРА Е ОБЪРНАТА — на същата страница `<h3>` стоят ПРЕДИ
`<h2>`. Тъй че разделите се подреждат по РЕДА В ДОКУМЕНТА, а нивото на тага
се пренебрегва. Подредено по ниво, пълното житие би скочило пред краткото.

## Изходният формат

Само таговете, които четецът наистина стилизира (виж `reader_styles.dart`):
`<h3>` за заглавие на раздел, `<p>` за абзац, `<strong>`/`<em>`/`<i>` вътре.
⚠ `<h1>`/`<h2>`/`<h4>` НЯМАТ стил там и излизат като гол текст — затова всяко
заглавие се снижава до `<h3>`, независимо какво е било в извора.
"""

from __future__ import annotations

import argparse
import html as html_mod
import json
import re
from collections import Counter

from common import CACHE, SITE, SOURCE_NAME, WORK

# ── Изчистване ────────────────────────────────────────────────────────────
RE_SCRIPT = re.compile(r'<(script|style|noscript)\b.*?</\1>', re.S | re.I)
RE_COMMENT = re.compile(r'<!--.*?-->', re.S)
RE_TAG = re.compile(r'<[^>]+>')

# Заглавие от кой да е ранг — редът в документа решава, не рангът.
RE_HEADING = re.compile(r'<h([1-6])\b[^>]*>(.*?)</h\1>', re.S | re.I)
RE_PARA = re.compile(r'<p\b[^>]*>(.*?)</p>', re.S | re.I)

# Илюстрациите. ⚠ Само тези под `icons/` — там живеят същинските (икони,
# стенописи, мозайки). Всичко в `../images/` е обзавеждане на сайта
# (стрелки, пликчета, разделители) и влезе ли, в житието се появяват иконки
# за е-поща насред разказа.
RE_IMG = re.compile(r'<img([^>]*?)src="([^"]+)"([^>]*)>', re.I)
RE_IMG_CHROME = re.compile(
    r'(i\.gif|spacer|button|arrow|/line|bullet|logo|banner|felles|'
    r'molitvoslov/skiller|bible_icon)', re.I)

# ⚠ ИЛЮСТРАЦИИТЕ НЕ СА САМО В `icons/`. Първата версия взимаше само тази
# папка и пропускаше 69 изображения — сред тях цели раздели българска
# иконопис (`iconopis_bulgarian/`), исторически репродукции (`history/`) и
# снимки на храмове (`hramove/`). Личеше косвено: девет НАДПИСА стояха в
# текста без картинка над тях, защото описваха точно пропуснатите.
RE_IMG_GOOD = re.compile(
    r'(icons/|iconopis|ikonopis|/history/|hramove|poklonnichestvo|'
    r'MANUSCRIPTS)', re.I)



# ⚠ Долният колонтитул на всяка страница. „Виж също" открива списък с чужди
# връзки, който НЕ е част от житието; всичко след него отпада.
RE_TAIL = re.compile(
    r'(виж\s+също|към\s+съдържанието|обратно\s+към|©\s*\d{4}|'
    r'www\.pravoslavieto\.com)', re.I)

# Вътре в текста стоят връзки към речника с иконка. Махат се — в Библията
# се оказаха същият случай.
RE_DICT_LINK = re.compile(
    r'<a\b[^>]*href="[^"]*(rechnik|slovar)[^"]*"[^>]*>(.*?)</a>', re.S | re.I)

# Запазват се само тези вътрешни тагове; всичко друго се сваля до текст.
KEEP_INLINE = {'strong', 'b', 'em', 'i', 'br'}

# ⚠ ВРЪЗКИТЕ ОСТАВАТ ДЕЙСТВАЩИ (искане на потребителя, 01.09.2026). Дотук
# `a` стоеше в DROP_SILENT и всяка препратка се сваляше до гол текст — а
# те сочат към първоизточници, книги и други четива. Пазят се само
# ВЪНШНИТЕ (http/https): вътрешните навигационни („../1/calendar.htm",
# „Виж също") водят наникъде извън своя сайт.
RE_KEEP_HREF = re.compile(r'^https?://', re.I)

# ⚠ Тагове, които се махат БЕЗ да оставят интервал.
#
# Поводът е истински бъг, докладван от потребителя (30.08.2026): в източника
# думата „втори" стои разкъсана като `вт</span>o<span lang="bg">ри` — среден
# знак, изваден в собствен таг. Браузърът я слепва и я чете нормално; моят
# парсър заменяше ВСЕКИ таг с интервал и я изписваше „вт o ри".
#
# Разликата е смислова: `<span>`/`<font>` не разделят думи, а `<p>`/`<br>`
# разделят. Затова първите отпадат безшумно, а вторите оставят интервал.
# Измерено: 25 такива места в 13 страници — не епидемия, но всяко от тях е
# видима грешка насред текста.
DROP_SILENT = {
    'span', 'font', 'a', 'u', 'small', 'sup', 'sub', 'big', 'strike', 's',
    'o:p', 'st1:place', 'st1:placename', 'st1:placetype', 'nobr',
}


# ⚠ ЛОГОТО НА ПЪРВОИЗТОЧНИКА се превръща в ИМЕ С ВРЪЗКА.
#
# Под част от житията сайтът пише „Първа публикация в Интернет" и слага
# ЛОГО-картинка, обвита във връзка към онзи, който пръв я е публикувал —
# religiabg.com, slovo.bg, liternet.bg. Логото е в `images/logo/` и се
# отсява като обзавеждане, връзката се сваля до текст, и накрая оставаше
# голо „Първа публикация в Интернет ." — което се чете, че ПУБЛИКАЦИЯТА В
# ПРИЛОЖЕНИЕТО е първа. Некоректно към два сайта наведнъж: към истинския
# първоизточник, чието име изчезва, и към pravoslavieto.com, комуто се
# приписва чужда заслуга. (Забелязано от потребителя, 01.09.2026.)
#
# Името се взима от `alt` на самото лого — сайтът го попълва точно с адреса
# („religiabg.com", „Slovoto.bg").
RE_LOGO_LINK = re.compile(
    r'<a\b[^>]*href="([^"]+)"[^>]*>\s*<img\b[^>]*alt="([^"]+)"[^>]*>\s*</a>',
    re.S | re.I)


def strip_tags(fragment: str) -> str:
    """Маха таговете, но пази вътрешното оформление, което четецът разбира."""
    frag = RE_DICT_LINK.sub(r'\2', fragment)
    frag = RE_LOGO_LINK.sub(
        lambda m: f'<a href="{m.group(1)}">{m.group(2)}</a>', frag)

    # ⚠ Броят на отворените връзки. Затварящото `</a>` трябва да се изпише
    # САМО ако отварящото е било запазено — инак остава увиснал таг, който
    # flutter_html оцветява до края на абзаца.
    depth = [0]

    def keep(m: re.Match) -> str:
        tag = re.match(r'</?(\w+)', m.group(0))
        if tag and tag.group(1).lower() in KEEP_INLINE:
            name = tag.group(1).lower()
            # <b>/<i> се свеждат до <strong>/<em> — четецът стилизира тях.
            name = {'b': 'strong', 'i': 'em'}.get(name, name)
            closing = m.group(0).startswith('</')
            if name == 'br':
                return '<br>'
            return f'</{name}>' if closing else f'<{name}>'
        # Външните връзки се пазят; вътрешните се свеждат до текст.
        if tag and tag.group(1).lower() == 'a':
            if m.group(0).startswith('</'):
                if depth[0] > 0:
                    depth[0] -= 1
                    return '</a>'
                return ''
            href = re.search(r'href="([^"]*)"', m.group(0), re.I)
            if href and RE_KEEP_HREF.match(href.group(1).strip()):
                depth[0] += 1
                return f'<a href="{href.group(1).strip()}">'
            return ''
        # ⚠ Инлайн тагът се маха БЕЗ интервал — виж [DROP_SILENT]. Иначе
        # думата, вътре в която стои, се разкъсва („вт o ри").
        if tag and tag.group(1).lower() in DROP_SILENT:
            return ''
        return ' '

    out = RE_TAG.sub(keep, frag)
    out = html_mod.unescape(out)
    # ⚠ Неразделящият интервал (\xa0) идва масово от този сайт и минава
    # незабелязано през сравненията после. Свежда се до обикновен.
    out = out.replace('\xa0', ' ')
    out = fix_latin_in_cyrillic(out)
    return re.sub(r'[ \t]+', ' ', out).strip()


# Латински букви, които изглеждат като кирилски. ⚠ Само визуалните двойници:
# буква без кирилски двойник (напр. „q", „w") насред дума е друг случай и не
# се пипа.
# ⚠ БУКВИТЕ ОТ РИМСКИТЕ ЧИСЛА ЛИПСВАТ НАРОЧНО — `i c x m d l v` и главните
# им. Те се срещат ЗАКОННО насред кирилски текст и транслитерацията им е
# същинска повреда:
#
#   „ХIХ век"      → „ХИХ век"       (римско число!)
#   „Сказанiе"     → „Сказание"      (стар правопис — десетерично „i“
#                                     в църковнославянски цитат)
#
# Открито при преглед на реалните места, след предупреждение на потребителя
# да не се пипат линкове и цитати (30.08.2026): от 22 намерени, осем щяха да
# са грешка и всичките осем са точно от тези букви.
#
# Остават само еднозначните — които нямат нито числова, нито старописна
# служба.
LATIN_TO_CYRILLIC = {
    'a': 'а', 'e': 'е', 'o': 'о', 'p': 'р', 'y': 'у',
    'k': 'к', 'h': 'н', 't': 'т', 'b': 'в', 'n': 'п',
    'A': 'А', 'E': 'Е', 'O': 'О', 'P': 'Р', 'Y': 'У',
    'K': 'К', 'H': 'Н', 'T': 'Т', 'B': 'В', 'N': 'П',
}

# Латинска буква, ОБГРАДЕНА от кирилски — тоест насред кирилска дума.
RE_LATIN_INSIDE = re.compile(
    r'(?<=[а-яА-ЯёЁ])([A-Za-z])(?=[а-яА-ЯёЁ])')


def fix_latin_in_cyrillic(text: str) -> str:
    """Поправя латински букви, попаднали насред кирилска дума.

    ⚠ Брак от текстообработващата програма, с която е правен източникът:
    „вт**o**ри" с латинско „o", „М**i**" с латинско „i". В браузър се чете
    като нищо, но е грешка — и понеже думата после се дели на две от
    таговете около чуждата буква, тя изплува веднага.

    Решението е ТРАНСЛИТЕРАЦИЯ, не пренасяне на грешката — по изричното
    указание на потребителя (30.08.2026).

    ⚠ Пипа се САМО буква, обградена ОТ ДВЕТЕ СТРАНИ с кирилица. Латиница в
    началото или края на дума е законна (съкращение, чужда дума, адрес) и не
    се докосва — иначе „ХV" (римско пет) би станало „ХВ", а „Sanct" —
    неузнаваемо.
    """
    return RE_LATIN_INSIDE.sub(
        lambda m: LATIN_TO_CYRILLIC.get(m.group(1), m.group(1)), text)


# ⚠ Указание за ПЕЧАТ, което сайтът слага насред четивото:
#   „С В.  П И С А Н И Е.  С КЛАВИАТУРАТА: Натисни едновременно ALT+P,
#    последвано от ENTER (Mac: COMMAND+P, ЕNTER)"
# Първата половина е разредена с интервали между буквите, тъй че търсенето
# на цяла дума („ПИСАНИЕ") не я хваща. Хващаме по клавишната комбинация —
# тя е недвусмислена и не може да се яви в житие. Засягаше 5 четива:
# Кирил Философ, Климент Охридски, Георги Софийски Нови, Йоаким Търновски,
# 26-те зографски мъченици.
RE_PRINT_HINT = re.compile(r'(ALT\s*\+\s*P|COMMAND\s*\+\s*P|КЛАВИАТУРАТА)', re.I)


def is_noise(text: str) -> bool:
    """Абзац, който е обзавеждане, а не четиво."""
    plain = RE_TAG.sub('', text).strip()
    if len(plain) < 25:
        return True
    # Ред само от връзки/навигация.
    if plain.count('|') > 3:
        return True
    if RE_PRINT_HINT.search(plain):
        return True
    return False


def parse_page(raw: str, path: str) -> dict:
    """Една страница → раздели със заглавия и абзаци."""
    doc = RE_COMMENT.sub(' ', RE_SCRIPT.sub(' ', raw))

    # Отрязва се колонтитулът. Търси се в ПОСЛЕДНАТА четвърт, за да не се
    # спъне в дума, употребена в самото житие.
    cut = len(doc)
    for m in RE_TAIL.finditer(doc):
        if m.start() > len(doc) * 0.55:
            cut = m.start()
            break
    doc = doc[:cut]

    # Всички заглавия и абзаци, В РЕДА, В КОЙТО СТОЯТ.
    marks = []
    for m in RE_HEADING.finditer(doc):
        title = strip_tags(m.group(2))
        if title:
            marks.append((m.start(), 'h', int(m.group(1)), title))
    for m in RE_PARA.finditer(doc):
        body = strip_tags(m.group(1))
        if body and not is_noise(body):
            marks.append((m.start(), 'p', 0, body))

    # ⚠ Илюстрациите влизат КАТО БЛОК, на мястото си в потока — не се
    # свързват с описанието си по догадка. Описанията („Стенопис от ХV в.
    # в църквата…") и без това са съседни абзаци; запази ли се редът,
    # картинката остава до своя надпис от само себе си.
    #
    # Опитът да се сдвоят изрично беше изоставен по измерване: описателен
    # текст наблизо имат само 18 от 73 картинки, при това разделени поравно
    # ПРЕДИ и СЛЕД — тоест няма правило, което да се улови.
    for m in RE_IMG.finditer(doc):
        src = m.group(2)
        if RE_IMG_CHROME.search(src):
            continue
        if not RE_IMG_GOOD.search(src):
            continue
        attrs = m.group(1) + m.group(3)
        alt = re.search(r'alt="([^"]*)"', attrs)
        alt_text = html_mod.unescape(alt.group(1)).strip() if alt else ''

        # ⚠ РАЗМЕРИТЕ СЕ ПРЕНАСЯТ ЗАДЪЛЖИТЕЛНО. `Image.asset` не знае колко е
        # висок файлът, преди да го зареди, а оформлението става преди това —
        # без предварително съотношение картинката се свива до височината на
        # текстовия ред и от нея се вижда само тънка ивица.
        # За щастие изворът ги дава за ВСИЧКИТЕ 73 картинки.
        w = re.search(r'width="?(\d+)', attrs)
        h = re.search(r'height="?(\d+)', attrs)
        marks.append((m.start(), 'img', 0, (
            src, alt_text,
            int(w.group(1)) if w else 0,
            int(h.group(1)) if h else 0,
        )))

    # ⚠ Надписите на отхвърлените илюстрации отпадат ЧАК ТУК, а не в цикъла
    # за абзаци: той върви ПРЕДИ цикъла за картинки, тъй че в момента, в
    # който абзацът се разглежда, още не се знае, че картинката му ще падне.

    marks.sort(key=lambda t: t[0])

    title = next((t for _, k, lvl, t in marks if k == 'h' and lvl == 1), None)

    # ── Редът с годините, точно под заглавието ────────────────────────────
    #
    # ⚠ УЛАВЯ СЕ ТУК, защото `is_noise()` го изхвърля: той е под 25 знака
    # („1786 - 1818"), а прагът е сложен срещу навигационни огризки. Открит
    # чак когато потребителят си спомни, че сайтът дава и рождената година —
    # 44 от 54 страници го носят, макар да не личи от разчетеното.
    #
    # ⚠ Форматите са разнородни и НЕ се нормализират: „1786 - 1818",
    # „† 1067 година", „ок. 293/297 – 2 май 373 година", а някъде и цяло
    # изречение. Прибират се както са — по-честно от опит да се сведат до
    # един вид, при който половината ще излязат осакатени.
    years = None
    if title:
        h1_end = next((pos for pos, k, lvl, _ in marks
                       if k == 'h' and lvl == 1), None)
        tail = doc[h1_end:h1_end + 900] if h1_end is not None else ''
        chunks = [re.sub(r'\s+', ' ', x).replace('\xa0', ' ').strip()
                  for x in RE_TAG.sub('\n', tail).split('\n')]
        for chunk in [c for c in chunks if c and c != '&nbsp;'][:4]:
            plain = html_mod.unescape(chunk)
            if (len(plain) <= 60 and re.search(r'\b\d{3,4}\b', plain)
                    and not RE_MEMORY_LINE.match(plain)):
                years = plain.strip('()')
                break

    sections: list[dict] = []
    current: dict | None = None
    preamble: list[str] = []

    for _, kind, lvl, text in marks:
        if kind == 'h':
            if lvl == 1:
                continue                      # името на светията, не раздел
            current = {'title': text, 'paras': []}
            sections.append(current)
        elif kind == 'img':
            # Картинката пътува като кортеж (път, alt) и се различава от
            # абзаца по това. Пази се в същия списък, за да НЕ се разпадне
            # редът спрямо съседните абзаци — той е цялата връзка с надписа.
            src, alt_text, w, h = text
            (current['paras'] if current else preamble).append(
                {'img': src, 'alt': alt_text, 'w': w, 'h': h})
        else:
            (current['paras'] if current else preamble).append(text)

    # Абзаци преди първото заглавие са си пълноценно четиво (кратките
    # страници нямат нито едно заглавие).
    if preamble:
        sections.insert(0, {'title': None, 'paras': preamble})

    sections = [s for s in sections if s['paras']]
    return {
        'path': path,
        'url': f'{SITE}{path}',
        'page_title': title,
        'years': years,
        'sections': sections,
    }


# ── Песнопения ────────────────────────────────────────────────────────────
# Видовете са същите като в таблицата `lives.hymns` — tropar / kondak /
# molitva / velichanie. „Ин тропар" значи „друг тропар" и е СЪЩИЯТ вид, само
# пореден: в базата това се пази в `seq`, не в `kind`.
HYMN_KINDS = [
    ('tropar', re.compile(r'^\s*(ин\s+)?тропар', re.I)),
    ('kondak', re.compile(r'^\s*(ин\s+)?кондак', re.I)),
    ('molitva', re.compile(r'^\s*молитв', re.I)),
    ('velichanie', re.compile(r'^\s*величани', re.I)),
]
RE_GLAS = re.compile(r'глас\s+([\wа-я]+)', re.I)


def hymn_kind(title: str | None) -> str | None:
    """Заглавието на раздел → вид песнопение, или None за обикновено четиво."""
    if not title:
        return None
    plain = RE_TAG.sub(' ', title)
    for kind, rx in HYMN_KINDS:
        if rx.match(plain):
            return kind
    return None


def extract_hymns(sections: list[dict]) -> list[dict]:
    """Изважда песнопенията от разделите — за таблицата `hymns`.

    ⚠ Разделите НЕ се махат от четивото. По решение на потребителя песнопението
    остава да си стои под житието, а тук се вади ВТОРИ път, за да има и
    отделна връзка под името на светията (тропар / кондак / молитва /
    величание) — както при вече наличните 2445 песнопения.

    ⚠ Текстът тук е БЪЛГАРСКИ и отива в колоната `bg`; `csl` остава празна.
    Съществуващите записи идват от църковнославянски извор и имат и двете.
    Не ги смесвай: празна `csl` е честен признак „този няма славянски текст",
    а не липса на данни.
    """
    hymns = []
    seq: Counter = Counter()
    for sec in sections:
        kind = hymn_kind(sec['title'])
        if not kind or not sec['paras']:
            continue
        seq[kind] += 1
        title_plain = RE_TAG.sub(' ', sec['title'] or '')
        glas = RE_GLAS.search(title_plain)
        hymns.append({
            'kind': kind,
            'kind_ru': re.sub(r'\s+', ' ', title_plain).strip(),
            'seq': seq[kind],
            'glas': f'глас {glas.group(1)}' if glas else None,
            # ⚠ Само текстовите блокове: `paras` вече може да носи и
            # илюстрации (речници), а те нямат работа в текста на песнопение.
            'bg': '\n'.join(p for p in sec['paras'] if isinstance(p, str)),
        })
    return hymns


def merge_split_sections(sections: list[dict]) -> list[dict]:
    """Слива съседни раздели с ЕДНО И СЪЩО заглавие.

    ⚠ Поводът е Гавриил Лесновски: житието му излизаше на ДВА раздела с
    еднакъв надпис, защото в извора по средата стои икона. Картинката отпада
    (иконите се достигат по връзката към източника накрая), а текстът от двете
    страни е един и същ разказ и трябва да е един раздел.

    Сравнява се по нормализирано заглавие, за да не се спъне в различен
    интервал или регистър.
    """
    out: list[dict] = []
    for sec in sections:
        key = re.sub(r'\s+', ' ', RE_TAG.sub('', sec['title'] or '')).strip().lower()
        prev_key = (re.sub(r'\s+', ' ', RE_TAG.sub('', out[-1]['title'] or '')).strip().lower()
                    if out else None)
        if out and key and key == prev_key:
            out[-1]['paras'].extend(sec['paras'])
        else:
            out.append(sec)
    return out


# Въвеждащият ред „Чества се на 12 юли заедно с…". Той е указание кога се
# чества светията, не част от разказа.
RE_MEMORY_LINE = re.compile(
    r'^\s*(честват?\s+се|празнува\s+се|отбелязва\s+се|памет(та)?\s+(на|се))',
    re.I)

# Колко дълъг трябва да е абзац, за да мине за начало на самия разказ.
# ⚠ Мярка на ОКО, но с широк луфт: най-дългото въвеждащо нещо, което срещаме,
# е 96 знака („Чества се на 16 януари заедно с Честните вериги на св.ап. Петър
# и преп. Ромил Видински"), а най-краткото начало на житие — над 200.
NARRATIVE_MIN = 130

# ⚠ Чуждоезичен ред насред български жития — остатък от алтернативните
# заглавия на страницата („Св. мученик Георгий", „St. Demetrius of…").
# Разпознава се по това, че НЯМА нито една буква, характерна само за
# българската азбука, но има характерни за руската — или е изцяло латиница.
RE_LATIN_ONLY = re.compile(r'^[^Ѐ-ӿ]{8,}$')

# ⚠ Конкретни руски ДУМИ, не окончания. Първата версия търсеше окончания
# (`\w+(ый|ого|ому|ых)`) и това беше сериозен бъг: „мн-ОГО" съвпадаше, тъй че
# филтърът изяде най-честата българска дума и с нея 426 000 знака (34% от
# целия текст), докато истинският руски ред „Св. мученик Георгий" мина
# необезпокоен. В два толкова близки славянски езика окончанията неизбежно се
# застъпват — сигурни са само цели думи и буквите, които българският няма.
RUSSIAN_WORDS = {
    'мученик', 'мученица', 'мученики', 'преподобный', 'преподобная',
    'святые', 'святой', 'святая', 'равноапостольный', 'равноапостольные',
    'князь', 'первоучители', 'блаженный', 'священномученик', 'великомученик',
    'исповедник', 'чудотворец', 'архиепископ', 'митрополит',
}

# Ред по-дълъг от това почти сигурно е същински текст, не заглавен остатък.
MAX_FOREIGN_LEN = 200


def is_foreign(text: str) -> bool:
    """Ред на чужд език, попаднал в българското житие.

    ⚠ Нарочно ПРЕСТОРОЖЕН: по-добре да остане чужд ред, отколкото да изчезне
    български текст. Затова три условия наведнъж — късо, и (изцяло латиница
    ИЛИ буква, каквато българският няма, ИЛИ цяла руска дума).
    """
    plain = text.strip()
    if len(plain) < 8 or len(plain) > MAX_FOREIGN_LEN:
        return False
    if RE_LATIN_ONLY.match(plain):
        return True

    low = plain.lower()
    # „ы", „э", „ё" не съществуват в българската азбука изобщо.
    if any(ch in low for ch in 'ыэё'):
        return True
    words = set(re.findall(r'[а-яё]+', low))
    return bool(words & RUSSIAN_WORDS)


def clean_title(title: str) -> str:
    """Заглавието от `<h1>` → един ред, годен за `<h3>`.

    ⚠ Две заглавия носят `<br>` вътре („…Йоаким Осоговски <br>(Иоаким
    Сардиполски…)"). Прекъсването се свежда до интервал: `<h3>` в четеца е
    центриран и сам пренася дългия ред, а вграден `<br>` би дал чупка на
    място, което не съвпада с реалната ширина.
    """
    t = re.sub(r'<br\s*/?>', ' ', title, flags=re.I)
    t = RE_TAG.sub(' ', t)
    t = html_mod.unescape(t).replace('\xa0', ' ')
    return re.sub(r'\s+', ' ', t).strip(' .,;:')


def build_html(sections: list[dict], title: str | None = None,
               years: str | None = None) -> str:
    """Разделите → един HTML низ за `texts.life`.

    Подредбата е тази на досегашните жития в базата:

        1. въвеждащият ред („Чества се на…")     — class="memorydate"
        2. самото житие (с подзаглавия)          — буквицата пада ТУК
        3. песнопенията                          — class="prayerhead" + текст

    ⚠ ПЕСНОПЕНИЯТА СЕ МЕСТЯТ НАКРАЯ, където и да са стояли в извора. В сайта
    тропарът често стои ПРЕДИ житието; оставен там, той получава буквицата и
    четивото започва с песнопение вместо с разказа.

    ⚠ Въвеждащият ред получава `class="memorydate"` по ДВЕ причини наведнъж:
    изписва се в курсив (той е указание, не разказ) и — понеже
    `splitDropCap` търси ГОЛ `<p>` — буквицата сама го прескача до следващия
    абзац. Същият похват като в `book_reader._normalize`.

    ⚠ Заглавие се изписва САМО когато разделите са повече от един. При едно
    четиво то повтаря името на светията, което четецът рисува отгоре.
    """
    memory: list[str] = []
    body: list[dict] = []
    hymn_secs: list[dict] = []

    # ⚠ ВЪВЕЖДАЩАТА ЗОНА СВЪРШВА ПРИ ПЪРВИЯ ИСТИНСКИ АБЗАЦ ОТ РАЗКАЗА, а не
    # при първия абзац изобщо. Дотогава редът „Чества се на…" си е указание,
    # независимо колко кратки сведения стоят пред него.
    #
    # Условието беше `not body and not keep`, тоест „абсолютно първи". Но
    # страниците слагат отпред и годините, и подзаглавие, и надпис на
    # илюстрация — и тогава редът оставаше ГОЛ `<p>`: без курсив, центриране
    # и — по-лошото — С БУКВИЦА, защото `splitDropCap` прескача само класа.
    # Тъй че житието започваше с инициал върху „Чества се на 16 януари…"
    # вместо върху първите думи на разказа. Засягаше 5 жития.
    narrative = False

    for sec in sections:
        if hymn_kind(sec['title']):
            hymn_secs.append(sec)
            continue
        keep = []
        for p in sec['paras']:
            if isinstance(p, dict):            # илюстрация — минава както е
                keep.append(p)
                continue
            plain = RE_TAG.sub('', p).strip()
            if is_foreign(plain):
                continue                       # чуждоезичен остатък
            if not narrative:
                # ⚠ Годините вече стоят отгоре като отделен ред (виж `years`
                # по-горе) — страницата обаче ги дава И като абзац, тъй че без
                # това изхвърляне се изписват ДВА ПЪТИ едно под друго.
                # Св. Дамаскин Габровски: „Пострадал заради Христа през 1771
                # година" се четеше два пъти, вторият път с буквица.
                if years and plain == years.strip():
                    continue
                if RE_MEMORY_LINE.match(plain):
                    memory.append(plain)       # въвеждащият ред
                    continue
                # Първият абзац с истинска дължина затваря въвеждащата зона.
                # Кратките пред него (подзаглавие, надпис на илюстрация) я
                # оставят отворена — те също не са разказ.
                if len(plain) >= NARRATIVE_MIN:
                    narrative = True
            keep.append(p)
        if keep:
            body.append({'title': sec['title'], 'paras': keep})

    parts: list[str] = []

    # ⚠ ЗАГЛАВИЕТО Е ЗАДЪЛЖИТЕЛНО И ВЪРВИ ПЪРВО. Без него четивото започваше
    # с въвеждащия ред и подзаглавието „Кратко животоописание", а четецът
    # НЕ слагаше свое: той проверява дали четивото има собствено `<h1>`–`<h6>`
    # и подзаглавието вече минаваше за такова (виж `hasOwnTitle` в
    # reader_screen.dart). Тъй че житието оставаше без основен надпис.
    #
    # Взима се заглавието от сайта, а не името от календара — то е по-пълно:
    # „Св. равноапостолен цар Борис-Михаил, покръстител на българите" срещу
    # „благоверен и равноап. княз Борис".
    if title:
        parts.append(f'<h3>{html_mod.escape(clean_title(title))}</h3>')
    # Годините — отделен ред под заглавието, в същия вид като въвеждащия.
    if years:
        parts.append(f'<p class="memorydate">{html_mod.escape(years)}</p>')

    for line in memory:
        parts.append(f'<p class="memorydate">{line}</p>')

    many = len(body) > 1
    for sec in body:
        if sec['title'] and many:
            parts.append(f'<h3>{html_mod.escape(sec["title"])}</h3>')
        for p in sec['paras']:
            if isinstance(p, dict):
                # ⚠ Пътят е ВРЕМЕНЕН (адресът в сайта). `09_place_images.py`
                # го подменя с името на файла в `assets/`, след като картинките
                # се копират там. Тук нарочно не се гадае бъдещото име: то се
                # решава от картата в `work/images.json`, а не от парсъра.
                alt = html_mod.escape(p.get('alt') or '')
                # ⚠ `width`/`height` СА ЗАДЪЛЖИТЕЛНИ в изхода — от тях четецът
                # смята съотношението, преди файлът да се е заредил.
                dims = ''
                if p.get('w') and p.get('h'):
                    dims = f' width="{p["w"]}" height="{p["h"]}"'
                parts.append(f'<img src="{html_mod.escape(p["img"])}" '
                             f'alt="{alt}"{dims}>')
            else:
                parts.append(f'<p>{p}</p>')

    # Песнопенията — накрая, в утвърдения вид (виж `_prayersBlocksHtml` в
    # reader_screen.dart). ⚠ Текстът тук е БЪЛГАРСКИ, тъй че върви като
    # обикновен абзац: `.csl` е за църковнославянски, а `.trans` — за превод
    # ПОД него. Няма ги двете, значи не се преструваме, че ги има.
    for sec in hymn_secs:
        title = RE_TAG.sub(' ', sec['title'] or '')
        title = re.sub(r'\s+', ' ', title).strip().rstrip(':')
        parts.append(f'<p class="prayerhead">{html_mod.escape(title)}</p>')
        # ⚠ САМО текстовите блокове. `paras` може да носи и илюстрации
        # (речници) — минат ли оттук без проверка, речникът се изписва в
        # четивото като низ: `<p>{'img': 'icons/…', 'alt': …}</p>`. Точно това
        # се появи при „Методий и Кирил" (30.08.2026).
        parts.extend(f'<p>{p}</p>' for p in sec['paras'] if isinstance(p, str))

    return '\n'.join(parts)


def verify_page(saint_name: str, page_title: str | None,
                section_titles: list) -> tuple[bool, str]:
    """Наистина ли тази страница е за ТОЗИ светия?

    ⚠ Тази проверка е задължителна, защото разчитането само по себе си НЕ
    греши — то честно разчита каквото му дадеш. Ако засечката е сбъркала
    страницата, изходът излиза богат и правдоподобен, само че за друг човек.
    Уловени така (30.08.2026):

        „Симеон, митр. Самоковски"  →  св. пророк Самуил   (55 595 знака)
        „Христо"                    →  св. Стефан Нови     (94 214 знака)

    Първото е съвпадение по ЗВУЧЕНЕ („Samui" ↔ „Samokovski"). И двете щяха да
    минат незабелязано: числата изглеждат отлично, а никой не чете 55 000
    знака, за да провери за кого са.

    Признакът е прост: заглавието на страницата трябва да носи поне една
    значеща дума от името на светията. Сравнява се и със заглавията на
    разделите — при съборните памети името стои там, а не горе.
    """
    from common import name_tokens

    ours = set(name_tokens(saint_name))
    if not ours:
        return True, 'няма с какво да се провери'

    haystack = ' '.join(
        [page_title or ''] + [t or '' for t in section_titles]).lower()
    theirs = set(name_tokens(haystack))

    common_words = ours & theirs
    if common_words:
        return True, f'общи: {", ".join(sorted(common_words))}'
    return False, f'нищо общо с „{(page_title or "?")[:45]}"'


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument('--only', help='само този светия (по ключ или част от име)')
    ap.add_argument('--keep-suspect', action='store_true',
                    help='записва и непотвърдените (по подразбиране се пропускат)')
    args = ap.parse_args()

    cands = json.loads((WORK / 'candidates.json').read_text(encoding='utf-8'))
    out_dir = WORK / 'parsed'
    out_dir.mkdir(parents=True, exist_ok=True)

    report = ['# Разчитане на житията', '',
              '⚠ Гледай колоната „раздели": светия с 0 раздела значи, че',
              'страницата е с формат, който парсърът още не разбира.', '',
              '| светия | раздели | знаци | страница |',
              '|---|---:|---:|---|']
    stats = Counter()
    suspects: list[dict] = []
    total_chars = 0

    for s in cands:
        if not s['matches']:
            stats['без страница'] += 1
            continue
        if args.only and args.only.lower() not in (
                s['key'] + s['name_core']).lower():
            continue

        path = s['matches'][0]['path']
        cached = CACHE / path.lstrip('/').replace('/', '__')
        if not cached.exists():
            stats['не е свалена'] += 1
            continue

        parsed = parse_page(cached.read_text(encoding='utf-8'), path)
        section_titles = [x['title'] for x in parsed['sections']]

        ok, why = verify_page(s['name_core'], parsed['page_title'],
                              section_titles)
        if not ok and not args.keep_suspect:
            stats['⛔ ЧУЖДА страница'] += 1
            suspects.append({
                'name': s['name_core'], 'path': path,
                'page_title': parsed['page_title'], 'why': why,
                'how': s['how'],
            })
            continue

        # ⚠ Сливането е ПРЕДИ вадене на песнопенията и преди сглобяването —
        # инак разкъсаният раздел брои за два и seq-овете излизат криви.
        parsed['sections'] = merge_split_sections(parsed['sections'])
        section_titles = [x['title'] for x in parsed['sections']]

        hymns = extract_hymns(parsed['sections'])
        life = build_html(parsed['sections'], title=parsed['page_title'],
                          years=parsed.get('years'))
        plain = RE_TAG.sub('', life)

        rec = {
            'key': s['key'],
            'name_core': s['name_core'],
            'name_full': s['name_full'],
            'slug': s['slug'],
            'church_date': s['church_date'],
            'need': s['need'],
            'existing_len': s['life_len'],
            'source_url': parsed['url'],
            'source_name': SOURCE_NAME,
            'page_title': parsed['page_title'],
            'years': parsed.get('years'),
            'section_titles': [x['title'] for x in parsed['sections']],
            'sections': len(parsed['sections']),
            'life_html': life,
            'life_chars': len(plain),
            'hymns': hymns,
        }
        (out_dir / f'{s["key"].replace(" ", "_")}.json').write_text(
            json.dumps(rec, ensure_ascii=False, indent=2), encoding='utf-8')

        stats['разчетени'] += 1
        total_chars += len(plain)
        if len(plain) < 400:
            stats['⚠ подозрително къси'] += 1
        report.append(
            f'| {s["name_core"][:40]} | {len(parsed["sections"])} | '
            f'{len(plain)} | `{path.split("/")[-1]}` |')

    if suspects:
        report += ['', '## ⛔ Отхвърлени — страницата е за ДРУГ светия', '',
                   'Засечката е сбъркала. ⚠ Тези НЕ влизат в базата: изходът',
                   'им изглежда богат и правдоподобен, но е за друг човек.',
                   'Решават се на ръка в `input/manual_map.csv`.', '',
                   '| в календара | разчетена страница | засечка |',
                   '|---|---|---|']
        for x in suspects:
            report.append(
                f'| {x["name"][:38]} | {(x["page_title"] or "?")[:44]} '
                f'| {x["how"]} |')
        (WORK / 'suspects.json').write_text(
            json.dumps(suspects, ensure_ascii=False, indent=2),
            encoding='utf-8')

    (WORK / 'parse_report.md').write_text('\n'.join(report), encoding='utf-8')

    for k, v in stats.most_common():
        print(f'  {k:22} {v}')
    if stats['разчетени']:
        print(f'\n  общо знаци:            {total_chars:,}')
        print(f'  средно на житие:       {total_chars // stats["разчетени"]:,}')
    print(f'\n→ work/parsed/,  work/parse_report.md')


if __name__ == '__main__':
    main()
