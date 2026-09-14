#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
13_bible_links_bg.py — Пренасочва препратките към Свещеното Писание в
lives.db към БЪЛГАРСКИ текст.

Текстовете идват от azbyka.ru и библейските препратки водят към руския
превод. Опашката „&bg~utfcs" отваря българския текст с успореден
църковнославянски (плъзга се надясно на сайта) — за приложение на български
това е правилната цел.

Правилото е едно и също навсякъде:
    вече има bg~utfcs  → не се пипа
    има &cr&rus        → заменя се
    няма опашка        → добавя се

Пипат се САМО връзките към /biblia/. Другите връзки към azbyka (към светите
отци, правилата на съборите, Минеи) нямат такъв превключвател и се оставят.
Не се пипат и saint:// връзките — те са вътрешна навигация в приложението.

Същата поправка е вградена и в 04_parse_saints.py, за да излизат вярни при
следващо сваляне. Този скрипт е за ВЕЧЕ СЪСТАВЕНАТА база.

Прави резервно копие до базата, преди да пише. Може да се пуска повторно —
резултатът е един и същ.

Употреба:
  python3 13_bible_links_bg.py --dry-run
  python3 13_bible_links_bg.py
  python3 13_bible_links_bg.py --db /път/до/lives.db
"""

import argparse
import os
import re
import shutil
import sqlite3
import sys
import time

DEFAULT_DB = os.path.expanduser("~/orthodox_calendar/assets/db/lives.db")

# Колоните, в които изобщо може да има разметка с връзки.
COLUMNS = ["life", "sluzhba", "tropar", "tropar_trans", "tropar2",
           "tropar2_trans", "kondak", "kondak_trans", "kondak2",
           "kondak2_trans", "name", "source"]

RE_BIBLE = re.compile(r'href="([^"]*azbyka\.ru/biblia/[^"]*)"')
NEW = "&amp;bg~utfcs"
OLD = "&amp;cr&amp;rus"
# „&r" е режимът за цяла книга — също руски и също се ЗАМЕНЯ.
MODES = (OLD, "&amp;r")


def fix_href(href):
    if "bg~utfcs" in href:
        return href, False
    for mode in MODES:
        if href.endswith(mode):
            return href[: -len(mode)] + NEW, True
    return href + NEW, True


def convert(text):
    """Връща (нов текст, брой сменени)."""
    if not text or "biblia" not in text:
        return text, 0
    n = 0

    def repl(m):
        nonlocal n
        new, changed = fix_href(m.group(1))
        if changed:
            n += 1
        return 'href="%s"' % new

    return RE_BIBLE.sub(repl, text), n


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--db", default=DEFAULT_DB)
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    if not os.path.exists(args.db):
        print("Няма такава база: %s" % args.db)
        sys.exit(1)

    if not args.dry_run:
        bak = "%s.bak-%s" % (args.db, time.strftime("%Y%m%d-%H%M%S"))
        shutil.copy2(args.db, bak)
        print("резервно копие: %s" % bak)

    con = sqlite3.connect(args.db)
    have = {r[1] for r in con.execute("PRAGMA table_info(texts)")}
    cols = [c for c in COLUMNS if c in have]

    total, rows_touched, per_col = 0, set(), {}
    updates = []
    for row in con.execute("SELECT slug, %s FROM texts"
                           % ", ".join('"%s"' % c for c in cols)):
        slug, values = row[0], row[1:]
        new_values, changed_here = [], 0
        for c, v in zip(cols, values):
            nv, n = convert(v)
            new_values.append(nv)
            if n:
                per_col[c] = per_col.get(c, 0) + n
                changed_here += n
        if changed_here:
            total += changed_here
            rows_touched.add(slug)
            updates.append((new_values, slug))

    print("препратки за смяна : %d" % total)
    print("засегнати светии   : %d" % len(rows_touched))
    for c, n in sorted(per_col.items(), key=lambda x: -x[1]):
        print("   %-16s %d" % (c, n))

    if args.dry_run:
        print("(--dry-run: нищо не е записано)")
        return

    sql = "UPDATE texts SET %s WHERE slug = ?" % ", ".join(
        '"%s" = ?' % c for c in cols)
    con.executemany(sql, [(*vals, slug) for vals, slug in updates])
    con.commit()

    # --- проверка ---
    left = bad = ok = 0
    for row in con.execute("SELECT %s FROM texts"
                           % ", ".join('"%s"' % c for c in cols)):
        for v in row:
            for h in RE_BIBLE.findall(v or ""):
                if "bg~utfcs" in h:
                    ok += 1
                elif OLD in h:
                    left += 1
                else:
                    bad += 1
    print()
    print("след промяната: с bg~utfcs %d | останали руски %d | без опашка %d"
          % (ok, left, bad))
    con.close()


if __name__ == "__main__":
    main()
