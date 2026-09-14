#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
09_export_for_translation.py — Изважда от ../output/lives.db само това,
което трябва да се преведе: slug + петте преводими полета.

Преводими полета (виж texts таблицата):
  life            — житието, HTML фрагмент (руски)
  tropar_trans    — руският превод на тропара (църковнославянският tropar
                    си остава непреведен, той е вече разбираем)
  tropar2_trans   — същото за "Ин тропарь", ако има
  kondak_trans    — руският превод на кондака
  kondak2_trans   — същото за "Ин кондак", ако има

Вход:  ../output/lives.db
Изход: ../output/texts_selected.csv   (slug | life | tropar_trans |
                                        tropar2_trans | kondak_trans |
                                        kondak2_trans)

Пропускат се редове, при които и петте полета са празни (няма какво
да се превежда).
"""

import csv
import os
import sqlite3
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.dirname(SCRIPT_DIR)
OUT_DIR = os.path.join(PROJECT_DIR, "output")
LIVES_DB = os.path.join(OUT_DIR, "lives.db")
OUT_CSV = os.path.join(OUT_DIR, "texts_selected.csv")

FIELDS = ["slug", "life", "tropar_trans", "tropar2_trans",
          "kondak_trans", "kondak2_trans"]


def main():
    if not os.path.exists(LIVES_DB):
        print(f"Липсва {LIVES_DB}.")
        sys.exit(1)

    db = sqlite3.connect(LIVES_DB)
    db.row_factory = sqlite3.Row
    rows = db.execute(
        "SELECT slug, life, tropar_trans, tropar2_trans, "
        "kondak_trans, kondak2_trans FROM texts ORDER BY slug"
    ).fetchall()
    db.close()

    written = 0
    with open(OUT_CSV, "w", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(f, fieldnames=FIELDS, delimiter="|",
                           quotechar="'", quoting=csv.QUOTE_MINIMAL)
        w.writeheader()
        for r in rows:
            if not any(r[c] for c in FIELDS[1:]):
                continue
            w.writerow({c: r[c] or "" for c in FIELDS})
            written += 1

    print(f"Общо редове в texts: {len(rows)}")
    print(f"Записани (поне едно преводимо поле): {written}")
    print(f"Изход: {OUT_CSV}")


if __name__ == "__main__":
    main()
