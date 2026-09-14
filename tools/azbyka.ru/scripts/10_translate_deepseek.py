#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
10_translate_deepseek.py — Превежда житията/тропарите/кондаците от
../output/texts_selected.csv от руски на български чрез DeepSeek API.

За всеки ред (светия) се прави ЕДНО извикване на API-то с всичките му
непразни полета накуп (не поотделно) — по-евтино е и преводът е по-
консистентен (напр. името на светеца се изписва еднакво навсякъде).

НАРОЧНО БЕЗ речника от translation_glossary.txt — пилотен тест показа, че
натъпкването на десетки конкретни бележки в промпта на САМИЯ превод
разсейва модела и влошава качеството другаде, извън засегнатите места.
Речникът/стилът се прилагат в отделна СЛЕДВАЩА стъпка върху вече готовия
превод — виж 11_edit_deepseek.py. Тук промптът остава нарочно лек и стабилен.

Вход:
  ../output/texts_selected.csv   (от 09_export_for_translation.py)
  ../.env                        DEEPSEEK_API_KEY=...

Изход:
  ../output/translated/ГГГГ-ММ-ДД_(trans)_<slug>.csv — ПО ЕДИН файл на
  светия (slug|life|tropar_trans|tropar2_trans|kondak_trans|kondak2_trans).
  Датата в името е КАЛЕНДАРНАТА дата на светеца от ../db/saints.csv (не
  датата на превода!) — ако slug има повече от един ред в календара
  (напр. преставяне + пренасяне на мощи), взима се тази с най-нисък rank
  (по-главното празненство); при равен rank — най-ранната. Ако slug изобщо
  няма ред в календара (само reachable чрез saint:// линк), се ползва
  "0000-00-00". Отделните файлове, подредени по календарна дата, правят
  прегледа/сравнението с оригинала и по-късните корекции много по-лесни,
  отколкото един общ многохиляден CSV — особено месеци по-късно.

Може да се прекъсва и пуска наново — slug, за който вече има файл в
translated/ (независимо от датата в името), се прескача, освен ако не е
изрично поискан с --slug.

Употреба:
  python3 10_translate_deepseek.py --limit 3          # пилотно
  python3 10_translate_deepseek.py --slug sv-petr-afonskij
  python3 10_translate_deepseek.py                     # всичко останало
"""

import argparse
import csv
import glob
import os
import re
import sys
import time

import requests

csv.field_size_limit(sys.maxsize)

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.dirname(SCRIPT_DIR)
OUT_DIR = os.path.join(PROJECT_DIR, "output")
IN_CSV = os.path.join(OUT_DIR, "texts_selected.csv")
TRANSLATED_DIR = os.path.join(OUT_DIR, "translated")
ENV_FILE = os.path.join(PROJECT_DIR, ".env")
SAINTS_CSV = os.path.join(PROJECT_DIR, "db", "saints.csv")
NO_DATE = "0000-00-00"

FIELDS = ["slug", "life", "tropar_trans", "tropar2_trans",
          "kondak_trans", "kondak2_trans"]
TRANSLATABLE = FIELDS[1:]

API_URL = "https://api.deepseek.com/chat/completions"
MODEL = "deepseek-v4-pro"

# Промптът е тук, отделно от логиката — редактвай спокойно при пилотния тест.
SYSTEM_PROMPT = """Ти си опитен преводач на православна църковна литература от руски на български.

Превеждаш откъси от жития на светии, тропари и кондаци (в руски превод, взети от azbyka.ru) за приложение "Православен календар".

Правила:
1. Превеждай СМИСЪЛА, не буквално — на естествен, литературен църковен български, какъвто се използва в български жития и синаксари (не разговорен, но и не изкуствено сложен).
2. Имената на светии, места и събори използвай в утвърдените им български православни форми, ако съществуват такива (напр. "Йоан", не "Иоанн"; "Атон", не "Афон", освен когато става дума за конкретен собствен принадлежащ израз). Ако не си сигурен в утвърдена форма, транслитерирай последователно.
3. В полето за житие (life) текстът е HTML фрагмент. ЗАДЪЛЖИТЕЛНО запази HTML таговете (<p>, <h3>, <strong>, <em>, <a href="...">...</a> и др.) ТОЧНО както са, включително атрибутите на <a href="saint://...">. Превеждай САМО видимия текст между таговете — таговете, техните атрибути и структурата на документа не се пипат.
4. Тропарите и кондаците (tropar_trans, tropar2_trans, kondak_trans, kondak2_trans) са обикновен текст (без HTML) — преведи ги на съвременен литературен български, запазвайки молитвения регистър.
5. Не добавяй свои обяснения, бележки или заглавия — само превода.
6. Ако вход за дадено поле е празен ред, не го включвай изобщо в отговора.

Отговори ТОЧНО в следния формат, само за полетата, които са дадени във входа (пропусни маркерите на празните полета):

===LIFE===
<превод на life, ако е даден>
===TROPAR_TRANS===
<превод на tropar_trans, ако е даден>
===TROPAR2_TRANS===
<превод на tropar2_trans, ако е даден>
===KONDAK_TRANS===
<превод на kondak_trans, ако е даден>
===KONDAK2_TRANS===
<превод на kondak2_trans, ако е даден>
===END===
"""


MARKER_TO_FIELD = {
    "LIFE": "life",
    "TROPAR_TRANS": "tropar_trans",
    "TROPAR2_TRANS": "tropar2_trans",
    "KONDAK_TRANS": "kondak_trans",
    "KONDAK2_TRANS": "kondak2_trans",
}


def load_saint_dates():
    """slug → 'главната' календарна дата: най-нисък rank; при равенство —
    най-ранната дата. Slug без ред в календара просто липсва тук."""
    best = {}
    with open(SAINTS_CSV, encoding="utf-8") as f:
        for row in csv.DictReader(f, delimiter="|"):
            slug = (row.get("slug") or "").strip()
            d = (row.get("date") or "").strip()
            if not slug or not d:
                continue
            try:
                rank = int(row.get("rank") or 999)
            except ValueError:
                rank = 999
            key = (rank, d)
            if slug not in best or key < best[slug]:
                best[slug] = key
    return {slug: d for slug, (rank, d) in best.items()}


SAINT_DATES = load_saint_dates()


def existing_file_for_slug(slug):
    """Намира вече записан файл за slug в translated/, независимо от датата
    в името му. Връща пътя или None."""
    matches = glob.glob(os.path.join(TRANSLATED_DIR, f"*_(trans)_{slug}.csv"))
    return matches[0] if matches else None


def write_slug_file(slug, out_row):
    os.makedirs(TRANSLATED_DIR, exist_ok=True)
    d = SAINT_DATES.get(slug, NO_DATE)
    fname = f"{d}_(trans)_{slug}.csv"
    path = os.path.join(TRANSLATED_DIR, fname)
    with open(path, "w", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(f, fieldnames=FIELDS, delimiter="|",
                           quotechar="'", quoting=csv.QUOTE_MINIMAL)
        w.writeheader()
        w.writerow(out_row)
    return path


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


def build_user_prompt(row):
    parts = []
    for field in TRANSLATABLE:
        val = (row.get(field) or "").strip()
        if val:
            parts.append(f"[{field.upper()}]\n{val}")
    return "\n\n".join(parts)


def parse_response(text):
    """Разбива отговора по ===MARKER=== секции обратно в полета."""
    out = {}
    pattern = re.compile(r"===([A-Z0-9_]+)===\s*(.*?)(?=\n?===[A-Z0-9_]+===|\Z)",
                         re.S)
    for m in pattern.finditer(text):
        marker, body = m.group(1), m.group(2).strip()
        if marker == "END":
            continue
        field = MARKER_TO_FIELD.get(marker)
        if field:
            out[field] = body
    return out


def translate_row(session, api_key, row, retries=3):
    user_prompt = build_user_prompt(row)
    if not user_prompt:
        return {}

    payload = {
        "model": MODEL,
        "messages": [
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": user_prompt},
        ],
        "temperature": 0.3,
        "stream": False,
    }
    headers = {"Authorization": f"Bearer {api_key}",
               "Content-Type": "application/json"}

    last_err = None
    for attempt in range(1, retries + 1):
        try:
            resp = session.post(API_URL, json=payload, headers=headers, timeout=120)
            if resp.status_code == 429:
                wait = 5 * attempt
                print(f"  429 rate limit, чакам {wait}s...")
                time.sleep(wait)
                continue
            resp.raise_for_status()
            data = resp.json()
            content = data["choices"][0]["message"]["content"]
            return parse_response(content)
        except Exception as e:
            last_err = e
            print(f"  опит {attempt}/{retries} неуспешен: {e}")
            time.sleep(3 * attempt)
    raise RuntimeError(f"Провал след {retries} опита: {last_err}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--limit", type=int, default=None,
                    help="преведи само първите N реда (пилотно)")
    ap.add_argument("--slug", action="append", default=[],
                    help="преведи само конкретен slug (може повече от веднъж)")
    ap.add_argument("--show-prompt", action="store_true",
                    help="само отпечатай системния промпт и излез, без да превежда")
    args = ap.parse_args()

    if args.show_prompt:
        print(SYSTEM_PROMPT)
        return

    if not os.path.exists(IN_CSV):
        print(f"Липсва {IN_CSV}. Пусни 09_export_for_translation.py първо.")
        sys.exit(1)

    api_key = load_api_key()

    with open(IN_CSV, encoding="utf-8", newline="") as f:
        all_rows = list(csv.DictReader(f, delimiter="|", quotechar="'"))
    by_slug = {r["slug"]: r for r in all_rows}

    n_existing = sum(1 for r in all_rows if existing_file_for_slug(r["slug"]))

    if args.slug:
        # Изрично поискани slug-ове — превеждат се ВИНАГИ, дори вече да ги
        # има (корекция) — старият им файл (стара дата) се трие, за да няма
        # два файла за един и същ slug едновременно в translated/.
        missing = [s for s in args.slug if s not in by_slug]
        if missing:
            print(f"ВНИМАНИЕ: тези slug-ове не са в {IN_CSV}: {missing}")
        todo = [by_slug[s] for s in args.slug if s in by_slug]
    else:
        todo = [r for r in all_rows if not existing_file_for_slug(r["slug"])]
        if args.limit is not None:
            todo = todo[:args.limit]

    print(f"Общо в {IN_CSV}: {len(all_rows)} | вече преведени: {n_existing} | "
          f"за превод сега: {len(todo)}")

    if not todo:
        print("Няма какво да се превежда.")
        return

    session = requests.Session()
    for i, row in enumerate(todo, 1):
        slug = row["slug"]
        print(f"[{i}/{len(todo)}] {slug} ...")
        translated = translate_row(session, api_key, row)
        out_row = {"slug": slug}
        for field in TRANSLATABLE:
            out_row[field] = translated.get(field, "")

        old = existing_file_for_slug(slug)
        if old:
            os.remove(old)
        path = write_slug_file(slug, out_row)
        print(f"  → {path}")

    print(f"\nГотово. Папка: {TRANSLATED_DIR}")


if __name__ == "__main__":
    main()
