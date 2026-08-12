#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
02b_extract_meta.py — Стъпка 2б (МЕХАНИЧНА, без DeepSeek): изважда текста,
който НЕ живее в главите — надписите на съдържанието и описанието на книгата.

Защо отделно от 02_extract.py: 02 обхожда блоковете (<h1>, <div
class="paragraph">) вътре в xhtml файловете. Надписите на каскадното
съдържание обаче стоят в toc.ncx, а името на книгата — в content.opf.
Нито едното не е блок в глава, тъй че 02 просто не ги вижда. Без тази
стъпка книгата излиза с български текст и РУСКО съдържание.

Второ съображение: 02 трие extract/ при всяко пускане. Този скрипт само
ДОБАВЯ extract/meta_toc.json и не пипа нищо друго, тъй че може да се пусне
безопасно, докато превод върви.

Адресиране (за да знае стъпка 4 къде да върне превода):
  ncx:<N>    N-тият <text> елемент в toc.ncx по ред в документа
             (нулевият е docTitle, останалите са надписите на navPoint-ите)
  opf:<таг>  съдържанието на <dc:title>, <dc:creator>, <dc:subject>
  html:title стойността на <title> в главите (една и съща във всички)

Изход:
  ../work/<том>/extract/meta_toc.json

Употреба:
  python3 02b_extract_meta.py --vol 09
"""

import argparse
import glob
import html
import json
import os
import re
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.dirname(SCRIPT_DIR)
WORK_DIR = os.path.join(PROJECT_DIR, "work")

OPF_TAGS = ("dc:title", "dc:creator", "dc:subject")
# Заглавието на корицата не е текст от книгата — не се превежда.
SKIP_HTML_TITLES = {"Cover"}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--vol", required=True)
    args = ap.parse_args()

    vols = [os.path.basename(d) for d in glob.glob(os.path.join(WORK_DIR, "*"))
            if os.path.basename(d).startswith(args.vol + "(")]
    if not vols:
        print("Няма подготвен том %s" % args.vol)
        sys.exit(1)
    vol = vols[0]

    work = os.path.join(WORK_DIR, vol)
    oebps = os.path.dirname(glob.glob(os.path.join(work, "src", "**",
                                                   "content.opf"),
                                      recursive=True)[0])
    units = []

    # --- надписите на съдържанието ---
    ncx = open(os.path.join(oebps, "toc.ncx"), encoding="utf-8").read()
    for i, m in enumerate(re.finditer(r"<text>(.*?)</text>", ncx, re.S)):
        t = html.unescape(m.group(1)).strip()
        if t:
            units.append({"target": "ncx:%d" % i, "kind": "toc",
                          "text": t, "tags": []})

    # --- описанието на книгата ---
    opf = open(os.path.join(oebps, "content.opf"), encoding="utf-8").read()
    for tag in OPF_TAGS:
        m = re.search(r"<%s[^>]*>([^<]+)</%s>" % (tag, tag), opf)
        if m:
            units.append({"target": "opf:%s" % tag, "kind": "meta",
                          "text": html.unescape(m.group(1)).strip(), "tags": []})

    # --- <title> в главите (една и съща стойност навсякъде) ---
    titles = set()
    for p in glob.glob(os.path.join(oebps, "Text", "*.xhtml")):
        m = re.search(r"<title>([^<]*)</title>",
                      open(p, encoding="utf-8").read())
        if m and m.group(1).strip() and m.group(1).strip() not in SKIP_HTML_TITLES:
            titles.add(m.group(1).strip())
    for t in sorted(titles):
        units.append({"target": "html:title", "kind": "meta",
                      "text": t, "tags": []})

    group = {
        "id": "meta_toc",
        "kind": "meta",
        "day": None,
        "saint": "съдържание и описание на книгата",
        "part": 1,
        "parts": 1,
        "units": units,
        "note_refs": [],
    }

    out_dir = os.path.join(work, "extract")
    os.makedirs(out_dir, exist_ok=True)
    path = os.path.join(out_dir, "meta_toc.json")
    with open(path, "w", encoding="utf-8") as f:
        json.dump(group, f, ensure_ascii=False, indent=1)

    kinds = {}
    for u in units:
        kinds[u["kind"]] = kinds.get(u["kind"], 0) + 1
    print("Том: %s" % vol)
    print("  единици: %d  %s" % (len(units), kinds))
    print("  символи: %d" % sum(len(u["text"]) for u in units))
    print("  → %s" % path)
    print("  (стъпка 3 ще я вземе при следващото пускане — вече готовите")
    print("   групи се прескачат, тъй че нищо не се превежда втори път)")


if __name__ == "__main__":
    main()
