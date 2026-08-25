#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
03_parse.py — Разглобяване на свалените глави. НИТО ЕДНА мрежова заявка.

Чете cache/<език>/<Книга>.<глава>.html и произвежда
output/json/<език>/<Книга>.json — стих по стих.

⚠ ТУК НИЩО НЕ СЕ ИЗХВЪРЛЯ. Пази се и суровият HTML на всеки стих (без
служебната отметка на сайта), и изчистеният текст. Решението как да
изглежда стихът в приложението е на 04_build_db.py — иначе първата промяна
в оформлението иска ново теглене на 14 000 глави.

Устройството на страницата е извънредно удобно: всеки стих е самостоятелен
<div> със собствени атрибути —

    data-lang="bg" data-chapter="1" data-line="1" data-verse="Gen.1:1"

`data-verse` е готов УНИВЕРСАЛЕН КЛЮЧ, еднакъв във всички преводи. По него
се съединяват колоните в базата; не се налага никакво сверяване по номера.

⚠ `data-line` НЕ Е номерът на стиха. То е поредното място в главата, докато
номерът идва от `data-verse` — и той започва от 0 там, където главата има
надписание (Пс. 117:0). Затова редът на показване се пази отделно от номера.

Отчетът накрая изброява ВСИЧКИ срещнати тагове вътре в стиховете. Появи ли
се непознат, се вижда веднага, вместо да бъде мълчаливо изгладен.

Употреба:
    python3 03_parse.py                      # всичко в кеша
    python3 03_parse.py --langs bg,utfcs
    python3 03_parse.py --langs bg --report  # само отчет, без запис
"""

import argparse
import collections
import html
import json
import os
import re
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.dirname(SCRIPT_DIR)
INPUT_DIR = os.path.join(PROJECT_DIR, "input")
CACHE_DIR = os.path.join(PROJECT_DIR, "cache")
JSON_DIR = os.path.join(PROJECT_DIR, "output", "json")

# Един стих: <div ...атрибути... class="verse ...">СЪДЪРЖАНИЕ</div>
# Хваща се по атрибутите, а не по класа — те са машинно поставени и не се
# менят между преводите, докато списъкът с класове носи и оформителски неща.
RE_VERSE = re.compile(
    r'<div\s+[^>]*?data-lang="(?P<lang>[^"]*)"'
    r'[^>]*?data-chapter="(?P<chapter>[^"]*)"'
    r'[^>]*?data-line="(?P<line>[^"]*)"'
    r'[^>]*?data-verse="(?P<verse>[^"]*)"'
    r'[^>]*?>(?P<body>.*?)</div>',
    re.S,
)

# Служебната отметка на сайта („прочетено") — не е част от текста.
RE_CHECKBOX = re.compile(r'<span class="icon-check checkbox"></span>')

# Ключът от data-verse: „Gen.1:1", „Ps.117:0", „Phlm.1:25".
RE_VERSE_KEY = re.compile(r"^(?P<book>[A-Za-z0-9]+)\.(?P<chapter>\d+):(?P<verse>.+)$")

RE_TAG = re.compile(r"<(/?)([a-zA-Z0-9]+)([^>]*)>")

# НАДПИСАНИЕТО на псалом („Началнику на хора. Псалом Давидов.") — то не е
# стих от Писанието, а заглавие, и трябва да се отличава при четене.
#
# ⚠ Разпознава се по това, че ЦЕЛИЯТ стих е получер `cyn` спан. Само `cyn` НЕ
# СТИГА: със същия клас се бележат и отделни думи, добавени от преводачите
# насред стиха („послужил мне в узах <span class=cyn>за</span> благовествование").
# Мерено срещу целия кеш: при руския 3466 стиха носят `cyn`, но само 151 са
# изцяло получерни — и всичките 151 са в Псалтира. При цсл — 136, пак само
# там. Тоест правилото не лови нищо чуждо.
RE_WHOLE_BOLD_CYN = re.compile(
    r'^<span[^>]*class="[^"]*\bcyn\b[^"]*"[^>]*>\s*<(b|strong)>.*</\1>\s*'
    r'</span>$',
    re.S)

# Началото на <span class="…"> с ТЪРСЕНИЯ клас. Затварящият таг не се лови с
# регекс — вижда се защо в docstring-а на _cut_spans().
def _open_span_re(cls: str) -> re.Pattern:
    return re.compile(r'<span\b[^>]*class="[^"]*\b' + re.escape(cls) + r'\b[^"]*"[^>]*>')


RE_ANY_SPAN_OPEN = re.compile(r"<span\b[^>]*>", re.I)
RE_ANY_SPAN_CLOSE = re.compile(r"</span>", re.I)


def _cut_spans(fragment: str, cls: str):
    """Изважда всички <span class="cls">…</span> и връща (остатък, [съдържания]).

    ⚠ Затварящият таг СЕ БРОИ, не се търси с регекс. Сноските на сайта са
    ВЛОЖЕНИ една в друга —

        <span class="snos">//*Приятная. <span class="snos">/**Горькая.</span></span>

    — тъй че първото `</span>` принадлежи на вътрешната. Ленив регекс би
    отрязал по него и би оставил едно самотно `</span>` да виси в текста на
    стиха; лаком би глътнал всичко до края на реда. Затова се брои дълбочина.

    Взимат се само ВЪНШНИТЕ спанове; вложените идват със съдържанието им.
    """
    out = []
    rest = []
    pos = 0
    opener = _open_span_re(cls)

    while True:
        m = opener.search(fragment, pos)
        if not m:
            rest.append(fragment[pos:])
            break

        rest.append(fragment[pos:m.start()])
        depth = 1
        i = m.end()
        start = i

        while depth and i < len(fragment):
            nxt_open = RE_ANY_SPAN_OPEN.search(fragment, i)
            nxt_close = RE_ANY_SPAN_CLOSE.search(fragment, i)
            if not nxt_close:
                # Нечифтен таг в изворната страница — прибираме остатъка и
                # спираме, вместо да въртим безкрайно.
                i = len(fragment)
                break
            if nxt_open and nxt_open.start() < nxt_close.start():
                depth += 1
                i = nxt_open.end()
            else:
                depth -= 1
                i = nxt_close.end()
                if depth == 0:
                    out.append(fragment[start:nxt_close.start()])

        pos = i

    return "".join(rest), out


def load_books():
    path = os.path.join(INPUT_DIR, "books.csv")
    if not os.path.exists(path):
        sys.exit(f"Липсва {path}. Пусни първо 01_fetch_map.py.")
    import csv
    with open(path, encoding="utf-8") as fh:
        return list(csv.DictReader(fh))


def plain_text(fragment: str) -> str:
    """Гол текст: без тагове, с разкодирани същности, със свити интервали."""
    text = re.sub(r"<[^>]+>", "", fragment)
    text = html.unescape(text)
    # Неразделният интервал на сайта се среща често и в базата е излишен —
    # той е оформителски, а не част от Писанието.
    text = text.replace(" ", " ")
    return re.sub(r"\s+", " ", text).strip()


# Сноската носи водещи наклонени черти и звездички: „//*Приятная." Звездичките
# са ѝ знакът (същият, който стои и в самия стих след думата), чертите са
# разделител между няколко сноски, събрани в един блок.
RE_NOTE_SPLIT = re.compile(r"/+(\*+|\d+)")


def extract_verse(body: str):
    """Разглобява един стих на текст, зачала и сноски.

    ⚠ ТРИ вида съдържание в стиха НЕ СА текст на Писанието и трябва да излязат
    оттам, ПРЕДИ да се маха какъвто и да било таг:

    1. `<span class="info">` — ПОЯСНЕНИЕ ЗА ЕКРАНА, показвано при посочване.
       Стои ВЪТРЕ в <abbr>, точно преди истинската дума:

           <abbr><span class="info">В тексте Ветхого Завета в квадратные
           скобки заключены слова…</span>[нарядные]</abbr>

       Сляпо `re.sub(r'<[^>]+>', '')` залепва цялото това изречение насред
       стиха. Маха се ИЗЦЯЛО. Квадратните скоби около думата ОСТАВАТ — те са
       конвенция на Синодалния превод (дума, взета от Септуагинтата), не
       оформление.

    2. `<span class="zachala">` — богослужебното зачало („Зач. 302В."), със
       квадратни скоби ОКОЛО спана, не вътре в него. Излиза в свое поле: по
       него после се строят дневните четива, а в текста би било шум.

    3. `<span class="snos">` — самата сноска, долепена накрая на стиха.
       Излиза в свое поле; знакът ѝ (звездичка) остава в текста при думата,
       отбелязана със `snosCit`.

    Останалото се ПАЗИ: `cyn` (думи, добавени от преводачите за яснота),
    `cuSnos` (църковнославянското пояснение в къдрави скоби), `snosCit`.
    """
    rest, zachala = _cut_spans(body, "zachala")
    # Скобите около зачалото остават сираци, щом спанът излезе.
    rest = re.sub(r"\[\s*\]", "", rest)

    rest, notes_raw = _cut_spans(rest, "snos")

    # 3б. Подсказките НЕ СЕ ХВЪРЛЯТ, а излизат в свое поле. Те не са текст на
    #     Писанието и в стиха нямат работа — но са истинско пояснение (какво
    #     значат квадратните скоби в Синодалния превод) и утре може да потрябват
    #     като бележка под линия. Изхвърленото не се връща без ново теглене.
    rest, tooltips = _cut_spans(rest, "info")

    # 4. `<span class="verse-chapter-title">` — ПОДЗАГЛАВИЕ НА ДЯЛА, залепено
    #    вътре в първия стих на главата и отделено от него само с <br/>
    #    (среща се в сръбския). Остане ли, стих 1 тръгва със заглавие вместо
    #    със Писанието. Излиза в свое поле, а осиротелият <br/> след него —
    #    вън.
    rest, titles = _cut_spans(rest, "verse-chapter-title")
    rest = re.sub(r"^\s*(<br\s*/?>\s*)+", "", rest)
    rest = re.sub(r"(<br\s*/?>\s*)+$", "", rest)

    notes = []
    for blob in notes_raw:
        flat = plain_text(blob)
        parts = RE_NOTE_SPLIT.split(flat)
        # split() връща [преди, знак, текст, знак, текст, …]
        head = parts[0].strip()
        if head:
            notes.append({"mark": "", "text": head})
        for mark, text in zip(parts[1::2], parts[2::2]):
            text = text.strip()
            if text:
                notes.append({"mark": mark, "text": text})

    # Каквото остане с `title=` е `cyn` — думата, добавена от преводачите,
    # заедно с обяснението защо. И двете се пазят: думата остава в текста,
    # обяснението застава до нея като бележка.
    annotations = [{"kind": "info", "text": plain_text(t)} for t in tooltips
                   if plain_text(t)]
    for tm in re.finditer(r'<([a-zA-Z]+)\b([^>]*\btitle="([^"]+)"[^>]*)>(.*?)</\1>',
                          rest, re.S):
        word = plain_text(tm.group(4))
        note = html.unescape(tm.group(3)).strip()
        if note and word:
            annotations.append({"kind": "title", "word": word, "text": note})

    # Връзките навън (към зачалата, към пояснителни страници). Пазят се и от
    # ИЗВАДЕНИТЕ парчета, не само от текста — зачалото например носи своята
    # връзка вътре в себе си и тя се губи заедно с него.
    links = []
    for chunk in [rest] + zachala + titles:
        for lm in re.finditer(r'<a\b[^>]*href="([^"]+)"[^>]*>(.*?)</a>', chunk, re.S):
            links.append({
                "href": html.unescape(lm.group(1)),
                "text": plain_text(lm.group(2)),
            })

    return {
        "heading": bool(RE_WHOLE_BOLD_CYN.match(rest.strip())),
        "html": rest.strip(),
        "text": plain_text(rest),
        "zachala": [plain_text(z) for z in zachala],
        "notes": notes,
        "titles": [plain_text(t) for t in titles if plain_text(t)],
        "annotations": annotations,
        "links": links,
    }


def parse_chapter(path: str, tag_counter, anomalies):
    """Стиховете на една глава, по реда на четене."""
    with open(path, encoding="utf-8") as fh:
        page = fh.read()

    verses = []
    for m in RE_VERSE.finditer(page):
        key = m.group("verse")
        km = RE_VERSE_KEY.match(key)
        if not km:
            # Страницата носи и един JS шаблон със същия вид атрибут; той не
            # е стих и се разпознава по това, че ключът не се разчита.
            continue

        body = RE_CHECKBOX.sub("", m.group("body")).strip()

        for tm in RE_TAG.finditer(body):
            tag = tm.group(2).lower()
            cls = re.search(r'class="([^"]*)"', tm.group(3) or "")
            tag_counter[f"{tag}" + (f".{cls.group(1).split()[0]}" if cls else "")] += 1

        # ⚠ Номерът се РАЗКОДИРА. Източникът бележи вариантни стихове с
        # апостроф, който в атрибута стои като `&#039;` — „2Chron.36:23'".
        # Без това в базата влиза буквалното `23&#039;` и същият стих не може
        # да се намери по ключа си.
        num_raw = html.unescape(km.group("verse"))
        if not num_raw.isdigit():
            anomalies.append((os.path.basename(path), key))

        parts = extract_verse(body)
        verse = {
            "key": key,
            "chapter": int(km.group("chapter")),
            "verse": num_raw,
            "line": int(m.group("line")) if m.group("line").isdigit() else 0,
            "html": parts["html"],
            "text": parts["text"],
        }

        # ⚠ СУРОВИЯТ HTML СЕ ПАЗИ НЕПОКЪТНАТ, когато се различава от
        # изчистения. Разглобяването може да извади само онова, за което
        # знае — а описът (inventory.py) редовно изкарва по нещо ново.
        # Пази ли се суровото и тук, следващата итерация тръгва от JSON-а,
        # без да рови из 500-те MB кеш; изтрие ли се кешът, това остава
        # единственият пълен запис.
        if body.strip() != parts["html"]:
            verse["raw"] = body.strip()

        # Празните полета не се записват — иначе JSON-ът надува двойно за
        # едно и също, а зачала и сноски има само у част от преводите.
        for field in ("zachala", "notes", "titles", "annotations", "links"):
            if parts[field]:
                verse[field] = parts[field]
        # Надписанието е булево, не списък — затова е извън цикъла.
        if parts["heading"]:
            verse["heading"] = True
        verses.append(verse)

    return verses


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--langs", default="", help="само тези езици (през запетая)")
    ap.add_argument("--report", action="store_true",
                    help="само отчет, без да пише JSON")
    args = ap.parse_args()

    books = load_books()
    book_order = {b["code"]: int(b["order"]) for b in books}

    if not os.path.isdir(CACHE_DIR):
        sys.exit("Няма cache/. Пусни първо 02_fetch_chapters.py.")

    langs = [c.strip() for c in args.langs.split(",") if c.strip()]
    if not langs:
        langs = sorted(d for d in os.listdir(CACHE_DIR)
                       if os.path.isdir(os.path.join(CACHE_DIR, d))
                       and not d.startswith("_"))

    grand_total = 0
    for lang in langs:
        lang_dir = os.path.join(CACHE_DIR, lang)
        if not os.path.isdir(lang_dir):
            print(f"⚠ няма cache/{lang} — прескачам")
            continue

        tag_counter = collections.Counter()
        anomalies = []
        by_book = collections.defaultdict(dict)
        empty = []

        files = sorted(f for f in os.listdir(lang_dir) if f.endswith(".html"))
        for fname in files:
            # „Gen.1.html" → book='Gen', chapter=1. Кодовете на книгите нямат
            # точка в себе си („3Jn", „1Pet", „pJer"), тъй че деленето е
            # еднозначно.
            book = fname.split(".")[0]
            chapter = int(fname.split(".")[1])

            verses = parse_chapter(os.path.join(lang_dir, fname),
                                   tag_counter, anomalies)
            if not verses:
                empty.append(f"{book}.{chapter}")
                continue
            by_book[book][chapter] = verses

        all_verses = [v for ch in by_book.values() for vs in ch.values() for v in vs]
        total = len(all_verses)
        grand_total += total
        extracted = {f: sum(len(v.get(f, [])) for v in all_verses)
                     for f in ("zachala", "notes", "titles",
                               "annotations", "links")}
        n_raw = sum(1 for v in all_verses if "raw" in v)
        n_head = sum(1 for v in all_verses if v.get("heading"))

        print(f"── {lang}")
        print(f"   глави: {len(files)}  книги: {len(by_book)}  стихове: {total}")
        if any(extracted.values()):
            labels = {"zachala": "зачала", "notes": "сноски",
                      "titles": "подзаглавия", "annotations": "пояснения",
                      "links": "връзки"}
            detail = ", ".join(f"{labels[f]} {n}"
                               for f, n in extracted.items() if n)
            print(f"   извадени отделно: {detail}")
        if n_raw:
            print(f"   със запазен суров HTML: {n_raw}")
        if n_head:
            print(f"   разпознати надписания: {n_head}")
        if empty:
            print(f"   без нито един стих: {len(empty)}"
                  + (f"  ({', '.join(empty[:6])}"
                     + (" …" if len(empty) > 6 else "") + ")" if empty else ""))
        if anomalies:
            uniq = sorted({a[1] for a in anomalies})
            print(f"   ⚠ нецифрови номера на стихове: {len(anomalies)}"
                  f"  напр. {', '.join(uniq[:5])}")
        top = ", ".join(f"{t}×{n}" for t, n in tag_counter.most_common(12))
        print(f"   тагове в стиховете: {top or '(няма)'}")

        if args.report:
            continue

        out_dir = os.path.join(JSON_DIR, lang)
        os.makedirs(out_dir, exist_ok=True)
        for book, chapters in by_book.items():
            payload = {
                "lang": lang,
                "book": book,
                "order": book_order.get(book, 999),
                "chapters": {
                    str(ch): chapters[ch] for ch in sorted(chapters)
                },
            }
            with open(os.path.join(out_dir, f"{book}.json"), "w",
                      encoding="utf-8") as fh:
                json.dump(payload, fh, ensure_ascii=False, indent=1)

    print()
    print(f"общо стихове: {grand_total}")
    if not args.report:
        print(f"записано в {os.path.relpath(JSON_DIR, PROJECT_DIR)}/")


if __name__ == "__main__":
    main()
