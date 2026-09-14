#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
find_missing_linked_slugs.py — Сканира ВСИЧКИ saint:// линкове в целия
суров pool (../output/saints_raw_ru.csv — life_html и sluzhba на всяко
вече изтеглено и парснато житие) и събира пълния списък от референтни
slug-ове. После проверява кои от тях НЯМАМЕ никъде (нито ред в
saints_raw_ru.csv, нито кеширан HTML в ../days/saints/) — тези трябва
да се изтеглят и парснат (виж workflow-а за св. ап. Павел).

Отделно докладва и slug-ове, които ГИ ИМАМЕ в суровия pool, но още не
са влезли в ../db/texts.csv (преведени) — по-малко спешно, просто за
информация.

Изход: ../output/missing_linked_slugs.txt — по един slug на ред,
готов за подаване директно на 03_fetch_saints.py --slugs.
"""

import csv
import os
import re
import sys

csv.field_size_limit(sys.maxsize)

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.dirname(SCRIPT_DIR)
OUT_DIR = os.path.join(PROJECT_DIR, "output")
DB_DIR = os.path.join(PROJECT_DIR, "db")
SAINTS_DIR = os.path.join(PROJECT_DIR, "days", "saints")

RAW_RU_CSV = os.path.join(OUT_DIR, "saints_raw_ru.csv")
TEXTS_CSV = os.path.join(DB_DIR, "texts.csv")
OUT_FILE = os.path.join(OUT_DIR, "missing_linked_slugs.txt")

LINK_RE = re.compile(r"saint://([a-zA-Z0-9\-]+)")


def read_csv(path):
    with open(path, encoding="utf-8", newline="") as f:
        return list(csv.DictReader(f, delimiter="|", quotechar="'"))


def main():
    if not os.path.exists(RAW_RU_CSV):
        print(f"Липсва {RAW_RU_CSV}.")
        sys.exit(1)

    raw_rows = read_csv(RAW_RU_CSV)
    have_raw = {r["slug"] for r in raw_rows if r.get("slug")}

    referenced = set()
    for r in raw_rows:
        for field in ("life_html", "sluzhba"):
            referenced.update(LINK_RE.findall(r.get(field) or ""))

    texts_rows = read_csv(TEXTS_CSV) if os.path.exists(TEXTS_CSV) else []
    have_texts = {r["slug"] for r in texts_rows if r.get("slug")}
    # също сканираме texts.csv — вече преведените версии на живота може
    # да съдържат линкове, липсващи от суровия (напр. ръчно добавени).
    for r in texts_rows:
        for field in ("life", "sluzhba"):
            referenced.update(LINK_RE.findall(r.get(field) or ""))

    cached_html = {fn[:-5] for fn in os.listdir(SAINTS_DIR)
                   if fn.endswith(".html")} if os.path.isdir(SAINTS_DIR) else set()

    truly_missing = sorted(referenced - have_raw - cached_html)
    not_yet_in_texts = sorted((referenced & have_raw) - have_texts)

    print(f"Общо референтни slug-ове (намерени в линкове): {len(referenced)}")
    print(f"Имаме суров ред за: {len(referenced & have_raw)}")
    print(f"От тях вече в texts.csv (преведени/курирани): "
          f"{len(referenced & have_raw & have_texts)}")
    print(f"Имаме суров ред, но НЕ СА в texts.csv (за превод, не за теглене): "
          f"{len(not_yet_in_texts)}")
    for s in not_yet_in_texts[:15]:
        print("   ", s)
    print()
    print(f"НАПЪЛНО ЛИПСВАЩИ (нито ред, нито кеширан HTML — трябва теглене): "
          f"{len(truly_missing)}")
    for s in truly_missing:
        print("   ", s)

    with open(OUT_FILE, "w", encoding="utf-8") as f:
        for s in truly_missing:
            f.write(s + "\n")
    print(f"\nСписъкът с напълно липсващите е записан в: {OUT_FILE}")
    print(f"За да ги изтеглиш: python3 03_fetch_saints.py --slugs {OUT_FILE}")


if __name__ == "__main__":
    main()
