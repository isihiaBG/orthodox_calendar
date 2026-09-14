#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Извлича (дата, заглавие, href, число) за всяко житие в дванайсетте тома
по св. Димитрий Ростовски — суровият материал за засечката със saints.

Датата идва от СТРУКТУРАТА на toc.ncx (ден → жития под него), не от
regex по текста на самото заглавие — виж бележката в CLAUDE.md за
epub_source.dart: първо ниво в съдържанието на всеки том са дните
("Памет на N <месец>"), второто са отделните жития. Числото (id-то на
статията в azbyka.ru) НЕ се вади наново от <h1> в главите — взима се от
готовия assets/lives_index.json, за да остане в синхрон с това, което
реално ползва четецът за навигация (виж lives_index.dart).

⚠ Първото житие под всеки ден дели href с ДЕНЯ (главата съдържа и двете
едно след друго — денят няма собствен <h1>, само първото му житие). На
практика числото излиза вярно (0 нерешени при пускането, сверено), но
скриптът пак маркира тези редове в `num_note`, чисто информативно.

Изход: output/dmitry_titles.csv

Пуска се без аргументи:
    python3 01_extract_dmitry.py
"""

import csv
import glob
import json
import os
import re
import zipfile
import xml.etree.ElementTree as ET

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(
    os.path.abspath(__file__)))))
BOOKS_DIR = os.path.join(ROOT, 'assets', 'books')
LIVES_INDEX_PATH = os.path.join(ROOT, 'assets', 'lives_index.json')
OUT_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'output')
OUT_CSV = os.path.join(OUT_DIR, 'dmitry_titles.csv')

NCX_NS = '{http://www.daisy.org/z3986/2005/ncx/}'

MONTHS = {
    'януари': 1, 'февруари': 2, 'март': 3, 'април': 4,
    'май': 5, 'юни': 6, 'юли': 7, 'август': 8,
    'септември': 9, 'октомври': 10, 'ноември': 11, 'декември': 12,
    # „юний" — архаичен изписан облик, ползван доследователно в целия том
    # за юни (иначе всички останали месеци са в съвременна форма); сверено
    # чрез директно сканиране на всичките 12 .ncx файла, не гадано.
    'юний': 6,
}
MONTH_RE = '|'.join(MONTHS)
RE_DAY = re.compile(r'^Памет(?:та)?\s+на\s+(\d{1,2})\s+(' + MONTH_RE + r')\b',
                     re.IGNORECASE)

# Дели се от "На <име>" (среща се в някои томове, напр. септември) —
# не носи смисъл за сравнение с saints.name.
RE_NA_PREFIX = re.compile(r'^На\s+')

# Бележка под линия, слята направо в текста на заглавието без интервал (в
# .ncx label-ите няма markup за <sup>, тъй че номерът остава гол текст) —
# напр. "Александрия2363". Открито на 23.08.2026 у 2 от 1155 заглавия;
# сверено, че шаблонът никъде другаде не съвпада с легитимно число
# (датите винаги имат интервал/скоба пред себе си).
RE_FOOTNOTE_DIGITS = re.compile(r'([А-Яа-яЁёѝЍ])\d{2,4}\b')


def nav_children(elem):
    """Директните <navPoint> деца на navMap/navPoint — без по-дълбоки нива."""
    return elem.findall(f'{NCX_NS}navPoint')


def nav_title(navpoint):
    label = navpoint.find(f'{NCX_NS}navLabel/{NCX_NS}text')
    return (label.text or '').strip() if label is not None else ''


def nav_href(navpoint):
    content = navpoint.find(f'{NCX_NS}content')
    return content.get('src') if content is not None else ''


def _join(ncx_dir, href):
    """Огледално на _join в epub_source.dart — href-ите в .ncx са спрямо
    папката му (обикновено OEBPS/), а lives_index.json пази пълния път."""
    if not ncx_dir or ncx_dir == '.':
        return href
    return os.path.normpath(f'{ncx_dir}/{href}').replace(os.sep, '/')


def load_lives_index():
    with open(LIVES_INDEX_PATH, encoding='utf-8') as f:
        data = json.load(f)
    # (книга, href) -> число, за обратно търсене
    by_book_href = {}
    for num, rec in data.items():
        by_book_href[(rec['book'], rec['href'])] = num
    return by_book_href


def extract_volume(epub_path, by_book_href, rows, stats):
    book = os.path.basename(epub_path)
    with zipfile.ZipFile(epub_path) as z:
        ncx_name = next(n for n in z.namelist() if n.endswith('.ncx'))
        ncx_dir = os.path.dirname(ncx_name)
        data = z.read(ncx_name).decode('utf-8', 'ignore')
    root = ET.fromstring(data)
    nav_map = root.find(f'{NCX_NS}navMap')

    for day_node in nav_children(nav_map):
        day_title = nav_title(day_node)
        m = RE_DAY.match(day_title)
        if not m:
            stats['non_day_roots'].append((book, day_title))
            continue
        day_num, month_num = int(m.group(1)), MONTHS[m.group(2).lower()]
        mmdd = f'{month_num:02d}-{day_num:02d}'

        day_href_full = _join(ncx_dir, nav_href(day_node).split('#')[0])

        children = nav_children(day_node)
        if not children:
            stats['days_without_children'].append((book, day_title))
            continue

        for i, life in enumerate(children):
            title = nav_title(life)
            href = _join(ncx_dir, nav_href(life).split('#')[0])
            clean_title = RE_NA_PREFIX.sub('', title).strip()
            clean_title = RE_FOOTNOTE_DIGITS.sub(r'\1', clean_title)

            num = by_book_href.get((book, href))
            num_note = ''
            if i == 0 and href == day_href_full:
                num_note = 'дели файл със заглавието на деня'
                if num is None:
                    stats['first_child_no_num'] += 1
            if num is None:
                stats['no_num'] += 1

            rows.append({
                'mm_dd': mmdd,
                'title': clean_title,
                'title_raw': title,
                'num': num or '',
                'num_note': num_note,
                'book': book,
                'href': href,
                'day_title': day_title,
            })
        stats['days'] += 1
        stats['lives'] += len(children)


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    by_book_href = load_lives_index()

    rows = []
    stats = {
        'days': 0, 'lives': 0, 'no_num': 0, 'first_child_no_num': 0,
        'non_day_roots': [], 'days_without_children': [],
    }

    for path in sorted(glob.glob(os.path.join(BOOKS_DIR, '*Ростовски.epub'))):
        extract_volume(path, by_book_href, rows, stats)

    rows.sort(key=lambda r: (r['mm_dd'], r['book'], r['href']))

    # Разделител "|", не запетая — по установената конвенция в
    # tools/azbyka.ru/scripts/. Заглавията тук често съдържат запетаи
    # (рангове, епитети), тъй че запетаята като разделител би довлякла
    # кавичене на повечето редове; "|" не се среща в текста, тъй че на
    # практика НИКОЙ ред не излиза кавичен.
    with open(OUT_CSV, 'w', encoding='utf-8', newline='') as f:
        w = csv.DictWriter(f, fieldnames=[
            'mm_dd', 'title', 'title_raw', 'num', 'num_note',
            'book', 'href', 'day_title',
        ], delimiter='|', quotechar="'")
        w.writeheader()
        w.writerows(rows)

    print('=' * 60)
    print(f'дни: {stats["days"]}   жития: {stats["lives"]}')
    print(f'без съответствие в lives_index: {stats["no_num"]}')
    print(f'  от тях — първо житие на деня (дели href): {stats["first_child_no_num"]}')
    print(f'root записи, разпознати като НЕ-ден (пропуснати): {len(stats["non_day_roots"])}')
    for book, title in stats['non_day_roots']:
        print(f'    {book}: "{title}"')
    if stats['days_without_children']:
        print(f'дни без нито едно житие под тях: {len(stats["days_without_children"])}')
        for book, title in stats['days_without_children']:
            print(f'    {book}: "{title}"')
    print(f'→ {OUT_CSV}')


if __name__ == '__main__':
    main()
