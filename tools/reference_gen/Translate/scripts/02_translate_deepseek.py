#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
02_translate_deepseek.py — Стъпка 2 (ЕДИНСТВЕНАТА, която харчи пари):
превежда единиците от ../work/units/ от руски на български.

Стъпва на 03_translate_deepseek.py от превода на житията
(tools/Translate_lives/scripts/) — същият модел, същата температура, същият
протокол "[1] …" и същото поведение при прекъсване. Разликите са три и са
нарочни:

 1. НЯМА запушалки ⟦n⟧ и проверки за сдвоени тагове — входът тук е чист
    текст, без никакъв markup.
 2. Промптът е ДРУГ по род. Житията искат разказвателен синаксарен език;
    тези текстове са уставни и справочни — цитати от Типика, канонически
    правила, указания. Затова уводът и правило 1 са преписани за този род,
    а правилата за имената и за „без добавки от себе си“ са запазени
    дословно, за да звучи всичко от едната ръка.
 3. Заглавието се превежда ЗАЕДНО с текста, като първа единица — така
    моделът вижда за какво става дума, преди да тръгне по абзаците.

Съкращенията (5-01) НЕ се превеждат — руските съкращения нямат
съответствие едно към едно в българските и ще се направят отделно на ръка.
Виж SKIP_IDS; с --include-skipped може да се пусне и то.

Може да се прекъсва и пуска наново — статия с готов файл в translated/ се
прескача (освен с --redo).

Вход:
  ../work/units/*.json          (от 01_extract.py)
  ключ DEEPSEEK_API_KEY — търси се в ../.env, после в ~/Desktop/azbyka.ru/.env

Изход:
  ../work/translated/<id>.json
  ../work/usage.json            натрупани токени и брой заявки

Употреба:
  python3 02_translate_deepseek.py --limit 2        # пилотно, две статии
  python3 02_translate_deepseek.py --only 2-07
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

# Съкращенията — отделна задача, виж горе.
SKIP_IDS = {"5-01"}

RE_LINE = re.compile(r"^\s*\[(\d+)\]\s?(.*)$")

_local = threading.local()
_lock = threading.Lock()


def session():
    """requests.Session не е безопасна за споделяне между нишки."""
    if not hasattr(_local, "s"):
        _local.s = requests.Session()
    return _local.s


# ─── Промптът ─────────────────────────────────────────────────────────────
SYSTEM_PROMPT = """Ти си опитен преводач на православна църковна литература от руски на български.

Превеждаш справочни и уставни текстове за православен календар: канонически правила, указания от Типикона за постите и трапезата, наставления за поменаването на покойниците, богослужебни редове.

Правила:
1. Превеждай СМИСЪЛА, не буквално — на точен и сдържан църковен български, какъвто се използва в български богослужебни указания и наръчници. Това не е разказ, а наставление: пази яснотата и премереността на оригинала, не го украсявай и не го разводнявай.
2. Имената на светии, места и събори използвай в утвърдените им български православни форми, ако съществуват такива (напр. "Йоан", не "Иоанн"; "Атон", не "Афон", освен когато става дума за конкретен собствен принадлежащ израз). Ако не си сигурен в утвърдена форма, транслитерирай последователно.
3. Не добавяй свои обяснения, бележки или заглавия — само превода.
4. Цитатите от Типикона и от богослужебните книги, дадени на църковнославянски, ОСТАВЯЙ както са, без да ги превеждаш и без да ги побългаряваш. Превежда се само руският текст около тях.
5. Числата, датите, препратките към глави и правила (напр. "глава 48", "69-то правило", "15.00") пренасяй точно както са.
6. Тези църковни думи имат установен български вид и НЕ бива да остават в руската си форма:
   - "усопший" → "починал" или "покойник" (никога "усопш");
   - "поминовение", "поминать" → "помен", "поменаване", "поменавам" (не "поменуване");
   - "кутия" (обредното ястие) → "коливо" (на български "кутия" значи съвсем друго);
   - "мытарства" → "митарства";
   - "заупокойный" → "заупокоен";
   - "сорокоуст" → "четиридесет литургии";
   - "новопреставленный" → "новопреставен";
   - "предпразднство" → "предпразненство";
   - "сухоядение" → "сухоядение".
   Останалите църковни термини (панихида, лития, ектения, поклон, седмица, трапеза, литургия, проскомидия) се пишат еднакво на двата езика.

Формат на входа и изхода:

Входът е номериран списък от откъси, по един на ред:
[1] първи откъс
[2] втори откъс

Отговори със същите номера, в същия ред и със същия брой редове:
[1] превод на първия
[2] превод на втория

Не сливай, не разделяй и не пропускай откъси. Всеки откъс е отделен абзац или отделен запис от списък и трябва да остане отделен ред в отговора.
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
    """Реже дългите статии на порции. Най-дългата тук е около 90 единици —
    подадена наведнъж, отговорът рискува да опре в тавана за изход и да се
    отреже по средата. Редът се пази, порциите се превеждат последователно."""
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


def translate_batch(api_key, units, context, retries, usage):
    n = len(units)
    lines = []
    if context:
        lines.append("(Контекст, НЕ го превеждай и НЕ го включвай в отговора: "
                     "това е продължение на текста „%s“.)\n" % context)
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
            return parts
        except Exception as e:
            last = e
            print("    опит %d/%d неуспешен: %s" % (attempt, retries, e))
            time.sleep(3 * attempt)
    raise RuntimeError("провал след %d опита: %s" % (retries, last))


def translate_article(api_key, art, args, usage):
    """Заглавието влиза като първа единица — моделът вижда темата, преди да
    тръгне по абзаците, а и самото заглавие трябва да е преведено."""
    all_units = [art["title_ru"]] + art["units"]
    result = []
    context = None
    for chunk in batches(all_units, args.max_units, args.max_chars):
        parts = translate_batch(api_key, chunk, context, args.retries, usage)
        result.extend(parts)
        if context is None:
            context = result[0]          # преведеното заглавие
    return result[0], result[1:]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", action="append", default=[],
                    help="само тези id-та (напр. --only 2-07)")
    ap.add_argument("--limit", type=int)
    ap.add_argument("--redo", action="store_true")
    ap.add_argument("--retries", type=int, default=3)
    ap.add_argument("--workers", type=int, default=6)
    ap.add_argument("--max-units", type=int, default=40)
    ap.add_argument("--max-chars", type=int, default=6000)
    ap.add_argument("--include-skipped", action="store_true",
                    help="преведи и съкращенията (5-01)")
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
        print("Няма разглобени статии в %s — пусни 01_extract.py." % UNITS_DIR)
        sys.exit(1)

    todo = []
    for f in files:
        aid = os.path.splitext(os.path.basename(f))[0]
        if args.only and aid not in args.only:
            continue
        if aid in SKIP_IDS and not args.include_skipped and not args.only:
            continue
        if not args.redo and os.path.exists(os.path.join(OUT_DIR, aid + ".json")):
            continue
        todo.append(f)
    if args.limit:
        todo = todo[:args.limit]

    print("=" * 64)
    print("статии общо: %d | за превод сега: %d | нишки: %d"
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
        art = json.load(open(path, encoding="utf-8"))
        try:
            title_bg, units_bg = translate_article(api_key, art, args, usage)
        except Exception as e:
            raise RuntimeError("%s: %s" % (art["id"], e)) from None
        art["title_bg"] = title_bg
        art["units_bg"] = units_bg
        with open(os.path.join(OUT_DIR, art["id"] + ".json"), "w",
                  encoding="utf-8") as fh:
            json.dump(art, fh, ensure_ascii=False, indent=1)
        with _lock:
            counter["n"] += 1
            print("[%d/%d] %s — %d единици — %s"
                  % (counter["n"], total, art["id"], len(units_bg), title_bg))
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
