#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
02_index.py — Парсва ОФЛАЙН кешираните дневни страници (папка days/)
и произвежда:

  output/index.csv            — мостът: дата ↔ слъг ↔ URL ↔ знак ↔ ред.
                                Захранва сваляча на светии (фаза 2) и после
                                match-а към твоята таблица saints.
  output/calendar_days_raw.csv — календарни данни за деня (второстепенно,
                                понеже calendar_days вече е почти финализиран).
  output/saints_slugs.txt     — уникалните слъгове за сваляне във фаза 2.

Не пипа мрежата. Може да се пуска колкото пъти трябва.

CSV конвенция (по уговорка):
  - разделител на колони: |
  - ограда на низове:     '
  - в текста: ' се заменя с " ; всеки | и нов ред се премахват
"""

import csv
import os
import re
import sys
from collections import OrderedDict

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.dirname(SCRIPT_DIR)
DAYS_DIR = os.path.join(PROJECT_DIR, "days")
OUT_DIR = os.path.join(PROJECT_DIR, "output")

# ---------------------------------------------------------------------------
# Знак по типикона: liturgika/N.svg  →  нотацията на Стоил.
# СВЕРЕНО срещу https://azbyka.ru/days/p-znaki-prazdnikov (14.07.2026):
#   1 = велик празник           → (+)
#   2 = бдение                  → +)
#   3 = полиелей                → +
#   4 = славословие (червен)    → (:. [red]
#   5 = шестеричен              → (:.
#   6, 7 = без знак
# ---------------------------------------------------------------------------
SIGN_MAP = {
    "1": "(+)",
    "2": "+)",
    "3": "+",
    "4": "(:. [red]",
    "5": "(:.",
    "6": "",
    "7": "",
}

# ---------------------------------------------------------------------------
# Помощни функции за текст и CSV
# ---------------------------------------------------------------------------

def strip_tags(html: str) -> str:
    """Маха HTML таговете, връща чист текст с нормализирани интервали."""
    text = re.sub(r"<[^>]+>", "", html)
    text = text.replace("&nbsp;", " ")
    # Азбука ползва комбиниращи ударения (ѐ, а́ …) — оставяме ги, безвредни са.
    return re.sub(r"\s+", " ", text).strip()


def clean_field(value: str) -> str:
    """Прилага CSV конвенцията върху едно поле."""
    if value is None:
        return ""
    v = value.replace("'", '"')      # ' → "  (за да не се бърка с оградата)
    v = v.replace("|", "/")          # | би счупил колоните
    v = v.replace("\r", " ").replace("\n", " ")
    return re.sub(r"[ \t]+", " ", v).strip()


def slug_from_href(href: str) -> str | None:
    """Изважда чистия слъг от href (последен сегмент след /days/)."""
    m = re.search(r"/days/([^/?#'\"]+)", href)
    if not m:
        return None
    return m.group(1)


def kind_from_slug(slug: str) -> str:
    """Тип на записа според префикса на слъга."""
    if slug.startswith("svv-"):
        return "svv"        # няколко светии на един линк
    if slug.startswith("sv-"):
        return "sv"         # един светия (вкл. събори — sv-sobor-…)
    if slug.startswith("ikona-"):
        return "ikona"
    if slug.startswith("prazdnik-"):
        return "prazdnik"
    return "other"


# ---------------------------------------------------------------------------
# Парсване на заглавната част (календарни данни за деня)
# ---------------------------------------------------------------------------

def parse_day_header(html: str, date_iso: str) -> dict:
    row = {
        "date": date_iso, "weekday": "", "old_style": "",
        "week_id": "", "sunday_id": "", "tone": "",
        "fast_period": "", "fast_type": "", "note": "",
    }

    m = re.search(r'<div class="days mob-hide">\s*(.*?)\s*</div>', html, re.S)
    if m:
        row["weekday"] = strip_tags(m.group(1))

    m = re.search(r'<div class="oldstyle">.*?<strong>(.*?)</strong>', html, re.S)
    if m:
        row["old_style"] = strip_tags(m.group(1))

    # div.post → "Неделя N-я …" (неделя) или "Седмица N-я …" (седмица)
    m = re.search(r'<div class="post">(.*?)</div>\s*</div>\s*</div>', html, re.S)
    if m:
        post_txt = strip_tags(m.group(1))
        if "Неделя" in post_txt:
            row["sunday_id"] = post_txt
        elif "Седмица" in post_txt:
            row["week_id"] = post_txt

    # day__text → пост + глас
    m = re.search(r'<div class="text day__text">(.*?)<ul', html, re.S)
    text_head = m.group(1) if m else html

    fm = re.search(r'<b class="fasting-message">(.*?)</b>', text_head, re.S)
    if fm:
        row["fast_period"] = strip_tags(fm.group(1))

    plain = strip_tags(text_head)
    if "Поста нет" in plain:
        row["fast_type"] = "Поста нет"

    tm = re.search(r"Глас\s*</a>\s*([0-9]+)", text_head)
    if not tm:
        tm = re.search(r"Глас\s*([0-9]+)", plain)
    if tm:
        row["tone"] = tm.group(1)

    return row


# ---------------------------------------------------------------------------
# Парсване на списъка със светии (индекс)
# ---------------------------------------------------------------------------

SAINT_LINK_RE = re.compile(r"<a\s+[^>]*href=['\"]([^'\"]+)['\"][^>]*>(.*?)</a>", re.S)

def parse_saints_list(html: str, date_iso: str) -> list[dict]:
    rows = []
    order = 0

    # Всички <li class="ideograph-N"> в блоковете paragraph-*
    for li in re.findall(r'<li class="ideograph-(\d+)">(.*?)</li>', html, re.S):
        ideograph, inner = li
        order += 1

        svg = re.search(r"liturgika/(\d+)\.svg", inner)
        sign_svg = svg.group(1) if svg else ""
        # Знакът предпочитаме от SVG-то; ако липсва, падаме на класа.
        sign_code = sign_svg if sign_svg else ideograph
        sign_notation = SIGN_MAP.get(sign_code, "")

        is_feast = 1 if "<strong>" in inner else 0
        has_menaion = 1 if "saint-link-pic" in inner else 0

        # Всички линкове към светии/икони в този <li> (може да са няколко —
        # случаят "двама светии на един булет"). Пропускаме служебните линкове.
        sub = 0
        for href, label in SAINT_LINK_RE.findall(inner):
            if "p-znaki-prazdnikov" in href:
                continue
            slug = slug_from_href(href)
            if not slug:
                continue
            if slug.startswith(("p-", "sedmica", "glas", "yulianskij")):
                continue
            sub += 1
            rows.append({
                "date": date_iso,
                "order": order,
                "sub": sub,
                "slug": slug,
                "kind": kind_from_slug(slug),
                "url": f"https://azbyka.ru/days/{slug}",
                "name_as_shown": strip_tags(label),
                "sign_svg": sign_svg,
                "ideograph": ideograph,
                "sign": sign_notation,
                "is_feast": is_feast,
                "has_menaion_service": has_menaion,
            })
    return rows


# ---------------------------------------------------------------------------
# Запис на CSV по конвенцията
# ---------------------------------------------------------------------------

def write_csv(path: str, fieldnames: list[str], rows: list[dict]):
    with open(path, "w", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(
            f, fieldnames=fieldnames,
            delimiter="|", quotechar="'", quoting=csv.QUOTE_MINIMAL,
            extrasaction="ignore",
        )
        w.writeheader()
        for r in rows:
            w.writerow({k: clean_field(str(r.get(k, ""))) for k in fieldnames})


# ---------------------------------------------------------------------------
# Основна логика
# ---------------------------------------------------------------------------

DATE_FILE_RE = re.compile(r"^(\d{4}-\d{2}-\d{2})\.html$")

def main():
    os.makedirs(OUT_DIR, exist_ok=True)

    files = sorted(
        fn for fn in os.listdir(DAYS_DIR) if DATE_FILE_RE.match(fn)
    )
    if not files:
        print(f"Няма дневни .html файлове в {DAYS_DIR}. Пусни първо 01_fetch_days.py.")
        sys.exit(1)

    calendar_rows = []
    index_rows = []
    unique_slugs = OrderedDict()

    for fn in files:
        date_iso = DATE_FILE_RE.match(fn).group(1)
        html = open(os.path.join(DAYS_DIR, fn), encoding="utf-8").read()

        calendar_rows.append(parse_day_header(html, date_iso))

        saints = parse_saints_list(html, date_iso)
        index_rows.extend(saints)
        for s in saints:
            unique_slugs.setdefault(s["slug"], None)

        print(f"{date_iso}: {len(saints)} записа")

    write_csv(
        os.path.join(OUT_DIR, "calendar_days_raw.csv"),
        ["date", "weekday", "old_style", "week_id", "sunday_id",
         "tone", "fast_period", "fast_type", "note"],
        calendar_rows,
    )
    write_csv(
        os.path.join(OUT_DIR, "index.csv"),
        ["date", "order", "sub", "slug", "kind", "url", "name_as_shown",
         "sign_svg", "ideograph", "sign", "is_feast", "has_menaion_service"],
        index_rows,
    )
    with open(os.path.join(OUT_DIR, "saints_slugs.txt"), "w", encoding="utf-8") as f:
        for slug in unique_slugs:
            f.write(slug + "\n")

    print("\n" + "=" * 50)
    print(f"Дни обработени     : {len(files)}")
    print(f"Записи в индекса   : {len(index_rows)}")
    print(f"Уникални слъгове   : {len(unique_slugs)}")
    print(f"Изход в            : {OUT_DIR}")
    print("=" * 50)
    print("\nПровери знаците (sign) срещу https://azbyka.ru/days/p-znaki-prazdnikov")
    print("и коригирай SIGN_MAP в началото на скрипта, ако се налага.")


if __name__ == "__main__":
    main()
