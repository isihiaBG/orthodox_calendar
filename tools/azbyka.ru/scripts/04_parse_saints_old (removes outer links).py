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

    # Вътрешни линкове към други светии → saint://slug (пази текста)
    def a_repl(m):
        href, inner = m.group(1), m.group(2)
        slug_m = re.search(r"/days/((?:sv|svv|ikona|prazdnik)-[^/?#'\"]+)", href)
        if slug_m:
            return f'<a href="saint://{slug_m.group(1)}">{inner}</a>'
        return inner  # външен/служебен линк → само текстът

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

def extract_name(page: str) -> str:
    m = re.search(r"<h1[^>]*>(.*?)</h1>", page, re.S)
    return strip_tags(m.group(1)) if m else ""


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
    os.makedirs(OUT_DIR, exist_ok=True)
    if not os.path.isdir(SAINTS_DIR):
        print(f"Липсва {SAINTS_DIR}. Пусни първо 03_fetch_saints.py.")
        sys.exit(1)

    files = sorted(fn for fn in os.listdir(SAINTS_DIR) if fn.endswith(".html"))
    if not files:
        print("Няма кеширани страници на светии.")
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

    fields = ["slug", "url", "name", "sign", "life_html", "sluzhba",
              "tropar", "tropar_trans", "tropar2", "tropar2_trans",
              "kondak", "kondak_trans", "kondak2", "kondak2_trans",
              "prayers_tropar_count", "prayers_kondak_count",
              "children", "icons", "review"]
    out = os.path.join(OUT_DIR, "saints_raw_ru.csv")
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
