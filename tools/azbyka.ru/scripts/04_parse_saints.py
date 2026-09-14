#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
04_parse_saints.py — Парсва ОФЛАЙН кешираните страници на светии
(days/saints/<slug>.html) и произвежда:

  output/saints_raw_ru.csv — суровите текстове:
      slug | url | name | sign | life_html | sluzhba |
      tropar | tropar_trans | tropar2 | tropar2_trans |
      kondak | kondak_trans | kondak2 | kondak2_trans |
      prayers_tropar_count | prayers_kondak_count | children | icons | review

  tropar/kondak       = основният "Тропарь"/"Кондак" (църковнославянски,
                        с гласа) — НЕ се превежда.
  tropar2/kondak2     = "Ин тропарь"/"Ин кондак" — втори, алтернативен текст
                        на СЪЩИЯ светия, ако има такъв.
  *_trans             = руският превод след "Перевод:" — само тези колони
                        (и life_html, name) отиват към DeepSeek за превод.

  Правило за пълнене: точно един основен → пълни се; точно един "Ин…" →
  отива във *2 колоната. Повече от един основен или повече от един "Ин…"
  (съборните страници) → празно + review=MANY_TROPARI/MANY_KONDAKI.

Правила:
  - Житието = "brif expandable" блоковете ПРЕДИ секцията <div id="tropari">,
    изчистени до едноредов HTML (само p/em/strong/h3), с вътрешни линкове
    пренаписани към saint://<slug> (за вградения четец във Flutter).
  - Тропар/кондак се пълнят САМО ако на страницата има точно по един —
    при съборните страници тропарите на отделните светии стоят в обща
    секция без надеждно приписване, затова там полетата остават празни
    и редът се маркира review=MANY_PRAYERS (светиите от събора имат свои
    страници със своите тропари).
  - Гласът е неразделна част от текста: "Тропарь, глас 4: …"; преводът,
    където го има, остава в текста след "Перевод:".
  - children = слъгове, към които сочи житието (разклонени страници).
  - Иконите се събират от URL-и вида …/icons-of-…: колона icons.

CSV конвенция: разделител |, ограда ', в текста ' → " и | → /.
"""

import csv
import html as htmlmod
import os
import re
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.dirname(SCRIPT_DIR)
SAINTS_DIR = os.path.join(PROJECT_DIR, "days", "saints")
OUT_DIR = os.path.join(PROJECT_DIR, "output")
INDEX_CSV = os.path.join(OUT_DIR, "index.csv")   # за колоната sign (по слъг)

# ---------------------------------------------------------------------------
# Текстови помощници
# ---------------------------------------------------------------------------

def clean_field(v: str) -> str:
    if v is None:
        return ""
    v = v.replace("'", '"').replace("|", "/")
    v = v.replace("\r", " ").replace("\n", " ")
    return re.sub(r"[ \t]+", " ", v).strip()


def strip_tags(s: str) -> str:
    s = re.sub(r"<[^>]+>", " ", s)
    s = htmlmod.unescape(s)
    return re.sub(r"\s+", " ", s).strip()


ALLOWED_TAGS = {"p", "em", "strong", "h3", "blockquote", "br", "i", "b"}

BASE = "https://azbyka.ru"   # за относителните адреси в линковете

# Библейските препратки от azbyka водят към РУСКИ текст. Опашката
# „&bg~utfcs" отваря българския с успореден църковнославянски (плъзга се
# надясно на сайта) — за приложение на български това е правилната цел.
#
# Правилото е едно и също навсякъде: има ли вече bg~utfcs → не се пипа;
# има ли руска опашка → заменя се; няма ли опашка → добавя се. Повечето
# връзки в тези страници са без опашка изобщо.
#
# Пипат се САМО връзките към /biblia/. Другите azbyka адреси (свети отци,
# правила на съборите, Минеи) нямат такъв превключвател.
#
# Същото се прилага и върху вече съставената база от 13_bible_links_bg.py.
BIBLE_TAIL = "&bg~utfcs"
# Руските режими, които се ЗАМЕНЯТ (а не се трупат отгоре): „&cr&rus" за
# отделен стих и „&r" за цяла книга. Проверено на живо — и двата отстъпват
# мястото си на българската опашка.
BIBLE_MODES = ("&cr&rus", "&r")


def bulgarian_bible(href: str) -> str:
    if "/biblia/" not in href or "bg~utfcs" in href:
        return href
    for mode in BIBLE_MODES:
        if href.endswith(mode):
            return href[: -len(mode)] + BIBLE_TAIL
        if mode + "&" in href:
            return href.replace(mode + "&", "&") + BIBLE_TAIL
    return href + BIBLE_TAIL


def sanitize_life_html(fragment: str) -> str:
    """
    Свежда HTML фрагмента на житието до едноредов, чист HTML:
    маха script/style/img/коментари, пренаписва вътрешните линкове към
    saint://<slug>, маха външните <a> (оставя текста им), допуска само
    ALLOWED_TAGS, и премахва новите редове.
    """
    s = fragment
    s = re.sub(r"<!--.*?-->", "", s, flags=re.S)
    s = re.sub(r"<(script|style)\b.*?</\1>", "", s, flags=re.S | re.I)
    s = re.sub(r"<img\b[^>]*>", "", s, flags=re.I)

    # Линковете:
    #   • вътрешни към друг светия  → saint://slug  (навигация в приложението)
    #   • външни към azbyka и др.   → ЗАПАЗВАТ СЕ като http(s) адрес
    #   • относителни (/otechnik/…) → правят се абсолютни
    #
    # Външните се пазят, защото службата понякога се състои САМО от линк
    # към Минея ("Минея. 29 ноября") — изхвърлянето му оставяше мъртъв текст.
    # Четецът ги отваря в браузъра през url_launcher.
    def a_repl(m):
        href, inner = m.group(1), m.group(2)
        slug_m = re.search(r"/days/((?:sv|svv|ikona|prazdnik)-[^/?#'\"]+)", href)
        if slug_m:
            return f'<a href="saint://{slug_m.group(1)}">{inner}</a>'
        if href.startswith("http://") or href.startswith("https://"):
            return f'<a href="{bulgarian_bible(href)}">{inner}</a>'
        if href.startswith("/"):
            return f'<a href="{bulgarian_bible(BASE + href)}">{inner}</a>'
        return inner  # javascript:, #anchor и подобни → само текстът

    s = re.sub(r"<a\s+[^>]*href=['\"]([^'\"]+)['\"][^>]*>(.*?)</a>",
               a_repl, s, flags=re.S | re.I)

    # Позволени тагове: чистим атрибутите им; останалите тагове изчезват.
    def tag_repl(m):
        closing, name = m.group(1), m.group(2).lower()
        if name == "a":
            return m.group(0)          # вече обработени по-горе
        if name in ALLOWED_TAGS:
            return f"<{closing}{name}>"
        return " "

    s = re.sub(r"<(/?)([a-zA-Z0-9]+)\b[^>]*>", tag_repl, s)

    s = s.replace("\r", " ").replace("\n", " ")
    s = re.sub(r"\s+", " ", s)
    s = re.sub(r"(<p>\s*)+", "<p>", s)
    s = re.sub(r"\s*</p>\s*(</p>\s*)+", "</p>", s)
    s = re.sub(r"<p>\s*</p>", "", s)
    return s.strip()


# ---------------------------------------------------------------------------
# Извличане на съставните части
# ---------------------------------------------------------------------------

# В заглавието azbyka обвива ударението в собствен span:
#     Иаки<span class="title-custom-character">́</span>нф
# strip_tags заменя таговете с ИНТЕРВАЛ и така разкъсва буквата
# ("Иаки ́ нф"). Затова тези span-ове се разгъват предварително, без интервал.
ACCENT_SPAN_RE = re.compile(
    r'<span[^>]*class\s*=\s*["\']title-custom-character["\'][^>]*>(.*?)</span>',
    re.S | re.I)


def extract_name(page: str) -> str:
    m = re.search(r"<h1[^>]*>(.*?)</h1>", page, re.S)
    if not m:
        return ""
    raw = ACCENT_SPAN_RE.sub(r"\1", m.group(1))
    return strip_tags(raw)


def split_sections(page: str):
    """
    Разделя страницата на три части по структурата на azbyka:

        [ … жития … ]  <div id="services">  [ … служба … ]  <div id="tropari"> [ … ]

    Секцията id="services" СЪЩЕСТВУВА винаги, но е празна, когато светията
    няма служба (тогава между нея и id="tropari" няма brif блокове).

    Връща (частта с житието, частта със службата, частта с тропарите).
    """
    ms = re.search(r'<div id="services"', page)
    mt = re.search(r'<div id="tropari"', page)

    life_end = ms.start() if ms else (mt.start() if mt else len(page))
    life_part = page[:life_end]

    if ms:
        srv_end = mt.start() if mt and mt.start() > ms.start() else len(page)
        srv_part = page[ms.start():srv_end]
    else:
        srv_part = ""

    trop_part = page[mt.start():] if mt else ""
    return life_part, srv_part, trop_part


# Текстовете на azbyka стоят в <div class="brif"> блокове. Два варианта:
#   "brif expandable" — дълги текстове, с бутон "Развернуть" (<div class="read-more">)
#   "brif"            — по-кратки, БЕЗ бутон и БЕЗ read-more терминатор
# Изрично НЕ хващаме "brif dates" (дневното резюме — то не е житие).
BRIF_START_RE = re.compile(r'<div class="brif(?: expandable)?">', re.I)
DIV_OPEN_RE = re.compile(r'<div\b', re.I)
DIV_CLOSE_RE = re.compile(r'</div>', re.I)

# Секции, които СЛЕДВАТ житието и не са част от него. Житийната част свършва
# при първата от тях. (Имената са стабилни за azbyka; ако сменят оформлението,
# тук е мястото за корекция.)
LIFE_END_MARKERS = [
    r'<h2[^>]*>\s*Жития и книги',    # библиотечни препратки към книги
    r'<h2[^>]*>\s*Аудиокалендарь',
    r'<h2[^>]*>\s*Список Святых',    # при съборните страници
    r'<h2[^>]*>\s*Книги, статьи',
    r'<div id="services"',
    r'<div id="tropari"',
]


def div_contents(section: str, start_re: re.Pattern) -> list[str]:
    """
    Връща съдържанието на всеки <div>, чийто отварящ таг съвпада със start_re.
    Краят се намира чрез БРОЕНЕ на вложените <div> — не чрез терминатор.

    Това е важно: кратките текстове на azbyka (жития и молитви) нямат бутон
    "Развернуть", тоест нямат <div class="read-more">. Разчитането на него
    водеше до поглъщане на цялата останала страница.
    """
    out = []
    for m in start_re.finditer(section):
        start = m.end()
        depth, pos = 1, start
        while depth > 0:
            no = DIV_OPEN_RE.search(section, pos)
            nc = DIV_CLOSE_RE.search(section, pos)
            if nc is None:
                break                      # незатворен блок → пропускаме
            if no and no.start() < nc.start():
                depth += 1
                pos = no.end()
            else:
                depth -= 1
                pos = nc.end()
                if depth == 0:
                    out.append(section[start:nc.start()])
    return out


def find_brif_blocks(section: str) -> list[str]:
    """Съдържанието на brif блоковете (житие / служба)."""
    return div_contents(section, BRIF_START_RE)


# ---------------------------------------------------------------------------
# Дните на паметта ("День памяти")
# ---------------------------------------------------------------------------
# azbyka ползва ДВА варианта на класа за тази секция — и двата се срещат
# в сурови страници: "brif dates" и "brif memorial-day".
DATES_START_RE = re.compile(r'<div class="brif (?:dates|memorial-day)">', re.I)
DATE_P_RE = re.compile(r'<p>(.*?)</p>', re.S | re.I)
DATE_HREF_RE = re.compile(r'/days/(\d{4})-(\d{2})-(\d{2})')
SOBOR_SPAN_RE = re.compile(r'<span>\s*[-–—]\s*Собор', re.I)


def extract_dates(page: str) -> tuple[list[str], list[str], list[str]]:
    """
    Вади дните на паметта от секцията "День памяти".

    Структурата е:
        <div class="brif dates">            (или class="brif memorial-day")
          <p><a href="/days/2027-05-05">5 мая</a>
             <span class="rolling">(переходящая)</span>
             <span> - Собор Синайских преподобных</span></p>
          <p><a href="/days/2026-07-20">20 июля</a></p>     ← личният ден
        </div>

    Всеки <p> е една памет. Два маркера я определят:
      class="rolling"      → подвижен празник (мени датата всяка година)
      <span> - Собор …</span> → съборен ден, не личният ден на светията

    Връща (own, all, labelled):
      own      — ЛИЧНИТЕ дни: MM-DD, без подвижни и без съборни
      all      — всички дни: MM-DD
      labelled — дните с етикет и маркер, за показване и за догодина:
                 "05-05:rolling:Собор Синайских преподобных"
                 "07-20::"                       (личен, неподвижен)
                 "09-06:rolling:Собор Московских святых"
                 Форматът е MM-DD:флаг:име — флагът е "rolling" или празно,
                 името е на събора или празно.

    ВАЖНО: форматът е MM-DD, годината се изхвърля нарочно. azbyka показва
    "следващото случване" спрямо деня на сваляне — затова една и съща
    страница дава 2027 за минали дати и 2026 за предстоящи.
    """
    blocks = div_contents(page, DATES_START_RE)
    if not blocks:
        return [], [], []

    own, every, labelled = [], [], []
    for pm in DATE_P_RE.finditer(blocks[0]):
        block = pm.group(1)
        hm = DATE_HREF_RE.search(block)
        if not hm:
            continue
        md = f"{hm.group(2)}-{hm.group(3)}"

        rolling = 'class="rolling"' in block
        sm = SOBOR_SPAN_RE.search(block)
        sobor_name = ""
        if sm:
            # Целият span с името на събора/неделята
            full = re.search(r"<span>\s*[-–—]\s*(.*?)</span>", block, re.S)
            if full:
                sobor_name = strip_tags(full.group(1))
                sobor_name = sobor_name.replace("|", "/").replace("'", '"')

        if md not in every:
            every.append(md)
        if not rolling and not sm and md not in own:
            own.append(md)

        labelled.append(f"{md}:{'rolling' if rolling else ''}:{sobor_name}")

    return own, every, labelled


def trim_life_section(life_part: str) -> str:
    """Отрязва житийната част при първата следваща секция."""
    ends = []
    for pat in LIFE_END_MARKERS:
        m = re.search(pat, life_part)
        if m:
            ends.append(m.start())
    return life_part[:min(ends)] if ends else life_part


def extract_brif(section: str) -> str:
    """Слива brif блоковете на дадена секция в едноредов чист HTML."""
    parts = find_brif_blocks(section)
    if not parts:
        return ""
    return sanitize_life_html(" ".join(parts))


PRAYER_SPLIT_RE = re.compile(r'<div class="inner taks_content">')
KIND_RE = re.compile(r"--widget-color[^>]*>\s*([^<]+?)\s*</span>")
GLAS_RE = re.compile(r'<span class="glas">\s*([^<]+?)\s*</span>')

def extract_prayers(tropari_section: str) -> list[dict]:
    """
    Връща списък от {kind, glas, text, trans} за всеки taks_content блок.
    kind: Тропарь / Кондак / Ин тропарь / Молитва / Величание …
    text : църковнославянският текст (новокирилица) като "Kind, глас N: тяло".
           НЕ подлежи на превод — ползваем директно и от български читатели.
    trans: руският превод (частта след "Перевод:"), празен ако липсва.
           Именно тази част се превежда на български на следващия етап.
    """
    prayers = []
    # Всеки молитвен блок е <div class="inner taks_content"> … </div>.
    # Границата се намира чрез броене на вложените div — кратките молитви
    # нямат "Развернуть", тъй че read-more терминатор може и да липсва.
    for chunk in div_contents(tropari_section, PRAYER_SPLIT_RE):
        # Ако все пак има read-more (дълга молитва), режем и по него.
        body_html = chunk.split('<div class="read-more">')[0]
        km = KIND_RE.search(body_html)
        kind = strip_tags(km.group(1)) if km else ""
        gm = GLAS_RE.search(body_html)
        glas = strip_tags(gm.group(1)) if gm else ""
        # Махаме заглавния h3, за да остане само текстът
        body_html = re.sub(r"<h3\b.*?</h3>", " ", body_html, flags=re.S)
        text = strip_tags(body_html)
        if not text:
            continue
        # Разцепваме на църковнославянски текст и руски превод по "Перевод:"
        trans = ""
        split = re.split(r"Перевод\s*:\s*", text, maxsplit=1)
        if len(split) == 2:
            text, trans = split[0].strip(), split[1].strip()
        head = kind if kind else "?"
        if glas:
            head += f", {glas}"
        prayers.append({"kind": kind, "glas": glas,
                        "text": f"{head}: {text}",
                        "trans": trans})
    return prayers


CHILD_LINK_RE = re.compile(r"/days/(sv-[a-z0-9\-]+)")

def extract_children(life_before: str, own_slug: str) -> list[str]:
    """Слъгове, към които сочи съдържанието преди тропарите (разклонения)."""
    found = []
    for s in CHILD_LINK_RE.findall(life_before):
        if s != own_slug and s not in found:
            found.append(s)
    return found


ICON_RE = re.compile(r"https?://[^\s'\"<>]*icons-of-[^\s'\"<>]+")

def extract_icons(page: str) -> list[str]:
    icons = []
    for u in ICON_RE.findall(page):
        u = htmlmod.unescape(u)
        if u not in icons:
            icons.append(u)
    return icons


# ---------------------------------------------------------------------------
# Основна логика
# ---------------------------------------------------------------------------

def load_signs() -> dict:
    """slug → sign от index.csv (ако е наличен)."""
    signs = {}
    if not os.path.exists(INDEX_CSV):
        return signs
    with open(INDEX_CSV, encoding="utf-8", newline="") as f:
        r = csv.DictReader(f, delimiter="|", quotechar="'")
        for row in r:
            slug = row.get("slug", "")
            if slug and slug not in signs and row.get("sign"):
                signs[slug] = row["sign"]
    return signs


def parse_one(slug: str, page: str, signs: dict) -> dict:
    before, services, tropari = split_sections(page)
    life = extract_brif(trim_life_section(before))
    sluzhba = extract_brif(services)      # богослужебното последование
    prayers = extract_prayers(tropari)
    dates_own, dates_all, dates_labelled = extract_dates(page)
    children = extract_children(before, slug)
    icons = extract_icons(page)

    # Тропарите и кондаците В РЕДА НА СТРАНИЦАТА (основни и "Ин ..." заедно —
    # "Ин тропарь" е просто втори тропар на същия светия).
    tropar_items = [p for p in prayers if "тропарь" in p["kind"].lower()]
    kondak_items = [p for p in prayers if "кондак" in p["kind"].lower()]

    review = []
    tropar = tropar_trans = tropar2 = tropar2_trans = ""
    kondak = kondak_trans = kondak2 = kondak2_trans = ""

    if children:
        # СЪБОРНА страница (има препратки към отделни светии): молитвите тук
        # са на РАЗЛИЧНИ светии и не могат да се припишат надеждно — първият
        # тропар на "Собор 12-ти апостолов" например е на ап. Юда. Не пълним
        # нищо; всеки светия има своя страница със своите молитви.
        review.append("COLLECTIVE")
    else:
        # Пълним първите два; ако има още, редът се маркира за преглед.
        if len(tropar_items) >= 1:
            tropar = tropar_items[0]["text"]
            tropar_trans = tropar_items[0]["trans"]
        if len(tropar_items) >= 2:
            tropar2 = tropar_items[1]["text"]
            tropar2_trans = tropar_items[1]["trans"]
        if len(tropar_items) > 2:
            review.append(f"EXTRA_TROPARI_{len(tropar_items) - 2}")

        if len(kondak_items) >= 1:
            kondak = kondak_items[0]["text"]
            kondak_trans = kondak_items[0]["trans"]
        if len(kondak_items) >= 2:
            kondak2 = kondak_items[1]["text"]
            kondak2_trans = kondak_items[1]["trans"]
        if len(kondak_items) > 2:
            review.append(f"EXTRA_KONDAKI_{len(kondak_items) - 2}")

        # Величание, Молитва и др. нямат своя колона — засега се изпускат,
        # но ги отбелязваме, за да се знае какво остава неизвлечено.
        others = sorted({p["kind"] for p in prayers
                         if "тропарь" not in p["kind"].lower()
                         and "кондак" not in p["kind"].lower()
                         and p["kind"]})
        if others:
            review.append("DROPPED:" + ",".join(others))

    if not life:
        review.append("NO_LIFE")
    if children:
        review.append("HAS_CHILDREN")

    return {
        "slug": slug,
        "url": f"https://azbyka.ru/days/{slug}",
        "name": extract_name(page),
        "sign": signs.get(slug, ""),
        "dates_own": ";".join(dates_own),
        "dates_all": ";".join(dates_all),
        "dates_labelled": ";".join(dates_labelled),
        "life_html": life,
        "sluzhba": sluzhba,
        "tropar": tropar,
        "tropar_trans": tropar_trans,
        "tropar2": tropar2,
        "tropar2_trans": tropar2_trans,
        "kondak": kondak,
        "kondak_trans": kondak_trans,
        "kondak2": kondak2,
        "kondak2_trans": kondak2_trans,
        "prayers_tropar_count": len(tropar_items),
        "prayers_kondak_count": len(kondak_items),
        "children": ",".join(children),
        "icons": ",".join(icons),
        "review": ";".join(review),
    }


def main():
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument("--slugs-file", help=(
        "Текстов файл с по един slug на ред — парсва САМО тях (от вече "
        "кешираните HTML), вместо всички файлове в days/saints/. Изходът "
        "отива в saints_raw_ru_missing.csv по подразбиране, за да не "
        "презаписва пълния saints_raw_ru.csv."))
    ap.add_argument("--out", help="Изходен CSV файл (подразбиране зависи от --slugs-file).")
    args = ap.parse_args()

    os.makedirs(OUT_DIR, exist_ok=True)
    if not os.path.isdir(SAINTS_DIR):
        print(f"Липсва {SAINTS_DIR}. Пусни първо 03_fetch_saints.py.")
        sys.exit(1)

    if args.slugs_file:
        with open(args.slugs_file, encoding="utf-8") as f:
            wanted = [s.strip() for s in f if s.strip()]
        files = []
        missing_html = []
        for slug in wanted:
            fn = slug + ".html"
            if os.path.exists(os.path.join(SAINTS_DIR, fn)):
                files.append(fn)
            else:
                missing_html.append(slug)
        if missing_html:
            print(f"ВНИМАНИЕ: {len(missing_html)} slug-а нямат кеширан HTML "
                  f"(пусни 03_fetch_saints.py за тях): {', '.join(missing_html)}")
        out_default = "saints_raw_ru_missing.csv"
    else:
        files = sorted(fn for fn in os.listdir(SAINTS_DIR) if fn.endswith(".html"))
        out_default = "saints_raw_ru.csv"

    if not files:
        print("Няма кеширани страници на светии за обработка.")
        sys.exit(1)

    signs = load_signs()
    rows = []
    for fn in files:
        slug = fn[:-5]
        page = open(os.path.join(SAINTS_DIR, fn), encoding="utf-8").read()
        row = parse_one(slug, page, signs)
        rows.append(row)
        flag = f"  [{row['review']}]" if row["review"] else ""
        print(f"{slug}: тропари={row['prayers_tropar_count']} "
              f"кондаци={row['prayers_kondak_count']} "
              f"житие={'да' if row['life_html'] else 'НЕ'} "
              f"служба={'да' if row['sluzhba'] else '-'}{flag}")

    fields = ["slug", "url", "name", "sign",
              "dates_own", "dates_all", "dates_labelled",
              "life_html", "sluzhba",
              "tropar", "tropar_trans", "tropar2", "tropar2_trans",
              "kondak", "kondak_trans", "kondak2", "kondak2_trans",
              "prayers_tropar_count", "prayers_kondak_count",
              "children", "icons", "review"]
    out = os.path.join(OUT_DIR, args.out or out_default)
    with open(out, "w", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fields, delimiter="|",
                           quotechar="'", quoting=csv.QUOTE_MINIMAL,
                           extrasaction="ignore")
        w.writeheader()
        for r in rows:
            w.writerow({k: clean_field(str(r.get(k, ""))) for k in fields})

    n_review = sum(1 for r in rows if r["review"])
    print(f"\nОбщо: {len(rows)} страници | за преглед: {n_review}")
    print(f"Изход: {out}")


if __name__ == "__main__":
    main()
