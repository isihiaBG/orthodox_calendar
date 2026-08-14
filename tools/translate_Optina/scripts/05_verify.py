#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
05_verify.py — Стъпка 5 (МЕХАНИЧНА): проверява сглобената optina.db.

Гледа четири неща, всяко от които е тихо чупливо:

 1. ПОКРИТИЕ — всеки от 366-те дни има точно по една сентенция, и нито един
    ден не е останал празен. Празен ден се вижда чак когато потребителят
    отвори точно него.
 2. ЦЯЛОСТ НА ПРЕВОДА — броят на запушалките и на кавичките «…» съвпада с
    руския оригинал, и преводът не е забележимо по-къс. Съкращаването е
    най-коварното, защото текстът изглежда наред.
 3. РАЗМЕТКА — всеки таг се затваря, няма останали ⟦…⟧, и класовете са само
    тези, които четецът рисува.
 4. РАВНОВЕСИЕ — как са разпределени старците и темите, за да се види с
    един поглед дали подборът не се е изкривил.

С --online се проверява и че препратките към Писанието се отварят. Бавно е;
не се пуска всеки път.

Употреба:
  python3 05_verify.py
  python3 05_verify.py --online
  python3 05_verify.py --day 08-15        # показва един ден както е в базата
"""

import argparse
import html
import os
import re
import sqlite3
import sys
from collections import Counter

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.dirname(SCRIPT_DIR)
REPO_ROOT = os.path.dirname(os.path.dirname(PROJECT_DIR))
DEFAULT_DB = os.path.join(REPO_ROOT, 'assets', 'db', 'optina.db')

DAYS_IN_MONTH = [31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
ALL_DAYS = ['%02d-%02d' % (m, d)
            for m in range(1, 13) for d in range(1, DAYS_IN_MONTH[m - 1] + 1)]

ALLOWED_TAGS = {'p', 'span', 'a', 'em', 'sup'}
ALLOWED_CLASSES = {'cite', 'source'}
RE_TAG = re.compile(r'<(/?)([a-z]+)([^>]*)>')
RE_CLASS = re.compile(r'class="([^"]*)"')
RE_QUOTE = re.compile(r'«[^«»]{2,}»')


def check(db, problems, notes):
    rows = db.execute(
        'SELECT id, day, elder, body, src_id, src_topic_ru, src_body_ru'
        ' FROM sayings ORDER BY id').fetchall()
    notes.append('записи: %d' % len(rows))

    # 1. Покритие
    days = [r[1] for r in rows if r[1]]
    missing = [d for d in ALL_DAYS if d not in set(days)]
    dup = [d for d, n in Counter(days).items() if n > 1]
    notes.append('дни с текст: %d от 366 | в запас: %d'
                 % (len(set(days)), len(rows) - len(days)))
    if missing:
        problems.append('дни без сентенция (%d): %s'
                        % (len(missing), ', '.join(missing[:15])))
    if dup:
        problems.append('дни с повече от една: %s' % ', '.join(dup))
    bad = [d for d in days if d not in ALL_DAYS]
    if bad:
        problems.append('дати, които не съществуват: %s' % ', '.join(bad))

    # 2. Цялост на превода
    short = []
    for sid, day, elder, body, src_id, topic, ru in rows:
        text = re.sub(r'<[^>]+>', '', body)
        text = html.unescape(text)
        text = text.replace('прп. ' + elder, '').strip()
        if ru and len(text) < 0.70 * len(ru):
            short.append('%s (%d знака срещу %d)' % (src_id, len(text),
                                                     len(ru)))
        if ru and ru.count('«') == ru.count('»'):
            want = len(RE_QUOTE.findall(ru))
            got = len(RE_QUOTE.findall(text))
            if want != got:
                problems.append('%s: цитати в «…» — %d в оригинала, %d в '
                                'превода' % (src_id, want, got))
    if short:
        problems.append('съкратени преводи (%d): %s'
                        % (len(short), '; '.join(short[:8])))

    # 3. Разметка
    for sid, day, elder, body, src_id, topic, ru in rows:
        if '⟦' in body or '⟧' in body:
            problems.append('%s: останала запушалка в тялото' % src_id)
        stack = []
        for closing, tag, attrs in RE_TAG.findall(body):
            if tag not in ALLOWED_TAGS:
                problems.append('%s: непознат таг <%s>' % (src_id, tag))
            for cls in RE_CLASS.findall(attrs):
                for c in cls.split():
                    if c not in ALLOWED_CLASSES:
                        problems.append('%s: непознат клас „%s"'
                                        % (src_id, c))
            if closing:
                if not stack or stack.pop() != tag:
                    problems.append('%s: незатворен <%s>' % (src_id, tag))
            elif not attrs.endswith('/'):
                stack.append(tag)
        if stack:
            problems.append('%s: остана отворен <%s>' % (src_id, stack[-1]))
        if '<p class="source">' not in body:
            problems.append('%s: няма ред с името на стареца' % src_id)

    # 4. Равновесие
    elders = Counter(r[2] for r in rows)
    notes.append('старци: ' + ', '.join('%s %d' % kv
                                        for kv in elders.most_common()))
    topics = Counter(r[5] for r in rows)
    notes.append('теми: %d различни; повторени: %s'
                 % (len(topics),
                    ', '.join(t for t, n in topics.items() if n > 1) or 'няма'))
    lens = sorted(len(re.sub(r'<[^>]+>', '', r[3])) for r in rows)
    notes.append('дължини: медиана %d, най-къса %d, най-дълга %d'
                 % (lens[len(lens) // 2], lens[0], lens[-1]))

    ncites = db.execute('SELECT COUNT(*) FROM quotes').fetchone()[0]
    noref = db.execute('SELECT COUNT(*) FROM quotes WHERE ref IS NULL'
                       ).fetchone()[0]
    notes.append('цитати в указателя: %d (без препратка: %d)' % (ncites,
                                                                 noref))
    return rows


def check_online(db, problems, notes):
    import urllib.request
    refs = [r[0] for r in db.execute(
        'SELECT DISTINCT ref FROM quotes WHERE ref IS NOT NULL')]
    notes.append('проверявам %d препратки онлайн…' % len(refs))
    bad = []
    for ref in refs:
        url = 'https://azbyka.ru/biblia/?%s&bg~utfcs' % ref
        try:
            req = urllib.request.Request(url, method='HEAD',
                                         headers={'User-Agent': 'curl/8'})
            with urllib.request.urlopen(req, timeout=20) as r:
                if r.status >= 400:
                    bad.append('%s (%d)' % (ref, r.status))
        except Exception as e:
            bad.append('%s (%s)' % (ref, e))
    if bad:
        problems.append('препратки, които не се отварят (%d): %s'
                        % (len(bad), ', '.join(bad[:10])))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--db', default=DEFAULT_DB)
    ap.add_argument('--online', action='store_true')
    ap.add_argument('--day', help='показва един ден, както е в базата')
    args = ap.parse_args()

    if not os.path.exists(args.db):
        sys.exit('Няма %s — пусни 04_build_db.py.' % args.db)
    db = sqlite3.connect(args.db)

    if args.day:
        row = db.execute('SELECT elder, src_topic_ru, body, src_body_ru'
                         ' FROM sayings WHERE day=?', (args.day,)).fetchone()
        if not row:
            sys.exit('За %s няма сентенция.' % args.day)
        print('%s · прп. %s · %s\n' % (args.day, row[0], row[1]))
        print(row[2])
        print('\n--- оригиналът ---\n%s' % row[3])
        return

    problems, notes = [], []
    check(db, problems, notes)
    if args.online:
        check_online(db, problems, notes)

    print('=' * 64)
    for n in notes:
        print(n)
    print('-' * 64)
    if problems:
        print('ПРОБЛЕМИ: %d' % len(problems))
        for p in problems:
            print('  · %s' % p)
        sys.exit(1)
    print('Всичко е наред.')


if __name__ == '__main__':
    main()
