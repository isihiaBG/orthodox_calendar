#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
01d_bible_links.py — Стъпка 1г (МЕХАНИЧНА, без DeepSeek): пренасочва
препратките към Свещеното Писание към БЪЛГАРСКИ текст.

Книгите идват от azbyka.ru и всяка библейска препратка води към РУСКИ превод:

    http://azbyka.ru/biblia/?Mt.5:17&cr&rus

Опашката „&cr&rus" се заменя с „&bg~utfcs", което отваря българския текст с
успореден църковнославянски (плъзга се надясно на сайта). За книга на
български това е очевидно по-правилната цел.

Пипат се САМО препратките към /biblia/. Другите връзки към azbyka.ru — към
съчинения на светите отци и към правилата на съборите — се оставят както са;
те не са към Писанието и нямат такъв превключвател.

В разметката знакът & стои екраниран като &amp;, тъй че реалната замяна е
„&amp;cr&amp;rus" → „&amp;bg~utfcs".

Прави се върху src/, а не при сглобяването: стъпка 4 чете таговете наново от
книгата, тъй че поправката влиза в готовия .epub без нищо да се превежда
повторно.

Вход:
  ../work/<том>/src/

Изход:
  същите файлове, поправени на място

Употреба:
  python3 01d_bible_links.py --all --dry-run
  python3 01d_bible_links.py --all
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

OLD_TAIL = "&amp;cr&amp;rus"
NEW_TAIL = "&amp;bg~utfcs"

# Само href към /biblia/. Другите azbyka връзки не се докосват.
RE_BIBLE = re.compile(r'href="([^"]*azbyka\.ru/biblia/[^"]*)"')
RE_TAG = re.compile(r"<[^>]+>")
RE_PARA = re.compile(r'<div class="paragraph"')


def process(vol, dry):
    src = os.path.join(WORK_DIR, vol, "src")
    oebps = os.path.dirname(glob.glob(os.path.join(src, "**", "content.opf"),
                                      recursive=True)[0])
    changed = already = other = 0
    files = 0

    for path in sorted(glob.glob(os.path.join(oebps, "Text", "*.xhtml"))):
        s = open(path, encoding="utf-8").read()
        before_text = " ".join(html.unescape(RE_TAG.sub(" ", s)).split())
        before_paras = len(RE_PARA.findall(s))

        def repl(m):
            nonlocal changed, already, other
            href = m.group(1)
            if NEW_TAIL in href:
                already += 1
                return m.group(0)
            changed += 1
            if OLD_TAIL in href:
                return 'href="%s"' % href.replace(OLD_TAIL, NEW_TAIL)
            # Библейска препратка БЕЗ опашка (в октомври има една такава —
            # „?Jac.1", сочи към цяла глава). Проверено на живо: добавянето
            # на &bg~utfcs работи и там.
            other += 1
            return 'href="%s%s"' % (href, NEW_TAIL)

        new = RE_BIBLE.sub(repl, s)
        if new == s:
            continue

        # Пипнат е само атрибут — текстът и блоковете трябва да са същите.
        if " ".join(html.unescape(RE_TAG.sub(" ", new)).split()) != before_text:
            print("  ✗ променен видим текст: %s" % os.path.basename(path))
            return
        if len(RE_PARA.findall(new)) != before_paras:
            print("  ✗ променен брой параграфи: %s" % os.path.basename(path))
            return

        files += 1
        if not dry:
            with open(path, "w", encoding="utf-8") as f:
                f.write(new)

    print("  библейски препратки: пренасочени %d | вече наред %d | "
          "добавена опашка %d | пипнати файлове %d"
          % (changed, already, other, files))
    if dry:
        return

    # --- проверка: не е ли останала руска опашка и не сме ли пипнали друго ---
    left = nonbible = 0
    for path in glob.glob(os.path.join(oebps, "Text", "*.xhtml")):
        s = open(path, encoding="utf-8").read()
        for href in RE_BIBLE.findall(s):
            if OLD_TAIL in href:
                left += 1
        for href in re.findall(r'href="([^"]*azbyka\.ru[^"]*)"', s):
            if "/biblia/" not in href and NEW_TAIL in href:
                nonbible += 1
    print("  проверка: останали с &cr&rus %d | небиблейски, пипнати по грешка %d"
          % (left, nonbible))


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
