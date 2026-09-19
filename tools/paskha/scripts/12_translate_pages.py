#!/usr/bin/env python3
"""Превежда разчетените страници → work/pages_bg/<слъг>.json.

    python3 12_translate_pages.py --stage 1 --limit 1   # пилот
    python3 12_translate_pages.py --stage 1

⚠⚠ ВЪЗОБНОВИМ ПО ДЯЛ, не по страница. Етап 1 е над милион знака; прекъсване
насред голяма страница не бива да я връща в началото. Готовото се записва
след ВСЕКИ дял.

⚠ Връзките преживяват превода с маркери ⟦n⟧…⟦/n⟧ — същият механизъм като в
`05_translate_text.py`, и проверката е същата: блок с разминати маркери се
пуска наново, а остане ли така, влиза без връзки.
"""
import argparse, csv, json, os, re, sys, time
from pathlib import Path
import requests

КОРЕН = Path(__file__).resolve().parents[1]
РАЗЧЕТЕНО = КОРЕН / 'work' / 'pages'
ЦЕЛ = КОРЕН / 'work' / 'pages_bg'
СПИСЪК = КОРЕН / 'input' / 'pages.csv'
ENV = [КОРЕН.parent / 'azbyka.ru' / '.env', КОРЕН / '.env']
API = 'https://api.deepseek.com/chat/completions'
МОДЕЛ = 'deepseek-v4-pro'
# ⚠ Дял по дял, но много големите се режат: един дял може да е 40 000 знака,
# а отговорът има таван.
ПАРЧЕ = 9000

ПРОМПТ = """Ти си опитен преводач на православна богословска литература от руски на български.

Превеждаш статия от православна енциклопедия — за понятие, празник или богослужение.

Правила:
1. Езикът е ясен и църковно грамотен, но НЕ архаичен — за съвременен читател.
2. Утвърдените богословски и богослужебни термини в българския им вид: „Възкресение Христово“, „изкупление“, „грехопадение“, „Света Троица“, „Причастие“, „плащаница“, „утреня“, „Царски двери“.
3. Имената на светии и автори в утвърдените български форми: „свт. Йоан Златоуст“, „прп. Йоан Дамаскин“, „св. ап. Павел“.
4. Библейските препратки в българското съкращение: „Изх. 12:14“, „1 Кор. 15:20“, „Мат. 5:8“.
5. Кавичките са български: „…“.
6. ⚠ МАРКЕРИТЕ ⟦1⟧ ⟦/1⟧ и т.н. СЕ ЗАПАЗВАТ ТОЧНО. Преведи текста ВЪТРЕ в тях, но не мести, не изпускай и не преномерирай самите маркери.
7. Не добавяй свои обяснения и не съкращавай — само превода.

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
    sys.exit('Няма DEEPSEEK_API_KEY')


def обвий(ru: str, links: list) -> str:
    out, poz = [], 0
    for n, l in enumerate(links, 1):
        i = ru.find(l['text'], poz)
        if i < 0:
            continue
        out.append(ru[poz:i])
        out.append('⟦%d⟧%s⟦/%d⟧' % (n, l['text'], n))
        poz = i + len(l['text'])
    out.append(ru[poz:])
    return ''.join(out)


def маркери(s: str):
    return sorted(МАРКЕР.findall(s))


def преведи(k, блокове, отчет, опити=4):
    вход = ['[%d] %s' % (i, b) for i, b in enumerate(блокове, 1)]
    payload = {'model': МОДЕЛ, 'temperature': 1.0, 'stream': False,
               'messages': [{'role': 'system', 'content': ПРОМПТ},
                            {'role': 'user', 'content': '\n'.join(вход)}]}
    последно = None
    for опит in range(1, опити + 1):
        try:
            r = requests.post(API, json=payload, timeout=1200,
                              headers={'Authorization': 'Bearer ' + k})
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
                print('      опит %d: %s' % (опит, последно)); continue
            изход = [ред[i] for i in range(1, len(блокове) + 1)]
            лоши = [i for i, (a, b) in enumerate(zip(блокове, изход))
                    if маркери(a) != маркери(b)]
            if лоши:
                последно = 'маркерите не съвпадат в %s' % лоши
                print('      опит %d: %s' % (опит, последно)); continue
            return изход
        except SystemExit:
            raise
        except Exception as e:                           # noqa: BLE001
            последно = e
            print('      опит %d неуспешен: %s' % (опит, e))
            time.sleep(3 * опит)
    raise RuntimeError('провал след %d опита: %s' % (опити, последно))


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('--stage', type=int, required=True)
    ap.add_argument('--limit', type=int)
    ap.add_argument('--only')
    a = ap.parse_args()
    ЦЕЛ.mkdir(parents=True, exist_ok=True)
    k = ключ()
    отчет = {'повиквания': 0, 'вход': 0, 'изход': 0}

    редове = [r for r in csv.DictReader(open(СПИСЪК, encoding='utf-8'))
              if int(r['stage']) == a.stage]
    if a.only:
        редове = [r for r in редове if r['slug'] == a.only]
    if a.limit:
        редове = редове[:a.limit]

    for r in редове:
        изв = РАЗЧЕТЕНО / (r['slug'] + '.json')
        if not изв.exists():
            print('  ⚠ %s: не е разчетена' % r['slug']); continue
        d = json.loads(изв.read_text(encoding='utf-8'))
        цел = ЦЕЛ / (r['slug'] + '.json')
        готово = json.loads(цел.read_text(encoding='utf-8')) if цел.exists() else {}
        готово.setdefault('slug', r['slug'])
        готово.setdefault('url', d['url'])
        готово.setdefault('sections', {})
        оставащи = [i for i in range(len(d['sections']))
                    if str(i) not in готово['sections']]
        if not оставащи:
            print('  %s: вече преведена' % r['slug']); continue
        print('  %s — %d дяла, остават %d (%d знака)'
              % (r['slug'], len(d['sections']), len(оставащи), d['chars']))
        if 'title_bg' not in готово and d.get('title_ru'):
            готово['title_bg'] = преведи(k, [d['title_ru']], отчет)[0]
        for i in оставащи:
            s = d['sections'][i]
            части = ([s['title_ru']] if s['title_ru'] else []) + \
                    [обвий(b['ru'], b.get('links') or []) for b in s['blocks']]
            # ⚠ Дългият дял се реже на порции, инак отговорът се орязва.
            преведени = []
            порция, обем = [], 0
            for ч in части:
                if порция and обем + len(ч) > ПАРЧЕ:
                    преведени += преведи(k, порция, отчет)
                    порция, обем = [], 0
                порция.append(ч); обем += len(ч)
            if порция:
                преведени += преведи(k, порция, отчет)
            готово['sections'][str(i)] = {
                'title_bg': преведени[0] if s['title_ru'] else '',
                'blocks_bg': преведени[1:] if s['title_ru'] else преведени,
            }
            цел.write_text(json.dumps(готово, ensure_ascii=False, indent=1),
                           encoding='utf-8')
            print('     дял %d ✅ (%d части)' % (i, len(части)))
    print('\nповиквания: %d | вход %d | изход %d токена'
          % (отчет['повиквания'], отчет['вход'], отчет['изход']))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
