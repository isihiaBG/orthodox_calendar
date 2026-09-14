#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
03_fetch_saints.py — Тегли страниците на светиите по output/saints_slugs.txt
                    (или по друг списък: --slugs ../output/athos_slugs.txt)
и ги кешира в days/saints/<slug>.html. Рестартируем, учтив, като 01.
"""

import os, sys, time, random
import requests

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.dirname(SCRIPT_DIR)
SAINTS_DIR = os.path.join(PROJECT_DIR, "days", "saints")
SLUGS_FILE = os.path.join(PROJECT_DIR, "output", "saints_slugs.txt")
FAILURES_FILE = os.path.join(SAINTS_DIR, "_failures.txt")

DELAY_MIN, DELAY_MAX = 1.5, 3.0
TIMEOUT, MAX_RETRIES, RETRY_BACKOFF = 30, 3, 5
USER_AGENT = ("orthodox_calendar-fetcher/1.0 "
              "(non-commercial Orthodox calendar app; contact: isihiabg [at] gmail [dot] com)")

def fetch_one(session, url):
    for attempt in range(1, MAX_RETRIES + 1):
        try:
            resp = session.get(url, timeout=TIMEOUT)
        except requests.RequestException as e:
            print(f"    ! мрежова грешка (опит {attempt}/{MAX_RETRIES}): {e}")
            time.sleep(RETRY_BACKOFF * attempt); continue
        if resp.status_code == 200:
            resp.encoding = "utf-8"; return resp.text
        if resp.status_code == 429:
            wait = RETRY_BACKOFF * attempt * 3
            print(f"    ! 429 — изчаквам {wait} сек"); time.sleep(wait); continue
        if resp.status_code == 404:
            print("    ! 404 — страницата липсва"); return None
        print(f"    ! HTTP {resp.status_code}"); time.sleep(RETRY_BACKOFF * attempt)
    return None

def main():
    retry = "--retry" in sys.argv

    # --slugs ПЪТ  — чете слъговете от друг файл вместо от saints_slugs.txt.
    # Полезно за допълване (напр. светогорския списък), без да се пипа
    # основният файл. Кешираните страници пак се пропускат.
    custom = None
    if "--slugs" in sys.argv:
        i = sys.argv.index("--slugs")
        if i + 1 >= len(sys.argv):
            print("--slugs иска път до файл."); sys.exit(1)
        custom = sys.argv[i + 1]

    os.makedirs(SAINTS_DIR, exist_ok=True)
    src = FAILURES_FILE if retry else (custom or SLUGS_FILE)
    if not os.path.exists(src):
        print(f"Липсва {src}."); sys.exit(1)
    slugs = [l.strip() for l in open(src, encoding="utf-8") if l.strip()]
    print(f"{'Повторен опит' if retry else 'Обхват'}: {len(slugs)} слъга")

    session = requests.Session(); session.headers.update({"User-Agent": USER_AGENT})
    fetched = skipped = 0; failed = []

    for i, slug in enumerate(slugs, 1):
        path = os.path.join(SAINTS_DIR, f"{slug}.html")
        if os.path.exists(path) and os.path.getsize(path) > 0:
            skipped += 1; continue
        url = f"https://azbyka.ru/days/{slug}"
        print(f"[{i}/{len(slugs)}] {slug} → тегля…")
        html = fetch_one(session, url)
        if html is None:
            failed.append(slug); print("    ✗ неуспех")
        else:
            tmp = path + ".part"
            open(tmp, "w", encoding="utf-8").write(html)
            os.replace(tmp, path)
            fetched += 1; print(f"    ✓ записан ({len(html):,} байта)")
        if i < len(slugs):
            time.sleep(random.uniform(DELAY_MIN, DELAY_MAX))

    print(f"\nСвалени: {fetched} | Прескочени: {skipped} | Неуспешни: {len(failed)}")
    if failed:
        open(FAILURES_FILE, "w", encoding="utf-8").write("\n".join(failed) + "\n")
        print(f"Неуспешните са в {FAILURES_FILE} — пусни с --retry.")
    elif os.path.exists(FAILURES_FILE):
        os.remove(FAILURES_FILE)

if __name__ == "__main__":
    try: main()
    except KeyboardInterrupt:
        print("\nПрекъснато. Кешът е запазен — пусни пак, за да продължиш."); sys.exit(1)
