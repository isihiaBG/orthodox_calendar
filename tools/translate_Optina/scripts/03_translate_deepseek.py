#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
03_translate_deepseek.py — Стъпка 3 (ЕДИНСТВЕНАТА, която харчи пари):
превежда избраните сентенции на Оптинските старци от руски на български.

Стъпва на 02_translate_deepseek.py от Теофан — същият модел, същата
температура, същият протокол „[1] …", същото поведение при прекъсване и
същият отчет на токените. Разликите са три и са нарочни:

 1. ПОРЦИЯТА Е ОТ РАЗНИ СЕНТЕНЦИИ, не абзаци от едно поучение. Затова
    темата и старецът вървят в отделен блок над текста: моделът трябва да
    знае, че „ПОСЛУШАНИЕ" е темата на трети ред, без да я сметне за текст
    за превод.
 2. ГОТОВОТО СЕ ПАЗИ ПО ЕДНО НА ФАЙЛ (work/translated/<id>.json). Порцията
    е само начин да се пести заявка; провали ли се една, останалите остават.
 3. ЕЗИКЪТ Е ДРУГ. Това не е размисъл върху дневното четиво, а сентенция от
    XIX век — старец отговаря на духовно чедо. Стилът е по-стегнат, често
    с църковнославянски примеси. Не се приглажда до съвременен български.

⚠ НИЩО НЕ СЕ СЪКРАЩАВА. Няколко от сентенциите са дълги; преводът трябва да
ги пренесе цели. Ако моделът върне забележимо по-кратък текст, порцията се
превежда наново — това е една от проверките за цялост.

Вход:
  ../work/selected.json      (от 02_select.py)
  ключ DEEPSEEK_API_KEY — търси се в ../.env, после в ~/Desktop/azbyka.ru/.env

Изход:
  ../work/translated/<id>.json
  ../work/usage.json         натрупани токени и брой заявки

Употреба:
  python3 03_translate_deepseek.py --limit 10     # пилотно
  python3 03_translate_deepseek.py --only v1-054-04
  python3 03_translate_deepseek.py --show-prompt
  python3 03_translate_deepseek.py
"""

import argparse
import json
import os
import re
import sys
import threading
import time
from concurrent.futures import ThreadPoolExecutor

import requests

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.dirname(SCRIPT_DIR)
WORK_DIR = os.path.join(PROJECT_DIR, 'work')
OUT_DIR = os.path.join(WORK_DIR, 'translated')

# Ключът е общ с предишните преводи. НЕ се копира тук — само се чете.
ENV_FILES = [
    os.path.join(PROJECT_DIR, '.env'),
    os.path.join(SCRIPT_DIR, '.env'),
    os.path.expanduser('~/Desktop/azbyka.ru/.env'),
]

API_URL = 'https://api.deepseek.com/chat/completions'
MODEL = 'deepseek-v4-pro'
TEMPERATURE = 0.3

RE_LINE = re.compile(r'^\s*\[(\d+)\]\s?(.*)$')
RE_ATOM = re.compile(r'⟦(\d+)⟧')
RE_QUOTE = re.compile(r'«[^«»]{2,}»')

_local = threading.local()
_lock = threading.Lock()


def session():
    """requests.Session не е безопасна за споделяне между нишки."""
    if not hasattr(_local, 's'):
        _local.s = requests.Session()
    return _local.s


# ─── Промптът ─────────────────────────────────────────────────────────────
SYSTEM_PROMPT = """Ти си опитен преводач на православна духовна литература от руски на български.

Превеждаш кратки поучения на преподобните Оптински старци (XIX – началото на XX век) — прп. Лъв, Макарий, Моисей, Антоний, Иларион, Амвросий, Анатолий, Исаакий, Иосиф, Варсонофий, Нектарий, Никон. Всяко поучение е извадка от писмо, беседа или житие и се чете самò, като сентенция за деня.

Правила:
1. Превеждай СМИСЪЛА, не буквално — на естествен църковен български. Езикът на старците е от XIX век, стегнат, с църковнославянски примеси и с дълги подчинени изречения. Пази тази строгост: не го приглаждай до съвременна разговорна реч и не го разводнявай с обяснения.
2. НЕ СЪКРАЩАВАЙ. Всяка мисъл от оригинала трябва да я има в превода — до последното подчинено изречение. Ако руското изречение е дълго, може да го разчлениш на две български, но не изхвърляй нищо и не обобщавай.
3. Обръщението се пази точно както е в оригинала: „ти" си остава „ти", „вие" си остава „вие", безличното си остава безлично. Не ги уеднаквявай и не ги обезличавай.
4. Аскетическите и богословските термини се пренасят в установения си български вид: „умиление", „трезвение", „внимание", „богоугождение", „ревност", „съкрушение", „помисли", „страсти", „подвиг", „благодат", „смирение", „послушание", „отсичане на волята", „откровение на помислите", „безмолвие", „сребролюбие", „славолюбие", „сластолюбие". НЕ ги обяснявай и НЕ ги заменяй с всекидневни думи.
5. КАВИЧКИТЕ «…» СА НАЙ-ВАЖНОТО ТЕХНИЧЕСКО ИЗИСКВАНЕ. По тях се разпознават цитатите — от Свещеното Писание, от светите отци и от богослужебните книги. Спазвай и трите правила:
   а) Броят на двойките « » в превода трябва да е ТОЧНО същият както в оригинала — нито една повече, нито една по-малко.
   б) НЕ превръщай « » в „ " или в " ". Знаците « и » се пренасят като « и ».
   в) Където оригиналът ИМА « », пази ги — каквото и да стои вътре. Където НЯМА, не добавяй. Ако българският непременно иска кавички за пряка реч, сложи „…".
   Текстът вътре в « » се превежда заедно с останалото; пазят се само знаците.
6. Запушалките ⟦1⟧, ⟦2⟧ и т.н. са препратки към Свещеното Писание. Пренасяй ги НЕПРОМЕНЕНИ и на същото място в изречението. Не ги превеждай, не ги преномерирай, не добавяй нови и не изпускай нито една.
7. Имената на светии, места и празници използвай в утвърдените им български православни форми: Йоан, Атон, Оптина пустиня, Сретение Господне, Успение Богородично, Въведение Богородично, Въздвижение на Честния Кръст, Преображение Господне, Възнесение Господне, Петдесетница, Рождество Христово, Богоявление.
8. Не добавяй свои обяснения, бележки, заглавия и не повтаряй темата в текста. Само превода.

Формат на входа и изхода:

Първо получаваш списък с темите — той е САМО за ориентир и НЕ се превежда и НЕ се включва в отговора. После идват откъсите, номерирани, по един на ред.

Отговори със същите номера, в същия ред и със същия брой редове:
[1] превод на първия
[2] превод на втория

Не сливай, не разделяй и не пропускай редове.
"""


def load_api_key(env_file):
    for path in ([env_file] if env_file else []) + ENV_FILES:
        if path and os.path.exists(path):
            for line in open(path, encoding='utf-8'):
                line = line.strip()
                if line.startswith('DEEPSEEK_API_KEY='):
                    return line.split('=', 1)[1].strip(), path
    key = os.environ.get('DEEPSEEK_API_KEY')
    if key:
        return key, 'средата'
    print('Няма DEEPSEEK_API_KEY. Търсих в:\n  %s' % '\n  '.join(ENV_FILES))
    sys.exit(1)


def parse_response(text, n):
    """Разбива отговора обратно на номерирани редове. Връща списък с дължина
    n или None, ако номерата не съвпадат."""
    out, cur = {}, None
    for line in text.splitlines():
        m = RE_LINE.match(line)
        if m:
            cur = int(m.group(1))
            out[cur] = m.group(2)
        elif cur is not None and line.strip():
            out[cur] += ' ' + line.strip()
    if set(out) != set(range(1, n + 1)):
        return None
    return [out[i].strip() for i in range(1, n + 1)]


def integrity(items, translated):
    """Проверява какво е оцеляло. Връща описание на повредата или None."""
    for q, dst in zip(items, translated):
        src = q['body_ru']
        want = sorted(RE_ATOM.findall(src))
        got = sorted(RE_ATOM.findall(dst))
        if want != got:
            return '%s: запушалки — очаквах %s, върна %s' % (
                q['id'], want or 'нищо', got or 'нищо')
        if src.count('«') == src.count('»'):
            if len(RE_QUOTE.findall(src)) != len(RE_QUOTE.findall(dst)):
                return '%s: цитати в «…» — %d в оригинала, %d в превода' % (
                    q['id'], len(RE_QUOTE.findall(src)),
                    len(RE_QUOTE.findall(dst)))
        # Българският е с 3–8% по-дълъг от руския при същия смисъл. Падне ли
        # преводът под 70% от оригинала, моделът е обобщил вместо да преведе —
        # точно това, което правило 2 забранява.
        if len(dst) < 0.70 * len(src):
            return '%s: преводът е съкратен (%d знака срещу %d)' % (
                q['id'], len(dst), len(src))
    return None


def translate_batch(api_key, items, retries, usage):
    n = len(items)
    head = ['(Теми на откъсите — само за ориентир, НЕ ги превеждай и НЕ ги '
            'включвай в отговора:']
    for i, q in enumerate(items, 1):
        head.append('[%d] %s — прп. %s' % (i, q['topic_ru'], q['elder']))
    head.append(')\n')
    head.append('Откъси за превод:')
    for i, q in enumerate(items, 1):
        head.append('[%d] %s' % (i, ' '.join(q['body_ru'].split())))
    user_prompt = '\n'.join(head)

    headers = {'Authorization': 'Bearer %s' % api_key,
               'Content-Type': 'application/json'}
    payload = {
        'model': MODEL,
        'messages': [{'role': 'system', 'content': SYSTEM_PROMPT},
                     {'role': 'user', 'content': user_prompt}],
        'temperature': TEMPERATURE,
        'stream': False,
    }

    last = None
    for attempt in range(1, retries + 1):
        try:
            r = session().post(API_URL, json=payload, headers=headers,
                               timeout=300)
            if r.status_code == 429:
                wait = 5 * attempt
                print('    429 — чакам %ds' % wait)
                time.sleep(wait)
                continue
            r.raise_for_status()
            data = r.json()
            u = data.get('usage') or {}
            with _lock:
                usage['requests'] += 1
                usage['prompt_tokens'] += u.get('prompt_tokens', 0)
                usage['completion_tokens'] += u.get('completion_tokens', 0)

            parts = parse_response(data['choices'][0]['message']['content'], n)
            if parts is None:
                last = 'разминаване в броя/номерата на редовете'
            elif any(not p for p in parts):
                last = 'празен ред в отговора'
            else:
                last = integrity(items, parts)
                if not last:
                    return parts
            print('    опит %d/%d: %s' % (attempt, retries, last))
        except Exception as e:
            last = e
            print('    опит %d/%d неуспешен: %s' % (attempt, retries, e))
            time.sleep(3 * attempt)
    raise RuntimeError('провал след %d опита: %s' % (retries, last))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--only', action='append', default=[],
                    help='само тези id (напр. --only v1-054-04)')
    ap.add_argument('--limit', type=int)
    ap.add_argument('--redo', action='store_true')
    ap.add_argument('--retries', type=int, default=3)
    ap.add_argument('--workers', type=int, default=6)
    ap.add_argument('--batch', type=int, default=12,
                    help='сентенции в една заявка')
    ap.add_argument('--env-file')
    ap.add_argument('--show-prompt', action='store_true')
    args = ap.parse_args()

    if args.show_prompt:
        print(SYSTEM_PROMPT)
        return

    path = os.path.join(WORK_DIR, 'selected.json')
    if not os.path.exists(path):
        print('Няма %s — пусни първо 02_select.py.' % path)
        sys.exit(1)
    selected = json.load(open(path, encoding='utf-8'))

    api_key, where = load_api_key(args.env_file)
    print('ключът е взет от: %s' % where)
    os.makedirs(OUT_DIR, exist_ok=True)

    todo = []
    for q in selected:
        if args.only and q['id'] not in args.only:
            continue
        if not args.redo and os.path.exists(
                os.path.join(OUT_DIR, q['id'] + '.json')):
            continue
        todo.append(q)
    if args.limit:
        todo = todo[:args.limit]

    print('=' * 64)
    print('избрани: %d | за превод сега: %d | в порция: %d | нишки: %d'
          % (len(selected), len(todo), args.batch, args.workers))
    if not todo:
        print('Няма какво да се превежда.')
        return

    usage_path = os.path.join(WORK_DIR, 'usage.json')
    usage = (json.load(open(usage_path, encoding='utf-8'))
             if os.path.exists(usage_path)
             else {'requests': 0, 'prompt_tokens': 0, 'completion_tokens': 0})

    chunks = [todo[i:i + args.batch] for i in range(0, len(todo), args.batch)]
    counter, failed = {'n': 0}, []

    def run(items):
        parts = translate_batch(api_key, items, args.retries, usage)
        for q, bg in zip(items, parts):
            out = dict(q)
            out['body_bg'] = bg
            with open(os.path.join(OUT_DIR, q['id'] + '.json'), 'w',
                      encoding='utf-8') as fh:
                json.dump(out, fh, ensure_ascii=False, indent=1)
        with _lock:
            counter['n'] += len(items)
            print('[%d/%d] %s … %s' % (counter['n'], len(todo),
                                       items[0]['id'], items[-1]['id']))
            with open(usage_path, 'w', encoding='utf-8') as fh:
                json.dump(usage, fh, ensure_ascii=False, indent=1)

    with ThreadPoolExecutor(max_workers=args.workers) as pool:
        for fut in [pool.submit(run, ch) for ch in chunks]:
            try:
                fut.result()
            except Exception as e:
                failed.append(str(e))

    print('-' * 64)
    if failed:
        print('ПРОВАЛЕНИ порции: %d' % len(failed))
        for msg in failed[:10]:
            print('  %s' % msg)
        print('(пусни наново — готовите се прескачат)')
    print('заявки: %d | входни токени: %d | изходни токени: %d'
          % (usage['requests'], usage['prompt_tokens'],
             usage['completion_tokens']))
    print('→ %s' % OUT_DIR)


if __name__ == '__main__':
    main()
