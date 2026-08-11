#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
04_verify.py — Стъпка 4 (МЕХАНИЧНА): проверява сглобената teofan.db.

Нищо не поправя — само докладва. Проверките са пет на брой и всяка отговаря
на конкретен начин, по който конвейерът може да сгреши тихо:

 1. НАЛИЧНОСТ. Всяка запушалка от оригинала трябва да е станала таг. Ако
    моделът е изял ⟦7⟧, препратката просто изчезва и никой не забелязва —
    затова се брои поучение по поучение срещу work/units/.

 2. ИЗПРАВНОСТ на адресите. Всяка връзка трябва да носи опашката
    „&bg~utfcs" (иначе azbyka.ru отваря руския текст, не българския с
    успореден църковнославянски) и да сочи код, който познаваме.
    С --online се проверява и че адресът наистина отваря страница.

 3. НАДПИСИТЕ. Никъде не бива да е останала руска или дълга форма на
    съкращение („Мф.", „Мат.", „Марк.", „Лук.", „Иоан.") — те се разминават
    с късите, които слагаме по машинен път.

 4. ЦЕЛОСТ на разметката. Никаква останала запушалка ⟦…⟧, сдвоени тагове,
    и всяка препратка към бележка да сочи бележка, която съществува.

 5. АДРЕСИТЕ на поученията. Без сблъсъци и без дупки в аритметичните
    отрязъци — ако липсва „pent 17:3", значи някое поучение се е загубило.

Вход:
  ../../../assets/db/teofan.db
  ../work/units/*.json          за сверка срещу оригинала

Употреба:
  python3 04_verify.py
  python3 04_verify.py --online          проверява и че адресите отварят
  python3 04_verify.py --online --limit 40
"""

import argparse
import glob
import json
import os
import re
import sqlite3
import sys
import time

from common import BOOK_BG

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.dirname(SCRIPT_DIR)
WORK_DIR = os.path.join(PROJECT_DIR, 'work')
UNITS_DIR = os.path.join(WORK_DIR, 'units')
REPO_ROOT = os.path.dirname(os.path.dirname(PROJECT_DIR))
DEFAULT_DB = os.path.join(REPO_ROOT, 'assets', 'db', 'teofan.db')

REQUIRED_TAIL = '&amp;bg~utfcs'
RE_HREF = re.compile(r'href="([^"]+)"')
RE_LEFTOVER = re.compile(r'⟦[^⟧]*⟧')
RE_NOTE_REF = re.compile(r'data-note="([^"]+)"')
RE_TAG = re.compile(r'</?(\w+)')
# Руските и дългите форми, които не бива да остават. Търсят се като ЦЯЛА
# дума пред точка — „Мат." е грешка, но „Матей" в текста е съвсем редно.
RE_BAD_ABBREV = re.compile(
    r'(?<![А-Яа-я])(Мф|Мат|Марк|Лук|Иоан|Быт|Исх|Суд|Прит|Флп|Фес|Апок)\.')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--db', default=DEFAULT_DB)
    ap.add_argument('--online', action='store_true',
                    help='провери и че адресите отварят страница')
    ap.add_argument('--limit', type=int,
                    help='при --online: колко адреса да провери')
    args = ap.parse_args()

    if not os.path.exists(args.db):
        sys.exit('Няма %s — пусни 03_build_db.py.' % args.db)

    db = sqlite3.connect(args.db)
    thoughts = {r[0]: r for r in db.execute(
        'SELECT id, kind, key, level, body FROM thoughts')}
    notes = {r[0] for r in db.execute('SELECT key FROM notes')}
    беди = []

    # ── 1. Наличност: всяка запушалка от оригинала да е станала таг ────────
    очаквани = {}
    for path in glob.glob(os.path.join(UNITS_DIR, '*.json')):
        unit = json.load(open(path, encoding='utf-8'))
        очаквани[unit['index']] = {
            'bible': sum(1 for a in unit['atoms'] if a['kind'] == 'bible'),
            'footnote': sum(1 for a in unit['atoms'] if a['kind'] == 'footnote'),
        }

    връзки_общо = бележки_общо = 0
    for tid, (_, kind, key, _, body) in sorted(thoughts.items()):
        има = len(RE_HREF.findall(body))
        има_бел = len(RE_NOTE_REF.findall(body))
        връзки_общо += има
        бележки_общо += има_бел
        want = очаквани.get(tid)
        if want is None:
            беди.append('%03d: няма съответствие в work/units/' % tid)
            continue
        if има != want['bible']:
            беди.append('%03d: %d връзки в базата, %d в оригинала'
                        % (tid, има, want['bible']))
        if има_бел != want['footnote']:
            беди.append('%03d: %d препратки към бележки, %d в оригинала'
                        % (tid, има_бел, want['footnote']))

    # ── 2. Изправност на адресите ─────────────────────────────────────────
    адреси = []
    for tid, (_, _, _, _, body) in sorted(thoughts.items()):
        for href in RE_HREF.findall(body):
            адреси.append((tid, href))
            if not href.endswith(REQUIRED_TAIL):
                беди.append('%03d: адрес без опашката %s → %s'
                            % (tid, REQUIRED_TAIL, href))
            code = href.split('?', 1)[1].split('&', 1)[0] if '?' in href else ''
            book = code.partition('.')[0]
            if book not in BOOK_BG:
                беди.append('%03d: непозната библейска книга „%s" в %s'
                            % (tid, book, href))

    # ── 3. Надписите ──────────────────────────────────────────────────────
    for tid, (_, _, _, _, body) in sorted(thoughts.items()):
        for m in RE_BAD_ABBREV.finditer(body):
            беди.append('%03d: остаряло съкращение „%s." → %s'
                        % (tid, m.group(1),
                           body[max(0, m.start() - 30):m.end() + 10]))

    # ── 4. Цялост на разметката ───────────────────────────────────────────
    for tid, (_, _, _, _, body) in sorted(thoughts.items()):
        for m in RE_LEFTOVER.finditer(body):
            беди.append('%03d: останала запушалка %s' % (tid, m.group(0)))
        депо = {}
        for m in re.finditer(r'<(/?)(\w+)', body):
            депо[m.group(2)] = депо.get(m.group(2), 0) + (-1 if m.group(1) else 1)
        for tag, n in депо.items():
            if n != 0 and tag not in ('br', 'img'):
                беди.append('%03d: несдвоен таг <%s> (разлика %d)'
                            % (tid, tag, n))
        for key in RE_NOTE_REF.findall(body):
            if key not in notes:
                беди.append('%03d: препратка към несъществуваща бележка %s'
                            % (tid, key))

    # ── 5. Адресите на поученията ─────────────────────────────────────────
    видени = {}
    for tid, (_, kind, key, _, _) in thoughts.items():
        видени.setdefault((kind, key), []).append(tid)
    for адрес, ids in sorted(видени.items()):
        if len(ids) > 1:
            беди.append('адрес %s %s се дели от записи %s'
                        % (адрес[0], адрес[1], ids))

    липсващи = []
    for offset in range(-70, 57):
        if ('pascha', str(offset)) not in видени:
            липсващи.append('pascha %d' % offset)
    for week in range(2, 32):
        for day in range(1, 7):
            if ('pent', '%d:%d' % (week, day)) not in видени:
                липсващи.append('pent %d:%d' % (week, day))
    for sunday in range(2, 31):
        if ('pent', 'sunday:%d' % sunday) not in видени:
            липсващи.append('pent sunday:%d' % sunday)

    # ── Отчет ─────────────────────────────────────────────────────────────
    print('=' * 66)
    print('поучения: %d | връзки: %d | препратки към бележки: %d | бележки: %d'
          % (len(thoughts), връзки_общо, бележки_общо, len(notes)))
    цитати, без_реф = db.execute(
        'SELECT count(*), sum(ref IS NULL) FROM quotes').fetchone()
    print('цитати: %d (от тях %d без препратка)' % (цитати, без_реф or 0))

    if липсващи:
        print()
        print('адреси без поучение: %d — очаквано е да има такива, книгата '
              'не покрива всеки ден от всяка година' % len(липсващи))
        print('  ' + ', '.join(липсващи[:14])
              + (' …' if len(липсващи) > 14 else ''))

    print()
    if беди:
        print('НАМЕРЕНИ ПРОБЛЕМИ: %d' % len(беди))
        for line in беди[:40]:
            print('  ' + line)
        if len(беди) > 40:
            print('  … и още %d' % (len(беди) - 40))
    else:
        print('Всички проверки минаха.')

    # ── По желание: наистина ли отварят адресите ──────────────────────────
    if args.online:
        import requests
        уникални = sorted({h for _, h in адреси})
        if args.limit:
            уникални = уникални[:args.limit]
        print()
        print('проверявам %d различни адреса на живо…' % len(уникални))
        счупени = []
        s = requests.Session()
        for i, href in enumerate(уникални, 1):
            url = href.replace('&amp;', '&')
            try:
                r = s.head(url, timeout=20, allow_redirects=True)
                if r.status_code >= 400:
                    r = s.get(url, timeout=20)
                if r.status_code >= 400:
                    счупени.append('%s → %d' % (url, r.status_code))
            except Exception as e:
                счупени.append('%s → %s' % (url, e))
            if i % 25 == 0:
                print('  %d/%d' % (i, len(уникални)))
            time.sleep(0.3)          # да не удряме azbyka.ru
        print('счупени адреси: %d' % len(счупени))
        for line in счупени[:20]:
            print('  ' + line)

    db.close()
    sys.exit(1 if беди else 0)


if __name__ == '__main__':
    main()
