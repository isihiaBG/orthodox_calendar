#!/usr/bin/env python3
"""Стъпка 2 — ЕДИНСТВЕНАТА, която харчи пари.

Стъпва на `tools/Translate_lives/scripts/03_translate_deepseek.py` (същият
автор, същият регистър), с три разлики:

  • материалът е СЛОВА и ПОУЧЕНИЯ, не жития — казано е в промпта;
  • няма запушалки за разметка: тук се превежда гол текст по абзаци;
  • отчита се РАЗХОДЪТ — баланс преди и след, плюс токени по повикване.

⚠ ВЪЗОБНОВИМ: дял с готов `work/translated/<id>.json` се прескача. Тъй че
може да се пуска на порции и да се спира по всяко време.

    python3 02_translate_deepseek.py --limit 2      # пилот, за да се измери
    python3 02_translate_deepseek.py --only vosk-004
    python3 02_translate_deepseek.py                # всичко останало
"""
import argparse
import json
import os
import re
import sys
import threading
import time
from pathlib import Path

import requests

КОРЕН = Path(__file__).resolve().parents[1]
РАБОТА = КОРЕН / 'work'

# ⚠⚠ `--root` ПОЗВОЛЯВА ДРУГ КОНВЕЙЕР ДА ПОЛЗВА ТОЗИ ПРЕВОДАЧ.
#
# „Дни богослужения" (tools/dni_bogosluzheniya/) е книга с друго
# устройство и има свое разчитане, но САМИЯТ превод е същият — промпт,
# парчета, отчет на разхода, възобновимост. Преписан втори път, той щеше
# да се размине при първата поправка в промпта.
#
# ⚠ Чуждата папка трябва да носи `work/units/*.json` с полетата `id`,
# `title_ru` и `blocks_ru` — това е целият договор.
ENV = [КОРЕН.parent / 'azbyka.ru' / '.env', КОРЕН / '.env']

API = 'https://api.deepseek.com/chat/completions'
БАЛАНС = 'https://api.deepseek.com/user/balance'
МОДЕЛ = 'deepseek-v4-pro'
ТЕМПЕРАТУРА = 1.0

# ⚠ Парче от ~3000 знака. По-голямо води до разминаване в броя редове (моделът
# почва да слива абзаци), по-малко умножава постоянната надбавка за мислене,
# която при този модел е няколко пъти по-голяма от самия превод.
ПАРЧЕ = 3000

_брава = threading.Lock()

ПРОМПТ = """Ти си опитен преводач на православна църковна литература от руски на български.

Превеждаш СЛОВА и ПОУЧЕНИЯ на св. Димитрий Ростовски — проповеди, говорени в храм.

Правила:
1. Превеждай СМИСЪЛА, не буквално — на естествен, литературен църковен български, какъвто се използва в български проповеди и жития (не разговорен, но и не изкуствено сложен).
2. Запази проповедническия глас: обръщенията към слушателите („възлюбени слушатели“, „благословени християни“) са част от текста и остават.
3. Имената на светии, места и събори използвай в утвърдените им български православни форми (напр. „Йоан“, не „Иоанн“). Ако не си сигурен в утвърдена форма, транслитерирай последователно.
4. Библейските препратки в скоби остават както са, само съкращенията на книгите ги побългарявай („Мф.“ → „Мат.“, „Лк.“ → „Лук.“, „Ин.“ → „Йоан.“, „Быт.“ → „Бит.“, „Пс.“ остава „Пс.“).
5. Цитатите от Писанието вътре в текста превеждай в стила на българския синодален превод.
6. ПОВЕСТВОВАНИЕТО Е В ПРЕИЗКАЗНО НАКЛОНЕНИЕ — така се разказва в българските жития и проповеди за неща, на които разказвачът не е бил свидетел: „обикалял“, „казвал“, „отишъл“, а НЕ „обикаляше“, „казваше“, „отиде“. Сегашно и минало свършено остават само в пряка реч и в разсъждение на проповедника.
7. Кавичките са БЪЛГАРСКИ: „…“ — не «…» и не "…".
8. „сравни“ се съкращава „срв.“, не „ср.“.
9. Имената на библейските книги в утвърдените български синодални форми: „Юдит“, „Сирах“, при съмнение — както са в българската Библия.
10. Не добавяй свои обяснения, бележки или заглавия — само превода.

Формат на входа и изхода:

Входът е номериран списък от абзаци, по един на ред:
[1] първи абзац
[2] втори абзац

Отговори със същите номера, в същия ред и със същия брой редове:
[1] превод на първия
[2] превод на втория

Не сливай, не разделяй и не пропускай абзаци. Всеки е отделен абзац от книгата и трябва да остане отделен ред в отговора.
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


def баланс(k: str) -> float | None:
    """⚠ ЗАКЪСНЯВА с няколко минути — не става за точна спирачка."""
    try:
        r = requests.get(БАЛАНС, headers={'Authorization': f'Bearer {k}'},
                         timeout=30)
        d = r.json()['balance_infos'][0]
        return float(d['total_balance'])
    except Exception:
        return None


def парчета(блокове: list[str]) -> list[list[str]]:
    out, текущо, n = [], [], 0
    for b in блокове:
        if текущо and n + len(b) > ПАРЧЕ:
            out.append(текущо)
            текущо, n = [], 0
        текущо.append(b)
        n += len(b)
    if текущо:
        out.append(текущо)
    return out


def разчети(текст: str, брой: int) -> list[str] | None:
    """Отговорът → редове. `None` при разминаване в броя или номерата."""
    ред = {}
    for m in re.finditer(r'^\s*\[(\d+)\]\s*(.*)$', текст, re.M):
        ред[int(m.group(1))] = m.group(2).strip()
    if sorted(ред) != list(range(1, брой + 1)):
        return None
    return [ред[i] for i in range(1, брой + 1)]


def преведи(k: str, парче: list[str], подсказка: str, отчет: dict,
            опити: int = 4) -> list[str]:
    вход = []
    if подсказка:
        вход.append('(Контекст, НЕ го превеждай и НЕ го включвай в отговора: '
                    f'това е продължение на словото „{подсказка}“.)\n')
    for i, b in enumerate(парче, 1):
        вход.append(f'[{i}] {" ".join(b.split())}')
    payload = {'model': globals()['МОДЕЛ'], 'temperature': ТЕМПЕРАТУРА, 'stream': False,
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
            # ⚠⚠ ИЗЧЕРПАН БАЛАНС НЕ СЕ ПОВТАРЯ. Без това всяко парче изяжда
            # четири опита с изчакване, а краят е същият — само че след
            # десетки минути и с неясно съобщение.
            if r.status_code == 402 or 'Insufficient Balance' in r.text:
                raise SystemExit('⚠⚠ ИЗЧЕРПАН БАЛАНС в DeepSeek. Преведеното '
                                 'дотук е запазено; допълни сметката и пусни '
                                 'скрипта наново — той прескача готовото.')
            r.raise_for_status()
            d = r.json()
            u = d.get('usage') or {}
            with _брава:
                отчет['повиквания'] += 1
                отчет['вход'] += u.get('prompt_tokens', 0)
                отчет['изход'] += u.get('completion_tokens', 0)
            редове = разчети(d['choices'][0]['message']['content'], len(парче))
            if редове is None:
                последно = 'разминаване в броя редове'
                print(f'    опит {опит}/{опити}: {последно}')
                continue
            return редове
        except Exception as e:                      # noqa: BLE001
            последно = e
            print(f'    опит {опит}/{опити} неуспешен: {e}')
            time.sleep(3 * опит)
    raise RuntimeError(f'провал след {опити} опита: {последно}')


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('--limit', type=int)
    ap.add_argument('--only', action='append')
    ap.add_argument('--redo', action='store_true')
    ap.add_argument('--chunk', type=int, help='знаци на повикване')
    ap.add_argument('--model')
    ap.add_argument('--workers', type=int, default=4)
    ap.add_argument('--root', help='друга папка на конвейер (със своя work/)')
    a = ap.parse_args()

    if a.chunk:
        globals()['ПАРЧЕ'] = a.chunk
    if a.model:
        globals()['МОДЕЛ'] = a.model
    k = ключ()
    global РАБОТА
    if a.root:
        РАБОТА = Path(a.root).resolve() / 'work'
        if not (РАБОТА / 'units').is_dir():
            sys.exit('няма %s' % (РАБОТА / 'units'))
        print('работи върху: %s' % РАБОТА)
    (РАБОТА / 'translated').mkdir(parents=True, exist_ok=True)
    дялове = sorted((РАБОТА / 'units').glob('*.json'))
    todo = []
    for f in дялове:
        x = json.loads(f.read_text(encoding='utf-8'))
        if a.only and x['id'] not in a.only:
            continue
        цел = РАБОТА / 'translated' / f'{x["id"]}.json'
        if цел.exists() and not a.redo:
            continue
        todo.append(x)
    if a.limit:
        todo = todo[:a.limit]
    if not todo:
        print('няма какво да се превежда')
        return 0

    знаци = sum(sum(len(b) for b in x['blocks_ru']) for x in todo)
    преди = баланс(k)
    print(f'за превод: {len(todo)} дяла, {знаци:,} знака')
    if преди is not None:
        print(f'баланс преди: ${преди:.4f}')

    отчет = {'повиквания': 0, 'вход': 0, 'изход': 0}
    готови = [0]

    def един(x):
        т0 = time.time()
        гр = парчета(x['blocks_ru'])
        готово = []
        for j, п in enumerate(гр):
            готово += преведи(k, п, x['title_ru'] if j else '', отчет)
        assert len(готово) == len(x['blocks_ru'])
        # ⚠ Записва се ВЕДНАГА след дяла, не накрая: пуск от часове може да
        # бъде прекъснат по всякакъв повод и вършеното не бива да се губи.
        (РАБОТА / 'translated' / f'{x["id"]}.json').write_text(
            json.dumps({**x, 'blocks_bg': готово}, ensure_ascii=False,
                       indent=1), encoding='utf-8')
        готови[0] += 1
        print(f'[{готови[0]}/{len(todo)}] {x["id"]} — {len(гр)} парчета, '
              f'{time.time() - т0:.0f} сек | {x["title_ru"][:46]}', flush=True)

    # ⚠ Успоредно ПО ДЯЛОВЕ, не по парчета: парчетата вътре в един дял вървят
    # по ред, защото второто и нататък получават заглавието за контекст.
    if a.workers > 1 and len(todo) > 1:
        from concurrent.futures import ThreadPoolExecutor
        with ThreadPoolExecutor(max_workers=a.workers) as ex:
            list(ex.map(един, todo))
    else:
        for x in todo:
            един(x)

    след = баланс(k)
    print(f'\nповиквания {отчет["повиквания"]} | входни токени '
          f'{отчет["вход"]:,} | изходни {отчет["изход"]:,}')
    if преди is not None and след is not None:
        похарчено = преди - след
        print(f'баланс след: ${след:.4f} | похарчено ${похарчено:.4f}')
        if знаци and похарчено > 0:
            print(f'≈ ${похарчено / знаци * 1e6:.2f} на 1 млн. знака вход')
        print('⚠ балансът закъснява с няколко минути — сметката е ориентир')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
