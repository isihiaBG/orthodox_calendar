#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Създава и пълни saint_dmitry_refs в assets/db/lives.db от резултата
на ръчния преглед (input/manual_review.csv).

Ключът е `slug` (СЪЩИЯТ, който вече свързва saints с lives.texts/hymns),
НЕ saints.id — той е автономериран наново при всяко пускане на
merge_years.py и се дублира по веднъж на година в многогодишна база
(потвърдено: „Св. царица Теодора" излиза с id 143/1279/2411 в трите
години, но с ЕДИН И СЪЩ slug). Затова първо се превежда saint_id (от
manual_review.csv, отнасящ се към СЕМЕТО — tools/calendar_gen/input/db/
calendar_old.db) в slug, четейки директно от СЕГАШНОТО състояние на
семето — не от остарялото output/saints.csv (правено преди почистването
на дублажите и допълването на липсващите slug-ове).

Като страничен ефект решава и „братята на легитимни различни дни" (напр.
Мария Египетска, подвижен + неподвижен празник) БЕЗ отделен run — двата
реда в saints делят един slug, тъй че една връзка в saint_dmitry_refs
важи и за двата автоматично.

⚠ Трите жития на 29 февруари (num 197/198/199 — Касиан Римлянин, Йоан
Варсануфий, Теоктирист Пеликитски) НЕ идват от manual_review.csv, а са
добавени тук изрично (LEAP_DAY_REFS) — светиите им живеят в
extract_rules.LEAP_FIXED (виж там защо), не като обикновени редове в
semeто, тъй че нямат saints.id за обичайното превеждане. Скриптът пак
трие и пълни цялата таблица наведнъж, тъй че тези три трябва да останат
тук, инак следващото пускане (напр. при добавянето на 529-те нови
светии) ще ги изтрие мълчаливо.

Пуска се без аргументи (изисква вече попълнени липсващи slug-ове в
семето — виж README.md/CLAUDE.md за списъка):
    python3 04_build_dmitry_refs.py [--dry-run]
"""
import argparse
import csv
import os
import sqlite3

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(
    os.path.abspath(__file__)))))
SEED_DB = os.path.join(ROOT, 'tools', 'calendar_gen', 'input', 'db', 'calendar_old.db')
LIVES_DB = os.path.join(ROOT, 'assets', 'db', 'lives.db')
IN_DIR = os.path.join(os.path.dirname(HERE), 'input')
REVIEW_CSV = os.path.join(IN_DIR, 'manual_review.csv')

# Виж бележката най-горе — тези три не идват от manual_review.csv, защото
# светиите им нямат saints.id (генерират се условно в build.py, вижте
# extract_rules.LEAP_FIXED). slug-овете тук трябва да съвпадат с тези там.
LEAP_DAY_REFS = [
    ('sv-kassian-ioann-kassian-rimljanin', 197, 'main'),
    ('sv-ioann-varsanufij', 198, 'main'),
    ('sv-teoktirist-pelikitskij', 199, 'main'),
]


def load_id_to_slug():
    con = sqlite3.connect(f'file:{SEED_DB}?mode=ro', uri=True)
    out = dict(con.execute('SELECT id, slug FROM saints').fetchall())
    con.close()
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--dry-run', action='store_true')
    args = ap.parse_args()

    id_to_slug = load_id_to_slug()

    rows = list(csv.DictReader(open(REVIEW_CSV, encoding='utf-8'), delimiter='|', quotechar="'"))
    linked = [r for r in rows if r['action'] in ('confirm', 'reassign')]

    refs = []  # (slug, num, kind)
    errors = []
    for r in linked:
        sid = int(r['saint_id'])
        slug = id_to_slug.get(sid)
        if not slug:
            errors.append(r)
            continue
        refs.append((slug, int(r['dmitry_num']), r['kind'] or 'main'))

    if errors:
        print(f'!!! {len(errors)} реда сочат към saint_id, който вече не '
              f'съществува в семето (изтрит дублаж без пренасочване?) — СПРЯНО:')
        for r in errors:
            print(f"    num={r['dmitry_num']} saint_id={r['saint_id']}")
        return

    refs.extend(LEAP_DAY_REFS)

    dupes = {}
    for slug, num, kind in refs:
        dupes.setdefault((slug, num), []).append(kind)
    bad = {k: v for k, v in dupes.items() if len(v) > 1}
    if bad:
        print(f'!!! {len(bad)} двойки (slug, num) се повтарят — проверка на входа:')
        for k, v in list(bad.items())[:10]:
            print(f'    {k}: {v}')
        return

    print(f'жития за връзка: {len(refs)} (от {len(linked)} потвърдени реда в прегледа)')
    kinds = {}
    for _, _, k in refs:
        kinds[k] = kinds.get(k, 0) + 1
    print('по вид:', kinds)

    if args.dry_run:
        print('--dry-run: нищо не е записано.')
        return

    con = sqlite3.connect(LIVES_DB)
    con.execute('''
        CREATE TABLE IF NOT EXISTS saint_dmitry_refs (
            slug TEXT NOT NULL,
            num  INTEGER NOT NULL,
            kind TEXT NOT NULL DEFAULT 'main',
            PRIMARY KEY (slug, num)
        )
    ''')
    con.execute('CREATE INDEX IF NOT EXISTS idx_saint_dmitry_refs_slug ON saint_dmitry_refs(slug)')
    con.execute('DELETE FROM saint_dmitry_refs')
    con.executemany(
        'INSERT INTO saint_dmitry_refs (slug, num, kind) VALUES (?,?,?)', refs)
    con.commit()

    n = con.execute('SELECT COUNT(*) FROM saint_dmitry_refs').fetchone()[0]
    n_slugs = con.execute('SELECT COUNT(DISTINCT slug) FROM saint_dmitry_refs').fetchone()[0]
    con.close()
    print(f'→ {LIVES_DB}: saint_dmitry_refs — {n} реда, {n_slugs} различни светии')


if __name__ == '__main__':
    main()
