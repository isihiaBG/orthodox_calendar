#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
01_fetch_days.py — Кеширащ сваляч на дневните страници от azbyka.ru/days

Единствената стъпка, която пипа мрежата за дневните страници.
Тегли всяка дата само веднъж и я записва като HTML файл на диска.
Рестартируем: ако файлът вече съществува и не е празен, го прескача.

След като приключи, парсването се прави ОФЛАЙН от кеша (скрипт 02),
без нито една нова заявка.

Употреба:
    python3 01_fetch_days.py
    python3 01_fetch_days.py --start 2026-01-01 --end 2026-12-31
    python3 01_fetch_days.py --retry        # само датите, останали в failures.txt
"""

import argparse
import os
import sys
import time
import random
from datetime import date, timedelta

import requests

# ---------------------------------------------------------------------------
# Настройки (лесни за редактиране)
# ---------------------------------------------------------------------------

BASE_URL = "https://azbyka.ru/days/{date}"     # {date} = YYYY-MM-DD

# Кешът на дневните страници. Според уговорената структура — папка "days"
# успоредно на папката "scripts". __file__ сочи към scripts/, затова качваме
# едно ниво нагоре.
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.dirname(SCRIPT_DIR)
DAYS_DIR = os.path.join(PROJECT_DIR, "days")
FAILURES_FILE = os.path.join(DAYS_DIR, "_failures.txt")

# Учтивост към сайта: пауза между заявките (секунди). Диапазон, за да не е
# машинно равномерно. Не сваляй под ~1 сек.
DELAY_MIN = 1.5
DELAY_MAX = 3.0

TIMEOUT = 30            # секунди за една заявка
MAX_RETRIES = 3        # опити при мрежова грешка, преди да се откажем
RETRY_BACKOFF = 5      # секунди, умножени по номера на опита

# Коректен, честен User-Agent: казваме кои сме и защо, с адрес за контакт.
USER_AGENT = (
    "orthodox_calendar-fetcher/1.0 "
    "(non-commercial Orthodox calendar app; contact: isihiabg [at] gmail [dot] com)"
)

# Датите по подразбиране — цялата 2026 г.
DEFAULT_START = date(2026, 1, 1)
DEFAULT_END = date(2026, 12, 31)


# ---------------------------------------------------------------------------
# Помощни функции
# ---------------------------------------------------------------------------

def daterange(start: date, end: date):
    """Генерира всяка дата от start до end включително."""
    cur = start
    while cur <= end:
        yield cur
        cur += timedelta(days=1)


def out_path_for(d: date) -> str:
    """Пътят на кеш-файла за дадена дата."""
    return os.path.join(DAYS_DIR, f"{d.isoformat()}.html")


def already_cached(path: str) -> bool:
    """Истина, ако файлът съществува и не е празен."""
    return os.path.exists(path) and os.path.getsize(path) > 0


def polite_sleep():
    time.sleep(random.uniform(DELAY_MIN, DELAY_MAX))


def fetch_one(session: requests.Session, url: str) -> str | None:
    """
    Тегли един URL с повторни опити. Връща текста при успех (HTTP 200),
    или None при неуспех.
    """
    for attempt in range(1, MAX_RETRIES + 1):
        try:
            resp = session.get(url, timeout=TIMEOUT)
        except requests.RequestException as e:
            print(f"    ! мрежова грешка (опит {attempt}/{MAX_RETRIES}): {e}")
            time.sleep(RETRY_BACKOFF * attempt)
            continue

        if resp.status_code == 200:
            # Азбука е на UTF-8; налагаме го, за да не гадае requests.
            resp.encoding = "utf-8"
            return resp.text

        if resp.status_code == 429:
            # Твърде много заявки — изчакай по-дълго и опитай пак.
            wait = RETRY_BACKOFF * attempt * 3
            print(f"    ! 429 Too Many Requests — изчаквам {wait} сек")
            time.sleep(wait)
            continue

        if resp.status_code == 404:
            print(f"    ! 404 Not Found — датата липсва на сайта")
            return None

        print(f"    ! HTTP {resp.status_code} (опит {attempt}/{MAX_RETRIES})")
        time.sleep(RETRY_BACKOFF * attempt)

    return None


def load_retry_dates() -> list[date]:
    """Чете датите за повторен опит от _failures.txt."""
    if not os.path.exists(FAILURES_FILE):
        print(f"Няма файл {FAILURES_FILE} — нищо за повтаряне.")
        return []
    dates = []
    with open(FAILURES_FILE, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line:
                dates.append(date.fromisoformat(line))
    return dates


def save_failures(failed: list[date]):
    """Записва останалите неуспешни дати за следващ --retry."""
    if not failed:
        # Ако всичко е минало, чистим стария файл.
        if os.path.exists(FAILURES_FILE):
            os.remove(FAILURES_FILE)
        return
    with open(FAILURES_FILE, "w", encoding="utf-8") as f:
        for d in failed:
            f.write(d.isoformat() + "\n")
    print(f"\n{len(failed)} неуспешни дати са записани в {FAILURES_FILE}")
    print("Пусни отново с флага --retry, за да ги опиташ пак.")


# ---------------------------------------------------------------------------
# Основна логика
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(description="Кеширащ сваляч на дневни страници от azbyka.ru")
    parser.add_argument("--start", type=date.fromisoformat, default=DEFAULT_START,
                        help="начална дата YYYY-MM-DD (по подразбиране 2026-01-01)")
    parser.add_argument("--end", type=date.fromisoformat, default=DEFAULT_END,
                        help="крайна дата YYYY-MM-DD (по подразбиране 2026-12-31)")
    parser.add_argument("--retry", action="store_true",
                        help="тегли само датите, останали в _failures.txt")
    args = parser.parse_args()

    os.makedirs(DAYS_DIR, exist_ok=True)

    if args.retry:
        dates = load_retry_dates()
        if not dates:
            return
        print(f"Повторен опит за {len(dates)} дати.")
    else:
        dates = list(daterange(args.start, args.end))
        print(f"Обхват: {args.start} … {args.end}  ({len(dates)} дни)")

    session = requests.Session()
    session.headers.update({"User-Agent": USER_AGENT})

    fetched = 0
    skipped = 0
    failed: list[date] = []

    for i, d in enumerate(dates, 1):
        path = out_path_for(d)

        if already_cached(path):
            skipped += 1
            continue

        url = BASE_URL.format(date=d.isoformat())
        print(f"[{i}/{len(dates)}] {d.isoformat()} → тегля…")

        html = fetch_one(session, url)

        if html is None:
            print(f"    ✗ неуспех за {d.isoformat()}")
            failed.append(d)
        else:
            # Записваме атомарно: първо във временен файл, после преименуваме,
            # за да няма полусвалени файлове при прекъсване.
            tmp = path + ".part"
            with open(tmp, "w", encoding="utf-8") as f:
                f.write(html)
            os.replace(tmp, path)
            fetched += 1
            print(f"    ✓ записан ({len(html):,} байта)")

        # Пауза само след реална мрежова заявка (не след прескочен файл).
        if i < len(dates):
            polite_sleep()

    print("\n" + "=" * 50)
    print(f"Свалени сега : {fetched}")
    print(f"Прескочени   : {skipped}  (вече в кеша)")
    print(f"Неуспешни    : {len(failed)}")
    print("=" * 50)

    save_failures(failed)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\nПрекъснато от потребителя. Кешът е запазен — пусни пак, за да продължиш.")
        sys.exit(1)
