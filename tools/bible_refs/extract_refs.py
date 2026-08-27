#!/usr/bin/env python3
"""Вади ВСИЧКИ библейски препратки от житията и томовете в refs.txt.

Пуска се от корена на проекта:

    python3 tools/bible_refs/extract_refs.py
    dart run tools/bible_refs/verify_refs.dart

Второто разчита всяка препратка с `parseBibleRef` и я сглобява ОБРАТНО, за
да излезе наяве тиха грешка в смисъла — не просто „не гърми ли".
"""
import sqlite3, zipfile, re, pathlib

RE = re.compile(r'azbyka\.ru/biblia/\?([^"&]+)')
refs = []
db = sqlite3.connect('assets/db/lives.db')
for (l,) in db.execute("SELECT life FROM texts WHERE life LIKE '%azbyka.ru/biblia%'"):
    refs += RE.findall(l or '')
for v in sorted(pathlib.Path('assets/books').glob('*.epub')):
    with zipfile.ZipFile(v) as z:
        for n in z.namelist():
            if n.endswith(('.xhtml', '.html')):
                refs += RE.findall(z.read(n).decode('utf-8', 'replace'))

uniq = sorted(set(refs))
pathlib.Path('tools/bible_refs/refs.txt').write_text('\n'.join(uniq), encoding='utf-8')
print(f"{len(uniq)} различни препратки (от {len(refs)} срещания) → tools/bible_refs/refs.txt")
