#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
04_build_db.py — Сглобява assets/db/bible.db от output/json/. Без мрежа.

⚠ УСТРОЙСТВЕНО РЕШЕНИЕ: ЕЗИЦИТЕ СА РЕДОВЕ, НЕ КОЛОНИ.

Първоначалната мисъл беше по една колона на превод (`text_bg`, `text_cs`,
`text_ru`, `text_gr1`…) — един ред на стих, всички езици до него. Отказах се,
и то по опит на СЪЩИЯ проект: точно така бяха устроени тропарите и кондаците
(осем колони `tropar`, `tropar2`, `kondak`…) и се наложи да бъдат преправени
на таблица `hymns` с редове, защото реалността не се побра в колоните — 93
тропара и 57 кондака се губеха мълчаливо, а молитвите и величанията изобщо
не се вадеха. Виж бележката за `hymns` в CLAUDE.md.

Тук същият натиск личи още отсега:
  • преводите вече са 12 и списъкът НЕ е затворен (сайтът дава 62);
  • покритието е РАЗЛИЧНО за всеки — Септуагинтата няма Нов завет,
    еврейската Библия няма второканоничните книги, древният грузински е
    само на части. При колони това са хиляди NULL-ове;
  • номерацията на стиховете се разминава между преводите, тъй че „един ред
    = един стих на всички езици" е предположение, което не издържа.

Отгоре на всичко четецът показва по ЕДИН-ДВА езика наведнъж (паралелният
превод се сменя с плъзгане), а при колони всяка заявка мъкне и дванайсетте.

За удобство пак има изглед `verses_wide`, който подрежда исканите колони —
но той е УДОБСТВО върху редовете, не устройството на базата.

Употреба:
    python3 04_build_db.py
    python3 04_build_db.py --langs bg,utfcs        # частично, за проба
    python3 04_build_db.py --out /път/до/bible.db
"""

import argparse
import csv
import json
from html import unescape
import os
import sqlite3
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.dirname(SCRIPT_DIR)
INPUT_DIR = os.path.join(PROJECT_DIR, "input")
JSON_DIR = os.path.join(PROJECT_DIR, "output", "json")
REPO_DIR = os.path.dirname(os.path.dirname(PROJECT_DIR))
DEFAULT_OUT = os.path.join(REPO_DIR, "assets", "db", "bible.db")

SCHEMA = """
PRAGMA journal_mode = DELETE;

DROP VIEW  IF EXISTS verses_wide;
DROP TABLE IF EXISTS verses;
DROP TABLE IF EXISTS zachala;
DROP TABLE IF EXISTS notes;
DROP TABLE IF EXISTS titles;
DROP TABLE IF EXISTS annotations;
DROP TABLE IF EXISTS links;
DROP TABLE IF EXISTS headings;
DROP TABLE IF EXISTS books;
DROP TABLE IF EXISTS languages;

-- Книгите на Свещеното Писание, по реда на самия източник (първо Нов завет).
-- ⚠ ТРИ форми на името, всяка за свое място:
--   bg_title  „Евангелие от Матей"  — заглавия, търсене
--   bg_short  „Матей"                — списъкът в съдържанието
--   bg_abbr   „Мат."                 — хедърът на четеца и препратките
-- Списъкът се чете на един поглед: там „Евангелие от" се повтаря четири
-- пъти подред и не различава нищо.
CREATE TABLE books (
    code       TEXT PRIMARY KEY,   -- „Gen", „Ps", „Mt" — ключът на azbyka.ru
    ord        INTEGER NOT NULL,   -- ред на показване
    testament  TEXT NOT NULL,      -- „OT" / „NT"
    chapters   INTEGER NOT NULL,   -- брой глави (по пълния канон)
    bg_title   TEXT NOT NULL,
    bg_short   TEXT NOT NULL,
    bg_abbr    TEXT NOT NULL,
    ru_title   TEXT
);

-- Преводите. `scope` казва какво изобщо покрива преводът, `direction` — как
-- се пише (ивритът е отдясно наляво), `font` — кой шрифт го иска.
CREATE TABLE languages (
    code       TEXT PRIMARY KEY,
    ord        INTEGER NOT NULL,
    bg_title   TEXT NOT NULL,
    bg_short   TEXT NOT NULL,
    title      TEXT,               -- както го нарича самият източник
    scope      TEXT NOT NULL,      -- „all" / „ot" / „nt"
    -- Двубуквено съкращение („бг", „цс", „ру") за полето в лентата, където
    -- пълното име би изяло половината ширина.
    bg_abbr    TEXT NOT NULL DEFAULT '',
    direction  TEXT NOT NULL DEFAULT 'ltr',
    -- Добавка към МЕЖДУРЕДИЕТО само за този превод.
    -- ⚠ Пак свойство на шрифта: църковнославянският носи свой въздух в
    -- глифовете и при общото 1.35 текстът се разрежда прекомерно. За кратък
    -- надпис това е хубаво, за цяло Писание — не.
    line_delta REAL NOT NULL DEFAULT 0,
    -- Добавка към размера на шрифта САМО за този превод.
    -- ⚠ Свойство на ШРИФТА, не на езика: църковнославянските глифове са с
    -- по-ниска редова буква и при еднакъв кегел изглеждат осезаемо по-дребни
    -- от системния до тях. Стои тук, защото шрифтът се избира по превод.
    size_delta REAL NOT NULL DEFAULT 0,
    font       TEXT,
    -- Първата буква на стиха да се изписва в червено.
    -- ⚠ Не е украса на приложението, а РУБРИКАЦИЯ — установеният начин за
    -- открояване на началото в славянските богослужебни книги. Затова стои
    -- при превода: важи за църковнославянския, не за текста изобщо.
    rubricate  INTEGER NOT NULL DEFAULT 0,
    note       TEXT
);

-- Сърцевината. Един ред = един стих в един превод.
--
-- ⚠ `verse` е ТЕКСТ, не число: започва от 0 там, където главата има
-- надписание (Пс. 117:0), а някои преводи носят и слети номера. `ord` пази
-- реда на показване, който НЕ бива да се извежда от номера.
CREATE TABLE verses (
    book       TEXT NOT NULL REFERENCES books(code),
    chapter    INTEGER NOT NULL,
    verse      TEXT NOT NULL,
    lang       TEXT NOT NULL REFERENCES languages(code),
    ord        INTEGER NOT NULL,
    text       TEXT NOT NULL,      -- гол текст, за търсене и за четене
    html       TEXT,               -- с оцелялата маркировка, ако се различава
    raw        TEXT,               -- суровото от източника; само при --with-raw
    PRIMARY KEY (book, chapter, verse, lang)
) WITHOUT ROWID;

-- Богослужебните зачала („Зач. 302В.") — по тях после се строят четивата.
CREATE TABLE zachala (
    book     TEXT NOT NULL,
    chapter  INTEGER NOT NULL,
    verse    TEXT NOT NULL,
    lang     TEXT NOT NULL,
    label    TEXT NOT NULL
);

-- Сноските под стиховете. `mark` е знакът им („*", „**"), какъвто стои и в
-- текста при отбелязаната дума.
CREATE TABLE notes (
    book     TEXT NOT NULL,
    chapter  INTEGER NOT NULL,
    verse    TEXT NOT NULL,
    lang     TEXT NOT NULL,
    mark     TEXT,
    text     TEXT NOT NULL
);

-- Подзаглавията на дяловете (сръбският ги носи слети в първия стих).
CREATE TABLE titles (
    book     TEXT NOT NULL,
    chapter  INTEGER NOT NULL,
    verse    TEXT NOT NULL,
    lang     TEXT NOT NULL,
    text     TEXT NOT NULL
);

-- Пояснения, които източникът показва при посочване, а не в самия текст.
-- `kind='info'` е бележката за квадратните скоби в Синодалния превод;
-- `kind='title'` е обяснението към дума, добавена от преводачите — там
-- `word` пази за коя дума се отнася.
--
-- Не се показват никъде засега. Пазят се, защото са истинско съдържание и
-- изхвърленото не се връща без ново теглене.
CREATE TABLE annotations (
    book     TEXT NOT NULL,
    chapter  INTEGER NOT NULL,
    verse    TEXT NOT NULL,
    lang     TEXT NOT NULL,
    kind     TEXT NOT NULL,
    word     TEXT,
    text     TEXT NOT NULL
);

-- Връзките навън, срещнати в стиховете (към страницата за зачалата и др.).
CREATE TABLE links (
    book     TEXT NOT NULL,
    chapter  INTEGER NOT NULL,
    verse    TEXT NOT NULL,
    lang     TEXT NOT NULL,
    href     TEXT NOT NULL,
    text     TEXT
);

-- Надписанията на псалмите („Началнику на хора. Псалом Давидов.") — те не
-- са стих от Писанието, а заглавие, и при четене се отличават.
--
-- ⚠ БЕЗ колона за език, и това е същината. Надписанието е свойство на
-- МЯСТОТО в Писанието, не на превода: щом Пс. 50:1 е заглавие, той е
-- заглавие на всички езици.
--
-- Оттам и как се пълни: източникът го бележи надеждно САМО в руския (151) и
-- в църковнославянския (136), а в българския — изобщо не. Тъй че двата
-- служат за УКАЗАТЕЛ, а стилът се прилага навсякъде по общия ключ. Иначе би
-- трябвало ръчно съпоставяне на всички надписания, което не е нужно.
CREATE TABLE headings (
    book     TEXT NOT NULL,
    chapter  INTEGER NOT NULL,
    verse    TEXT NOT NULL,
    PRIMARY KEY (book, chapter, verse)
) WITHOUT ROWID;

CREATE INDEX idx_verses_chapter ON verses (lang, book, chapter, ord);
CREATE INDEX idx_verses_key     ON verses (book, chapter, verse);
CREATE INDEX idx_zachala_place  ON zachala (lang, book, chapter);
CREATE INDEX idx_notes_place    ON notes   (lang, book, chapter, verse);
CREATE INDEX idx_titles_place   ON titles  (lang, book, chapter);
"""

# Изгледът с исканите колони. Строи се СЛЕД напълването, за да знае кои езици
# наистина ги има — иначе колона за непопълнен превод виси празна завинаги.
WIDE_TEMPLATE = """
CREATE VIEW verses_wide AS
SELECT book, chapter, verse,
{columns}
FROM verses
GROUP BY book, chapter, verse;
"""


def load_corrections():
    """Поправки по конкретен стих, четени от input/corrections.csv.

    ⚠ ЗАЩО ПО СТИХ, А НЕ ПО ДУМА. Изворникът има печатни грешки, но същата
    словоформа другаде е вярна: „възлизаме" е грешка в надписанието на Пс.
    119, а в Мт. 20:18, Мк. 10:33 и Лк. 18:31 е правилното сегашно време.
    Обща замяна щеше да счупи трите евангелски стиха мълчаливо. Затова
    ключът е (превод, книга, глава, стих).

    ⚠ Поправката се прилага ТУК, при сглобяването — не в кеша и не в JSON-а.
    Кешът е дословно копие на свалената страница и не бива да се пипа; а
    приложена при разглобяването, поправката би се губила при всяко ново
    теглене. Така преживява и двете.
    """
    rows = read_csv("corrections.csv", required=False)
    out = {}
    for r in rows:
        key = (r["lang"], r["book"], int(r["chapter"]), r["verse"])
        out.setdefault(key, []).append((r["find"], r["replace"]))
    return out


def read_csv(name, required=True):
    path = os.path.join(INPUT_DIR, name)
    if not os.path.exists(path):
        if required:
            sys.exit(f"Липсва {path}.")
        return []
    with open(path, encoding="utf-8") as fh:
        return list(csv.DictReader(fh))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--langs", default="", help="само тези езици (през запетая)")
    ap.add_argument("--out", default=DEFAULT_OUT)
    ap.add_argument("--with-raw", action="store_true",
                    help="слага и суровия HTML на всеки стих в базата. ⚠ Не за "
                         "приложението — базата отива в APK-то и всеки MB се "
                         "тегли от потребителите. За разработка, когато трябва "
                         "да се рови в маркировката със заявки.")
    args = ap.parse_args()

    books = read_csv("books.csv")
    books_bg = {r["code"]: r for r in read_csv("books_bg.csv")}
    langs_src = {r["code"]: r for r in read_csv("languages.csv")}
    langs_bg = read_csv("languages_bg.csv")

    if not os.path.isdir(JSON_DIR):
        sys.exit("Няма output/json/. Пусни първо 03_parse.py.")

    wanted = [c.strip() for c in args.langs.split(",") if c.strip()]
    langs = [l for l in langs_bg if not wanted or l["code"] in wanted]
    if not langs:
        sys.exit("Никой от исканите езици го няма в input/languages_bg.csv.")

    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    if os.path.exists(args.out):
        os.remove(args.out)

    con = sqlite3.connect(args.out)
    con.executescript(SCHEMA)

    for b in books:
        bg = books_bg.get(b["code"])
        if not bg:
            sys.exit(f"Няма българско име за книга {b['code']} — виж books_bg.csv.")
        con.execute(
            "INSERT INTO books (code, ord, testament, chapters, bg_title,"
            " bg_short, bg_abbr, ru_title) VALUES (?,?,?,?,?,?,?,?)",
            (b["code"], int(b["order"]), b["testament"], int(b["chapters"]),
             bg["bg_title"], bg["bg_short"], bg["bg_abbr"], b["ru_title"]))

    # Ключовете на надписанията, обединени от всички преводи, които ги
    # бележат. Виж бележката при таблицата `headings`.
    heading_keys = set()

    corrections = load_corrections()
    applied = 0
    unused = set(corrections)

    stats = []
    for lang in langs:
        code = lang["code"]
        src = langs_src.get(code, {})
        con.execute(
            "INSERT INTO languages (code, ord, bg_title, bg_short, bg_abbr,"
            " title, scope, direction, line_delta, size_delta, font,"
            " rubricate, note) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)",
            (code, int(lang["ord"]), lang["bg_title"], lang["bg_short"],
             lang.get("bg_abbr") or code[:2],
             src.get("title"), src.get("scope", "all"),
             lang["direction"], float(lang.get("line_delta") or 0),
             float(lang.get("size_delta") or 0),
             lang["font"] or None,
             1 if (lang.get("rubricate") or "0") == "1" else 0,
             lang["note"] or None))

        lang_dir = os.path.join(JSON_DIR, code)
        if not os.path.isdir(lang_dir):
            print(f"⚠ няма output/json/{code} — преводът остава празен")
            stats.append((code, 0, 0, 0))
            continue

        n_verses = n_books = 0
        for fname in sorted(os.listdir(lang_dir)):
            if not fname.endswith(".json"):
                continue
            with open(os.path.join(lang_dir, fname), encoding="utf-8") as fh:
                payload = json.load(fh)
            book = payload["book"]
            n_books += 1

            for chapter_str, verses in payload["chapters"].items():
                chapter = int(chapter_str)
                for ordinal, v in enumerate(verses, start=1):
                    fixes = corrections.get((code, book, chapter, v["verse"]))
                    if fixes:
                        for find, repl in fixes:
                            if find in v["text"]:
                                v["text"] = v["text"].replace(find, repl)
                                if v.get("html"):
                                    v["html"] = v["html"].replace(find, repl)
                                applied += 1
                                unused.discard((code, book, chapter, v["verse"]))
                    # HTML-ът се пази САМО ако наистина се различава от голия
                    # текст — инак базата носи два пъти едно и също за
                    # преводите без никаква маркировка (а те са мнозинството).
                    #
                    # ⚠ СРАВНЯВА СЕ СЛЕД РАЗКОДИРАНЕ НА СЪЩНОСТИТЕ. Гръцката
                    # Септуагинта идва с всяка буква като `&Alpha;` вместо
                    # `Α` — същият текст, само друго кодиране. Сравнен
                    # буквално, той „се различава" за 27 694 от 28 057 стиха
                    # и се пазеше втори път: 14,3 MB html срещу 3,2 MB текст,
                    # тоест пакетът на този превод излизаше 51,9 MB вместо
                    # към 10. Разкодирането не пипа истинската маркировка
                    # (`<i>`, `<sup>`) — тя си остава различна и се пази.
                    html_val = (v["html"]
                                if unescape(v["html"]) != v["text"] else None)
                    raw_val = v.get("raw") if args.with_raw else None
                    con.execute(
                        "INSERT OR REPLACE INTO verses (book, chapter, verse,"
                        " lang, ord, text, html, raw) VALUES (?,?,?,?,?,?,?,?)",
                        (book, chapter, v["verse"], code, ordinal,
                         v["text"], html_val, raw_val))
                    n_verses += 1

                    if v.get("heading"):
                        heading_keys.add((book, chapter, v["verse"]))
                    # Зачалата се събират ОТДЕЛНО, след всички езици —
                    # виж бележката там защо не бива да зависят от избора.
                    for note in v.get("notes", []):
                        con.execute(
                            "INSERT INTO notes (book, chapter, verse, lang,"
                            " mark, text) VALUES (?,?,?,?,?,?)",
                            (book, chapter, v["verse"], code,
                             note.get("mark") or None, note["text"]))
                    for title in v.get("titles", []):
                        con.execute(
                            "INSERT INTO titles (book, chapter, verse, lang,"
                            " text) VALUES (?,?,?,?,?)",
                            (book, chapter, v["verse"], code, title))
                    for ann in v.get("annotations", []):
                        con.execute(
                            "INSERT INTO annotations (book, chapter, verse,"
                            " lang, kind, word, text) VALUES (?,?,?,?,?,?,?)",
                            (book, chapter, v["verse"], code, ann["kind"],
                             ann.get("word"), ann["text"]))
                    for link in v.get("links", []):
                        con.execute(
                            "INSERT INTO links (book, chapter, verse, lang,"
                            " href, text) VALUES (?,?,?,?,?,?)",
                            (book, chapter, v["verse"], code,
                             link["href"], link.get("text")))

        n_chapters = con.execute(
            "SELECT COUNT(*) FROM (SELECT DISTINCT book, chapter FROM verses"
            " WHERE lang=?)", (code,)).fetchone()[0]
        stats.append((code, n_books, n_chapters, n_verses))

    con.executemany(
        "INSERT OR IGNORE INTO headings (book, chapter, verse) VALUES (?,?,?)",
        sorted(heading_keys))

    # ── Зачалата — от ВСИЧКИ преводи, не само от избраните ───────────────
    #
    # ⚠ ЗАЧАЛОТО Е СВОЙСТВО НА МЯСТОТО В ПИСАНИЕТО, не на превода: „Зач. 122"
    # стои на едно и също място, на който език и да четеш. Затова
    # приложението ги чете БЕЗ филтър по език (виж BibleDb.zachala).
    #
    # ⚠ Източникът обаче е ЕДИН: източникът ги бележи само в руския превод
    # (740 реда, всичките с lang='r'), а църковнославянският ги носи вградени
    # в самия текст. Събирани заедно с избраните езици, пускане като
    # `--langs bg,utfcs,cs,g,el-r` ги оставяше НУЛА — руският не влиза, тъй
    # че никой не ги внася — и настройката „Показвай зачалата" нямаше какво
    # да покаже.
    #
    # Затова тук се минава ОТДЕЛНО през всички папки в output/json/ и се
    # взимат само зачалата. Цената е един допълнителен прочит на JSON-ите;
    # печалбата е, че изборът на езици не може да ги отнесе мълчаливо.
    n_zach = 0
    for code in sorted(os.listdir(JSON_DIR)):
        lang_dir = os.path.join(JSON_DIR, code)
        if not os.path.isdir(lang_dir):
            continue
        for fname in sorted(os.listdir(lang_dir)):
            if not fname.endswith(".json"):
                continue
            with open(os.path.join(lang_dir, fname), encoding="utf-8") as fh:
                payload = json.load(fh)
            book = payload["book"]
            for chapter_str, verses in payload["chapters"].items():
                chapter = int(chapter_str)
                for v in verses:
                    for label in v.get("zachala", []):
                        con.execute(
                            "INSERT OR IGNORE INTO zachala (book, chapter,"
                            " verse, lang, label) VALUES (?,?,?,?,?)",
                            (book, chapter, v["verse"], code, label))
                        n_zach += 1
    print(f"зачала: {n_zach}")

    if corrections:
        print(f"поправки по стих: приложени {applied} от {len(corrections)}")
        # ⚠ Неприложена поправка се ИЗПИСВА. Мълчаливото ѝ подминаване е
        # най-лошият изход: изглежда, че е нанесена, а текстът си стои сгрешен.
        for key in sorted(unused):
            print(f"   ⚠ НЕ СЕ ПРИЛОЖИ: {key[0]} {key[1]}.{key[2]}:{key[3]}"
                  f" — текстът не съвпада")

    filled = [c for c, _b, _ch, v in stats if v]
    columns = ",\n".join(
        f"    MAX(CASE WHEN lang='{c}' THEN text END) AS text_{c.replace('-', '_')}"
        for c in filled)
    if columns:
        con.executescript(WIDE_TEMPLATE.format(columns=columns))

    con.commit()
    con.execute("VACUUM")
    con.close()

    print()
    print(f"{'превод':<10} {'книги':>6} {'глави':>7} {'стихове':>9}")
    print("-" * 36)
    for code, nb, nch, nv in stats:
        print(f"{code:<10} {nb:>6} {nch:>7} {nv:>9}")
    print("-" * 36)
    print(f"{'общо':<10} {'':>6} {'':>7} {sum(s[3] for s in stats):>9}")
    size = os.path.getsize(args.out) / (1024 * 1024)
    print()
    print(f"→ {args.out}  ({size:.1f} MB)")


if __name__ == "__main__":
    main()
