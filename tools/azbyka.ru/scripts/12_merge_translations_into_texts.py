#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
12_merge_translations_into_texts.py — Влива готовите преводи от
../output/translated/ (или --edited, ако вече има редакция) обратно в
../db/texts.csv, замествайки САМО преводимите полета (life, tropar_trans,
tropar2_trans, kondak_trans, kondak2_trans) с българските версии.
tropar/kondak (църковнославянски) и всички останали колони (name, dates,
sluzhba, source) остават непипнати.

Slug, който го има в превода, но НЯМА ред в texts.csv (обикновено
"reachable" допълнения — жития, достижими само чрез saint:// линк от
други жития, но никога не влезли в куратираната texts.csv) — за такива
се създава НОВ ред: останалите полета (name, dates, tropar/kondak на
църковнославянски, source) идват от ../output/saints_raw_ru.csv (суровия
scrape), а преводимите — от превода. Така влизат постоянно в texts.csv
и вътрешните линкове винаги ги намират, без да зависят от --reachable.

ЕЗИКОВ АРХИВ: първия път, когато се пусне (ако ../db/texts_ru.csv още
не съществува), прави снимка на ЦЕЛИЯ текущ (все още руски) texts.csv
като texts_ru.csv — за бъдеща многоезична поддръжка, по аналогия на
lives_ru.db. Не презаписва texts_ru.csv при следващи пускания.

Вход:
  --dir output/translated (по подразбиране) или output/edited (--edited)
  ../db/texts.csv          текущата (все още руска) база

Изход:
  ../db/texts.csv           обновен, с .bak_ЧАС резервно копие преди презапис
  ../db/texts_ru.csv        еднократна снимка на оригинала (само първия път)

След това пусни 08_split.py, за да прекомпилираш ../output/lives.db.
"""

import argparse
import csv
import glob
import os
import re
import shutil
import sys
from datetime import datetime

csv.field_size_limit(sys.maxsize)

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.dirname(SCRIPT_DIR)
OUT_DIR = os.path.join(PROJECT_DIR, "output")
DB_DIR = os.path.join(PROJECT_DIR, "db")
TEXTS_CSV = os.path.join(DB_DIR, "texts.csv")
TEXTS_RU_CSV = os.path.join(DB_DIR, "texts_ru.csv")
RAW_RU_CSV = os.path.join(OUT_DIR, "saints_raw_ru.csv")

TRANSLATABLE = ["life", "tropar_trans", "tropar2_trans",
                "kondak_trans", "kondak2_trans"]

TEXTS_FIELDS = ["slug", "name", "dates_own", "dates_all", "dates_labelled",
                "life", "sluzhba", "tropar", "tropar_trans", "tropar2",
                "tropar2_trans", "kondak", "kondak_trans", "kondak2",
                "kondak2_trans", "source"]

# RAW (saints_raw_ru.csv) колона → TEXTS схема, за slug-ове без ред в
# texts.csv (виж по-горе). Същото съответствие като в 08_split.py.
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

FNAME_RE = re.compile(r"^\d{4}-\d{2}-\d{2}_\((trans|edit)\)_(.+)\.csv$")


def read_csv(path):
    with open(path, encoding="utf-8", newline="") as f:
        return list(csv.DictReader(f, delimiter="|", quotechar="'"))


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--edited", action="store_true",
                    help="чети от output/edited/ вместо output/translated/")
    args = ap.parse_args()

    src_dir = os.path.join(OUT_DIR, "edited" if args.edited else "translated")
    if not os.path.isdir(src_dir) or not os.listdir(src_dir):
        print(f"Липсва/празна {src_dir}.")
        sys.exit(1)

    if not os.path.exists(TEXTS_CSV):
        print(f"Липсва {TEXTS_CSV}.")
        sys.exit(1)

    # Езиков архив — само първия път.
    if not os.path.exists(TEXTS_RU_CSV):
        shutil.copy2(TEXTS_CSV, TEXTS_RU_CSV)
        print(f"Създаден езиков архив: {TEXTS_RU_CSV}")
    else:
        print(f"Езиковият архив вече съществува, не се пипа: {TEXTS_RU_CSV}")

    rows = read_csv(TEXTS_CSV)
    by_slug = {r["slug"]: r for r in rows}

    # Пулът за slug-ове без ред в texts.csv — зареждаме мързеливо, само
    # ако наистина потрябва (файлът е голям).
    raw_pool = None

    def get_raw_pool():
        nonlocal raw_pool
        if raw_pool is None:
            if not os.path.exists(RAW_RU_CSV):
                raw_pool = {}
            else:
                raw_pool = {r["slug"]: r for r in read_csv(RAW_RU_CSV) if r.get("slug")}
        return raw_pool

    updated = 0
    added = 0
    no_match = []
    for path in sorted(glob.glob(os.path.join(src_dir, "*.csv"))):
        fn = os.path.basename(path)
        m = FNAME_RE.match(fn)
        if not m:
            continue
        tr = read_csv(path)
        if not tr:
            continue
        tr_row = tr[0]
        slug = tr_row["slug"]
        row = by_slug.get(slug)
        if row is None:
            raw_row = get_raw_pool().get(slug)
            if raw_row is None:
                no_match.append(slug)
                continue
            new_row = {a: raw_row.get(b, "") for a, b in RAW_MAP}
            for field in TRANSLATABLE:
                new_row[field] = tr_row.get(field, "")
            rows.append(new_row)
            by_slug[slug] = new_row
            added += 1
            continue
        for field in TRANSLATABLE:
            row[field] = tr_row.get(field, "")
        updated += 1

    stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    backup = TEXTS_CSV + f".bak_{stamp}"
    shutil.copy2(TEXTS_CSV, backup)
    print(f"Backup: {backup}")

    with open(TEXTS_CSV, "w", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(f, fieldnames=TEXTS_FIELDS, delimiter="|",
                           quotechar="'", quoting=csv.QUOTE_MINIMAL,
                           extrasaction="ignore")
        w.writeheader()
        for r in rows:
            w.writerow(r)

    print("=" * 58)
    print(f"Източник: {src_dir}")
    print(f"Обновени slug-ове в texts.csv: {updated}")
    print(f"Нови (добавени от суровия pool): {added}")
    if no_match:
        print(f"Изцяло без данни (пропуснати): {len(no_match)}")
        for s in no_match[:10]:
            print("   ", s)
    print(f"Общо редове в texts.csv: {len(rows)}")
    print("=" * 58)
    print(f"\nИзход: {TEXTS_CSV}")
    print("Следваща стъпка: python3 08_split.py --db ../db/saints.csv "
          "--reachable --extra ../output/athos_slugs.txt "
          "--extra ../output/sobor_slugs.txt")


if __name__ == "__main__":
    main()
