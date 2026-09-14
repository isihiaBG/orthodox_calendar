#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
15_translate_hymns.py — превежда с DeepSeek онези песнопения от
output/hymns.csv, които още нямат български текст.

  output/hymns.csv  →  output/hymns_translated/<slug>.json

Превежда се РУСКИЯТ превод (колоната `ru`), не църковнославянският —
точно както при 10_translate_deepseek.py. Ред без `ru` (молитвите и
величанията са такива) НЕ се праща никъде: той си остава само на
църковнославянски, което е и положението на самата azbyka.

Ред с вече наличен `bg` се прескача — 1540-те стари превода са пренесени
от колоните в 14_extract_hymns.py и не се плащат наново.

Всичките песнопения на ЕДИН светия отиват в едно извикване. Така името
му се изписва еднакво във всичките му тропари, а и излиза по-евтино.
Записва се по един файл на светия, тъй че пускането може да се прекъсва
и подновява — светия с готов файл се прескача (освен с --redo).

⚠ Балансът по /user/balance ЗАКЪСНЯВА с няколко минути. Тук общата сметка
е от порядъка на 5 цента, тъй че спирачка по остатък няма — но не копирай
този скрипт за по-голяма задача, без да добавиш такава.

Употреба:
  python3 15_translate_hymns.py --dry-run       # какво би се пратило
  python3 15_translate_hymns.py --limit 2       # пилотно, два светии
  python3 15_translate_hymns.py                 # всичко останало
  python3 15_translate_hymns.py --slug sv-ioann-rylskij --redo
"""

import argparse
import collections
import csv
import json
import os
import re
import sys
import time

import requests

csv.field_size_limit(sys.maxsize)

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.dirname(SCRIPT_DIR)
OUT_DIR = os.path.join(PROJECT_DIR, "output")
IN_CSV = os.path.join(OUT_DIR, "hymns.csv")
TRANSLATED_DIR = os.path.join(OUT_DIR, "hymns_translated")
ENV_FILE = os.path.join(PROJECT_DIR, ".env")

API_URL = "https://api.deepseek.com/chat/completions"
MODEL = "deepseek-v4-pro"

# Промптът нарочно е лек — същото решение както в 10_translate_deepseek.py:
# натъпкването на речника разсейва модела. Разликата тук е, че вход има
# САМО песнопения (без HTML), тъй че правилото за таговете отпада.
SYSTEM_PROMPT = """Ти си опитен преводач на православна църковна литература от руски на български.

Превеждаш тропари, кондаци и други църковни песнопения (в руски превод, взети от azbyka.ru) за приложение "Православен календар".

Правила:
1. Превеждай СМИСЪЛА, не буквално — на естествен, литературен църковен български, какъвто се използва в български богослужебни книги. Запази молитвения регистър: това са текстове за пеене и четене на глас, не проза.
2. Имената на светии, места и събори използвай в утвърдените им български православни форми, ако съществуват такива (напр. "Йоан", не "Иоанн"; "Атон", не "Афон"). Ако не си сигурен в утвърдена форма, транслитерирай последователно.
3. Наклонената черта / в текста бележи мястото на цезурата при пеене. Запази я там, където естествено пада и в българския превод; не добавяй нови и не махай съществуващи без нужда.
4. Не добавяй свои обяснения, бележки или заглавия — само превода.
5. Преведи ТОЧНО толкова текста, колкото са дадени, и всеки под своя номер.

Отговори ТОЧНО в следния формат, по един блок за всеки даден номер:

===H1===
<превод на текста с номер 1>
===H2===
<превод на текста с номер 2>
===END===
"""

FIELDS = ["slug", "ord", "kind", "kind_ru", "seq", "glas", "csl", "ru", "bg"]

# Как се именува видът в подсказката към модела — само за контекст, в
# изхода не влиза.
KIND_NAMES = {
    "tropar": "тропар",
    "kondak": "кондак",
    "molitva": "молитва",
    "velichanie": "величание",
    "other": "песнопение",
}


def load_api_key():
    if os.path.exists(ENV_FILE):
        with open(ENV_FILE, encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if line.startswith("DEEPSEEK_API_KEY="):
                    return line.split("=", 1)[1].strip()
    key = os.environ.get("DEEPSEEK_API_KEY")
    if key:
        return key
    print(f"Няма DEEPSEEK_API_KEY нито в {ENV_FILE}, нито в средата.")
    sys.exit(1)


def load_rows():
    with open(IN_CSV, encoding="utf-8", newline="") as f:
        return list(csv.DictReader(f, delimiter="|", quotechar='"'))


def pending_by_slug(rows):
    """slug → редовете, които имат руски текст, но нямат български."""
    out = collections.OrderedDict()
    for r in rows:
        if r["ru"].strip() and not r["bg"].strip():
            out.setdefault(r["slug"], []).append(r)
    return out


def build_user_prompt(items):
    """Номерата в промпта са ПОСЛЕДОВАТЕЛНИ 1..N, а не `ord` от страницата.

    ⚠ Моделът преномерира. Дадени му [3], [6], [7], [8], той връща
    ===H1===…===H4=== — преводите са верни и в правилния ред, но номерата
    са негови. Затова му се дава каквото очаква, а съответствието с `ord`
    се пази тук, по реда на списъка."""
    parts = []
    for n, r in enumerate(items, start=1):
        name = KIND_NAMES.get(r["kind"], "песнопение")
        head = f"[{n}] {name}"
        if r["glas"]:
            head += f", {r['glas']}"
        parts.append(f"{head}\n{r['ru'].strip()}")
    return "\n\n".join(parts)


def parse_response(text):
    """===H<ord>=== секциите обратно в {ord: превод}."""
    out = {}
    pattern = re.compile(r"===H(\d+)===\s*(.*?)(?=\n?===(?:H\d+|END)===|\Z)", re.S)
    for m in pattern.finditer(text):
        out[m.group(1)] = m.group(2).strip()
    return out


def translate_slug(session, api_key, items, retries=3):
    payload = {
        "model": MODEL,
        "messages": [
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": build_user_prompt(items)},
        ],
        "temperature": 0.3,
        "stream": False,
    }
    headers = {"Authorization": f"Bearer {api_key}",
               "Content-Type": "application/json"}
    last = None
    for attempt in range(1, retries + 1):
        try:
            resp = session.post(API_URL, json=payload, headers=headers,
                                timeout=300)
            if resp.status_code != 200:
                last = f"HTTP {resp.status_code}: {resp.text[:200]}"
            else:
                body = resp.json()
                text = body["choices"][0]["message"]["content"]
                usage = body.get("usage", {})
                return parse_response(text), usage
        except Exception as e:                       # noqa: BLE001
            last = repr(e)
        if attempt < retries:
            time.sleep(3 * attempt)
    print(f"    ✗ провал след {retries} опита: {last}")
    return None, None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--limit", type=int, help="най-много толкова светии")
    ap.add_argument("--slug", help="само този светия")
    ap.add_argument("--redo", action="store_true",
                    help="превежда наново, дори да има готов файл")
    ap.add_argument("--dry-run", action="store_true",
                    help="показва какво би се пратило, без да вика API-то")
    args = ap.parse_args()

    rows = load_rows()
    pending = pending_by_slug(rows)
    if args.slug:
        pending = {k: v for k, v in pending.items() if k == args.slug}

    os.makedirs(TRANSLATED_DIR, exist_ok=True)
    todo = []
    for slug, items in pending.items():
        path = os.path.join(TRANSLATED_DIR, slug + ".json")
        if os.path.exists(path) and not args.redo:
            continue
        todo.append((slug, items, path))
    if args.limit:
        todo = todo[:args.limit]

    total_texts = sum(len(i) for _, i, _ in todo)
    total_chars = sum(len(r["ru"]) for _, i, _ in todo for r in i)
    print(f"светии за превод: {len(todo)}   текстове: {total_texts}   "
          f"знаци: {total_chars}")

    if args.dry_run:
        for slug, items, _ in todo:
            print(f"\n=== {slug} ===")
            print(build_user_prompt(items)[:600])
        return 0

    if not todo:
        print("Няма какво да се превежда.")
        return 0

    api_key = load_api_key()
    session = requests.Session()
    done = failed = 0
    in_tok = out_tok = 0

    for n, (slug, items, path) in enumerate(todo, start=1):
        print(f"[{n}/{len(todo)}] {slug} ({len(items)} текста) … ", end="",
              flush=True)
        got, usage = translate_slug(session, api_key, items)
        if got is None:
            failed += 1
            continue
        # Номерата на модела (1..N) обратно към `ord` на страницата.
        by_ord = {}
        missing = []
        for n, r in enumerate(items, start=1):
            text = got.get(str(n), "").strip()
            if text:
                by_ord[r["ord"]] = text
            else:
                missing.append(r["ord"])
        if missing:
            print(f"⚠ липсват {missing} ", end="")
        if len(got) != len(items):
            print(f"⚠ дадени {len(items)}, върнати {len(got)} ", end="")
        with open(path, "w", encoding="utf-8") as f:
            json.dump({"slug": slug, "bg": by_ord}, f, ensure_ascii=False,
                      indent=1)
        if usage:
            in_tok += usage.get("prompt_tokens", 0)
            out_tok += usage.get("completion_tokens", 0)
        done += 1
        print("готово")

    print(f"\nпреведени: {done}   провалени: {failed}")
    print(f"токени: вход {in_tok}, изход {out_tok}")
    print(f"→ {TRANSLATED_DIR}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
