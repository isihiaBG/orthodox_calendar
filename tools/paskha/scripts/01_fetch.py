#!/usr/bin/env python3
"""Сваля страниците за Пасха от azbyka.ru в `cache/`.

⚠ ЕДИНСТВЕНАТА мрежова стъпка. Свалено веднъж не се тегли повторно; за нов
обход — `--force`.

    python3 01_fetch.py
    python3 01_fetch.py --force
"""
import argparse
from pathlib import Path

import requests

КОРЕН = Path(__file__).resolve().parents[1]
КЕШ = КОРЕН / 'cache'

# ⚠⚠ ОСНОВНАТА СТРАНИЦА Е `/paskha/1`, НЕ `/paskha`. Двете връщат един и същи
# HTML, но адресите в съдържанието сочат „1/#ch_0_N" — тоест текстът живее на
# втората. Първата е запазена само за пълнота.
СТРАНИЦИ = {
    'page1.html': 'https://azbyka.ru/paskha/1',
    'hymns.html': 'https://azbyka.ru/pashalnye-pesnopeniya',
    'chasy.html': 'https://azbyka.ru/chasy-pasxalnye',
    'kanon.html': 'https://azbyka.ru/molitvoslov/'
                  'pasxalnyj-kanon-tvorenie-ioanna-damaskina.html',
}

ЗАГЛАВКИ = {'User-Agent': 'Mozilla/5.0 (orthodox-calendar research)'}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('--force', action='store_true')
    a = ap.parse_args()
    КЕШ.mkdir(parents=True, exist_ok=True)
    for име, url in СТРАНИЦИ.items():
        цел = КЕШ / име
        if цел.exists() and цел.stat().st_size > 1000 and not a.force:
            print(f'  {име:14} вече е свалена ({цел.stat().st_size:,} б.)')
            continue
        r = requests.get(url, headers=ЗАГЛАВКИ, timeout=60)
        if r.status_code != 200:
            print(f'  ⚠ {име:14} HTTP {r.status_code} — {url}')
            continue
        цел.write_text(r.text, encoding='utf-8')
        print(f'  {име:14} {len(r.text):,} байта')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
