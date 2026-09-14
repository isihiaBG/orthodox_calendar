#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
08_split.py — Строи ../output/lives.db (SQLite, ключувана по slug) от
../db/texts.csv — курираната таблица с текстовете.

ЗАЩО: житието на св. Атанасий Атонски не зависи от годината. Календарът
зависи (подвижните празници се местят), текстовете — не. Ако стоят заедно,
всяка нова година значи да разнасяш едни и същи мегабайти наново.

    ../db/saints.csv   годишна, лека   : id | date | name | rank | group_code | sign | slug
    ../db/texts.csv    вечна, курирана : slug | name | dates | life | sluzhba | тропари…
    ../output/lives.db SQLite експорт на texts.csv (+ достижимите доп. slug-ове)

Връзката е slug. Ред без slug няма партньор в lives.db — LEFT JOIN връща
NULL, флаговете са false, и в приложението нищо не се показва.

ИЗТОЧНИК НА ДАННИТЕ: ../db/texts.csv е основният/предпочитан източник —
РЪЧНИТЕ ти редакции там се пазят (за разлика от старата версия на този
скрипт, която препарсваше всичко наново от suровия scrape и ги губеше).
Виж 06_merge_into_texts.py за това как нови slug-ове влизат в texts.csv.

--reachable ДОПЪЛНИТЕЛНО обхожда saint:// линковете в житията/службите,
за да намери slug-ове, към които се сочи, но които още ги няма в
texts.csv (напр. отделните апостоли, споменати в житието на "Събора на
12-те апостола"). За ТЯХ съдържанието идва от ../output/saints_raw_ru.csv
(суровия, непреглеждан от теб пул) — само за да не сочи линкът в никъде;
щом слугът мине през твоя преглед и влезе в texts.csv, той автоматично
взима предимство пред суровата версия.

Пуска се от scripts/:
    python3 08_split.py --db ../db/saints.csv --reachable --extra ../output/athos_slugs.txt

Вход:
    ../db/texts.csv                курираните текстове (основен източник)
    ../output/saints_raw_ru.csv    суров pool — само за --reachable fallback
    --db ПЪТ                       лек експорт на календара (seed + отчет)

Изход:
    ../output/lives.db                 новата база с текстовете
    ../output/calendar_cleanup.sql     заявки за отслабване на календара
"""

import argparse
import csv
import os
import re
import sqlite3
import sys

csv.field_size_limit(sys.maxsize)

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.dirname(SCRIPT_DIR)
OUT_DIR = os.path.join(PROJECT_DIR, "output")
DB_DIR = os.path.join(PROJECT_DIR, "db")

TEXTS_CSV = os.path.join(DB_DIR, "texts.csv")          # основен източник
RAW = os.path.join(OUT_DIR, "saints_raw_ru.csv")        # само за --reachable fallback

LINK_RE = re.compile(r'saint://([a-z0-9\-]+)')
LIVES = os.path.join(OUT_DIR, "lives.db")
CLEANUP = os.path.join(OUT_DIR, "calendar_cleanup.sql")

SCHEMA = """
CREATE TABLE texts (
    slug            TEXT PRIMARY KEY,
    name            TEXT,   -- РЕЗЕРВНО: ползва се само когато календарът
                            -- няма ред за този светия (напр. съборните
                            -- атонци). Иначе заглавието идва от календара.
    dates_own       TEXT,   -- личните дни: "07-23;09-15"  (MM-DD)
    dates_all       TEXT,   -- всички дни, вкл. съборните
    dates_labelled  TEXT,   -- "05-05:rolling:Собор Синайских преподобных"
    life            TEXT,
    sluzhba         TEXT,
    tropar          TEXT,
    tropar_trans    TEXT,
    tropar2         TEXT,
    tropar2_trans   TEXT,
    kondak          TEXT,
    kondak_trans    TEXT,
    kondak2         TEXT,
    kondak2_trans   TEXT,
    source          TEXT    -- адресът, за атрибуция под житието
);
"""

TEXT_COLS = ["life", "sluzhba", "tropar", "tropar2", "kondak", "kondak2"]
TEXTS_COLS = ["slug", "name", "dates_own", "dates_all", "dates_labelled",
              "life", "sluzhba", "tropar", "tropar_trans", "tropar2",
              "tropar2_trans", "kondak", "kondak_trans", "kondak2",
              "kondak2_trans", "source"]

# RAW (saints_raw_ru.csv) колона → TEXTS схема, само за --reachable fallback
RAW_MAP = [
    ("slug", "slug"), ("name", "name"),
    ("dates_own", "dates_own"), ("dates_all", "dates_all"),
    ("dates_labelled", "dates_labelled"),
    ("life", "life_html"), ("sluzhba", "sluzhba"),
    ("tropar", "tropar"), ("tropar_trans", "tropar_trans"),
    ("tropar2", "tropar2"), ("tropar2_trans", "tropar2_trans"),
    ("kondak", "kondak"), ("kondak_trans", "kondak_trans"),
    ("kondak2", "kondak2"), ("kondak2_trans", "kondak2_trans"),
    ("source", "url"),
]

# Тези колони излизат от календара — вече живеят в lives.db
DROP_FROM_CALENDAR = [
    "tropar", "tropar_trans", "tropar2", "tropar2_trans",
    "kondak", "kondak_trans", "kondak2", "kondak2_trans",
    "life", "sluzhba", "source", "match_score", "year_warn",
]


def read_csv(path):
    with open(path, encoding="utf-8", newline="") as f:
        return list(csv.DictReader(f, delimiter="|", quotechar="'"))


def main():
    ap = argparse.ArgumentParser(description="Строи lives.db от db/texts.csv")
    ap.add_argument("--db", help="лек експорт на календара (seed за --reachable + за отчета)")
    ap.add_argument("--all", action="store_true",
                    help="включи и slug-овете БЕЗ никакъв текст (по подразбиране "
                         "се пропускат — те само биха надули базата)")
    ap.add_argument("--reachable", action="store_true",
                    help="ДОПЪЛНИ texts.csv с достижимите чрез saint:// линкове "
                         "slug-ове (fallback съдържание от saints_raw_ru.csv за "
                         "тези, които още ги няма в texts.csv). Иска --db.")
    ap.add_argument("--extra", action="append", default=[],
                    help="файл със слъгове, които да се включат непременно "
                         "(може повече от веднъж): --extra ../output/athos_slugs.txt")
    args = ap.parse_args()

    if args.reachable and not args.db:
        print("--reachable иска и --db (оттам тръгва обхождането).")
        sys.exit(1)

    if not os.path.exists(TEXTS_CSV):
        print(f"Липсва {TEXTS_CSV}. Пусни 06_merge_into_texts.py първо.")
        sys.exit(1)

    texts_rows = read_csv(TEXTS_CSV)
    by_slug = {r["slug"]: r for r in texts_rows if r.get("slug")}
    n_curated = len(by_slug)

    keep = None
    if args.reachable:
        if not os.path.exists(RAW):
            print(f"Липсва {RAW} — --reachable няма откъде да вземе fallback "
                  f"съдържание. Пусни 04_parse_saints.py (без --slugs-file).")
            sys.exit(1)

        # Fallback pool: суровият scrape, преведен към texts схемата.
        # texts.csv (курирано) има предимство при съвпадение на slug.
        raw_rows = read_csv(RAW)
        pool = {}
        for r in raw_rows:
            slug = r.get("slug", "")
            if not slug:
                continue
            pool[slug] = {a: r.get(b, "") for a, b in RAW_MAP}
        pool.update(by_slug)   # курираните текстове печелят пред суровите

        seed = set()
        with open(args.db, encoding="utf-8", newline="") as f:
            for r in csv.DictReader(f, delimiter="|", quotechar="'"):
                if r.get("slug"):
                    seed.add(r["slug"])
        for path in args.extra:
            if os.path.exists(path):
                for line in open(path, encoding="utf-8"):
                    if line.strip():
                        seed.add(line.strip())
            else:
                print(f"! няма {path} — пропускам")

        # Обхождане в ширина: от всяко житие/служба тръгват saint:// линкове
        # към други светии; и от ТЕХНИТЕ жития — още, докато не спре да расте.
        keep, frontier = set(), set(seed)
        hops = 0
        while frontier:
            keep |= frontier
            nxt = set()
            for slug in frontier:
                r = pool.get(slug)
                if not r:
                    continue
                for field in ("life", "sluzhba"):
                    for t in LINK_RE.findall(r.get(field, "") or ""):
                        if t not in keep:
                            nxt.add(t)
            frontier = nxt & set(pool)
            hops += 1
        print(f"Достижими: от {len(seed)} начални → {len(keep)} за {hops} стъпки "
              f"({sum(1 for s in keep if s in by_slug)} курирани + "
              f"{sum(1 for s in keep if s not in by_slug)} само от суровия pool)")

        source_rows = [pool[s] for s in keep if s in pool]
    else:
        source_rows = list(by_slug.values())

    if os.path.exists(LIVES):
        os.remove(LIVES)
    db = sqlite3.connect(LIVES)
    db.executescript(SCHEMA)

    ins = (f"INSERT OR REPLACE INTO texts ({','.join(TEXTS_COLS)}) "
           f"VALUES ({','.join('?' * len(TEXTS_COLS))})")

    n_in = n_skip = 0
    for r in source_rows:
        vals = [r.get(c, "") or "" for c in TEXTS_COLS]
        has_text = any(r.get(c) for c in TEXT_COLS)
        if not has_text and not args.all:
            n_skip += 1
            continue
        db.execute(ins, vals)
        n_in += 1

    db.commit()

    stat = {c: db.execute(
        f"SELECT COUNT(*) FROM texts WHERE {c} IS NOT NULL AND {c} != ''"
    ).fetchone()[0] for c in TEXT_COLS}
    db.execute("VACUUM")
    db.close()

    with open(CLEANUP, "w", encoding="utf-8") as f:
        f.write("-- Отслабване на календара: текстовите колони вече са в lives.db.\n")
        f.write("-- ПУСНИ ГО СЛЕД като си проверил, че lives.db е наред!\n")
        f.write("-- БЕКЪП на .db файла преди това.\n")
        f.write("-- DROP COLUMN иска SQLite 3.35+ (DB Browser го има).\n")
        f.write("-- В DB Browser махни BEGIN/COMMIT — той си държи транзакция.\n\n")
        for c in DROP_FROM_CALENDAR:
            f.write(f"ALTER TABLE saints DROP COLUMN {c};\n")
        f.write("\nVACUUM;\n")

    size = os.path.getsize(LIVES)
    print("=" * 58)
    print(f"Курирани в texts.csv   : {n_curated}")
    print(f"Кандидати за lives.db  : {len(source_rows)}")
    print(f"  влязоха в lives.db   : {n_in}")
    print(f"  пропуснати (без текст): {n_skip}")
    print("-" * 58)
    for c in TEXT_COLS:
        print(f"  с {c:<14}: {stat[c]}")
    print("-" * 58)
    print(f"lives.db               : {size / 1024 / 1024:.1f} MB")
    print("=" * 58)

    if args.db and os.path.exists(args.db):
        cal = read_csv(args.db)
        db2 = sqlite3.connect(LIVES)
        have = {r[0] for r in db2.execute("SELECT slug FROM texts")}
        db2.close()
        cal_slugs = {r["slug"] for r in cal if r.get("slug")}
        print(f"\nКалендар               : {len(cal)} реда")
        print(f"  със slug             : {len(cal_slugs)}")
        print(f"  ще намерят текст     : {len(cal_slugs & have)}")
        orphan = cal_slugs - have
        if orphan:
            print(f"  слъг БЕЗ текст       : {len(orphan)}")
            for s in list(orphan)[:5]:
                print(f"      {s}")
        extra = have - cal_slugs
        print(f"  текстове БЕЗ календарен ред: {len(extra)}")
        print("      (те са печалбата: saint:// линковете ще ги намират)")

    print(f"\nБаза  : {LIVES}")
    print(f"SQL   : {CLEANUP}")


if __name__ == "__main__":
    main()
