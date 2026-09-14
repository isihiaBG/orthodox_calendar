#!/usr/bin/env python3
"""Разчита свалените страници от `cache/` в `output/json/`.

Пуска се от корена на проекта:

    python3 tools/bible_bg/scripts/02_parse.py
    python3 tools/bible_bg/scripts/02_parse.py --only Mk Ps

Изходът е по един JSON на книга, със същата форма, каквато чака `04_apply.py`:

    {"book": "Mk", "chapters": {"1": [{"verse": "1", "text": "…"}, …], …}}

⚠ КЕШЪТ НЕ СЕ ПИПА. Всяка поправка тук се пуска наново върху вече свалените
страници — без нито една заявка към чуждия сървър.
"""

import argparse
import csv
import html as htmlmod
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CACHE = os.path.join(ROOT, "cache")
OUT = os.path.join(ROOT, "output", "json")
BOOKS = os.path.join(ROOT, "input", "books.csv")

# ── Разпознаване на структурата ────────────────────────────────────────────
#
# ⚠ ТРИ РАЗЛИЧНИ СЛУЧАЯ, не един шаблон — виж README.
# ⚠ ЗАГЛАВИЕТО НА ГЛАВАТА НЕ Е ВИНАГИ В `<h3>`. При 2 Макавейска то стои в
# обикновен `<p>` („<p><a name="6"></a><br><br>ГЛАВА 6.</p>"), а книгата
# излизаше празна, без грешка. Затова се реже по САМАТА ДУМА „ГЛАВА N",
# независимо в какъв таг е обвита.
RE_CHAPTER_SPLIT = re.compile(r"(ГЛАВА\s*\d+)", re.I)
RE_CHAPTER_NO = re.compile(r"ГЛАВА\s*(\d+)", re.I)

# Текстовата колона. ⚠ `width="17%"` НЕ е текст — там стоят богослужебните
# бележки отстрани („Неделя пред Богоявление"); влязат ли, всяка глава ще носи
# по няколко фалшиви „стиха".
# ⚠ НЕ СЕ РАЗЧИТА НА `</td>` — старите страници просто го нямат (Псалом 1:
# шест отварящи клетки, два затварящи тага). Всеки израз от вида
# `<td…>(.*?)</td>` там не хваща НИЩО и книгата излиза празна, без грешка.
# Затова клетката се реже до СЛЕДВАЩАТА клетка, реда или таблицата.
RE_TD_OPEN = re.compile(r'<td([^>]*)>', re.I)
RE_CELL_END = re.compile(r'</td>|<td\b|</tr>|</table>', re.I)


def cells(raw, want):
    """Съдържанието на всяка клетка, чиято ширина съвпада с `want`."""
    out = []
    for m in RE_TD_OPEN.finditer(raw):
        if 'width="%s"' % want not in m.group(1).lower().replace("'", '"'):
            continue
        rest = raw[m.end():]
        stop = RE_CELL_END.search(rest)
        out.append(rest[:stop.start()] if stop else rest)
    return out

# ⚠ Речниковите връзки се махат ЦЕЛИ, заедно с иконката вътре. Оставена сама,
# тя оставя в текста празен `alt` или счупен интервал.
RE_DICT_LINK = re.compile(r"<a[^>]*>\s*<img[^>]*>\s*</a>", re.S | re.I)
RE_TAG = re.compile(r"<[^>]+>")
RE_BR = re.compile(r"<br\s*/?>", re.I)

# ⚠ ДВА ФОРМАТА НА НОМЕРИРАНЕ, не един — открито на 28.08.2026, след като
# седем книги излязоха с „нито една глава" въпреки напълно редовен шаблон:
#
#     „13. И Той беше…"    само стих  (Марк, Иуда, повечето)
#     „1:1 След смъртта…"  глава:стих (Иисус Навин, Рут, Песен на песните…)
#
# Номерът на главата във втория е излишен (той вече идва от `<h3>`), но се
# улавя нарочно — служи за проверка, че не сме се разминали с главата.
#
# ⚠ Двата случая са ИЗБРОЕНИ, а не сглобени в един израз с незадължителна
# точка. Иначе „5 хляба" в началото на ред би минало за стих 5.
RE_VERSE = re.compile(r"^\s*(?:(\d+):(\d+)|(\d+)[\.\)])\s*(.*)$", re.S)


def match_verse(t):
    """→ (номер на стих, текст) или None. Скрива разликата между двата вида."""
    m = RE_VERSE.match(t)
    if not m:
        return None
    verse = m.group(2) or m.group(3)
    return verse, m.group(4).strip()


def clean(fragment):
    """HTML къс → чист текст."""
    s = RE_DICT_LINK.sub("", fragment)
    s = RE_TAG.sub("", s)
    s = htmlmod.unescape(s)
    # ⚠ Неразделимият интервал идва като истински знак и после личи в четеца
    # като необяснимо широка шпация.
    s = s.replace("\xa0", " ")
    return re.sub(r"\s+", " ", s).strip()


def parse_verses(fragment, first_unnumbered=False):
    """Къс от текстовата колона → списък (номер, текст)."""
    out = []
    for piece in RE_BR.split(fragment):
        t = clean(piece)
        if not t:
            continue
        m = match_verse(t)
        if m:
            out.append(m)
        elif first_unnumbered and not out:
            # Неномерираното начало Е стих 1 — виж `parse_psalm`.
            out.append(("1", t))
        elif out:
            # ⚠ Продължение на предходния стих: източникът понякога слага <br>
            # вътре в стиха (при стихотворните книги). Залепва се, вместо да
            # се изхвърли — инак половин стих изчезва мълчаливо.
            out[-1] = (out[-1][0], (out[-1][1] + " " + t).strip())
    return out


def parse_book(raw):
    """Обикновена книга: „ГЛАВА N" + текстовите колони под него."""
    chapters = {}
    parts = RE_CHAPTER_SPLIT.split(raw)
    # parts = [преди, "ГЛАВА 1", тяло1, "ГЛАВА 2", тяло2, …]
    for i in range(1, len(parts) - 1, 2):
        m = RE_CHAPTER_NO.search(parts[i])
        if not m:
            continue
        ch = m.group(1)
        body = parts[i + 1]
        verses = []
        for td in cells(body, "83%"):
            verses.extend(parse_verses(td))
        # ⚠ ТРЕТИ НАЧИН НА ПОДРЕЖДАНЕ: част от книгите изобщо нямат таблици —
        # текстът стои направо в абзаци. При 2 Макавейска само три глави от
        # петнайсет са в клетки; останалите дванайсет излизаха празни, макар
        # заглавията им да се намираха. Тогава се чете цялото тяло на главата.
        #
        # Безопасно е, защото `parse_verses` взима САМО номерираните редове —
        # навигацията и бележките наоколо нямат номер и отпадат сами.
        if not verses:
            verses = parse_verses(body)
        if verses:
            chapters.setdefault(ch, []).extend(verses)

    # ⚠ КНИГА С ЕДНА ГЛАВА И БЕЗ ЗАГЛАВИЕ. „Послание на Иеремия" няма нито
    # едно „ГЛАВА N" — текстът започва направо. Без този клон книгата излизаше
    # празна, макар клетката ѝ да е на мястото си.
    if not chapters:
        verses = []
        for td in cells(raw, "83%"):
            verses.extend(parse_verses(td))
        if verses:
            chapters["1"] = verses
    return chapters


def parse_psalm(raw):
    """Един псалом.

    ⚠ И ТУК ШАБЛОНЪТ НЕ Е ЕДИН. Част от псалмите са двуколонни (българският е
    в първата `width="50%"`, до него църковнославянският — той не ни трябва,
    идва си от `utfcs`), а останалите са едноколонни в `width="100%"`.
    Затова се опитват поред.

    ⚠ ПЪРВИЯТ СТИХ Е БЕЗ НОМЕР. Източникът номерира от втория нататък, тъй че
    неномерираното начало се приписва на стих 1 — инак всеки псалом губи
    първия си стих мълчаливо.
    """
    for want in ("50%", "100%"):
        tds = cells(raw, want)
        if not tds:
            continue
        verses = parse_verses(tds[0], first_unnumbered=True)
        if verses:
            return verses
    return []


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", nargs="*", default=None)
    args = ap.parse_args()

    os.makedirs(OUT, exist_ok=True)
    with open(BOOKS, encoding="utf-8") as fh:
        rows = list(csv.DictReader(fh))
    if args.only:
        rows = [r for r in rows if r["code"] in set(args.only)]

    total_v = total_c = 0
    problems = []
    for r in rows:
        code, want_ch = r["code"], int(r["chapters"])
        chapters = {}

        if r["kind"] == "psalter":
            for n in range(1, 152):
                path = os.path.join(CACHE, "Ps_%03d.htm" % n)
                if not os.path.exists(path):
                    continue
                with open(path, encoding="utf-8") as fh:
                    v = parse_psalm(fh.read())
                if v:
                    chapters[str(n)] = v
        else:
            path = os.path.join(CACHE, "%s.htm" % code)
            if not os.path.exists(path):
                problems.append("%s — няма в кеша" % code)
                continue
            with open(path, encoding="utf-8") as fh:
                chapters = parse_book(fh.read())

        if not chapters:
            problems.append("%s — нито една глава" % code)
            continue

        nv = sum(len(v) for v in chapters.values())
        total_v += nv
        total_c += len(chapters)
        # ⚠ Броят глави се сверява срещу НАШАТА база, не срещу източника:
        # разминаване значи или пропуснат шаблон, или книга с друго деление.
        if len(chapters) != want_ch:
            problems.append("%s — %d глави, а се чакат %d"
                            % (code, len(chapters), want_ch))

        with open(os.path.join(OUT, "%s.json" % code), "w", encoding="utf-8") as fh:
            json.dump({"book": code,
                       "chapters": {k: [{"verse": a, "text": b} for a, b in v]
                                    for k, v in chapters.items()}},
                      fh, ensure_ascii=False, indent=1)

    print("книги   : %d" % (len(rows) - len([p for p in problems if "няма в кеша" in p])))
    print("глави   : %d" % total_c)
    print("стихове : %d" % total_v)
    if problems:
        print("\n⚠ за проверка (%d):" % len(problems))
        for p in problems[:40]:
            print("   " + p)
        sys.exit(1 if any("нито една" in p or "няма в кеша" in p for p in problems) else 0)


if __name__ == "__main__":
    main()
