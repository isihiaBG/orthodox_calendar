#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Слага илюстрациите в `assets/` и подменя пътищата в разчетеното.

Вход:  `cache/img/` (свалено от 08_images.py) + `work/parsed/*.json`
Изход: `assets/lives_images/` + подменени пътища в същите JSON-и

⚠ Пуска се СЛЕД `05_parse.py` и ПРЕДИ `06_apply.py`. Парсърът оставя
временния адрес от сайта (`icons/001/…jpg`); тук той става името на файла в
`assets/`. Разделено е така, защото парсването се повтаря често, а копирането
на файлове — не.

⚠ Имената в `assets/` са ПЛОСКИ и носят къс отпечатък на пълния адрес.
Причината: в сайта един и същ прост файл (`1.jpg`) се среща в няколко папки с
РАЗЛИЧНО съдържание. Само по basename те се презаписват мълчаливо и житието
показва чужда картинка.

⚠ Папката се изброява ИЗРИЧНО в `pubspec.yaml` — там няма общо `assets/`, а
ред за всяка папка поотделно. Забрави ли се, картинките не влизат в APK-то и
това личи чак на устройството.
"""

from __future__ import annotations

import argparse
import json
import re
import shutil
import sqlite3
from pathlib import Path

from common import CACHE, INPUT, LIVES_DB, ROOT, WORK

ASSETS = ROOT / 'assets' / 'lives_images'
IMG_DIR = CACHE / 'img'


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument('--dry-run', action='store_true')
    args = ap.parse_args()

    images = json.loads((WORK / 'images.json').read_text(encoding='utf-8'))

    # (страница, адрес-в-сайта) → име на файла
    by_src: dict[tuple[str, str], str] = {
        (r['page'], r['src']): r['file'] for r in images
    }
    # адресът сам по себе си, за случаите, в които страницата се разминава
    by_src_only: dict[str, str] = {}
    for r in images:
        by_src_only.setdefault(r['src'], r['file'])

    parsed = sorted((WORK / 'parsed').glob('*.json'))
    placed = missing = 0
    used: set[str] = set()
    touched = 0

    for path in parsed:
        rec = json.loads(path.read_text(encoding='utf-8'))
        html = rec['life_html']
        if '<img' not in html:
            continue
        page = '/' + rec['source_url'].split('/', 3)[-1] if rec.get(
            'source_url') else ''

        import re

        def swap(m: re.Match) -> str:
            nonlocal placed, missing
            src = m.group(1)
            rest = m.group(2) or ''      # alt + width/height, както са дошли
            name = by_src.get((page, src)) or by_src_only.get(src)
            if not name or not (IMG_DIR / name).exists():
                missing += 1
                return ''            # няма файл → махаме тага, не оставяме счупен
            placed += 1
            used.add(name)
            # ⚠ ОСТАНАЛИТЕ АТРИБУТИ СЕ ПАЗЯТ ДОСЛОВНО — сред тях са
            # `width`/`height`, от които четецът смята съотношението. Изгубят
            # ли се, картинката се свива до височината на текстовия ред и от
            # нея се вижда само тънка ивица.
            return f'<img src="assets/lives_images/{name}"{rest}>'

        new_html = re.sub(r'<img src="([^"]+)"([^>]*)>', swap, html)

        if new_html != html and not args.dry_run:
            rec['life_html'] = new_html
            path.write_text(json.dumps(rec, ensure_ascii=False, indent=2),
                            encoding='utf-8')
            touched += 1

    print(f'подменени пътища:   {placed}')
    print(f'без наличен файл:   {missing}  (тагът се маха)')
    print(f'пипнати жития:      {touched}')

    if args.dry_run:
        print('\n--dry-run: нищо не е копирано')
        return

    ASSETS.mkdir(parents=True, exist_ok=True)
    # ⚠ Копират се САМО реално използваните. Свалени са и такива, които после
    # отпадат (чужда страница, отхвърлено житие) — те нямат работа в APK-то.
    copied = 0
    total_bytes = 0
    for name in sorted(used):
        src = IMG_DIR / name
        dst = ASSETS / name
        if not dst.exists() or dst.stat().st_size != src.stat().st_size:
            shutil.copy2(src, dst)
            copied += 1
        total_bytes += dst.stat().st_size

    # Изчистване на осиротелите — иначе папката расте с всяко пускане.
    #
    # ⚠ СВЕРЯВА СЕ СРЕЩУ ЦЯЛАТА БАЗА, не срещу собствения списък. В
    # `assets/lives_images/` пише И ДРУГ конвейер (`tools/lives_extra/`), а
    # неговите файлове не са в `used`. Сверявано само със своето, чистенето
    # ги изтриваше ВСИЧКИТЕ — тихо, без грешка; личеше чак когато четивото
    # се отвори и на мястото на илюстрацията зее празно. (01.09.2026:
    # изтрити бяха 10 картинки на св. Евстатий Чепеларски и на Монреалската
    # икона.)
    #
    # Правилото е просто: файл, към който сочи КОЕТО И ДА Е житие в
    # `lives.db`, не се трие — независимо кой го е сложил.
    referenced = set(used)
    try:
        con = sqlite3.connect(LIVES_DB)
        for (life,) in con.execute(
                "SELECT life FROM texts WHERE life LIKE '%lives_images/%'"):
            referenced.update(
                re.findall(r'assets/lives_images/([^"\'\s>]+)', life or ''))
        con.close()
    except Exception as e:                            # noqa: BLE001
        # ⚠ Не пипаме нищо, ако базата не се чете: по-добре папката да
        # порасне, отколкото да изтрием чуждо.
        print(f'  ⚠ базата не се чете ({e}) — чистенето се пропуска')
        referenced = None

    orphans = ([p for p in ASSETS.glob('*') if p.name not in referenced]
               if referenced is not None else [])
    for p in orphans:
        p.unlink()

    print(f'\nв assets/lives_images/: {len(used)} файла, '
          f'{total_bytes/1024/1024:.1f} MB  (копирани сега: {copied})')
    if orphans:
        print(f'изтрити осиротели:      {len(orphans)}')
    print('\n⚠ Папката трябва да е изброена в pubspec.yaml — там няма общо'
          ' `assets/`.')


if __name__ == '__main__':
    main()
