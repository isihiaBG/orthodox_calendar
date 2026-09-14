#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""06_hymns.py — тропарите и кондаците от томовете по свт. Димитрий Ростовски
влизат в таблицата `lives.hymns`, за да се появят в разгъващата се секция на
дневния изглед.

ЗАЩО. 1121 слъга имат четиво по Димитрий, но 697 от тях нямат нито едно
песнопение в базата — тропарът стоеше само вътре в житието, недостижим от
дневния изглед. В томовете обаче той е СТРУКТУРНО обозначен (`data-prayer`),
тъй че не се налага да се гадае по текста.

⚠ ПИПАТ СЕ САМО ПРАЗНИТЕ СЛЪГОВЕ. Слъг, който вече има песнопения от
azbyka.ru, НЕ се докосва — те носят истински църковнославянски оригинал плюс
превод и са по-пълни, а добавянето отгоре би дало ДУБЛИРАНЕ в секцията
(изрично искане на потребителя, 06.09.2026).

⚠ ИДЕМПОТЕНТЕН. Нашите редове се разпознават по [OUR_NOTE] и се трият в
началото на всяко пускане. Оттам „празен слъг" се мери СЛЕД триенето, тъй че
повторно пускане не удвоява нищо — капанът, платен три пъти в конвейерите за
жития (виж CLAUDE.md, „Идемпотентност на конвейерите").

ВХОД   assets/books/*.epub  +  assets/lives_index.json  +  lives.saint_dmitry_refs
ИЗХОД  assets/db/lives.db, таблица hymns

    python3 06_hymns.py --dry-run     # какво би влязло
    python3 06_hymns.py               # нанася (прави резервно копие)
"""

import argparse
import json
import re
import shutil
import sqlite3
import sys
import time
import zipfile
from collections import defaultdict
from html import unescape
from pathlib import Path

КОРЕН = Path(__file__).resolve().parents[3]
БАЗА = КОРЕН / 'assets' / 'db' / 'lives.db'
УКАЗАТЕЛ = КОРЕН / 'assets' / 'lives_index.json'
ТОМОВЕ = КОРЕН / 'assets' / 'books'
БЕКЪПИ = Path(__file__).resolve().parents[1] / 'backups'

# Признакът, по който познаваме СВОИТЕ редове. Чуждите (от azbyka.ru) не бива
# да се трият при повторно пускане — те са по-пълни и не са наша работа.
OUR_NOTE = 'от житието по свт. Димитрий Ростовски'

# Блокът с молитва, както го слага 04_build_epub.py: три поредни div-а с
# data-prayer="head" / "csl" / "trans". Виж CLAUDE.md, „Тропарите и кондаците
# накрая на житието".
RE_БЛОК = re.compile(
    r'<div class="paragraph" data-prayer="(head|csl|trans)"[^>]*>(.*?)</div>',
    re.S)

# ⚠ Бележката под линия се маха КАТО ЕЛЕМЕНТ, не като цифри — инак номерът
# остава гол текст насред тропара. Същото правило като в build_lives_index.py.
RE_БЕЛЕЖКА = re.compile(r'<a[^>]*href="[^"]*note\d+[^"]*"[^>]*>.*?</a>', re.S)
RE_ЕТИКЕТ = re.compile(r'<span class="translabel">.*?</span>', re.S)
RE_ТАГ = re.compile(r'<[^>]+>')

# „Тропар, глас 4" → („Тропар", „глас 4"). ⚠ Реже се само по „, глас", не по
# коя да е запетая: „Тропар на св. Йоан, еп. Суздалски" няма глас изобщо.
RE_ГЛАС = re.compile(r'^(.*?),\s*(глас\s+.+)$')

ВИДОВЕ = (
    ('тропар', 'tropar'),
    ('кондак', 'kondak'),
    ('молитва', 'molitva'),
    ('величание', 'velichanie'),
)


def почисти(html: str) -> str:
    """HTML на един блок → гол текст, годен за колоните csl/bg."""
    т = RE_БЕЛЕЖКА.sub('', html)
    т = RE_ЕТИКЕТ.sub('', т)          # „Превод:" — четецът си го слага сам
    т = RE_ТАГ.sub('', т)
    т = unescape(т)
    т = т.replace(' ', ' ')
    return re.sub(r'\s+', ' ', т).strip()


def вид_на(заглавие: str) -> str:
    н = заглавие.lower()
    for дума, код in ВИДОВЕ:
        if дума in н:
            return код
    return 'other'


def разцепи_заглавие(заглавие: str):
    """„Друг кондак, глас 4" → („Друг кондак", „глас 4")."""
    м = RE_ГЛАС.match(заглавие)
    return (м.group(1).strip(), м.group(2).strip()) if м else (заглавие, '')


def сгъни(т: str) -> str:
    """Ключ за разпознаване на един и същ текст в две различни четива."""
    return re.sub(r'[^а-яa-z]', '', т.lower())


class Томове:
    """Отваря всеки .epub най-много веднъж."""

    def __init__(self):
        self._архиви = {}

    def глава(self, том: str, href: str) -> str:
        if том not in self._архиви:
            self._архиви[том] = zipfile.ZipFile(ТОМОВЕ / том)
        try:
            return self._архиви[том].read(href).decode('utf-8', 'replace')
        except KeyError:
            return ''


def песнопения_в(html: str):
    """Тройките head/csl/trans от една глава, по реда им в текста."""
    блокове = RE_БЛОК.findall(html)
    готови, текущо = [], None
    for вид, тяло in блокове:
        текст = почисти(тяло)
        if вид == 'head':
            if текущо:
                готови.append(текущо)
            текущо = {'head': текст, 'csl': '', 'bg': ''}
        elif текущо is not None:
            текущо['csl' if вид == 'csl' else 'bg'] = текст
    if текущо:
        готови.append(текущо)
    # Празен ред няма какво да покаже — четецът и без това го прескача.
    return [п for п in готови if п['csl'] or п['bg']]


def main():
    ап = argparse.ArgumentParser()
    ап.add_argument('--dry-run', action='store_true',
                    help='само отчет, нищо не се пише')
    ап.add_argument('--verbose', action='store_true',
                    help='изброява всяко песнопение')
    арг = ап.parse_args()

    if not БАЗА.exists():
        sys.exit(f'няма база: {БАЗА}')
    указател = json.loads(УКАЗАТЕЛ.read_text(encoding='utf-8'))
    db = sqlite3.connect(БАЗА)

    # ── 1. нашите стари редове си отиват ПЪРВИ (оттам идва идемпотентността)
    наши = db.execute('SELECT COUNT(*) FROM hymns WHERE note = ?',
                      (OUR_NOTE,)).fetchone()[0]
    if наши and not арг.dry_run:
        db.execute('DELETE FROM hymns WHERE note = ?', (OUR_NOTE,))
    print(f'наши редове от предишно пускане: {наши}'
          + ('  (в dry-run не се трият)' if наши and арг.dry_run else ''))

    # ── 2. кои слъгове са ПРАЗНИ след това
    чужди = {r[0] for r in db.execute(
        'SELECT DISTINCT slug FROM hymns WHERE note IS NULL OR note <> ?',
        (OUR_NOTE,))}

    връзки = defaultdict(list)
    for slug, num in db.execute(
            'SELECT slug, num FROM saint_dmitry_refs ORDER BY slug, num'):
        връзки[slug].append(num)

    томове = Томове()
    редове, пропуснати, слъгове = [], 0, 0

    for slug in sorted(връзки):
        if slug in чужди:
            пропуснати += 1
            continue
        намерени, видени = [], set()
        for num in връзки[slug]:
            r = указател.get(str(num))
            if not r:
                continue
            for п in песнопения_в(томове.глава(r['book'], r['href'])):
                ключ = сгъни(п['csl'] or п['bg'])
                if ключ in видени:       # същият тропар в две четива на един слъг
                    continue
                видени.add(ключ)
                намерени.append(п)
        if not намерени:
            continue
        слъгове += 1
        брояч = defaultdict(int)
        for ord_, п in enumerate(намерени, start=1):
            kind = вид_на(п['head'])
            брояч[kind] += 1
            kind_ru, glas = разцепи_заглавие(п['head'])
            редове.append((slug, ord_, kind, kind_ru, брояч[kind],
                           glas, п['csl'], п['bg'], OUR_NOTE))
            if арг.verbose:
                print(f'  {slug:<44} {ord_}. {kind_ru}'
                      + (f', {glas}' if glas else ''))

    # ── 3. отчет
    print(f'слъга с чужди песнопения (не се пипат): {пропуснати}')
    print(f'слъга, които получават песнопения:      {слъгове}')
    print(f'песнопения общо:                        {len(редове)}')
    по_вид = defaultdict(int)
    for r in редове:
        по_вид[r[2]] += 1
    print('  по вид: ' + ', '.join(f'{k}={v}' for k, v in sorted(по_вид.items())))

    if арг.dry_run:
        print('\n--dry-run: нищо не е записано')
        return

    # ── 4. запис, с резервно копие
    # ⚠ Копието НЕ ляга до самата база: `pubspec.yaml` включва ЦЯЛАТА папка
    # `assets/db/`, тъй че всеки `lives.db.bak-…` пътува в APK-то (веднъж така
    # заминаха 15,8 MB от 74-те). Стои настрани, в папката на конвейера.
    БЕКЪПИ.mkdir(parents=True, exist_ok=True)
    копие = БЕКЪПИ / f'lives.db.bak-{time.strftime("%Y%m%d_%H%M%S")}'
    shutil.copy2(БАЗА, копие)
    print(f'\nрезервно копие: {копие}')
    db.executemany(
        'INSERT INTO hymns (slug, ord, kind, kind_ru, seq, glas, csl, bg, note)'
        ' VALUES (?,?,?,?,?,?,?,?,?)', редове)
    db.commit()
    общо = db.execute('SELECT COUNT(*) FROM hymns').fetchone()[0]
    свои = db.execute('SELECT COUNT(*) FROM hymns WHERE note = ?',
                      (OUR_NOTE,)).fetchone()[0]
    print(f'записано. hymns вече има {общо} реда, от които наши {свои}.')


if __name__ == '__main__':
    main()
