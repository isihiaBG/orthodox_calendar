#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
02b_translate_notes.py — Стъпка 2б (харчи стотинки): превежда бележките
под линия.

Бележките в книгата са 51 и се делят на две по произход:

  *1–*5   гражданската дата от 1887 г. („15.1.1887"). Това е редакционен
          апарат на „Азбука Веры" за годината, за която е писана книгата.
          Сочат се САМО от заглавията и нямат смисъл в приложението —
          датата вече е записана в справочната колона src_date_1887.
          НЕ се превеждат.

  останалите 46
          същинско съдържание: източници („Макарий Великий. «Беседы», 4,
          6."), богослужебни указания („Стихира Октоиха, глас 6…"),
          пояснения („Далила – Далида, блудница из Суд.16…"). Всичките 46
          препратки в текста на поученията сочат тъкмо към тях, тъй че се
          превеждат.

Разделението е проверено, не предположено — виж отчета накрая.

Бележките са къси и самостоятелни, затова тук няма нито порциониране, нито
контекст: всички влизат в една заявка.

Вход:
  ../work/notes.json            (от 01_extract.py)
  ../work/units/*.json          за да се види кои бележки се ползват

Изход:
  ../work/notes_bg.json

Употреба:
  python3 02b_translate_notes.py
  python3 02b_translate_notes.py --redo
"""

import argparse
import glob
import json
import os
import re
import sys

import requests

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.dirname(SCRIPT_DIR)
WORK_DIR = os.path.join(PROJECT_DIR, "work")

ENV_FILES = [
    os.path.join(PROJECT_DIR, ".env"),
    os.path.join(SCRIPT_DIR, ".env"),
    os.path.expanduser("~/Desktop/azbyka.ru/.env"),
]

API_URL = "https://api.deepseek.com/chat/completions"
MODEL = "deepseek-v4-pro"
TEMPERATURE = 0.3

RE_LINE = re.compile(r"^\s*\[(\d+)\]\s?(.*)$")
RE_DATE_ONLY = re.compile(r"\d{1,2}\.\d{1,2}\.1887")

SYSTEM_PROMPT = """Ти си опитен преводач на православна литература от руски на български.

Превеждаш бележки под линия към „Мисли за всеки ден от годината" на свт. Теофан Затворник. Бележките са кратки и справочни: посочват източник на цитат, назовават богослужебен текст (стихира, тропар, канон, самогласен) или поясняват библейско лице.

Правила:
1. Превеждай кратко и точно, както е в оригинала. Това са бележки, не текст за четене — не ги разгръщай.
2. Църковнославянските цитати ОСТАВЯЙ както са, без да ги превеждаш и без да ги побългаряваш.
3. Имената на светии и на богослужебни книги използвай в утвърдените им български форми: Октоих, Триод, Минея, Часослов, Макарий Велики, Йоан Златоуст.
4. Названията на богослужебните части се пренасят: стихира, самогласен, тропар, кондак, седален, канон, шестопсалмие, велико славословие, утреня, вечерня, отпуст.
5. Числата и стиховете пренасяй точно както са. Съкращенията на библейските книги ЗАДЪЛЖИТЕЛНО се заменят по това съответствие (руско → българско):
   Мф. → Мт.;  Мк. → Мк.;  Лк. → Лк.;  Ин. → Ин.;  Деян. → Деян.;
   Иак. → Иак.;  1Пет. → 1 Пет.;  2Пет. → 2 Пет.;  1Ин. → 1 Ин.;
   Рим. → Рим.;  1Кор. → 1 Кор.;  2Кор. → 2 Кор.;  Гал. → Гал.;
   Еф. → Еф.;  Флп. → Фил.;  Кол. → Кол.;  1Фес. → 1 Сол.;
   1Тим. → 1 Тим.;  2Тим. → 2 Тим.;  Евр. → Евр.;  Апок. → Откр.;
   Быт. → Бит.;  Исх. → Изх.;  Втор. → Втор.;  Суд. → Съд.;  Пс. → Пс.;
   Прит. → Притч.;  Прем. → Прем.;  Сир. → Сир.;  Ис. → Ис.;
   Иоил. → Иоил.;  Ам. → Ам.;  Зах. → Зах.
   Не оставяй руската форма и не пиши дългите варианти „Мат.", „Марк.", „Лук.", „Иоан." — тези съкращения се явяват и в текста на поученията и трябва да съвпадат навсякъде.
6. Приписката „– Редакция «Азбуки Веры»" превеждай като „– Редакция на «Азбука Веры»".
7. Не добавяй свои обяснения — само превода.

Формат на входа и изхода:

Входът е номериран списък, по една бележка на ред:
[1] първа бележка
[2] втора бележка

Отговори със същите номера, в същия ред и със същия брой редове.
"""


def load_api_key():
    for path in ENV_FILES:
        if os.path.exists(path):
            for line in open(path, encoding="utf-8"):
                line = line.strip()
                if line.startswith("DEEPSEEK_API_KEY="):
                    return line.split("=", 1)[1].strip(), path
    key = os.environ.get("DEEPSEEK_API_KEY")
    if key:
        return key, "средата"
    print("Няма DEEPSEEK_API_KEY. Търсих в:\n  %s" % "\n  ".join(ENV_FILES))
    sys.exit(1)


def parse_response(text, n):
    out, cur = {}, None
    for line in text.splitlines():
        m = RE_LINE.match(line)
        if m:
            cur = int(m.group(1))
            out[cur] = m.group(2)
        elif cur is not None and line.strip():
            out[cur] += " " + line.strip()
    if set(out) != set(range(1, n + 1)):
        return None
    return [out[i].strip() for i in range(1, n + 1)]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--redo", action="store_true")
    ap.add_argument("--retries", type=int, default=3)
    ap.add_argument("--show-prompt", action="store_true")
    args = ap.parse_args()

    if args.show_prompt:
        print(SYSTEM_PROMPT)
        return

    out_path = os.path.join(WORK_DIR, "notes_bg.json")
    if os.path.exists(out_path) and not args.redo:
        print("%s вече съществува — пусни с --redo, за да го презапишеш."
              % out_path)
        return

    notes = json.load(open(os.path.join(WORK_DIR, "notes.json"),
                           encoding="utf-8"))

    # Кои бележки изобщо се сочат от текста на поученията.
    used = set()
    for path in glob.glob(os.path.join(WORK_DIR, "units", "*.json")):
        for atom in json.load(open(path, encoding="utf-8"))["atoms"]:
            if atom["kind"] == "footnote":
                used.add(atom["payload"])

    todo, skipped = [], []
    for key, text in sorted(notes.items()):
        if key not in used or RE_DATE_ONLY.fullmatch(text.strip()):
            skipped.append(key)
        else:
            todo.append(key)

    print("бележки общо: %d | за превод: %d | пропуснати: %d (%s)"
          % (len(notes), len(todo), len(skipped), ", ".join(skipped)))
    if not todo:
        print("Няма какво да се превежда.")
        return

    api_key, where = load_api_key()
    print("ключът е взет от: %s" % where)

    prompt = "\n".join("[%d] %s" % (i, " ".join(notes[k].split()))
                       for i, k in enumerate(todo, 1))
    payload = {
        "model": MODEL,
        "messages": [{"role": "system", "content": SYSTEM_PROMPT},
                     {"role": "user", "content": prompt}],
        "temperature": TEMPERATURE,
        "stream": False,
    }
    headers = {"Authorization": "Bearer %s" % api_key,
               "Content-Type": "application/json"}

    parts = None
    for attempt in range(1, args.retries + 1):
        try:
            r = requests.post(API_URL, json=payload, headers=headers,
                              timeout=300)
            r.raise_for_status()
            data = r.json()
            parts = parse_response(data["choices"][0]["message"]["content"],
                                   len(todo))
            if parts is None:
                print("  опит %d/%d: разминаване в номерата на редовете"
                      % (attempt, args.retries))
                continue
            usage = data.get("usage") or {}
            print("входни токени: %d | изходни токени: %d"
                  % (usage.get("prompt_tokens", 0),
                     usage.get("completion_tokens", 0)))
            break
        except Exception as e:
            print("  опит %d/%d неуспешен: %s" % (attempt, args.retries, e))
    if parts is None:
        sys.exit("провал след %d опита" % args.retries)

    result = dict(zip(todo, parts))

    # Ръчните поправки имат превес над модела и НЕ се губят при --redo.
    # Същият похват както manual_notes.json в конвейера за житията: превод,
    # поправен направо в notes_bg.json, изчезва при следващото пускане,
    # затова поправките живеят отделно.
    manual_path = os.path.join(SCRIPT_DIR, "manual_notes.json")
    if os.path.exists(manual_path):
        manual = json.load(open(manual_path, encoding="utf-8"))
        applied = [k for k in manual if k in result]
        result.update({k: v for k, v in manual.items() if k in result})
        print("ръчни поправки: %d (%s)" % (len(applied), ", ".join(applied)))

    with open(out_path, "w", encoding="utf-8") as fh:
        json.dump(result, fh, ensure_ascii=False, indent=1)
    print("→ %s (%d бележки)" % (out_path, len(result)))


if __name__ == "__main__":
    main()
