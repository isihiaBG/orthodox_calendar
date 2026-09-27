#!/usr/bin/env python3
"""Библейските препратки в словата → ДЕЙСТВАЩИ връзки.

⚠⚠ ЕМИТИРА СЕ СЪЩИЯТ ВИД АДРЕС КАТО В ТОМОВЕТЕ:

    <a href="https://azbyka.ru/biblia/?Mt.5:1-7&amp;bg~utfcs">Мат. 5:1-7</a>

Нарочно — така препратката минава по вече наличния път и се отваря ВЪТРЕ в
приложението (виж „Библейските препратки се отварят ВЪТРЕ" в CLAUDE.md). Нов
вид адрес би искал второ разчитане и втори повод двете да се разминат.

⚠ Кодовете на книгите се четат от `bible.db` (`books.bg_abbr`), НЕ се пишат
на ръка: същият списък храни и надписа под споделен цитат, тъй че разминаване
е невъзможно по устройство.

    python3 05_bible_links.py --dry-run
    python3 05_bible_links.py
"""
import argparse
import json
import re
import sqlite3
import sys
from pathlib import Path

КОРЕН = Path(__file__).resolve().parents[1]
РАБОТА = КОРЕН / 'work'
БИБЛИЯ = КОРЕН.parents[1] / 'assets' / 'db' / 'bible.db'

# ⚠ Съкращенията и самото свързване живеят в ОБЩИЯ модул
# tools/bible_refs/linkify.py (27.09.2026) — ползват го и справочникът,
# Дебольски и житията. Тук остават само тънки обвивки със старите имена.
sys.path.insert(0, str(КОРЕН.parents[0] / 'bible_refs'))
import linkify  # noqa: E402


def съкращения() -> dict[str, str]:
    return linkify.abbreviations()


def свържи(текст: str, карта: dict[str, str], брой: dict) -> str:
    st = {}
    out = linkify.link(текст, карта, st)
    брой['връзки'] = брой.get('връзки', 0) + st.get('links', 0)
    for k, n in st.get('unknown', {}).items():
        брой.setdefault('непознати', {})
        брой['непознати'][k] = брой['непознати'].get(k, 0) + n
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('--dry-run', action='store_true')
    a = ap.parse_args()
    if not БИБЛИЯ.exists():
        sys.exit(f'липсва {БИБЛИЯ}')
    карта = съкращения()
    брой = {}
    файлове = sorted((РАБОТА / 'translated').glob('*.json'))
    if not файлове:
        sys.exit('няма преводи')
    пипнати = 0
    for f in файлове:
        x = json.loads(f.read_text(encoding='utf-8'))
        нови = [свържи(b, карта, брой) for b in x['blocks_bg']]
        if нови != x['blocks_bg']:
            пипнати += 1
            if not a.dry_run:
                x['blocks_bg'] = нови
                f.write_text(json.dumps(x, ensure_ascii=False, indent=1),
                             encoding='utf-8')
    print(f'{"БИ СВЪРЗАЛ" if a.dry_run else "свързани"}: '
          f'{брой.get("връзки", 0)} препратки в {пипнати} от {len(файлове)} слова')
    неп = брой.get('непознати', {})
    if неп:
        print(f'⚠ непознати съкращения ({len(неп)}), най-чести:')
        for k, n in sorted(неп.items(), key=lambda kv: -kv[1])[:14]:
            print(f'   {k:14} ×{n}')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
