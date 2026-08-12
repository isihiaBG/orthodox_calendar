#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
05_normalize.py — Стъпка 5 (МЕХАНИЧНА, без DeepSeek): изравнява превода на
изходни низове, които се повтарят ДУМА ПО ДУМА в набора.

Защо е нужно: групите се превеждат поотделно и всяка заявка е самостоятелна.
Когато един и същ руски низ се среща на две места — в два тома или на две
места в един том — моделът лесно го превежда по два начина: „Иулиан" и
„Юлиан", „посвещение в сан презвитер" и „ръкоположение в презвитерски сан",
„светител" и „светителя". В комплект от 12 тома това личи.

Тук НЕ се превежда нищо ново. За всеки изходен низ, срещащ се повече от
веднъж, се избира един вариант и се прилага навсякъде. Изборът е по
мнозинство; при равенство — вариантът от най-ранния том, за да е решението
устойчиво и повторяемо, а не случайно.

Пипат се САМО низове, чийто руски текст съвпада напълно (след свиване на
празните места). Различен изходен текст никога не се приравнява — това би
било редактиране, а не изравняване.

ВАЖНО: пуска се СЛЕД като всички томове са преведени. Пуснат по-рано,
изравнява само по това, което е налично, и по-късните томове пак ще се
разминат. Може да се пуска многократно — резултатът е един и същ.

Вход/изход:
  ../work/*/translated/*.json   (променят се на място)

Употреба:
  python3 05_normalize.py --dry-run
  python3 05_normalize.py
"""

import argparse
import collections
import glob
import json
import os
import re
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.dirname(SCRIPT_DIR)
WORK_DIR = os.path.join(PROJECT_DIR, "work")

PH = re.compile(r"⟦(\d+)⟧")
MIN_LEN = 3          # по-къси низове (пунктуация, числа) не си струват


def norm(s):
    return " ".join(s.split())


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--min-len", type=int, default=MIN_LEN)
    args = ap.parse_args()

    files = sorted(glob.glob(os.path.join(WORK_DIR, "*", "translated", "*.json")))
    if not files:
        print("Няма преведени групи.")
        sys.exit(1)

    # 1) Кой изходен низ на какви преводи е раждал и в кои томове.
    variants = collections.defaultdict(collections.Counter)
    earliest = {}
    for f in files:
        vol = f.split(os.sep)[-3]
        g = json.load(open(f, encoding="utf-8"))
        for u in g["units"]:
            t = u.get("translated")
            if not t:
                continue
            k = norm(u["text"])
            if len(k) < args.min_len:
                continue
            v = norm(t)
            variants[k][v] += 1
            earliest.setdefault((k, v), vol)

    # 2) Кой вариант печели: по мнозинство, при равенство — от най-ранния том.
    chosen, divergent = {}, 0
    for k, c in variants.items():
        if len(c) < 2:
            continue
        divergent += 1
        top = max(c.values())
        best = sorted((v for v, n in c.items() if n == top),
                      key=lambda v: (earliest[(k, v)], v))[0]
        chosen[k] = best

    print("повтарящи се изходни низове : %d"
          % sum(1 for c in variants.values() if sum(c.values()) > 1))
    print("от тях с различен превод    : %d" % divergent)

    # 3) Прилагане. Запушалките се пазят: сменяме само низове, чиито
    #    запушалки съвпадат — иначе сглобяването после няма да намери таг.
    changed, skipped, touched_files = 0, 0, 0
    for f in files:
        g = json.load(open(f, encoding="utf-8"))
        dirty = False
        for u in g["units"]:
            t = u.get("translated")
            if not t:
                continue
            k = norm(u["text"])
            want = chosen.get(k)
            if not want or norm(t) == want:
                continue
            if sorted(PH.findall(want)) != sorted(PH.findall(t)):
                skipped += 1          # различни запушалки — не пипаме
                continue
            u["translated"] = want
            changed += 1
            dirty = True
        if dirty:
            touched_files += 1
            if not args.dry_run:
                with open(f, "w", encoding="utf-8") as fh:
                    json.dump(g, fh, ensure_ascii=False, indent=1)

    print("изравнени блокове           : %d в %d групи" % (changed, touched_files))
    if skipped:
        print("прескочени (различни запушалки): %d" % skipped)
    if args.dry_run:
        print("(--dry-run: нищо не е записано)")


if __name__ == "__main__":
    main()
