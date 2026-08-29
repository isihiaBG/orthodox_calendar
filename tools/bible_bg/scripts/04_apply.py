#!/usr/bin/env python3
"""Подменя българския текст в `assets/db/bible.db` с разчетения.

    python3 tools/bible_bg/scripts/04_apply.py --dry-run
    python3 tools/bible_bg/scripts/04_apply.py

⚠ ПОДМЯНАТА Е СТИХ ПО СТИХ, не по книга или глава.

Има ли новият източник даден стих — подменя се; няма ли го — старият остава
непокътнат. Така ЗАГУБА Е НЕВЪЗМОЖНА ПО УСТРОЙСТВО, а не защото сме
проверили: 51 стиха от близо 37 000 не се разчитат (разпръснати по 18 книги,
най-често слети със съседния), а два псалома изобщо ги няма в източника —
46 е с празна страница, 151 връща 404.

⚠ ПСАЛТИРЪТ Е ИЗКЛЮЧЕН и това НЕ Е предпазливост, а необходимост.

Двата източника броят надписанието различно: у нас „Псалом Давидов" е стих 0
или 1, а в новия източник го няма като отделен ред. Оттам цялата номерация се
измества — новият стих 1 отговаря на нашия стих 2. Подмяна по НОМЕР там би
сложила верен текст на грешно място, което е далеч по-лошо от печатна грешка:
не се вижда при четене и разваля всяка препратка към псалом.

Псалтирът иска своя, отделна работа — виж „Какво предстои" в README.
"""

import argparse
import difflib
import json
import os
import re
import shutil
import sqlite3
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
JSON = os.path.join(ROOT, "output", "json")
DB = os.path.join(os.path.dirname(os.path.dirname(ROOT)), "assets", "db", "bible.db")

# ⚠ Копията стоят ТУК, а НЕ до самата база.
#
# `pubspec.yaml` включва цялата папка `assets/db/`, тъй че всяко `.bak` до
# базата пътува в APK-то — веднъж така заминаха 15,8 MB от 74-те. Оставено в
# `tools/`, копието не влиза никъде и няма нужда да се трие бързо: пази се за
# сравнение и разбор.
BACKUP = os.path.join(ROOT, "backup")

# ⚠ ПСАЛТИРЪТ НЕ СЕ ИЗКЛЮЧВА ЦЯЛ, а минава през ПРАГ НА ПРИЛИКА.
#
# Първоначално беше изключен изцяло — заради изместването на номерацията
# (виж докстринга). Но това изхвърляше и стотици стиха, при които двата
# източника си съвпадат и подмяната е чиста печалба.
#
# Затова: подменя се само там, където новият текст ПРИЛИЧА на стария за същия
# номер. Прилича ли — значи говорят за един и същи стих и номерацията там не
# се е разминала; не прилича ли — там е разместването и не се пипа.
#
# ⚠ Прагът 0.90 не е избран на око. Измерено върху 2609-те стиха на Псалтира,
# разпределението е ДВУПОЛЮСНО: 2066 съвпадат дословно, 302 са над 0.95, а 64
# са под 0.70 — между 0.70 и 0.95 попадат ПЕТ стиха. Тоест прагът минава през
# същинска празнина, а не през размита зона.
PSALTER_MIN_RATIO = 0.90


def norm(s):
    return re.sub(r"\s+", " ", s or "").strip()


# ⚠ ПРАГ, под който подмяната се ОТКАЗВА.
#
# Ако новият текст прилича на СЪСЕДЕН стих повече, отколкото на своя, значи
# източникът брои иначе и подмяната би сложила верен текст на грешно място.
# Открито на 28.08.2026: така се разместиха `Est 10:3` (взе стар стих 4) и
# `Sir 1:19` (взе стар стих 29, дословно) — две от 5008, но и двете невидими
# при четене, защото текстът е напълно смислен, само не е този.
SHIFT_MIN = 0.85


def looks_shifted(new_text, verse, chapter_old):
    """Верно ли е, че новият текст всъщност е ДРУГ стих от същата глава."""
    mine = chapter_old.get(verse, "")
    mine_ratio = difflib.SequenceMatcher(None, new_text, mine).ratio()
    # Прилича си със своя — няма съмнение.
    if mine_ratio >= 0.5:
        return False
    for v, t in chapter_old.items():
        if v == verse:
            continue
        if difflib.SequenceMatcher(None, new_text, t).ratio() >= SHIFT_MIN:
            return True
    return False


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true", help="само брои, не пише")
    args = ap.parse_args()

    new = {}
    for f in sorted(os.listdir(JSON)):
        if not f.endswith(".json"):
            continue
        code = f[:-5]
        with open(os.path.join(JSON, f), encoding="utf-8") as fh:
            d = json.load(fh)
        for ch, verses in d["chapters"].items():
            for v in verses:
                new[(code, int(ch), v["verse"])] = norm(v["text"])

    con = sqlite3.connect(DB)
    rows = list(con.execute(
        "SELECT book, chapter, verse, text FROM verses WHERE lang='bg'"))

    # Старият текст, подреден по глави — нужен за проверката по-долу.
    by_chapter = {}
    for b, c, v, t in rows:
        by_chapter.setdefault((b, c), {})[v] = norm(t)

    changes = []
    untouched = 0
    refused = []
    for b, c, v, old in rows:
        n = new.get((b, c, v))
        if n is None or n == norm(old):
            untouched += 1
            continue
        # ⚠ В Псалтира се иска и минимална прилика със СВОЯ стих — там
        # номерацията на двата източника се разминава на места.
        if b == "Ps":
            mine = by_chapter[(b, c)].get(v, "")
            if difflib.SequenceMatcher(None, n, mine).ratio() < PSALTER_MIN_RATIO:
                refused.append((b, c, v))
                untouched += 1
                continue
        if looks_shifted(n, v, by_chapter[(b, c)]):
            refused.append((b, c, v))
            untouched += 1
            continue
        changes.append((n, b, c, v))

    print("стихове на български : %d" % len(rows))
    print("подменени            : %d" % len(changes))
    print("оставени както са    : %d  (в тях Псалтирът)" % untouched)
    if refused:
        print("⚠ ОТКАЗАНИ (личат като разместени): %d" % len(refused))
        for b, c, v in refused[:10]:
            print("     %s %d:%s" % (b, c, v))

    if args.dry_run:
        print("\n(dry-run — нищо не е записано)")
        return

    if not changes:
        print("\nняма какво да се подмени")
        return

    # ⚠ Копие ПРЕДИ писането. Базата се пресъздава от конвейера, но онова
    # пускане тегли наново 14 625 страници от azbyka.ru — час и половина за
    # нещо, което тук струва един `cp`.
    os.makedirs(BACKUP, exist_ok=True)
    backup = os.path.join(BACKUP, "bible.db.bak-%s" % time.strftime("%Y%m%d_%H%M%S"))
    shutil.copy2(DB, backup)
    print("\nрезервно копие: tools/bible_bg/backup/%s" % os.path.basename(backup))

    con.executemany(
        "UPDATE verses SET text=? WHERE lang='bg' AND book=? AND chapter=? AND verse=?",
        changes)
    con.commit()

    left = con.execute(
        "SELECT COUNT(*) FROM verses WHERE lang='bg' AND text LIKE '%Накова%'"
    ).fetchone()[0]
    print("подменени %d стиха." % len(changes))
    print('остатъчни „Накова": %d' % left)

    # Копието не пречи никому там, където е — пази се за сравнение и разбор.
    print("\nвръщане назад при нужда:")
    print("   cp %s %s" % (backup, DB))


if __name__ == "__main__":
    main()
