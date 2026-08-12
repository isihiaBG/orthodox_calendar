#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
03_translate_deepseek.py — Стъпка 3 (ЕДИНСТВЕНАТА, която харчи пари):
превежда групите от ../work/<том>/extract/ от руски на български.

Промптът стъпва ДОСЛОВНО на 10_translate_deepseek.py от предишния превод на
житията (~/Desktop/azbyka.ru/scripts/) — уводът и правила 1, 2 и 5 са
пренесени буква по буква, за да звучи книгата като вече преведените над
хиляда жития. Отпаднаха само правилата за HTML таговете, за тропарите и за
празните CSV полета: тук моделът НЕ вижда markup изобщо (виж 02_extract.py),
няма тропари, а входът не е CSV. Моделът и температурата също са същите.

Речник НЯМА и тук — нарочно, по същата причина, записана в стария скрипт:
натъпкването на десетки конкретни бележки в промпта на самия превод
разсейва модела и влошава качеството другаде. Речникът се прилага в отделна
следваща стъпка върху готовия превод.

Може да се прекъсва и пуска наново — група, за която вече има файл в
translated/, се прескача (освен с --redo).

Вход:
  ../work/<том>/extract/*.json     (от 02_extract.py)
  ../.env                          DEEPSEEK_API_KEY=...   (или --env-file)

Изход:
  ../work/<том>/translated/<група>.json
  ../work/<том>/usage.json         натрупани токени и брой заявки

Употреба:
  python3 03_translate_deepseek.py --vol 09 --limit 3      # пилотно
  python3 03_translate_deepseek.py --vol 09 --group 002_index_split_728_p02
  python3 03_translate_deepseek.py --vol 09 --show-prompt
  python3 03_translate_deepseek.py --vol 09
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

# Заявките са напълно независими една от друга — моделът няма памет между
# тях. Успоредността НЕ влияе на превода; единственото, което трябва да се
# опази, е редът на частите в едно житие (част 2 чака превода на част 1, за
# да вземе оттам името на светеца). Затова успоредяваме по ЖИТИЯ, а вътре в
# житието вървим последователно — виж build_chains().
_local = threading.local()
_lock = threading.Lock()


def session():
    """requests.Session не е безопасна за споделяне между нишки — по една
    на нишка."""
    if not hasattr(_local, "s"):
        _local.s = requests.Session()
    return _local.s

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.dirname(SCRIPT_DIR)
WORK_DIR = os.path.join(PROJECT_DIR, "work")
# Ключът се търси и до скриптовете, и в корена на Translate_lives. Цялата
# папка е в .gitignore именно заради него — затова НЕ връщай скриптовете в
# git с изключение, ключът ще тръгне с тях.
ENV_FILES = [os.path.join(SCRIPT_DIR, ".env"),
             os.path.join(PROJECT_DIR, ".env")]

API_URL = "https://api.deepseek.com/chat/completions"
MODEL = "deepseek-v4-pro"
TEMPERATURE = 0.3

PH = re.compile(r"⟦(\d+)⟧")
RE_LINE = re.compile(r"^\s*\[(\d+)\]\s?(.*)$")

# ─── Промптът ─────────────────────────────────────────────────────────────
# Уводът и правила 1–3 по-долу са ДОСЛОВНО от 10_translate_deepseek.py.
# Не ги преписвай „по-хубаво" — смисълът им е книгата да звучи еднакво с
# вече преведените жития.
SYSTEM_PROMPT = """Ти си опитен преводач на православна църковна литература от руски на български.

Превеждаш жития на светии от „Жития на светиите“ на св. Димитрий Ростовски.

Правила:
1. Превеждай СМИСЪЛА, не буквално — на естествен, литературен църковен български, какъвто се използва в български жития и синаксари (не разговорен, но и не изкуствено сложен).
2. Имената на светии, места и събори използвай в утвърдените им български православни форми, ако съществуват такива (напр. "Йоан", не "Иоанн"; "Атон", не "Афон", освен когато става дума за конкретен собствен принадлежащ израз). Ако не си сигурен в утвърдена форма, транслитерирай последователно.
3. Не добавяй свои обяснения, бележки или заглавия — само превода.

Формат на входа и изхода:

Входът е номериран списък от откъси, по един на ред:
[1] първи откъс
[2] втори откъс

Отговори със същите номера, в същия ред и със същия брой редове:
[1] превод на първия
[2] превод на втория

Не сливай, не разделяй и не пропускай откъси. Всеки откъс е отделен абзац от книгата и трябва да остане отделен ред в отговора.

В текста се срещат запушалки от вида ⟦1⟧, ⟦2⟧, ⟦3⟧ — те заместват форматиращи означения и НЕ са част от текста. Пренеси ги ВСИЧКИ в превода непроменени: същите числа, същият брой, нищо добавено и нищо изпуснато. Може да се местят заедно с думите, за които се отнасят, ако словоредът на български го изисква.
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
    print("Няма DEEPSEEK_API_KEY. Сложи го в един от:\n  %s\n"
          "(ред DEEPSEEK_API_KEY=...), подай --env-file, или го изнеси в средата.\n"
          "Ключът от предишния превод е в ~/Desktop/azbyka.ru/.env"
          % "\n  ".join(ENV_FILES))
    sys.exit(1)


def build_user_prompt(group, title_hint=None):
    lines = []
    if title_hint:
        # Дългите жития се режат на части; без това подсказване моделът
        # почва част 2 „на сухо" и името на светеца лесно се разиграва в
        # друг вариант. Подсказката е контекст, не текст за превод.
        lines.append("(Контекст, НЕ го превеждай и НЕ го включвай в отговора: "
                     "това е продължение на житието „%s“.)\n" % title_hint)
    for i, u in enumerate(group["units"], 1):
        # Протоколът е „един откъс на ред", а 2.2% от блоковете съдържат нов
        # ред вътре в себе си (в разметката заглавието стои на ред след
        # котвите). Подаден както е, такъв блок заема два реда и моделът
        # съвсем основателно обърква номерата — това беше причината за
        # всички засечки „разминаване в броя редове". Свиването на празните
        # места е безобидно: в HTML те и без това се сливат при изписване, а
        # запушалките не се пипат.
        lines.append("[%d] %s" % (i, " ".join(u["text"].split())))
    return "\n".join(lines)


def parse_response(text, n):
    """Разбива отговора обратно на номерирани редове. Връща списък с дължина
    n или None, ако номерата не съвпадат."""
    out = {}
    cur = None
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


VOID_TAGS = {"br", "img", "hr", "meta", "link", "image", "input"}


def check_nesting(dst, tags):
    """Сдвоени ли са таговете, ако запушалките се върнат по местата си.

    Броят им може да съвпада, а редът да е разменен: моделът веднъж размени
    ⟦9⟧ и ⟦10⟧ (тоест </sup> и </a>) и получи <sup><a>…</sup></a>. Броячът
    не забелязва нищо, но файлът излиза с несдвоени тагове и не се разбира
    като XML. Затова тук се възстановява наистина и се проверява."""
    if not tags:
        return True
    rebuilt = PH.sub(lambda m: tags[int(m.group(1)) - 1]
                     if int(m.group(1)) <= len(tags) else "", dst)
    stack = []
    for m in re.finditer(r"<(/?)(\w+)([^>]*?)(/?)>", rebuilt):
        close, tag, _, selfc = m.groups()
        if tag in VOID_TAGS or selfc:
            continue
        if not close:
            stack.append(tag)
        elif stack and stack[-1] == tag:
            stack.pop()
        else:
            return False
    return not stack


def check_placeholders(src, dst):
    """Същите запушалки, същия брой. Редът може да се различава.

    Освен това в превода НЕ бива да остава ⟦ или ⟧ извън редовните запушалки:
    моделът понякога подхваща стила на скобите и ги ползва като кавички —
    напр. „в името ⟦Христово⟧" на място, където оригиналът няма нито един
    таг. Сравняването само на ⟦число⟧ пропуска точно това и такъв надпис
    стига чак до готовата книга."""
    if sorted(PH.findall(src)) != sorted(PH.findall(dst)):
        return False
    leftover = PH.sub("", dst)
    return "⟦" not in leftover and "⟧" not in leftover


def translate_group(api_key, group, title_hint, retries, usage):
    n = len(group["units"])
    user_prompt = build_user_prompt(group, title_hint)
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

            bad = [i for i, (u, dst) in enumerate(zip(group["units"], parts), 1)
                   if not check_placeholders(u["text"], dst)
                   or not check_nesting(dst, u.get("tags") or [])]
            if bad:
                last = "разместени запушалки в редове %s" % bad[:5]
                print("    опит %d/%d: %s" % (attempt, retries, last))
                continue

            return parts
        except Exception as e:
            last = e
            print("    опит %d/%d неуспешен: %s" % (attempt, retries, e))
            time.sleep(3 * attempt)
    raise RuntimeError("провал след %d опита: %s" % (retries, last))


def build_chains(files):
    """Групира файловете във ВЕРИГИ — по една на житие. Частите на едно
    житие (…_p01, …_p02, …) влизат в обща верига и се превеждат по ред от
    ЕДНА нишка. Всичко останало (кратките жития, бележките, съдържанието) е
    верига от един елемент. Веригите са напълно независими помежду си, тъй
    че се пускат успоредно без никакъв риск.

    Дългите вериги тръгват първи: една верига от 8 части е най-дългият път
    през задачата и ако я оставим за накрая, всички нишки ще я чакат."""
    chains = {}
    for f in files:
        gid = os.path.splitext(os.path.basename(f))[0]
        chains.setdefault(re.sub(r"_p\d+$", "", gid), []).append(f)
    return sorted((sorted(v) for v in chains.values()),
                  key=len, reverse=True)


def process(vol, args, api_key):
    work = os.path.join(WORK_DIR, vol)
    ext_dir = os.path.join(work, "extract")
    out_dir = os.path.join(work, "translated")
    os.makedirs(out_dir, exist_ok=True)

    files = sorted(glob.glob(os.path.join(ext_dir, "*.json")))
    if not files:
        print("Няма извлечени групи в %s — пусни 02_extract.py." % ext_dir)
        sys.exit(1)

    todo = []
    for f in files:
        gid = os.path.splitext(os.path.basename(f))[0]
        if args.group and gid not in args.group:
            continue
        if not args.redo and os.path.exists(os.path.join(out_dir, gid + ".json")):
            continue
        todo.append(f)
    if args.limit:
        todo = todo[:args.limit]

    print("=" * 64)
    print("Том: %s | групи общо: %d | за превод сега: %d"
          % (vol, len(files), len(todo)))
    if not todo:
        print("Няма какво да се превежда.")
        return

    usage_path = os.path.join(work, "usage.json")
    usage = (json.load(open(usage_path, encoding="utf-8"))
             if os.path.exists(usage_path)
             else {"requests": 0, "prompt_tokens": 0, "completion_tokens": 0})

    chains = build_chains(todo)
    print("вериги (жития): %d | нишки: %d" % (len(chains), args.workers))
    counter = {"n": 0}
    total = len(todo)

    def run_chain(chain):
        """Едно житие изцяло, в една нишка, част по част по ред. Така част 2
        винаги вижда вече готовата част 1 и взима оттам името на светеца —
        никога две нишки по едно и също житие."""
        for f in chain:
            g = json.load(open(f, encoding="utf-8"))
            gid = g["id"]

            hint = None
            if g.get("part", 1) > 1:
                first = os.path.join(out_dir,
                                     re.sub(r"_p\d+$", "_p01", gid) + ".json")
                if os.path.exists(first):
                    prev = json.load(open(first, encoding="utf-8"))
                    for u in prev["units"]:
                        if u["kind"] == "h1":
                            hint = PH.sub("", u["translated"]).strip()
                            break

            try:
                parts = translate_group(api_key, g, hint, args.retries, usage)
            except Exception as e:
                # Без това съобщението за провал сочи ПЪРВИЯ файл на веригата
                # (единственото, което извикващият знае), а не групата, която
                # наистина е пропаднала — при дълго житие разликата е голяма.
                raise RuntimeError("%s: %s" % (gid, e)) from None
            for u, t in zip(g["units"], parts):
                u["translated"] = t
            with open(os.path.join(out_dir, gid + ".json"), "w",
                      encoding="utf-8") as fh:
                json.dump(g, fh, ensure_ascii=False, indent=1)
            with _lock:
                counter["n"] += 1
                print("[%d/%d] %s — %d блока, %d символа"
                      % (counter["n"], total, gid, len(g["units"]),
                         sum(len(u["text"]) for u in g["units"])))
                with open(usage_path, "w", encoding="utf-8") as fh:
                    json.dump(usage, fh, ensure_ascii=False, indent=1)

    failed = []
    with ThreadPoolExecutor(max_workers=args.workers) as pool:
        futures = {pool.submit(run_chain, c): c for c in chains}
        for fut in futures:
            try:
                fut.result()
            except Exception as e:
                failed.append(str(e))       # вече носи името на самата група

    print("-" * 64)
    if failed:
        print("ПРОВАЛЕНИ вериги: %d" % len(failed))
        for msg in failed[:10]:
            print("  %s" % msg)
        print("(пусни наново — готовите групи се прескачат)")
    print("заявки: %d | входни токени: %d | изходни токени: %d"
          % (usage["requests"], usage["prompt_tokens"],
             usage["completion_tokens"]))
    print("→ %s" % out_dir)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--vol", required=True)
    ap.add_argument("--limit", type=int)
    ap.add_argument("--group", action="append", default=[])
    ap.add_argument("--redo", action="store_true",
                    help="преведи наново, дори да има готов файл")
    ap.add_argument("--retries", type=int, default=3)
    ap.add_argument("--workers", type=int, default=6,
                    help="успоредни нишки (по една на житие); 1 = както преди")
    ap.add_argument("--env-file")
    ap.add_argument("--show-prompt", action="store_true")
    args = ap.parse_args()

    if args.show_prompt:
        print(SYSTEM_PROMPT)
        return

    api_key, where = load_api_key(args.env_file)
    print("ключът е взет от: %s" % where)

    vols = [os.path.basename(d) for d in glob.glob(os.path.join(WORK_DIR, "*"))
            if os.path.basename(d).startswith(args.vol + "(")]
    if not vols:
        print("Няма подготвен том %s" % args.vol)
        sys.exit(1)
    for v in vols:
        process(v, args, api_key)


if __name__ == "__main__":
    main()
