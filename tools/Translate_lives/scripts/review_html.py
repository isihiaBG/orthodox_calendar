#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
review_html.py — помощен: прави страница за преглед на превода, руският и
българският текст един до друг, блок по блок.

Не е част от конвейера — нищо не произвежда и нищо не променя. Служи само
за човешки поглед върху готовите преводи, преди да се сглоби книгата.

Запушалките ⟦N⟧ се заменят с ▪, за да не пречат на четенето; целостта им
се проверява отделно (в 03_translate_deepseek.py при самия превод) —
несъответните блокове тук се маркират в червено.

Вход:
  ../work/<том>/translated/*.json

Изход:
  ../Output/Преглед на превода — <том>.html

Употреба:
  python3 review_html.py --vol 09
  python3 review_html.py --vol 09 --group notes_001
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
OUTPUT_DIR = os.path.join(PROJECT_DIR, "Output")

PH = re.compile(r"⟦(\d+)⟧")

CSS = """
:root { color-scheme: light dark; }
body { font: 16px/1.55 Georgia, serif; margin: 0; padding: 1.5rem;
       background: #fbfbf9; color: #1a1a1a; }
h1 { font-size: 1.3rem; margin: 0 0 .3rem; }
.meta { color: #666; font-size: .85rem; margin-bottom: 1.5rem; }
details { border: 1px solid #ddd; border-radius: 6px; margin: 0 0 .9rem;
          background: #fff; }
summary { cursor: pointer; padding: .6rem .8rem; font-size: .95rem;
          font-family: system-ui, sans-serif; }
summary b { font-weight: 600; }
summary .day { color: #777; font-weight: 400; }
table { width: 100%; border-collapse: collapse; }
td { vertical-align: top; padding: .55rem .8rem; width: 50%;
     border-top: 1px solid #eee; }
td.ru { color: #555; border-right: 1px solid #eee; }
tr.h1 td { font-weight: 700; background: #faf7f0; }
tr.bad td { background: #fff0f0; }
.ph { color: #b08; font-size: .8em; }
.no { color: #999; font-size: .75rem; font-family: system-ui, sans-serif;
      user-select: none; }
@media (prefers-color-scheme: dark) {
  body { background: #16171a; color: #e6e6e6; }
  details { background: #1e1f23; border-color: #33343a; }
  td { border-top-color: #2a2b30; } td.ru { color: #9a9a9a;
       border-right-color: #2a2b30; }
  tr.h1 td { background: #26241d; } tr.bad td { background: #331a1a; }
}
@media (max-width: 800px) { td { display: block; width: auto; }
  td.ru { border-right: 0; border-bottom: 1px dashed #ddd; } }
"""


def show(text):
    return PH.sub('<span class="ph">▪</span>', html.escape(text))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--vol", required=True)
    ap.add_argument("--group", action="append", default=[])
    args = ap.parse_args()

    vols = [os.path.basename(d) for d in glob.glob(os.path.join(WORK_DIR, "*"))
            if os.path.basename(d).startswith(args.vol + "(")]
    if not vols:
        print("Няма подготвен том %s" % args.vol)
        sys.exit(1)
    vol = vols[0]

    tdir = os.path.join(WORK_DIR, vol, "translated")
    files = sorted(glob.glob(os.path.join(tdir, "*.json")))
    if args.group:
        files = [f for f in files
                 if os.path.splitext(os.path.basename(f))[0] in args.group]
    if not files:
        print("Няма преведени групи в %s" % tdir)
        sys.exit(1)

    rows, n_blocks, n_bad = [], 0, 0
    for f in files:
        g = json.load(open(f, encoding="utf-8"))
        head = "<b>%s</b>" % html.escape(g["saint"])
        if g.get("parts", 1) > 1:
            head += " <span class='day'>(част %d от %d)</span>" % (
                g["part"], g["parts"])
        if g.get("day"):
            head += " <span class='day'>— %s</span>" % html.escape(g["day"])

        body = []
        for u in g["units"]:
            n_blocks += 1
            bad = sorted(PH.findall(u["text"])) != sorted(
                PH.findall(u["translated"]))
            n_bad += bad
            cls = " ".join(c for c in (u["kind"] if u["kind"] == "h1" else "",
                                       "bad" if bad else "") if c)
            # Блоковете от главите се номерират по реда си във файла;
            # съдържанието и текстът извън блоковете имат адрес вместо номер.
            label = (str(u["block"]) if "block" in u
                     else u.get("target", "").split(":")[-1])
            body.append(
                "<tr class='%s'><td class='ru'><span class='no'>%s</span> %s</td>"
                "<td>%s</td></tr>"
                % (cls, label, show(u["text"]), show(u["translated"])))
        rows.append("<details open><summary>%s</summary>"
                    "<table>%s</table></details>" % (head, "".join(body)))

    os.makedirs(OUTPUT_DIR, exist_ok=True)
    out = os.path.join(OUTPUT_DIR, "Преглед на превода — %s.html" % vol)
    with open(out, "w", encoding="utf-8") as fh:
        fh.write("<!doctype html><html lang='bg'><head><meta charset='utf-8'>"
                 "<meta name='viewport' content='width=device-width,initial-scale=1'>"
                 "<title>Преглед на превода — %s</title><style>%s</style></head>"
                 "<body><h1>Преглед на превода — том %s</h1>"
                 "<div class='meta'>групи: %d &middot; блокове: %d &middot; "
                 "с разминати запушалки: %d &middot; вляво руски, вдясно "
                 "български &middot; ▪ = форматиращо означение</div>%s"
                 "</body></html>"
                 % (vol, CSS, vol, len(files), n_blocks, n_bad, "".join(rows)))
    print("групи: %d | блокове: %d | с разминати запушалки: %d"
          % (len(files), n_blocks, n_bad))
    print("→ %s" % out)


if __name__ == "__main__":
    main()
