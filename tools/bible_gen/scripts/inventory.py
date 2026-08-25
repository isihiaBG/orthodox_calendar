#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
inventory.py — Какво изобщо има вътре в стиховете. Диагностика, не стъпка.

Обхожда суровите страници в cache/ и брои ВСЕКИ таг, ВСЕКИ клас и ВСЕКИ
атрибут, срещнат вътре в `<div class="verse">`. За всеки дава колко пъти се
среща, в кои преводи и един истински пример.

Смисълът: да НЕ се гадае какво носи маркировката. Разглобяването може да
пази само онова, за което знае — а капаните в този източник са точно от
вида „съдържание, което изглежда като текст, но не е" (виж README). Описът
е начинът да се види целият списък наведнъж, вместо да изплува по едно на
всеки няколко месеца.

Пуска се по всяко време — и по средата на тегленето, и след него. НЕ пипа
мрежата и не пише нищо освен отчета.

Употреба:
    python3 inventory.py                 # всичко в cache/
    python3 inventory.py --langs r,sb
    python3 inventory.py --attrs         # и атрибутите, не само таговете
    python3 inventory.py --tag span.cyn  # всички примери за едно нещо
"""

import argparse
import collections
import html
import os
import re
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.dirname(SCRIPT_DIR)
CACHE_DIR = os.path.join(PROJECT_DIR, "cache")

RE_VERSE = re.compile(
    r'<div\s+[^>]*?data-lang="(?P<lang>[^"]*)"'
    r'[^>]*?data-verse="(?P<verse>[^"]*)"'
    r'[^>]*?>(?P<body>.*?)</div>',
    re.S,
)
RE_CHECKBOX = re.compile(r'<span class="icon-check checkbox"></span>')
RE_TAG = re.compile(r"<(?P<close>/?)(?P<name>[a-zA-Z0-9]+)(?P<attrs>[^>]*)>")
RE_ATTR = re.compile(r'([a-zA-Z_:][-a-zA-Z0-9_:.]*)\s*=\s*"([^"]*)"')
RE_ENTITY = re.compile(r"&(#\d+|#x[0-9a-fA-F]+|[a-zA-Z]+);")


def snippet(body, around, width=150):
    """Къс откъс около съвпадението, за да се вижда в какъв контекст стои."""
    start = max(0, around - width // 3)
    text = re.sub(r"\s+", " ", body[start:start + width])
    return ("…" if start else "") + text.strip() + "…"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--langs", default="")
    ap.add_argument("--attrs", action="store_true",
                    help="показва и кои атрибути носи всеки таг")
    ap.add_argument("--tag", default="",
                    help="всички примери за едно нещо, напр. span.cyn")
    ap.add_argument("--examples", type=int, default=1)
    args = ap.parse_args()

    if not os.path.isdir(CACHE_DIR):
        sys.exit("Няма cache/. Пусни първо 02_fetch_chapters.py.")

    langs = [c.strip() for c in args.langs.split(",") if c.strip()]
    if not langs:
        langs = sorted(d for d in os.listdir(CACHE_DIR)
                       if os.path.isdir(os.path.join(CACHE_DIR, d))
                       and not d.startswith("_"))

    counts = collections.Counter()
    by_lang = collections.defaultdict(set)
    examples = collections.defaultdict(list)
    attrs_of = collections.defaultdict(collections.Counter)
    entities = collections.Counter()
    n_verses = n_chapters = 0

    for lang in langs:
        lang_dir = os.path.join(CACHE_DIR, lang)
        if not os.path.isdir(lang_dir):
            continue
        for fname in sorted(os.listdir(lang_dir)):
            if not fname.endswith(".html"):
                continue
            n_chapters += 1
            with open(os.path.join(lang_dir, fname), encoding="utf-8") as fh:
                page = fh.read()

            for m in RE_VERSE.finditer(page):
                if ":" not in m.group("verse"):
                    continue
                body = RE_CHECKBOX.sub("", m.group("body"))
                n_verses += 1

                for em in RE_ENTITY.finditer(body):
                    entities[em.group(0)] += 1

                for tm in RE_TAG.finditer(body):
                    if tm.group("close"):
                        continue
                    name = tm.group("name").lower()
                    raw_attrs = tm.group("attrs") or ""
                    attrs = dict(RE_ATTR.findall(raw_attrs))
                    cls = attrs.get("class", "").split()
                    key = f"{name}.{cls[0]}" if cls else name

                    counts[key] += 1
                    by_lang[key].add(lang)
                    for attr_name in attrs:
                        attrs_of[key][attr_name] += 1
                    if len(examples[key]) < max(args.examples, 1):
                        examples[key].append(
                            (lang, m.group("verse"), snippet(body, tm.start())))

    if args.tag:
        key = args.tag
        print(f"{key}: {counts.get(key, 0)} срещания в {sorted(by_lang.get(key, []))}")
        for lang, verse, text in examples.get(key, []):
            print(f"  {lang} {verse}: {html.unescape(text)}")
        return

    print(f"прегледани: {n_chapters} глави, {n_verses} стиха, "
          f"преводи {', '.join(langs)}")
    print()
    print(f"{'таг / клас':<28} {'брой':>8}  преводи")
    print("─" * 78)
    for key, n in counts.most_common():
        langs_str = ", ".join(sorted(by_lang[key]))
        if len(langs_str) > 34:
            langs_str = langs_str[:31] + "…"
        print(f"{key:<28} {n:>8}  {langs_str}")
        if args.attrs and attrs_of[key]:
            shown = ", ".join(f"{a}×{c}" for a, c in attrs_of[key].most_common())
            print(f"{'':<28} {'':>8}  атрибути: {shown}")
        for lang, verse, text in examples[key]:
            print(f"{'':<28} {'':>8}  напр. {lang} {verse}: "
                  f"{html.unescape(text)[:120]}")

    if entities:
        print()
        print("HTML същности в текста:")
        for ent, n in entities.most_common(15):
            print(f"  {ent:<12} ×{n}")


if __name__ == "__main__":
    main()
