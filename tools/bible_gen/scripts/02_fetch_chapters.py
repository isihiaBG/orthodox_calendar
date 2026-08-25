#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
02_fetch_chapters.py — Кеширащ сваляч на главите. ЕДИНСТВЕНАТА стъпка с мрежа.

Тегли по една глава на заявка, в по един превод наведнъж, и я записва като
HTML файл. Рестартируем: вече свалено се прескача, тъй че прекъснато пускане
се продължава просто с повторно пускане.

⚠ ЕДИН ЕЗИК НА ЗАЯВКА, а не няколко наведнъж. Сайтът приема до ДВА превода
в адреса (`?Gen.1&r~utfcs`), но при трети мълчаливо пренасочва (302) към
първите два — `?Gen.1&r~utfcs~bg` връща страница БЕЗ българския, без никакво
съобщение за това. Един превод на заявка е и по-лесен за разглобяване, и
единственият начин да не се окаже накрая, че цял език липсва.

⚠ Пред сайта стои ddos-guard, тъй че cookie-тата се пазят в обща сесия. Без
тях всяка заявка тръгва от нулата и рискува да бъде спряна.

Обхватът на всеки превод се чете от input/languages.csv (`scope`): LXX и
еврейската Библия нямат Нов завет, гръцкият НЗ няма Стар. За тях главите
извън обхвата дори не се искат.

Употреба:
    python3 02_fetch_chapters.py --langs bg,utfcs,cs,r
    python3 02_fetch_chapters.py --langs bg --books Gen,Mt      # проба
    python3 02_fetch_chapters.py --langs bg --limit 20          # проба
    python3 02_fetch_chapters.py --langs bg --retry             # само провалените
    python3 02_fetch_chapters.py --langs bg --plan              # само сметка, без мрежа
"""

import argparse
import csv
import os
import random
import sys
import time

import requests

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.dirname(SCRIPT_DIR)
INPUT_DIR = os.path.join(PROJECT_DIR, "input")
CACHE_DIR = os.path.join(PROJECT_DIR, "cache")

BASE_URL = "https://azbyka.ru/biblia/?{book}.{chapter}&{lang}"

# Учтивост към сайта. Не сваляй под ~1.5 сек. — конвейерът и без това е
# нощна работа, а спирането по вина на нетърпелив скрипт струва много повече
# от няколкото спестени часа.
#
# ⚠ ИЗПИТАНО НА ПРАКТИКА (25.08.2026): при 1.5–3 сек. сайтът издържа около
# 5800 страници, после започна да връща HTTP 403 на поток. Блокирането се
# оказа ВРЕМЕННО — след спиране единична заявка веднага мина — тоест е
# ограничение по скорост, а не забрана. При подновяване вдигай паузата с
# --delay; спирането по средата струва много повече от изчакването.
DELAY_MIN = 1.5
DELAY_MAX = 3.0

TIMEOUT = 30
MAX_RETRIES = 3
RETRY_BACKOFF = 5      # секунди × номера на опита

# Дълга пауза на всеки N заявки — дава на сайта да си отдъхне и намалява
# шанса да ни сметне за поток.
LONG_PAUSE_EVERY = 200
LONG_PAUSE = 30

USER_AGENT = (
    "orthodox_calendar-fetcher/1.0 "
    "(non-commercial Orthodox calendar app; contact: isihiabg [at] gmail [dot] com)"
)

# Под този размер страницата почти сигурно е грешка или пренасочване, а не
# глава. Най-малката истинска глава (един стих) излиза около 25 KB заради
# общата обвивка на сайта.
MIN_SANE_SIZE = 8000


def load_csv(name):
    path = os.path.join(INPUT_DIR, name)
    if not os.path.exists(path):
        sys.exit(f"Липсва {path}. Пусни първо 01_fetch_map.py.")
    with open(path, encoding="utf-8") as fh:
        return list(csv.DictReader(fh))


def out_path_for(lang: str, book: str, chapter: int) -> str:
    return os.path.join(CACHE_DIR, lang, f"{book}.{chapter}.html")


def already_cached(path: str) -> bool:
    return os.path.exists(path) and os.path.getsize(path) >= MIN_SANE_SIZE


def failures_path(lang: str) -> str:
    return os.path.join(CACHE_DIR, lang, "_failures.txt")


def build_worklist(books, langs, only_books, limit):
    """Кои (език, книга, глава) трябва да се изтеглят, по реда на четене."""
    work = []
    for lang in langs:
        scope = lang["scope"]
        for b in books:
            if only_books and b["code"] not in only_books:
                continue
            if scope == "ot" and b["testament"] == "NT":
                continue
            if scope == "nt" and b["testament"] == "OT":
                continue
            for ch in range(1, int(b["chapters"]) + 1):
                work.append((lang["code"], b["code"], ch))

    if limit:
        # ⚠ Ограничението важи ЗА ВСЕКИ ЕЗИК поотделно, не общо — иначе проба
        # с няколко езика би изтеглила само първия и щеше да изглежда, че
        # останалите ги няма.
        per_lang = {}
        trimmed = []
        for item in work:
            per_lang[item[0]] = per_lang.get(item[0], 0) + 1
            if per_lang[item[0]] <= limit:
                trimmed.append(item)
        work = trimmed

    return work


def fetch_one(session, lang, book, chapter, path):
    """Тегли една глава. Връща (успех, бележка)."""
    url = BASE_URL.format(book=book, chapter=chapter, lang=lang)

    for attempt in range(1, MAX_RETRIES + 1):
        try:
            resp = session.get(url, timeout=TIMEOUT)
        except requests.RequestException as exc:
            if attempt == MAX_RETRIES:
                return False, f"мрежа: {exc}"
            time.sleep(RETRY_BACKOFF * attempt)
            continue

        if resp.status_code != 200:
            if attempt == MAX_RETRIES:
                return False, f"HTTP {resp.status_code}"
            time.sleep(RETRY_BACKOFF * attempt)
            continue

        resp.encoding = "utf-8"
        text = resp.text

        if len(text) < MIN_SANE_SIZE:
            if attempt == MAX_RETRIES:
                return False, f"подозрително къса страница ({len(text)} знака)"
            time.sleep(RETRY_BACKOFF * attempt)
            continue

        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as fh:
            fh.write(text)
        return True, ""

    return False, "изчерпани опити"


def human_time(seconds: float) -> str:
    seconds = int(seconds)
    h, rest = divmod(seconds, 3600)
    m, s = divmod(rest, 60)
    if h:
        return f"{h} ч. {m} мин."
    if m:
        return f"{m} мин. {s} сек."
    return f"{s} сек."


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--langs", required=True,
                    help="кодове през запетая, напр. bg,utfcs,cs,r")
    ap.add_argument("--books", default="",
                    help="само тези книги (кодове през запетая) — за проба")
    ap.add_argument("--limit", type=int, default=0,
                    help="най-много N глави на език — за проба")
    ap.add_argument("--retry", action="store_true",
                    help="само главите, останали в _failures.txt")
    ap.add_argument("--plan", action="store_true",
                    help="показва сметката и излиза, без нито една заявка")
    ap.add_argument("--delay", type=float, default=0,
                    help="средна пауза между заявките в секунди (по "
                         "подразбиране 1.5-3). Вдигни я при HTTP 403 — "
                         "виж бележката при DELAY_MIN.")
    ap.add_argument("--stop-after-errors", type=int, default=40,
                    help="спира, ако толкова заявки ПОДРЕД се провалят: при "
                         "блокиране няма смисъл да се чука напразно")
    args = ap.parse_args()

    global DELAY_MIN, DELAY_MAX
    if args.delay > 0:
        DELAY_MIN = args.delay * 0.75
        DELAY_MAX = args.delay * 1.25

    books = load_csv("books.csv")
    all_langs = {row["code"]: row for row in load_csv("languages.csv")}

    wanted = [c.strip() for c in args.langs.split(",") if c.strip()]
    unknown = [c for c in wanted if c not in all_langs]
    if unknown:
        sys.exit(f"Непознати кодове: {', '.join(unknown)}. Виж input/languages.csv.")
    langs = [all_langs[c] for c in wanted]

    only_books = {b.strip() for b in args.books.split(",") if b.strip()}
    if only_books:
        known = {b["code"] for b in books}
        bad = only_books - known
        if bad:
            sys.exit(f"Непознати книги: {', '.join(sorted(bad))}")

    if args.retry:
        work = []
        for lang in langs:
            fp = failures_path(lang["code"])
            if not os.path.exists(fp):
                continue
            with open(fp, encoding="utf-8") as fh:
                for line in fh:
                    line = line.strip()
                    if not line or line.startswith("#"):
                        continue
                    ref = line.split("\t")[0]
                    book, _, ch = ref.rpartition(".")
                    work.append((lang["code"], book, int(ch)))
        print(f"повторен опит за {len(work)} глави")
    else:
        work = build_worklist(books, langs, only_books, args.limit)

    todo = [item for item in work
            if not already_cached(out_path_for(*item))]

    avg_delay = (DELAY_MIN + DELAY_MAX) / 2
    est = len(todo) * (avg_delay + 0.7)
    est += (len(todo) // LONG_PAUSE_EVERY) * LONG_PAUSE

    print()
    print(f"преводи : {', '.join(l['code'] for l in langs)}")
    print(f"общо    : {len(work)} глави")
    print(f"в кеша  : {len(work) - len(todo)}")
    print(f"остават : {len(todo)}")
    print(f"време   : около {human_time(est)}")
    print()

    if args.plan or not todo:
        if not todo and not args.plan:
            print("Няма какво да се тегли — всичко е в кеша.")
        return

    session = requests.Session()
    session.headers.update({
        "User-Agent": USER_AGENT,
        "Accept-Language": "bg,ru;q=0.8,en;q=0.5",
    })

    failures = {}
    started = time.time()
    done = 0
    consecutive = 0   # провали ПОДРЕД — брояч за спирачката при блокиране

    for lang, book, chapter in todo:
        path = out_path_for(lang, book, chapter)
        ok, note = fetch_one(session, lang, book, chapter, path)
        done += 1

        if not ok:
            failures.setdefault(lang, []).append((f"{book}.{chapter}", note))
            print(f"  ✗ {lang} {book}.{chapter} — {note}")
            consecutive += 1
            # ⚠ Поредица провали значи блокиране, не лоша страница. Чукането
            # напразно нито ще успее, нито е възпитано — по-добре да спрем и
            # да подновим по-късно с по-дълга пауза. Всичко изтеглено дотук е
            # в кеша, тъй че подновяването продължава оттам.
            if consecutive >= args.stop_after_errors:
                print(f"\n⚠ {consecutive} провала ПОДРЕД — най-вероятно сме "
                      f"ограничени по скорост. Спирам.")
                print("   Подновяване по-късно, по-бавно:")
                print(f"   python3 02_fetch_chapters.py --langs {args.langs} "
                      f"--delay 6")
                break
        else:
            consecutive = 0

        if done % 25 == 0 or done == len(todo):
            elapsed = time.time() - started
            rate = elapsed / done
            left = human_time(rate * (len(todo) - done))
            bad = sum(len(v) for v in failures.values())
            print(f"  {done}/{len(todo)}  ({lang} {book}.{chapter})  "
                  f"остават ~{left}"
                  + (f"  провалени: {bad}" if bad else ""))

        if done % LONG_PAUSE_EVERY == 0 and done < len(todo):
            print(f"  … дълга пауза {LONG_PAUSE} сек.")
            time.sleep(LONG_PAUSE)
        elif done < len(todo):
            time.sleep(random.uniform(DELAY_MIN, DELAY_MAX))

    print()
    print(f"готово за {human_time(time.time() - started)}")

    for lang in {l["code"] for l in langs}:
        fp = failures_path(lang)
        rows = failures.get(lang, [])
        if rows:
            os.makedirs(os.path.dirname(fp), exist_ok=True)
            with open(fp, "w", encoding="utf-8") as fh:
                fh.write("# глава\tпричина — пусни наново с --retry\n")
                for ref, note in rows:
                    fh.write(f"{ref}\t{note}\n")
            print(f"⚠ {lang}: {len(rows)} провалени, вписани в "
                  f"{os.path.relpath(fp, PROJECT_DIR)}")
        elif os.path.exists(fp):
            os.remove(fp)


if __name__ == "__main__":
    main()
