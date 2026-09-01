#!/usr/bin/env python3
"""Разпределя записите от calendar_old.db по трите пласта и пише отчет.

НИЩО не променя. Тук се допускат повечето грешки, затова отчетът се гледа
пръв — преди изобщо да сме пипнали база.

Видове:
  fixed   — привързан към църковната дата (мести се с −13)
  pascha  — привързан към Пасха (остава на същата гражданска дата)
  anchor  — подвижен спрямо НЕПОДВИЖЕН празник (пресмята се наново)
"""
import csv
import os
import re
import sqlite3
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', '..'))
OLD = os.path.join(HERE, 'input', 'db', 'calendar_old.db')

# Пасхалният кръг: тези думи говорят за подвижен празник.
PASCHA = re.compile(
    r'Велик(?:и|а|ата)\s+(?:пост|понеделник|вторник|сряда|четвъртък|петък|събота)'
    r'|Светл(?:а|и|ата)\s+(?:седмиц|понеделник|вторник|сряда|четвъртък|петък|събота)'
    r'|ВЕЛИКДЕН|Пасха'
    r'|Петдесетниц|Троиц|Възнесение|Кръстопоклонн'
    r'|Сирн(?:а|и)|Месопустн|Всички светии|Всех свет'
    r'|седмица от Велики(?:я)? пост'
    r'|недел\S*\s+(?:\S+\s+){0,3}мироносиц'  # САМО "неделя … мироносици"
    r'|Вход Господ\S*\s+в\s+\S*ерусалим'  # Цветница/Връбница
    r'|Неделя на ', re.I)

# Празникът е изписан с главни букви; „Обновление на храма „Възкресение
# Христово“ в Йерусалим“ е неподвижен и не бива да се хваща.
PASCHA_CS = re.compile(r'ВЪЗКРЕСЕНИЕ')

# Подвижен спрямо неподвижен празник — „събота преди/след Богоявление" и пр.
ANCHOR = re.compile(
    r'(събота|неделя)\s+(преди|след)\s+'
    r'(Богоявление|Рождество|Въздвижение|Просвещение)', re.I)


def key_name(name: str) -> str:
    """Името във вид, годен за КЛЮЧ в overrides.csv / known_movable.csv.

    ⚠ 736 от 1656-те имена в семето носят НЕРАЗБИВАЕМ интервал (U+00A0) —
    остатък от източника, невидим при четене и невъзможен за напипване при
    ръчно вписване в CSV. Дотук ключът се сравняваше буквално, тъй че ред,
    написан с обикновен интервал, просто НЕ съвпадаше: правилото се
    подминаваше МЪЛЧАЛИВО, без грешка и без следа в отчета. Загубено време,
    01.09.2026, върху „Вмч. Георги Победоносец († 303) (Гергьовден)".

    Затова и двете страни минават оттук. Замяната е безопасна за заварените
    редове: обикновеният интервал остава какъвто е, а ключ, писан с U+00A0
    от двете страни, продължава да съвпада — само вече след свеждане.
    """
    return (name or '').replace(' ', ' ')


def classify(name: str) -> str:
    name = name or ''
    if ANCHOR.search(name):
        return 'anchor'
    if PASCHA.search(name) or PASCHA_CS.search(name):
        return 'pascha'
    return 'fixed'


def load_known_movable():
    """Записи, чиято подвижност НЕ е написана никъде в текста им — външно
    знание, потвърдено на ръка, изразено с езика от rules.py. Допълва
    overrides.csv (там поправяме сгрешена класификация ПО текста; тук
    вписваме правило, което текстът изобщо не съдържа). Има превес над
    regex-а на classify() — не се насилва в pascha/anchor, защото по
    природа може да е и двете (напр. Паисий Светогорец е чиста Пасхална
    верига, а "неделя преди Архангеловден" е котва към неподвижна дата);
    build.py смята и двата вида еднакво, през rules.resolve()."""
    path = os.path.join(HERE, 'known_movable.csv')
    if not os.path.exists(path):
        return {}
    out = {}
    with open(path, encoding='utf-8') as f:
        for row in csv.DictReader(f):
            out[(row['date'], key_name(row['name']))] = row['rule']
    return out


def load_overrides():
    """Ключът е (date, name), не `id` — id е автоувеличаващо се число в
    calendar_old.db и се размества при всяка редакция на saints (добавен
    или изтрит ред). (date, name) е стабилно, защото описва самото
    съдържание, което classify() и без друго чете, и е доказано уникално
    по цялата таблица (виж README)."""
    path = os.path.join(HERE, 'overrides.csv')
    if not os.path.exists(path):
        return {}
    out = {}
    with open(path, encoding='utf-8') as f:
        for row in csv.DictReader(f):
            if row.get('table') == 'saints':
                out[(row['date'], key_name(row['name']))] = row['kind']
    return out


def main():
    if not os.path.exists(OLD):
        sys.exit(f'няма {OLD}')
    # САМО за четене: старата база е източникът за всичко и не бива да
    # може да бъде променена дори по невнимание.
    db = sqlite3.connect(f'file:{OLD}?mode=ro', uri=True)
    over = load_overrides()

    known = load_known_movable()
    buckets = {'fixed': [], 'pascha': [], 'anchor': [], 'manual': [], 'skip': []}
    for sid, date, name in db.execute('select id,date,name from saints order by date'):
        k = (date, key_name(name))
        kind = 'manual' if k in known else (
            over.get(k) or classify(name))
        buckets[kind].append((sid, date, name))

    total = sum(len(v) for v in buckets.values())
    print(f'saints: {total} записа  '
          f'(ръчни решения: {len(over)}, известни подвижни: {len(known)})')
    for k in ('fixed', 'pascha', 'anchor', 'manual', 'skip'):
        print(f'  {k:7} {len(buckets[k]):5}')
    print()
    if buckets['skip']:
        print('--- skip (изключени от изхода — виж overrides.csv защо) ---')
        for sid, date, name in buckets['skip']:
            print(f'  {sid:5} {date} | {(name or "")[:88]}')
        print()

    for k in ('pascha', 'anchor'):
        print(f'--- {k} ---')
        for sid, date, name in buckets[k]:
            print(f'  {sid:5} {date} | {(name or "")[:88]}')
        print()

    # Записите в calendar_days.note минават през същото правило.
    print('--- calendar_days.note ---')
    counts = {'fixed': 0, 'pascha': 0, 'anchor': 0}
    for date, note in db.execute(
            "select date,note from calendar_days "
            "where note is not null and note!='' order by date"):
        counts[classify(note)] += 1
    for k, v in counts.items():
        print(f'  {k:7} {v:5}')


if __name__ == '__main__':
    main()
