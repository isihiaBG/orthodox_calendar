#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
16_build_hymns_table.py — сглобява таблицата `hymns` в assets/db/lives.db
от output/hymns.csv плюс преводите от output/hymns_translated/.

  output/hymns.csv            ← 14_extract_hymns.py
  output/hymns_translated/    ← 15_translate_hymns.py
                              →  lives.db.hymns

Таблицата замества осемте колони (tropar, tropar2, kondak, kondak2 и
преводите им), които побираха най-много по два от вид. Тук редът е ред,
тъй че светия с три тропара и пет кондака се събира без схемата да се
пипа пак.

Схема:
  slug     кой светия — същият слъг както в texts
  ord      редът на страницата, от 1; заедно със slug е първичен ключ
  kind     tropar | kondak | molitva | velichanie | other
  kind_ru  оригиналното заглавие: "Ин тропарь", "2-я Молитва"
  seq      кой пореден е вътре във вида си, от 1
  glas     "глас 4" или празно
  csl      църковнославянският текст, БЕЗ заглавната част
  bg       българският превод (празен при молитвите и величанията —
           azbyka не дава руски превод за тях)
  note     бележка, когато редът има особеност (виж 14_extract_hymns.py)

⚠ Заглавието („Тропар, глас 4“) НЕ се пази тук, а се строи в Dart от
kind/seq/glas. Нарочно: промяна в кода се вижда с горещо презареждане, а
промяна в базата иска НОВ БИЛД — горещото презареждане не пренася
assets/. Думата се нагласява по-евтино от страната на приложението.

⚠ Резервното копие се пише в db/backups/, НЕ до базата в assets/db/.
pubspec.yaml включва цялата папка assets/db/, тъй че всяко копие,
оставено там, влиза в пакета и потребителите го теглят.

⚠ Ако записът гръмне с „database is locked", провери с `lsof` дали
sqlitebro държи базата отворена, и я затвори — не форсирай.

Употреба:
  python3 16_build_hymns_table.py --dry-run
  python3 16_build_hymns_table.py
"""

import argparse
import csv
import datetime
import glob
import json
import os
import re
import shutil
import sqlite3
import sys

csv.field_size_limit(sys.maxsize)

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.dirname(SCRIPT_DIR)
OUT_DIR = os.path.join(PROJECT_DIR, "output")
IN_CSV = os.path.join(OUT_DIR, "hymns.csv")
TRANSLATED_DIR = os.path.join(OUT_DIR, "hymns_translated")
BACKUP_DIR = os.path.join(PROJECT_DIR, "db", "backups")
LIVES_DB = "/home/mypc/orthodox_calendar/assets/db/lives.db"

SCHEMA = """
CREATE TABLE hymns (
    slug     TEXT    NOT NULL,
    ord      INTEGER NOT NULL,
    kind     TEXT    NOT NULL,
    kind_ru  TEXT,
    seq      INTEGER NOT NULL,
    glas     TEXT,
    csl      TEXT,
    bg       TEXT,
    note     TEXT,
    PRIMARY KEY (slug, ord)
);
CREATE INDEX hymns_slug_kind ON hymns(slug, kind);
"""


# ⚠ Моделът понякога ПОВТАРЯ заглавието от промпта в началото на превода:
# "Тропар, глас 4\nТвоите мъченици, Господи…" (26 от 148 текста), а веднъж
# и с номера — "[1] кондак, глас 2\n…". Заглавието се рисува отделно, от
# kind_ru и glas, тъй че оставено там излиза ДВА пъти на екрана.
#
# Чисти се тук, а не в 15_translate_hymns.py, за да не се плаща наново за
# вече преведеното; лекува и старите файлове, и бъдещите.
#
# ⚠ Признакът е „заглавие на СВОЙ ред": само 28 от 1696 превода изобщо
# съдържат нов ред, 26 от тях са тъкмо тези. Другите два са преводи,
# разположени на строфи (св. Фива Римска, св. Владимир) — те не започват
# с име на вид и не се пипат.
REPEATED_HEAD_RE = re.compile(
    r"^\s*(?:\[\d+\]\s*)?"
    r"(?:тропар|кондак|молитва|величание|песнопение|стихира)\b[^\n]*\n+",
    re.IGNORECASE)


def strip_repeated_heading(bg: str) -> str:
    return REPEATED_HEAD_RE.sub("", bg, count=1).strip()


def load_translations():
    """slug → {ord: български текст} от преведените файлове."""
    out = {}
    for path in glob.glob(os.path.join(TRANSLATED_DIR, "*.json")):
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
        out[data["slug"]] = data.get("bg", {})
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true",
                    help="само отчита, без да пипа базата")
    args = ap.parse_args()

    with open(IN_CSV, encoding="utf-8", newline="") as f:
        rows = list(csv.DictReader(f, delimiter="|", quotechar='"'))
    trans = load_translations()

    filled = cleaned = 0
    for r in rows:
        if not r["bg"].strip():
            got = trans.get(r["slug"], {}).get(str(r["ord"]), "")
            if got:
                stripped = strip_repeated_heading(got)
                if stripped != got.strip():
                    cleaned += 1
                r["bg"] = stripped
                filled += 1

    with_bg = sum(1 for r in rows if r["bg"].strip())
    no_bg_but_ru = sum(1 for r in rows if r["ru"].strip() and not r["bg"].strip())
    csl_only = sum(1 for r in rows if not r["ru"].strip() and not r["bg"].strip())

    print(f"редове общо        : {len(rows)}")
    print(f"с български текст  : {with_bg}   (от които {filled} новопреведени)")
    if cleaned:
        print(f"махнато повторено заглавие: {cleaned}")
    print(f"само ЦСЛ, без превод: {csl_only}   (молитви/величания — очаквано)")
    if no_bg_but_ru:
        print(f"⚠ имат руски, но НЕ и български: {no_bg_but_ru} — пусни 15_translate_hymns.py")

    if args.dry_run:
        print("\n(dry-run — базата не е пипана)")
        return 0

    if not os.path.exists(LIVES_DB):
        print(f"няма {LIVES_DB}", file=sys.stderr)
        return 1

    os.makedirs(BACKUP_DIR, exist_ok=True)
    stamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
    backup = os.path.join(BACKUP_DIR, f"lives.db.bak-{stamp}")
    shutil.copy2(LIVES_DB, backup)
    print(f"\nрезервно копие: {backup}")

    db = sqlite3.connect(LIVES_DB)
    try:
        db.execute("DROP TABLE IF EXISTS hymns")
        db.executescript(SCHEMA)
        db.executemany(
            "INSERT INTO hymns (slug, ord, kind, kind_ru, seq, glas, csl, bg, note)"
            " VALUES (?,?,?,?,?,?,?,?,?)",
            [(r["slug"], int(r["ord"]), r["kind"], r["kind_ru"], int(r["seq"]),
              r["glas"], r["csl"], r["bg"], r["note"]) for r in rows])
        db.commit()
    except sqlite3.OperationalError as e:
        print(f"\n✗ {e}", file=sys.stderr)
        if "locked" in str(e):
            print("  Провери с `lsof` дали sqlitebro държи базата отворена.",
                  file=sys.stderr)
        return 1
    finally:
        db.close()

    db = sqlite3.connect(LIVES_DB)
    n, saints = db.execute(
        "SELECT count(*), count(DISTINCT slug) FROM hymns").fetchone()
    print(f"→ hymns: {n} реда у {saints} светии")
    for kind, c in db.execute(
            "SELECT kind, count(*) FROM hymns GROUP BY kind ORDER BY 2 DESC"):
        print(f"    {c:6}  {kind}")
    db.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
