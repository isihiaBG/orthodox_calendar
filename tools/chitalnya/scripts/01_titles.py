#!/usr/bin/env python3
"""Заглавията за „Читалня" → work/titles.json (кеш; преведеното не се плаща
наново).

    python3 01_titles.py

Превежда с DeepSeek САМО заглавия — текстовете вече са преведени:
  • темите (дяловете) на „Симфонията" за Оптинските старци (src_topic_ru);
  • заглавията на поученията на свт. Теофан (src_title_ru).
"""
import json
import re
import sqlite3
import sys
import time
from pathlib import Path

import requests

ROOT = Path(__file__).resolve().parents[1]
PROJ = ROOT.parents[1]
OUT = ROOT / 'work' / 'titles.json'
ENV = [PROJ / 'tools' / 'azbyka.ru' / '.env']
API = 'https://api.deepseek.com/chat/completions'
MODEL = 'deepseek-v4-pro'

PROMPT = '''Превеждаш от руски на български КРАТКИ ЗАГЛАВИЯ от православни книги.
Всеки ред е „[N] текст"; върни ТОЧНО същите номера, по един на ред: „[N] превод".
Без обяснения. Църковната терминология е българската:
  Неделя мытаря и фарисея → Неделя на митаря и фарисея; Неделя блудного → Неделя на блудния син;
  Неделя мясопустная → Месопустна неделя; Сыропустная неделя → Сиропустна неделя;
  Неделя Ваий → Неделя Ваия (Връбница); Светлое Христово Воскресение → Светло Христово Възкресение;
  Фомина неделя → Томина неделя; по Пятидесятнице → след Петдесетница;
  Сретение → Сретение Господне; Введение → Въведение; Богоявление → Богоявление;
  Суббота → Събота; Неделя (за ден) → Неделя; седмица остава седмица.
Числата и скобите се пазят („Понедельник (32-й)" → „Понеделник (32-ри)").
Темите от речник са с ГЛАВНИ БУКВИ на руски — превеждай ги с главна буква само отпред
(„АД" → „Ад", „АККУРАТНОСТЬ" → „Акуратност").'''


def key():
    for p in ENV:
        if p.exists():
            for line in p.read_text(encoding='utf-8').splitlines():
                if line.strip().startswith('DEEPSEEK_API_KEY='):
                    return line.split('=', 1)[1].strip()
    sys.exit('Няма DEEPSEEK_API_KEY')


def ask(k, items):
    body = '\n'.join('[%d] %s' % (i, t) for i, t in enumerate(items, 1))
    for attempt in range(4):
        r = requests.post(API, timeout=600, headers={'Authorization': 'Bearer ' + k}, json={
            'model': MODEL, 'temperature': 0.3, 'stream': False,
            'messages': [{'role': 'system', 'content': PROMPT},
                         {'role': 'user', 'content': body}]})
        if r.status_code == 429:
            time.sleep(5 * (attempt + 1))
            continue
        r.raise_for_status()
        txt = r.json()['choices'][0]['message']['content']
        got = {int(m.group(1)): m.group(2).strip()
               for m in re.finditer(r'^\s*\[(\d+)\]\s*(.*)$', txt, re.M)}
        if sorted(got) == list(range(1, len(items) + 1)):
            return [got[i] for i in range(1, len(items) + 1)]
        print('  ⚠ разминаване в номерата, нов опит')
    sys.exit('⚠ преводът не се получи')


def main():
    db = PROJ / 'assets' / 'db'
    want = set()
    for (t,) in sqlite3.connect(db / 'optina.db').execute(
            'SELECT DISTINCT src_topic_ru FROM sayings'):
        want.add(t)
    for (t,) in sqlite3.connect(db / 'teofan.db').execute(
            'SELECT DISTINCT src_title_ru FROM thoughts'):
        want.add(re.sub(r'\*\d+', '', t).strip())
    done = json.loads(OUT.read_text(encoding='utf-8')) if OUT.exists() else {}
    todo = sorted(t for t in want if t and t not in done)
    print('за превод: %d (готови %d)' % (len(todo), len(done)))
    k = key()
    for i in range(0, len(todo), 80):
        part = todo[i:i + 80]
        for src, bg in zip(part, ask(k, part)):
            done[src] = bg
        OUT.write_text(json.dumps(done, ensure_ascii=False, indent=1), encoding='utf-8')
        print('  %d/%d' % (min(i + 80, len(todo)), len(todo)))
    print('→', OUT)


if __name__ == '__main__':
    main()
