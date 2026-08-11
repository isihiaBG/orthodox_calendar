#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
03_build_db.py — Стъпка 3 (МЕХАНИЧНА, без DeepSeek): сглобява
assets/db/teofan.db от преведените поучения.

Базата е отделна, като reference.db, и НЕ се ATTACH-ва към календарната —
заявката е една и се пуска чак при разгъване на секцията.

Разметката нарочно ползва САМО тагове, които flutter_html вече рисува, и
класови селектори, каквито четецът вече има (`.csl`, `.trans`, `.source`).
Така секцията в дневния изглед не иска нито едно ново TagExtension:

    <p>…</p>                                   абзац
    <span class="cite" data-ref="Jac.2:14">    цитат от Писанието; data-ref
      «…»</span>                               е за по-късната сверка със
                                               синодалното издание
    <a href="…?Jac.2:14&bg~utfcs">Иак.2:14</a> препратка към Писанието
    <sup class="note" data-note="*5">*5</sup>  препратка към бележка

Опашката „&bg~utfcs" отваря българския текст на azbyka.ru с успореден
църковнославянски — същата поправка както 01d_bible_links.py при житията.
Докато си направим своя секция „Библия", препратките остават външни; тогава
ще се преобразуват във вътрешни по data-ref, без да се пипа текстът.

РЕДЪТ Е ВАЖЕН: първо се екранира, чак после се вкарват таговете. Обратното
би превърнало собствените ни ъглови скоби в &lt; — същият капан както при
знаците на Типикона в справочника.

Вход:
  ../work/translated/*.json     (от 02_translate_deepseek.py)
  ../work/notes_bg.json         (от 02b_translate_notes.py)

Изход:
  ../../../assets/db/teofan.db

Употреба:
  python3 03_build_db.py
  python3 03_build_db.py --out /друг/път/teofan.db
"""

import argparse
import glob
import html
import json
import os
import re
import sqlite3
import sys

from common import bulgarian_ref

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.dirname(SCRIPT_DIR)
WORK_DIR = os.path.join(PROJECT_DIR, 'work')
TRANSLATED_DIR = os.path.join(WORK_DIR, 'translated')
REPO_ROOT = os.path.dirname(os.path.dirname(PROJECT_DIR))
DEFAULT_OUT = os.path.join(REPO_ROOT, 'assets', 'db', 'teofan.db')

BIBLE_URL = 'https://azbyka.ru/biblia/?%s&bg~utfcs'

RE_ATOM = re.compile(r'⟦(\d+)⟧')
RE_QUOTE = re.compile(r'«[^«»]{2,}»')
# Колко ЧИСТИ знака търпим между края на цитата и препратката, за да ги
# смятаме за сдвоени. Обикновено между тях стои „ (" или „. (" — но има и
# случаи с кратко пояснение помежду им, затова прозорецът е малко по-широк.
REF_WINDOW = 25

SCHEMA = """
CREATE TABLE thoughts (
    id            INTEGER PRIMARY KEY,   -- номерът на записа в книгата (2..354)
    kind          TEXT    NOT NULL,      -- fixed | pascha | pent | anchor
    key           TEXT    NOT NULL,      -- '01-06' | '-70' | '12:5' | 'sunday:13'
    level         INTEGER NOT NULL,      -- 1..5, веригата на приоритета
    body          TEXT    NOT NULL,      -- български, готов за flutter_html
    -- Справочни. Приложението НЕ ги чете; стоят, за да може всяка мисъл да
    -- се сверява назад към книгата. Заглавието остава руско нарочно — на
    -- български денят си има име в календарната база.
    src_file      TEXT,
    src_title_ru  TEXT,
    src_parent_ru TEXT,                  -- под кое заглавие стои в книгата
    src_readings  TEXT,
    src_body_ru   TEXT,
    src_date_1887 TEXT,
    src_week_label TEXT
);
CREATE UNIQUE INDEX thoughts_addr ON thoughts(kind, key);

-- Указател към цитатите от Писанието. НЕ е източник на текста — текстът
-- живее в thoughts.body. Тази таблица служи за по-късната сверка със
-- синодалното издание: минава се по нея, поправя се тялото на място.
CREATE TABLE quotes (
    id         INTEGER PRIMARY KEY,
    thought_id INTEGER NOT NULL,
    n          INTEGER NOT NULL,         -- пореден номер в поучението
    ref        TEXT,                     -- 'Jac.2:14' или NULL, ако няма
    text_bg    TEXT    NOT NULL,
    verified   INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX quotes_thought ON quotes(thought_id);

CREATE TABLE notes (
    key  TEXT PRIMARY KEY,               -- '*5' или '3'
    body TEXT NOT NULL
);
"""


def build_body(unit, quotes_out):
    """Сглобява тялото на едно поучение и попълва указателя на цитатите."""
    atoms = {a['n']: a for a in unit['atoms']}
    paragraphs = []
    quote_index = 0

    for text in unit['units_bg']:
        # 1. Цитатите се намират ПРЕДИ екранирането, докато запушалките още
        #    са ⟦N⟧ — така препратката след цитата се чете направо от атома.
        marks = {}

        def on_quote(m):
            nonlocal quote_index
            quote_index += 1
            tail = text[m.end():m.end() + REF_WINDOW]
            ref = None
            for num in RE_ATOM.findall(tail):
                atom = atoms.get(int(num))
                if atom and atom['kind'] == 'bible':
                    ref = atom['payload']
                    break
            quotes_out.append({'n': quote_index, 'ref': ref,
                               'text_bg': m.group(0)})
            marks[quote_index] = ref
            return '⟦ц%d⟧%s⟦/ц%d⟧' % (quote_index, m.group(0), quote_index)

        marked = RE_QUOTE.sub(on_quote, text)

        # 2. Екранираме. Всичко след тази точка вкарва СОБСТВЕНИ тагове,
        #    които не бива да бъдат екранирани.
        escaped = html.escape(marked, quote=False)

        # 3. Запушалките на цитатите → <span class="cite">.
        def open_cite(m):
            ref = marks.get(int(m.group(1)))
            attr = ' data-ref="%s"' % html.escape(ref, quote=True) if ref else ''
            return '<span class="cite"%s>' % attr

        escaped = re.sub(r'⟦ц(\d+)⟧', open_cite, escaped)
        escaped = re.sub(r'⟦/ц\d+⟧', '</span>', escaped)

        # 4. Запушалките на препратките → <a> и <sup>.
        def on_atom(m):
            atom = atoms.get(int(m.group(1)))
            if atom is None:
                return ''
            if atom['kind'] == 'bible':
                code = atom['payload']
                return '<a href="%s">%s</a>' % (
                    html.escape(BIBLE_URL % code, quote=True),
                    html.escape(bulgarian_ref(code), quote=False))
            label = html.escape(atom['payload'], quote=False)
            return '<sup class="note" data-note="%s">%s</sup>' % (label, label)

        escaped = RE_ATOM.sub(on_atom, escaped)
        paragraphs.append('<p>%s</p>' % escaped.strip())

    return '\n'.join(paragraphs)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--out', default=DEFAULT_OUT)
    args = ap.parse_args()

    files = sorted(glob.glob(os.path.join(TRANSLATED_DIR, '*.json')))
    if not files:
        sys.exit('Няма преведени поучения в %s — пусни 02_translate_deepseek.py.'
                 % TRANSLATED_DIR)

    notes_path = os.path.join(WORK_DIR, 'notes_bg.json')
    notes = (json.load(open(notes_path, encoding='utf-8'))
             if os.path.exists(notes_path) else {})
    if not notes:
        print('ВНИМАНИЕ: няма notes_bg.json — препратките към бележки ще '
              'сочат в празното. Пусни 02b_translate_notes.py.')

    if os.path.exists(args.out):
        os.remove(args.out)
    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    db = sqlite3.connect(args.out)
    db.executescript(SCHEMA)

    адреси = {}
    сблъсъци = []
    всички_цитати = 0
    без_препратка = 0

    for path in files:
        unit = json.load(open(path, encoding='utf-8'))
        if not unit.get('units_bg'):
            print('  пропускам %03d — няма превод' % unit['index'])
            continue

        quotes = []
        body = build_body(unit, quotes)
        адрес = (unit['kind'], unit['key'])
        if адрес in адреси:
            сблъсъци.append('%s %s: записи %d и %d'
                            % (unit['kind'], unit['key'],
                               адреси[адрес], unit['index']))
        адреси[адрес] = unit['index']

        db.execute(
            'INSERT INTO thoughts (id, kind, key, level, body, src_file,'
            ' src_title_ru, src_parent_ru, src_readings, src_body_ru,'
            ' src_date_1887, src_week_label)'
            ' VALUES (?,?,?,?,?,?,?,?,?,?,?,?)',
            (unit['index'], unit['kind'], unit['key'], unit['level'], body,
             unit['file'], unit['title_ru'], unit['parent_ru'],
             unit['readings'], '\n\n'.join(unit['units_ru']),
             unit['date_1887'], unit['week_label_1887']))

        for q in quotes:
            db.execute('INSERT INTO quotes (thought_id, n, ref, text_bg)'
                       ' VALUES (?,?,?,?)',
                       (unit['index'], q['n'], q['ref'], q['text_bg']))
            всички_цитати += 1
            без_препратка += 0 if q['ref'] else 1

    for key, text in notes.items():
        if not key.startswith('_'):
            db.execute('INSERT INTO notes (key, body) VALUES (?,?)',
                       (key, text))

    db.commit()

    поучения = db.execute('SELECT count(*) FROM thoughts').fetchone()[0]
    print('=' * 64)
    print('поучения: %d' % поучения)
    for kind, n in db.execute('SELECT kind, count(*) FROM thoughts'
                              ' GROUP BY kind ORDER BY kind'):
        print('  %-7s %3d' % (kind, n))
    print('цитати: %d (от тях %d без препратка)'
          % (всички_цитати, без_препратка))
    print('бележки: %d' % db.execute('SELECT count(*) FROM notes').fetchone()[0])
    if сблъсъци:
        print('СБЛЪСЪЦИ В АДРЕСИТЕ (%d):' % len(сблъсъци))
        for line in сблъсъци:
            print('  ' + line)
    db.close()

    print('→ %s (%.1f MB)' % (args.out, os.path.getsize(args.out) / 1e6))


if __name__ == '__main__':
    main()
