#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
04_build_db.py — Стъпка 4 (МЕХАНИЧНА, без DeepSeek): сглобява
assets/db/optina.db от преведените сентенции.

Базата е отделна, като teofan.db и reference.db, и НЕ се ATTACH-ва към
календарната — заявката е една и се пуска чак при разгъване на секцията.

Разметката ползва САМО тагове и класове, които четецът вече рисува
(`.cite`, `.source`), тъй че секцията в дневния изглед не иска ново
TagExtension:

    <p>…</p>                                   сентенцията
    <span class="cite" data-ref="Mt.11:29">    цитат; data-ref е за
      «…»</span>                               по-късната сверка със
                                               синодалното издание
    <a href="…?Mt.11:29&bg~utfcs">Мт.11:29</a> препратка към Писанието
    <p class="source">прп. Амвросий</p>        старецът

РЕДЪТ Е ВАЖЕН: първо се екранира, чак после се вкарват таговете. Обратното
би превърнало собствените ни ъглови скоби в &lt;.

Защо адресът е гражданска дата „ММ-ДД"
--------------------------------------
За разлика от мислите на свт. Теофан, сентенциите на старците НЕ са вързани
за деня — това е тематичен речник, не годишен кръг. Затова тук няма верига
на приоритета, няма подвижни адреси и няма нужда от нищо повече от една
дата. „ММ-ДД" се чете еднакво в стар и нов стил, повтаря се всяка година и
държи отметките стабилни.

34-те сентенции в запас влизат с day = NULL. Уникалният показалец по `day`
ги пропуска (SQLite не смята NULL за повторение) и пази обещанието, че на
всеки ден отговаря най-много една.

Вход:   ../work/translated/*.json     (от 03_translate_deepseek.py)
Изход:  ../../../assets/db/optina.db

Употреба:
  python3 04_build_db.py
  python3 04_build_db.py --out /друг/път/optina.db
"""

import argparse
import glob
import html
import json
import os
import re
import sqlite3
import sys
from collections import Counter

from common import bulgarian_ref

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.dirname(SCRIPT_DIR)
WORK_DIR = os.path.join(PROJECT_DIR, 'work')
TRANSLATED_DIR = os.path.join(WORK_DIR, 'translated')
REPO_ROOT = os.path.dirname(os.path.dirname(PROJECT_DIR))
DEFAULT_OUT = os.path.join(REPO_ROOT, 'assets', 'db', 'optina.db')

BIBLE_URL = 'https://azbyka.ru/biblia/?%s&bg~utfcs'

RE_ATOM = re.compile(r'⟦(\d+)⟧')
RE_QUOTE = re.compile(r'«[^«»]{2,}»')
# Колко чисти знака търпим между края на цитата и препратката, за да ги
# смятаме за сдвоени. Обикновено между тях стои „ (" или „. (".
REF_WINDOW = 25

SCHEMA = """
CREATE TABLE sayings (
    id      INTEGER PRIMARY KEY,
    day     TEXT,                        -- 'ММ-ДД'; NULL значи „в запас"
    elder   TEXT NOT NULL,               -- 'Амвросий' — без „прп.", то е в body
    body    TEXT NOT NULL,               -- български, готов за flutter_html
    -- Справочни. Приложението НЕ ги чете; стоят, за да може всяка сентенция
    -- да се сверява назад към симфонията. Темата остава руска нарочно —
    -- тя е ключът към дяла в книгата, а не текст за показване.
    src_id       TEXT NOT NULL,          -- 'v1-054-04', както в work/quotes.json
    src_vol      INTEGER,                -- 1 или 2
    src_topic_ru TEXT,                   -- дялът на симфонията
    src_ref      TEXT,                   -- '3, ч. 2' — номер от библиографията
    src_title    TEXT,                   -- заглавието на този източник
    src_body_ru  TEXT,
    score        REAL                    -- оценката от 02_select.py
);
CREATE UNIQUE INDEX sayings_day ON sayings(day);
CREATE INDEX sayings_elder ON sayings(elder);

-- Указател към цитатите. НЕ е източник на текста — текстът живее в
-- sayings.body. Служи за по-късната сверка със синодалното издание.
CREATE TABLE quotes (
    id        INTEGER PRIMARY KEY,
    saying_id INTEGER NOT NULL,
    n         INTEGER NOT NULL,
    ref       TEXT,
    text_bg   TEXT NOT NULL,
    verified  INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX quotes_saying ON quotes(saying_id);

-- Библиографията на симфонията, за да не се търси в книгата какво значи „20".
CREATE TABLE sources (
    n     TEXT PRIMARY KEY,
    title TEXT NOT NULL
);
"""


def build_body(unit, quotes_out):
    """Сглобява тялото на една сентенция и попълва указателя на цитатите."""
    atoms = {a['n']: a for a in unit['atoms']}
    text = unit['body_bg']
    marks = {}
    index = 0

    # 1. Цитатите се намират ПРЕДИ екранирането, докато запушалките още са
    #    ⟦N⟧ — така препратката след цитата се чете направо от атома.
    def on_quote(m):
        nonlocal index
        index += 1
        tail = text[m.end():m.end() + REF_WINDOW]
        ref = None
        for num in RE_ATOM.findall(tail):
            atom = atoms.get(int(num))
            if atom:
                ref = atom['code']
                break
        quotes_out.append({'n': index, 'ref': ref, 'text_bg': m.group(0)})
        marks[index] = ref
        return '⟦ц%d⟧%s⟦/ц%d⟧' % (index, m.group(0), index)

    marked = RE_QUOTE.sub(on_quote, text)

    # 2. Екранираме. Всичко след тази точка вкарва СОБСТВЕНИ тагове.
    escaped = html.escape(marked, quote=False)

    def open_cite(m):
        ref = marks.get(int(m.group(1)))
        attr = ' data-ref="%s"' % html.escape(ref, quote=True) if ref else ''
        return '<span class="cite"%s>' % attr

    escaped = re.sub(r'⟦ц(\d+)⟧', open_cite, escaped)
    escaped = re.sub(r'⟦/ц\d+⟧', '</span>', escaped)

    def on_atom(m):
        atom = atoms.get(int(m.group(1)))
        if atom is None:
            return ''
        code = atom['code']
        return '<a href="%s">%s</a>' % (
            html.escape(BIBLE_URL % code, quote=True),
            html.escape(bulgarian_ref(code), quote=False))

    escaped = RE_ATOM.sub(on_atom, escaped)
    # Всичките дванайсет са оптински старци, тъй че прозвището се долепя
    # машинно и не се пази в колоната `elder` — там стои голото име, по
    # което се групира и брои.
    return '<p>%s</p>\n<p class="source">прп. %s Оптински</p>' % (
        escaped.strip(), unit['elder'])


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--out', default=DEFAULT_OUT)
    args = ap.parse_args()

    files = sorted(glob.glob(os.path.join(TRANSLATED_DIR, '*.json')))
    if not files:
        sys.exit('Няма преведени сентенции в %s — пусни '
                 '03_translate_deepseek.py.' % TRANSLATED_DIR)

    sources_path = os.path.join(WORK_DIR, 'sources.json')
    sources = (json.load(open(sources_path, encoding='utf-8'))
               if os.path.exists(sources_path) else {})

    # ⚠ Датата се взима от selected.json, НЕ от преведения файл. Преводът е
    # платен и се пази; разбъркването на датите е безплатно и се прави
    # колкото пъти трябва с 02_select.py. Четеше ли се от превода, всяко
    # разбъркване щеше да иска нов превод, за да се усети.
    sel_path = os.path.join(WORK_DIR, 'selected.json')
    if not os.path.exists(sel_path):
        sys.exit('Няма %s — пусни 02_select.py.' % sel_path)
    selected = {q['id']: q for q in json.load(open(sel_path,
                                                   encoding='utf-8'))}
    # Разширеният резерв (02b_expand.py) — всичко преведено извън календара.
    # Тези нямат и НЕ получават ден: стоят в базата и чакат да заменят
    # сентенция, която при преглед се окаже неподходяща. Ако някой ден се
    # окаже и в двата списъка, календарният печели — той носи датата.
    # Ръчните ПОДМЕНИ. Тук, а не в 02_select.py, нарочно: там датите се
    # раздават наново за цялата година и подмяната на един ден би разместила
    # всички останали. Резервът съществува тъкмо за да може да се сменя по
    # един ден, без да мръдне нищо друго.
    #
    #   "swap": {"<id на пенсионираната>": "<id на заместника>"}
    #
    # Пенсионираната остава в базата без ден — може да потрябва пак.
    manual_path = os.path.join(WORK_DIR, 'manual_select.json')
    manual = (json.load(open(manual_path, encoding='utf-8'))
              if os.path.exists(manual_path) else {})
    swap = manual.get('swap', {})

    exp_path = os.path.join(WORK_DIR, 'expand.json')
    n_exp = 0
    if os.path.exists(exp_path):
        for q in json.load(open(exp_path, encoding='utf-8')):
            if q['id'] not in selected:
                q['day'] = None
                selected[q['id']] = q
                n_exp += 1
        print('резерв от 02b_expand.py: %d записа' % n_exp)

    if os.path.exists(args.out):
        os.remove(args.out)
    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    db = sqlite3.connect(args.out)
    db.executescript(SCHEMA)

    # Прилагането е ПРЕДИ обхождането: заместникът поема датата, а
    # пенсионираната минава в резерва.
    for old_id, new_id in swap.items():
        a, b = selected.get(old_id), selected.get(new_id)
        if a is None or b is None:
            print('  ⚠ подмяна %s → %s: липсва един от двата' % (old_id,
                                                                 new_id))
            continue
        b['day'], a['day'] = a['day'], None
        print('  подмяна: %s (%s) отстъпва деня на %s' % (old_id, b['day'],
                                                          new_id))

    dates, clashes, ncites, noref = {}, [], 0, 0
    elders, days, reserve = Counter(), 0, 0

    for sid, path in enumerate(files, 1):
        unit = json.load(open(path, encoding='utf-8'))
        if not unit.get('body_bg'):
            print('  пропускам %s — няма превод' % unit['id'])
            continue

        current = selected.get(unit['id'])
        if current is None:
            print('  пропускам %s — вече не е в избора' % unit['id'])
            continue

        quotes = []
        body = build_body(unit, quotes)
        day = current.get('day')
        if day:
            if day in dates:
                clashes.append('%s: %s и %s' % (day, dates[day], unit['id']))
            dates[day] = unit['id']
            days += 1
        else:
            reserve += 1
        elders[unit['elder']] += 1

        ref = unit['src']
        if unit.get('src_part'):
            ref = '%s, %s' % (ref, unit['src_part'])
        db.execute(
            'INSERT INTO sayings (id, day, elder, body, src_id, src_vol,'
            ' src_topic_ru, src_ref, src_title, src_body_ru, score)'
            ' VALUES (?,?,?,?,?,?,?,?,?,?,?)',
            (sid, day, unit['elder'], body, unit['id'], unit['vol'],
             unit['topic_ru'], ref, unit.get('src_title'), unit['body_ru'],
             current.get('score')))
        for q in quotes:
            db.execute('INSERT INTO quotes (saying_id, n, ref, text_bg)'
                       ' VALUES (?,?,?,?)', (sid, q['n'], q['ref'],
                                             q['text_bg']))
            ncites += 1
            noref += 0 if q['ref'] else 1

    for n, title in sources.items():
        db.execute('INSERT INTO sources (n, title) VALUES (?,?)', (n, title))

    db.commit()

    print('=' * 64)
    print('сентенции: %d (с дата %d, в запас %d)' % (days + reserve, days,
                                                     reserve))
    print('старци: ' + ', '.join('%s %d' % kv for kv in elders.most_common()))
    print('цитати в «…»: %d (без препратка: %d)' % (ncites, noref))
    if clashes:
        print('СБЛЪСЪЦИ ПО ДАТА: %d' % len(clashes))
        for c in clashes:
            print('  %s' % c)
    missing = [d for d in ('%02d-%02d' % (m, d)
                           for m in range(1, 13)
                           for d in range(1, [31, 29, 31, 30, 31, 30, 31, 31,
                                              30, 31, 30, 31][m - 1] + 1))
               if d not in dates]
    if missing:
        print('ДНИ БЕЗ СЕНТЕНЦИЯ: %d — %s' % (len(missing),
                                              ', '.join(missing[:12])))
    size = os.path.getsize(args.out)
    print('→ %s (%.0f KB)' % (args.out, size / 1024))
    db.close()


if __name__ == '__main__':
    main()
