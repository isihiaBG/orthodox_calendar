#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
05c_apply_edits.py — Нанася РЕДАКЦИОННИТЕ решения върху готовия превод.

Формите не са измислени тук: те идват от прегледа на
„Output/За редакция — руски букви.txt", където решенията са взети от
човек. Скриптът само ги разнася последователно из 12-те тома.

Две неща НЕ се пипат:
  • църковнославянските цитати („взыде вдыхаяй в лице твое", „чистоты,
    вселенны светилниче", „Елици оглашеннии, изыдите") — там ы е НА МЯСТО;
  • всичко, за което не е дадена форма.

Манастирът на Акимитите се предава ПО РАЗЛИЧЕН начин според мястото —
„незаспиващите" за чина и обителта, „Неспящите" за името в кавички.
Затова тези случаи са изброени поименно (том + група), а не се заменят
общо. Главната буква следва оригинала.

Може да се пуска повторно — вече нанесена промяна не се повтаря.

Употреба:
  python3 05c_apply_edits.py --dry-run
  python3 05c_apply_edits.py
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

# ─── Поименни поправки: (том, група, старо, ново) ────────────────────────
# Манастирът на Акимитите. Формата зависи от употребата, затова тук са
# изброени поотделно. Където в скоби е повторена същата дума, тя се сменя
# с „бдящи", за да не обяснява думата сама себе си.
TARGETED = [
    ("11(ноя)", "042_index_split_993_p04", "„Незаспиващите“", "„Неспящите“"),
    ("11(ноя)", "notes_008", "„Незаспиващите“", "„Неспящите“"),
    # Тук главната буква пада: изразът не е име на обителта, а пояснение защо
    # монасите са били наречени така. В скоби стои „бдящи", за да не обяснява
    # думата сама себе си.
    ("11(ноя)", "notes_008", "„Незаспиващи“ (неспящи)", "„незаспиващи“ (бдящи)"),
    ("11(ноя)", "notes_003", "„незаспиващи“", "„неспящи“"),
    ("12(дек)", "notes_017", "„Незаспиващите“ („на неспящите“)",
     "„Неспящите“ („на бдящите“)"),
    ("01(яну)", "notes_020", "„незаспиващите“", "„неспящите“"),
    ("02(фев)", "076_index_split_187", "незаспиващите", "неспящите"),
]

# ─── Общи замени по цяла дума ────────────────────────────────────────────
# Ключът е точната форма, както се среща в текста.
WORDS = {
    "ныне": "сега",
    "усыпалницата": "катакомбите",
    "усыпалница": "погребалница",
    "Геттэ": "Гете",
    "Владыко": "Владико",
    "Владыката": "Владиката",
    "кэ": "ке",
    "съпребывание": "съпребивание",
    "безвыходно": "неотлъчно",
    "устыди": "засрами",
    "Косноязычний": "Петелогласни (заекващ)",
    "Быт.": "Бит.",
    "хвалы": "хвалебствия",
    "пристыден": "опозорен",
    "постыдил": "засрамил",
    "Менуфиэ": "Менуфие",
    "вперён": "устремен",
    "Услышани": "Чути",
    "пафаны": "пафа́ни",
    "побыде": "побъде",
    "Побыди": "Побъди",
    "невыразима": "неизказуема",
}

# Славянските цитати. Ако след всички замени в текста остане някоя от тези
# думи — това е ОЧАКВАНО и не е пропуск.
SLAVONIC = {"чистоты", "вселенны", "взыде", "вдыхаяй", "изыдите"}


def apply_words(text):
    n = 0
    for old, new in sorted(WORDS.items(), key=lambda x: -len(x[0])):
        # Цяла дума: пред и след нея да няма буква. „Быт." носи точка, затова
        # десният ограничител е гледане напред, а не \b.
        pat = r"(?<![А-Яа-яA-Za-zЁё])%s(?![А-Яа-яA-Za-zЁё])" % re.escape(old)
        text, k = re.subn(pat, new, text)
        n += k
    return text, n


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    # 1) поименните
    hit_targeted = 0
    for vol, gid, old, new in TARGETED:
        path = os.path.join(WORK_DIR, vol, "translated", gid + ".json")
        if not os.path.exists(path):
            print("  ✗ няма %s / %s" % (vol, gid))
            continue
        g = json.load(open(path, encoding="utf-8"))
        n = 0
        for u in g["units"]:
            t = u.get("translated", "")
            if old in t:
                u["translated"] = t.replace(old, new)
                n += t.count(old)
        if n:
            hit_targeted += n
            print("  %-9s %-26s %-34s → %s  (%d)"
                  % (vol, gid[:26], old, new, n))
            if not args.dry_run:
                json.dump(g, open(path, "w", encoding="utf-8"),
                          ensure_ascii=False, indent=1)

    # 2) общите
    hit_words, touched = 0, 0
    for path in sorted(glob.glob(os.path.join(WORK_DIR, "*", "translated",
                                              "*.json"))):
        g = json.load(open(path, encoding="utf-8"))
        dirty = 0
        for u in g["units"]:
            t = u.get("translated")
            if not t:
                continue
            nt, n = apply_words(t)
            if n:
                u["translated"] = nt
                dirty += n
        if dirty:
            hit_words += dirty
            touched += 1
            if not args.dry_run:
                json.dump(g, open(path, "w", encoding="utf-8"),
                          ensure_ascii=False, indent=1)

    print()
    print("поименни поправки : %d" % hit_targeted)
    print("общи замени       : %d в %d групи" % (hit_words, touched))

    # 3) какво остава с руски букви
    left = {}
    for path in glob.glob(os.path.join(WORK_DIR, "*", "translated", "*.json")):
        g = json.load(open(path, encoding="utf-8"))
        for u in g["units"]:
            for m in re.finditer(r"\S*[ыэё]\S*", u.get("translated", "")):
                w = m.group(0).strip(".,;:!?()«»„“⟦⟧")
                left[w] = left.get(w, 0) + 1
    print()
    print("остават с руски букви: %d места" % sum(left.values()))
    for w, n in sorted(left.items(), key=lambda x: -x[1]):
        mark = "славянски цитат ✓" if w in SLAVONIC else "← ПРОВЕРИ"
        print("   %-16s %d  %s" % (w, n, mark))
    if args.dry_run:
        print("\n(--dry-run: нищо не е записано)")


if __name__ == "__main__":
    main()
