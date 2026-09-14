#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
migrate_rename_by_calendar_date.py — Еднократен миграционен скрипт.

Преименува вече съществуващите файлове в ../output/translated/ и
../output/edited/ от "<дата на превода/редакцията>_(tag)_<slug>.csv" на
"<календарна дата на slug-а от ../db/saints.csv>_(tag)_<slug>.csv" —
същото правило като в 10_translate_deepseek.py / 11_edit_deepseek.py
(най-нисък rank; при равенство — най-ранната дата; "0000-00-00" ако
slug-ът изобщо няма ред в календара).

Безопасно е за повторно пускане — ако файлът вече е на правилното име,
просто се пропуска.
"""

import csv
import os
import re
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.dirname(SCRIPT_DIR)
OUT_DIR = os.path.join(PROJECT_DIR, "output")
SAINTS_CSV = os.path.join(PROJECT_DIR, "db", "saints.csv")
NO_DATE = "0000-00-00"

FNAME_RE = re.compile(r"^\d{4}-\d{2}-\d{2}_\((trans|edit)\)_(.+)\.csv$")


def load_saint_dates():
    best = {}
    with open(SAINTS_CSV, encoding="utf-8") as f:
        for row in csv.DictReader(f, delimiter="|"):
            slug = (row.get("slug") or "").strip()
            d = (row.get("date") or "").strip()
            if not slug or not d:
                continue
            try:
                rank = int(row.get("rank") or 999)
            except ValueError:
                rank = 999
            key = (rank, d)
            if slug not in best or key < best[slug]:
                best[slug] = key
    return {slug: d for slug, (rank, d) in best.items()}


def migrate_dir(dirpath):
    if not os.path.isdir(dirpath):
        print(f"  (няма {dirpath}, пропускам)")
        return 0, 0, 0
    saint_dates = load_saint_dates()
    renamed = skipped = no_cal = 0
    for fn in sorted(os.listdir(dirpath)):
        m = FNAME_RE.match(fn)
        if not m:
            print(f"  ! непозната форма на име, пропускам: {fn}")
            continue
        tag, slug = m.group(1), m.group(2)
        new_date = saint_dates.get(slug, NO_DATE)
        if new_date == NO_DATE:
            no_cal += 1
        new_fn = f"{new_date}_({tag})_{slug}.csv"
        if new_fn == fn:
            skipped += 1
            continue
        src = os.path.join(dirpath, fn)
        dst = os.path.join(dirpath, new_fn)
        if os.path.exists(dst):
            print(f"  ! конфликт, {new_fn} вече съществува — пропускам {fn}")
            continue
        os.rename(src, dst)
        renamed += 1
        print(f"  {fn}  ->  {new_fn}")
    return renamed, skipped, no_cal


def main():
    for sub in ("translated", "edited"):
        dirpath = os.path.join(OUT_DIR, sub)
        print(f"=== {sub}/ ===")
        renamed, skipped, no_cal = migrate_dir(dirpath)
        print(f"  преименувани: {renamed} | вече наред: {skipped} | "
              f"без календарен ред (0000-00-00): {no_cal}")
        print()


if __name__ == "__main__":
    main()
