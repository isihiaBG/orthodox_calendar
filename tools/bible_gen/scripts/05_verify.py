#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
05_verify.py — Проверява готовата bible.db. Без мрежа.

Три вида проверки, по нарастваща коварност:

  ПЪЛНОТА    липсва ли книга или глава, която каноничният брой обещава.
             Тук липсите често са ЗАКОННИ (Септуагинтата няма Нов завет),
             затова се сверява срещу `languages.scope`, а останалото се
             изброява, за да се погледне с очи.

  ПОДРЕДБА   съвпадат ли ключовете на стиховете между преводите. Разминаване
             не значи непременно грешка — номерацията наистина се различава
             между Масоретския текст и Септуагинтата — но трябва да се ЗНАЕ
             колко е, за да не изненада паралелния изглед в четеца.

  ЗАМЪРСЯВАНЕ  ⚠ най-важното. В стиховете на сайта има съдържание, което НЕ Е
             Писание: подсказки за екрана, зачала, сноски, подзаглавия.
             Всяко от тях се залепва насред стиха при небрежно махане на
             таговете и после НИКОЙ не го забелязва — текстът изглежда
             правдоподобно. Тези проверки са нарочно писани като капани за
             самите себе си: пуснат ли се след промяна в 03_parse.py, ще
             гръмнат, ако някой ги е върнал обратно в текста.

Употреба:
    python3 05_verify.py
    python3 05_verify.py --db ../output/bible_pilot.db
"""

import argparse
import os
import re
import sqlite3
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.dirname(SCRIPT_DIR)
REPO_DIR = os.path.dirname(os.path.dirname(PROJECT_DIR))
DEFAULT_DB = os.path.join(REPO_DIR, "assets", "db", "bible.db")

# Следи от съдържание, което е трябвало да излезе от текста на стиха. Всяка
# двойка е (име, израз) и всяко съвпадение е ГРЕШКА, не предупреждение.
CONTAMINATION = [
    ("подсказка за скобите (span.info)",
     re.compile(r"В тексте Ветхого Завета в квадратные скобки")),
    ("подсказка за добавените думи (title на cyn)",
     re.compile(r"Слова, добавленные переводчиками")),
    ("зачало, останало в текста",
     re.compile(r"\[?\s*Зач\.\s*\d")),
    ("недоизчистен таг",
     re.compile(r"</?(?:span|div|abbr|a)\b", re.I)),
    ("празни квадратни скоби от извадено зачало",
     re.compile(r"\[\s*\]")),
    ("двойни интервали",
     re.compile(r"  ")),
]


def rule(title):
    print()
    print(title)
    print("─" * len(title))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--db", default=DEFAULT_DB)
    args = ap.parse_args()

    if not os.path.exists(args.db):
        sys.exit(f"Няма {args.db}. Пусни първо 04_build_db.py.")

    con = sqlite3.connect(args.db)
    con.row_factory = sqlite3.Row
    problems = 0

    langs = con.execute(
        "SELECT code, bg_short, scope FROM languages ORDER BY ord").fetchall()
    books = con.execute(
        "SELECT code, bg_abbr, testament, chapters FROM books ORDER BY ord"
    ).fetchall()

    # ── ПЪЛНОТА ────────────────────────────────────────────────────────────
    rule("ПЪЛНОТА")
    print(f"{'превод':<12} {'книги':>6} {'глави':>7} {'стихове':>9}  липсващи глави")
    for lang in langs:
        code, scope = lang["code"], lang["scope"]
        rows = con.execute(
            "SELECT book, chapter FROM verses WHERE lang=? GROUP BY book, chapter",
            (code,)).fetchall()
        have = {(r["book"], r["chapter"]) for r in rows}
        nverses = con.execute(
            "SELECT COUNT(*) FROM verses WHERE lang=?", (code,)).fetchone()[0]

        expected = set()
        for b in books:
            if scope == "ot" and b["testament"] == "NT":
                continue
            if scope == "nt" and b["testament"] == "OT":
                continue
            for ch in range(1, b["chapters"] + 1):
                expected.add((b["code"], ch))

        missing = expected - have
        by_book = {}
        for bk, ch in missing:
            by_book.setdefault(bk, []).append(ch)
        summary = ", ".join(
            f"{bk}({len(chs)})" for bk, chs in sorted(
                by_book.items(), key=lambda kv: -len(kv[1]))[:5])
        if len(by_book) > 5:
            summary += f" … още {len(by_book) - 5} книги"

        nbooks = len({b for b, _ in have})
        print(f"{code:<12} {nbooks:>6} {len(have):>7} {nverses:>9}  "
              f"{len(missing) or '—'}{'  ' + summary if missing else ''}")

    # ── ПОДРЕДБА ───────────────────────────────────────────────────────────
    rule("ПОДРЕДБА НА СТИХОВЕТЕ (спрямо българския)")
    ref = "bg"
    ref_keys = {
        (r["book"], r["chapter"], r["verse"])
        for r in con.execute(
            "SELECT book, chapter, verse FROM verses WHERE lang=?", (ref,))
    }
    if not ref_keys:
        print("  българският е празен — проверката се пропуска")
    else:
        for lang in langs:
            code = lang["code"]
            if code == ref:
                continue
            keys = {
                (r["book"], r["chapter"], r["verse"])
                for r in con.execute(
                    "SELECT book, chapter, verse FROM verses WHERE lang=?", (code,))
            }
            if not keys:
                continue
            # Сравняват се само книгите, които и двата превода изобщо имат —
            # иначе цял липсващ завет се брои за „разминаване".
            shared = {k[0] for k in keys} & {k[0] for k in ref_keys}
            a = {k for k in keys if k[0] in shared}
            b = {k for k in ref_keys if k[0] in shared}
            common = len(a & b)
            pct = 100.0 * common / len(b) if b else 0.0
            print(f"  {code:<10} общи книги {len(shared):>2}   "
                  f"съвпадащи ключове {common:>6} / {len(b):<6} ({pct:5.1f}%)"
                  f"   само в него: {len(a - b)}")

    # ── ЗАМЪРСЯВАНЕ ────────────────────────────────────────────────────────
    rule("ЗАМЪРСЯВАНЕ НА ТЕКСТА")
    for name, pattern in CONTAMINATION:
        hits = []
        for r in con.execute("SELECT book, chapter, verse, lang, text FROM verses"):
            if pattern.search(r["text"]):
                hits.append(f"{r['lang']} {r['book']}.{r['chapter']}:{r['verse']}")
                if len(hits) >= 4:
                    break
        if hits:
            problems += 1
            print(f"  ✗ {name}: намерено — {', '.join(hits)}")
        else:
            print(f"  ✓ {name}: чисто")

    empty = con.execute(
        "SELECT COUNT(*) FROM verses WHERE TRIM(text)=''").fetchone()[0]
    if empty:
        problems += 1
        print(f"  ✗ празни стихове: {empty}")
    else:
        print("  ✓ празни стихове: няма")

    # ── ИЗВАДЕНОТО ОТДЕЛНО ─────────────────────────────────────────────────
    rule("ИЗВАДЕНО В СВОИ ТАБЛИЦИ")
    for table, label in [("zachala", "зачала"), ("notes", "сноски"),
                         ("titles", "подзаглавия"), ("annotations", "пояснения"),
                         ("links", "връзки")]:
        rows = con.execute(
            f"SELECT lang, COUNT(*) n FROM {table} GROUP BY lang ORDER BY n DESC"
        ).fetchall()
        total = sum(r["n"] for r in rows)
        detail = ", ".join(f"{r['lang']} {r['n']}" for r in rows)
        print(f"  {label:<12} {total:>6}   {detail or '—'}")

    print()
    if problems:
        print(f"⚠ ПРОБЛЕМИ: {problems}")
        sys.exit(1)
    print("Проверката мина чисто.")


if __name__ == "__main__":
    main()
