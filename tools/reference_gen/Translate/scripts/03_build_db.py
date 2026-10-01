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

# ⚠ Статии, написани НА РЪКА, а не преведени (27.09.2026): „Дни, в които се
# разрешава тайнството брак" и „Символ на вярата". Носят готов HTML
# (`body_html`), защото Символът иска класовете на песнопенията (.csl /
# .trans), а не голи абзаци. Всяка става САМОСТОЯТЕЛНА група с едно четиво
# и еднакво име — екранът (reference_book_screen.dart) я рисува като карта,
# която се отваря с едно докосване, и я слага НАЙ-ОТГОРЕ, по `position`.
# Идентификаторите им започват от 100, за да не се бъркат с номерата на
# групите от превода.
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                 '..', '..', '..', 'bible_refs'))
import linkify  # noqa: E402

_BIBLE = linkify.abbreviations()

MANUAL_DIR = os.path.join(REFGEN_DIR, "manual")
MANUAL_ID0 = 100

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


# ⚠ Главите-СПИСЪЦИ в „Редът за четене на Евангелието през Великите пости"
# (указание на потребителя): седмиците — група (получер, синьо, главни),
# дните — подзаглавие, редовете с четива — системен шрифт и ДЕЙСТВАЩА
# връзка към целия откъс (и през няколко глави). Обяснителните изречения
# вътре остават в шрифта за четене. Главите с описания (4-01, 4-05) — не.
LIST_ARTICLES = {'4-02', '4-03', '4-04', '4-06'}
_GOSPEL = {'мт': 'Mt', 'мат': 'Mt', 'мф': 'Mt', 'мк': 'Mk', 'марк': 'Mk', 'лк': 'Lk',
           'лук': 'Lk', 'ин': 'Jn', 'йн': 'Jn', 'йоан': 'Jn'}
RE_WEEK = re.compile(r'^\d+-\w+ седмица:?$')
RE_DAY = re.compile(r'^(Пн|Вт|Ср|Чт|Пт|Пет|Сб)\.$|^(Понеделник|Вторник|Сряда|Четвъртък|Петък)$'
                    r'|^\d+-\w+ ден:?$')
RE_LINE = re.compile(r'^(.*?–\s*)((\w+)\.,\s*зач\.\s*[\d–-]+\s*\((\d+)\s*[:,]\s*(\d+)\s*[–-]\s*'
                     r'(?:(\d+)\s*[:,]\s*)?(\d+)\))(\.?)$')


def list_html(units):
    out = []
    for u in units:
        t = u.strip()
        if RE_WEEK.match(t):
            out.append(f'<p class="refgroup">{html.escape(t.rstrip(":"))}</p>')
        elif RE_DAY.match(t):
            out.append(f'<p class="refday">{html.escape(t.rstrip(":"))}</p>')
        else:
            # „Мф." — руската форма, останала от превода; съседните редове
            # казват „Мт.".
            t = re.sub(r'(–\s*)Мф\.', r'\1Мт.', t)
            m = RE_LINE.match(t)
            code = _GOSPEL.get(m.group(3).lower()) if m else None
            if not code:
                out.append(f'<p>{html.escape(t)}</p>')   # обяснително изречение
                continue
            c1, v1, c2, v2 = m.group(4), m.group(5), m.group(6), m.group(7)
            rng = f'{c1}:{v1}-{v2}' if not c2 or c2 == c1 else f'{c1}:{v1}-{c2}:{v2}'
            href = f'https://azbyka.ru/biblia/?{code}.{rng}&amp;bg~utfcs'
            out.append(f'<p class="refline">{html.escape(m.group(1))}'
                       f'<a href="{href}">{html.escape(m.group(2))}</a>{m.group(8)}</p>')
    return ''.join(out)


def bg_html(units):
    """Българският текст: като to_html, плюс ДЕЙСТВАЩИ библейски връзки.

    ⚠ До 27.09.2026 препратките в справочника („(Мат. 9:15)") стояха като
    обикновен текст. Свързва ги общият модул tools/bible_refs/linkify.py —
    същият вид адрес като в томовете, тъй че се отварят вътре в приложението.
    Руската колона (`body_ru`) е само за сверка и не се пипа."""
    return linkify.link(to_html(units), _BIBLE)


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

    manual = sorted((json.load(open(f, encoding="utf-8"))
                     for f in glob.glob(os.path.join(MANUAL_DIR, "*.json"))),
                    key=lambda m: m["position"])

    out = os.path.abspath(args.out)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    if os.path.exists(out):
        os.remove(out)

    db = sqlite3.connect(out)
    db.executescript(SCHEMA)

    # Ръчните — най-отгоре, после групите от превода. С `"at_end": true`
    # ръчната отива НАЙ-ОТДОЛУ, след превода („Съкращения" — потребителят).
    top = [m for m in manual if not m.get("at_end")]
    end = [m for m in manual if m.get("at_end")]
    gpos = {}
    for m in top:
        gpos[m["id"]] = len(gpos) + 1
    for gid in used_groups:
        gpos[gid] = len(gpos) + 1
    for m in end:
        gpos[m["id"]] = len(gpos) + 1
    for k, m in enumerate(manual, start=1):
        db.execute("INSERT INTO ref_groups (id, title, position) VALUES (?,?,?)",
                   (MANUAL_ID0 + k, m["title"], gpos[m["id"]]))
    for gid in used_groups:
        db.execute("INSERT INTO ref_groups (id, title, position) VALUES (?,?,?)",
                   (gid, GROUP_TITLES[gid], gpos[gid]))

    counts = {}
    for i, a in enumerate(articles, start=1):
        gid = a["group"]
        counts[gid] = counts.get(gid, 0) + 1
        db.execute(
            "INSERT INTO ref_articles"
            " (id, group_id, title, title_ru, body, body_ru, position)"
            " VALUES (?,?,?,?,?,?,?)",
            (i, gid, a["title_bg"], a["title_ru"],
             list_html(a["units_bg"]) if a["id"] in LIST_ARTICLES else bg_html(a["units_bg"]),
             to_html(a["units"]), counts[gid]))

    # ⚠ Id-то на статията е и слъгът ѝ (`ref-<id>`) — в отметките и в
    # споделените линкове. Затова ръчните имат ПОСТОЯНЕН номер — изричното
    # поле `ref_id`, — който не зависи нито от броя преведени, нито от РЕДА:
    # `position` решава само кое стои по-горе. Дотук номерът беше
    # 1000 + `position` и размяната на реда разменяше и слъговете —
    # отметка към брака щеше да отваря Символа (27.09.2026).
    for k, m in enumerate(manual, start=1):
        db.execute(
            "INSERT INTO ref_articles"
            " (id, group_id, title, title_ru, body, body_ru, position)"
            " VALUES (?,?,?,?,?,?,?)",
            (m["ref_id"], MANUAL_ID0 + k, m["title"], None,
             m["body_html"], None, 1))

    db.commit()
    print("=" * 64)
    for m in manual:
        print("  ръчна: %s" % m["title"])
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
