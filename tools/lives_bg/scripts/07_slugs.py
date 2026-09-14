#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Вписва новите слъгове в СЕМЕТО на календара.

⚠ БЕЗ ТАЗИ СТЪПКА ЦЕЛИЯТ КОНВЕЙЕР Е НАПРАЗЕН. `06_apply.py` пише житието в
`lives.db` под някакъв слъг, но приложението стига до него през
`saints.slug` — празен ли е той, четивото съществува и е недостижимо.
Проверено на 30.08.2026: 41 внесени жития, от които само 16 се виждаха.

⚠ Пише в СЕМЕТО (`tools/calendar_gen/input/db/calendar_old.db`), а НЕ в
`assets/db/`. Поправка направо в готовите бази живее до първото пускане на
`merge_years.py` и после тихо изчезва — това е изрично документирано в
[tools/calendar_gen/README.md](../../calendar_gen/README.md).

⚠ Ключът е двойката `(date, name)`, а не `id`: той е AUTOINCREMENT и се
преномерира при всяко сглобяване на годините.

⚠ Името се чете БУКВАЛНО от базата. Тя съдържа невидими знаци (неразделящ
интервал \\xa0) и преписано на ръка име тихо не съвпада.

След пускане:

    rm -f tools/calendar_gen/out/*.db          # ⚠ инак старите се преизползват
    cd tools/calendar_gen
    python3 merge_years.py --years 2025 2026 2027 --style old
    python3 merge_years.py --years 2025 2026 2027 --style new
    cp out/calendar_old_2025-2027.db ../../assets/db/calendar_old.db
    cp out/calendar_new_2025-2027.db ../../assets/db/calendar_new.db
"""

from __future__ import annotations

import argparse
import glob
import json
import shutil
import sqlite3
import subprocess
from datetime import datetime

from common import ROOT, TOOL, WORK, core_name, fold

SEED = ROOT / 'tools' / 'calendar_gen' / 'input' / 'db' / 'calendar_old.db'


def check_lock(path) -> None:
    """⚠ Семето понякога стои отворено в sqlitebro и записът гърми с
    „database is locked". По-добре да се каже кой го държи, отколкото да се
    форсира през заключването."""
    try:
        out = subprocess.run(['lsof', str(path)], capture_output=True,
                             text=True, timeout=10).stdout.strip()
    except Exception:
        return
    if out:
        print('⚠ Семето е отворено от друга програма:')
        print('\n'.join(out.splitlines()[:4]))
        print('  Затвори я (и запази), преди да пуснеш това.')
        raise SystemExit(1)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument('--dry-run', action='store_true')
    args = ap.parse_args()

    if not SEED.exists():
        raise SystemExit(f'семето липсва: {SEED}')

    records = [json.loads(open(f, encoding='utf-8').read())
               for f in sorted(glob.glob(str(WORK / 'parsed' / '*.json')))]
    # Какво реално е записано в lives.db — оттам идват верните слъгове.
    from common import LIVES_DB
    lives = sqlite3.connect(f'file:{LIVES_DB}?mode=ro', uri=True)
    known = {r[0]: r[1] for r in lives.execute(
        "SELECT slug, name FROM texts WHERE source LIKE '%pravoslavieto%'")}
    lives.close()

    # Слъг по ядрото на името — така се намира редът в семето.
    by_core = {fold(name): slug for slug, name in known.items() if name}

    if not args.dry_run:
        check_lock(SEED)

    con = sqlite3.connect(SEED)
    rows = con.execute("""
        SELECT id, date, name FROM saints
         WHERE group_code='BG' AND (slug IS NULL OR slug='')
    """).fetchall()

    plan = []
    for sid, date, name in rows:
        slug = by_core.get(fold(core_name(name)))
        if slug:
            plan.append((sid, date, name, slug))

    print(f'редове без слъг в семето: {len(rows)}')
    print(f'от тях получават слъг:    {len(plan)}')
    print()
    for _, date, name, slug in plan[:12]:
        print(f'  {date}  {name[:40]:42} → {slug}')
    if len(plan) > 12:
        print(f'  … и още {len(plan) - 12}')

    if args.dry_run:
        print('\n--dry-run: НИЩО не е записано')
        con.close()
        return

    backup_dir = TOOL / 'backups'
    backup_dir.mkdir(exist_ok=True)
    stamp = datetime.now().strftime('%Y%m%d_%H%M%S')
    dest = backup_dir / f'calendar_old.db.seed.{stamp}'
    shutil.copy2(SEED, dest)
    print(f'\nрезервно копие на семето: {dest.name}')

    for sid, _, _, slug in plan:
        con.execute('UPDATE saints SET slug=? WHERE id=?', (slug, sid))
    con.commit()
    left = con.execute("""SELECT COUNT(*) FROM saints
                           WHERE group_code='BG' AND (slug IS NULL OR slug='')
                       """).fetchone()[0]
    con.close()

    print(f'вписани: {len(plan)} реда;  остават без слъг: {left}')
    print('\n⚠ СЕГА ПРЕГЕНЕРИРАЙ — инак промяната не стига до assets/db/:')
    print('    rm -f tools/calendar_gen/out/*.db')
    print('    cd tools/calendar_gen && python3 merge_years.py '
          '--years 2025 2026 2027 --style old')
    print('    python3 merge_years.py --years 2025 2026 2027 --style new')


if __name__ == '__main__':
    main()
