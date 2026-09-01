#!/usr/bin/env python3
"""Произвежда пълна calendar_*.db за произволна (година, стил) от
правилата в calendar_old.db.

Съдържа:
  saints         — от extract_rules.extract() (виж build_saints)
  calendar_days  — tone/week_id/sunday_id от weeks_sundays.generate_year(),
                   fast_period/fast_type от fasts.py (ползва ПРЯСНО
                   генерираните saints за годината, не calendar_old.db)
  weeks, sundays — от weeks_sundays.generate_year()
  fast_periods, fast_types, saint_ranks, saint_groups — статични
                   справочни таблици, преписват се БЕЗ промяна
  readings       — ЗНАЙНО ОГРАНИЧЕНИЕ: преписва се БЕЗ промяна, датите му
                   остават тези от 2026 стар стил (собствен генератор още
                   няма — виж README). Валидна само за --year 2026
                   --style old; за друга (година,стил) е просто "за да не
                   се губи", не е коректна.

Употреба:
  python3 build.py --year 2026 --style new
  python3 build.py --year 2026 --style old   (трябва да възпроизведе
                                               calendar_old.db почти точно —
                                               най-добрата налична проверка)
"""
import argparse
import calendar as pycalendar
import datetime
import os
import sqlite3
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from paschalion import civil_from_church, pascha_civil
from rules import resolve as resolve_rule
import extract_rules
import weeks_sundays as ws
import fasts

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', '..'))
OLD = os.path.join(HERE, 'input', 'db', 'calendar_old.db')
OUT_DIR = os.path.join(HERE, 'out')

# Преписват се БЕЗ промяна от calendar_old.db — не зависят от година/стил.
STATIC_TABLES = ['fast_periods', 'fast_types', 'saint_ranks', 'saint_groups',
                  'fast_explanations']
# Знайно ограничение (виж докстринга) — преписва се, но не е коректно
# извън --year 2026 --style old.
COPY_AS_IS_TABLES = ['readings']


# Добавя се към името, когато 29.II (църковно) пада на 28.II в
# невисокосна целева година — виж LEAP_FIXED в extract_rules.py.
LEAP_FALLBACK_NOTE = ' (Паметта му се пренася от 29.II)'


def build_saints(rules: dict, year: int, old_style: bool) -> list[tuple]:
    """(date, name, rank, group_code, sign, slug, movable) за всеки жив
    запис, сортирано по дата. `rules` е резултатът от extract_rules.extract().

    ⚠ `movable` е 1 за подвижните и 0 за неподвижните. Знае се ТУК и никъде
    другаде: подвижността личи по СПИСЪКА, от който идва записът, а не по
    самата дата. Опитът да се изведе отвън — „падал ли е на различни дни
    през годините" — дава лъжливи положителни: „Касперовска икона" и
    „прп. Акакий Синайски" имат по ДВЕ памети годишно и изглеждат подвижни,
    без да са. (Добавено 01.09.2026 по искане на потребителя, за да може
    PDF-ът да слага „Памет на 14.фев." само където датата има смисъл.)
    """
    rows = []

    for r in rules['fixed']:
        d = civil_from_church(year, r['church_month'], r['church_day'], old_style)
        rows.append((d, r, 0))

    # ⚠ ГРАЖДАНСКИ фиксираните — единственият пласт, който НЕ минава през
    # civil_from_church(): датата е една и съща в двата стила. Затова и
    # `old_style` изобщо не участва тук.
    for r in rules.get('civil', []):
        d = datetime.date(year, r['civil_month'], r['civil_day'])
        rows.append((d, r, 0))

    # ⚠ Разминаващите се между стиловете — по нов стил своя гражданска дата,
    # по стар стил обичайното пресмятане от църковната.
    for r in rules.get('civil_new', []):
        if old_style:
            d = civil_from_church(year, r['church_month'], r['church_day'], True)
        else:
            d = datetime.date(year, r['new_month'], r['new_day'])
        rows.append((d, r, 0))

    for r in rules.get('leap_fixed', []):
        leap = pycalendar.isleap(year)
        day = 29 if leap else 28
        d = civil_from_church(year, 2, day, old_style)
        name = r['name'] if leap else r['name'] + LEAP_FALLBACK_NOTE
        rows.append((d, dict(r, name=name), 0))

    for r in rules['pascha']:
        d = pascha_civil(year) + datetime.timedelta(days=r['offset_days'])
        rows.append((d, r, 1))

    for r in rules['anchor']:
        m, day = rules['anchor_church'][r['anchor_feast']]
        anchor_civil = civil_from_church(year, m, day, old_style)
        d = extract_rules.nearest_weekday(
            anchor_civil, extract_rules.WEEKDAY[r['weekday']], r['direction'])
        rows.append((d, r, 1))

    # ⚠ „Ръчните" са подвижни ПО ОПРЕДЕЛЕНИЕ: в known_movable.csv влиза само
    # запис, чиято подвижност не е написана в текста му (виж докстринга на
    # load_known_movable) — неподвижен ред няма какво да търси там.
    for r in rules['manual']:
        d = resolve_rule(r['rule'], year, old_style, rules['anchor_church'])
        rows.append((d, r, 1))

    rows.sort(key=lambda x: x[0])
    return [(d.isoformat(), r['name'], r['rank'], r['group_code'], r['sign'],
             r['slug'], mov)
            for d, r, mov in rows]


def build_calendar_days(saints: list[tuple], year: int, old_style: bool):
    """calendar_days/weeks/sundays с fast_period/fast_type, включени в
    calendar_days редовете. `saints` е ИЗХОДЪТ на build_saints() — оттам
    се строи справочника за деня, който fasts.fast_type() очаква."""
    saints_by_date: dict[str, list[tuple[int, str]]] = {}
    for date_s, name, rank, group_code, sign, slug, _movable in saints:
        saints_by_date.setdefault(date_s, []).append((rank, group_code))

    cd_base, weeks_rows, sundays_rows = ws.generate_year(year, old_style)

    cd_rows = []
    for date_s, tone, week_id, sunday_id in cd_base:
        d = datetime.date.fromisoformat(date_s)
        period = fasts.fast_period(d, year, old_style)
        st = saints_by_date.get(date_s, [])
        ftype = fasts.fast_type(d, year, old_style, period, st)
        key = fasts.fast_explanation_key(d, year, old_style, period, st)
        cd_rows.append((date_s, tone, period, ftype, key, week_id, sunday_id))

    return cd_rows, weeks_rows, sundays_rows


def write_db(path: str, saints, cd_rows, weeks_rows, sundays_rows, src_db):
    if os.path.exists(path):
        os.remove(path)
    conn = sqlite3.connect(path)

    conn.execute('''
        CREATE TABLE saints (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            date TEXT, name TEXT, rank INTEGER, group_code TEXT,
            sign TEXT, slug TEXT,
            -- 1 = подвижен (спрямо Пасха или котва), 0 = неподвижен.
            -- Виж build_saints() защо не се извежда от самите дати.
            movable INTEGER NOT NULL DEFAULT 0
        )
    ''')
    conn.executemany(
        'INSERT INTO saints (date,name,rank,group_code,sign,slug,movable)'
        ' VALUES (?,?,?,?,?,?,?)',
        saints)

    conn.execute('''
        CREATE TABLE weeks (id INTEGER PRIMARY KEY, name TEXT, note TEXT, tone INTEGER)
    ''')
    conn.executemany('INSERT INTO weeks (id,name,note,tone) VALUES (?,?,?,?)',
                      [(i, n, '', t) for i, n, t in weeks_rows])

    conn.execute('''
        CREATE TABLE sundays (id INTEGER PRIMARY KEY, name TEXT, note TEXT, tone INTEGER)
    ''')
    conn.executemany('INSERT INTO sundays (id,name,note,tone) VALUES (?,?,?,?)',
                      [(i, n, '', t) for i, n, t in sundays_rows])

    conn.execute('''
        CREATE TABLE calendar_days (
            date TEXT PRIMARY KEY, tone INTEGER, fast_period INTEGER,
            fast_type INTEGER, fast_explanation_key TEXT,
            week_id INTEGER, sunday_id INTEGER, note TEXT
        )
    ''')
    conn.executemany(
        'INSERT INTO calendar_days (date,tone,fast_period,fast_type,fast_explanation_key,week_id,sunday_id) '
        'VALUES (?,?,?,?,?,?,?)', cd_rows)

    # ── статични/копирани таблици — директно от изходната база ──
    for table in STATIC_TABLES + COPY_AS_IS_TABLES:
        schema = src_db.execute(
            "select sql from sqlite_master where type='table' and name=?",
            (table,)).fetchone()
        if schema is None:
            print(f'  (пропускам {table} — липсва в изходната база)')
            continue
        conn.execute(schema[0])
        rows = src_db.execute(f'select * from {table}').fetchall()
        if rows:
            placeholders = ','.join('?' * len(rows[0]))
            conn.executemany(f'insert into {table} values ({placeholders})', rows)

    conn.commit()
    conn.close()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--year', type=int, required=True)
    ap.add_argument('--style', choices=['old', 'new'], required=True)
    args = ap.parse_args()
    old_style = args.style == 'old'

    src_db = sqlite3.connect(f'file:{OLD}?mode=ro', uri=True)
    r = extract_rules.extract(src_db)
    if r['mismatches']:
        print(f"ГРЕШКА: {len(r['mismatches'])} правила не минават round-trip "
              "спрямо изходната 2026 стар стил — пусни extract_rules.py и "
              "оправи, преди да генерираш нещо.")
        sys.exit(1)

    saints = build_saints(r, args.year, old_style)
    cd_rows, weeks_rows, sundays_rows = build_calendar_days(saints, args.year, old_style)

    os.makedirs(OUT_DIR, exist_ok=True)
    out_path = os.path.join(OUT_DIR, f'calendar_{args.style}_{args.year}.db')
    write_db(out_path, saints, cd_rows, weeks_rows, sundays_rows, src_db)

    print(f'{out_path}')
    print(f'saints={len(saints)} calendar_days={len(cd_rows)} '
          f'weeks={len(weeks_rows)} sundays={len(sundays_rows)}')
    if args.year != 2026 or not old_style:
        print('ЗАБЕЛЕЖКА: readings е преписана от 2026 стар стил непроменена '
              '— датите ѝ НЕ отговарят на тази (година,стил). Собствен '
              'генератор още няма.')


if __name__ == '__main__':
    main()
