#!/usr/bin/env python3
"""Превежда заглавията от work/links.json → work/links_bg.json.

    python3 09_translate_links.py --dry-run   # само брои
    python3 09_translate_links.py

⚠ Превеждат се ЗАГЛАВИЯТА и имената на групите, както и редът с автора
(„еп. Александр (Милеант)" → „еп. Александър (Милеант)"). Адресите НЕ се
пипат — те сочат чужд сайт и остават каквито са.

⚠ Възобновим: вече преведено се прескача. Ключът е самият руски низ, тъй че
едно и също заглавие на две места се превежда веднъж.
"""
import argparse, json, os, re, sys, time
from pathlib import Path
import requests

КОРЕН = Path(__file__).resolve().parents[1]
РАБОТА = КОРЕН / 'work'
ENV = [КОРЕН.parent / 'azbyka.ru' / '.env', КОРЕН / '.env']
API = 'https://api.deepseek.com/chat/completions'
МОДЕЛ = 'deepseek-v4-pro'
ПОРЦИЯ = 40

ПРОМПТ = """Ти си опитен преводач на православна литература от руски на български.

Превеждаш КРАТКИ ЗАГЛАВИЯ на статии, книги и понятия, свързани с Пасха (Великден), както и редове с автор или издание.

Правила:
1. Заглавието си остава заглавие — кратко, без добавени обяснения.
2. Имената на автори и светии — в утвърдените български форми: „еп. Александър (Милеант)“, „св. Йоан Златоуст“, „прот. Александър Шмеман“.
3. Утвърдените термини — в българския им вид: „Възкресение Христово“, „Пасхален канон“, „Светлата седмица“, „Антипасха“, „Благодатен огън“.
4. Съкращенията на сан се запазват: „еп.“, „прот.“, „свт.“, „прп.“, „архим.“.
5. Кавичките са български: „…“.
6. Ако редът е име на издание или речник, преведи го като такова.
7. Не добавяй свои обяснения — само превода.

Входът е номериран списък, по един ред:
[1] първи ред
[2] втори ред

Отговори със същите номера, същия ред и същия брой редове.
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
    sys.exit('Няма DEEPSEEK_API_KEY')


def преведи(k, редове, отчет, опити=4):
    вход = [f'[{i}] {r}' for i, r in enumerate(редове, 1)]
    payload = {'model': МОДЕЛ, 'temperature': 1.0, 'stream': False,
               'messages': [{'role': 'system', 'content': ПРОМПТ},
                            {'role': 'user', 'content': '\n'.join(вход)}]}
    последно = None
    for опит in range(1, опити + 1):
        try:
            r = requests.post(API, json=payload, timeout=600,
                              headers={'Authorization': f'Bearer {k}'})
            if r.status_code == 429:
                time.sleep(5 * опит); continue
            if r.status_code == 402 or 'Insufficient Balance' in r.text:
                raise SystemExit('⚠⚠ ИЗЧЕРПАН БАЛАНС.')
            r.raise_for_status()
            d = r.json()
            u = d.get('usage') or {}
            отчет['повиквания'] += 1
            отчет['вход'] += u.get('prompt_tokens', 0)
            отчет['изход'] += u.get('completion_tokens', 0)
            ред = {}
            for m in re.finditer(r'^\s*\[(\d+)\]\s*(.*)$',
                                 d['choices'][0]['message']['content'], re.M):
                ред[int(m.group(1))] = m.group(2).strip()
            if sorted(ред) != list(range(1, len(редове) + 1)):
                последно = 'разминаване в броя редове'
                print(f'    опит {опит}/{опити}: {последно}'); continue
            return [ред[i] for i in range(1, len(редове) + 1)]
        except SystemExit:
            raise
        except Exception as e:                        # noqa: BLE001
            последно = e
            print(f'    опит {опит}/{опити} неуспешен: {e}')
            time.sleep(3 * опит)
    raise RuntimeError(f'провал след {опити} опита: {последно}')


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('--dry-run', action='store_true')
    a = ap.parse_args()

    d = json.loads((РАБОТА / 'links.json').read_text(encoding='utf-8'))
    цел = РАБОТА / 'links_bg.json'
    готови = json.loads(цел.read_text(encoding='utf-8')) if цел.exists() else {}

    нужни = []
    for г in d['literature']:
        нужни.append(г['title_ru'])
        for x in г['items']:
            нужни += [x['title_ru'], x['by_ru']]
    нужни += [x['title_ru'] for x in d['related']]
    нужни = [s for s in dict.fromkeys(нужни) if s and s not in готови]

    print(f'за превод: {len(нужни)} различни низа, '
          f'{sum(len(s) for s in нужни)} знака')
    if a.dry_run:
        return 0

    k = ключ()
    отчет = {'повиквания': 0, 'вход': 0, 'изход': 0}
    for i in range(0, len(нужни), ПОРЦИЯ):
        порция = нужни[i:i + ПОРЦИЯ]
        print(f'  порция {i // ПОРЦИЯ + 1}: {len(порция)} реда')
        for р, п in zip(порция, преведи(k, порция, отчет)):
            готови[р] = п
        цел.write_text(json.dumps(готови, ensure_ascii=False, indent=1),
                       encoding='utf-8')
    print(f"повиквания: {отчет['повиквания']} | вход {отчет['вход']} | "
          f"изход {отчет['изход']} токена")
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
