#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
05b_titles.py — Привежда заглавията на 12-те тома към единен образец.

05_normalize.py изравнява само низове, чийто РУСКИ текст съвпада дума по
дума. Заглавията обаче се различават по месец („месяц январь" срещу „месяц
февраль"), тъй че за него те са различни низове и остават както ги е
превел моделът. А той ги е превел на воля:

  01  „Жития на светии — месец януари"      (без члена „-те")
  06  „месец юний"                          (архаична форма)
  08  „Жития на светиите – месец август"    (късо тире вместо дълго)
  11  „Месец ноемврий"                      (главна буква + архаична форма)

За комплект от 12 тома това личи най-много, защото заглавието се показва в
библиотеката на четеца, едно под друго. Затова тук те НЕ се превеждат, а се
СГЛОБЯВАТ по образец: „Жития на светиите — месец <име>".

Пипат се само заглавните низове (dc:title, docTitle в ncx, редът с месеца на
заглавната страница). Текстът на житията и бележките не се докосва.

Вход/изход:
  ../work/*/translated/meta_toc.json и extra_text.json  (на място)

Употреба:
  python3 05b_titles.py --dry-run
  python3 05b_titles.py
"""

import argparse
import glob
import json
import os
import re
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.dirname(SCRIPT_DIR)
WORK_DIR = os.path.join(PROJECT_DIR, "work")

MONTHS = {"01": "януари", "02": "февруари", "03": "март", "04": "април",
          "05": "май", "06": "юни", "07": "юли", "08": "август",
          "09": "септември", "10": "октомври", "11": "ноември",
          "12": "декември"}

BOOK = "Жития на светиите"
TITLE = "%s — месец %s"          # дълго тире, както е в 10 от 12 тома
MONTH_LINE = "месец %s"

# Низ, който изглежда като заглавие на тома: започва с „Жития на свет…" и
# съдържа „месец". Достатъчно тясно, за да не закачи текст от житие.
RE_TITLE_LIKE = re.compile(r"^Жития на свет\S*\s*[—–-]\s*месец\s+\S+$")
RE_MONTH_LIKE = re.compile(r"^[Мм]есец\s+\S+$")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    vols = sorted(os.path.basename(d) for d in glob.glob(os.path.join(WORK_DIR, "*"))
                  if os.path.isdir(os.path.join(d, "translated")))
    changed = 0
    for vol in vols:
        num = vol[:2]
        if num not in MONTHS:
            continue
        title = TITLE % (BOOK, MONTHS[num])
        month = MONTH_LINE % MONTHS[num]

        for name in ("meta_toc.json", "extra_text.json"):
            path = os.path.join(WORK_DIR, vol, "translated", name)
            if not os.path.exists(path):
                continue
            g = json.load(open(path, encoding="utf-8"))
            dirty = False
            for u in g["units"]:
                t = (u.get("translated") or "").strip()
                want = (title if RE_TITLE_LIKE.match(t)
                        else month if RE_MONTH_LIKE.match(t) else None)
                if want and t != want:
                    print("  %-9s %-46s → %s" % (vol, t, want))
                    u["translated"] = want
                    dirty = True
                    changed += 1
            if dirty and not args.dry_run:
                with open(path, "w", encoding="utf-8") as f:
                    json.dump(g, f, ensure_ascii=False, indent=1)

    print("\nприведени низа: %d" % changed)
    if args.dry_run:
        print("(--dry-run: нищо не е записано)")


if __name__ == "__main__":
    main()
