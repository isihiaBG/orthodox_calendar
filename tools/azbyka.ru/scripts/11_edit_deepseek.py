#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
11_edit_deepseek.py — Стъпка 2: РЕДАКЦИЯ на вече готовия български превод
от ../output/texts_translated.csv (изхода на 10_translate_deepseek.py).

За разлика от 10_translate_deepseek.py (превод RU→BG под ограничен, лек
промпт — нарочно БЕЗ речника, за да остане плавен), тук моделът вижда
ГОТОВ български текст и само го преглежда/поправя — прилага бележките от
translation_glossary.txt (термини, изрази, словоред) и общо подобрява
изказа, БЕЗ да променя смисъла, структурата или HTML таговете.

Идеята: редакция на съществуващ текст е много по-ограничена, по-безопасна
задача за модела от превод под десетки едновременни условия — затова
речникът може да расте свободно тук, без риск да разваля превода.

Вход:
  ../output/translated/*_(trans)_<slug>.csv   (от 10_translate_deepseek.py)
  ../scripts/translation_glossary.txt
  ../.env                                     DEEPSEEK_API_KEY=...

Изход:
  ../output/edited/ГГГГ-ММ-ДД_(edit)_<slug>.csv — ПО ЕДИН файл на светия,
  успоредно на translated/, за лесно сравнение оригинал/превод/редакция
  ред по ред, дори месеци по-късно. Датата в името е КАЛЕНДАРНАТА дата на
  светеца (виж 10_translate_deepseek.py за точното правило), не датата на
  редакцията.

Може да се прекъсва и пуска наново; --slug force-редактира и ЗАМЕСТВА
конкретен файл (за нови итерации по речника).

Употреба:
  python3 11_edit_deepseek.py --limit 3
  python3 11_edit_deepseek.py --slug sv-petr-afonskij
  python3 11_edit_deepseek.py --show-prompt
  python3 11_edit_deepseek.py
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
TRANSLATED_DIR = os.path.join(OUT_DIR, "translated")
EDITED_DIR = os.path.join(OUT_DIR, "edited")
ENV_FILE = os.path.join(PROJECT_DIR, ".env")
GLOSSARY_FILE = os.path.join(SCRIPT_DIR, "translation_glossary.txt")
SAINTS_CSV = os.path.join(PROJECT_DIR, "db", "saints.csv")
NO_DATE = "0000-00-00"

FIELDS = ["slug", "life", "tropar_trans", "tropar2_trans",
          "kondak_trans", "kondak2_trans"]
EDITABLE = FIELDS[1:]

API_URL = "https://api.deepseek.com/chat/completions"
MODEL = "deepseek-v4-pro"

BASE_SYSTEM_PROMPT = """Ти си опитен редактор на български православна църковна литература.

Пред теб е ГОТОВ български превод на откъс от житие на светия, тропар или кондак (за приложение "Православен календар"). Той вече е преведен от руски — твоята задача НЕ Е да превеждаш, а само да РЕДАКТИРАШ вече съществуващия български текст.

Правила:
1. Поправяй само каквото реално се нуждае от поправка: неестествени, буквално преведени от руски конструкции; сгрешени или неутвърдени имена/термини; тромав словоред; думи, които не звучат като литературен църковен български. НЕ пренаписвай изречения, които вече звучат добре — минимална, целенасочена намеса.
2. НЕ променяй смисъла, фактите или структурата на текста. Не съкращавай и не добавяй съдържание.
3. В полето за житие (life) текстът е HTML фрагмент. ЗАДЪЛЖИТЕЛНО запази HTML таговете (<p>, <h3>, <strong>, <em>, <a href="...">...</a> и др.) ТОЧНО както са, включително атрибутите на <a href="saint://...">. Пипай само видимия текст между таговете.
4. Тропарите и кондаците (tropar_trans, tropar2_trans, kondak_trans, kondak2_trans) са обикновен текст — редактирай ги, запазвайки молитвения регистър.
5. Не добавяй свои обяснения, бележки или заглавия — само редактирания текст.
6. Ако вход за дадено поле е празен ред, не го включвай изобщо в отговора.
7. Ако даден пасаж вече е добър и не се нуждае от промяна по бележките по-долу или по общия усет за качество — върни го непроменен.

Отговори ТОЧНО в следния формат, само за полетата, които са дадени във входа (пропусни маркерите на празните полета):

===LIFE===
<редактиран life, ако е даден>
===TROPAR_TRANS===
<редактиран tropar_trans, ако е даден>
===TROPAR2_TRANS===
<редактиран tropar2_trans, ако е даден>
===KONDAK_TRANS===
<редактиран kondak_trans, ако е даден>
===KONDAK2_TRANS===
<редактиран kondak2_trans, ако е даден>
===END===
"""


def load_glossary_notes():
    if not os.path.exists(GLOSSARY_FILE):
        return []
    notes = []
    with open(GLOSSARY_FILE, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith("#"):
                notes.append(line)
    return notes


def build_system_prompt():
    notes = load_glossary_notes()
    if not notes:
        return BASE_SYSTEM_PROMPT
    bullet_list = "\n".join(f"- {n}" for n in notes)
    return (BASE_SYSTEM_PROMPT +
            f"\n\nРечник и изключения (приложи ги, ако се срещнат в текста; "
            f"те имат предимство пред общия усет по-горе при противоречие):\n{bullet_list}\n")


MARKER_TO_FIELD = {
    "LIFE": "life",
    "TROPAR_TRANS": "tropar_trans",
    "TROPAR2_TRANS": "tropar2_trans",
    "KONDAK_TRANS": "kondak_trans",
    "KONDAK2_TRANS": "kondak2_trans",
}


def read_slug_file(path):
    with open(path, encoding="utf-8", newline="") as f:
        rows = list(csv.DictReader(f, delimiter="|", quotechar="'"))
    return rows[0] if rows else None


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


def existing_edit_for_slug(slug):
    matches = glob.glob(os.path.join(EDITED_DIR, f"*_(edit)_{slug}.csv"))
    return matches[0] if matches else None


def write_slug_file(slug, out_row):
    os.makedirs(EDITED_DIR, exist_ok=True)
    d = SAINT_DATES.get(slug, NO_DATE)
    fname = f"{d}_(edit)_{slug}.csv"
    path = os.path.join(EDITED_DIR, fname)
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
    for field in EDITABLE:
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


def edit_row(session, api_key, row, retries=3):
    user_prompt = build_user_prompt(row)
    if not user_prompt:
        return {}

    payload = {
        "model": MODEL,
        "messages": [
            {"role": "system", "content": build_system_prompt()},
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
                    help="редактирай само първите N реда (пилотно)")
    ap.add_argument("--slug", action="append", default=[],
                    help="редактирай само конкретен slug (може повече от веднъж)")
    ap.add_argument("--show-prompt", action="store_true",
                    help="само отпечатай сглобения системен промпт "
                         "(база + речник) и излез, без да редактира")
    args = ap.parse_args()

    if args.show_prompt:
        print(build_system_prompt())
        return

    if not os.path.isdir(TRANSLATED_DIR) or not os.listdir(TRANSLATED_DIR):
        print(f"Няма нищо в {TRANSLATED_DIR}. Пусни 10_translate_deepseek.py първо.")
        sys.exit(1)

    api_key = load_api_key()

    all_rows = []
    for path in sorted(glob.glob(os.path.join(TRANSLATED_DIR, "*_(trans)_*.csv"))):
        r = read_slug_file(path)
        if r:
            all_rows.append(r)
    by_slug = {r["slug"]: r for r in all_rows}

    n_existing = sum(1 for r in all_rows if existing_edit_for_slug(r["slug"]))

    if args.slug:
        missing = [s for s in args.slug if s not in by_slug]
        if missing:
            print(f"ВНИМАНИЕ: тези slug-ове не са в {TRANSLATED_DIR}: {missing}")
        todo = [by_slug[s] for s in args.slug if s in by_slug]
    else:
        todo = [r for r in all_rows if not existing_edit_for_slug(r["slug"])]
        if args.limit is not None:
            todo = todo[:args.limit]

    print(f"Общо преведени: {len(all_rows)} | вече редактирани: {n_existing} | "
          f"за редакция сега: {len(todo)}")

    if not todo:
        print("Няма какво да се редактира.")
        return

    session = requests.Session()
    for i, row in enumerate(todo, 1):
        slug = row["slug"]
        print(f"[{i}/{len(todo)}] {slug} ...")
        edited = edit_row(session, api_key, row)
        out_row = {"slug": slug}
        for field in EDITABLE:
            out_row[field] = edited.get(field, row.get(field, ""))

        old = existing_edit_for_slug(slug)
        if old:
            os.remove(old)
        path = write_slug_file(slug, out_row)
        print(f"  → {path}")

    print(f"\nГотово. Папка: {EDITED_DIR}")


if __name__ == "__main__":
    main()
