#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
01_extract.py — Стъпка 1 (МЕХАНИЧНА, без DeepSeek): разглобява .epub-а на
свт. Теофан Затворник и дава на всяко поучение ЛИТУРГИЧЕН АДРЕС.

Книгата е писана за 1887 г. и се движи ден по ден през църковната година.
Заглавията ѝ обаче носят по няколко пласта наведнъж — „Неделя мытаря и
фарисея (33-я)" е едновременно подвижен спрямо Пасха ден И 33-та неделя
след Петдесетница. Двете съвпадат само през 1887 г.; през 2026 г. Митар и
фарисей е 34-та. Затова номерът се ИЗХВЪРЛЯ (остава само за справка) и
записът се завежда по пасхалния си адрес.

Видовете адреси са четири — същата тройка както в calendar_gen, плюс
броенето по Петдесетница:

    fixed   църковна дата „ММ-ДД"      Богоявление = 01-06
    pascha  офсет в дни от Пасха       Митар и фарисей = -70
    pent    седмица/неделя по Петд.    „12:5" = петък на седмица 12
                                       „sunday:13" = Неделя 13
    anchor  подвижен спрямо неподвижен „sunday_before_theophany"

Всеки запис получава ТОЧНО ЕДИН адрес. Веригата на приоритета (level 1–5)
не се ползва тук — тя работи в приложението, когато един ден има няколко
възможни адреса:

    1 Господски празник      Обрезание, Богоявление, Сретение, Възнесение,
                             Преображение, Въздвижение, Рождество
    2 подвижен спрямо Пасха  Триод и Пентикостар, вкл. всяка тяхна неделя
    3 неделя                 по Петдесетница или спрямо неподвижен празник
    4 Богородичен/светийски  Успение, Въведение, Събор Предтечев
    5 делник по седмица      броене напред от Петдесетница

Нищо не се превежда и нищо не се пише в бази. Пише се work/units/*.json и
отчет — тук се допускат повечето грешки, затова се гледа първо.

Вход:
  ../input/Мысли на каждый день [1887] года.gen.epub

Изход:
  ../work/units/NNN.json      по един на поучение
  ../work/notes.json          бележките под линия
  ../work/classification.tsv  отчетът за преглед

Употреба:
  python3 01_extract.py
  python3 01_extract.py --check-only     само проверките, без запис
"""

import argparse
import html
import json
import os
import re
import sys
import zipfile

from common import BOOK_BG, bulgarian_ref

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.dirname(SCRIPT_DIR)
INPUT_DIR = os.path.join(PROJECT_DIR, 'input')
WORK_DIR = os.path.join(PROJECT_DIR, 'work')
UNITS_DIR = os.path.join(WORK_DIR, 'units')

# Записите в книгата: 002–354 са поученията, 355–366 са редакционни
# бележки, 367–405 са бележките под линия.
FIRST_DAY, LAST_DAY = 2, 354
FIRST_EDNOTE, LAST_EDNOTE = 355, 366
FIRST_FOOTNOTE, LAST_FOOTNOTE = 367, 405

# ---------------------------------------------------------------------------
# Адресите, които не следват общата формула.
#
# Зимният отрязък (записи 2–17) го изписваме поименно: там се преплитат
# Богоявление, котвите около него и делниците на седмици 32–33, а формула
# за това няма. Оттам нататък всичко е аритметика.
# ---------------------------------------------------------------------------
WINTER = {
    2:  ('fixed',  '01-01', 1, 'Обрезание Господне / Нова година'),
    3:  ('anchor', 'saturday_before_theophany', 3, 'Събота преди Богоявление'),
    4:  ('anchor', 'sunday_before_theophany', 3, 'Неделя преди Богоявление'),
    5:  ('pent',   '32:1', 5, 'Понеделник, седмица 32'),
    6:  ('pent',   '32:2', 5, 'Вторник, седмица 32'),
    7:  ('fixed',  '01-06', 1, 'Богоявление'),
    8:  ('fixed',  '01-07', 4, 'Събор на св. Йоан Предтеча'),
    9:  ('pent',   '32:5', 5, 'Петък, седмица 32'),
    10: ('anchor', 'saturday_after_theophany', 3, 'Събота след Богоявление'),
    11: ('anchor', 'sunday_after_theophany', 3, 'Неделя след Богоявление'),
    12: ('pent',   '33:1', 5, None), 13: ('pent', '33:2', 5, None),
    14: ('pent',   '33:3', 5, None), 15: ('pent', '33:4', 5, None),
    16: ('pent',   '33:5', 5, None), 17: ('pent', '33:6', 5, None),
}

# Записи, чийто ТЕКСТ е за празника, макар заглавието и четивото да сочат
# редовия ден. През 1887 г. празникът се е случил на този делник (или
# неделя) и свт. Теофан е писал за празника. Формулата би ги завела на
# грешно място, затова тук ги пренасочваме — виж отчета, колоната „защо".
#
# Успение и Въведение са Богородични, тоест по веригата стоят ПОД неделята;
# завеждат се все пак при празника, защото текстът е изцяло за него, а не
# за неделното четиво. Цената: Неделя 13 и Неделя 27 остават без мисъл в
# годините, когато не съвпадат с празника.
FEAST_OVERRIDES = {
    34:  ('fixed', '02-02', 1, 'Сретение Господне'),
    127: ('pascha', '39',   1, 'Възнесение Господне'),
    219: ('fixed', '08-06', 1, 'Преображение Господне'),
    228: ('fixed', '08-15', 4, 'Успение на Пресвета Богородица'),
    258: ('fixed', '09-14', 1, 'Въздвижение на Честния Кръст'),
    326: ('fixed', '11-21', 4, 'Въведение Богородично'),
    347: ('anchor', 'forefathers', 3, 'Неделя на св. Праотци'),
    354: ('fixed', '12-25', 1, 'Рождество Христово'),
}

# Границите на аритметичните отрязъци.
PASCHA_FIRST, PASCHA_LAST = 18, 144   # Митар и фарисей … Всички светии
PASCHA_ZERO = 88                      # записът на самата Пасха
WEEK2_FIRST, WEEK2_LAST = 145, 150    # делниците на седмица 2
PENT_FIRST, PENT_LAST = 151, 353      # Неделя 2 … събота на седмица 31

# Руските числителни в заглавията — за round-trip проверката.
ORDINALS = {
    'первая': 1, 'вторая': 2, 'третья': 3, 'четвертая': 4, 'пятая': 5,
    'шестая': 6, 'седьмая': 7, 'восьмая': 8, 'девятая': 9, 'десятая': 10,
    'одиннадцатая': 11, 'двенадцатая': 12, 'тринадцатая': 13,
    'четырнадцатая': 14, 'пятнадцатая': 15, 'шестнадцатая': 16,
    'семнадцатая': 17, 'восемнадцатая': 18, 'девятнадцатая': 19,
    'двадцатая': 20, 'тридцатая': 30,
}
# Съставните числителни („двадцать первая") се пишат с отделна дума за
# десетиците. Тя стои ПРЕДИ единиците, затова се проверява първа —
# иначе „двадцать вторая" се прочита като 2.
TENS = {'двадцать': 20, 'тридцать': 30}
WEEKDAY_RU = {
    'Понедельник': 1, 'Вторник': 2, 'Среда': 3,
    'Четверг': 4, 'Пятница': 5, 'Суббота': 6,
}


RE_BIBLE_LINK = re.compile(
    r'<a href="https://azbyka\.ru/biblia/\?([^"]+)"[^>]*>(.*?)</a>', re.S)
RE_DEAD_ANCHOR = re.compile(r'<a href=""[^>]*>(.*?)</a>', re.S)
# Бележките са два вида и сочат към различни котви: авторовите към
# #footnoteN (изписват се „*5"), редакционните на „Азбука Веры" към #noteN
# (изписват се само с число). И двете трябва да се уловят.
RE_FOOTNOTE_REF = re.compile(
    r'<a href="[^"]*#(?:foot)?note\d+"[^>]*>\s*<sup[^>]*>(\*?\d+)</sup>\s*</a>',
    re.S)
RE_EMPHASIS = re.compile(r'</?(em|strong)>')


def to_units(body_html):
    """Реже тялото на абзаци и заменя вградените тагове със запушалки.

    Запушалките са ⟦N⟧ — по образеца на ⟦znak1⟧ в справочника. Причината е
    същата: моделът иначе разваля или размества разметката. Тук атомите са
    три вида:

      препратка към Писанието   целият <a>…</a> става един атом; етикетът
                                се пресъздава на български от кода, не се
                                превежда
      препратка към бележка     <sup>*5</sup>
      подчертаване              <em>/<strong> — двойка запушалки

    Кавичките «…» НЕ стават запушалки. Потребителят пожела да останат както
    са в оригинала, тъй че те си пътуват през превода като обикновени знаци
    и 03_build_db.py ги хваща после, за да ги обвие в <cite>.

    Мъртвите котви <a href=""> на calibre се разтварят — те не носят нищо,
    а накъсват цитатите („Дом Бож" + „ий, който е…") и биха объркали
    сдвояването с препратката.
    """
    body_html = RE_DEAD_ANCHOR.sub(r'\1', body_html)
    atoms = []

    def take(kind, payload, shown=''):
        atoms.append({'n': len(atoms) + 1, 'kind': kind,
                      'payload': payload, 'shown_ru': shown})
        return '⟦%d⟧' % len(atoms)

    def on_footnote(m):
        return take('footnote', m.group(1))

    def on_link(m):
        return take('bible', m.group(1), plain(m.group(2)))

    body_html = RE_FOOTNOTE_REF.sub(on_footnote, body_html)
    body_html = RE_BIBLE_LINK.sub(on_link, body_html)

    units = []
    for paragraph in re.findall(r'<p[^>]*>(.*?)</p>', body_html, re.S):
        paragraph = RE_EMPHASIS.sub('', paragraph)
        text = plain(paragraph)
        if text:
            units.append(repair_quotes(text))
    return units, atoms


def repair_quotes(text):
    """Затваря цитат, отворен с « и затворен с прав кавичкоподобен знак.

    Книгата има набор печатни грешки от рода на «Се ныне время благоприятно"
    — отваря се с гийме, затваря се с прав ". Такива цитати после не се
    разпознават (03_build_db.py търси «…»), а и объркват проверката за
    цялост на превода: тя брои двойките и наказва модела, задето е върнал
    правилни кавички там, където оригиналът е сгрешен.

    Пипа се САМО когато между отварящото « и правия знак няма друго гийме —
    иначе рискуваме да залепим два съседни цитата в един.
    """
    return re.sub(r'(«[^«»]*?)["″”]', r'\1»', text)


def plain(fragment):
    """Тагове навън, знаците разекранирани, интервалите нормализирани."""
    fragment = re.sub(r'<sup.*?</sup>', '', fragment, flags=re.S)
    fragment = re.sub(r'<[^>]+>', ' ', fragment)
    return ' '.join(html.unescape(fragment).split())


def read_epub():
    """Отваря .epub-а и връща {име на файл: съдържание}."""
    candidates = [f for f in os.listdir(INPUT_DIR) if f.endswith('.epub')]
    if len(candidates) != 1:
        sys.exit('Очаквам точно един .epub в %s, намерих %d'
                 % (INPUT_DIR, len(candidates)))
    path = os.path.join(INPUT_DIR, candidates[0])
    with zipfile.ZipFile(path) as z:
        return path, {os.path.basename(n): z.read(n).decode('utf-8')
                      for n in z.namelist() if n.endswith('.xhtml')}


def parse_entry(source):
    """Изважда заглавие, четиво, тяло и датата от 1887 г. от един файл."""
    h1_match = re.search(r'<h1.*?</h1>', source, re.S)
    h1 = h1_match.group(0)
    h2_match = re.search(r'<h2.*?</h2>', source, re.S)

    # Датата стои в title="…" на препратката към бележка под линия. Понякога
    # е предшествана от пояснение („32-й недели по Пятидесятнице, 21.1.1887").
    date_match = re.search(r'title="[^"]*?(\d{1,2}\.\d{1,2}\.1887)"', h1)

    # Тялото е всичко след последното заглавие; таговете вътре се ПАЗЯТ —
    # <span> огражда библейските цитати, <a> сочи към azbyka.ru/biblia,
    # <sup> е препратка към бележка. Всички те трябва да преживеят превода.
    tail = source.split('</h2>', 1)[1] if h2_match else source.split('</h1>', 1)[1]
    body = tail.split('</body>', 1)[0]
    body = re.sub(r'^\s*', '', body)

    title = plain(h1)
    # Номерът по Петдесетница от 1887 г. — само за справка.
    week_label = None
    label_match = re.search(r'\((\d+)-[йяе]\b[^)]*\)', title)
    if label_match:
        week_label = label_match.group(1)

    return {
        'title_ru': title,
        'readings': plain(h2_match.group(0)) if h2_match else '',
        'body_html_ru': body.strip(),
        'body_text_ru': plain(body),
        'date_1887': date_match.group(1) if date_match else None,
        'week_label_1887': week_label,
    }


def address_for(index, entry):
    """Литургичният адрес на записа: (kind, key, level, коментар)."""
    if index in FEAST_OVERRIDES:
        kind, key, level, why = FEAST_OVERRIDES[index]
        return kind, key, level, 'празник: ' + why
    if index in WINTER:
        kind, key, level, why = WINTER[index]
        return kind, key, level, ('зимен отрязък' if why is None
                                  else 'зимен отрязък: ' + why)
    if PASCHA_FIRST <= index <= PASCHA_LAST:
        return 'pascha', str(index - PASCHA_ZERO), 2, 'Триод/Пентикостар'
    if WEEK2_FIRST <= index <= WEEK2_LAST:
        return 'pent', '2:%d' % (index - WEEK2_FIRST + 1), 5, 'седмица 2'
    if PENT_FIRST <= index <= PENT_LAST:
        offset = index - PENT_FIRST
        block, position = divmod(offset, 7)
        if position == 0:
            return 'pent', 'sunday:%d' % (2 + block), 3, 'неделя по Петдесетница'
        return 'pent', '%d:%d' % (3 + block, position), 5, 'делник по Петдесетница'
    raise AssertionError('запис %d остана без адрес' % index)


def assign_parents(entries):
    """Дописва на всеки запис заглавието на блока, който го управлява.

    280 от 353-те заглавия са голи делнични имена — „Вторник" и нищо
    повече. Сам по себе си такъв ред не значи нищо: в книгата читателят
    се ориентира по това СЛЕД КОЕ заглавие стои вторникът. Ако запазим
    само „Вторник", справочната колона става безполезна — ще имаме 50
    вторника, неразличими един от друг.

    Затова за всеки гол делник помним последното „истинско" заглавие
    преди него (неделя или празник). Записите, които сами откриват блок,
    остават без родител.
    """
    current = None
    for index in sorted(entries):
        entry = entries[index]
        first_word = entry['title_ru'].split()[0].rstrip('.') if entry['title_ru'] else ''
        bare_weekday = (first_word in WEEKDAY_RU
                        and len(entry['title_ru'].split()) == 1)
        if bare_weekday:
            entry['parent_ru'] = current
        else:
            entry['parent_ru'] = None
            current = entry['title_ru']


def check(entries):
    """Round-trip: адресът, приложен назад, трябва да даде заглавието.

    Същият похват както в extract_rules.py на календарния генератор —
    правилото се проверява срещу данните, от които е извлечено.
    """
    problems = []
    for index, entry in sorted(entries.items()):
        kind, key, _, _ = entry['address']
        title = entry['title_ru']

        if kind == 'pent' and key.startswith('sunday:'):
            expected = int(key.split(':')[1])
            match = re.search(r'Неделя\s+(\S+(?:\s+\S+)?)\s+по\s+Пятидес',
                              title)
            if match:
                words = match.group(1).lower().split()
                if words[0] in TENS:
                    got = TENS[words[0]] + (ORDINALS.get(words[1], 0)
                                            if len(words) > 1 else 0)
                else:
                    got = ORDINALS.get(words[-1])
                if got != expected:
                    problems.append('%3d  „%s" → sunday:%d, а заглавието казва %s'
                                    % (index, title[:48], expected, got))
        elif kind == 'pent':
            week, day = (int(x) for x in key.split(':'))
            first_word = title.split()[0].rstrip('.').rstrip()
            if first_word in WEEKDAY_RU and WEEKDAY_RU[first_word] != day:
                problems.append('%3d  „%s" → ден %d, а заглавието казва %s'
                                % (index, title[:48], day, first_word))
            in_title = entry['week_label_1887']
            if in_title and int(in_title) != week:
                problems.append('%3d  „%s" → седмица %d, а 1887 г. казва %s'
                                % (index, title[:48], week, in_title))
    return problems


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--check-only', action='store_true',
                        help='само проверките, без да се пише')
    args = parser.parse_args()

    epub_path, files = read_epub()
    print('Чета %s' % os.path.basename(epub_path))

    entries = {}
    for index in range(FIRST_DAY, LAST_DAY + 1):
        name = 'index_split_%03d.xhtml' % index
        if name not in files:
            sys.exit('липсва %s' % name)
        entry = parse_entry(files[name])
        entry['index'] = index
        entry['file'] = name
        entry['address'] = address_for(index, entry)
        entry['units_ru'], entry['atoms'] = to_units(entry['body_html_ru'])
        entries[index] = entry
    assign_parents(entries)

    # Бележките под линия — номер → текст.
    notes = {}
    for index in range(FIRST_FOOTNOTE, LAST_FOOTNOTE + 1):
        source = files['index_split_%03d.xhtml' % index]
        number = re.search(r'<h1[^>]*>\s*(?:<[^>]+>\s*)*\*(\d+)', source)
        paragraphs = re.findall(r'<p[^>]*>(.*?)</p>', source, re.S)
        if number:
            notes['*' + number.group(1)] = plain(' '.join(paragraphs))
    for index in range(FIRST_EDNOTE, LAST_EDNOTE + 1):
        source = files['index_split_%03d.xhtml' % index]
        number = re.search(r'<h1[^>]*>\s*(?:<[^>]+>\s*)*(\d+)', source)
        paragraphs = re.findall(r'<p[^>]*>(.*?)</p>', source, re.S)
        if number:
            notes[number.group(1)] = plain(' '.join(paragraphs))

    # --- отчет ---------------------------------------------------------
    by_kind = {}
    for entry in entries.values():
        by_kind.setdefault(entry['address'][0], []).append(entry['index'])
    print()
    print('поучения: %d, бележки: %d' % (len(entries), len(notes)))
    for kind in ('fixed', 'pascha', 'pent', 'anchor'):
        print('  %-7s %3d' % (kind, len(by_kind.get(kind, []))))
    без_четиво = [e['index'] for e in entries.values() if not e['readings']]
    print('без четиво (алитургични дни на поста): %d' % len(без_четиво))

    units = sum(len(e['units_ru']) for e in entries.values())
    atoms = [a for e in entries.values() for a in e['atoms']]
    знаци = sum(len(u) for e in entries.values() for u in e['units_ru'])
    кавички = sum(len(re.findall(r'«[^«»]{2,}»', u))
                  for e in entries.values() for u in e['units_ru'])
    print('абзаци за превод: %d (%d знака)' % (units, знаци))
    print('запушалки: %d препратки към Писанието, %d към бележки'
          % (sum(1 for a in atoms if a['kind'] == 'bible'),
             sum(1 for a in atoms if a['kind'] == 'footnote')))
    print('цитати в «…»: %d' % кавички)

    непознати = sorted({a['payload'].partition('.')[0] for a in atoms
                        if a['kind'] == 'bible'
                        and a['payload'].partition('.')[0] not in BOOK_BG})
    if непознати:
        print('БИБЛЕЙСКИ КНИГИ БЕЗ БЪЛГАРСКО СЪКРАЩЕНИЕ: %s'
              % ', '.join(непознати))

    problems = check(entries)
    print()
    if problems:
        print('РАЗМИНАВАНИЯ при проверката (%d):' % len(problems))
        for line in problems:
            print('  ' + line)
    else:
        print('Проверката мина: всички адреси се връзват със заглавията.')

    if args.check_only:
        return

    os.makedirs(UNITS_DIR, exist_ok=True)
    for index, entry in entries.items():
        kind, key, level, why = entry['address']
        unit = {
            'index': index,
            'file': entry['file'],
            'kind': kind,
            'key': key,
            'level': level,
            'note': why,
            'title_ru': entry['title_ru'],
            'parent_ru': entry['parent_ru'],
            'readings': entry['readings'],
            'date_1887': entry['date_1887'],
            'week_label_1887': entry['week_label_1887'],
            'body_html_ru': entry['body_html_ru'],
            'units_ru': entry['units_ru'],
            'atoms': entry['atoms'],
            # Превежда се САМО тялото. Заглавието остава руско и служи за
            # справка — на български денят си има име в календарната база
            # („Неделя 12 след Петдесетница"), а втори набор имена, дошъл
            # от превода на книгата, само би се разминал с него.
            'units_bg': None,
        }
        path = os.path.join(UNITS_DIR, '%03d.json' % index)
        with open(path, 'w', encoding='utf-8') as f:
            json.dump(unit, f, ensure_ascii=False, indent=1)

    with open(os.path.join(WORK_DIR, 'notes.json'), 'w', encoding='utf-8') as f:
        json.dump(notes, f, ensure_ascii=False, indent=1)

    report = os.path.join(WORK_DIR, 'classification.tsv')
    with open(report, 'w', encoding='utf-8') as f:
        f.write('index\tkind\tkey\tlevel\tзащо\tзаглавие (1887)\t'
                'под кое заглавие стои\tчетиво\n')
        for index, entry in sorted(entries.items()):
            kind, key, level, why = entry['address']
            f.write('%d\t%s\t%s\t%d\t%s\t%s\t%s\t%s\n'
                    % (index, kind, key, level, why, entry['title_ru'],
                       entry['parent_ru'] or '', entry['readings']))

    print()
    print('записах %d файла в %s' % (len(entries), UNITS_DIR))
    print('отчет: %s' % report)


if __name__ == '__main__':
    main()
