#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
01_fetch_map.py — картата на Писанието: кои книги, по колко глави, кои езици.

Тегли ДВЕ страници от azbyka.ru и от тях изважда всичко, което следващите
скриптове ще обхождат. Пуска се веднъж; после конвейерът работи по CSV-тата.

    /biblia/instruction.html  → книгите и броят глави във всяка
    /biblia/                  → списъкът с преводи (код → име)

⚠ Защо „instruction.html", а не самата /biblia/: страницата за уебмастери
носи ПЪЛНАТА карта книга→глави в един-единствен документ (всяка глава е
отделна връзка `/biblia/?Gen.1`). Иначе броят глави се вади с 77 отделни
заявки към книгите. Едната страница спестява цялото това обикаляне.

Изход (и двата се пазят в git — леки са и от тях всичко се възпроизвежда):
    input/books.csv      order, code, testament, chapters, ru_title
    input/languages.csv  code, title, scope, note

Употреба:
    python3 01_fetch_map.py
    python3 01_fetch_map.py --offline    # разглобява вече свалените в cache/
"""

import argparse
import csv
import html
import os
import re
import sys

import requests

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.dirname(SCRIPT_DIR)
INPUT_DIR = os.path.join(PROJECT_DIR, "input")
CACHE_DIR = os.path.join(PROJECT_DIR, "cache", "_map")

MAP_URL = "https://azbyka.ru/biblia/instruction.html"
INDEX_URL = "https://azbyka.ru/biblia/"

USER_AGENT = (
    "orthodox_calendar-fetcher/1.0 "
    "(non-commercial Orthodox calendar app; contact: isihiabg [at] gmail [dot] com)"
)
TIMEOUT = 30

# Колко книги очакваме. Ако сайтът някой ден се промени, по-добре скриптът да
# гръмне тук, отколкото да произведе половин карта, която мълчаливо отрязва
# книги чак в готовата база.
EXPECT_BOOKS = 77
EXPECT_NT = 27
EXPECT_CHAPTERS = 1361

# Преводите, които НЕ покриват цялата Библия. Сайтът просто връща страница без
# нито един стих за липсващата част — за да не се броят тези хиляди празни
# заявки за грешка, обхватът се знае предварително.
#
# ⚠ „ot" тук значи „каквото този превод има от Стария завет", а не целия
# православен канон: еврейската Библия няма второканоничните книги, а LXX ги
# има. Точното покритие излиза при самото теглене (скрипт 02) и се записва в
# отчета — тази колона е само за да не се хабят заявки за очевидното.
LANG_SCOPE = {
    "el-r": "ot",   # Septuaginta (Rahlfs) — само Стар завет
    "i": "ot",      # Hebrew — само Стар завет, и то по еврейския канон
    "g": "nt",      # Greek NT Byz — само Нов завет
    "he": "nt",     # Hebrew NT by Delitzsch — само Нов завет
}


def fetch(url: str, cache_name: str, offline: bool) -> str:
    """Тегли страница веднъж и я пази в cache/_map/. Второ пускане чете кеша."""
    os.makedirs(CACHE_DIR, exist_ok=True)
    path = os.path.join(CACHE_DIR, cache_name)

    if os.path.exists(path) and os.path.getsize(path) > 0:
        with open(path, encoding="utf-8") as fh:
            return fh.read()

    if offline:
        sys.exit(f"НЯМА кеш за {cache_name}, а е поискано --offline. Пусни без него.")

    print(f"тегля {url} …")
    resp = requests.get(url, headers={"User-Agent": USER_AGENT}, timeout=TIMEOUT)
    resp.raise_for_status()
    resp.encoding = "utf-8"
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(resp.text)
    return resp.text


def strip_scripts(s: str) -> str:
    """Маха <script>/<style> — иначе JS-ът вътре бълва фалшиви съвпадения."""
    return re.sub(r"(?is)<(script|style).*?</\1>", "", s)


def parse_books(map_html: str, index_html: str):
    """Книгите с броя глави и завета, по реда на самия сайт (първо НЗ, после СЗ).

    Броят глави идва от instruction.html (всяка глава е отделна връзка), а
    имената и РЕДЪТ — от началната страница, където книгите стоят в
    богослужебния си ред с пълните си заглавия.
    """
    map_body = strip_scripts(map_html)

    # Заветите се различават по мястото в документа: всичко преди надписа
    # „Новый Завет" е Стар завет. Търси се ПОСЛЕДНОТО срещане на „Ветхий
    # Завет" преди него — първите две са в горното меню на портала, не в
    # самата карта.
    nt_marker = None
    for m in re.finditer(r"Новый\s+Завет", map_body):
        # Картата е най-дългата част от страницата; истинският надпис стои
        # след стотици връзки към глави, не в менюто.
        if map_body.count("/biblia/?", 0, m.start()) > 100:
            nt_marker = m.start()
            break
    if nt_marker is None:
        sys.exit("Не намирам границата между заветите в instruction.html.")

    chapters = {}
    testament = {}
    for m in re.finditer(r"/biblia/\?([A-Za-z0-9]+)\.(\d+)\b", map_body):
        code, num = m.group(1), int(m.group(2))
        chapters[code] = max(chapters.get(code, 0), num)
        # Заветът се решава по ПЪРВОТО срещане на книгата — нататък по
        # страницата има и препратки в друг контекст.
        if code not in testament:
            testament[code] = "NT" if m.start() > nt_marker else "OT"

    # Имената и редът — от началната страница.
    index_body = strip_scripts(index_html)
    titles = []
    seen = set()
    pattern = r'href="/biblia/\?([A-Za-z0-9]+)\.1&amp;r"[^>]*>(.*?)</a>'
    for m in re.finditer(pattern, index_body, re.S):
        code = m.group(1)
        if code in seen:
            continue
        seen.add(code)
        title = html.unescape(re.sub(r"<[^>]+>", "", m.group(2))).strip()
        titles.append((code, title))

    rows = []
    for order, (code, ru_title) in enumerate(titles, start=1):
        if code not in chapters:
            sys.exit(f"Книга {code} я има в списъка, но не и в картата с главите.")
        rows.append({
            "order": order,
            "code": code,
            "testament": testament.get(code, "OT"),
            "chapters": chapters[code],
            "ru_title": ru_title,
        })
    return rows


def parse_languages(index_html: str):
    """Преводите: код → име, както ги обявява самият сайт."""
    body = strip_scripts(index_html)
    rows = []
    seen = set()
    pattern = r'href="/biblia/\?([A-Za-z0-9_\-]+)"[^>]*>(.*?)</a>'
    for m in re.finditer(pattern, body, re.S):
        code = m.group(1)
        title = html.unescape(re.sub(r"<[^>]+>", "", m.group(2))).strip()
        # Пропускат се кратките надписи от горния ред („русском", „греческом") —
        # те сочат същите преводи, но с име в падеж вместо заглавие.
        if not title or code in seen or title[0].islower():
            continue
        seen.add(code)
        rows.append({
            "code": code,
            "title": title,
            "scope": LANG_SCOPE.get(code, "all"),
            "note": "",
        })
    return rows


def write_csv(path: str, rows, fields):
    with open(path, "w", encoding="utf-8", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=fields)
        w.writeheader()
        w.writerows(rows)
    print(f"  → {os.path.relpath(path, PROJECT_DIR)}  ({len(rows)} реда)")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--offline", action="store_true",
                    help="само разглобяване на вече свалените страници")
    args = ap.parse_args()

    os.makedirs(INPUT_DIR, exist_ok=True)

    map_html = fetch(MAP_URL, "instruction.html", args.offline)
    index_html = fetch(INDEX_URL, "index.html", args.offline)

    books = parse_books(map_html, index_html)
    langs = parse_languages(index_html)

    total_chapters = sum(b["chapters"] for b in books)
    nt = sum(1 for b in books if b["testament"] == "NT")

    print()
    print(f"книги: {len(books)}  (Нов завет {nt}, Стар завет {len(books) - nt})")
    print(f"глави: {total_chapters}")
    print(f"преводи: {len(langs)}")
    print()

    problems = []
    if len(books) != EXPECT_BOOKS:
        problems.append(f"книгите са {len(books)}, а очакваме {EXPECT_BOOKS}")
    if nt != EXPECT_NT:
        problems.append(f"новозаветните са {nt}, а очакваме {EXPECT_NT}")
    if total_chapters != EXPECT_CHAPTERS:
        problems.append(f"главите са {total_chapters}, а очакваме {EXPECT_CHAPTERS}")
    if problems:
        print("⚠ РАЗМИНАВАНЕ С ОЧАКВАНОТО:")
        for p in problems:
            print("   -", p)
        print("   Сайтът се е променил. Провери, преди да пишеш CSV-тата.")
        sys.exit(1)

    write_csv(os.path.join(INPUT_DIR, "books.csv"), books,
              ["order", "code", "testament", "chapters", "ru_title"])
    write_csv(os.path.join(INPUT_DIR, "languages.csv"), langs,
              ["code", "title", "scope", "note"])


if __name__ == "__main__":
    main()
