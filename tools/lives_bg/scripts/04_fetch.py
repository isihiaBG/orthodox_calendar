#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Сваля страниците с житията ДОСЛОВНО в `cache/`.

⚠ ЕДИНСТВЕНИЯТ скрипт, който пипа мрежата (освен `02_index.py` за указателя).
Всичко нататък се пресмята от `cache/`, тъй че донастройването на парсването
не струва нито една заявка — това е изричното изискване към конвейера.

⚠ Свалената страница се пази КАКТО Е, без изчистване. Изкушението е да се
запише вече разчетеното; но тогава всяка промяна в разбирането ни за формата
иска ново теглене, а сайтът е чужд и бавен.

Учтивост към сайта: една заявка в секунда, пропускат се вече свалените.
Повторно пускане не тегли нищо (освен с --refresh).
"""

from __future__ import annotations

import argparse
import json
import time
import urllib.error
import urllib.parse
import urllib.request

from common import CACHE, SITE, WORK

UA = 'Mozilla/5.0 (compatible; orthodox-calendar/1.0; +non-commercial church app)'
DELAY = 1.0


def cache_path(path: str):
    """Един URL → един файл в `cache/`, с име, от което пътят се чете."""
    return CACHE / path.lstrip('/').replace('/', '__')


def fetch(url: str, dest, refresh: bool = False) -> tuple[bool, str]:
    """Сваля една страница. Връща (пипната ли е мрежата, съобщение)."""
    if dest.exists() and not refresh:
        return False, 'вече е тук'

    req = urllib.request.Request(url, headers={'User-Agent': UA})
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            raw = resp.read()
    except urllib.error.HTTPError as e:
        return True, f'HTTP {e.code}'
    except urllib.error.URLError as e:
        return True, f'мрежа: {e.reason}'

    # ⚠ Две кодировки в един сайт — по-новите страници са UTF-8, по-старите
    # windows-1251 (при Библията: 38 от 227). Обявената в самия файл има
    # превес; без това толкова страници влизат със счупени букви и това не
    # личи, докато някой не ги прочете.
    head = raw[:3000].decode('ascii', errors='replace').lower()
    import re
    m = re.search(r'charset=["\']?([a-z0-9-]+)', head)
    enc = (m.group(1) if m else 'utf-8').lower()
    if enc in ('windows-1251', 'cp1251', 'win-1251'):
        text, used = raw.decode('cp1251', errors='replace'), 'cp1251'
    else:
        text, used = raw.decode('utf-8', errors='replace'), 'utf-8'

    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_text(text, encoding='utf-8')
    return True, f'{len(raw)//1024} KB, {used}'


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument('--refresh', action='store_true',
                    help='тегли наново дори вече свалените')
    ap.add_argument('--limit', type=int, default=0,
                    help='спира след толкова заявки (за проба)')
    ap.add_argument('--all-candidates', action='store_true',
                    help='тегли ВСИЧКИ кандидати, не само първия за светия')
    args = ap.parse_args()

    cands = json.loads((WORK / 'candidates.json').read_text(encoding='utf-8'))

    # Кои страници ни трябват. По подразбиране — най-добрият кандидат за
    # всеки светия; с --all-candidates и останалите, за случаите, при които
    # верният не е първи.
    wanted: dict[str, list] = {}
    for s in cands:
        picks = s['matches'] if args.all_candidates else s['matches'][:1]
        for m in picks:
            wanted.setdefault(m['path'], []).append(s['name_core'])

    print(f'страници за сваляне: {len(wanted)}')
    fetched = skipped = failed = 0
    log = []

    for i, (path, saints) in enumerate(sorted(wanted.items()), 1):
        dest = cache_path(path)
        url = urllib.parse.urljoin(SITE, path)
        touched, msg = fetch(url, dest, refresh=args.refresh)

        if not touched:
            skipped += 1
        elif msg.startswith(('HTTP', 'мрежа')):
            failed += 1
            log.append({'path': path, 'error': msg})
            print(f'  [{i:3}/{len(wanted)}] ✗ {path}  — {msg}')
        else:
            fetched += 1
            print(f'  [{i:3}/{len(wanted)}] ✓ {path}  ({msg})')

        if touched:
            if args.limit and fetched >= args.limit:
                print(f'  …спряно на {args.limit} заявки (--limit)')
                break
            time.sleep(DELAY)

    print(f'\nсвалени: {fetched}   пропуснати (вече в cache): {skipped}'
          f'   провалени: {failed}')
    if log:
        (WORK / 'fetch_failures.json').write_text(
            json.dumps(log, ensure_ascii=False, indent=2), encoding='utf-8')
        print('⚠ провалените са в work/fetch_failures.json')
        print('  ⚠ файлът ОСТАРЯВА — не съди по него при следващо пускане,')
        print('    а по това дали страницата е в cache/ (вж. README).')


if __name__ == '__main__':
    main()
