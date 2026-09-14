#!/usr/bin/env python3
"""Сваля българския текст на Библията от pravoslavieto.com в `cache/`.

Пуска се от корена на проекта:

    python3 tools/bible_bg/scripts/01_fetch.py
    python3 tools/bible_bg/scripts/01_fetch.py --only Mk Ps
    python3 tools/bible_bg/scripts/01_fetch.py --retry     # само провалените

⚠ КЕШЪТ Е ДОСЛОВНО КОПИЕ на свалената страница и НЕ СЕ ПИПА. Разчитането е
работа на `02_parse.py`. Смесят ли се двете, всяка поправка в разчитането иска
ново теглене на 228 страници — а източникът е чужд сървър, не наш.

⚠ Вече свалена страница се ПРОПУСКА. Прекъснато пускане се продължава, вместо
да започва отначало.
"""

import argparse
import csv
import re
import os
import sys
import time
import urllib.error
import urllib.request

BASE = "https://www.pravoslavieto.com/bible"
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CACHE = os.path.join(ROOT, "cache")
BOOKS = os.path.join(ROOT, "input", "books.csv")

# ⚠ Пауза между заявките. Сървърът е чужд и малък; 228 заявки без пауза са
# грубост, а и azbyka.ru ни отряза точно за това (виж 403-те в bible_gen).
DELAY = 0.7

# ⚠ Псалтирът е с ФАЙЛ НА ПСАЛОМ (`sz/ps/1.htm`…), а не един файл с глави.
# 151, не 150: синодалното издание носи и „допълнителния" псалом.
PSALMS = 151


def read_books():
    with open(BOOKS, encoding="utf-8") as fh:
        return list(csv.DictReader(fh))


def targets(rows, only):
    """Двойки (име на файла в кеша, адрес) за всичко, което трябва да се свали."""
    out = []
    for r in rows:
        if only and r["code"] not in only:
            continue
        if r["kind"] == "psalter":
            for n in range(1, PSALMS + 1):
                out.append(("Ps_%03d.htm" % n, "%s/%s/%d.htm" % (BASE, r["path"], n)))
        else:
            out.append(("%s.htm" % r["code"], "%s/%s.htm" % (BASE, r["path"])))
    return out


# ⚠ САЙТЪТ Е В ДВЕ РАЗЛИЧНИ КОДИРОВКИ и това не личи отникъде отвън.
# По-новите страници са UTF-8, а по-старите — windows-1251. Открито на
# 28.08.2026: `2Sam` (2 Царства) излизаше със счупени знаци още в заглавието
# на главата („????? 1."), докато Марк и Иуда бяха наред.
#
# Затова кодировката се чете от САМАТА страница, а не се приема наготово.
RE_CHARSET = re.compile(rb'charset=["\']?([\w-]+)', re.I)


def decode(raw):
    """Разчита байтовете по кодировката, която страницата сама обявява."""
    m = RE_CHARSET.search(raw[:4000])
    enc = (m.group(1).decode("ascii", "ignore").lower() if m else "utf-8")
    # Нормализация на псевдонимите, с които стари страници се назовават.
    enc = {"windows-1251": "cp1251", "win-1251": "cp1251",
           "utf8": "utf-8"}.get(enc, enc)
    try:
        return raw.decode(enc), enc
    except (LookupError, UnicodeDecodeError):
        # ⚠ Пада се към cp1251, а НЕ към utf-8: тук грешната кодировка е
        # почти винаги кирилска осмобитова, а utf-8 върху нея дава ред
        # въпросителни вместо четим текст.
        try:
            return raw.decode("cp1251"), "cp1251(падане)"
        except UnicodeDecodeError:
            return raw.decode("utf-8", "replace"), "utf-8(със загуби)"


def fetch(url):
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    with urllib.request.urlopen(req, timeout=30) as resp:
        raw = resp.read()
    html, enc = decode(raw)
    # Кешът е ЕДНОРОДЕН — всичко се пази в UTF-8, независимо как е дошло.
    # Така `02_parse.py` не знае нищо за кодировки.
    if "charset=" in html[:4000].lower():
        html = re.sub(r'charset=["\']?[\w-]+', "charset=utf-8", html[:4000],
                      count=1, flags=re.I) + html[4000:]
    return html, enc


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", nargs="*", default=None, help="само тези кодове")
    ap.add_argument("--retry", action="store_true", help="само провалените")
    args = ap.parse_args()

    os.makedirs(CACHE, exist_ok=True)
    rows = read_books()
    jobs = targets(rows, set(args.only) if args.only else None)

    failures_path = os.path.join(CACHE, "_failures.txt")
    if args.retry:
        if not os.path.exists(failures_path):
            print("няма провалени")
            return
        want = {l.split("\t")[0] for l in open(failures_path, encoding="utf-8")
                if l.strip() and not l.startswith("#")}
        jobs = [j for j in jobs if j[0] in want]

    todo = [(n, u) for n, u in jobs
            if args.retry or not os.path.exists(os.path.join(CACHE, n))]

    print("страници общо : %d" % len(jobs))
    print("в кеша        : %d" % (len(jobs) - len(todo)))
    print("остават       : %d" % len(todo))
    if not todo:
        print("\nнищо за сваляне")
        return
    print("време         : около %d мин.\n" % max(1, round(len(todo) * (DELAY + 0.5) / 60)))

    failed = []
    encodings = {}
    for i, (name, url) in enumerate(todo, 1):
        try:
            html, enc = fetch(url)
            if not enc.startswith("utf-8"):
                encodings[enc] = encodings.get(enc, 0) + 1
            with open(os.path.join(CACHE, name), "w", encoding="utf-8") as fh:
                fh.write(html)
        except (urllib.error.URLError, urllib.error.HTTPError, OSError) as e:
            reason = getattr(e, "code", None) or str(e)[:60]
            failed.append((name, reason))
            print("  ✗ %s — %s" % (name, reason))
        if i % 25 == 0 or i == len(todo):
            print("  %d/%d%s" % (i, len(todo),
                                 "   провалени: %d" % len(failed) if failed else ""))
        time.sleep(DELAY)

    with open(failures_path, "w", encoding="utf-8") as fh:
        fh.write("# страница\tпричина — пусни наново с --retry\n")
        for n, r in failed:
            fh.write("%s\t%s\n" % (n, r))

    if encodings:
        print("\n⚠ страници НЕ в utf-8 (прекодирани): %s" % encodings)
    print("\nготово. провалени: %d" % len(failed))
    if failed:
        print("виж cache/_failures.txt, после: 01_fetch.py --retry")
        sys.exit(1)


if __name__ == "__main__":
    main()
