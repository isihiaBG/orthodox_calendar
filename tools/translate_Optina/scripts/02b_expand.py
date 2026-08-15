#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
02b_expand.py — Стъпка 2б (МЕХАНИЧНА, безплатна): нарежда ОПАШКА за превод от
всичко годно, което още не е преведено.

За какво е. 400-те избрани покриват годината, но резервът за подмяна е само
34. Тази стъпка прави резерва дълбок: превежда се колкото стигнат парите, а
всичко преведено влиза в базата с `day = NULL` и чака да замени сентенция,
която при преглед се окаже неподходяща.

⚠ ПОДРЕДБАТА Е ПО КРЪГОВЕ, НЕ ПО ОЦЕНКА. Това е цялата хитрост тук.
Опашка, наредена само по оценка, изчерпва парите в няколко богати дяла:
„Смирение" има десетки годни, „Кротост" — три. Спре ли преводът по средата
(а той ще спре — бюджетът е малък), резервът излиза дълбок на пет места и
празен навсякъде другаде.

Затова се върви на кръгове по ДЪЛБОЧИНА:

    кръг 1   по още една сентенция от всяка тема
    кръг 2   по още една  (тоест две на тема)
    кръг 3   по още две   (четири на тема)
    кръг 4   по още четири
    …

Всеки кръг удвоява дълбочината. Където и да свърши преводът, разпределението
е равномерно: навсякъде по N, някъде по N+1. Вътре в кръга редът е по оценка,
тъй че първо върви по-доброто.

Твърдите правила НЕ се пипат — лични обръщения, разговор, назован събеседник,
роднина, откъслечно начало, манастирски речник и изключените дялове остават
както са в 02_select.py. Разхлабва се САМО таванът на дължината: за резерв
върши работа и по-дълго поучение, стига да не е цяло писмо.

Вход:   ../work/quotes.json       (от 01_extract.py)
        ../work/selected.json     (от 02_select.py — да не ги дублираме)
        ../work/translated/       (вече преведеното се прескача)
Изход:  ../work/expand.json       опашката, готова за 03_translate_deepseek.py

Употреба:
  python3 02b_expand.py                    # таван 1000 знака
  python3 02b_expand.py --max-len 1500
  python3 02b_expand.py --limit 300        # само първите N от опашката
"""

import argparse
import glob
import json
import os
import sys
from collections import Counter, defaultdict

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.dirname(SCRIPT_DIR)
WORK_DIR = os.path.join(PROJECT_DIR, 'work')

sys.path.insert(0, SCRIPT_DIR)
_select = __import__('02_select')
acceptable, score = _select.acceptable, _select.score


def rounds(by_topic):
    """Темите → опашка по кръгове с удвояваща се дълбочина.

    Връща списък от (номер на кръг, откъс). Кръг 1 взима по едно от всяка
    тема, кръг 2 — още по едно, кръг 3 — още по две, и така нататък.
    """
    out, taken, depth, rnd = [], Counter(), 1, 1
    while True:
        added = 0
        # Темите се обхождат по силата на най-добрия си останал откъс, за да
        # тръгне кръгът от по-стойностното. Вътре в темата — по оценка.
        order = sorted(by_topic,
                       key=lambda t: -(by_topic[t][taken[t]]['score']
                                       if taken[t] < len(by_topic[t]) else -1e9))
        for topic in order:
            lst = by_topic[topic]
            while taken[topic] < len(lst) and taken[topic] < depth:
                out.append((rnd, lst[taken[topic]]))
                taken[topic] += 1
                added += 1
        if not added:
            return out
        rnd += 1
        depth = depth * 2 if depth > 1 else 2


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--max-len', type=int, default=1000,
                    help='таван в знаци; над него са цели писма')
    ap.add_argument('--limit', type=int)
    args = ap.parse_args()

    quotes = json.load(open(os.path.join(WORK_DIR, 'quotes.json'),
                            encoding='utf-8'))
    selected = {q['id'] for q in json.load(
        open(os.path.join(WORK_DIR, 'selected.json'), encoding='utf-8'))}
    done = {os.path.basename(f)[:-5]
            for f in glob.glob(os.path.join(WORK_DIR, 'translated', '*.json'))}

    manual_path = os.path.join(WORK_DIR, 'manual_select.json')
    manual = (json.load(open(manual_path, encoding='utf-8'))
              if os.path.exists(manual_path) else {})
    dropped = set(manual.get('drop', []))

    by_topic, skipped = defaultdict(list), Counter()
    for q in quotes:
        if q['id'] in done or q['id'] in selected:
            skipped['вече преведени или в календара'] += 1
            continue
        if q['id'] in dropped:
            skipped['изхвърлени на ръка'] += 1
            continue
        why = acceptable(q, args.max_len)
        if why:
            skipped[why] += 1
            continue
        q['score'] = score(q)
        by_topic[q['topic_ru']].append(q)
    for lst in by_topic.values():
        lst.sort(key=lambda q: -q['score'])

    queue = rounds(by_topic)
    if args.limit:
        queue = queue[:args.limit]

    print('=' * 64)
    print('откъси общо: %d' % len(quotes))
    for why, n in skipped.most_common():
        print('   %-46s %5d' % (why + ':', n))
    print('в опашката: %d, от %d теми' % (len(queue), len(by_topic)))
    print()
    print('%-6s %8s %10s %14s' % ('кръг', 'бройки', 'до тук', 'знаци (хил.)'))
    per = Counter(r for r, _ in queue)
    run = 0
    for r in sorted(per):
        run += per[r]
        chars = sum(len(q['body_ru']) for rr, q in queue if rr == r)
        print('%-6d %8d %10d %14.0f' % (r, per[r], run, chars / 1000))

    out = []
    for r, q in queue:
        rec = {k: q[k] for k in ('id', 'vol', 'src', 'src_part', 'src_title',
                                 'topic_ru', 'elder', 'body_ru', 'atoms',
                                 'notes', 'also_in', 'flags')}
        rec['day'] = None            # резервите нямат ден — виж 04_build_db.py
        rec['score'] = q['score']
        rec['round'] = r
        out.append(rec)
    path = os.path.join(WORK_DIR, 'expand.json')
    with open(path, 'w', encoding='utf-8') as fh:
        json.dump(out, fh, ensure_ascii=False, indent=1)
    print('\n→ %s' % path)


if __name__ == '__main__':
    main()
