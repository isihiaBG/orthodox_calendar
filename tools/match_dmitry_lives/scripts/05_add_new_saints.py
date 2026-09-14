#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Добавя в СЕМЕТО (tools/calendar_gen/input/db/calendar_old.db) новите
светии от Димитрий Ростовски, за които input/manual_review.csv няма
съответствие в saints (action='new').

Изключва:
  - 6 записа, за които бележката сочи поучителен разказ/легенда без
    собствено име на светия (num 125, 222, 270, 284, 290, 534) — не са
    подходящи за самостоятелен ред в saints.
  - num 197/198/199 (29 февруари) — вече решени отделно чрез
    extract_rules.LEAP_FIXED, не минават по този път.

За всеки остатъчен запис (520 общо):
  - дата: гражданска = date(2026, church_month, church_day) + 13 дни
    (СЪЩАТА формула, която вече важи за целия семе — SOURCE_YEAR=2026,
    офсет от paschalion.julian_gregorian_offset).
  - rank=6 (подразбиране, съгласно установеното правило — виж CLAUDE.md),
    group_code='ECUMENICAL', sign='' — еднакво за всичките 520, без
    претенция за прецизност по ранг за толкова много записи наведнъж.
  - slug: транслитериран от заглавието (рангови думи свалени), с проверка
    за сблъсък срещу ВСИЧКИ съществуващи slug-ове (saints + lives.texts +
    lives.hymns) — поуката от Йосиф Обручник по-рано.

След INSERT обновява input/manual_review.csv — редовете от action='new'
за добавените стават action='confirm' с новия saint_id.

Пуска се без аргументи (изисква готово output/dmitry_titles.csv и
input/manual_review.csv):
    python3 05_add_new_saints.py [--dry-run]
"""
import argparse
import csv
import datetime
import os
import re
import sqlite3
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(
    os.path.abspath(__file__)))))
CALENDAR_GEN = os.path.join(ROOT, 'tools', 'calendar_gen')
sys.path.insert(0, CALENDAR_GEN)
from paschalion import julian_gregorian_offset  # noqa: E402

SEED_DB = os.path.join(CALENDAR_GEN, 'input', 'db', 'calendar_old.db')
LIVES_DB = os.path.join(ROOT, 'assets', 'db', 'lives.db')
OUT_DIR = os.path.join(os.path.dirname(HERE), 'output')
IN_DIR = os.path.join(os.path.dirname(HERE), 'input')
DMITRY_CSV = os.path.join(OUT_DIR, 'dmitry_titles.csv')
REVIEW_CSV = os.path.join(IN_DIR, 'manual_review.csv')

STORY_NUMS = {'125', '222', '270', '284', '290', '534'}
LEAP_NUMS = {'197', '198', '199'}
EXCLUDED = STORY_NUMS | LEAP_NUMS

RANK_WORDS = [
    'препмчц', 'препмч', 'свщмчц', 'свщмч', 'сщмч', 'первомч', 'первомчц',
    'прмчц', 'прмч', 'мчца', 'мчцц', 'мчц', 'мчч', 'мчк', 'мч',
    'блгв', 'блж', 'прав', 'прор', 'преп', 'прп', 'свт', 'свв', 'св',
    'апп', 'ап', 'еп', 'архиеп', 'митр', 'патр', 'презв', 'диак',
    'чудотв', 'безср', 'девица', 'дева', 'кн', 'царица', 'царь', 'игумен',
]
RE_RANK = re.compile(r'\b(?:' + '|'.join(RANK_WORDS) + r')\.?\b', re.IGNORECASE)
RE_PAREN = re.compile(r'\([^)]*\)')
RE_PUNCT = re.compile(r'[.,†«»„“"\'\-–—:]')
RE_WS = re.compile(r'\s+')

TRANSLIT = {
    'а': 'a', 'б': 'b', 'в': 'v', 'г': 'g', 'д': 'd', 'е': 'e', 'ж': 'zh',
    'з': 'z', 'и': 'i', 'й': 'j', 'к': 'k', 'л': 'l', 'м': 'm', 'н': 'n',
    'о': 'o', 'п': 'p', 'р': 'r', 'с': 's', 'т': 't', 'у': 'u', 'ф': 'f',
    'х': 'h', 'ц': 'c', 'ч': 'ch', 'ш': 'sh', 'щ': 'shch', 'ъ': '', 'ь': '',
    'ю': 'ju', 'я': 'ja', 'ѝ': 'i',
}


def transliterate(word: str) -> str:
    return ''.join(TRANSLIT.get(ch, ch) for ch in word.lower())


def make_slug_base(title: str) -> str:
    s = RE_PAREN.sub(' ', title)
    s = RE_RANK.sub(' ', s)
    s = RE_PUNCT.sub(' ', s)
    words = [w for w in RE_WS.split(s) if w]
    words = words[:4]  # първите неколко значещи думи стигат за различимост
    parts = [transliterate(w) for w in words]
    parts = [p for p in parts if p]
    return 'sv-' + '-'.join(parts) if parts else 'sv-neizvesten'


def unique_slug(title: str, num: str, taken: set) -> str:
    base = make_slug_base(title)
    slug = base
    n = 2
    while slug in taken:
        slug = f'{base}-{n}'
        n += 1
    taken.add(slug)
    return slug


def load_dmitry():
    return {r['num']: r for r in csv.DictReader(
        open(DMITRY_CSV, encoding='utf-8'), delimiter='|', quotechar="'")}


def civil_date_for_church(mm_dd: str) -> str:
    month, day = (int(x) for x in mm_dd.split('-'))
    d = datetime.date(2026, month, day) + datetime.timedelta(
        days=julian_gregorian_offset(2026))
    return d.isoformat()


# Заглавията от книгата носят руски/църковнославянски съкращения
# ("мчк.", "мчци", "преп."), различни от установената българска
# конвенция в календара ("Мч.", "Мчч.", "Прп." — виж лидиращите форми в
# оригиналните saints, преброени с tools/calendar_gen). Открито на
# 23.08.2026 при преглед на потребителя (520-те нови реда бяха влезли
# несменени) и поправено ТУК, в източника, а не само в готовата база —
# същото правило като при tools/corrections/.
RANK_ABBR_MAP = {
    'мчк': 'Мч.', 'мчк.': 'Мч.',
    'мчци': 'Мчч.', 'мчци.': 'Мчч.', 'мчци:': 'Мчч.',
    'мчца': 'Мц.', 'мчца.': 'Мц.',
    'мчц.': 'Мц.',
    'мцца': 'Мцц.', 'мцца.': 'Мцц.',
    'мцц': 'Мцц.', 'мцц.': 'Мцц.',
    'преп': 'Прп.', 'преп.': 'Прп.',
    'преподобни': 'Прп.',
    'преподобните': 'Препп.',
    'преподобна': 'Прп.',
    'свщмчк': 'Свщмч.', 'свщмчк.': 'Свщмч.',
    'свещеномчк.': 'Свщмч.',
    'свещеномъченик': 'Свщмч.',
    'свщмчци': 'Свщмчч.', 'свщмчци.': 'Свщмчч.',
    'светител': 'Свт.',
    'светите': 'Апп.',  # единственият наблюдаван случай е "светите апостоли"
    'свети': 'Св.',
    'св.': 'Св.',
    'свв.': 'Свв.',
    'блаж': 'Блж.', 'блаж.': 'Блж.',
    'прав': 'Прав.', 'прав.': 'Прав.',
    'прор': 'Прор.', 'прор.': 'Прор.',
    'мъченик': 'Мч.',
    'мъченица': 'Мц.',
    'мъчениците': 'Мчч.', 'мъчениците,': 'Мчч.,',
    'праведния': 'Прав.',
    'препмчк.': 'Прпмч.',
    'благоверни': 'Блгв.',
}
RE_FOOTNOTE_DIGITS = re.compile(r'([А-Яа-яЁёѝЍ])\d{2,4}\b')


def normalize_rank(name: str) -> str:
    """Съобразява водещото съкращение по ранг с българската конвенция.
    Пипа само ПЪРВАТА дума — рангови думи по-нататък в изречението
    (напр. в комбинирани редове за няколко души) не се пипат."""
    m = re.match(r'^(\S+)\s+(.*)$', name, re.S)
    if not m:
        result = name
    else:
        first, rest = m.group(1), m.group(2)
        repl = RANK_ABBR_MAP.get(first.lower())
        result = f'{repl} {rest}' if repl else name
    result = RE_FOOTNOTE_DIGITS.sub(r'\1', result)
    if result and result[0].islower():
        result = result[0].upper() + result[1:]
    return result


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--dry-run', action='store_true')
    args = ap.parse_args()

    dmitry = load_dmitry()
    review_rows = list(csv.DictReader(open(REVIEW_CSV, encoding='utf-8'),
                                       delimiter='|', quotechar="'"))
    new_rows = [r for r in review_rows
                if r['action'] == 'new' and r['dmitry_num'] not in EXCLUDED]

    con = sqlite3.connect(SEED_DB)
    taken = set(r[0] for r in con.execute(
        "SELECT slug FROM saints WHERE slug IS NOT NULL AND slug != ''"))
    livesdb = sqlite3.connect(LIVES_DB)
    taken |= set(r[0] for r in livesdb.execute("SELECT DISTINCT slug FROM texts"))
    taken |= set(r[0] for r in livesdb.execute("SELECT DISTINCT slug FROM hymns"))
    livesdb.close()

    to_insert = []
    for r in new_rows:
        d = dmitry.get(r['dmitry_num'])
        if d is None:
            print(f"!!! num={r['dmitry_num']} липсва в dmitry_titles.csv — пропуснат")
            continue
        civil = civil_date_for_church(d['mm_dd'])
        name = normalize_rank(d['title'])
        slug = unique_slug(d['title'], r['dmitry_num'], taken)
        to_insert.append(dict(
            civil_date=civil, name=name, rank=6,
            group_code='ECUMENICAL', sign='', slug=slug,
            dmitry_num=int(r['dmitry_num']),
        ))

    print(f"'new' записи общо: {len(new_rows)}, за вмъкване: {len(to_insert)}")
    dupe_slugs = [x['slug'] for x in to_insert]
    assert len(dupe_slugs) == len(set(dupe_slugs)), "вътрешен сблъсък на slug-ове!"

    if args.dry_run:
        for x in to_insert[:10]:
            print(f"  {x['civil_date']} | {x['name'][:50]:50} | {x['slug']}")
        print('  ...')
        con.close()
        return

    # ⚠ "id" в семето е ОБИКНОВЕНА колона (CREATE TABLE няма "INTEGER
    # PRIMARY KEY"), НЕ псевдоним на SQLite rowid — cur.lastrowid дава
    # вътрешния rowid, който не съвпада с реалната стойност в "id".
    # Трябва да се зададе изрично, инак остава NULL. (Хванато точно тук
    # на 23.08.2026 — първият опит остави всичките 520 нови реда с
    # id=NULL; засечено, преди да засегне assets/, върнато от бекъп.)
    next_id = con.execute('SELECT MAX(id) FROM saints').fetchone()[0] + 1
    id_by_num = {}
    for x in to_insert:
        con.execute(
            'INSERT INTO saints (id,date,name,rank,group_code,sign,slug) '
            'VALUES (?,?,?,?,?,?,?)',
            (next_id, x['civil_date'], x['name'], x['rank'], x['group_code'],
             x['sign'], x['slug']))
        id_by_num[x['dmitry_num']] = next_id
        next_id += 1
    con.commit()
    n_total = con.execute('SELECT COUNT(*) FROM saints').fetchone()[0]
    con.close()
    print(f'→ {SEED_DB}: +{len(to_insert)} реда, общо {n_total}')

    # manual_review.csv: 'new' -> 'confirm' + saint_id, за добавените
    updated = 0
    for r in review_rows:
        if r['action'] == 'new' and int(r['dmitry_num']) in id_by_num:
            r['action'] = 'confirm'
            r['saint_id'] = str(id_by_num[int(r['dmitry_num'])])
            r['kind'] = 'main'
            r['note'] = (r['note'] + ' | ' if r['note'] else '') + \
                'добавен нов ред в saints на 23.08.2026 (05_add_new_saints.py)'
            updated += 1

    with open(REVIEW_CSV, 'w', encoding='utf-8', newline='') as f:
        w = csv.DictWriter(f, fieldnames=['dmitry_num', 'action', 'saint_id', 'kind', 'note'],
                            delimiter='|', quotechar="'")
        w.writeheader()
        w.writerows(review_rows)
    print(f'→ {REVIEW_CSV}: {updated} реда преминаха от new в confirm')


if __name__ == '__main__':
    main()
