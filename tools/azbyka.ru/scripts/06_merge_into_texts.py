#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
06_merge_into_texts.py — Допълва ../db/texts.csv с нови slug-ове от
суров parse файл (изхода на 04_parse_saints.py), БЕЗ да презаписва
съществуващи редове.

ЗАЩО: ../db/texts.csv е курираната, вечна таблица с текстовете
(slug-ключувана) — там може да има РЪЧНИ редакции. Пускането на
04_parse_saints.py --slugs-file произвежда нов суров CSV само за
липсващите slug-ове; тук той се слива в texts.csv, вместо да го
презаписва целия наново (както правеше старият 08_split.py).

Вход:
  --in ПЪТ           суров CSV от 04_parse_saints.py
                      (по подразбиране output/saints_raw_ru_missing.csv)
  ../db/texts.csv     базата, в която се слива (ако липсва — създава се)

Изход:
  ../db/texts.csv     обновена (със .bak_ЧАС backup преди презапис)

По подразбиране: slug, който вече го има в texts.csv, се ПРЕСКАЧА
(пази ръчните редакции). За изрична принудителна замяна: --overwrite.

CSV конвенция: разделител |, ограда ' (както при другите скриптове).
"""

import argparse
import csv
import os
import shutil
import sys
from datetime import datetime

csv.field_size_limit(sys.maxsize)

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.dirname(SCRIPT_DIR)
OUT_DIR = os.path.join(PROJECT_DIR, "output")
DB_DIR = os.path.join(PROJECT_DIR, "db")
TEXTS_CSV = os.path.join(DB_DIR, "texts.csv")

FIELDS = [
    "slug", "name", "dates_own", "dates_all", "dates_labelled",
    "life", "sluzhba",
    "tropar", "tropar_trans", "tropar2", "tropar2_trans",
    "kondak", "kondak_trans", "kondak2", "kondak2_trans",
    "source",
]

# texts.csv колона ← суров (04_parse_saints.py) колона
MAP = [
    ("slug", "slug"),
    ("name", "name"),
    ("dates_own", "dates_own"),
    ("dates_all", "dates_all"),
    ("dates_labelled", "dates_labelled"),
    ("life", "life_html"),
    ("sluzhba", "sluzhba"),
    ("tropar", "tropar"),
    ("tropar_trans", "tropar_trans"),
    ("tropar2", "tropar2"),
    ("tropar2_trans", "tropar2_trans"),
    ("kondak", "kondak"),
    ("kondak_trans", "kondak_trans"),
    ("kondak2", "kondak2"),
    ("kondak2_trans", "kondak2_trans"),
    ("source", "url"),
]


def read_csv(path):
    with open(path, encoding="utf-8", newline="") as f:
        return list(csv.DictReader(f, delimiter="|", quotechar="'"))


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--in", dest="infile",
                    default=os.path.join(OUT_DIR, "saints_raw_ru_missing.csv"),
                    help="суров CSV от 04_parse_saints.py за сливане")
    ap.add_argument("--overwrite", action="store_true",
                    help="презаписва slug-ове, които вече ги има в texts.csv "
                         "(по подразбиране се пропускат)")
    args = ap.parse_args()

    if not os.path.exists(args.infile):
        print(f"Липсва {args.infile}.")
        sys.exit(1)

    existing = read_csv(TEXTS_CSV) if os.path.exists(TEXTS_CSV) else []
    by_slug = {r["slug"]: r for r in existing if r.get("slug")}

    raw_rows = read_csv(args.infile)

    added = 0
    overwritten = 0
    skipped = 0
    for r in raw_rows:
        slug = r.get("slug", "").strip()
        if not slug:
            continue
        row = {a: r.get(b, "") for a, b in MAP}
        if slug in by_slug:
            if args.overwrite:
                by_slug[slug] = row
                overwritten += 1
            else:
                skipped += 1
            continue
        by_slug[slug] = row
        added += 1

    if os.path.exists(TEXTS_CSV):
        stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        backup = TEXTS_CSV + f".bak_{stamp}"
        shutil.copy2(TEXTS_CSV, backup)
        print(f"Backup: {backup}")

    os.makedirs(DB_DIR, exist_ok=True)
    with open(TEXTS_CSV, "w", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(f, fieldnames=FIELDS, delimiter="|",
                           quotechar="'", quoting=csv.QUOTE_MINIMAL,
                           extrasaction="ignore")
        w.writeheader()
        # Стабилен ред: първо старите (в оригиналния им ред), после новите.
        for slug, row in by_slug.items():
            w.writerow(row)

    print("=" * 58)
    print(f"Вход                : {len(raw_rows)} реда от {args.infile}")
    print(f"Добавени (нови)     : {added}")
    print(f"Презаписани         : {overwritten}"
          + ("" if args.overwrite else "  (0, защото няма --overwrite)"))
    print(f"Пропуснати (вече ги имаше, без --overwrite): {skipped}")
    print(f"Общо в texts.csv сега: {len(by_slug)}")
    print("=" * 58)
    print(f"\nИзход: {TEXTS_CSV}")


if __name__ == "__main__":
    main()
