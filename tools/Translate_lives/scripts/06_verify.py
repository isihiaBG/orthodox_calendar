#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
06_verify.py — Проверява готовите .epub файлове в ../Output/.

Не поправя нищо и не пипа нищо — само гледа. Съществува, защото накрая
трябва да се минат 12 книги, а еднократните команди на ръка вече два пъти
показаха, че лъжат: веднъж заради работната папка, веднъж заради &nbsp;.

За &nbsp; специално: файловете носят DOCTYPE на XHTML 1.1, който ГО
ДЕФИНИРА, но обикновен XML разбор не изтегля DTD-то и го обявява за
неизвестен обект. Затова преди разбора петте предефинирани обекта плюс
&nbsp; се обявяват наум — иначе всяка книга би отчитала фалшива грешка на
заглавната си страница. Оригиналните руски книги съдържат същото.

Употреба:
  python3 06_verify.py
  python3 06_verify.py --file "Output/... .epub"
"""

import argparse
import glob
import html
import os
import re
import sys
import xml.etree.ElementTree as ET
import zipfile

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.dirname(SCRIPT_DIR)
OUTPUT_DIR = os.path.join(PROJECT_DIR, "Output")

RE_TAG = re.compile(r"<[^>]+>")
RE_DOCTYPE = re.compile(r"<!DOCTYPE[^>]*>", re.S)
PH = re.compile(r"⟦")

# Църковнославянски думи, за които присъствието на ы/э е ПРАВИЛНО.
# Решено при редакционния преглед, виж „За редакция — руски букви.txt".
SLAVONIC = {"чистоты", "вселенны", "взыде", "вдыхаяй", "изыдите"}


def parses(data):
    """Разбор без DTD: махаме DOCTYPE и подаваме &nbsp; наум."""
    s = data.decode("utf-8", "replace")
    s = RE_DOCTYPE.sub("", s, count=1)
    s = s.replace("&nbsp;", "&#160;")
    try:
        ET.fromstring(s)
        return True
    except ET.ParseError:
        return False


def check(path):
    fails = []
    def want(cond, label):
        print("  %s %s" % ("✓" if cond else "✗", label))
        if not cond:
            fails.append(label)

    z = zipfile.ZipFile(path)
    names = z.namelist()
    nameset = set(names)
    opf_name = next(n for n in names if n.endswith("content.opf"))
    opf = z.read(opf_name).decode()
    oebps = os.path.dirname(opf_name)
    xhtml = [n for n in names if n.endswith(".xhtml")]

    print("\n%s  (%.1f MB, %d файла)"
          % (os.path.basename(path), os.path.getsize(path) / 1e6, len(names)))

    ver = re.search(r'<package[^>]*?version="([\d.]+)"', opf).group(1)
    want(ver == "2.0", "EPUB 2.0 (а не 3) — за стари устройства: %s" % ver)
    want(names[0] == "mimetype"
         and z.getinfo("mimetype").compress_type == zipfile.ZIP_STORED,
         "mimetype е пръв и некомпресиран")
    want(z.testzip() is None, "архивът е здрав")
    want(all(parses(z.read(n)) for n in xhtml + [opf_name]),
         "всички файлове се разбират като XML")

    lang = re.search(r"<dc:language[^>]*>([^<]*)</dc:language>", opf)
    want(lang and lang.group(1) == "bg", "език bg")

    ncx = [n for n in names if n.endswith(".ncx")]
    labels = []
    if ncx:
        labels = [html.unescape(x) for x in
                  re.findall(r"<text>(.*?)</text>", z.read(ncx[0]).decode(), re.S)]
    bad_lbl = [l for l in labels if re.search(r"[ыэё]", l)]
    want(labels and not bad_lbl,
         "съдържанието е преведено (%d надписа, %d с руски следи)"
         % (len(labels), len(bad_lbl)))

    # Руски букви в български текст. Изключение правят църковнославянските
    # цитати, предадени умишлено на славянски („взыде вдыхаяй в лице твое“,
    # „чистоты, вселенны светилниче“, „Елици оглашеннии, изыдите“) — там ы е
    # НА МЯСТО и не е пропуск в превода. Списъкът е затворен и решен от
    # човек при прегледа; всичко извън него е грешка.
    body = "".join(RE_TAG.sub(" ", z.read(n).decode("utf-8", "replace"))
                   for n in xhtml)
    stray = [w for w in re.findall(r"\S*[ыэё]\S*", body)
             if w.strip(".,;:!?()«»„“") not in SLAVONIC]
    want(not stray, "няма неволно останали руски думи (славянски цитати: %d)"
         % (len(re.findall(r"\S*[ыэё]\S*", body)) - len(stray)))
    if stray:
        print("      %s" % ", ".join(sorted(set(stray))[:6]))
    want(not PH.search(body), "няма блуждаещи запушалки ⟦⟧")

    man = {h for h, _ in re.findall(r'<item href="([^"]+)" id="([^"]+)"', opf)
           if h.endswith(".xhtml")}
    disk = {n[len(oebps) + 1:] for n in xhtml}
    want(man == disk, "манифестът съвпада с диска (%d файла)" % len(disk))

    spine = set(re.findall(r'<itemref idref="([^"]+)"', opf))
    mids = {i for h, i in re.findall(r'<item href="([^"]+)" id="([^"]+)"', opf)
            if h.endswith(".xhtml")}
    want(not mids - spine, "всичко е в реда на четене (извън: %d)"
         % len(mids - spine))

    broken = 0
    for n in xhtml:
        for _, nid in re.findall(r'href="([^"]*)#(note\d+)"',
                                 z.read(n).decode("utf-8", "replace")):
            tgt = "%s/Text/%s.xhtml" % (oebps, nid)
            if tgt not in nameset:
                broken += 1
    notes = [n for n in xhtml if re.search(r"/note\d+\.xhtml$", n)]
    want(broken == 0, "препратки към бележки: %d файла, счупени %d"
         % (len(notes), broken))

    # ⚠ ВИДИМИЯТ номер на бележката трябва да е ТОЧНО номерът от адреса.
    # Машинният превод понякога го изпуска, преиначава („1367 г.", „на 3091",
    # „(бележка под линия)") или слага на мястото му измислена фраза — а
    # сглобяването честно я слага в горния индекс. Проверката по-горе гледа
    # само дали препратката СОЧИ някъде. (Открито от потребителя, 08.10.2026:
    # 14 такива от 8922.)
    wrong = []
    for n in xhtml:
        if re.search(r"/note\d+\.xhtml$", n):
            continue
        for num, inner in re.findall(
                r'<a href="[^"]*note(\d+)\.xhtml#note\d+"[^>]*>(.*?)</a>',
                z.read(n).decode("utf-8", "replace"), re.S):
            if RE_TAG.sub("", inner).strip() != num or "<sup" not in inner:
                wrong.append("%s:%s" % (n.split("/")[-1], num))
    want(not wrong, "видимият номер на всяка бележка съвпада с адреса (грешни: %d)"
         % len(wrong))
    if wrong:
        print("      %s" % ", ".join(wrong[:6]))

    # ⚠ Дума със СМЕСЕНИ букви — латинско „e"/„o"/„a" насред кирилска дума
    # („старeца" — 61 пъти), или изобщо чужда дума („samtidigt"). Изглеждат
    # нормално, но не се намират при търсене. Машинният превод ги ражда.
    # (Открито 09.10.2026 — 123 блока в 12-те тома.) Римските цифри трябва да
    # са ИЗЦЯЛО латински — „ІV" с кирилско І също се хваща.
    raw = "".join(z.read(n).decode("utf-8", "replace") for n in xhtml)
    mixed = sorted({w for w in re.findall(r"[A-Za-zА-Яа-яЀ-ӿ]+", raw)
                    if re.search(r"[A-Za-z]", w) and re.search(r"[А-Яа-яЀ-ӿ]", w)})
    want(not mixed, "няма думи със смесени кирилски и латински букви (%d)"
         % len(mixed))
    if mixed:
        print("      %s" % ", ".join(mixed[:8]))

    fonts = sorted(n.split("/")[-1] for n in names if "/Fonts/" in n)
    want("CharisSIL-Regular.ttf" in fonts and "CharisSIL-Italic.ttf" in fonts,
         "шрифтове: %s" % ", ".join(fonts))
    # Лицензът трябва да пътува с шрифта — виж коментара при LICENSE_FILE
    # в 04_build_epub.py.
    want("OFL-CharisSIL.txt" in fonts, "лиценз на шрифта в тома")
    return fails


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--file")
    args = ap.parse_args()

    files = ([args.file] if args.file
             else sorted(glob.glob(os.path.join(OUTPUT_DIR, "*.epub"))))
    if not files:
        print("Няма .epub файлове в %s" % OUTPUT_DIR)
        sys.exit(1)

    total = 0
    for f in files:
        total += len(check(f))
    print("\n" + "=" * 60)
    print("книги: %d | неминали проверки: %d" % (len(files), total))
    sys.exit(1 if total else 0)


if __name__ == "__main__":
    main()
