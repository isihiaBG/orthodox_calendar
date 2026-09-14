#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Сваля илюстрациите към житията и ги подрежда за приложението.

Изход: `cache/img/` (свалените, дословно) + `work/images.json` (картата).

⚠ Поводът: описанията под картинките ВЕЧЕ са в текста („Стенопис от ХV в. в
църквата…"), но самите картинки ги няма. Пояснение без илюстрация е по-лошо
от липсата и на двете — чете се като недоглеждане.

⚠ Тегли се ВЕДНЪЖ, в `cache/img/`. Оттам `09_place_images.py` ги слага в
`assets/` — разделено по същата причина като при страниците: донастройването
на размера и имената не бива да струва нови заявки към чужд сайт.

## Кои картинки

Само тези под `icons/` — там живеят същинските илюстрации (икони, стенописи,
мозайки), подредени по дата и светия. ⚠ Всичко в `../images/` е обзавеждане
на сайта (стрелки, пликчета, разделители) и НЕ влиза.

## Атрибуция

⚠ Изображенията идват от същия сайт като текстовете и стоят под същата
уговорка — виж README.md, раздела за правата. Всяко носи адреса, от който е
свалено, в `work/images.json`, за да може да се посочи източникът.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import time
import urllib.error
import urllib.parse
import urllib.request
from collections import defaultdict

from common import CACHE, SITE, WORK

UA = 'Mozilla/5.0 (compatible; orthodox-calendar/1.0; +non-commercial church app)'
DELAY = 0.7
IMG_DIR = CACHE / 'img'

RE_IMG = re.compile(r'<img[^>]+src="([^"]+)"[^>]*>', re.I)
# ⚠ Обзавеждането на сайта — стрелки, пликчета, разделители. Влезе ли, в
# житието се появяват иконки за е-поща насред разказа.
RE_CHROME = re.compile(
    r'(i\.gif|spacer|button|arrow|/line|bullet|logo|banner|felles|'
    r'molitvoslov/skiller|bible_icon)', re.I)

# ⚠ ИЛЮСТРАЦИИТЕ НЕ СА САМО В `icons/`. Първата версия взимаше само тази
# папка и пропускаше 69 изображения — цели раздели българска иконопис
# (`iconopis_bulgarian/`), исторически репродукции (`history/`), снимки на
# храмове (`hramove/`). Личеше косвено: девет НАДПИСА стояха в текста без
# картинка над тях, защото описваха точно пропуснатите.
#
# ⚠ Този списък ТРЯБВА да съвпада с `RE_IMG_GOOD` в `05_parse.py`. Разминат
# ли се, парсърът слага в текста картинка, която тук не е свалена (или
# обратното) — и в двата случая четивото излиза счупено.
RE_IMG_GOOD = re.compile(
    r'(icons/|iconopis|ikonopis|/history/|hramove|poklonnichestvo|'
    r'MANUSCRIPTS)', re.I)



def flat_name(page_path: str, src: str) -> str:
    """Плоско, устойчиво име за `assets/`.

    ⚠ Пътищата в сайта са дълбоки и се повтарят между страници
    (`icons/001/…/1.jpg` го има на няколко места, с РАЗЛИЧНО съдържание).
    Затова името носи и къс отпечатък на пълния адрес — инак две различни
    картинки се презаписват мълчаливо.
    """
    base = src.rsplit('/', 1)[-1]
    base = re.sub(r'[^A-Za-z0-9._-]+', '_', base)
    stem, _, ext = base.rpartition('.')
    stem = (stem or base)[:40]
    digest = hashlib.sha1(f'{page_path}|{src}'.encode()).hexdigest()[:8]
    return f'{stem}_{digest}.{(ext or "jpg").lower()}'


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument('--refresh', action='store_true')
    ap.add_argument('--limit', type=int, default=0)
    args = ap.parse_args()

    # Само страниците, които реално влизат в базата.
    cands = json.loads((WORK / 'candidates.json').read_text(encoding='utf-8'))
    used = {s['matches'][0]['path'] for s in cands if s['matches']}

    wanted: dict[tuple[str, str], str] = {}
    for page in sorted(used):
        cached = CACHE / page.lstrip('/').replace('/', '__')
        if not cached.exists():
            continue
        html = cached.read_text(encoding='utf-8')
        for m in RE_IMG.finditer(html):
            src = m.group(1)
            if RE_CHROME.search(src):
                continue
            if not RE_IMG_GOOD.search(src):
                continue
            wanted[(page, src)] = flat_name(page, src)

    print(f'илюстрации за сваляне: {len(wanted)}')
    IMG_DIR.mkdir(parents=True, exist_ok=True)

    records = []
    got = skipped = failed = 0
    for i, ((page, src), name) in enumerate(sorted(wanted.items()), 1):
        dest = IMG_DIR / name
        url = urllib.parse.urljoin(f'{SITE}{page}', src)

        if dest.exists() and not args.refresh:
            skipped += 1
        else:
            try:
                req = urllib.request.Request(url, headers={'User-Agent': UA})
                with urllib.request.urlopen(req, timeout=30) as resp:
                    data = resp.read()
                # ⚠ Сървър зад прокси връща HTML със статус 200 при грешка.
                # Картинка под 200 байта почти сигурно е такава страница.
                if len(data) < 200:
                    failed += 1
                    print(f'  [{i:3}] ✗ {name} — само {len(data)} байта')
                    continue
                dest.write_bytes(data)
                got += 1
                print(f'  [{i:3}/{len(wanted)}] ✓ {name}  ({len(data)//1024} KB)')
            except urllib.error.HTTPError as e:
                failed += 1
                print(f'  [{i:3}] ✗ {name} — HTTP {e.code}')
                continue
            except urllib.error.URLError as e:
                failed += 1
                print(f'  [{i:3}] ✗ {name} — {e.reason}')
                continue
            time.sleep(DELAY)
            if args.limit and got >= args.limit:
                print(f'  …спряно на {args.limit} (--limit)')
                break

        records.append({'page': page, 'src': src, 'file': name, 'url': url,
                        'bytes': dest.stat().st_size if dest.exists() else 0})

    (WORK / 'images.json').write_text(
        json.dumps(records, ensure_ascii=False, indent=2), encoding='utf-8')

    total = sum(r['bytes'] for r in records)
    by_page = defaultdict(int)
    for r in records:
        by_page[r['page']] += 1
    print(f'\nсвалени: {got}   вече налични: {skipped}   провалени: {failed}')
    print(f'общо: {total/1024/1024:.1f} MB в {len(by_page)} жития')
    print(f'\n→ cache/img/,  work/images.json')


if __name__ == '__main__':
    main()
