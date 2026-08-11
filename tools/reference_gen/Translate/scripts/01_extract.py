#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
01_extract.py — Стъпка 1: разглобява текстовете от ../../input/ на единици
за превод. Безплатна и повторяема колкото искаш.

Устройството на входните файлове (проверено върху всичките 47):
  - името е "<група>-<пореден номер> <отрязано заглавие>.txt";
  - ПЪРВИЯТ непразен ред е ПЪЛНОТО заглавие (имената на файловете са
    отрязани на ~50 знака и три от тях съвпадат — затова заглавието се
    взима от съдържанието, не от името);
  - всеки абзац стои НА ЕДИН ред (редовете не са пренасяни), а абзаците са
    разделени с празни редове. В списъчните файлове (напр. съкращенията)
    празни редове почти няма и всеки ред е отделен запис.

Затова единицата за превод е "непразен ред" — работи еднакво добре и за
прозата, и за списъците, и ляга точно върху протокола "[1] …" на
02_translate_deepseek.py.

За разлика от житията ТУК НЯМА запушалки ⟦n⟧: входът е чист текст, без
никакъв markup, тъй че няма какво да се крие от модела.

Изход: ../work/units/<id>.json
  {"id": "3-05", "group": 3, "order": 5,
   "title_ru": "…", "units": ["…", "…"]}

Употреба:
  python3 01_extract.py
  python3 01_extract.py --show 2-07
"""

import argparse
import json
import os
import re
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.dirname(SCRIPT_DIR)                  # …/Translate
INPUT_DIR = os.path.join(os.path.dirname(PROJECT_DIR), "input")
WORK_DIR = os.path.join(PROJECT_DIR, "work")
UNITS_DIR = os.path.join(WORK_DIR, "units")

RE_NAME = re.compile(r"^(\d+)-(\d+)\s+(.*)\.txt$")


def extract_one(path):
    name = os.path.basename(path)
    m = RE_NAME.match(name)
    if not m:
        return None, "името не е във вида <група>-<номер> <заглавие>.txt"

    group, order = int(m.group(1)), int(m.group(2))
    with open(path, encoding="utf-8") as fh:
        lines = [ln.strip() for ln in fh]

    units = [ln for ln in lines if ln]
    if not units:
        return None, "празен файл"

    # Първият непразен ред е заглавието и НЕ влиза в тялото.
    title, body = units[0], units[1:]
    if not body:
        return None, "файлът е само заглавие, без текст"

    return {
        "id": "%d-%02d" % (group, order),
        "group": group,
        "order": order,
        "file": name,
        "title_ru": title,
        "units": body,
    }, None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--show", help="покажи разглобяването на един файл (по id)")
    args = ap.parse_args()

    if not os.path.isdir(INPUT_DIR):
        print("Няма папка %s" % INPUT_DIR)
        sys.exit(1)

    os.makedirs(UNITS_DIR, exist_ok=True)
    files = sorted(f for f in os.listdir(INPUT_DIR) if f.endswith(".txt"))
    if not files:
        print("Няма .txt файлове в %s" % INPUT_DIR)
        sys.exit(1)

    ok, problems, total_units, total_chars = 0, [], 0, 0
    for name in files:
        data, err = extract_one(os.path.join(INPUT_DIR, name))
        if err:
            problems.append("%s — %s" % (name, err))
            continue

        if args.show and data["id"] == args.show:
            print("id: %s | група %d | %d единици" %
                  (data["id"], data["group"], len(data["units"])))
            print("заглавие: %s" % data["title_ru"])
            for i, u in enumerate(data["units"][:10], 1):
                print("  [%d] %s%s" % (i, u[:90], "…" if len(u) > 90 else ""))
            if len(data["units"]) > 10:
                print("  … още %d" % (len(data["units"]) - 10))
            return

        with open(os.path.join(UNITS_DIR, data["id"] + ".json"), "w",
                  encoding="utf-8") as fh:
            json.dump(data, fh, ensure_ascii=False, indent=1)
        ok += 1
        total_units += len(data["units"])
        total_chars += sum(len(u) for u in data["units"]) + len(data["title_ru"])

    if args.show:
        print("Няма файл с id %s" % args.show)
        return

    print("разглобени: %d файла | %d единици | %d символа"
          % (ok, total_units, total_chars))
    if problems:
        print("ПРОБЛЕМНИ: %d" % len(problems))
        for p in problems:
            print("  %s" % p)
    print("→ %s" % UNITS_DIR)


if __name__ == "__main__":
    main()
