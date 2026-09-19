#!/usr/bin/env python3
"""Превежда РУСКИЯ превод на песнопенията → `work/hymns_bg.json`.

⚠⚠ ПРЕВЕЖДА СЕ РУСКИЯТ, НЕ ЦЪРКОВНОСЛАВЯНСКИЯТ. Славянският текст с
ударения влиза в базата КАКТО Е — той е оригиналът и се чете на
църковнославянски. Същата схема като в `tools/azbyka.ru/15_translate_hymns.py`.

⚠ Възобновим: вече преведено се прескача.

    python3 03_translate.py --limit 2      # пилот
    python3 03_translate.py
"""
import argparse
import json
import os
import re
import sys
import time
from pathlib import Path

import requests

КОРЕН = Path(__file__).resolve().parents[1]
РАБОТА = КОРЕН / 'work'
ENV = [КОРЕН.parent / 'azbyka.ru' / '.env', КОРЕН / '.env']

API = 'https://api.deepseek.com/chat/completions'
БАЛАНС = 'https://api.deepseek.com/user/balance'
МОДЕЛ = 'deepseek-v4-pro'

ПРОМПТ = """Ти си опитен преводач на православна богослужебна литература от руски на български.

Превеждаш РУСКИЯ ПРЕВОД на пасхални песнопения (тропар, кондак, стихири, канон) на български.

Правила:
1. Езикът е богослужебен и тържествен, но РАЗБИРАЕМ — както в български богослужебни преводи. Не превеждай на църковнославянски и не архаизирай изкуствено.
2. Утвърдените богослужебни формули се дават в българския им вид: „Христос възкръсна от мъртвите, със смърт смъртта потъпка и на тия, които са в гробовете, живот дарува.“
3. Имената и обръщенията — в утвърдените български форми („Христе Спасителю“, „Богородице“).
4. ЗАПАЗИ ДЕЛЕНИЕТО НА РЕДОВЕ. Всеки нов ред в входа е нов ред в изхода — стиховете на песнопението не се сливат.
5. Указанията в скоби и курсив („Трижды“, „Припев“, „Ирмос“) също се превеждат: „Трикратно“, „Припев“, „Ирмос“.
6. Кавичките са български: „…“.
7. Не добавяй свои обяснения — само превода.

Входът е номериран списък от блокове, по един на ред:
[1] първи блок
[2] втори блок

Отговори със същите номера, същия ред и същия брой редове. Ако блокът съдържа няколко реда, запази ги, като ги разделиш с „ | “.
"""


def ключ() -> str:
    for p in ENV:
        if p.exists():
            for line in p.read_text(encoding='utf-8').splitlines():
                if line.strip().startswith('DEEPSEEK_API_KEY='):
                    return line.split('=', 1)[1].strip()
    k = os.environ.get('DEEPSEEK_API_KEY')
    if k:
        return k
    sys.exit('Няма DEEPSEEK_API_KEY — очаква се в ' + str(ENV[0]))


def баланс(k: str):
    try:
        d = requests.get(БАЛАНС, headers={'Authorization': f'Bearer {k}'},
                         timeout=30).json()['balance_infos'][0]
        return float(d['total_balance'])
    except Exception:
        return None


def преведи(k: str, блокове: list[str], отчет: dict, опити: int = 4):
    вход = [f'[{i}] {b.replace(chr(10), " | ")}'
            for i, b in enumerate(блокове, 1)]
    payload = {'model': МОДЕЛ, 'temperature': 1.0, 'stream': False,
               'messages': [{'role': 'system', 'content': ПРОМПТ},
                            {'role': 'user', 'content': '\n'.join(вход)}]}
    последно = None
    for опит in range(1, опити + 1):
        try:
            r = requests.post(API, json=payload, timeout=600,
                              headers={'Authorization': f'Bearer {k}'})
            if r.status_code == 429:
                time.sleep(5 * опит)
                continue
            if r.status_code == 402 or 'Insufficient Balance' in r.text:
                raise SystemExit('⚠⚠ ИЗЧЕРПАН БАЛАНС. Преведеното е запазено; '
                                 'допълни и пусни наново.')
            r.raise_for_status()
            d = r.json()
            u = d.get('usage') or {}
            отчет['повиквания'] += 1
            отчет['вход'] += u.get('prompt_tokens', 0)
            отчет['изход'] += u.get('completion_tokens', 0)
            текст = d['choices'][0]['message']['content']
            ред = {}
            for m in re.finditer(r'^\s*\[(\d+)\]\s*(.*)$', текст, re.M):
                ред[int(m.group(1))] = m.group(2).strip()
            if sorted(ред) != list(range(1, len(блокове) + 1)):
                последно = 'разминаване в броя редове'
                print(f'    опит {опит}/{опити}: {последно}')
                continue
            # ⚠ „ | " се връща обратно в нови редове — редовете на
            # песнопението са част от вида му.
            return [ред[i].replace(' | ', '\n') for i in range(1, len(блокове) + 1)]
        except SystemExit:
            raise
        except Exception as e:                       # noqa: BLE001
            последно = e
            print(f'    опит {опит}/{опити} неуспешен: {e}')
            time.sleep(3 * опит)
    raise RuntimeError(f'провал след {опити} опита: {последно}')


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('--limit', type=int)
    ap.add_argument('--redo', action='store_true')
    a = ap.parse_args()

    песн = json.loads((РАБОТА / 'hymns.json').read_text(encoding='utf-8'))
    цел = РАБОТА / 'hymns_bg.json'
    готови = {} if a.redo or not цел.exists() else json.loads(
        цел.read_text(encoding='utf-8'))

    todo = [h for h in песн if h['ru'] and h['kind_ru'] not in готови]
    if a.limit:
        todo = todo[:a.limit]
    if not todo:
        print('няма какво да се превежда')
        return 0

    k = ключ()
    преди = баланс(k)
    зн = sum(len(h['ru']) for h in todo)
    print(f'за превод: {len(todo)} песнопения, {зн:,} знака')
    if преди is not None:
        print(f'баланс преди: ${преди:.4f}')

    отчет = {'повиквания': 0, 'вход': 0, 'изход': 0}
    # ⚠ На порции по 3: блоковете са дълги (канонът е по 1–2 хиляди знака) и
    # при повече редове моделът започва да слива стихове.
    for i in range(0, len(todo), 3):
        порция = todo[i:i + 3]
        print(f'  [{i + len(порция)}/{len(todo)}] '
              + ', '.join(h['kind_ru'][:28] for h in порция), flush=True)
        редове = преведи(k, [h['ru'] for h in порция], отчет)
        for h, bg in zip(порция, редове):
            готови[h['kind_ru']] = bg
        цел.write_text(json.dumps(готови, ensure_ascii=False, indent=1),
                       encoding='utf-8')

    след = баланс(k)
    print(f'\nповиквания {отчет["повиквания"]} | изходни токени '
          f'{отчет["изход"]:,}')
    if преди is not None and след is not None:
        print(f'похарчено ${преди - след:.4f}')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
