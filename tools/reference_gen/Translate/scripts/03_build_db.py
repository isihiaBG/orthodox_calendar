#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
03_build_db.py — Стъпка 3: сглобява преведените статии в
assets/db/reference.db, базата на секцията "Справочник".

Безплатна и повторяема — пуска се наново след всяка поправка по превода,
без нищо да се превежда пак.

Схемата е тази от първата (примерна) база, плюс две колони с оригинала:
`title_ru` и `body_ru`. Те не се показват в приложението и тежат нищожно,
но правят сверката на превода възможна по всяко време, без да се рови из
work/.

Статия без превод се ПРЕСКАЧА, а група, останала без нито една статия, не
влиза в базата — така недовършеното (напр. съкращенията, които ще се правят
на ръка) не се показва като празно поле в приложението.

Употреба:
  python3 03_build_db.py
  python3 03_build_db.py --out /друг/път/reference.db
"""

import argparse
import glob
import html
import json
import os
import re
import sqlite3
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.dirname(SCRIPT_DIR)                 # …/Translate
REFGEN_DIR = os.path.dirname(PROJECT_DIR)                 # …/reference_gen
REPO_DIR = os.path.dirname(os.path.dirname(REFGEN_DIR))   # коренът на проекта
TRANSLATED_DIR = os.path.join(PROJECT_DIR, "work", "translated")
DEFAULT_OUT = os.path.join(REPO_DIR, "assets", "db", "reference.db")

# Имената на групите — дадени от потребителя (10 август 2026 г.).
# Номерът е префиксът на файловете във входната папка.
GROUP_TITLES = {
    1: "Канонични правила",
    2: "Указания за постите по Типикона",
    3: "За поменаването на покойниците",
    4: "Редът за четене на Евангелието през Великите пости",
    5: "Използвани съкращения",
    6: "Знаците от Типикона",
}

SCHEMA = """
DROP TABLE IF EXISTS ref_articles;
DROP TABLE IF EXISTS ref_groups;

CREATE TABLE ref_groups (
    id       INTEGER PRIMARY KEY,
    title    TEXT    NOT NULL,
    position INTEGER NOT NULL
);

-- `body` е HTML — четецът (reader_screen.dart) го рендира без буквица.
-- `title_ru`/`body_ru` пазят оригинала само за сверка.
CREATE TABLE ref_articles (
    id       INTEGER PRIMARY KEY,
    group_id INTEGER NOT NULL REFERENCES ref_groups(id),
    title    TEXT    NOT NULL,
    title_ru TEXT,
    body     TEXT    NOT NULL,
    body_ru  TEXT,
    position INTEGER NOT NULL
);

CREATE INDEX idx_articles_group ON ref_articles(group_id, position);
"""


RE_ZNAK = re.compile(r"⟦znak([1-5])⟧")


def to_html(units):
    """Всяка единица е отделен абзац. Текстът се екранира — иначе случаен
    знак < или & би счупил рендирането в четеца.

    Единственото изключение са запушалките ⟦znak1⟧…⟦znak5⟧ от статията
    "Знаците от Типикона": те се превръщат в таг <znak n="…">, който четецът
    рисува със самите SVG знаци (виж _tipikonExtensions в
    reader_screen.dart). Замяната е СЛЕД екранирането — иначе то би изяло
    ъгловите скоби на тага.

    Тагът се затваря ИЗРИЧНО (<znak …></znak>), а не самозатварящо се:
    `znak` не е сред празните елементи, които HTML парсерът познава, тъй че
    <znak/> отваря елемент, който никога не се затваря — и целият останал
    текст от абзаца става негово съдържание и изчезва от изгледа."""
    out = []
    for u in units:
        if not u.strip():
            continue
        out.append("<p>%s</p>" % RE_ZNAK.sub(
            lambda m: '<znak n="%s"></znak>' % m.group(1), html.escape(u)))
    return "".join(out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=DEFAULT_OUT)
    args = ap.parse_args()

    files = sorted(glob.glob(os.path.join(TRANSLATED_DIR, "*.json")))
    if not files:
        print("Няма преведени статии в %s — пусни 02_translate_deepseek.py."
              % TRANSLATED_DIR)
        sys.exit(1)

    articles, skipped = [], []
    for f in files:
        a = json.load(open(f, encoding="utf-8"))
        if not a.get("title_bg") or not a.get("units_bg"):
            skipped.append("%s (няма превод)" % a["id"])
            continue
        if a["group"] not in GROUP_TITLES:
            skipped.append("%s (непозната група %s)" % (a["id"], a["group"]))
            continue
        articles.append(a)

    articles.sort(key=lambda a: (a["group"], a["order"]))
    used_groups = sorted({a["group"] for a in articles})

    out = os.path.abspath(args.out)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    if os.path.exists(out):
        os.remove(out)

    db = sqlite3.connect(out)
    db.executescript(SCHEMA)

    for pos, gid in enumerate(used_groups, start=1):
        db.execute("INSERT INTO ref_groups (id, title, position) VALUES (?,?,?)",
                   (gid, GROUP_TITLES[gid], pos))

    counts = {}
    for i, a in enumerate(articles, start=1):
        gid = a["group"]
        counts[gid] = counts.get(gid, 0) + 1
        db.execute(
            "INSERT INTO ref_articles"
            " (id, group_id, title, title_ru, body, body_ru, position)"
            " VALUES (?,?,?,?,?,?,?)",
            (i, gid, a["title_bg"], a["title_ru"],
             to_html(a["units_bg"]), to_html(a["units"]), counts[gid]))

    db.commit()
    print("=" * 64)
    for gid in used_groups:
        print("  %d. %-52s %2d статии" % (gid, GROUP_TITLES[gid], counts[gid]))
    print("общо: %d статии в %d групи" % (len(articles), len(used_groups)))
    if skipped:
        print("прескочени: %s" % ", ".join(skipped))
    missing = [g for g in GROUP_TITLES if g not in used_groups]
    if missing:
        print("групи без нито една преведена статия (няма ги в базата): %s"
              % ", ".join("%d %s" % (g, GROUP_TITLES[g]) for g in missing))
    db.close()
    print("→ %s" % out)


if __name__ == "__main__":
    main()
