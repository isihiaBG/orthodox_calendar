#!/usr/bin/env python3
"""Сваля страниците от input/pages.csv → cache/pages/<слъг>.html.

    python3 10_fetch_pages.py --stage 1
    python3 10_fetch_pages.py --stage 1 --force

⚠ Възобновим: вече свалена страница се прескача. Прекъснато пускане не
губи нищо и не тегли наново.

⚠ Пауза между заявките — сайтът е чужд и не бива да се залива.
"""
import argparse, csv, os, sys, time
from pathlib import Path
import requests

КОРЕН = Path(__file__).resolve().parents[1]
СПИСЪК = КОРЕН / 'input' / 'pages.csv'
КЕШ = КОРЕН / 'cache' / 'pages'
ПАУЗА = 1.2


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('--stage', type=int, required=True)
    ap.add_argument('--force', action='store_true')
    a = ap.parse_args()

    КЕШ.mkdir(parents=True, exist_ok=True)
    редове = [r for r in csv.DictReader(open(СПИСЪК, encoding='utf-8'))
              if int(r['stage']) == a.stage]
    print(f'етап {a.stage}: {len(редове)} страници')
    нови = пропуснати = грешни = 0
    for r in редове:
        цел = КЕШ / (r['slug'] + '.html')
        if цел.exists() and not a.force:
            пропуснати += 1
            continue
        try:
            resp = requests.get(r['url'], timeout=60,
                                headers={'User-Agent': 'Mozilla/5.0'})
            resp.raise_for_status()
            цел.write_text(resp.text, encoding='utf-8')
            нови += 1
            print(f"  ✅ {r['slug']:34} {len(resp.text):>8} байта")
        except Exception as e:                          # noqa: BLE001
            грешни += 1
            print(f"  ⚠ {r['slug']:34} {e}")
        time.sleep(ПАУЗА)
    print(f'свалени {нови} | вече налични {пропуснати} | неуспешни {грешни}')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
