#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
athos_slice.py — Изважда САМО светогорските светии от saints_raw_ru.csv
и произвежда малък CSV за преглед (без житията и службите).

Пуска се от scripts/:
    python3 athos_slice.py

Вход:
    ../output/athos_slugs.txt      (132-та слъга)
    ../output/saints_raw_ru.csv    (парснатото от 04)

Изход:
    ../output/athos_slice.csv      — малък, за качване/преглед

Житието и службата не се пренасят — само дали ги ИМА (има_житие / има_служба),
за да остане файлът малък.
"""

import csv
import os
import sys

csv.field_size_limit(sys.maxsize)

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
OUT_DIR = os.path.join(os.path.dirname(SCRIPT_DIR), "output")

SLUGS = os.path.join(OUT_DIR, "athos_slugs.txt")
RAW = os.path.join(OUT_DIR, "saints_raw_ru.csv")
DEST = os.path.join(OUT_DIR, "athos_slice.csv")

FIELDS = ["slug", "name", "dates_own", "dates_all", "sign",
          "has_life", "has_sluzhba", "has_tropar", "has_kondak",
          "children", "review"]


def main():
    for p in (SLUGS, RAW):
        if not os.path.exists(p):
            print(f"Липсва {p}")
            sys.exit(1)

    want = [l.strip() for l in open(SLUGS, encoding="utf-8") if l.strip()]
    want_set = set(want)

    with open(RAW, encoding="utf-8", newline="") as f:
        rows = {r["slug"]: r for r in csv.DictReader(f, delimiter="|", quotechar="'")
                if r["slug"] in want_set}

    missing = [s for s in want if s not in rows]

    out = []
    for slug in want:                      # пазим реда от списъка
        r = rows.get(slug)
        if not r:
            continue
        out.append({
            "slug": slug,
            "name": r.get("name", ""),
            "dates_own": r.get("dates_own", ""),
            "dates_all": r.get("dates_all", ""),
            "sign": r.get("sign", ""),
            "has_life": "1" if r.get("life_html") else "",
            "has_sluzhba": "1" if r.get("sluzhba") else "",
            "has_tropar": "1" if r.get("tropar") else "",
            "has_kondak": "1" if r.get("kondak") else "",
            "children": r.get("children", ""),
            "review": r.get("review", ""),
        })

    with open(DEST, "w", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(f, fieldnames=FIELDS, delimiter="|", quotechar="'",
                           quoting=csv.QUOTE_MINIMAL)
        w.writeheader()
        w.writerows(out)

    print("=" * 56)
    print(f"В списъка          : {len(want)}")
    print(f"Намерени в парснатото: {len(out)}")
    if missing:
        print(f"НЕ са парснати     : {len(missing)}")
        for s in missing[:10]:
            print(f"    {s}")
        if len(missing) > 10:
            print(f"    … и още {len(missing) - 10}")
    print("-" * 56)
    print(f"С житие            : {sum(1 for r in out if r['has_life'])}")
    print(f"Със служба         : {sum(1 for r in out if r['has_sluzhba'])}")
    print(f"С тропар           : {sum(1 for r in out if r['has_tropar'])}")
    print(f"Без личен ден      : {sum(1 for r in out if not r['dates_own'])}")
    print("=" * 56)
    size = os.path.getsize(DEST)
    print(f"\nИзход: {DEST}  ({size / 1024:.0f} KB)")


if __name__ == "__main__":
    main()
