#!/usr/bin/env python3
"""Извежда "вечните" правила за saints от calendar_old.db.

За всеки от трите пласта (виж classify.py) правилото не зависи от 2026-та:
  fixed   — църковен (месец, ден). civil_date - 13 = църковна дата (проверено
            по-долу: целият източник обхваща точно църковната 2026 година,
            civil 2026-01-14 = църковен 1 януари).
  civil   — ГРАЖДАНСКИ (месец, ден), еднакъв и в двата стила. Вписва се на
            ръка в overrides.csv; classify() не го връща никога.
            ⚠ Такива дни има малко и всеки е изключение по СЪЩЕСТВО, а не
            по сметка: Съединението и Денят на будителите изобщо не са
            църковни празници (стоят в календара за сведение), а Гергьовден
            БПЦ държи на 6 май и след приемането на новия стил — макар
            църковната му дата да е 23 април. Сверено с календара на
            Патриаршията (bg-patriarshia.bg/calendar/2026-5, 01.09.2026).
            Без този пласт трите излизаха верни по стар стил и с 13 дни
            по-рано по нов — 23.IV, 24.VIII и 19.X.
  pascha  — офсет в дни спрямо гражданската дата на Пасха (тя е една и съща
            и при двата стила).
  anchor  — (коя котва, посока преди/след, кой ден от седмицата). Котвата
            се търси КАТО ДАННИ (по подниз в името), не се хардкодва —
            остава вярно, ако текстовете се пренапишат.

Скриптът само ИЗВЕЖДА и ПРОВЕРЯВА (round-trip: приложи правилото към 2026 г.
стар стил → трябва да излезе точно оригиналната гражданска дата). Нищо не
пише.
"""
import datetime
import os
import re
import sqlite3
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from paschalion import civil_from_church, julian_gregorian_offset, pascha_civil
from classify import classify, key_name, load_overrides, load_known_movable
from rules import resolve as resolve_rule

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', '..'))
OLD = os.path.join(HERE, 'input', 'db', 'calendar_old.db')
SOURCE_YEAR = 2026  # църковната година, която calendar_old.db представя

# Три жития от Димитрий Ростовски на църковен 29 февруари (виж
# tools/match_dmitry_lives/) — SOURCE_YEAR (2026) няма такава гражданска
# дата (datetime.date(2026,2,29) гърми), тъй че не могат да минат по
# обичайния път (граждански ред в calendar_old.db → church_md() назад).
# Вписани директно тук. build_saints() ги генерира УСЛОВНО за всяка
# целева година: високосна → 29.II, самото име; невисокосна → 28.II, с
# добавка към името (виж LEAP_FALLBACK_NOTE в build.py). Решено от
# потребителя на 23.08.2026 — вместо два отделни реда (риск от нов
# дублаж, каквито тъкмо изчистихме), едно правило с два изхода.
#
# ⚠ „Прп. Касиан Римлянин" ВЕЧЕ имаше обикновен fixed ред в calendar_old.db
# (id 192, църковно 28.II, постоянно всяка година) — той е ИЗТРИТ оттам и
# СЛЯТ тук (запазен е истинският му slug/rank), защото иначе в невисокосна
# година двата реда (старият постоянен + новия leap_fixed) щяха да излязат
# на едно и също гражданско число (28.II + офсет = СЪЩАТА дата и за двата,
# аритметиката съвпада) — видимо повторение на един и същ светия същия ден.
# Потвърдено от потребителя: остава САМО едно място в месеца — 28.II в
# невисокосна година, 29.II във високосна, никога и двете.
LEAP_FIXED = [
    dict(name='Прп. Касиан Римлянин († 435)', rank=6, group_code='ECUMENICAL',
         sign='', slug='sv-kassian-ioann-kassian-rimljanin'),
    dict(name='Прп. Йоан, наречен Варсануфий', rank=6, group_code='ECUMENICAL',
         sign='', slug='sv-ioann-varsanufij'),
    dict(name='Мч. Теоктирист, игумен Пеликитски', rank=6, group_code='ECUMENICAL',
         sign='', slug='sv-teoktirist-pelikitskij'),
]

ANCHOR_FEAST = {
    'Богоявление': re.compile(r'БОГОЯВЛЕНИЕ'),
    'Въздвижение': re.compile(r'Въздвижение', re.I),
    'Рождество Христово': re.compile(r'РОЖДЕСТВО ХРИСТОВО'),
    # Нужен и за трите анкерни реда от classify(), и за known_movable.csv
    # (правилото "Архангеловден<нед" го ползва по име).
    'Архангеловден': re.compile(r'Архангеловден'),
}
WEEKDAY = {'събота': 5, 'неделя': 6}  # Python Monday=0


def church_md(civil: datetime.date) -> tuple[int, int]:
    d = civil - datetime.timedelta(days=julian_gregorian_offset(civil.year))
    return d.month, d.day


# Тези квалификатори НЕ сочат самия ден на празника — предпразненство и
# попразненство го обграждат, а анкерните редове (събота/неделя преди/след)
# са именно това, което извеждаме, не е позволено да го ползваме за вход.
NOT_THE_FEAST = re.compile(
    r'Предпразненство|Попразненство|Отдание|събота|неделя', re.I)


def find_anchor_church_dates(db) -> dict[str, tuple[int, int]]:
    """Църковната (месец, ден) на трите неподвижни котви — НАМЕРЕНИ в
    данните (saints + calendar_days.note), не вкарани отвън."""
    out = {}
    rows = list(db.execute("select date,name from saints")) + \
        list(db.execute(
            "select date,note from calendar_days "
            "where note is not null and note!=''"))
    for feast, pat in ANCHOR_FEAST.items():
        hits = {d for d, text in rows if text and pat.search(text)}
        direct = {d for d in hits
                  if not NOT_THE_FEAST.search(
                      next(t for dd, t in rows if dd == d and pat.search(t or '')))}
        if direct:
            civil = datetime.date.fromisoformat(min(direct))
            out[feast] = church_md(civil)
            continue
        # Няма пряк ред за самия ден (тази година е погълнат от бележка
        # без думата за празника — виж случая с Въздвижение, паднало точно
        # в неделя). Извеждаме деня СТРУКТУРНО: денят веднага след
        # предпразненството.
        pre = {d for d in hits
               if re.search(r'Предпразненство', next(
                   t for dd, t in rows if dd == d and pat.search(t or '')), re.I)}
        if pre:
            civil = datetime.date.fromisoformat(min(pre)) + datetime.timedelta(days=1)
            out[feast] = church_md(civil)
            print(f'  забележка: "{feast}" изведен структурно '
                  f'(ден след предпразненството = {civil}), няма пряк ред тази година')
            continue
        print(f'  ПРЕДУПРЕЖДЕНИЕ: не намерих котва "{feast}" в данните')
    return out


def parse_anchor(name: str) -> tuple[str, str, str] | None:
    """(weekday_word, direction, feast) от текста на реда, или None."""
    m = re.search(r'(събота|неделя)\s+(преди|след)\s+([А-Яа-яA-Za-z ]+)',
                   name, re.I)
    if not m:
        return None
    wd, direction, rest = m.group(1).lower(), m.group(2).lower(), m.group(3)
    for feast in ANCHOR_FEAST:
        if feast.split()[0].lower() in rest.lower():
            return wd, direction, feast
    return None


def nearest_weekday(anchor: datetime.date, weekday: int, direction: str) -> datetime.date:
    delta = (weekday - anchor.weekday()) % 7
    if direction == 'преди':
        delta -= 7
    return anchor + datetime.timedelta(days=delta)


def extract(db) -> dict:
    """Извежда правилата от saints — ПОДЕЛЕНА логика между валидацията тук
    (round-trip срещу 2026 стар стил) и build.py (действителна генерация
    за произволна година/стил). Нищо не пише, само чете и връща данни.

    Връща dict с ключове fixed/pascha/anchor/manual (списъци с правила,
    всяко нещо dict с достатъчно за пресмятане на дата + name/rank/
    group_code/sign/slug), skipped (списък (date,name)), anchor_church
    (речник за rules.resolve) и mismatches (за round-trip проверката,
    винаги смятана спрямо SOURCE_YEAR стар стил).
    """
    over = load_overrides()
    known = load_known_movable()
    anchor_church = find_anchor_church_dates(db)

    fixed_rules, pascha_rules, anchor_rules, manual_rules = [], [], [], []
    civil_rules = []
    skipped = []
    mismatches = []

    for sid, date, name, rank, group_code, sign, slug in db.execute(
            'select id,date,name,rank,group_code,sign,slug from saints order by date'):
        civil = datetime.date.fromisoformat(date)
        # ⚠ Ключът минава през classify.key_name — виж докстринга ѝ:
        # почти половината имена носят неразбиваем интервал.
        kname = key_name(name)
        rule_text = known.get((date, kname))
        kind = 'manual' if rule_text is not None else (
            over.get((date, kname)) or classify(name))
        rest = dict(rank=rank, group_code=group_code, sign=sign, slug=slug, name=name)

        if kind == 'skip':
            skipped.append((date, name))
            continue

        if kind == 'manual':
            manual_rules.append(dict(rule=rule_text, **rest))
            check = resolve_rule(rule_text, SOURCE_YEAR, True, anchor_church)
            if check != civil:
                mismatches.append(('manual', date, name, check))
            continue

        if kind == 'civil':
            # ⚠ Датата се взима КАКТО Е — тя вече е гражданската. Тук няма
            # какво да се проверява с round-trip: правилото „същият ден по
            # гражданския календар" възпроизвежда входа по определение.
            civil_rules.append(
                dict(civil_month=civil.month, civil_day=civil.day, **rest))
            continue

        if kind == 'fixed':
            m, d = church_md(civil)
            fixed_rules.append(dict(church_month=m, church_day=d, **rest))
            check = civil_from_church(SOURCE_YEAR, m, d, old_style=True)
            if check != civil:
                mismatches.append(('fixed', date, name, check))

        elif kind == 'pascha':
            offset = (civil - pascha_civil(SOURCE_YEAR)).days
            pascha_rules.append(dict(offset_days=offset, **rest))
            check = pascha_civil(SOURCE_YEAR) + datetime.timedelta(days=offset)
            if check != civil:
                mismatches.append(('pascha', date, name, check))

        else:  # anchor
            parsed = parse_anchor(name)
            if parsed is None:
                mismatches.append(('anchor-НЕРАЗПОЗНАТ', date, name, None))
                continue
            wd_word, direction, feast = parsed
            m, d = anchor_church[feast]
            anchor_rules.append(dict(
                anchor_feast=feast, weekday=wd_word, direction=direction, **rest))
            anchor_civil = civil_from_church(SOURCE_YEAR, m, d, old_style=True)
            check = nearest_weekday(anchor_civil, WEEKDAY[wd_word], direction)
            if check != civil:
                mismatches.append(('anchor', date, name, check))

    return dict(fixed=fixed_rules, pascha=pascha_rules, anchor=anchor_rules,
                manual=manual_rules, civil=civil_rules,
                leap_fixed=list(LEAP_FIXED), skipped=skipped,
                anchor_church=anchor_church, mismatches=mismatches)


def main():
    db = sqlite3.connect(f'file:{OLD}?mode=ro', uri=True)
    r = extract(db)

    print('--- църковни дати на котвите (намерени в данните) ---')
    for feast, (m, d) in r['anchor_church'].items():
        print(f'  {feast:20} църковно {m:02}.{d:02}')
    print()

    print(f"правила: fixed={len(r['fixed'])} pascha={len(r['pascha'])} "
          f"anchor={len(r['anchor'])} manual={len(r['manual'])} "
          f"skip={len(r['skipped'])}")
    print()
    if r['skipped']:
        print('--- skip (изключени по overrides.csv) ---')
        for date, name in r['skipped']:
            print(f'  {date} | {name[:88]}')
        print()
    if r['mismatches']:
        print(f"!!! РАЗМИНАВАНИЯ (round-trip не съвпада): {len(r['mismatches'])}")
        for kind, date, name, check in r['mismatches']:
            print(f'  [{kind}] {date} | {name[:70]}  ->  преизчислено: {check}')
    else:
        total = len(r['fixed']) + len(r['pascha']) + len(r['anchor']) + len(r['manual'])
        print(f'Round-trip проверката е ЧИСТА: правилото за всеки от {total} '
              'записа, приложено към 2026 стар стил, възпроизвежда точната '
              'оригинална гражданска дата.')


if __name__ == '__main__':
    main()
