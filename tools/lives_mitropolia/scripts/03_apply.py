#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Тегли статиите по плана, разчита ги и ги внася в `lives.db`.

Вход:  `work/plan.json` (от 02_match.py)
Изход: `assets/db/lives.db` + резервно копие в `backups/`

⚠ ИДЕМПОТЕНТЕН, по образеца на `tools/lives_bg/06_apply.py`: какво е имало
ПРЕДИ нас се пази в `work/originals.json` и всяко следващо пускане строи от
запомненото, а не от собствения си изход. Без това повторното пускане лепи
житието втори път под първото.

⚠ Слъгът се вписва И В СЕМЕТО (`tools/calendar_gen/input/db/calendar_old.db`),
не само в assets — инак се губи при следващото `merge_years.py`. Същият
капан като при `07_slugs.py` в tools/lives_bg.
"""

from __future__ import annotations

import argparse
import html
import json
import re
import shutil
import sqlite3
import unicodedata
from datetime import datetime

from common import CACHE, LIVES_DB, ROOT, SEED_DB, WORK, fetch

RE_DROP = re.compile(r'<(script|style|noscript)\b.*?</\1>', re.S | re.I)
RE_PARA = re.compile(r'<p\b[^>]*>(.*?)</p>', re.S | re.I)
RE_TAG = re.compile(r'<[^>]+>')

# ⚠ Отсяване на обзавеждането. Страницата носи меню, футър, „Сподели",
# бутони за бисквитки — всичко като `<p>`. Същинският текст е дълъг; освен
# това тези редове са познати и се махат поименно.
MIN_PARA = 60
NOISE = (
    'Сподели', 'Прочети още', 'Абонирай', 'бисквитк', 'cookie',
    'Всички права', 'Софийска света митрополия ©', 'Виж още',
    'Публикувано на', 'Категория', 'Тагове',
    # ⚠ Опашката, която сайтът слага под всяко житие. Тя говори за самия
    # сайт и за картата към статията, не за светията — в четивото няма
    # какво да прави.
    'в Именника на българските светии', 'на картата по-долу',
    'Хронология на богослуженията', 'Официалният сайт на Софийска епархия',
)

# ⚠ Мярката е ОБЩАТА ДЪЛЖИНА, не броят абзаци. Част от статиите носят цялото
# житие в ЕДИН абзац (св. Игнатий Старозагорски — 2961 знака наведнъж) и
# праг „поне три абзаца" ги отхвърляше като празни.
MIN_TOTAL = 400

HEADING = 'Житие'
SOURCE_NOTE = 'Софийска света митрополия'


def parse_article(raw: str) -> tuple[str, list[str]]:
    """Заглавието и абзаците на статията."""
    t = RE_DROP.sub(' ', raw)
    m = re.search(r'<title>(.*?)</title>', t, re.S | re.I)
    title = html.unescape(re.sub(r'\s+', ' ', m.group(1))).strip() if m else ''
    title = re.sub(r'\s*[-–]\s*Софийска света митрополия\s*$', '', title)
    title = re.sub(r'\s*[–-]\s*(житие|сведения)\s+и\s+карта\s*$', '', title,
                   flags=re.I).strip()

    paras = []
    for p in RE_PARA.findall(t):
        txt = html.unescape(RE_TAG.sub('', p))
        txt = unicodedata.normalize('NFC', re.sub(r'\s+', ' ', txt)).strip()
        if len(txt) < MIN_PARA:
            continue
        if any(n.lower() in txt.lower() for n in NOISE):
            continue
        if txt in paras:            # менюта се повтарят по няколко пъти
            continue
        paras.append(txt)
    return title, paras


def build_html(title: str, paras: list[str], url: str) -> str:
    """Сглобява четивото — същата подредба като в tools/lives_bg."""
    out = [f'<h3>{html.escape(title)}</h3>']
    for p in paras:
        out.append(f'<p>{html.escape(p)}</p>')
    return '\n'.join(out)


def load_originals() -> dict:
    f = WORK / 'originals.json'
    return json.loads(f.read_text(encoding='utf-8')) if f.exists() else {}


def make_slug(name: str, taken: set[str]) -> str:
    """Слъг от името — по формата на съществуващите (`sv-ime-prozvishte`)."""
    table = str.maketrans({
        'а': 'a', 'б': 'b', 'в': 'v', 'г': 'g', 'д': 'd', 'е': 'e', 'ж': 'zh',
        'з': 'z', 'и': 'i', 'й': 'j', 'к': 'k', 'л': 'l', 'м': 'm', 'н': 'n',
        'о': 'o', 'п': 'p', 'р': 'r', 'с': 's', 'т': 't', 'у': 'u', 'ф': 'f',
        'х': 'h', 'ц': 'c', 'ч': 'ch', 'ш': 'sh', 'щ': 'sht', 'ъ': 'a',
        'ь': '', 'ю': 'ju', 'я': 'ja', 'ѝ': 'i',
    })
    s = name.lower()
    s = re.sub(r'\(.*?\)|†.*$', ' ', s)
    # титлите отпадат — те не отличават светията
    s = re.sub(r'\b(св|свв|свт|прп|прпмч|прпмчч|мч|мчч|мц|вмч|вмчц|свщмч|'
               r'блгв|блж|ап|равноап|еп|архиеп|митр|патр)\.?\b', ' ', s)
    # ⚠ САМО ПЪРВИТЕ ТРИ значещи думи. Календарните имена понякога са цели
    # изречения („…и двамата му ученици: йеродякон Иаков и монах Дионисий",
    # „…брат на цар Самуил") и слъгът излизаше 60 знака — нечетим и
    # неудобен за ръчно вписване в семето.
    def words(text: str) -> list[str]:
        x = re.sub(r'[^a-z0-9]+', '-', text.translate(table)).strip('-')
        return [w for w in x.split('-') if w and w not in
                ('i', 'v', 'na', 'car', 'brat', 'knjaz', 'ep', 'e', 'mu')]

    # ⚠ Рязането при запетаята важи САМО ако пред нея остава истинско име.
    # „Свт. Григорий, еп. Мизийски" и „Св. Давид, цар Български" губеха
    # точно отличаващата си дума и слъгът излизаше `sv-grigorij` — под него
    # в календара стоят десетина различни светии.
    parts = words(re.split(r'[:,;]', s)[0])
    if len(parts) < 2:
        parts = words(s)
    s = '-'.join(parts[:3])
    base = f'sv-{s}'[:44].rstrip('-')
    slug, n = base, 1
    while slug in taken:
        n += 1
        slug = f'{base}-{n}'
    return slug


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument('--dry-run', action='store_true')
    ap.add_argument('--only', help='само този слъг или част от името')
    args = ap.parse_args()

    plan = json.loads((WORK / 'plan.json').read_text(encoding='utf-8'))
    if args.only:
        plan = [p for p in plan
                if args.only.lower() in (p['slug'] + p['name']).lower()]
    if not plan:
        raise SystemExit('няма какво да се внася — пусни 02_match.py')

    con = sqlite3.connect(LIVES_DB)
    taken = {r[0] for r in con.execute('SELECT slug FROM texts')}
    taken |= {r[0] for r in con.execute('SELECT DISTINCT slug FROM hymns')}

    originals = load_originals()
    records = []
    for p in plan:
        # ── 1. страницата ──
        name = re.sub(r'[^0-9a-zA-Zа-яА-Я]+', '_', p['name'])[:48]
        dest = CACHE / 'art' / f'{name}.html'
        try:
            fetch(p['url'], dest)
        except Exception as e:                       # noqa: BLE001
            print(f'  ⚠ {p["name"][:40]}: {e}')
            continue
        title, paras = parse_article(dest.read_text(encoding='utf-8',
                                                    errors='ignore'))
        total = sum(len(x) for x in paras)
        if total < MIN_TOTAL:
            print(f'  ⚠ {p["name"][:40]}: само {total} знака — пропуснат')
            continue

        # ── 2. слъг ──
        slug = p['slug']
        if not slug:
            slug = make_slug(p['name'], taken)
            taken.add(slug)
            p['generated_slug'] = slug

        life_new = build_html(title, paras, p['url'])
        records.append((p, slug, title, life_new, sum(len(x) for x in paras)))
        print(f'  {p["name"][:42]:44} {len(paras):>2} абз., '
              f'{sum(len(x) for x in paras):>6} зн.'
              f'{"  НОВ СЛЪГ: " + slug if not p["slug"] else ""}')

    if args.dry_run:
        print('\n--dry-run: НИЩО не е записано')
        return
    if not records:
        raise SystemExit('нищо за внасяне')

    # ── 3. запис ──
    backups = ROOT / 'backups'
    backups.mkdir(exist_ok=True)
    stamp = datetime.now().strftime('%Y%m%d_%H%M%S')
    shutil.copy2(LIVES_DB, backups / f'lives.db.{stamp}')
    print(f'\nрезервно копие: backups/lives.db.{stamp}')

    seed = sqlite3.connect(SEED_DB)
    for p, slug, title, life_new, _ in records:
        row = con.execute('SELECT life, source FROM texts WHERE slug=?',
                          (slug,)).fetchone()
        key = p['url']
        if key in originals:
            old_life, old_src = originals[key]['life'], originals[key]['source']
        else:
            old_life = row[0] if row else None
            old_src = row[1] if row else None
            originals[key] = {'slug': slug, 'life': old_life, 'source': old_src}

        # старото четиво + новото под него, с разделящо заглавие
        if old_life and RE_TAG.sub('', old_life).strip():
            life = f'{old_life.rstrip()}\n<h3>Допълнение</h3>\n' + \
                   re.sub(r'^\s*<h3>.*?</h3>\s*', '', life_new, count=1, flags=re.S)
        else:
            life = life_new

        srcs = [u.strip() for u in (old_src or '').split('\n') if u.strip()]
        if p['url'] not in srcs:
            srcs.append(p['url'])
        source = '\n'.join(srcs)

        if row:
            con.execute('UPDATE texts SET life=?, source=? WHERE slug=?',
                        (life, source, slug))
        else:
            con.execute('INSERT INTO texts (slug, name, life, source)'
                        ' VALUES (?,?,?,?)', (slug, p['name'], life, source))
        # ⚠ Слъгът — И В СЕМЕТО, инак се губи при merge_years.py.
        if not p['slug']:
            seed.execute("UPDATE saints SET slug=? WHERE name=? AND slug IS NULL",
                         (slug, p['name']))
    con.commit()
    seed.commit()
    (WORK / 'originals.json').write_text(
        json.dumps(originals, ensure_ascii=False, indent=1), encoding='utf-8')

    print(f'записани: {len(records)} жития')
    news = [p for p, *_ in records if not p['slug']]
    if news:
        print('\n⚠ СЛЕДВА прегенериране — нови слъгове са вписани в семето:')
        print('    cd tools/calendar_gen && rm -f out/*.db')
        print('    python3 merge_years.py --years 2025 2026 2027 --style old')
        print('    python3 merge_years.py --years 2025 2026 2027 --style new')
        print('    cp out/calendar_old_2025-2027.db ../../assets/db/calendar_old.db')
        print('    cp out/calendar_new_2025-2027.db ../../assets/db/calendar_new.db')


if __name__ == '__main__':
    main()
