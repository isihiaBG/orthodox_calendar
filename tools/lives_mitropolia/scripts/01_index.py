#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Указателят на поредицата „Кръстният подвиг на българските светии".

Изход: `work/index.json` — {адрес: заглавие}.
⚠ Мрежова стъпка. Страниците се пазят в `cache/cat*.html` и не се теглят
повторно; за нов обход — `--force`.
"""

from __future__ import annotations

import argparse
import html
import json
import re

from common import CACHE, CATEGORY, WORK, fetch

# ⚠ Само статии за светии. Категорията носи и „Кратка история на Софийска
# епархия", устави, преводи на Писанието — всичко, което редакцията е
# сложила в същия раздел.
RE_ARTICLE = re.compile(
    r'<a[^>]+href="(https://mitropolia-sofia\.org/\d{4}/\d\d/\d\d/[^"]+)"'
    r'[^>]*>([^<]{6,140})</a>')
RE_SAINT = re.compile(r'^\s*Св\.', re.I)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument('--force', action='store_true', help='тегли наново')
    ap.add_argument('--pages', type=int, default=10)
    args = ap.parse_args()

    found: dict[str, str] = {}
    for p in range(1, args.pages + 1):
        url = CATEGORY if p == 1 else f'{CATEGORY}{p}/'
        dest = CACHE / f'cat{p}.html'
        try:
            got = fetch(url, dest, force=args.force)
        except Exception as e:                      # noqa: BLE001
            print(f'  стр {p}: {e}')
            break
        t = dest.read_text(encoding='utf-8', errors='ignore')
        page = {}
        for m in RE_ARTICLE.finditer(t):
            title = html.unescape(re.sub(r'\s+', ' ', m.group(2))).strip()
            if RE_SAINT.match(title):
                page[m.group(1)] = title
        new = len(set(page) - set(found))
        found.update(page)
        print(f'  стр {p}: {len(page)} статии ({new} нови)'
              f'{"  ← свалена сега" if got else ""}')
        # ⚠ Свършили са, щом страницата не добавя нищо ново: WordPress връща
        # последната страница и за всеки номер отвъд нея, вместо 404.
        if not new and p > 1:
            break

    WORK.mkdir(exist_ok=True)
    (WORK / 'index.json').write_text(
        json.dumps(found, ensure_ascii=False, indent=1), encoding='utf-8')
    print(f'\nжития на светии: {len(found)}   → work/index.json')


if __name__ == '__main__':
    main()
