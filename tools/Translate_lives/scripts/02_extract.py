#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
02_extract.py — Стъпка 2 (МЕХАНИЧНА, без DeepSeek): изважда преводимия текст
от подготвения том и го групира ПО СВЕТИЯ според toc.ncx.

Основното решение тук: моделът НЕ вижда markup изобщо. Вместо да му подаваме
xhtml и да се надяваме да не пипне таговете (както правеше старият скрипт за
житията от azbyka.ru), разглобяваме всеки блок на чист текст + номерирани
запушалки на мястото на вътрешните тагове:

    Отечеством святого Иосифа была Сицилия⟦1⟧⟦2⟧2377⟦3⟧⟦4⟧. Родители его...

където ⟦1⟧ е <a href="...">, ⟦2⟧ е <sup class="calibre8"> и т.н. Така
таговете са физически недостижими, а моделът пак вижда ЦЯЛОТО изречение —
което е важно, защото разделянето по текстови възли би му дало парчета от
изречения и преводът щеше да загрубее.

Единица за превод е БЛОК (един <h1> или един <div class="paragraph">), а не
текстов възел и не цял файл. Блокът е и единицата, на която стъпва CSS-ът:
буквицата виси на реда на div-овете, затова броят и редът на блоковете
задължително остават непокътнати — оттам и проверката в стъпка 4.

Бележките под линия се превеждат ВЕДНЪЖ, макар текстът им да стои на две
места в книгата (в notes.xhtml и в title="..." атрибута на всяка препратка
към тях). За септември те съвпадат и на 773 от 773 места — виж
notes_map.json. Стъпка 4 попълва и двете места от един и същ превод, тъй
че ~четвърт от обема отпада и изскачащото описание не може да се разминае
със самата бележка.

Вход:
  ../work/<том>/src/           (от 01_merge_notes.py)
  ../work/<том>/notes_map.json

Изход:
  ../work/<том>/extract/<група>.json   по един файл на светия + бележките
  ../work/<том>/groups.json            обобщение (за преглед и за стъпка 3)

Употреба:
  python3 02_extract.py --vol 09
  python3 02_extract.py --vol 09 --stats     # само сметките, без запис
"""

import argparse
import glob
import html
import json
import os
import re
import sys
import xml.etree.ElementTree as ET

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.dirname(SCRIPT_DIR)
WORK_DIR = os.path.join(PROJECT_DIR, "work")

NCX_NS = {"n": "http://www.daisy.org/z3986/2005/ncx/"}

# Блоковете, които носят преводим текст. Редът в регулярния израз няма
# значение — намираме ги в реда, в който се срещат във файла.
RE_BLOCK = re.compile(
    r'<h1\b[^>]*>.*?</h1>|<div class="paragraph"[^>]*>.*?</div>', re.S)
RE_INNER_H1 = re.compile(r'^<h1\b[^>]*>(.*)</h1>$', re.S)
RE_INNER_DIV = re.compile(r'^<div class="paragraph"[^>]*>(.*)</div>$', re.S)
RE_TAG = re.compile(r'<[^>]+>')
RE_NOTE_REF = re.compile(r'href="[^"]*#(note\d+)"\s+title="([^"]*)"')

# Блок, чийто видим текст е само число/пунктуация, няма какво да се превежда
# (такива са <h1> заглавията на бележките — те са просто номера).
RE_NOTHING_TO_TRANSLATE = re.compile(r'^[\d\s\.,;:!?()\[\]«»—–\-]*$')

PH_OPEN, PH_CLOSE = "⟦", "⟧"          # ⟦ ⟧


def placeholderize(inner):
    """Заменя всеки таг с ⟦N⟧ и връща (текст със запушалки, списък тагове)."""
    tags = []

    def repl(m):
        tags.append(m.group(0))
        return "%s%d%s" % (PH_OPEN, len(tags), PH_CLOSE)

    return RE_TAG.sub(repl, inner), tags


def visible(inner):
    return " ".join(html.unescape(RE_TAG.sub("", inner)).split())


def load_toc(oebps):
    """Връща [(ден, светия, файл)] за листата на съдържанието."""
    root = ET.parse(os.path.join(oebps, "toc.ncx")).getroot()
    out, day = [], None
    for np in root.find("n:navMap", NCX_NS).findall("n:navPoint", NCX_NS):
        label = np.find("n:navLabel/n:text", NCX_NS).text
        src = np.find("n:content", NCX_NS).get("src").split("#")[0]
        kids = np.findall("n:navPoint", NCX_NS)
        if not kids:
            # Ден без деца (или заглавната страница на месеца) — сам си е група.
            out.append((label, label, src))
            continue
        day = label
        for kid in kids:
            out.append((day,
                        kid.find("n:navLabel/n:text", NCX_NS).text,
                        kid.find("n:content", NCX_NS).get("src").split("#")[0]))
    return out


def extract_file(oebps, rel_path, skip_note_headings=False):
    """Блоковете на един файл → списък единици за превод."""
    path = os.path.join(oebps, rel_path)
    s = open(path, encoding="utf-8").read()
    units = []
    for idx, m in enumerate(RE_BLOCK.finditer(s)):
        block = m.group(0)
        im = RE_INNER_H1.match(block) or RE_INNER_DIV.match(block)
        inner = im.group(1) if im else block
        if RE_NOTHING_TO_TRANSLATE.match(visible(inner)):
            continue
        text, tags = placeholderize(inner)
        units.append({
            "file": rel_path,
            "block": idx,
            "kind": "h1" if block.startswith("<h1") else "p",
            "text": text.strip(),
            "tags": tags,
        })
    return units


def note_refs(oebps, rel_path):
    """noteID-тата, чиито title= атрибути ще се попълнят от превода на
    самата бележка (не се превеждат отделно)."""
    s = open(os.path.join(oebps, rel_path), encoding="utf-8").read()
    return sorted({nid for nid, _ in RE_NOTE_REF.findall(s)})


def chunk_units(units, max_chars):
    """Реже списък блокове на части до max_chars. Срезът е ВИНАГИ между
    блокове, никога вътре в блок — иначе моделът би получил половин
    изречение, а и сглобяването в стъпка 4 стъпва на цели блокове.

    Голям блок сам по себе си може да надхвърли тавана; тогава си остава
    сам в своята част, вместо да бъде разсечен."""
    out, cur, size = [], [], 0
    for u in units:
        n = len(u["text"])
        if cur and size + n > max_chars:
            out.append(cur)
            cur, size = [], 0
        cur.append(u)
        size += n
    if cur:
        out.append(cur)
    return out


def process(vol, max_chars, stats_only):
    work = os.path.join(WORK_DIR, vol)
    src = os.path.join(work, "src")
    if not os.path.isdir(src):
        print("Няма %s — пусни 01_merge_notes.py --vol %s първо."
              % (src, vol.split("(")[0]))
        sys.exit(1)
    oebps = os.path.dirname(glob.glob(os.path.join(src, "**", "content.opf"),
                                      recursive=True)[0])
    out_dir = os.path.join(work, "extract")

    groups = []

    # --- жития, по светия според toc.ncx ---
    seen = set()
    for i, (day, saint, rel) in enumerate(load_toc(oebps), 1):
        if rel in seen:
            continue                      # ден и първият му светия сочат един файл
        seen.add(rel)
        units = extract_file(oebps, rel)
        if not units:
            continue
        base = "%03d_%s" % (i, os.path.splitext(os.path.basename(rel))[0])
        refs = note_refs(oebps, rel)
        # Дългите жития се режат на части. Частите пак са „по светия" — само
        # че на няколко заявки, защото едно житие стига до 99 хиляди символа,
        # а толкова не се събира в един отговор. Частите се превеждат ПО РЕД
        # (виж part/parts) — стъпка 3 подава името на светеца от част 1 като
        # контекст на следващите, за да не се разиграе в различни варианти.
        parts = chunk_units(units, max_chars)
        for k, chunk in enumerate(parts, 1):
            groups.append({
                "id": base if len(parts) == 1 else "%s_p%02d" % (base, k),
                "kind": "life",
                "day": day,
                "saint": saint,
                "part": k,
                "parts": len(parts),
                "units": chunk,
                "note_refs": refs if k == 1 else [],
            })

    # --- бележките, на парчета ---
    notes_rel = "Text/notes.xhtml"
    if os.path.exists(os.path.join(oebps, notes_rel)):
        nunits = extract_file(oebps, notes_rel)
        chunks = chunk_units(nunits, max_chars)
        for j, chunk in enumerate(chunks, 1):
            groups.append({
                "id": "notes_%03d" % j,
                "kind": "notes",
                "day": None,
                "saint": "бележки под линия (част %d)" % j,
                "part": j,
                "parts": len(chunks),
                "units": chunk,
                "note_refs": [],
            })

    # --- сметки ---
    n_units = sum(len(g["units"]) for g in groups)
    n_chars = sum(len(u["text"]) for g in groups for u in g["units"])
    lives = [g for g in groups if g["kind"] == "life"]
    notes = [g for g in groups if g["kind"] == "notes"]
    life_chars = sum(len(u["text"]) for g in lives for u in g["units"])
    note_chars = sum(len(u["text"]) for g in notes for u in g["units"])

    saints = {(g["day"], g["saint"]) for g in lives}
    sizes = sorted(sum(len(u["text"]) for u in g["units"]) for g in groups)

    print("=" * 64)
    print("Том: %s" % vol)
    print("  светии: %d → заявки: %d  (жития: %d | бележки: %d)"
          % (len(saints), len(groups), len(lives), len(notes)))
    print("  блокове за превод: %d" % n_units)
    print("  символи: %d  (жития: %d | бележки: %d)"
          % (n_chars, life_chars, note_chars))
    print("  заявка: най-малка %d | медиана %d | най-голяма %d символа"
          % (sizes[0], sizes[len(sizes) // 2], sizes[-1]))
    split = sum(1 for g in lives if g["parts"] > 1 and g["part"] == 1)
    print("  жития, разрязани на части: %d" % split)
    dup = sum(len(g["note_refs"]) for g in lives)
    print("  препратки към бележки, които НЕ се превеждат отделно: %d" % dup)

    if stats_only:
        return

    if os.path.isdir(out_dir):
        for f in glob.glob(os.path.join(out_dir, "*.json")):
            os.remove(f)
    os.makedirs(out_dir, exist_ok=True)
    for g in groups:
        with open(os.path.join(out_dir, g["id"] + ".json"), "w",
                  encoding="utf-8") as f:
            json.dump(g, f, ensure_ascii=False, indent=1)

    summary = [{k: g[k] for k in ("id", "kind", "day", "saint", "part", "parts")} |
               {"units": len(g["units"]),
                "chars": sum(len(u["text"]) for u in g["units"])}
               for g in groups]
    with open(os.path.join(work, "groups.json"), "w", encoding="utf-8") as f:
        json.dump(summary, f, ensure_ascii=False, indent=1)
    print("  → %s" % out_dir)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--vol", required=True, help="номер на том, напр. 09")
    ap.add_argument("--max-chars", type=int, default=6000,
                    help="таван на една група с бележки (по подразбиране 6000)")
    ap.add_argument("--stats", action="store_true",
                    help="само сметките, без да пише файлове")
    args = ap.parse_args()

    vols = [os.path.basename(d) for d in glob.glob(os.path.join(WORK_DIR, "*"))
            if os.path.basename(d).startswith(args.vol + "(")]
    if not vols:
        print("Няма подготвен том %s в %s" % (args.vol, WORK_DIR))
        sys.exit(1)
    for v in vols:
        process(v, args.max_chars, args.stats)


if __name__ == "__main__":
    main()
