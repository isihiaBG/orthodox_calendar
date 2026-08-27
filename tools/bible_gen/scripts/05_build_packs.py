#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""05_build_packs.py — реже по един ЕЗИКОВ ПАКЕТ на превод. Без мрежа.

За какво е. Пълната база с всичките дванайсет превода излиза 143 MB, а в
APK-то тя пътува цялата — тоест всеки потребител тегли и грузинския, и
иврита, за да чете на български. Затова в приложението остават ПЕТ превода
(виж `--langs` при 04_build_db.py), а останалите се предлагат за сваляне
поотделно.

    python3 05_build_packs.py                    # всички извън основните
    python3 05_build_packs.py --langs r,l,en-kjv # само тези
    python3 05_build_packs.py --list             # какво би направил

Готовите файлове излизат в `output/packs/` и се качват като assets към ЕДНО
издание в GitHub. ⚠ ТАГЪТ НА ИЗДАНИЕТО НЕ СЕ СМЕНЯ — адресите са зашити в
приложението и вече инсталираните копия теглят точно от него; смени ли се
тагът, те спират да работят, а не могат да се поправят без нов APK.

⚠ ПАКЕТЪТ Е ПЪЛНОЦЕНЕН SQLite ФАЙЛ, не изрезка. Приложението го отваря като
втора база и насочва към нея заявките за неговия език (виж BibleDb) — затова
носи същите таблици със същите имена и колони. Причината да не се влива в
основната: `bible.db` се ТРИЕ И ПРЕЗАПИСВА от assets при всяко пускане
(BibleDb.database), тъй че всичко влято в нея живее до първото рестартиране.

⚠ КАКВО НЕ ВЛИЗА в пакета: `books`, `zachala` и `headings`. Първата е обща за
всички преводи; другите две са свойство на МЯСТОТО в Писанието, не на езика,
и стоят в основната база. Инак едно и също би се повтаряло в осем файла.
"""

import argparse
import os
import shutil
import sqlite3
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.dirname(SCRIPT_DIR)
ROOT = os.path.dirname(os.path.dirname(PROJECT_DIR))
FULL_DB = os.path.join(PROJECT_DIR, "output", "bible_full.db")
BASE_DB = os.path.join(ROOT, "assets", "db", "bible.db")
OUT_DIR = os.path.join(PROJECT_DIR, "output", "packs")

# Преводите, които ПЪТУВАТ В APK-то. Всичко останало става пакет.
#
# ⚠ САМО ДВА, и това е съзнателно свито (27.08.2026). Първоначално бяха пет —
# с двата гръцки и църковнославянския на гражданска азбука — но щом свалянето
# на пакет е няколко тапа в настройките, всеки допълнителен превод в APK-то
# се плаща от ВСЕКИ потребител, за да го ползват малцина. Българският и
# църковнославянският са двойката, с която приложението има смисъл още на
# първото пускане; останалите се добавят по желание.
BASE_LANGS = ["bg", "utfcs"]

# Таблиците, които са свойство на ЕЗИКА и влизат в пакета.
LANG_TABLES = ["verses", "titles", "notes", "annotations", "links"]


def table_sql(con, name):
    row = con.execute(
        "SELECT sql FROM sqlite_master WHERE type='table' AND name=?",
        (name,)).fetchone()
    return row[0] if row else None


def build_pack(src, code, out_path):
    """Изнася един език в собствен файл."""
    if os.path.exists(out_path):
        os.remove(out_path)
    dst = sqlite3.connect(out_path)

    # Схемата се преписва ОТ ИЗТОЧНИКА, не се дублира тук: смени ли се утре
    # колона в 04_build_db.py, пакетът я поема сам.
    dst.execute(table_sql(src, "languages"))
    for t in LANG_TABLES:
        sql = table_sql(src, t)
        if sql:
            dst.execute(sql)

    row = src.execute("SELECT * FROM languages WHERE code=?", (code,)).fetchone()
    if row is None:
        dst.close()
        os.remove(out_path)
        return None
    dst.execute(
        "INSERT INTO languages VALUES (%s)" % ",".join("?" * len(row)), row)

    counts = {}
    for t in LANG_TABLES:
        if not table_sql(src, t):
            continue
        rows = src.execute("SELECT * FROM %s WHERE lang=?" % t, (code,)).fetchall()
        if rows:
            dst.executemany(
                "INSERT INTO %s VALUES (%s)" % (t, ",".join("?" * len(rows[0]))),
                rows)
        counts[t] = len(rows)

    # ⚠ Индексът по (lang, book, chapter) е СЪЩИЯТ като в основната база:
    # четецът вика една и съща заявка, независимо дали езикът е тук или там.
    dst.execute("CREATE INDEX IF NOT EXISTS idx_verses_place"
                " ON verses (lang, book, chapter)")
    dst.commit()
    # VACUUM свива файла до реално заетото — иначе носи празните страници,
    # останали от изтритото.
    dst.execute("VACUUM")
    dst.commit()
    dst.close()
    return counts


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--langs", default="",
                    help="само тези кодове (през запетая); празно = всички "
                         "извън основните")
    ap.add_argument("--src", default="",
                    help="откъде да чете (по подразбиране output/bible_full.db, "
                         "а ако го няма — assets/db/bible.db)")
    ap.add_argument("--list", action="store_true", help="само показва")
    args = ap.parse_args()

    src_path = args.src or (FULL_DB if os.path.exists(FULL_DB) else BASE_DB)
    if not os.path.exists(src_path):
        sys.exit("Няма откъде да чета: %s" % src_path)
    src = sqlite3.connect(src_path)

    have = [r[0] for r in src.execute(
        "SELECT DISTINCT lang FROM verses ORDER BY lang")]
    wanted = [c.strip() for c in args.langs.split(",") if c.strip()]
    if not wanted:
        wanted = [c for c in have if c not in BASE_LANGS]

    missing = [c for c in wanted if c not in have]
    if missing:
        sys.exit(
            "В %s няма стихове за: %s\n"
            "⚠ Пакетите се режат от ПЪЛНАТА база. Пусни първо\n"
            "   python3 04_build_db.py --out output/bible_full.db\n"
            "БЕЗ --langs, за да влязат всички преводи."
            % (os.path.basename(src_path), ", ".join(missing)))

    print("източник : %s" % src_path)
    print("пакети   : %s" % ", ".join(wanted))
    if args.list:
        return

    os.makedirs(OUT_DIR, exist_ok=True)
    print()
    print("%-8s %10s %10s %s" % ("език", "стихове", "MB", "файл"))
    print("-" * 52)
    total = 0
    for code in wanted:
        out_path = os.path.join(OUT_DIR, "bible-%s.db" % code)
        counts = build_pack(src, code, out_path)
        if counts is None:
            print("%-8s  ⚠ няма ред в languages — пропуснат" % code)
            continue
        mb = os.path.getsize(out_path) / 1048576
        total += mb
        print("%-8s %10d %10.1f %s"
              % (code, counts.get("verses", 0), mb, os.path.basename(out_path)))
    print("-" * 52)
    print("общо %.1f MB в %s" % (total, OUT_DIR))
    print()
    print("Качи ги като assets към ЕДНО издание в GitHub и НЕ сменяй тага му.")


if __name__ == "__main__":
    main()
