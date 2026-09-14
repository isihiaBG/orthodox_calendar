#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Сваля указателя на житията и вади от него всички връзки.

Изход: `work/site_index.json` — по един запис на СТРАНИЦА (не на връзка).

⚠ ЕДНА заявка към сайта. Указателят се пази в `cache/`, тъй че повторно
пускане не го тегли наново (освен с --refresh).

⚠ Датата е В САМОТО ИМЕ на файла — „01.04_sv_Onufrij_Gabrovski.htm" — и е
ЦЪРКОВНА (стар стил), сверено срещу календара ни. Това е много по-надежден
ключ от заглавието: то се разминава по прозвище („Видински"/„Бдински") и по
съкращение („Димитрий"/„D"), а датата — не.

⚠ Указателят на този сайт е НЕПЪЛЕН по начало — при Библията се оказа, че
изброява 60 книги от 77, а останалите просто нямат връзка. Затова тук не се
приема за изчерпателен: `03_match.py` пробва и адреси, отгатнати по схема.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

from common import CACHE, INDEX_URL, SITE, WORK, fold

UA = 'Mozilla/5.0 (compatible; orthodox-calendar/1.0; +non-commercial church app)'

# Връзка към житие, заедно с текста ѝ (той е заглавието в указателя).
RE_LINK = re.compile(
    r'<a\s+[^>]*href="([^"]*life/[^"]+)"[^>]*>(.*?)</a>',
    re.IGNORECASE | re.DOTALL)
RE_TAGS = re.compile(r'<[^>]+>')
# „01.04_sv_Onufrij_Gabrovski.htm" и „11_06_sv_Pavel_Izpovednik.htm" —
# ⚠ разделителят е ту точка, ту долна черта. Един-единствен файл ползва
# второто, но сглобен само с точка, той изчезва мълчаливо.
RE_DATED = re.compile(r'(\d{2})[._](\d{2})[._](.+)\.html?$', re.IGNORECASE)


def fetch(url: str, refresh: bool = False) -> str:
    """Сваля страница, пазейки я в `cache/`. Второто пускане не пипа мрежата."""
    name = urllib.parse.urlparse(url).path.lstrip('/').replace('/', '__')
    path = CACHE / name
    if path.exists() and not refresh:
        return path.read_text(encoding='utf-8', errors='replace')

    req = urllib.request.Request(url, headers={'User-Agent': UA})
    with urllib.request.urlopen(req, timeout=30) as resp:
        raw = resp.read()

    # ⚠ Сайтът смесва две кодировки — по-новите страници са UTF-8, по-старите
    # windows-1251 (38 от 227 при Библията). Обявената в самия файл има превес.
    head = raw[:2000].decode('ascii', errors='replace').lower()
    m = re.search(r'charset=["\']?([a-z0-9-]+)', head)
    enc = m.group(1) if m else 'utf-8'
    if enc in ('windows-1251', 'cp1251', 'win-1251'):
        text = raw.decode('cp1251', errors='replace')
    else:
        text = raw.decode('utf-8', errors='replace')

    CACHE.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding='utf-8')
    return text


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument('--refresh', action='store_true',
                    help='тегли указателя наново, вместо от cache/')
    args = ap.parse_args()

    try:
        html = fetch(INDEX_URL, refresh=args.refresh)
    except urllib.error.URLError as e:
        sys.exit(f'указателят не се сваля: {e}')

    pages: dict[str, dict] = {}
    for href, label in RE_LINK.findall(html):
        # Адресът в указателя е относителен спрямо неговата папка.
        url = urllib.parse.urljoin(INDEX_URL, href)
        if not url.startswith(SITE):
            continue
        path = urllib.parse.urlparse(url).path
        title = RE_TAGS.sub(' ', label)
        title = re.sub(r'\s+', ' ', title).strip()

        rec = pages.setdefault(path, {
            'path': path, 'url': url, 'titles': [], 'date': None, 'stem': None,
        })
        if title and title not in rec['titles']:
            rec['titles'].append(title)

        m = RE_DATED.search(path.rsplit('/', 1)[-1])
        if m:
            rec['date'] = f'{m.group(1)}-{m.group(2)}'
            rec['stem'] = m.group(3)

    out = sorted(pages.values(), key=lambda p: (p['date'] or 'zz', p['path']))
    for rec in out:
        rec['title_fold'] = fold(' '.join(rec['titles']))

    WORK.mkdir(parents=True, exist_ok=True)
    dest = WORK / 'site_index.json'
    dest.write_text(json.dumps(out, ensure_ascii=False, indent=2),
                    encoding='utf-8')

    dated = sum(1 for r in out if r['date'])
    print(f'връзки в указателя:     {len(RE_LINK.findall(html))}')
    print(f'различни страници:      {len(out)}')
    print(f'  с дата в името:       {dated}')
    print(f'  без дата (подпапки):  {len(out) - dated}')
    print(f'\n→ {dest.relative_to(dest.parents[2])}')


if __name__ == '__main__':
    main()
