#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Търси ВЪТРЕШНИ дублажи в saints — един и същ светия/празник, записан
двукратно на СЪЩИЯ ден с малко по-различен текст (най-вероятно защото
идва от различни group_code — ECUMENICAL/RU/BG/... — сглобени без
взаимна дедупликация). Забелязано от потребителя по повод num=19
("Кръщение Господне") при прегледа на януари — макар че конкретно ТОЗИ
случай, при проверка, излезе дубъл от страната на Димитрий Ростовски, не
на saints. Скриптът е точно за да не гадаем, а да видим къде РЕАЛНО има
такива вътре в saints.

Ползва normalize()/score() от 03_match.py — същата мярка, не нова.

Изход: конзолен списък двойки над прага, сортиран по ден — за ръчен
преглед, НЕ автоматично премахване (сливането на два реда в saints иска
преценка коя версия/кой slug да остане).
"""
import csv
import os
import sys
from collections import defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from importlib import import_module
match = import_module('03_match')

OUT_DIR = os.path.join(os.path.dirname(HERE), 'output')
SAINTS_CSV = os.path.join(OUT_DIR, 'saints.csv')

THRESHOLD = 0.55  # под тук почти никога не е реален дубъл (виж калибровката в конзолата)


def main():
    with open(SAINTS_CSV, encoding='utf-8', newline='') as f:
        rows = list(csv.DictReader(f, delimiter='|', quotechar="'"))

    by_day = defaultdict(list)
    for r in rows:
        if match.RE_LITURGICAL_MARKER.search(r['name']):
            continue
        by_day[r['mm_dd']].append(r)

    pairs = []
    for mm_dd, day_rows in by_day.items():
        for i in range(len(day_rows)):
            for j in range(i + 1, len(day_rows)):
                a, b = day_rows[i], day_rows[j]
                sc = match.score(a['name'], b['name'])
                if sc >= THRESHOLD:
                    pairs.append((sc, mm_dd, a, b))

    pairs.sort(key=lambda p: (p[1], -p[0]))
    print(f'кандидати за дублаж (праг {THRESHOLD}): {len(pairs)}')
    print('=' * 60)
    for sc, mm_dd, a, b in pairs:
        print(f'{mm_dd}  {sc:.3f}')
        print(f'   id={a["id"]:>5} [{a["group_code"]:10}] {a["name"]}')
        print(f'   id={b["id"]:>5} [{b["group_code"]:10}] {b["name"]}')


if __name__ == '__main__':
    main()
