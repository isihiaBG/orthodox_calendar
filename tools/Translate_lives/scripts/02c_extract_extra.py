#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
02c_extract_extra.py — Стъпка 2в (МЕХАНИЧНА, без DeepSeek): изважда текста,
който стои ИЗВЪН блоковете, разпознавани от 02_extract.py.

02_extract.py хваща само <h1> и <div class="paragraph">. Оказа се, че това не
е целият текст: заглавната страница на всеки месец (index_split_003.xhtml)
ползва <div class="calibre9"> и оттам „по изложению святителя Димитрия,
митрополита Ростовского" и „месяц сентябрь" оставаха на руски под преведеното
заглавие. В декември има и още едно място — надписът „Примечания".

Пропускът е малък и напълно очертан: 13 файла в целия набор от 12 тома,
проверено чрез търсене на кирилица извън блоковете. Никъде другаде няма
непокрит текст.

ЗАЩО ОТДЕЛЕН СКРИПТ, а не разширяване на RE_BLOCK в 02_extract.py: блоковете
се адресират по ПОРЕДЕН НОМЕР във файла. Разширяването на израза би вмъкнало
нови блокове и би разместило номерата на всички следващи — тоест би обезсилило
всичко вече преведено. Затова тук се ползва самостоятелно адресиране:

  extra:<файл>:<N>   N-тият текстов възел с кирилица извън блоковете

Изход:
  ../work/<том>/extract/extra_text.json

Употреба:
  python3 02c_extract_extra.py --vol 09
  python3 02c_extract_extra.py --all
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

RE_BLOCK = re.compile(
    r'<h1\b[^>]*>.*?</h1>|<div class="paragraph"[^>]*>.*?</div>', re.S)
RE_BODY = re.compile(r'<body[^>]*>.*?</body>', re.S)
RE_TEXT_NODE = re.compile(r'>([^<>]+)<')
CYR = re.compile(r'[А-Яа-яЁё]')


def extra_nodes(s):
    """Текстовите възли с кирилица, които са в <body>, но ИЗВЪН блоковете.
    Връща [(начало, край, текст)] по ред в документа. Същата функция се
    ползва и при сглобяването, за да съвпадне номерацията."""
    body = RE_BODY.search(s)
    if not body:
        return []
    lo, hi = body.start(), body.end()
    blocks = [(m.start(), m.end()) for m in RE_BLOCK.finditer(s)]

    out = []
    for m in RE_TEXT_NODE.finditer(s):
        a, b = m.start(1), m.end(1)
        if a < lo or b > hi:
            continue
        if any(bs <= a < be for bs, be in blocks):
            continue
        raw = m.group(1)
        if not CYR.search(html.unescape(raw)):
            continue
        out.append((a, b, raw))
    return out


def process(vol):
    work = os.path.join(WORK_DIR, vol)
    oebps = os.path.dirname(glob.glob(os.path.join(work, "src", "**",
                                                   "content.opf"),
                                      recursive=True)[0])
    units = []
    for path in sorted(glob.glob(os.path.join(oebps, "Text", "*.xhtml"))):
        rel = "Text/" + os.path.basename(path)
        s = open(path, encoding="utf-8").read()
        for i, (_, _, raw) in enumerate(extra_nodes(s)):
            units.append({
                "target": "extra:%s:%d" % (rel, i),
                "kind": "extra",
                "text": " ".join(html.unescape(raw).split()),
                "tags": [],
            })

    if not units:
        print("  няма пропуснат текст")
        return

    group = {
        "id": "extra_text",
        "kind": "extra",
        "day": None,
        "saint": "текст извън блоковете (заглавни страници и подобни)",
        "part": 1,
        "parts": 1,
        "units": units,
        "note_refs": [],
    }
    out_dir = os.path.join(work, "extract")
    os.makedirs(out_dir, exist_ok=True)
    path = os.path.join(out_dir, "extra_text.json")
    with open(path, "w", encoding="utf-8") as f:
        json.dump(group, f, ensure_ascii=False, indent=1)

    files = sorted({u["target"].split(":")[1] for u in units})
    print("  единици: %d в %d файла (%s)"
          % (len(units), len(files), ", ".join(os.path.basename(f) for f in files)))
    for u in units:
        print("     %s" % u["text"][:70])


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--vol")
    ap.add_argument("--all", action="store_true")
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
        process(v)


if __name__ == "__main__":
    main()
