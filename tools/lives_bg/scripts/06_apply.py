#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Внася разчетените жития в `assets/db/lives.db`.

⚠ ЕДИНСТВЕНИЯТ скрипт, който пише в базата. Пуска се СЛЕД `--dry-run`.

## Трите решения, взети от потребителя (30.08.2026)

1. **Слъгове се генерират** за светиите, които нямат — по същата
   транслитерация, с която са правени вече съществуващите.
2. **Новият текст се ДОБАВЯ ПОД стария**, а не го подменя, с надлежно
   заглавие помежду им. Старият идва от друг извор и си остава.
3. **Песнопенията остават под четивото И влизат в `hymns`** — за да има
   отделна връзка под името на светията (тропар / кондак / молитва /
   величание).

## Атрибуцията

⚠ И ДВАТА източника се посочват, всеки с връзка към КОНКРЕТНОТО четиво, а не
общо към сайта. Пазят се в `texts.source`, разделени с НОВ РЕД; четецът ги
разчита в `_sourceHtml()` (reader_screen.dart) и ги изписва накрая на
четивото. Един ред = един източник, тъй че досегашните 1033 записа минават
оттам непроменени.
"""

from __future__ import annotations

import argparse
import glob
import json
import re
import shutil
import sqlite3
from datetime import datetime

from common import INPUT, LIVES_DB, TOOL, WORK, transliterate

RE_TAG = re.compile(r'<[^>]+>')

# Заглавието, което отделя новия текст от стария. ⚠ `<h3>` е единственото
# заглавно ниво със стил в четеца (виж reader_styles.dart).
#
# ⚠ Само „Допълнение", БЕЗ името на източника (31.08.2026). Дотук пишеше
# „Жития от Православието.com" — смесицата от кирилица и латиница в едно
# заглавие стои неестетично, а източникът и без това е посочен най-отдолу
# под четивото, с връзка към конкретната страница.
#
# ⚠ Слага се САМО когато отгоре има стар текст. Житие изцяло от този извор
# си запазва собственото заглавие от сайта — виж [compose_life].
NEW_PART_HEADING = 'Допълнение'


# Думи, които НЕ са част от името и нямат работа в слъга: титли, санове,
# епитети. ⚠ Без това излизаха „sv-evtimij-**patriarh**-trnovski" редом с
# „sv-ioakim-**patr**-trnovski" — един и същи сан, изписан веднъж пълно и
# веднъж съкратено, тъй че двата слъга не изглеждат като направени по едно
# правило.
SLUG_DROP = {
    'sv', 'sveti', 'svv', 'patr', 'patriarh', 'arhiep', 'arhiepiskop',
    'ep', 'episkop', 'mitr', 'mitropolit', 'prezv', 'prezviter', 'igumen',
    'chudotvorec', 'chudotvorka', 'car', 'knjaz', 'kn',
    'prepmchch', 'prpmch', 'mchch', 'postradali', 'ot', 'latinite', 'uniati',
    'i', 'na', 'v', 's',
}

# ⚠ „Български" НЕ Е в списъка по-горе, макар да изглежда като излишен епитет.
# При тези светии то често е ЕДИНСТВЕНОТО отличаващо прозвище: махнато,
# „Йоан Български" дава `sv-joan`, а „Лазар Български" — `sv-lazar`. Първото е
# толкова общо, че рано или късно ще се сблъска с друг Йоан, а слъгът е
# ключът, по който житието стига до календара — сблъсък там показва чуждо
# четиво. Хванато при пробно пускане на 30.08.2026, преди запис в семето.


def make_slug(name_core: str, taken: set[str]) -> str:
    """Слъг по конвенцията на проекта: `sv-ime-prozvishte`.

    ⚠ Проверява се срещу ВСИЧКИ вече заети слъгове (в трите таблици), защото
    сблъсък би слял двама светии мълчаливо — единият би показал четивото на
    другия.
    """
    base = transliterate(name_core)
    base = re.sub(r'[^a-z0-9]+', '-', base).strip('-')
    words = [w for w in base.split('-') if w and w not in SLUG_DROP]
    # ⚠ Ако изчистването не остави нищо (име само от титли), се пада обратно
    # на пълното — по-добре грозен слъг, отколкото празен.
    base = '-'.join(words) if words else re.sub(r'-{2,}', '-', base)
    slug = f'sv-{base}'[:120]

    if slug not in taken:
        return slug
    for n in range(2, 40):
        cand = f'{slug}-{n}'
        if cand not in taken:
            return cand
    raise RuntimeError(f'не мога да намеря свободен слъг за „{name_core}"')


def load_slug_map() -> dict[str, str]:
    """Ръчните пренасочвания от `input/slug_map.csv` (колони: key,slug,note).

    ⚠ Файлът е ЕДИНСТВЕНОТО място, където се решава „този светия вече има
    запис в базата под друго име". Автоматично това не се хваща надеждно:
    „Климент, архиеп. Охридски чудотворец" и
    `sv-kliment-ohridskij-velichskij-bolgarskij` са един и същ човек, но
    прозвищата са три и се разминават.
    """
    import csv
    path = INPUT / 'slug_map.csv'
    if not path.exists():
        return {}
    with path.open(encoding='utf-8') as fh:
        return {r['key'].strip(): r['slug'].strip()
                for r in csv.DictReader(fh)
                if r.get('key') and r.get('slug')}


def compose_life(old: str | None, new: str, name: str) -> str:
    """Старото четиво + новото под него, с разделящо заглавие.

    ⚠ Заглавие се слага САМО ако горе наистина има стар текст. Иначе новото
    четиво би започвало с надпис „Жития от…", което на празно място е
    безсмислено.
    """
    new = new.strip()
    if not old or not RE_TAG.sub('', old).strip():
        return new

    # ⚠ Заглавието от сайта отпада, когато текстът се долепя ПОД стар.
    # Инак излизат две заглавия едно под друго — разделящото („Жития от
    # Православието.com") и веднага под него името на светията, което вече
    # стои и по-горе. Годините и въвеждащият ред ОСТАВАТ: те са сведения,
    # а не повторен надпис.
    new = re.sub(r'^\s*<h3>.*?</h3>\s*', '', new, count=1, flags=re.S)
    return f'{old.rstrip()}\n<h3>{NEW_PART_HEADING}</h3>\n{new}'


# ⚠ ОРИГИНАЛИТЕ — единственото, което прави пускането ИДЕМПОТЕНТНО.
#
# Без този файл повторното пускане чупи базата на ДВА независими начина, а и
# двата минават тихо (открити на 31.08.2026, второто — само защото
# потребителят видя удвоеното житие на св. Кирил):
#
#   1. `compose_life` лепи новото четиво под старото. Втори път лепи ПАК — а
#      базата вече носи първото добавяне, тъй че житието излиза с две заглавия
#      „Допълнение" и двоен текст с двойни картинки.
#   2. `make_slug` вижда СОБСТВЕНИЯ си слъг от предишното пускане като зает и
#      прави нов с наставка: `sv-onufrij-gabrovski-2`. Появява се втори,
#      дублиращ запис — с ново четиво и нови песнопения, но недостижим, защото
#      календарът сочи първия.
#
# Затова при първото пускане тук се запомня какво е имало ПРЕДИ нас И кой слъг
# е получил всеки светия; всяко следващо пускане строи от ЗАПОМНЕНОТО, а не от
# заварената стойност в базата.
#
# ⚠ Ключът е `key` на светията (стабилен през пусканията), а НЕ слъгът — той е
# тъкмо това, което трябва да се запомни.
#
# ⚠ Файлът живее в `work/`, а НЕ в самата база: таблица с оригиналите щеше да
# пътува в APK-то, а тя е нужна само на конвейера.
ORIGINALS = WORK / 'originals.json'


def load_originals() -> dict[str, dict]:
    if ORIGINALS.exists():
        return json.loads(ORIGINALS.read_text(encoding='utf-8'))
    return {}


def save_originals(data: dict[str, dict]) -> None:
    ORIGINALS.write_text(json.dumps(data, ensure_ascii=False, indent=2),
                         encoding='utf-8')


def compose_source(old: str | None, new_url: str) -> str:
    """Двата източника, по един на ред, без повторения."""
    urls = []
    for u in (old or '').split('\n'):
        u = u.strip()
        if u and u not in urls:
            urls.append(u)
    if new_url not in urls:
        urls.append(new_url)
    return '\n'.join(urls)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument('--dry-run', action='store_true',
                    help='показва какво би станало, без да пише')
    ap.add_argument('--only', help='само този светия (част от името)')
    args = ap.parse_args()

    records = [json.loads(open(f, encoding='utf-8').read())
               for f in sorted(glob.glob(str(WORK / 'parsed' / '*.json')))]
    if args.only:
        records = [r for r in records
                   if args.only.lower() in r['name_core'].lower()]
    if not records:
        raise SystemExit('няма какво да се внася — пусни 05_parse.py')

    con = sqlite3.connect(LIVES_DB)
    con.row_factory = sqlite3.Row

    # Всички заети слъгове — от трите таблици наведнъж.
    taken = {r[0] for r in con.execute('SELECT slug FROM texts')}
    taken |= {r[0] for r in con.execute('SELECT DISTINCT slug FROM hymns')}
    taken |= {r[0] for r in con.execute(
        'SELECT DISTINCT slug FROM saint_dmitry_refs')}

    # ⚠ Ръчните пренасочвания. Тук се вписва светия, който в календара няма
    # слъг, но в `lives.db` ВЕЧЕ има запис под друго изписване на името.
    # Генериран слъг за него би раздвоил четивата му мълчаливо — същият
    # случай като Евфросиния Суздалска (виж CLAUDE.md).
    slug_map = load_slug_map()
    originals = load_originals()
    orphan_appends: list[str] = []

    # Слъговете, раздадени при предишно пускане, са ЗАЕТИ за всеки друг —
    # инак генераторът би могъл да върне един и същ на двама.
    taken |= {v['slug'] for v in originals.values() if v.get('slug')}

    plan = []
    for r in records:
        remembered = originals.get(r['key'])

        slug = r['slug']
        generated = False
        if not slug:
            # ⚠ Слъгът, раздаден миналия път, се ПРЕИЗПОЛЗВА. Генериран
            # наново, той щеше да излезе с наставка `-2` (виж бележката при
            # [ORIGINALS]) и да създаде втори, недостижим запис.
            if remembered and remembered.get('slug'):
                slug = remembered['slug']
                generated = remembered.get('generated', False)
            else:
                slug = slug_map.get(r['key'])
                if not slug:
                    slug = make_slug(r['name_core'], taken)
                    taken.add(slug)
                    generated = True

        row = con.execute(
            'SELECT life, source, name FROM texts WHERE slug=?', (slug,)
        ).fetchone()

        old_life = row['life'] if row else None
        old_source = row['source'] if row else None

        # ⚠ Заварената стойност е меродавна САМО първия път. После оригиналът
        # идва от [ORIGINALS] — инак второто пускане строи върху собствения си
        # изход и житието се удвоява.
        if remembered:
            old_life = remembered['life']
            old_source = remembered['source']
        else:
            if old_life and f'<h3>{NEW_PART_HEADING}</h3>' in old_life:
                # Базата вече носи наше добавяне, а оригиналът не се знае —
                # тук няма как да се отдели наизуст кое е било преди нас.
                orphan_appends.append(slug)
            originals[r['key']] = {'slug': slug, 'generated': generated,
                                   'life': old_life, 'source': old_source}

        life = compose_life(old_life, r['life_html'], r['name_core'])
        source = compose_source(old_source, r['source_url'])

        plan.append({
            'slug': slug, 'generated_slug': generated, 'exists': bool(row),
            'name': r['name_core'],
            'old_chars': len(RE_TAG.sub('', old_life or '')),
            'new_chars': len(RE_TAG.sub('', life)),
            'life': life, 'source': source,
            'hymns': r['hymns'],
            'church_date': r['church_date'],
        })

    # ── Дедупликация по слъг ──────────────────────────────────────────────
    #
    # ⚠ БЕЗ ТОВА текстът се залепва по няколко пъти под един запис. Няколко
    # реда в календара сочат ЕДИН светия — той има по няколко памети през
    # годината, а слъгът е общ (точно затова е ключът, виж CLAUDE.md):
    #
    #   sv-kirill-konstantin-filosof            ← 3 реда (Кирил)
    #   sv-ioann-rylskij                        ← 2 реда (Успение + Пренасяне)
    #   sv-kliment-ohridskij-velichskij-…       ← 2 реда (Успение + Седмочисл.)
    #
    # Оставя се НАЙ-БОГАТИЯТ запис за всеки слъг. Ако отпадналият идва от
    # ДРУГА страница, той носи различно четиво и се изписва в отчета — там
    # решението е ръчно, а не на скрипта.
    # ⚠ „НАЙ-БОГАТ" СЕ МЕРИ С ТРИ ЧИСЛА, не само с дължината на текста.
    #
    # Две страници могат да дадат ТОЧНО еднакъв текст и да се различават
    # само по това, че едната носи илюстрациите. Точно това стана с житието
    # на св. Кирил Философ (01.09.2026): два реда в календара сочат същия
    # слъг, и двата разчетени на 70 827 плоски знака — но единият с 7
    # картинки, другият без. При сравнение само по знаци побеждаваше онзи,
    # който случайно е пръв по азбучен ред на файловете, и картинките
    # изчезваха МЪЛЧАЛИВО от готовата база.
    def richness(p: dict) -> tuple[int, int, int]:
        return (p['new_chars'], p['life'].count('<img'), len(p['hymns']))

    best: dict[str, dict] = {}
    dropped: list[tuple[dict, dict]] = []
    for p in plan:
        cur = best.get(p['slug'])
        if cur is None:
            best[p['slug']] = p
        elif richness(p) > richness(cur):
            best[p['slug']] = p
            dropped.append((p, cur))
        else:
            dropped.append((cur, p))

    other_page = [(kept, drop) for kept, drop in dropped
                  if kept['source'] != drop['source']]
    plan = sorted(best.values(), key=lambda p: p['name'])

    if dropped:
        print(f'⚠ отпаднали като повторение: {len(dropped)}'
              f'  (същият слъг, вече внесен)')
        for kept, drop in dropped:
            same = 'същата страница' if kept['source'] == drop['source'] \
                else '⚠ ДРУГА страница — виж по-долу'
            print(f'    {drop["name"][:44]:46} → {kept["slug"][:34]}  ({same})')
    if other_page:
        print('\n⚠ ТЕЗИ носят РАЗЛИЧНО четиво под същия слъг и са пропуснати.')
        print('  Ако четивото им трябва, слей го на ръка:')
        for kept, drop in other_page:
            print(f'    {drop["name"][:40]:42} {drop["source"].splitlines()[-1]}')
        print()

    # ── Отчет ─────────────────────────────────────────────────────────────
    print(f'{"светия":34} {"слъг":6} {"беше":>8} {"става":>9}  песноп.')
    print('-' * 74)
    for p in plan[:14]:
        mark = 'НОВ' if p['generated_slug'] else '—'
        print(f'{p["name"][:33]:34} {mark:6} {p["old_chars"]:>8,} '
              f'{p["new_chars"]:>9,}  {len(p["hymns"])}')
    if len(plan) > 14:
        print(f'… и още {len(plan) - 14}')

    new_slugs = sum(1 for p in plan if p['generated_slug'])
    appended = sum(1 for p in plan if p['old_chars'] > 0)
    hymns_total = sum(len(p['hymns']) for p in plan)
    print(f'\nзаписи:            {len(plan)}')
    print(f'  нови слъгове:    {new_slugs}')
    print(f'  добавени под стар текст: {appended}')
    print(f'  песнопения:      {hymns_total}')

    # ⚠ СПИРАЧКА. Базата носи наше добавяне, но `work/originals.json` не знае
    # за него — тоест файлът е изтрит или базата идва отдругаде. Продължим ли,
    # новото четиво ще се залепи ПОД вече залепеното.
    if orphan_appends:
        print(f'\n⚠ СПРЯНО: {len(orphan_appends)} жития вече носят '
              f'„{NEW_PART_HEADING}", а оригиналът им не е запомнен:')
        for s in orphan_appends[:8]:
            print(f'    {s}')
        if len(orphan_appends) > 8:
            print(f'    … и още {len(orphan_appends) - 8}')
        print('\n  Върни чисто копие и пусни наново:')
        print(f'    cp {TOOL / "backups"}/lives.db.<най-старото> '
              f'{LIVES_DB}')
        raise SystemExit(1)

    if args.dry_run:
        print('\n--dry-run: НИЩО не е записано')
        return

    # ── Запис ─────────────────────────────────────────────────────────────
    # ⚠ Резервното копие е в ОТДЕЛНА папка, а не до самата база: копие с име
    # `lives.db.bak-…` вътре в assets/db/ влиза в APK-то (веднъж така пътуваха
    # 15,8 MB от 74-те — виж CLAUDE.md).
    backup_dir = TOOL / 'backups'
    backup_dir.mkdir(exist_ok=True)
    stamp = datetime.now().strftime('%Y%m%d_%H%M%S')
    backup = backup_dir / f'lives.db.{stamp}'
    shutil.copy2(LIVES_DB, backup)
    print(f'\nрезервно копие: {backup.relative_to(TOOL.parents[1])}')
    # ⚠ Записва се ПРЕДИ самото писане в базата: инак прекъснато пускане
    # оставя базата пипната, а оригиналите незапомнени.
    save_originals(originals)

    written = hymns_written = 0
    for p in plan:
        if p['exists']:
            con.execute('UPDATE texts SET life=?, source=? WHERE slug=?',
                        (p['life'], p['source'], p['slug']))
        else:
            con.execute(
                'INSERT INTO texts (slug, name, life, source) VALUES (?,?,?,?)',
                (p['slug'], p['name'], p['life'], p['source']))
        written += 1

        if p['hymns']:
            # ⚠ Пише се само ако за този слъг НЯМА песнопения — инак повторно
            # пускане би удвоило вече внесените. Съществуващите (от
            # църковнославянския извор) са по-пълни и не се пипат.
            have = con.execute(
                'SELECT COUNT(*) FROM hymns WHERE slug=?', (p['slug'],)
            ).fetchone()[0]
            if have:
                continue
            for i, h in enumerate(p['hymns'], 1):
                con.execute(
                    'INSERT INTO hymns (slug, ord, kind, kind_ru, seq, glas,'
                    ' csl, bg, note) VALUES (?,?,?,?,?,?,?,?,?)',
                    (p['slug'], i, h['kind'], h['kind_ru'], h['seq'],
                     h['glas'], None, h['bg'],
                     'от pravoslavieto.com — на български, без ЦСЛ текст'))
                hymns_written += 1

    con.commit()
    con.close()
    print(f'записани: {written} жития, {hymns_written} песнопения')
    print('\n⚠ СЛЕДВА: горещото презареждане НЕ пренася промяна в assets/ —')
    print('  иска нов билд, за да стигне до устройството.')


if __name__ == '__main__':
    main()
