#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Слива еднаквите илюстрации и пренасочва четивата към една от тях.

⚠ ПОСЛЕДНА стъпка в конвейера — след `06_apply.py`. Работи ВЪРХУ БАЗАТА,
не върху `work/parsed/`, и точно затова трябва да е накрая: пусната по-рано,
следващата стъпка ще пренапише `life` от разчетеното и сливането ще се
загуби. (Бележка на потребителя, 01.09.2026.)

    python3 12_dedupe_images.py --dry-run
    python3 12_dedupe_images.py

Два вида дублаж, различни по произход:

1. БАЙТ-ИДЕНТИЧНИ файлове с различни имена. Идват от самия сайт: една и
   съща картинка стои на няколко адреса, а името ѝ у нас носи отпечатък на
   АДРЕСА (нарочно — в източника „1.jpg" в различни папки е различно
   изображение). Сливат се автоматично, по `md5` на съдържанието.

2. РАЗЛИЧНИ ВЕРСИИ на едно изображение — един и същ образ, сканиран два
   пъти. Тук няма как да се съди по байтовете; коя да остане е решение и се
   вписва в `input/image_aliases.csv` (колони: from,to,note).

   Пример: съборната икона на софийските светии стоеше в седем файла — три
   байт-идентични копия на добрия скан (600×735) и четири на избелелия
   (371×454). Остава добрият.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import re
import shutil
import sqlite3
from collections import defaultdict
from datetime import datetime

from common import INPUT, LIVES_DB, ROOT, TOOL

ASSETS = ROOT / 'assets' / 'lives_images'
RE_IMG = re.compile(r'assets/lives_images/([^"\'\s>]+)')


def load_aliases() -> dict[str, str]:
    """Ръчните решения „този файл → онзи файл"."""
    path = INPUT / 'image_aliases.csv'
    if not path.exists():
        return {}
    out = {}
    with path.open(encoding='utf-8') as fh:
        for r in csv.DictReader(fh):
            src, dst = (r.get('from') or '').strip(), (r.get('to') or '').strip()
            if src and dst and src != dst:
                out[src] = dst
    return out


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument('--dry-run', action='store_true')
    args = ap.parse_args()

    if not ASSETS.is_dir():
        raise SystemExit(f'няма папка {ASSETS}')

    # ── 1. байт-идентичните ──
    by_hash: dict[str, list[str]] = defaultdict(list)
    for p in sorted(ASSETS.glob('*')):
        if p.is_file():
            by_hash[hashlib.md5(p.read_bytes()).hexdigest()].append(p.name)

    mapping: dict[str, str] = {}
    for names in by_hash.values():
        if len(names) < 2:
            continue
        # ⚠ Остава файлът с НАЙ-КЪСОТО име, при равни — първият по азбучен
        # ред. Изборът е произволен, но ТРАЕН: пуснато втори път, сливането
        # трябва да сочи същия файл, инак всяко пускане мести четивата.
        keep = min(names, key=lambda n: (len(n), n))
        for n in names:
            if n != keep:
                mapping[n] = keep

    auto = len(mapping)

    # ── 2. ръчните ──
    for src, dst in load_aliases().items():
        if not (ASSETS / dst).exists():
            print(f'  ⚠ картата сочи липсващ файл: {dst}')
            continue
        mapping[src] = dst
    # ⚠ Веригите се изправят: ако A→B, а B→C, то A трябва да сочи C.
    for _ in range(5):
        changed = False
        for src, dst in list(mapping.items()):
            if dst in mapping and mapping[dst] != dst:
                mapping[src] = mapping[dst]
                changed = True
        if not changed:
            break

    if not mapping:
        print('няма дублажи')
        return

    print(f'сливания: {len(mapping)}  (байт-идентични {auto}, '
          f'по карта {len(mapping) - auto})')
    for src, dst in sorted(mapping.items()):
        print(f'   {src[:46]:48} → {dst[:44]}')

    # ── 3. пренасочване в базата ──
    con = sqlite3.connect(LIVES_DB)
    touched, replaced = 0, 0
    updates = []
    for slug, life in con.execute(
            "SELECT slug, life FROM texts WHERE life LIKE '%lives_images/%'"):
        n = 0

        def swap(m: re.Match) -> str:
            nonlocal n
            name = m.group(1)
            if name in mapping:
                n += 1
                return f'assets/lives_images/{mapping[name]}'
            return m.group(0)

        new = RE_IMG.sub(swap, life)
        if n:
            touched += 1
            replaced += n
            updates.append((new, slug))
    print(f'\nпренасочени споменавания: {replaced} в {touched} четива')

    if args.dry_run:
        print('--dry-run: НИЩО не е записано')
        return

    backups = TOOL / 'backups'
    backups.mkdir(exist_ok=True)
    stamp = datetime.now().strftime('%Y%m%d_%H%M%S')
    shutil.copy2(LIVES_DB, backups / f'lives.db.{stamp}')
    con.executemany('UPDATE texts SET life=? WHERE slug=?', updates)
    con.commit()

    # ── 4. изтриване на слетите файлове ──
    #
    # ⚠ Трие се САМО онова, към което вече НИКОЕ четиво не сочи — сверява се
    # наново срещу базата, а не срещу картата. Два конвейера пишат в тази
    # папка (виж 09_place_images.py) и списък „мои файлове" не е меродавен.
    still: set[str] = set()
    for (life,) in con.execute(
            "SELECT life FROM texts WHERE life LIKE '%lives_images/%'"):
        still.update(RE_IMG.findall(life or ''))
    removed = 0
    for name in mapping:
        p = ASSETS / name
        if name not in still and p.exists():
            p.unlink()
            removed += 1
    con.close()
    print(f'изтрити файлове: {removed}   остават: {len(list(ASSETS.glob("*")))}')
    print('\n⚠ Ако е пипана базата, следва НОВ БИЛД — горещото презареждане '
          'не пренася промяна в assets/.')


if __name__ == '__main__':
    main()
