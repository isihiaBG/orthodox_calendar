#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
06_merge.py — Сглобява НОВ saints.csv: взима съществуващата таблица и
допълва tropar / kondak / life от съвпаденията в match_auto.csv.

Вход:
  --db saints.csv              изходната таблица (id|date|name|rank|group_code|sign|tropar|kondak|life)
  output/match_auto.csv        сигурните съвпадения (от 05_match.py)
  --review output/match_review.csv   (по избор) добави и прегледаните

Изход:
  output/saints_merged.csv

ВАЖНО: текстовете са СУРОВИ, на руски / църковнославянски — непреведени.
Целта на този файл е да се види как изглежда в приложението и да се
разработи функционалността. Преводът е отделна, по-късна стъпка.

Структура на изхода (запазва твоите колони, добавя новите):
  id | date | name | rank | group_code | sign |
  tropar | tropar_trans | tropar2 | tropar2_trans |
  kondak | kondak_trans | kondak2 | kondak2_trans |
  life | source | slug | match_score | year_warn

  tropar/tropar2/kondak/kondak2  — църковнославянски (новокирилица), с гласа.
                                   НЕ подлежат на превод.
  *_trans                        — руският превод. ТОЙ се превежда на български.
  life                           — житието като едноредов HTML със saint:// линкове.
  source                         — адресът на страницата (за атрибуция под житието).

ВСИЧКИ редове от базата се запазват. Тези без съвпадение просто остават
с празни текстови полета.

CSV конвенция: разделител |, ограда ', в текста ' → " и | → /.
"""

import argparse
import csv
import os
import re
import sys

csv.field_size_limit(sys.maxsize)   # житията са дълги полета

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.dirname(SCRIPT_DIR)
OUT_DIR = os.path.join(PROJECT_DIR, "output")

# Колоните на изхода — твоите, плюс новите за втория тропар/кондак и преводите.
FIELDS = [
    "id", "date", "name", "rank", "group_code", "sign",
    "tropar", "tropar_trans", "tropar2", "tropar2_trans",
    "kondak", "kondak_trans", "kondak2", "kondak2_trans",
    "life", "sluzhba", "source", "slug", "match_score", "year_warn",
]


def read_csv(path: str) -> list[dict]:
    with open(path, encoding="utf-8", newline="") as f:
        return list(csv.DictReader(f, delimiter="|", quotechar="'"))


def clean_field(v) -> str:
    if v is None:
        return ""
    v = str(v).replace("'", '"').replace("|", "/")
    v = v.replace("\r", " ").replace("\n", " ")
    return re.sub(r"[ \t]+", " ", v).strip()


def main():
    ap = argparse.ArgumentParser(
        description="Сглобява нов saints.csv с текстовете от match_auto.csv")
    ap.add_argument("--db", required=True, help="път до изходната saints.csv")
    ap.add_argument("--review", action="store_true",
                    help="включи и съвпаденията от match_review.csv "
                         "(по-ниска увереност — маркират се в match_score)")
    ap.add_argument("--out", default=os.path.join(OUT_DIR, "saints_merged.csv"))
    args = ap.parse_args()

    db_rows = read_csv(args.db)

    # Съвпаденията, ключувани по id на твоя ред.
    matches: dict[str, dict] = {}

    auto_path = os.path.join(OUT_DIR, "match_auto.csv")
    for m in read_csv(auto_path):
        matches[m["db_id"]] = m
    n_auto = len(matches)

    n_review = 0
    if args.review:
        rev_path = os.path.join(OUT_DIR, "match_review.csv")
        if os.path.exists(rev_path):
            for m in read_csv(rev_path):
                if m["db_id"] not in matches:   # auto има предимство
                    matches[m["db_id"]] = m
                    n_review += 1
        else:
            print(f"Няма {rev_path} — пропускам.")

    out_rows = []
    filled_life = filled_tropar = filled_kondak = filled_sluzhba = 0

    for db in db_rows:
        m = matches.get(db["id"])
        row = {
            # твоите колони — както са си
            "id": db.get("id", ""),
            "date": db.get("date", ""),
            "name": db.get("name", ""),
            "rank": db.get("rank", ""),
            "group_code": db.get("group_code", ""),
            "sign": db.get("sign", ""),
            # новите — празни, ако няма съвпадение
            "tropar": "", "tropar_trans": "", "tropar2": "", "tropar2_trans": "",
            "kondak": "", "kondak_trans": "", "kondak2": "", "kondak2_trans": "",
            "life": "", "sluzhba": "", "source": "", "slug": "",
            "match_score": "", "year_warn": "",
        }

        if m:
            row["tropar"] = m.get("tropar", "")
            row["tropar_trans"] = m.get("tropar_trans", "")
            row["tropar2"] = m.get("tropar2", "")
            row["tropar2_trans"] = m.get("tropar2_trans", "")
            row["kondak"] = m.get("kondak", "")
            row["kondak_trans"] = m.get("kondak_trans", "")
            row["kondak2"] = m.get("kondak2", "")
            row["kondak2_trans"] = m.get("kondak2_trans", "")
            row["life"] = m.get("life_html", "")
            row["sluzhba"] = m.get("sluzhba", "")
            row["source"] = m.get("url", "")
            row["slug"] = m.get("slug", "")
            row["match_score"] = m.get("score", "")
            row["year_warn"] = m.get("year_warn", "")

            if row["life"]:
                filled_life += 1
            if row["tropar"]:
                filled_tropar += 1
            if row["kondak"]:
                filled_kondak += 1
            if row["sluzhba"]:
                filled_sluzhba += 1

        out_rows.append(row)

    with open(args.out, "w", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(f, fieldnames=FIELDS, delimiter="|", quotechar="'",
                           quoting=csv.QUOTE_MINIMAL, extrasaction="ignore")
        w.writeheader()
        for r in out_rows:
            w.writerow({k: clean_field(r.get(k, "")) for k in FIELDS})

    n = len(out_rows)
    print("=" * 58)
    print(f"Редове в изхода   : {n}  (всички от базата са запазени)")
    print(f"Съвпадения ползвани: {n_auto} от auto" +
          (f" + {n_review} от review" if n_review else ""))
    print("-" * 58)
    print(f"С житие           : {filled_life:>5}  ({100*filled_life/n:.1f}%)")
    print(f"С тропар          : {filled_tropar:>5}  ({100*filled_tropar/n:.1f}%)")
    print(f"С кондак          : {filled_kondak:>5}  ({100*filled_kondak/n:.1f}%)")
    print(f"Със служба        : {filled_sluzhba:>5}  ({100*filled_sluzhba/n:.1f}%)")
    print("=" * 58)
    print(f"\nИзход: {args.out}")
    print("\nТекстовете са СУРОВИ (руски/църковнославянски) — за преглед на")
    print("оформлението в приложението. Преводът е следваща стъпка.")


if __name__ == "__main__":
    main()
