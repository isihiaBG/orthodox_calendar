#!/usr/bin/env python3
"""Сверява кратките бележки (lib/day_notes.dart) с изворите им.

Всяка бележка с връзка трябва да сочи четиво, което съществува, и пасажът
ѝ да стои в него ДОСЛОВНО — сверено сгънато (само букви и цифри, малки),
по същото правило като `foldForMatch` в приложението. Излиза с код 1 при
първото разминаване, за да не се пропусне.

    python3 tools/tipikon/scripts/check_notes.py
"""
import html, json, re, sqlite3, subprocess, sys
from pathlib import Path

КОРЕН = Path(__file__).resolve().parents[3]
DB = КОРЕН / 'assets' / 'db'


def сгъни(t: str) -> str:
    return ''.join(ch for ch in t.lower() if ch.isalnum())


def тяло(slug: str) -> str | None:
    if slug.startswith('tip-'):
        r = sqlite3.connect(DB / 'lives_plus.db').execute(
            'SELECT body FROM tipikon WHERE id=?', (slug,)).fetchone()
    elif slug.startswith('dni-'):
        r = sqlite3.connect(DB / 'lives_plus.db').execute(
            'SELECT body FROM dni WHERE id=?', (slug,)).fetchone()
    elif slug.startswith('azb-'):
        r = sqlite3.connect(DB / 'lives.db').execute(
            'SELECT body FROM articles WHERE slug=?', (slug[4:],)).fetchone()
    else:
        return None
    return html.unescape(re.sub(r'<[^>]+>', ' ', r[0])) if r else None


def main() -> None:
    бележки = json.loads(subprocess.run(
        ['dart', 'run', 'tools/tipikon/scripts/dump_notes.dart'],
        cwd=КОРЕН, capture_output=True, text=True, check=True).stdout)
    грешки = 0
    for б in бележки:
        if б['kind'] == 'custom':
            continue
        т = тяло(б['slug'])
        if т is None:
            print(f"✗ {б['day']}: няма четиво {б['slug']}")
            грешки += 1
            continue
        n = сгъни(т).count(сгъни(б['passage']))
        if n == 0:
            print(f"✗ {б['day']}: пасажът го няма в {б['slug']}: {б['passage'][:60]}")
            грешки += 1
        elif n > 1:
            print(f"· {б['day']}: пасажът се среща {n} пъти в {б['slug']} "
                  f"(маркира се първият): {б['passage'][:50]}")
    print(f"{len(бележки)} бележки, грешки: {грешки}")
    sys.exit(1 if грешки else 0)


if __name__ == '__main__':
    main()
