#!/usr/bin/env python3
"""Превежда СКАЗАНИЕТО за Пасха (work/text.json) → work/text_bg.json.

    python3 05_translate_text.py --limit 2    # пилот
    python3 05_translate_text.py

⚠ Възобновим: вече преведен дял се прескача. Прекъснато пускане не губи нищо.

⚠⚠ ВРЪЗКИТЕ ПРЕЖИВЯВАТ ПРЕВОДА С МАРКЕРИ. Котвата се обвива в ⟦n⟧…⟦/n⟧ и
моделът е задължен да ги запази; след превода те стават `<a href>`. Иначе
94-те връзки в текста се губят — а те са половината смисъл на страницата.

⚠ Проверката е СТРУКТУРНА, не на доверие: ако върнатият блок няма същите
маркери, блокът се пуска наново; остане ли така, влиза БЕЗ връзки, но с
изричен ред в отчета. По-добре текст без връзка, отколкото текст, накъсан
от полусчупени маркери.
"""
import argparse, json, os, re, sys, time
from pathlib import Path
import requests

КОРЕН = Path(__file__).resolve().parents[1]
РАБОТА = КОРЕН / 'work'
ENV = [КОРЕН.parent / 'azbyka.ru' / '.env', КОРЕН / '.env']
API = 'https://api.deepseek.com/chat/completions'
МОДЕЛ = 'deepseek-v4-pro'

ПРОМПТ = """Ти си опитен преводач на православна литература от руски на български.

Превеждаш обяснителен текст за празника Пасха (Великден) — за устройството на празника, богослужението и историята му.

Правила:
1. Езикът е ясен и църковно грамотен, но НЕ архаичен. Пише се за съвременен читател.
2. Утвърдените богослужебни и библейски термини — в българския им вид: „Пасха“, „Възкресение Христово“, „Велика събота“, „Светлата седмица“, „плащаница“, „Царски двери“, „полунощница“, „канон“, „тропар“, „задостойник“.
3. Имената на светиите и авторите — в утвърдените български форми („свт. Григорий Богослов“, „св. ап. Павел“).
4. Кавичките са български: „…“.
5. ⚠ МАРКЕРИТЕ ⟦1⟧ ⟦/1⟧ ⟦2⟧ ⟦/2⟧ и т.н. СЕ ЗАПАЗВАТ ТОЧНО. Те ограждат думи, които са препратки. Преведи текста ВЪТРЕ в тях, но не мести, не изпускай и не преномерирай самите маркери.
6. Библейските препратки вътре в маркери („Исх.12:14“) се превеждат в българското съкращение („Изх. 12:14“).
7. Не добавяй свои обяснения — само превода.

Входът е номериран списък от блокове, по един на ред:
[1] първи блок
[2] втори блок

Отговори със същите номера, същия ред и същия брой редове.
"""

МАРКЕР = re.compile(r'⟦(/?)(\d+)⟧')


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


def обвий(ru: str, links: list) -> str:
    """Слага ⟦n⟧…⟦/n⟧ около котвите — ПО РЕД, без застъпване."""
    out, poz = [], 0
    for n, l in enumerate(links, 1):
        i = ru.find(l['text'], poz)
        if i < 0:
            continue
        out.append(ru[poz:i])
        out.append(f'⟦{n}⟧{l["text"]}⟦/{n}⟧')
        poz = i + len(l['text'])
    out.append(ru[poz:])
    return ''.join(out)


def маркери(s: str):
    return sorted(МАРКЕР.findall(s))


def преведи(k, блокове, отчет, опити=4):
    вход = [f'[{i}] {b}' for i, b in enumerate(блокове, 1)]
    payload = {'model': МОДЕЛ, 'temperature': 1.0, 'stream': False,
               'messages': [{'role': 'system', 'content': ПРОМПТ},
                            {'role': 'user', 'content': '\n'.join(вход)}]}
    последно = None
    for опит in range(1, опити + 1):
        try:
            r = requests.post(API, json=payload, timeout=900,
                              headers={'Authorization': f'Bearer {k}'})
            if r.status_code == 429:
                time.sleep(5 * опит); continue
            if r.status_code == 402 or 'Insufficient Balance' in r.text:
                raise SystemExit('⚠⚠ ИЗЧЕРПАН БАЛАНС. Преведеното е запазено.')
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
            if sorted(ред) != list(range(1, len(блокове) + 1)):
                последно = 'разминаване в броя редове'
                print(f'    опит {опит}/{опити}: {последно}'); continue
            изход = [ред[i] for i in range(1, len(блокове) + 1)]
            лоши = [i for i, (a, b) in enumerate(zip(блокове, изход))
                    if маркери(a) != маркери(b)]
            if лоши:
                последно = f'маркерите не съвпадат в блокове {лоши}'
                print(f'    опит {опит}/{опити}: {последно}'); continue
            return изход
        except SystemExit:
            raise
        except Exception as e:                        # noqa: BLE001
            последно = e
            print(f'    опит {опит}/{опити} неуспешен: {e}')
            time.sleep(3 * опит)
    raise RuntimeError(f'провал след {опити} опита: {последно}')


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('--limit', type=int)
    ap.add_argument('--redo', action='store_true')
    a = ap.parse_args()

    данни = json.loads((РАБОТА / 'text.json').read_text(encoding='utf-8'))
    цел = РАБОТА / 'text_bg.json'
    готови = {} if a.redo or not цел.exists() else json.loads(
        цел.read_text(encoding='utf-8'))
    k = ключ()
    отчет = {'повиквания': 0, 'вход': 0, 'изход': 0}

    дялове = list(enumerate(данни['sections']))
    ако = [(i, s) for i, s in дялове if str(i) not in готови]
    if a.limit:
        ако = ако[:a.limit]
    print(f'дялове: {len(дялове)} | остават: {len(ако)}')

    for i, s in ако:
        части = ([s['title_ru']] if s['title_ru'] else []) + \
                [обвий(b['ru'], b.get('links') or []) for b in s['blocks']]
        print(f'  дял {i}: {len(части)} части, '
              f'{sum(len(c) for c in части)} знака')
        пр = преведи(k, части, отчет)
        готови[str(i)] = {
            'title_bg': пр[0] if s['title_ru'] else '',
            'blocks_bg': пр[1:] if s['title_ru'] else пр,
        }
        цел.write_text(json.dumps(готови, ensure_ascii=False, indent=1),
                       encoding='utf-8')
    print(f"\nповиквания: {отчет['повиквания']} | "
          f"вход {отчет['вход']} | изход {отчет['изход']} токена")
    print(f'записано: {цел}')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
