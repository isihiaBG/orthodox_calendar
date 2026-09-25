#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Литургичният адрес на всяка глава — от `input/address_manual.csv`.

⚠⚠ ТУК НЯМА ИЗВЕЖДАНЕ ПО ЗАГЛАВИЕ, за разлика от словата. Заглавията на
Дебольски са СТРУКТУРНИ („Вторая неделя", „Утреня", „Поучительность
праздника") и смисълът им идва от мястото в книгата, не от думите — пуснат
върху тях, `lives_plus/scripts/address.py` адресира 9 от 163, и то две от
деветте ГРЕШНО („Суббота Мясопустная" → T3:7 вместо T2:6). Затова картата е
изцяло ръчна и измерена.

⚠ ПАЗАЧИ, всеки от които ГЪРМИ вместо да мълчи:
  • ред за несъществуващ id;
  • заглавие, което не съвпада с това на главата (номерът се размества при
    всяка поправка в разчитането — платено веднъж на 25.09.2026);
  • адрес в непознат формат.
"""
import csv
import json
import pathlib
import re
import sys

КОРЕН = pathlib.Path(__file__).resolve().parent.parent
РАБОТА = КОРЕН / 'work'

ФОРМАТ = re.compile(
    r'^(?:[WTP]\d{1,2}:[1-7]'                     # W12:3 · T4:1 · P8:7
    r'|\d{2}-\d{2}'                               # 09-14 — църковна дата
    r'|\d{2}-\d{2}\|[1-7]\|(?:before|after))$')   # 09-14|7|before


def main() -> int:
    units = {}
    for f in sorted((РАБОТА / 'units').glob('*.json')):
        u = json.loads(f.read_text(encoding='utf-8'))
        units[u['id']] = u

    карта, грешки = {}, []
    с_csv = КОРЕН / 'input' / 'address_manual.csv'
    with с_csv.open(encoding='utf-8') as fh:
        for ред in csv.DictReader(l for l in fh if not l.startswith('#')):
            ид, загл = ред['id'].strip(), ред['title_ru'].strip()
            адр = (ред['address'] or '').strip()
            if ид not in units:
                грешки.append('няма такава глава: %s' % ид); continue
            ако = units[ид]['title_ru'].strip()
            if ако != загл:
                грешки.append('разминато заглавие при %s:\n     CSV: %s\n     кн.: %s'
                              % (ид, загл, ако)); continue
            for а in filter(None, адр.split(';')):
                if not ФОРМАТ.match(а.strip()):
                    грешки.append('непознат адрес при %s: %r' % (ид, а)); break
            else:
                if адр:
                    карта[ид] = [а.strip() for а in адр.split(';') if а.strip()]

    if грешки:
        print('\n'.join('⚠ ' + g for g in грешки), file=sys.stderr)
        raise SystemExit('картата не е изрядна — %d проблема' % len(грешки))

    (РАБОТА / 'addresses.json').write_text(
        json.dumps(карта, ensure_ascii=False, indent=1), encoding='utf-8')

    без = [u for и, u in sorted(units.items()) if и not in карта]
    print('глави: %d | с адрес: %d | адреса общо: %d'
          % (len(units), len(карта), sum(len(v) for v in карта.values())))
    print('без адрес (само за „Читалня"): %d' % len(без))
    for u in без:
        print('   %-9s %s' % (u['id'], u['title_ru'][:72]))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
