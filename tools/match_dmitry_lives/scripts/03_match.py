#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Засечка между output/dmitry_titles.csv и output/saints.csv — по (ден +
прилика на име), само СРЕЩУ кандидатите на СЪЩИЯ ден (виж уговорката в
разговора: не глобален праг през целия корпус).

За всеки църковен ден (mm_dd):
  1. взимат се всички жития на Димитрий Ростовски и всички saints за деня;
  2. смята се прилика между всяка двойка (нормализиран текст, виж
     normalize());
  3. алчно (greedy) сдвояване — най-добрата двойка първо, после следващата
     най-добра измежду останалите свободни, докато има какво да се сдвои.
     Денят рядко има повече от шепа кандидати от всяка страна, тъй че
     алчно е напълно достатъчно (и по-лесно за проверка от Унгарски
     алгоритъм) — не е нужна допълнителна зависимост (scipy).

Изходът е ЕДИН ред за всяко от 1155-те жития на Димитрий Ростовски (не за
saints — целта е да запълним dmitry_num в saints, тръгвайки от
Димитрий Ростовски като водеща страна): предложен светия + процент, за
ръчен преглед. Скриптът НЕ решава нищо сам — само нарежда кандидатите.

Изход: output/match_review.csv, plus разпределение на процентите в конзолата.

Пуска се без аргументи (изисква вече направени 01_ и 02_):
    python3 03_match.py
"""

import csv
import difflib
import os
import re
from collections import defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
OUT_DIR = os.path.join(os.path.dirname(HERE), 'output')
DMITRY_CSV = os.path.join(OUT_DIR, 'dmitry_titles.csv')
SAINTS_CSV = os.path.join(OUT_DIR, 'saints.csv')
OUT_CSV = os.path.join(OUT_DIR, 'match_review.csv')

# Рангови/обръщателни съкращения — премахват се КЪДЕТО и да се срещнат
# (не само в началото), защото и в двата източника могат да стоят посред
# изречение при съборни памети ("Мчч. Иполит ... и прочите двадесет
# мъченици"). Списъкът е събран от реални форми в двата CSV-та.
RANK_WORDS = [
    'препмчц', 'препмч', 'свщмчц', 'свщмч', 'сщмч', 'первомч', 'первомчц',
    'прмчц', 'прмч', 'мчца', 'мчцц', 'мчц', 'мчч', 'мчк', 'мч',
    'блгв', 'блж', 'прав', 'прор', 'преп', 'прп', 'свт', 'свв', 'св',
    'апп', 'ап', 'еп', 'архиеп', 'митр', 'патр', 'презв', 'диак',
    'чудотв', 'безср', 'девица', 'дева', 'кн', 'царица', 'царь',
]
RE_RANK = re.compile(
    r'\b(?:' + '|'.join(RANK_WORDS) + r')\.?\b', re.IGNORECASE)
RE_PAREN = re.compile(r'\([^)]*\)')
RE_PUNCT = re.compile(r'[.,†«»„“"\'\-–—]')
RE_WS = re.compile(r'\s+')

# Литургийни маркери, не самостоятелни светии — огледално на NOT_THE_FEAST
# в tools/calendar_gen/extract_rules.py. Оставени в saints.csv (реални
# редове от календара), но не бива да участват като КАНДИДАТИ в засечката:
# алчното сдвояване им лепи произволно житие, щом денят изчерпи истинските
# кандидати ("Отдание на Богоявление" вместо истинския пропуснат светия).
RE_LITURGICAL_MARKER = re.compile(
    r'Предпразненство|Попразненство|Отдание|Навечерие'
    r'|^Събота (преди|след)|^Неделя (преди|след)'
    # Страстната седмица и Пасха — движими литургийни дни в saints
    # (гражданските им дати попадат в март/април за 2026 стар стил),
    # огледално на PASCHA в tools/calendar_gen/classify.py.
    r'|Велик(?:и|а|ата)\s+(?:понеделник|вторник|сряда|четвъртък|петък|събота)'
    r'|Светл(?:а|и|ата)\s+(?:седмиц|понеделник|вторник|сряда|четвъртък|петък|събота)'
    r'|ВЕЛИКДЕН'
    # Постните начала, задушниците и Петдесетница/Св. Дух като ЧИСТИ дати
    # без биография — Димитрий Ростовски няма глава за "начало на пост".
    # Внимание: НЕ анкирано широко по "Петдесетница" — тя се среща и в
    # скоби на реални светии ("преходно празнуване … след Петдесетница"),
    # които не бива да се изключват.
    r'|Начало на .*пост|задушница|Преполовение'
    r'|^ДЕН НА СВЕТА ТРОИЦА|^СВЕТИ ДУХ$', re.IGNORECASE)


def normalize(name: str) -> str:
    s = name.lower()
    s = RE_PAREN.sub(' ', s)          # (†379), (Василовден) и пр.
    s = RE_RANK.sub(' ', s)
    s = RE_PUNCT.sub(' ', s)
    s = RE_WS.sub(' ', s).strip()
    return s


def score(a: str, b: str) -> float:
    return difflib.SequenceMatcher(None, normalize(a), normalize(b)).ratio()


def load_dmitry():
    with open(DMITRY_CSV, encoding='utf-8', newline='') as f:
        return list(csv.DictReader(f, delimiter='|', quotechar="'"))


def load_saints():
    with open(SAINTS_CSV, encoding='utf-8', newline='') as f:
        return list(csv.DictReader(f, delimiter='|', quotechar="'"))


def match_day(dmitry_rows, saint_rows):
    """Алчно сдвояване вътре в един ден. Връща list[(dmitry_row, saint_row|None, score)]."""
    pairs = []
    for dr in dmitry_rows:
        for sr in saint_rows:
            pairs.append((score(dr['title'], sr['name']), dr, sr))
    pairs.sort(key=lambda p: -p[0])

    used_dmitry, used_saint = set(), set()
    assigned = {}
    for sc, dr, sr in pairs:
        dk, sk = dr['num'], sr['id']
        if dk in used_dmitry or sk in used_saint:
            continue
        used_dmitry.add(dk)
        used_saint.add(sk)
        assigned[dk] = (sr, sc)

    out = []
    for dr in dmitry_rows:
        sr, sc = assigned.get(dr['num'], (None, 0.0))
        out.append((dr, sr, sc))
    return out


def main():
    dmitry = load_dmitry()
    saints = load_saints()

    by_day_dmitry = defaultdict(list)
    for r in dmitry:
        by_day_dmitry[r['mm_dd']].append(r)
    by_day_saints = defaultdict(list)
    excluded_markers = 0
    for r in saints:
        if RE_LITURGICAL_MARKER.search(r['name']):
            excluded_markers += 1
            continue
        by_day_saints[r['mm_dd']].append(r)

    rows = []
    for mm_dd, drows in by_day_dmitry.items():
        srows = by_day_saints.get(mm_dd, [])
        for dr, sr, sc in match_day(drows, srows):
            rows.append({
                'mm_dd': mm_dd,
                'dmitry_num': dr['num'],
                'dmitry_title': dr['title'],
                'saint_id': sr['id'] if sr else '',
                'saint_name': sr['name'] if sr else '',
                'score': f'{sc:.3f}',
                'day_dmitry_count': len(drows),
                'day_saints_count': len(srows),
                'decision': '',
            })

    rows.sort(key=lambda r: (r['mm_dd'], -float(r['score'])))

    with open(OUT_CSV, 'w', encoding='utf-8', newline='') as f:
        w = csv.DictWriter(f, fieldnames=[
            'mm_dd', 'dmitry_num', 'dmitry_title', 'saint_id', 'saint_name',
            'score', 'day_dmitry_count', 'day_saints_count', 'decision',
        ], delimiter='|', quotechar="'")
        w.writeheader()
        w.writerows(rows)

    # Разпределение по прагове — за да се вижда къде пада разумната
    # граница между "явно вярно" и "иска очи", БЕЗ да се решава тук.
    buckets = [(0.90, 1.01), (0.75, 0.90), (0.50, 0.75), (0.01, 0.50), (0.0, 0.01)]
    print('=' * 60)
    print(f'литургийни маркери, изключени от кандидатите: {excluded_markers}')
    print(f'жития на Димитрий Ростовски: {len(dmitry)}')
    print(f'от тях без чифт (денят има ПОВЕЧЕ жития, отколкото saints '
          f'кандидати, или (само 29.02) saints изобщо няма ред за деня): '
          f'{sum(1 for r in rows if r["saint_id"] == "")}')
    print('разпределение по прилика:')
    for lo, hi in buckets:
        n = sum(1 for r in rows if lo <= float(r['score']) < hi)
        print(f'  [{lo:.2f}, {hi:.2f}): {n}')
    print(f'→ {OUT_CSV}')


if __name__ == '__main__':
    main()
