"""Прави библейските препратки ДЕЙСТВАЩИ направо в готовите бази.

    python3 tools/bible_refs/link_dbs.py --dry-run
    python3 tools/bible_refs/link_dbs.py

Поводът (27.09.2026): в справочника, у Дебольски, в част от житията и в две
слова на Златоуст препратките стояха като ОБИКНОВЕН ТЕКСТ — всеки конвейер
правеше връзките сам или изобщо не ги правеше.

⚠⚠ ПУСКА СЕ СЛЕД ВСЕКИ КОНВЕЙЕР, КОЙТО ПИШЕ ЖИТИЯ ИЛИ СТАТИИ В lives.db
(lives_bg, lives_extra, lives_mitropolia, paskha) — те лепят текст, без да
свързват препратките. Справочникът, Дебольски и словата на Юстин/Златоуст
свързват сами при сглобяване (виж `linkify` в техните build скриптове).

⚠ Идемпотентно по устройство: пипа се само текстът ИЗВЪН вече съществуващите
връзки, тъй че второ пускане не мени нищо.

⚠ Резервното копие ляга в `tools/bible_refs/backups/`, НЕ до базата —
`pubspec.yaml` включва цялата `assets/db/`.
"""
import argparse
import shutil
import sqlite3
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import linkify  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
DB = ROOT / 'assets' / 'db'
BACKUP = Path(__file__).resolve().parent / 'backups'

# (база, таблица, ключ, колона)
TARGETS = [
    ('reference.db', 'ref_articles', 'id', 'body'),
    ('lives.db', 'texts', 'slug', 'life'),
    ('lives.db', 'articles', 'slug', 'body'),
    ('lives_plus.db', 'slova', 'id', 'body'),
    ('lives_plus.db', 'dni', 'id', 'body'),
]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('--dry-run', action='store_true')
    a = ap.parse_args()
    table = linkify.abbreviations()
    stamp = time.strftime('%Y%m%d_%H%M%S')
    backed = set()
    total = 0
    for db_name, tbl, key, col in TARGETS:
        path = DB / db_name
        con = sqlite3.connect(path)
        rows = con.execute(f'SELECT {key}, {col} FROM {tbl}').fetchall()
        stats, changed = {}, []
        for k, body in rows:
            if not body:
                continue
            new = linkify.link(body, table, stats)
            if new != body:
                changed.append((new, k))
        n = stats.get('links', 0)
        total += n
        print(f'{db_name}:{tbl:13} {n:4} нови връзки в {len(changed)} четива')
        if changed and not a.dry_run:
            if db_name not in backed:
                BACKUP.mkdir(exist_ok=True)
                shutil.copy2(path, BACKUP / f'{db_name}.bak-{stamp}')
                backed.add(db_name)
            con.executemany(f'UPDATE {tbl} SET {col}=? WHERE {key}=?', changed)
            con.commit()
        con.close()
    print(('БИ СВЪРЗАЛ' if a.dry_run else 'свързани') + f': {total}')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
