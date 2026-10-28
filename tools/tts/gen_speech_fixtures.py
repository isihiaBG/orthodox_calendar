#!/usr/bin/env python3
"""Образци за сверката Dart ↔ Python (test/speech_text_test.dart).

    python3 tools/tts/gen_speech_fixtures.py            # малкият набор → test/fixtures/
    python3 tools/tts/gen_speech_fixtures.py --all F    # всички абзаци от lives.db → F

Изходът е JSON [[показано, изговорено], …]; изговореното е accent.speak()
без оградките ⟦…⟧ (тях Dart не слага).
"""
import argparse
import json
import random
import re
import sqlite3
from pathlib import Path

from accent import _plain, speak

ROOT = Path(__file__).resolve().parents[2]
SMALL = ROOT / 'test' / 'fixtures' / 'speech_cases.json'
# Абзаци с нещо за разгъване — само те влизат в малкия набор.
INTERESTING = re.compile(r'\d|[Сс]в\.|т\.\s?[ен]\.|ап\.|[IVX]\s*в|[ѣѧѡіѿ]|[+†]|напр\.|срв\.|вж\.', re.I)


def paragraphs():
    db = sqlite3.connect(ROOT / 'assets' / 'db' / 'lives.db')
    for (life,) in db.execute('SELECT life FROM texts WHERE life IS NOT NULL ORDER BY slug'):
        for p in re.findall(r'<p[^>]*>(.*?)</p>', life, re.S):
            t = _plain(p)
            if t and '⟦' not in t:     # живите дати ⟦дата:…⟧ ги показва приложението
                yield t


def case(t):
    try:
        return [t, speak(t).replace('⟦', '').replace('⟧', '')]
    except ValueError:      # непознато съкращение под титла — Python спира
        return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--all')
    a = ap.parse_args()
    paras = list(paragraphs())
    if a.all:
        out, dest = [c for c in map(case, paras) if c], Path(a.all)
    else:
        pick = [t for t in paras if INTERESTING.search(t) and len(t) < 900]
        random.Random(1).shuffle(pick)
        out, dest = [c for c in map(case, pick[:400]) if c], SMALL
        dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_text(json.dumps(out, ensure_ascii=False, indent=0))
    print(dest, len(out), 'абзаца от', len(paras))


if __name__ == '__main__':
    main()
