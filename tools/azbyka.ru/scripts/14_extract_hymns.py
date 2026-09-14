#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
14_extract_hymns.py — вади ВСИЧКИ песнопения от кешираните страници на
светиите и ги нарежда в един плосък файл, готов за таблицата `hymns`.

  days/saints/<slug>.html  →  output/hymns.csv

Защо изобщо. Осемте колони в `texts` (tropar, tropar2, kondak, kondak2 и
преводите им) побират най-много по ДВА тропара и два кондака. Измерено по
1033-те наши светии това отрязва 93 тропара и 57 кондака у 77 души —
включително третия тропар на прп. Иоан Рилски („Покаяния основание…“,
глас 1), който е тъкмо онзи, който БПЦ пее като негов основен. Молитвите
(482) и величанията (153) пък не са вадени изобщо. Затова редът вече не е
колона, а ред в отделна таблица: тя поема колкото и да са.

Колони:
  slug     кой светия (същият слъг както в texts)
  ord      редът НА СТРАНИЦАТА, от 1 — пази последователността на azbyka
  kind     машинен вид: tropar | kondak | molitva | velichanie | other
  kind_ru  как е озаглавен на страницата: "Ин тропарь", "2-я Молитва"
  seq      кой пореден е ВЪТРЕ във вида си, от 1 (за „втори тропар“)
  glas     "глас 4" или празно
  csl      църковнославянският текст БЕЗ заглавието — не се превежда
  ru       руският превод от страницата (частта след "Перевод:")
  bg       българският превод; пълни се тук САМО където вече го имаме
  note     пояснителна бележка — виж по-долу защо не е превод

⚠ Съборните страници се ПРОПУСКАТ (166 от нашите). Там молитвите са на
различни светии и не могат да се припишат надеждно — първият тропар на
"Собор 12-ти апостолов" например е на ап. Юда. Всеки от тях си има своя
страница със своите песнопения. Същото правило държи и 04_parse_saints.py.

⚠ Готовите БЪЛГАРСКИ преводи се пренасят от lives.db по ПОЗИЦИЯ: старият
`tropar_trans` отива при първия тропар, `tropar2_trans` — при втория, и
така за кондаците. Съпоставянето е сигурно: ЦСЛ текстът в базата съвпада
буквално с онзи, който се вади от страницата днес (сверени 1690 текста,
0 разминавания). Тъй че наново се плаща само за наистина новите.

⚠ ОСЕМ стари превода нямат църковнославянски оригинал в базата (4 светии:
Фива Римска, св. Владимир, Порфирий Ефески, царица Тамара). Страницата им
днес не дава тези песнопения — при трима секцията с тропарите е празна,
при царица Тамара кондак изобщо няма. Тези преводи и ДНЕС не се виждат
никъде: reader_screen пропуска блок с празен ЦСЛ. Пренасят се въпреки
това, с празен `csl` и обяснение в `note` — иначе изчезват безследно, а
са истински текстове, за които вече е платено.

⚠ „Перевод:" на страницата НЕ Е винаги превод. Същият блок
`<p class="taks-explanation">` служи и за пояснителна бележка: под някои
молитви стои „Перевод: (имена)“ — указание какво се вмъква на мястото на
„имярек“, а не превод на молитвата. Такива 11 попадаха в колоната `ru` и
щяха да отидат за превод като самостоятелен текст. Разпознават се по
дължина: истинският превод е съизмерим с текста (отношение 0,75–1,5,
медиана 0,92), а бележките са под 0,02 от него. Между 0,013 и 0,75 няма
НИТО ЕДИН случай, тъй че прагът е с широк резерв в двете посоки. Отиват
в `note`, не се трият — иначе изчезват мълчаливо.

⚠ CSV-то тук НЕ ползва конвенцията на 04_parse_saints (| → /, ' → ").
Тя е загубна, а песнопенията минават оттук за пръв път. Разделителят
остава |, но оградата е стандартната двойна кавичка с удвояване.

Пуска се без нищо:  python3 14_extract_hymns.py
"""

import csv
import importlib.util
import os
import re
import sqlite3
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.dirname(SCRIPT_DIR)
SAINTS_DIR = os.path.join(PROJECT_DIR, "days", "saints")
OUT_DIR = os.path.join(PROJECT_DIR, "output")
OUT_CSV = os.path.join(OUT_DIR, "hymns.csv")
LIVES_DB = "/home/mypc/orthodox_calendar/assets/db/lives.db"

# Разчитането на страницата е вече написано — внасяме го, вместо да го
# повтаряме. Името на файла започва с цифра, тъй че обикновен import не
# става.
_spec = importlib.util.spec_from_file_location(
    "parse_saints", os.path.join(SCRIPT_DIR, "04_parse_saints.py"))
parse_saints = importlib.util.module_from_spec(_spec)
sys.modules["parse_saints"] = parse_saints
_spec.loader.exec_module(parse_saints)


# Под това отношение спрямо църковнославянския текст „преводът“ не е
# превод, а пояснителна бележка (виж докстринга). Наблюдаваните стойности
# са ≤0,013 за бележките и ≥0,75 за преводите — прагът стои в празното
# помежду им.
# ⚠⚠ СЪБОРНА СТРАНИЦА СЕ ПОЗНАВА ПО СПИСЪКА, НЕ ПО ВРЪЗКИТЕ (06.09.2026).
#
# Дотук признакът беше `extract_children()` — има ли ЛИНК към друг светия
# преди тропарите. Той обаче не различава „списък със светиите, които тази
# страница събира" от обикновено споменаване в разказа:
#
#   житието на св. Даниил Московски казва „четвърти син на <Александър
#   Невски>" — повествователна препратка, не събор;
#   заглавието при св. Кирил казва „жития на Кирил и <Методий>" — двойка,
#   чиито песнопения са ОБЩИ за двамата („Величаем вас, святии
#   равноапостольнии Мефодие и Кирилле");
#   а `sv-antonij-pecherski` се самопропускаше, защото нашият слъг е без
#   крайното „й", а каноничният на azbyka е `sv-antonij-pecherskij` — тъй
#   че собствената му канонична връзка минаваше за „дете".
#
# Цената: 166 страници се пропускаха, от които ИСТИНСКИ съборни са 13.
# Изгубени 520 песнопения, от тях 296 у 73 слъга без нито едно.
#
# ⚠ БРОЯТ ДЕЦА НЕ Е ПРИЗНАК — обхватите се застъпват: истинските имат от
# 12 до 690 връзки, лъжливите от 1 до 17. Праг тук е невъзможен.
#
# Истинската съборна страница има отделен блок със списъка:
#     <div class="block"> <h2>Список Святых</h2> <div class="brif"> <a …>
# Сверено: всичките 13 истински го имат, нито една от 153-те лъжливи.
#
# ⚠ Правилото стои ТУК, а не в extract_children() — тя се ползва и от
# 04_parse_saints.py за самите жития и значението ѝ там е друго („към кои
# страници сочи тази").
COLLECTIVE_RE = re.compile(r"<h2>\s*Спис[ое]к\s+[Сс]вятых\s*</h2>")


def is_collective(page: str) -> bool:
    """Съборна ли е страницата — по списъка със светиите, не по връзките."""
    return COLLECTIVE_RE.search(page) is not None


# Бележката, с която 06_hymns.py (конвейерът за Димитрий Ростовски) бележи
# своите редове. Тук служи само за да НЕ се пренасят те като готови преводи.
DMITRY_NOTE = 'от житието по свт. Димитрий Ростовски'

NOTE_RATIO = 0.3


def is_note(ru: str, csl: str) -> bool:
    """Бележка ли е това, а не превод."""
    if not ru or not csl:
        return False
    return len(ru) / len(csl) < NOTE_RATIO


def classify(kind_ru: str) -> str:
    """Машинен вид от заглавието на блока.

    Гледа се за подниз, защото azbyka пише и "Ин тропарь", и "2-я Молитва",
    и "3-я Молитва" — все същия вид, само пореден."""
    k = kind_ru.lower()
    if "тропарь" in k:
        return "tropar"
    if "кондак" in k:
        return "kondak"
    if "молитва" in k:
        return "molitva"
    if "величание" in k:
        return "velichanie"
    return "other"


def strip_heading(prayer: dict) -> str:
    """Текстът без заглавната част, която extract_prayers е долепила отпред.

    Тя строи `text` като "<kind>, <glas>: <тяло>" — тук същото се сглобява
    наново и се отрязва. Ако не съвпадне (страница с друга уредба), режем
    по първото ": ", а ако и то липсва — оставяме текста както е."""
    head = prayer["kind"] if prayer["kind"] else "?"
    if prayer["glas"]:
        head += f", {prayer['glas']}"
    head += ": "
    text = prayer["text"]
    if text.startswith(head):
        return text[len(head):]
    i = text.find(": ")
    return text[i + 2:] if 0 < i < 40 else text


def existing_bg() -> dict:
    """(slug, kind, seq) → готовият български превод от lives.db.

    ⚠ Гледа ПЪРВО таблицата `hymns`, и само ако я няма — старите осем
    колони на `texts`. Редът е такъв нарочно: колоните вече са изпразнени
    (виж 17_drop_old_hymn_columns.py), а всеки следващ пуск трябва да
    намира преводите някъде, инак 1548 готови текста се пращат наново към
    DeepSeek. Колонният път остава само за база отпреди пренасянето.
    """
    out = {}
    db = sqlite3.connect(LIVES_DB)
    has_hymns = db.execute(
        "SELECT 1 FROM sqlite_master WHERE type='table' AND name='hymns'"
    ).fetchone()

    if has_hymns:
        # ⚠⚠ ЧУЖДИТЕ ПРЕВОДИ НЕ СЕ ПРЕНАСЯТ ОТТУК (06.09.2026).
        # Съпоставянето е по ПОЗИЦИЯ (slug, вид, пореден номер), а редовете
        # от томовете по свт. Димитрий Ростовски са наредени по СВОЯ ред и
        # обикновено са по-малко. При св. Кирил например нашият тропар е
        # вторият на azbyka („Яко апостолом единонравнии"), а като seq=1 той
        # би се залепил за ПЪРВИЯ („От пелен прилежно") — съвсем друг текст,
        # при това мълчаливо. Пренасят се само преводи от самата azbyka.
        for slug, kind, seq, bg in db.execute(
                "SELECT slug, kind, seq, bg FROM hymns"
                " WHERE bg != '' AND (note IS NULL OR note <> ?)",
                (DMITRY_NOTE,)):
            out[(slug, kind, seq)] = bg
        db.close()
        return out

    rows = db.execute("""
        SELECT slug, tropar_trans, tropar2_trans, kondak_trans, kondak2_trans
        FROM texts
    """).fetchall()
    db.close()
    for slug, t1, t2, k1, k2 in rows:
        for kind, seq, val in (("tropar", 1, t1), ("tropar", 2, t2),
                               ("kondak", 1, k1), ("kondak", 2, k2)):
            if val:
                out[(slug, kind, seq)] = val
    return out


def main() -> int:
    if not os.path.isdir(SAINTS_DIR):
        print(f"няма {SAINTS_DIR}", file=sys.stderr)
        return 1

    db = sqlite3.connect(LIVES_DB)
    slugs = [r[0] for r in db.execute("SELECT slug FROM texts ORDER BY slug")]
    db.close()

    bg_map = existing_bg()
    os.makedirs(OUT_DIR, exist_ok=True)

    rows = []
    skipped_collective = skipped_missing = 0
    carried = notes = 0
    by_kind = {}

    for slug in slugs:
        path = os.path.join(SAINTS_DIR, slug + ".html")
        if not os.path.exists(path):
            skipped_missing += 1
            continue
        with open(path, encoding="utf-8") as f:
            page = f.read()

        before, services, tropari = parse_saints.split_sections(page)
        if is_collective(page):
            skipped_collective += 1
            continue

        prayers = parse_saints.extract_prayers(tropari)
        seen = {}
        for i, p in enumerate(prayers, start=1):
            kind = classify(p["kind"])
            seen[kind] = seen.get(kind, 0) + 1
            seq = seen[kind]
            bg = bg_map.get((slug, kind, seq), "")
            if bg:
                carried += 1
            by_kind[kind] = by_kind.get(kind, 0) + 1
            csl = strip_heading(p)
            ru, note = p["trans"], ""
            if is_note(ru, csl):
                ru, note = "", ru
                notes += 1
            rows.append({
                "slug": slug,
                "ord": i,
                "kind": kind,
                "kind_ru": p["kind"],
                "seq": seq,
                "glas": p["glas"],
                "csl": csl,
                "ru": ru,
                "bg": bg,
                "note": note,
            })

    # Стари преводи, които разчитането не покри — вж. докстринга. Лепят се
    # най-отзад за своя светия, за да не разместят номерата от страницата.
    orphans = 0
    used = {(r["slug"], r["kind"], r["seq"]) for r in rows}
    last_ord = {}
    for r in rows:
        last_ord[r["slug"]] = max(last_ord.get(r["slug"], 0), r["ord"])
    for (slug, kind, seq), bg in sorted(bg_map.items()):
        if (slug, kind, seq) in used:
            continue
        last_ord[slug] = last_ord.get(slug, 0) + 1
        rows.append({
            "slug": slug, "ord": last_ord[slug], "kind": kind,
            "kind_ru": "", "seq": seq, "glas": "", "csl": "", "ru": "",
            "bg": bg,
            "note": "стар превод без църковнославянски оригинал",
        })
        orphans += 1
    rows.sort(key=lambda r: (r["slug"], r["ord"]))

    with open(OUT_CSV, "w", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(
            f, fieldnames=["slug", "ord", "kind", "kind_ru", "seq",
                           "glas", "csl", "ru", "bg", "note"],
            delimiter="|", quotechar='"', quoting=csv.QUOTE_ALL)
        w.writeheader()
        w.writerows(rows)

    need_translation = sum(1 for r in rows if r["ru"] and not r["bg"])
    chars = sum(len(r["ru"]) for r in rows if r["ru"] and not r["bg"])

    print(f"светии в базата     : {len(slugs)}")
    print(f"съборни, пропуснати : {skipped_collective}")
    if skipped_missing:
        print(f"⚠ липсващи страници : {skipped_missing}")
    print(f"песнопения общо     : {len(rows)}")
    for k in sorted(by_kind, key=lambda k: -by_kind[k]):
        print(f"    {by_kind[k]:6}  {k}")
    print(f"с пренесен превод   : {carried}")
    print(f"пояснения, не превод: {notes}")
    print(f"сираци без ЦСЛ      : {orphans}")
    print(f"чакат превод        : {need_translation}  ({chars} знака)")
    print(f"\n→ {OUT_CSV}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
