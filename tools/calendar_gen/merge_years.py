#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
merge_years.py — слепва календарите на няколко години в ЕДНА база.

build.py прави по един файл на (година, стил). Този скрипт ги събира, за да
може приложението да носи няколко години наведнъж (и търсенето да ги
филтрира по година — виж search_screen.dart).

    python3 merge_years.py --years 2025 2026 2027 --style old
    python3 merge_years.py --years 2025 2026 2027 --style new --out моя.db

Липсващите години се генерират автоматично с build.py.

Как се слива всяка таблица и защо:

  calendar_days   ключът е датата, а годините не се застъпват → направо.
                  ЕДИНСТВЕНО week_id/sunday_id трябва да се преномерират
                  заедно с таблиците, към които сочат (виж по-долу).
  sundays, weeks  номерата им са малки и започват от 1 във ВСЯКА година,
                  тъй че при сливане се застъпват. Затова всяка следваща
                  година получава отместване, и то се нанася и в
                  calendar_days. Имената се повтарят между годините — това
                  е нарочно: така търсенето връща по едно попадение на
                  година, а не едно общо.
  saints          автономер → вмъкват се без id и SQLite ги преномерира.
  readings        ВЗИМА СЕ САМО ОТ ПЪРВАТА година. build.py я преписва
                  непроменена от 2026 стар стил за всяка (година, стил) —
                  датите ѝ вече не отговарят на годината, тъй че сливането
                  им би било просто дублиране на един и същ боклук.
  останалите      (fast_types, fast_periods, fast_explanations,
                  saint_ranks, saint_groups) са справочни и еднакви за
                  всички години → идват с основата и не се пипат.
"""

import argparse
import os
import shutil
import sqlite3
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
OUT_DIR = os.path.join(HERE, "out")

# Таблици, които идват само с основата (справочни, еднакви за всяка година).
BASE_ONLY = {"fast_types", "fast_periods", "fast_explanations",
             "saint_ranks", "saint_groups", "readings"}


def year_db(year, style):
    return os.path.join(OUT_DIR, "calendar_%s_%d.db" % (style, year))


def ensure_built(year, style):
    path = year_db(year, style)
    if os.path.exists(path):
        return path
    print("  %d/%s липсва — генерирам…" % (year, style))
    subprocess.run([sys.executable, os.path.join(HERE, "build.py"),
                    "--year", str(year), "--style", style],
                   cwd=HERE, check=True, capture_output=True)
    if not os.path.exists(path):
        print("build.py не произведе %s" % path)
        sys.exit(1)
    return path


def merge(years, style, out):
    years = sorted(set(years))
    paths = [ensure_built(y, style) for y in years]

    if os.path.exists(out):
        os.remove(out)
    shutil.copy2(paths[0], out)
    print("основа: %s" % os.path.basename(paths[0]))

    db = sqlite3.connect(out)
    for year, path in zip(years[1:], paths[1:]):
        db.execute("ATTACH DATABASE ? AS src", (path,))

        # Отместването се смята ПРЕДИ вмъкването — иначе новите редове
        # влизат в сметката и номерата тръгват да се застъпват сами със себе
        # си.
        sun_off = db.execute("SELECT COALESCE(MAX(id), 0) FROM sundays").fetchone()[0]
        wk_off = db.execute("SELECT COALESCE(MAX(id), 0) FROM weeks").fetchone()[0]

        db.execute("INSERT INTO sundays (id, name, note, tone) "
                   "SELECT id + ?, name, note, tone FROM src.sundays", (sun_off,))
        db.execute("INSERT INTO weeks (id, name, note, tone) "
                   "SELECT id + ?, name, note, tone FROM src.weeks", (wk_off,))
        db.execute(
            "INSERT INTO calendar_days "
            "(date, tone, fast_period, fast_type, fast_explanation_key, "
            " week_id, sunday_id, note) "
            "SELECT date, tone, fast_period, fast_type, fast_explanation_key, "
            "       CASE WHEN week_id   IS NULL THEN NULL ELSE week_id   + ? END, "
            "       CASE WHEN sunday_id IS NULL THEN NULL ELSE sunday_id + ? END, "
            "       note FROM src.calendar_days",
            (wk_off, sun_off))
        db.execute("INSERT INTO saints (date, name, rank, group_code, sign, slug) "
                   "SELECT date, name, rank, group_code, sign, slug FROM src.saints")

        db.commit()
        db.execute("DETACH DATABASE src")
        print("  + %d" % year)

    lo, hi = db.execute("SELECT MIN(date), MAX(date) FROM calendar_days").fetchone()
    days = db.execute("SELECT COUNT(*) FROM calendar_days").fetchone()[0]
    saints = db.execute("SELECT COUNT(*) FROM saints").fetchone()[0]
    orphans = db.execute(
        "SELECT COUNT(*) FROM calendar_days cd "
        "WHERE (cd.sunday_id IS NOT NULL "
        "       AND NOT EXISTS (SELECT 1 FROM sundays s WHERE s.id = cd.sunday_id)) "
        "   OR (cd.week_id IS NOT NULL "
        "       AND NOT EXISTS (SELECT 1 FROM weeks w WHERE w.id = cd.week_id))"
    ).fetchone()[0]
    db.commit()
    db.close()

    print("-" * 60)
    print("години: %s | дни: %d (%s → %s) | светии: %d"
          % (", ".join(map(str, years)), days, lo, hi, saints))
    if orphans:
        print("⚠ %d дни сочат към несъществуваща неделя/седмица!" % orphans)
    else:
        print("връзките към недели/седмици са наред")
    print("→ %s" % out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--years", type=int, nargs="+", required=True)
    ap.add_argument("--style", choices=["old", "new"], required=True)
    ap.add_argument("--out")
    args = ap.parse_args()

    out = args.out or os.path.join(
        OUT_DIR, "calendar_%s_%d-%d.db"
        % (args.style, min(args.years), max(args.years)))
    merge(args.years, args.style, os.path.abspath(out))


if __name__ == "__main__":
    main()
