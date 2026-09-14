#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Извлича saints от СЕМЕТО — другата страна на засечката с
output/dmitry_titles.csv (виж 01_extract_dmitry.py).

⚠ Чете директно от tools/calendar_gen/input/db/calendar_old.db, БЕЗ да го
копира тук — семето е едно-единствено място (виж CLAUDE.md), а ако утре
се поправи там (име, дата), следващо пускане на този скрипт трябва да
вижда актуалното, не остаряло копие.

⚠ Датата в семето е ГРАЖДАНСКА (григорианска), не църковна — виж
extract_rules.py: `civil_date - 13 дни = църковна дата`. Ред 1 например е
`date='2026-01-14'`, name='ОБРЕЗАНИЕ ГОСПОДНЕ' — църковно е 1 януари.
Димитрий Ростовски е подреден по ЦЪРКОВНИЯ месецослов, тъй че за
засечката трябва да сваляме офсета, не просто да режем годината — иначе
сравняваме `01-14` срещу `01-01` и нищо не съвпада, макар да е СЪЩИЯТ ден.
Офсетът се смята през `paschalion.julian_gregorian_offset()` (същата
функция, която `extract_rules.py` вече ползва и е сверил чрез round-trip
проверка) — не се преоткрива тук.

Изход: output/saints.csv — БЕЗ филтриране по ранг или каквото и да било:
пълното съдържание на saints, готово за групиране по ден в следващата
стъпка. Кой ранг има смисъл да участва в сравнението е преценка за
скрипта за засечка, не за извличането.

Пуска се без аргументи:
    python3 02_extract_saints.py
"""

import csv
import datetime
import os
import sqlite3
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(
    os.path.abspath(__file__)))))
CALENDAR_GEN = os.path.join(ROOT, 'tools', 'calendar_gen')
sys.path.insert(0, CALENDAR_GEN)
from paschalion import julian_gregorian_offset  # noqa: E402

SEED_DB = os.path.join(CALENDAR_GEN, 'input', 'db', 'calendar_old.db')
OUT_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'output')
OUT_CSV = os.path.join(OUT_DIR, 'saints.csv')


def church_mm_dd(civil_date: str) -> str:
    """Гражданска "ГГГГ-ММ-ДД" -> църковна "ММ-ДД" (виж бележката горе)."""
    civil = datetime.date.fromisoformat(civil_date)
    church = civil - datetime.timedelta(days=julian_gregorian_offset(civil.year))
    return f'{church.month:02d}-{church.day:02d}'


def main():
    os.makedirs(OUT_DIR, exist_ok=True)

    con = sqlite3.connect(SEED_DB)
    con.row_factory = sqlite3.Row
    rows_db = con.execute(
        'SELECT id, date, name, rank, group_code, sign, slug FROM saints'
    ).fetchall()
    con.close()

    rows = []
    by_day = {}
    for r in rows_db:
        mm_dd = church_mm_dd(r['date'])
        rows.append({
            'mm_dd': mm_dd,
            'civil_date': r['date'],
            'id': r['id'],
            'name': r['name'],
            'rank': r['rank'],
            'group_code': r['group_code'] or '',
            'sign': r['sign'] or '',
            'slug': r['slug'] or '',
        })
        by_day.setdefault(mm_dd, 0)
        by_day[mm_dd] += 1

    rows.sort(key=lambda r: (r['mm_dd'], r['id']))

    # "|" разделител, без кавичене за обичайния случай — по същата
    # конвенция като output/dmitry_titles.csv и както в tools/azbyka.ru.
    # civil_date се пази само за справка при ръчен преглед — засечката
    # трябва да ползва mm_dd (църковно), не civil_date.
    with open(OUT_CSV, 'w', encoding='utf-8', newline='') as f:
        w = csv.DictWriter(f, fieldnames=[
            'mm_dd', 'civil_date', 'id', 'name', 'rank', 'group_code', 'sign', 'slug',
        ], delimiter='|', quotechar="'")
        w.writeheader()
        w.writerows(rows)

    empty_slug = sum(1 for r in rows if not r['slug'])
    max_day = max(by_day.items(), key=lambda kv: kv[1])

    print('=' * 60)
    print(f'светии: {len(rows)}   различни дни: {len(by_day)}')
    print(f'без slug (само в семето, без текст в lives.db): {empty_slug}')
    print(f'най-натоварен ден: {max_day[0]} — {max_day[1]} записа')
    print(f'→ {OUT_CSV}')


if __name__ == '__main__':
    main()
