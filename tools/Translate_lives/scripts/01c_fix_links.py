#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
01c_fix_links.py — Стъпка 1в (МЕХАНИЧНА, без DeepSeek): превръща мъртвите
кръстосани препратки между житията в работещи — но САМО тези, чиято цел е в
същия том.

Откъде идват: книгите са направени от сайта azbyka.ru, където едно житие
сочи към друго с адрес от вида "../zhitija-svjatykh/1021" — 1021 е id-то на
целевото житие (същото число, което стои в <h1 id="1021"> на главата му).
В сайта това работи. В .epub не работи никъде: такава папка няма.

В целия набор има ~1505 такива препратки. Само ~164 сочат към житие в СЪЩИЯ
том — те стават истински вътрешни връзки и се поправят тук. Останалите ~1320
сочат в друг месец и няма как да проработят вътре в един .epub (напр.
„Прокл" в житието на преп. Мелания от 31 декември води към ноемврийското
житие на св. Прокл). Те се ОСТАВЯТ както са — ще се разрешат по-късно в
приложението, където всичките 1144 жития ще са в обща база. Тук нищо не се
влошава: мъртва връзка си остава мъртва връзка.

Пипа се САМО стойността на href. Видимият текст, броят и редът на блоковете
остават непокътнати — проверява се след това, защото буквицата виси на реда
на div-овете.

ВАЖНО за реда на стъпките: тази поправка променя таговете в книгата. Стъпка 4
чете таговете НАНОВО от книгата (а не от извлечените JSON-и), тъй че
поправката може да се пусне по всяко време — и преди, и след превода — без
да се преразглобява или превежда каквото и да било повторно.

Вход:
  ../work/<том>/src/     (след 01_merge_notes.py)

Изход:
  същите файлове, поправени на място

Употреба:
  python3 01c_fix_links.py --all
  python3 01c_fix_links.py --vol 12 --dry-run
"""

import argparse
import glob
import html
import os
import re
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.dirname(SCRIPT_DIR)
WORK_DIR = os.path.join(PROJECT_DIR, "work")

RE_LIFE_LINK = re.compile(r'href="\.\./zhitija-svjatykh/(\d+)"')
RE_TAG = re.compile(r'<[^>]+>')
RE_PARA = re.compile(r'<div class="paragraph"')
RE_BODY = re.compile(r'<body[^>]*>(.*)</body>', re.S)


def visible(x):
    b = RE_BODY.search(x)
    return " ".join(html.unescape(RE_TAG.sub(" ", b.group(1) if b else x)).split())


def life_index(oebps):
    """id на житие → името на файла, който го съдържа (в същия том)."""
    out = {}
    for p in glob.glob(os.path.join(oebps, "Text", "*.xhtml")):
        m = re.search(r'<h1[^>]*id="(\d+)"', open(p, encoding="utf-8").read())
        if m:
            out[m.group(1)] = os.path.basename(p)
    return out


def process(vol, dry):
    src = os.path.join(WORK_DIR, vol, "src")
    oebps = os.path.dirname(glob.glob(os.path.join(src, "**", "content.opf"),
                                      recursive=True)[0])
    lives = life_index(oebps)

    fixed = same = other = 0
    changed_files = 0
    for p in sorted(glob.glob(os.path.join(oebps, "Text", "*.xhtml"))):
        s = open(p, encoding="utf-8").read()
        hits = RE_LIFE_LINK.findall(s)
        if not hits:
            continue

        before_text, before_paras = visible(s), len(RE_PARA.findall(s))

        def repl(m):
            nonlocal same, other
            nid = m.group(1)
            target = lives.get(nid)
            if not target:
                other += 1
                return m.group(0)          # в друг том или никъде — не пипаме
            same += 1
            return 'href="%s#%s"' % (target, nid)

        new = RE_LIFE_LINK.sub(repl, s)
        if new == s:
            continue

        # Пипнали сме само атрибут — текстът и блоковете трябва да са същите.
        if visible(new) != before_text:
            print("  ✗ променен видим текст: %s" % os.path.basename(p))
            return
        if len(RE_PARA.findall(new)) != before_paras:
            print("  ✗ променен брой параграфи: %s" % os.path.basename(p))
            return

        fixed += len(hits)
        changed_files += 1
        if not dry:
            with open(p, "w", encoding="utf-8") as f:
                f.write(new)

    print("  препратки към жития: %d | поправени (в същия том): %d | "
          "оставени (друг том или без цел): %d"
          % (same + other, same, other))
    if dry:
        print("  (--dry-run: нищо не е записано)")
        return

    # --- проверка: всяка поправена връзка води до реално място ---
    broken = []
    for p in glob.glob(os.path.join(oebps, "Text", "*.xhtml")):
        s = open(p, encoding="utf-8").read()
        for tgt, anch in re.findall(r'href="(index_split_\d+\.xhtml)#(\d+)"', s):
            full = os.path.join(oebps, "Text", tgt)
            if not os.path.exists(full):
                broken.append((tgt, anch, "няма файл"))
            elif 'id="%s"' % anch not in open(full, encoding="utf-8").read():
                broken.append((tgt, anch, "няма котва"))
    print("  проверка на поправените: счупени %d %s"
          % (len(broken), broken[:3] if broken else ""))
    print("  останали мъртви „../zhitija-svjatykh/N“: %d" % other)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--vol")
    ap.add_argument("--all", action="store_true")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    vols = sorted(os.path.basename(d) for d in glob.glob(os.path.join(WORK_DIR, "*"))
                  if os.path.isdir(os.path.join(d, "src"))
                  and os.path.basename(d) != "_source")
    if args.vol:
        vols = [v for v in vols if v.startswith(args.vol + "(")]
    elif not args.all:
        print("Подай --vol NN или --all")
        sys.exit(1)

    for v in vols:
        print("=" * 64)
        print("Том: %s" % v)
        process(v, args.dry_run)


if __name__ == "__main__":
    main()
