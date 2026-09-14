#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Кои от намерените жития ни ЛИПСВАТ.

Вход:  `work/index.json` + календарът и `lives.db`
Изход: `work/plan.json` — само онези, за които светията съществува в
       календара, но няма (или има твърде късо) житие.

⚠ БЕЗ МРЕЖА. Пуска се колкото пъти трябва, докато засечката се укроти.

⚠ Ръчните решения — `input/manual_map.csv` (колони: slug,url,note). Те са
по-силни от засичането по име: сайтът често титулува светията другояче
(„Димитра Киевска" срещу „Димитра Доростолска") и приликата не стига.
"""

from __future__ import annotations

import argparse
import csv
import json
import sqlite3

from common import CALENDAR_DB, INPUT, LIVES_DB, WORK, similarity

# Под този праг четивото се смята за липсващо (същата мярка като в
# tools/lives_bg: под 3500 знака е кратка бележка, не житие).
SHORT = 3500
# Приликата, под която засечката по име не се приема за сигурна.
MIN_SCORE = 0.75


def load_manual() -> list[dict]:
    """Ръчните двойки. Колони: `slug` ИЛИ `name`, плюс `url` и `note`.

    ⚠ Приема се и ИМЕ, не само слъг: светиите, за които най-често трябва
    ръчно решение, са тъкмо тези БЕЗ слъг — той им се дава чак при
    внасянето.
    """
    path = INPUT / 'manual_map.csv'
    if not path.exists():
        return []
    with path.open(encoding='utf-8') as fh:
        return [r for r in csv.DictReader(fh)
                if r.get('url') and (r.get('slug') or r.get('name'))]


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument('--all', action='store_true',
                    help='включи и светиите, които ВЕЧЕ имат житие')
    args = ap.parse_args()

    index = json.loads((WORK / 'index.json').read_text(encoding='utf-8'))
    manual = load_manual()

    con = sqlite3.connect(CALENDAR_DB)
    con.execute(f'ATTACH "{LIVES_DB}" AS lives')
    # ⚠ И БЕЗ СЛЪГ. Точно те са най-нуждаещите се: светия без слъг няма как
    # да покаже четиво, дори да го внесем — вижда се в календара, но не се
    # отваря (същият капан като при `07_slugs.py` в tools/lives_bg). Слъгът
    # им се дава при внасянето.
    # ⚠ ДВА СПИСЪКА, не един.
    #
    # Автоматичната засечка гледа само българските — инак „Св. Григорий, еп.
    # Български" се лепва за първия срещнат Григорий измежду хилядите.
    # РЪЧНАТА обаче трябва да достига всеки: част от българските светии
    # стоят в календара с група ECUMENICAL (Ангел Лерински, Теофил
    # Мироточиви, Софроний Български) и филтърът ги скриваше.
    all_saints = con.execute("""
        SELECT DISTINCT s.name, COALESCE(s.slug, ''), COALESCE(LENGTH(l.life), 0),
               s.group_code
        FROM saints s LEFT JOIN lives.texts l ON l.slug = s.slug
    """).fetchall()
    saints = [(n, sl, ln) for n, sl, ln, gc in all_saints if gc == 'BG']

    plan, skipped, unmatched = [], [], []
    noslug = 0
    used_urls = set()

    # 1) ръчните — те печелят
    by_slug = {sl: (n, ln) for n, sl, ln, _ in all_saints if sl}
    by_name = {n: (sl, ln) for n, sl, ln, _ in all_saints}
    for row in manual:
        url = row['url'].strip()
        slug = (row.get('slug') or '').strip()
        name = (row.get('name') or '').strip()
        if slug and slug in by_slug:
            name, ln = by_slug[slug]
        elif name and name in by_name:
            slug, ln = by_name[name]
        else:
            print(f'  ⚠ ръчна карта сочи непознат светия: {slug or name}')
            continue
        used_urls.add(url)
        # ⚠ И ръчната връзка зачита „вече има житие". Тя казва КОЙ с кого се
        # свързва, не че четивото трябва да се тегли пак — част от редовете
        # са там тъкмо за да отменят грешна автоматична засечка.
        if ln >= SHORT and not args.all:
            skipped.append((index.get(url, ''), name, ln))
            continue
        if not slug:
            noslug += 1
        plan.append({'slug': slug, 'name': name, 'url': url,
                     'title': index.get(url, '(ръчно)'), 'have': ln,
                     'how': 'manual'})

    # 2) по прилика на името
    for url, title in index.items():
        if url in used_urls:
            continue
        best, score = None, 0.0
        for name, slug, ln in saints:
            s = similarity(title, name)
            if s > score:
                score, best = s, (name, slug, ln)
        if not best or score < MIN_SCORE:
            unmatched.append((title, best[0] if best else None, score))
            continue
        name, slug, ln = best
        if any(p['slug'] == slug for p in plan):
            continue
        if ln >= SHORT and not args.all:
            skipped.append((title, name, ln))
            continue
        if not slug:
            noslug += 1
        plan.append({'slug': slug, 'name': name, 'url': url, 'title': title,
                     'have': ln, 'how': f'name {score:.2f}'})

    WORK.mkdir(exist_ok=True)
    (WORK / 'plan.json').write_text(
        json.dumps(plan, ensure_ascii=False, indent=1), encoding='utf-8')

    print(f'ЗА СВАЛЯНЕ ({len(plan)}):')
    for p in sorted(plan, key=lambda x: x['name']):
        mark = 'няма' if p['have'] == 0 else f'{p["have"]} зн.'
        print(f'  {p["name"][:44]:46} [{mark:>9}]  {p["how"]}')
    print(f'\n  от тях БЕЗ слъг (искат и слъг): {noslug}')
    print(f'вече имат житие: {len(skipped)}')
    print(f'без съответствие в календара: {len(unmatched)}')
    for t, b, s in unmatched:
        print(f'  {t[:56]:58} най-близко: {(b or "—")[:34]} [{s:.0%}]')
    print('\n→ work/plan.json')


if __name__ == '__main__':
    main()
