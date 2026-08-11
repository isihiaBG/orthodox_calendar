#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
02_translate_deepseek.py — Стъпка 2 (ЕДИНСТВЕНАТА, която харчи пари):
превежда поученията на свт. Теофан Затворник от руски на български.

Стъпва на 02_translate_deepseek.py от справочника
(tools/reference_gen/Translate/scripts/) — същият модел, същата температура,
същият протокол „[1] …", същото поведение при прекъсване и същият отчет на
токените. Разликите са четири и са нарочни:

 1. ИМА запушалки ⟦N⟧ и проверка, че всички са оцелели — за разлика от
    справочника, тук входът носи препратки към Писанието и към бележки.
    Всяка запушалка трябва да се появи в превода точно веднъж; ако не —
    порцията се превежда наново.
 2. ЗАГЛАВИЕТО НЕ СЕ ПРЕВЕЖДА. Подава се само като контекст, за да знае
    моделът за какъв ден става дума. На български денят си има име в
    календарната база („Неделя 12 след Петдесетница") и втори набор имена,
    дошъл от книгата, само би се разминал с него.
 3. Промптът е за друг род текст. Справочникът е уставен и сух; тук е
    духовно поучение — размисъл върху дневното евангелско четиво, писан на
    „ти", с топлина, но без сладникавост.
 4. Кавичките «…» се пренасят непокътнати. Те не са запушалки, а обикновени
    знаци, но по тях 03_build_db.py разпознава цитатите от Писанието, за да
    ги обвие в <cite> — а по-късно да ги сверим със синодалното издание.
    Затова се броят преди и след превода.

Може да се прекъсва и пуска наново — поучение с готов файл в translated/ се
прескача (освен с --redo).

Вход:
  ../work/units/*.json          (от 01_extract.py)
  ключ DEEPSEEK_API_KEY — търси се в ../.env, после в ~/Desktop/azbyka.ru/.env

Изход:
  ../work/translated/NNN.json
  ../work/usage.json            натрупани токени и брой заявки

Употреба:
  python3 02_translate_deepseek.py --limit 4       # пилотно, четири поучения
  python3 02_translate_deepseek.py --only 018
  python3 02_translate_deepseek.py --show-prompt
  python3 02_translate_deepseek.py
"""

import argparse
import glob
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
WORK_DIR = os.path.join(PROJECT_DIR, "work")
UNITS_DIR = os.path.join(WORK_DIR, "units")
OUT_DIR = os.path.join(WORK_DIR, "translated")

# Ключът е общ с предишните преводи. НЕ се копира тук — само се чете.
ENV_FILES = [
    os.path.join(PROJECT_DIR, ".env"),
    os.path.join(SCRIPT_DIR, ".env"),
    os.path.expanduser("~/Desktop/azbyka.ru/.env"),
]

API_URL = "https://api.deepseek.com/chat/completions"
MODEL = "deepseek-v4-pro"
TEMPERATURE = 0.3

RE_LINE = re.compile(r"^\s*\[(\d+)\]\s?(.*)$")
RE_ATOM = re.compile(r"⟦(\d+)⟧")
RE_QUOTE = re.compile(r"«[^«»]{2,}»")

_local = threading.local()
_lock = threading.Lock()


def session():
    """requests.Session не е безопасна за споделяне между нишки."""
    if not hasattr(_local, "s"):
        _local.s = requests.Session()
    return _local.s


# ─── Промптът ─────────────────────────────────────────────────────────────
SYSTEM_PROMPT = """Ти си опитен преводач на православна духовна литература от руски на български.

Превеждаш „Мисли за всеки ден от годината" на свт. Теофан Затворник — кратки размисли върху евангелското и апостолското четиво за деня. Това не е устав и не е разказ, а живо поучение: светителят се обръща към читателя на „ти", подтиква го, пита го, изобличава го с любов. Пази тази интонация.

Правила:
1. Превеждай СМИСЪЛА, не буквално — на естествен църковен български. Изреченията на свт. Теофан са дълги и с много подчинени части; може да ги разчлениш, ако българският го изисква, но не съкращавай мисълта и не я разводнявай.
2. Обръщението е на „ти" (второ лице единствено число), както е в оригинала. Не го превръщай във „вие" и не го обезличавай.
3. Аскетическите и богословските термини се пренасят буквално, в установения си български вид: „умиление", „трезвение", „внимание", „богоугождение", „ревност", „съкрушение", „помисли", „страсти", „подвиг", „благодат". НЕ ги обяснявай и НЕ ги заменяй с всекидневни думи.
4. КАВИЧКИТЕ «…» СА НАЙ-ВАЖНОТО ТЕХНИЧЕСКО ИЗИСКВАНЕ. По тях се разпознават цитатите от Свещеното Писание. Спазвай и трите правила:
   а) Броят на двойките « » в превода трябва да е ТОЧНО същият както в оригинала — нито една повече, нито една по-малко. Ако абзацът има две двойки, преводът има точно две.
   б) НЕ превръщай « » в „ " или в " ". Знаците « и » се пренасят като « и ».
   в) Където оригиналът ИМА « », пази ги — каквото и да стои вътре. Свт. Теофан огражда с « » не само Писанието, а и чужда реч, въображаем възглас на неверник, отделна дума. НЕ ти решаваш кое заслужава « » и кое не; следваш оригинала.
      Където оригиналът НЯМА кавички, не добавяй « ». Ако българският непременно иска кавички за пряка реч, сложи „…".
   г) Свт. Теофан често цитира дълъг стих, а после повтаря две-три думи от него пак в « ». Това НЕ е излишно повторение — то е ново позоваване на същия стих. Кратките повторения ЗАДЪЛЖИТЕЛНО остават в « », със същите думи както в дългия цитат.
   Текстът вътре в « » се превежда заедно с останалото; пазят се само знаците.
5. Запушалките ⟦1⟧, ⟦2⟧ и т.н. са препратки. Пренасяй ги НЕПРОМЕНЕНИ и на същото място в изречението. Не ги превеждай, не ги преномерирай, не добавяй нови и не изпускай нито една.
6. „Неделя" в църковния език значи НЕДЕЛНИЯТ ДЕН, а не седмицата. „Неделя двенадцатая по Пятидесятнице" е „Неделя 12 след Петдесетница". Седмицата се казва „седмица".
7. Имената на светии, места и празници използвай в утвърдените им български православни форми: Йоан, Атон, Сретение Господне, Успение Богородично, Въведение Богородично, Въздвижение на Честния Кръст, Преображение Господне, Възнесение Господне, Петдесетница, Рождество Христово, Богоявление.
8. Не добавяй свои обяснения, бележки или заглавия — само превода.

Формат на входа и изхода:

Входът е номериран списък от абзаци, по един на ред:
[1] първи абзац
[2] втори абзац

Отговори със същите номера, в същия ред и със същия брой редове:
[1] превод на първия
[2] превод на втория

Не сливай, не разделяй и не пропускай абзаци.
"""


def load_api_key(env_file):
    for path in ([env_file] if env_file else []) + ENV_FILES:
        if path and os.path.exists(path):
            for line in open(path, encoding="utf-8"):
                line = line.strip()
                if line.startswith("DEEPSEEK_API_KEY="):
                    return line.split("=", 1)[1].strip(), path
    key = os.environ.get("DEEPSEEK_API_KEY")
    if key:
        return key, "средата"
    print("Няма DEEPSEEK_API_KEY. Търсих в:\n  %s" % "\n  ".join(ENV_FILES))
    sys.exit(1)


def batches(units, max_units, max_chars):
    """Реже дългите поучения на порции, за да не опре отговорът в тавана."""
    out, cur, cur_chars = [], [], 0
    for u in units:
        if cur and (len(cur) >= max_units or cur_chars + len(u) > max_chars):
            out.append(cur)
            cur, cur_chars = [], 0
        cur.append(u)
        cur_chars += len(u)
    if cur:
        out.append(cur)
    return out


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
            # Моделът е пренесъл абзаца на нов ред — долепяме го.
            out[cur] += " " + line.strip()
    if set(out) != set(range(1, n + 1)):
        return None
    return [out[i].strip() for i in range(1, n + 1)]


def integrity(source, translated):
    """Проверява какво е оцеляло. Връща описание на повредата или None.

    Двете неща, които не бива да се губят, са запушалките (иначе препратката
    увисва) и кавичките (иначе цитатът не може да се разпознае после).
    """
    for src, dst in zip(source, translated):
        want = sorted(RE_ATOM.findall(src))
        got = sorted(RE_ATOM.findall(dst))
        if want != got:
            return "запушалки: очаквах %s, върна %s" % (want or "нищо",
                                                        got or "нищо")
        # Книгата има ~20 абзаца, в които кавичките и в оригинала не се
        # връзват: затваряща » без отваряща, или обратното. Там сравнението
        # е безсмислено — не можем да искаме от модела да възпроизведе
        # счупено. Пропускаме проверката, вместо да въртим напразно опити.
        if src.count("«") != src.count("»"):
            continue
        if len(RE_QUOTE.findall(src)) != len(RE_QUOTE.findall(dst)):
            return "цитати в «…»: %d в оригинала, %d в превода" % (
                len(RE_QUOTE.findall(src)), len(RE_QUOTE.findall(dst)))
    return None


def translate_batch(api_key, units, context, retries, usage):
    n = len(units)
    lines = []
    if context:
        lines.append("(Контекст, НЕ го превеждай и НЕ го включвай в отговора: "
                     "това е поучението за „%s“.)\n" % context)
    for i, u in enumerate(units, 1):
        lines.append("[%d] %s" % (i, " ".join(u.split())))
    user_prompt = "\n".join(lines)

    headers = {"Authorization": "Bearer %s" % api_key,
               "Content-Type": "application/json"}
    payload = {
        "model": MODEL,
        "messages": [{"role": "system", "content": SYSTEM_PROMPT},
                     {"role": "user", "content": user_prompt}],
        "temperature": TEMPERATURE,
        "stream": False,
    }

    last = None
    for attempt in range(1, retries + 1):
        try:
            r = session().post(API_URL, json=payload, headers=headers,
                               timeout=300)
            if r.status_code == 429:
                wait = 5 * attempt
                print("    429 — чакам %ds" % wait)
                time.sleep(wait)
                continue
            r.raise_for_status()
            data = r.json()
            u = data.get("usage") or {}
            with _lock:
                usage["requests"] += 1
                usage["prompt_tokens"] += u.get("prompt_tokens", 0)
                usage["completion_tokens"] += u.get("completion_tokens", 0)

            parts = parse_response(data["choices"][0]["message"]["content"], n)
            if parts is None:
                last = "разминаване в броя/номерата на редовете"
                print("    опит %d/%d: %s" % (attempt, retries, last))
                continue
            if any(not p for p in parts):
                last = "празен ред в отговора"
                print("    опит %d/%d: %s" % (attempt, retries, last))
                continue
            damage = integrity(units, parts)
            if damage:
                last = damage
                print("    опит %d/%d: %s" % (attempt, retries, last))
                continue
            return parts
        except Exception as e:
            last = e
            print("    опит %d/%d неуспешен: %s" % (attempt, retries, e))
            time.sleep(3 * attempt)
    raise RuntimeError("провал след %d опита: %s" % (retries, last))


def translate_thought(api_key, unit, args, usage):
    """Заглавието и четивото влизат само като контекст — не се превеждат."""
    context = unit["title_ru"]
    if unit.get("parent_ru"):
        context += " (в книгата стои под „%s“)" % unit["parent_ru"]
    if unit.get("readings"):
        context += " " + unit["readings"]

    result = []
    for chunk in batches(unit["units_ru"], args.max_units, args.max_chars):
        result.extend(translate_batch(api_key, chunk, context, args.retries,
                                      usage))
    return result


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", action="append", default=[],
                    help="само тези номера (напр. --only 018)")
    ap.add_argument("--limit", type=int)
    ap.add_argument("--redo", action="store_true")
    ap.add_argument("--retries", type=int, default=3)
    ap.add_argument("--workers", type=int, default=6)
    ap.add_argument("--max-units", type=int, default=8)
    ap.add_argument("--max-chars", type=int, default=6000)
    ap.add_argument("--env-file")
    ap.add_argument("--show-prompt", action="store_true")
    args = ap.parse_args()

    if args.show_prompt:
        print(SYSTEM_PROMPT)
        return

    api_key, where = load_api_key(args.env_file)
    print("ключът е взет от: %s" % where)

    os.makedirs(OUT_DIR, exist_ok=True)
    files = sorted(glob.glob(os.path.join(UNITS_DIR, "*.json")))
    if not files:
        print("Няма разглобени поучения в %s — пусни 01_extract.py." % UNITS_DIR)
        sys.exit(1)

    todo = []
    for f in files:
        tid = os.path.splitext(os.path.basename(f))[0]
        if args.only and tid not in args.only:
            continue
        if not args.redo and os.path.exists(os.path.join(OUT_DIR, tid + ".json")):
            continue
        todo.append(f)
    if args.limit:
        todo = todo[:args.limit]

    print("=" * 64)
    print("поучения общо: %d | за превод сега: %d | нишки: %d"
          % (len(files), len(todo), args.workers))
    if not todo:
        print("Няма какво да се превежда.")
        return

    usage_path = os.path.join(WORK_DIR, "usage.json")
    usage = (json.load(open(usage_path, encoding="utf-8"))
             if os.path.exists(usage_path)
             else {"requests": 0, "prompt_tokens": 0, "completion_tokens": 0})

    counter, total, failed = {"n": 0}, len(todo), []

    def run(path):
        unit = json.load(open(path, encoding="utf-8"))
        try:
            unit["units_bg"] = translate_thought(api_key, unit, args, usage)
        except Exception as e:
            raise RuntimeError("%03d: %s" % (unit["index"], e)) from None
        out = os.path.join(OUT_DIR, "%03d.json" % unit["index"])
        with open(out, "w", encoding="utf-8") as fh:
            json.dump(unit, fh, ensure_ascii=False, indent=1)
        with _lock:
            counter["n"] += 1
            print("[%d/%d] %03d %s — %d абзаца"
                  % (counter["n"], total, unit["index"],
                     unit["title_ru"][:40], len(unit["units_bg"])))
            with open(usage_path, "w", encoding="utf-8") as fh:
                json.dump(usage, fh, ensure_ascii=False, indent=1)

    with ThreadPoolExecutor(max_workers=args.workers) as pool:
        for fut in [pool.submit(run, f) for f in todo]:
            try:
                fut.result()
            except Exception as e:
                failed.append(str(e))

    print("-" * 64)
    if failed:
        print("ПРОВАЛЕНИ: %d" % len(failed))
        for msg in failed[:10]:
            print("  %s" % msg)
        print("(пусни наново — готовите се прескачат)")
    print("заявки: %d | входни токени: %d | изходни токени: %d"
          % (usage["requests"], usage["prompt_tokens"],
             usage["completion_tokens"]))
    print("→ %s" % OUT_DIR)


if __name__ == "__main__":
    main()
