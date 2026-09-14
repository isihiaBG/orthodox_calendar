#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
07_athos.py — Сравнява светогорския списък с таблицата saints и подготвя
добавянето на липсващите.

Пуска се от scripts/:
    python3 07_athos.py --db ../db/saints.csv

Вход:
    ../output/athos_slugs.txt      132-та слъга (от съборната страница)
    ../output/saints_raw_ru.csv    парснатото от 04 (име, дати, текстове)
    --db ПЪТ                       експорт на таблицата saints
                                   (стигат колоните id|date|name|slug|group_code)

Изход:
    ../output/athos_report.csv     пълна картина с присъда за всеки
    ../output/athos_insert.sql     готови INSERT за липсващите

Как се решава:
  1. СЛЪГ — ако базата вече има този slug, светията е там. Точно и надеждно.
  2. ИМЕ+ДЕН — ако няма слъг, но на неговия ден има подобно име → за преглед
     (вероятно е същият светия, дошъл по друг път).
  3. Иначе → липсва.

Двата вида липсващи:
  • С личен ден  → INSERT с дата; ще се появи в календара.
  • БЕЗ личен ден → INSERT с date = NULL. Такъв светия се чества САМО на
    подвижния съборен ден (2-ра неделя след Петдесетница) и няма място в
    таблица с фиксирани дати. Записът служи за справка: дневната заявка
    (WHERE date = ?) никога няма да го върне, но saint:// линковете от
    съборното житие ще го намират по слъг.

ВНИМАНИЕ: имената в INSERT-ите са РУСКИ (както са в източника). Преведи ги
после — както правиш с останалите текстове.
"""

import argparse
import csv
import os
import re
import sys
import unicodedata

csv.field_size_limit(sys.maxsize)

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
OUT_DIR = os.path.join(os.path.dirname(SCRIPT_DIR), "output")

SLUGS = os.path.join(OUT_DIR, "athos_slugs.txt")
RAW = os.path.join(OUT_DIR, "saints_raw_ru.csv")
REPORT = os.path.join(OUT_DIR, "athos_report.csv")
SQLFILE = os.path.join(OUT_DIR, "athos_insert.sql")

# Църковната година на базата: 2026-01-14 … 2027-01-13
YEAR_MAIN, YEAR_NEXT = "2026", "2027"
CUTOVER = ("01", "14")

TITLES = {
    "свт", "св", "прп", "прмч", "прмц", "сщмч", "мч", "мц", "мчч", "мцц",
    "блгв", "блж", "прав", "ап", "равноап", "вмч", "вмц", "исп",
    "преподобный", "преподобная", "преподобномученик", "преподобномученица",
    "святитель", "мученик", "мученица", "блаженный", "равноапостольный",
    "исповедник", "праведный", "священномученик", "страстотерпец",
}
STOP = {
    "и", "в", "на", "с", "из", "от", "его", "иже", "нея",
    "архиепископ", "епископ", "патриарх", "митрополит", "игумен",
    "архимандрит", "пресвитер", "иеромонах", "монах", "диакон",
    "новый", "новая", "миру", "ктитор", "чудотворец", "затворник",
}


def strip_acc(s: str) -> str:
    return "".join(c for c in unicodedata.normalize("NFD", s)
                   if unicodedata.category(c) != "Mn")


def toks(s: str) -> set:
    """Нормализирани значещи корени на името."""
    s = strip_acc(s).lower()
    s = re.sub(r"\([^)]*\)", " ", s)     # скоби
    s = re.sub(r"\d+", " ", s)           # години
    s = (s.replace("ё", "е").replace("ъ", "")
          .replace("ф", "т")             # тета: BG=Т, RU=Ф
          .replace("й", "и"))
    s = re.sub(r"[^\w\s]", " ", s)
    out = set()
    for p in s.split():
        if p in TITLES or p in STOP or len(p) < 3:
            continue
        out.add(p[:6])                   # груб стем
    return out


def to_full(md: str) -> str:
    """MM-DD → пълна дата в диапазона на базата."""
    m, d = md.split("-")
    year = YEAR_MAIN if (m, d) >= CUTOVER else YEAR_NEXT
    return f"{year}-{m}-{d}"


def sql_str(s: str) -> str:
    return "'" + s.replace("'", "''") + "'"


def main():
    ap = argparse.ArgumentParser(
        description="Сравнява светогорския списък с базата")
    ap.add_argument("--db", required=True, help="експорт на таблицата saints")
    ap.add_argument("--group", default="ATHOS",
                    help="group_code за новите (по подразбиране ATHOS)")
    ap.add_argument("--rank", default="6",
                    help="rank за новите (по подразбиране 6 = без знак)")
    ap.add_argument("--min-score", type=float, default=0.5,
                    help="праг за съвпадение по име (0..1)")
    args = ap.parse_args()

    for p in (SLUGS, RAW, args.db):
        if not os.path.exists(p):
            print(f"Липсва {p}")
            sys.exit(1)

    want = [l.strip() for l in open(SLUGS, encoding="utf-8") if l.strip()]
    with open(RAW, encoding="utf-8", newline="") as f:
        raw = {r["slug"]: r for r in csv.DictReader(f, delimiter="|", quotechar="'")}
    with open(args.db, encoding="utf-8", newline="") as f:
        db = list(csv.DictReader(f, delimiter="|", quotechar="'"))

    has_slug_col = "slug" in db[0] if db else False
    db_slugs = {r["slug"] for r in db if has_slug_col and r.get("slug")}
    by_date = {}
    for r in db:
        by_date.setdefault(r["date"], []).append(r)

    rows, inserts = [], []
    n_slug = n_name = n_add_dated = n_add_ref = 0

    for slug in want:
        r = raw.get(slug)
        if not r:
            rows.append({"slug": slug, "name": "", "dates_own": "",
                         "verdict": "НЕ Е ПАРСНАТ", "db_match": "", "score": ""})
            continue

        name = r.get("name", "")
        own = [x for x in r.get("dates_own", "").split(";") if x]

        # 1) По слъг — точно
        if slug in db_slugs:
            n_slug += 1
            rows.append({"slug": slug, "name": name,
                         "dates_own": ";".join(own),
                         "verdict": "ИМА (по слъг)", "db_match": "", "score": ""})
            continue

        # 2) По име + ден
        best = None
        for md in own:
            for c in by_date.get(to_full(md), []):
                a, b = toks(name), toks(c["name"])
                if not a or not b:
                    continue
                score = len(a & b) / min(len(a), len(b))
                if best is None or score > best[2]:
                    best = (c["name"], md, score)
        if best and best[2] >= args.min_score:
            n_name += 1
            rows.append({"slug": slug, "name": name, "dates_own": ";".join(own),
                         "verdict": "ЗА ПРЕГЛЕД (име съвпада)",
                         "db_match": best[0], "score": f"{best[2]:.2f}"})
            continue

        # 3) Липсва → INSERT
        if own:
            n_add_dated += 1
            for md in own:
                inserts.append(
                    f"INSERT INTO saints (date, name, rank, group_code, slug) "
                    f"VALUES ({sql_str(to_full(md))}, {sql_str(name)}, "
                    f"{args.rank}, {sql_str(args.group)}, {sql_str(slug)});")
            verdict = "ЛИПСВА (с ден)"
        else:
            n_add_ref += 1
            inserts.append(
                f"INSERT INTO saints (date, name, rank, group_code, slug) "
                f"VALUES (NULL, {sql_str(name)}, {args.rank}, "
                f"{sql_str(args.group)}, {sql_str(slug)});")
            verdict = "ЛИПСВА (само събор → date=NULL)"

        rows.append({"slug": slug, "name": name, "dates_own": ";".join(own),
                     "verdict": verdict,
                     "db_match": best[0] if best else "",
                     "score": f"{best[2]:.2f}" if best else ""})

    with open(REPORT, "w", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(f, fieldnames=["slug", "name", "dates_own",
                                          "verdict", "db_match", "score"],
                           delimiter="|", quotechar="'",
                           quoting=csv.QUOTE_MINIMAL)
        w.writeheader()
        w.writerows(rows)

    with open(SQLFILE, "w", encoding="utf-8") as f:
        f.write("-- Светогорски светии, които липсват в saints.\n")
        f.write("-- Имената са РУСКИ — преведи ги после.\n")
        f.write("-- date = NULL значи: чества се само на подвижния съборен\n")
        f.write("--   ден; записът е за справка и за saint:// линковете.\n")
        f.write("-- ПРЕГЛЕДАЙ преди да пуснеш. Бекъп на .db файла!\n\n")
        f.write("\n".join(inserts) + "\n")

    print("=" * 58)
    if not has_slug_col:
        print("! Експортът НЯМА колона slug — сверката е само по име.")
        print("  Изнеси и slug за по-точен резултат.\n")
    print(f"В списъка              : {len(want)}")
    print(f"  вече ги имаш (слъг)  : {n_slug}")
    print(f"  за преглед (име)     : {n_name}")
    print(f"  липсват, с ден       : {n_add_dated}")
    print(f"  липсват, само събор  : {n_add_ref}")
    print("-" * 58)
    print(f"Готови INSERT заявки   : {len(inserts)}")
    print("=" * 58)
    print(f"\nОтчет : {REPORT}")
    print(f"SQL   : {SQLFILE}")
    print("\nПрегледай отчета, преди да пуснеш SQL-а. Бекъп на базата!")


if __name__ == "__main__":
    main()
