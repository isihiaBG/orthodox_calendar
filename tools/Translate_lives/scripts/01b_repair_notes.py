#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
01b_repair_notes.py — Стъпка 1б (МЕХАНИЧНА, без DeepSeek): възстановява
бележки, които липсват в разцепените томове.

Как се е получила повредата: 12-те тома са нарязани от една обща книга
(„Жития святых - Димитрий Ростовский.epub" в Input/, без номер на месец).
При нарязването блокът файлове index_split_7335–7394 — това са бележки
6177–6236, 60 непрекъснати броя — е останал в номерацията на СЕПТЕМВРИ, но
се реферира от ОКТОМВРИ. В септемврийския том тези файлове ги няма (стоят
само като празни записи в манифеста), а октомврийският сочи към тях в
празното. Декември има един отделен случай — note8926.

Затова ремонтът черпи от НЕРАЗЦЕПЕНАТА книга: там бележките са цели, с
вътрешните си препратки (към библейски стихове и др.). Това е по-добро от
другия възможен източник — текста в title="..." атрибута на препратката —
защото title е чист текст и вътрешните тагове в него са изгубени. Той се
ползва само като резерва, ако бележката липсва и в общата книга.

Каквото не се намери никъде, се докладва и се оставя както си е. Нищо не
се измисля.

Вход:
  ../work/<том>/src/                        (след 01_merge_notes.py)
  ../Input/Жития святых - Димитрий Ростовский.epub

Изход:
  същият notes.xhtml, допълнен на място

Употреба:
  python3 01b_repair_notes.py --vol 10
  python3 01b_repair_notes.py --all
"""

import argparse
import glob
import html
import json
import os
import re
import sys
import zipfile

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.dirname(SCRIPT_DIR)
WORK_DIR = os.path.join(PROJECT_DIR, "work")
INPUT_DIR = os.path.join(PROJECT_DIR, "Input")
SOURCE_CACHE = os.path.join(WORK_DIR, "_source")

RE_NOTE_BLOCK = re.compile(r'<div class="note">\n(.*?)\n</div>', re.S)


def note_blocks(src):
    """Съдържанието на всяка обвивка <div class="note">.

    НЕ с нежаден израз до първото „\\n</div>“: самата бележка може да съдържа
    такова място. В декември note8129 има три параграфа и затварящият таг на
    последния стои на СОБСТВЕН ред — нежадният израз спира там, отрязва един
    </div> и файлът излиза с несдвоени тагове. Точно това повреди
    12(дек)/src/OEBPS/Text/notes.xhtml при първото пускане.

    Затова режем по началния маркер (него го слагаме ние в 01_merge_notes.py,
    еднозначен е) и махаме последния </div> отзад."""
    body = re.search(r"<body[^>]*>(.*)</body>", src, re.S)
    if not body:
        return []
    out = []
    for chunk in body.group(1).split('<div class="note">\n')[1:]:
        inner = chunk.rstrip()
        if inner.endswith("</div>"):
            inner = inner[: -len("</div>")].rstrip("\n")
        out.append(inner)
    return out
RE_BODY_RW = re.compile(r'(<body[^>]*>\n)(.*)(\n</body>)', re.S)
RE_BODY = re.compile(r'<body[^>]*>(.*)</body>', re.S)

TPL_PLAIN = ('<h1 id="%s" class="calibre9">\n%s <br class="calibre10"/></h1>\n'
             '<div class="paragraph">%s</div>')


def esc(t):
    return t.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def load_manual():
    """Ръчно набавени бележки (manual_notes.json) — последен източник, за
    случаите, в които бележката липсва и в общата книга. Ключовете, които
    започват с долна черта или не приличат на noteNNNN, са коментари."""
    path = os.path.join(SCRIPT_DIR, "manual_notes.json")
    if not os.path.exists(path):
        return {}
    data = json.load(open(path, encoding="utf-8"))
    return {k: v for k, v in data.items()
            if re.fullmatch(r"note\d+", k) and isinstance(v, dict) and v.get("text")}


def unpack_source():
    """Разопакова общата книга веднъж и я държи в work/_source/."""
    cands = [e for e in glob.glob(os.path.join(INPUT_DIR, "*.epub"))
             if not re.search(r"- \d+\(", os.path.basename(e))]
    if not cands:
        return None
    if not os.path.isdir(SOURCE_CACHE):
        print("  разопаковам общата книга (еднократно)...")
        os.makedirs(SOURCE_CACHE)
        with zipfile.ZipFile(cands[0]) as z:
            z.extractall(SOURCE_CACHE)
    return SOURCE_CACHE


def index_source(root):
    """noteID → тялото на бележката, както е в общата книга (с таговете)."""
    idx = {}
    for p in glob.glob(os.path.join(root, "**", "*.xhtml"), recursive=True):
        s = open(p, encoding="utf-8", errors="replace").read()
        m = re.search(r'<h1[^>]*id="(note\d+)"', s)
        if not m:
            continue
        body = RE_BODY.search(s)
        if body:
            idx[m.group(1)] = body.group(1).strip("\n")
    return idx


def repair(vol, source_idx):
    src = os.path.join(WORK_DIR, vol, "src")
    oebps = os.path.dirname(glob.glob(os.path.join(src, "**", "content.opf"),
                                      recursive=True)[0])
    notes_path = os.path.join(oebps, "Text", "notes.xhtml")
    if not os.path.exists(notes_path):
        print("  няма notes.xhtml — пусни 01_merge_notes.py първо")
        return

    notes_src = open(notes_path, encoding="utf-8").read()
    have = set(re.findall(r'<h1[^>]*id="(note\d+)"', notes_src))

    wanted, from_title = set(), {}
    for p in glob.glob(os.path.join(oebps, "Text", "*.xhtml")):
        if p == notes_path:
            continue
        s = open(p, encoding="utf-8").read()
        wanted |= set(re.findall(r'href="[^"]*#(note\d+)"', s))
        for nid, ttl in re.findall(r'href="[^"]*#(note\d+)"\s+title="([^"]*)"', s):
            t = " ".join(html.unescape(ttl).split())
            if t:
                from_title.setdefault(nid, t)

    missing = sorted(wanted - have, key=lambda x: int(x[4:]))
    if not missing:
        print("  няма липсващи бележки")
        return

    manual = load_manual()
    new_blocks, src_n, ttl_n, man_n, lost = [], 0, 0, 0, []
    for nid in missing:
        # Редът е по надеждност: общата книга (пълна разметка) → title
        # (текст без вътрешните връзки) → ръчно набавена.
        if nid in source_idx:
            new_blocks.append((int(nid[4:]), source_idx[nid]))
            src_n += 1
        elif from_title.get(nid):
            new_blocks.append((int(nid[4:]),
                               TPL_PLAIN % (nid, nid[4:], esc(from_title[nid]))))
            ttl_n += 1
        elif manual.get(nid):
            new_blocks.append((int(nid[4:]),
                               TPL_PLAIN % (nid, nid[4:],
                                            esc(manual[nid]["text"]))))
            man_n += 1
        else:
            lost.append(nid)

    print("  липсващи: %d | от общата книга: %d | от title (без вътрешни "
          "връзки): %d | ръчно набавени: %d | невъзстановими: %d %s"
          % (len(missing), src_n, ttl_n, man_n, len(lost), lost or ""))
    if not new_blocks:
        return

    keyed = [(int(re.search(r'<h1[^>]*id="note(\d+)"', b).group(1)), b)
             for b in note_blocks(notes_src)]
    keyed += new_blocks
    keyed.sort(key=lambda x: x[0])

    body = "\n".join('<div class="note">\n%s\n</div>' % b for _, b in keyed)
    out = RE_BODY_RW.sub(lambda m: m.group(1) + body + m.group(3), notes_src)
    with open(notes_path, "w", encoding="utf-8") as f:
        f.write(out)

    after = open(notes_path, encoding="utf-8").read()
    ids = set(re.findall(r'<h1[^>]*id="(note\d+)"', after))
    nums = [int(x) for x in re.findall(r'<h1[^>]*id="note(\d+)"', after)]
    still = sorted(wanted - ids, key=lambda x: int(x[4:]))
    # Всяка бележка трябва да е сама в обвивката си — иначе .paragraph
    # излиза на грешна позиция и буквицата се закача на бележка.
    blocks = note_blocks(after)
    multi = sum(1 for b in blocks if len(re.findall(r'<h1', b)) != 1)
    print("  бележки: %d (бяха %d) | подредени: %s | обвивки с != 1 бележка: %d"
          % (len(ids), len(have), "да" if nums == sorted(nums) else "НЕ", multi))
    print("  все още висящи: %d %s" % (len(still), still or ""))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--vol")
    ap.add_argument("--all", action="store_true")
    args = ap.parse_args()

    vols = sorted(os.path.basename(d) for d in glob.glob(os.path.join(WORK_DIR, "*"))
                  if os.path.isdir(os.path.join(d, "src")))
    if args.vol:
        vols = [v for v in vols if v.startswith(args.vol + "(")]
    elif not args.all:
        print("Подай --vol NN или --all")
        sys.exit(1)

    root = unpack_source()
    if not root:
        print("Няма обща книга в %s — ремонтът ще ползва само title." % INPUT_DIR)
        source_idx = {}
    else:
        source_idx = index_source(root)
        print("бележки в общата книга: %d" % len(source_idx))

    for v in vols:
        print("=" * 64)
        print("Том: %s" % v)
        repair(v, source_idx)


if __name__ == "__main__":
    main()
