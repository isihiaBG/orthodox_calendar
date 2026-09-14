#!/usr/bin/env python3
"""Сверява разчетеното срещу текущия български текст. НЕ ПИШЕ НИЩО.

    python3 tools/bible_bg/scripts/03_verify.py
    python3 tools/bible_bg/scripts/03_verify.py --sample 20   # примери за разлики
    python3 tools/bible_bg/scripts/03_verify.py --book Mk

⚠ ПУСКА СЕ ВИНАГИ ПРЕДИ `04_apply.py`. Смисълът не е „гърми ли" — а да се
види ЧЕ новият източник наистина поправя, вместо да внася свои грешки.

Три въпроса, на които отговаря:

  1. ЗАГУБА ли има — стихове, които сегашната база има, а новият текст няма.
     Това е единственото, което може да влоши приложението, тъй че се брои
     отделно и се изписва първо.
  2. ПОПРАВЕНИ ли са известните грешки („Накова", „изкушавай").
  3. КОЛКО се различава изобщо — ако разликите са подозрително много или
     подозрително малко, нещо в разчитането не е наред.
"""

import argparse
import json
import os
import re
import sqlite3
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
JSON = os.path.join(ROOT, "output", "json")
DB = os.path.join(os.path.dirname(os.path.dirname(ROOT)), "assets", "db", "bible.db")


def norm(s):
    """За сравнение по СМИСЪЛ, не по форматиране.

    ⚠ Пунктуацията и кавичките се пазят — тъкмо в тях личат разликите между
    двата източника. Свива се само празното място, което е шум.
    """
    return re.sub(r"\s+", " ", s or "").strip()


def load_new(only=None):
    out = {}
    for f in sorted(os.listdir(JSON)):
        if not f.endswith(".json"):
            continue
        code = f[:-5]
        if only and code != only:
            continue
        with open(os.path.join(JSON, f), encoding="utf-8") as fh:
            d = json.load(fh)
        for ch, verses in d["chapters"].items():
            for v in verses:
                out[(code, int(ch), v["verse"])] = norm(v["text"])
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--sample", type=int, default=0, help="покажи N примера")
    ap.add_argument("--book", default=None)
    args = ap.parse_args()

    new = load_new(args.book)
    con = sqlite3.connect(DB)
    q = "SELECT book, chapter, verse, text FROM verses WHERE lang='bg'"
    if args.book:
        q += " AND book='%s'" % args.book
    old = {(b, c, v): norm(t) for b, c, v, t in con.execute(q)}

    same = diff = 0
    lost = []
    added = 0
    examples = []
    for key, o in old.items():
        n = new.get(key)
        if n is None:
            lost.append(key)
        elif n == o:
            same += 1
        else:
            diff += 1
            if len(examples) < args.sample:
                examples.append((key, o, n))
    added = len(set(new) - set(old))

    print("стихове в сегашната база : %d" % len(old))
    print("стихове в новия текст    : %d" % len(new))
    print()
    print("  еднакви      : %d" % same)
    print("  различни     : %d" % diff)
    print("  ⚠ ЗАГУБЕНИ   : %d" % len(lost))
    print("  нови (в повече): %d" % added)

    if lost:
        # Кои книги/глави губим — обобщено, не стих по стих.
        books = {}
        for b, c, v in lost:
            books.setdefault(b, set()).add(c)
        print("\n⚠ ЗАГУБА по книги (книга: глави):")
        for b in sorted(books):
            ch = sorted(books[b])
            short = ", ".join(str(x) for x in ch[:8]) + ("…" if len(ch) > 8 else "")
            print("   %-8s %d гл. (%s)" % (b, len(ch), short))

    # ── Известните грешки ──────────────────────────────────────────────────
    print("\nизвестните грешки в НОВИЯ текст:")
    checks = [
        ("Накова", "Накова (вместо Иакова)"),
        ("възлизаме.", "Песен на възлизаме"),
    ]
    for needle, label in checks:
        hits = sum(1 for t in new.values() if needle in t)
        was = sum(1 for t in old.values() if needle in t)
        mark = "OK" if hits < was else ("=" if hits == was else "ПОВЕЧЕ!")
        print("   %s %-34s сега %d, беше %d" % (mark, label, hits, was))

    mk113 = new.get(("Mk", 1, "13"), "")
    if mk113:
        ok = "изкушаван" in mk113
        print("   %s Мк. 1:13 -> изкушаван" % ("OK" if ok else "НЕ"))

    if examples:
        print("\nпримери за разлики (стар → нов):")
        for (b, c, v), o, n in examples:
            print("\n  %s %d:%s" % (b, c, v))
            print("    стар: %s" % o[:110])
            print("    нов : %s" % n[:110])

    if lost:
        print("\n⚠ ИМА ЗАГУБА — не прилагай, докато не се изясни.")
        sys.exit(1)


if __name__ == "__main__":
    main()
