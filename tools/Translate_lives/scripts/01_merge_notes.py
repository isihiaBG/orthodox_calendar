#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
01_merge_notes.py — Стъпка 1 (МЕХАНИЧНА, без DeepSeek): обединява стотиците
едноредови файлове с бележки под линия в един общ Text/notes.xhtml.

Защо изобщо: в оригинала всяка бележка е ОТДЕЛЕН xhtml файл (напр. 773 броя
за септември при само 117 жития). Това няма никаква полза за читателя, а
прави по-нататъшното водене на сметка (един JSON на група) излишно тежко.
След тази стъпка септемврийският том пада от 892 на 120 файла.

Защо ПРЕДИ превода, а не след: пренаписването на href-овете и на
content.opf се проверява безпощадно точно ТУК — извличаме видимия текст
преди и след и той трябва да съвпадне символ по символ. Ако смесим
обединяването с превода, при разминаване няма да знаем дали сме счупили
линк, или моделът е измислил нещо. Затова стъпката е нарочно отделна и
НЕ ползва API.

Работи чисто с текстови замени, БЕЗ да пуска xhtml-а през XML сериализатор
— иначе форматирането (което държим непокътнато) щеше да се пренареди.
Файловете с жития се пипат само на едно място: href-а към бележките.

Между другото се чистят и "фантомните" записи в content.opf — файлове,
изброени в manifest/spine, но липсващи на диска. Септемврийският том има
60 такива (index_split_7335..7394, празна опашка); останалите 11 тома са
изрядни. Нищо не сочи към тях и TOC не ги споменава.

Вход:
  ../Input/<книга>.epub

Изход:
  ../work/<том>/src/          разопакован том с обединени бележки
  ../work/<том>/notes_map.json  noteID → текст на бележката (за стъпка 2)

Употреба:
  python3 01_merge_notes.py --vol 09
  python3 01_merge_notes.py --all
"""

import argparse
import glob
import html
import json
import os
import re
import shutil
import sys
import zipfile

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.dirname(SCRIPT_DIR)
INPUT_DIR = os.path.join(PROJECT_DIR, "Input")
WORK_DIR = os.path.join(PROJECT_DIR, "work")

NOTES_FILE = "notes.xhtml"           # ново име, вътре в Text/
NOTES_ID = "notes.xhtml"             # id в manifest (както е при житията)

# Разпознаване на файловете. Житията имат <h1 id="ЧИСЛО">, бележките —
# <h1 id="noteЧИСЛО">. Титулните нямат h1 с id изобщо.
RE_H1_ID = re.compile(r'<h1[^>]*\bid="(note\d+|\d+)"')
RE_BODY = re.compile(r'<body[^>]*>(.*)</body>', re.S)
RE_PARAGRAPH = re.compile(r'<div class="paragraph"')
RE_TAG = re.compile(r'<[^>]+>')


def visible_text(xhtml):
    """Видимият текст на файла, нормализиран по празни места. Ползва се
    САМО за проверката преди/след — не и за същинската обработка."""
    body = RE_BODY.search(xhtml)
    body = body.group(1) if body else xhtml
    return " ".join(html.unescape(RE_TAG.sub(" ", body)).split())


def positions(fragment):
    """Поредните номера (1-базирани) на div-овете с class="paragraph" сред
    ВСИЧКИ div-ове на подадения фрагмент — точно това, което CSS-ът брои с
    nth-of-type. Ако тези числа не се променят, външният вид не се променя."""
    out, n = [], 0
    for m in re.finditer(r'<div\b([^>]*)>', fragment):
        n += 1
        if 'class="paragraph"' in m.group(1):
            out.append(n)
    return out


def unpack(epub_path, dest):
    if os.path.exists(dest):
        shutil.rmtree(dest)
    os.makedirs(dest)
    with zipfile.ZipFile(epub_path) as z:
        z.extractall(dest)


def find_opf(src):
    hits = glob.glob(os.path.join(src, "**", "content.opf"), recursive=True)
    if not hits:
        print("Няма content.opf — неочаквана структура.")
        sys.exit(1)
    return hits[0]


def classify(text_dir):
    """Разделя файловете в Text/ на бележки, жития и останали."""
    notes, lives, other = {}, [], []
    for path in sorted(glob.glob(os.path.join(text_dir, "*.xhtml"))):
        s = open(path, encoding="utf-8").read()
        m = RE_H1_ID.search(s)
        if m and m.group(1).startswith("note"):
            notes[m.group(1)] = path
        elif m:
            lives.append(path)
        else:
            other.append(path)
    return notes, lives, other


def build_notes_file(notes, template_src):
    """Слепва body-тата на всички бележки в един файл, подредени по номер.
    Скелетът (DOCTYPE, head, link към стиловете) се взима дословно от един
    от самите файлове с бележки, за да не се разминат стиловете.

    ВСЯКА бележка се обвива в свой <div class="note">. Това НЕ е разкрасяване
    — то е задължително, за да не се смени външният вид. Стиловете на книгата
    се закачат позиционно (.paragraph:nth-of-type(1) → центриран курсив,
    :nth-of-type(2) → БУКВИЦАТА), а nth-of-type брои div-овете сред съседите
    им. В оригинала всеки файл-бележка има само един .paragraph, тъй че той е
    винаги първи. Слепени голи един до друг, вторият по ред щеше да получи
    буквица насред бележките, а всички останали — отстъп вместо курсив.
    Обвивката нулира броенето за всяка бележка поотделно и стилът остава
    точно какъвто е бил, без да се пипа CSS файлът."""
    tpl = open(template_src, encoding="utf-8").read()
    head = tpl[:RE_BODY.search(tpl).start()]
    tail = tpl[RE_BODY.search(tpl).end():]
    body_open = re.search(r'<body[^>]*>', tpl).group(0)

    parts = []
    for nid in sorted(notes, key=lambda x: int(x[4:])):
        s = open(notes[nid], encoding="utf-8").read()
        inner = RE_BODY.search(s).group(1).strip("\n")
        parts.append('<div class="note">\n%s\n</div>' % inner)

    return head + body_open + "\n" + "\n".join(parts) + "\n</body>" + tail


def note_texts(notes):
    """noteID → видимият текст на бележката (без номера в <h1>)."""
    out = {}
    for nid, path in notes.items():
        s = open(path, encoding="utf-8").read()
        d = re.search(r'<div class="paragraph"[^>]*>(.*?)</div>', s, re.S)
        out[nid] = " ".join(html.unescape(RE_TAG.sub("", d.group(1))).split()) if d else ""
    return out


def rewrite_hrefs(path):
    """Пренасочва ../Text/index_split_NNNN.xhtml#noteXXXX към новия файл.
    Връща (нов текст, брой замени)."""
    s = open(path, encoding="utf-8").read()
    new, n = re.subn(r'(href=")([^"]*?)index_split_\d+\.xhtml(#note\d+")',
                     r'\1\2' + NOTES_FILE + r'\3', s)
    return new, n


def patch_opf(opf_path, drop_hrefs):
    """Маха <item>/<itemref> редовете на подадените href-и и добавя новия
    notes.xhtml в края на manifest-а и на spine-а."""
    s = open(opf_path, encoding="utf-8").read()

    drop_ids = set()
    for href in drop_hrefs:
        m = re.search(r'<item href="%s" id="([^"]+)"[^>]*/>\s*\n?'
                      % re.escape(href), s)
        if m:
            drop_ids.add(m.group(1))
            s = s.replace(m.group(0), "")

    for i in drop_ids:
        s = re.sub(r'[ \t]*<itemref idref="%s"[^>]*/>\s*\n?' % re.escape(i), "", s)

    # Отстъпът на затварящите тагове НЕ е еднакъв в тези файлове:
    # </manifest> е с два интервала, а </spine> е долепен вляво. Затова
    # вмъкването става с регулярен израз, а не с търсене на точен низ —
    # иначе се проваля БЕЗШУМНО и notes.xhtml остава извън реда на четене.
    # Пропуснат ли е spine-ът, повечето четци отказват да отворят бележките,
    # макар файлът да си е в архива и в манифеста.
    item = ('    <item href="Text/%s" id="%s" '
            'media-type="application/xhtml+xml"/>\n' % (NOTES_FILE, NOTES_ID))
    s, n_man = re.subn(r'([ \t]*)</manifest>', lambda m: item + m.group(0),
                       s, count=1)
    s, n_spn = re.subn(r'([ \t]*)</spine>',
                       lambda m: '    <itemref idref="%s"/>\n%s'
                                 % (NOTES_ID, m.group(0)), s, count=1)
    if not (n_man and n_spn):
        print("  ✗ не намерих %s%s в content.opf"
              % ("</manifest> " if not n_man else "",
                 "</spine>" if not n_spn else ""))
    return s, len(drop_ids)


def process(epub_path, vol_name):
    work = os.path.join(WORK_DIR, vol_name)
    src = os.path.join(work, "src")
    print("=" * 64)
    print("Том: %s" % vol_name)
    unpack(epub_path, src)

    opf_path = find_opf(src)
    oebps = os.path.dirname(opf_path)
    text_dir = os.path.join(oebps, "Text")

    notes, lives, other = classify(text_dir)
    print("  бележки: %d | жития: %d | други: %d"
          % (len(notes), len(lives), len(other)))
    if not notes:
        print("  Няма отделни файлове с бележки — нищо за обединяване.")
        return

    # --- снимка ПРЕДИ: видим текст + брой .paragraph на всеки жив файл ---
    before_text = {}
    before_paras = {}
    for p in lives + other:
        s = open(p, encoding="utf-8").read()
        before_text[p] = visible_text(s)
        before_paras[p] = len(RE_PARAGRAPH.findall(s))
    # Разделителят е интервал, а НЕ празен низ: в общия файл бележките са
    # на отделни редове, тъй че нормализацията оставя интервал между тях.
    before_notes = " ".join(visible_text(open(notes[n], encoding="utf-8").read())
                            for n in sorted(notes, key=lambda x: int(x[4:])))
    # Позициите се снимат СЕГА — оригиналните файлове се трият по-надолу.
    before_pos = {n: positions(RE_BODY.search(
                      open(notes[n], encoding="utf-8").read()).group(1))
                  for n in notes}
    # Някои томове идват със СЧУПЕНИ препратки още от източника: октомври
    # сочи към бележки 6177–6236, които ги няма никъде (същите 60, които
    # септември изброява в манифеста си като липсващи файлове — при
    # разцепването по томове са останали с чужда номерация и са се
    # загубили), декември има един такъв случай. Запомняме ги ОТСЕГА, за да
    # не ги отчетем после като своя повреда — проверката трябва да лови
    # само това, което сме счупили ние.
    already_broken = set()
    for p in lives + other:
        s = open(p, encoding="utf-8").read()
        for nid in re.findall(r'href="[^"]*#(note\d+)"', s):
            if nid not in notes:
                already_broken.add(nid)

    # --- обединяване ---
    template = notes[sorted(notes, key=lambda x: int(x[4:]))[0]]
    merged = build_notes_file(notes, template)
    notes_path = os.path.join(text_dir, NOTES_FILE)
    with open(notes_path, "w", encoding="utf-8") as f:
        f.write(merged)

    nmap = note_texts(notes)
    with open(os.path.join(work, "notes_map.json"), "w", encoding="utf-8") as f:
        json.dump(nmap, f, ensure_ascii=False, indent=1)

    # --- пренасочване на препратките ---
    total_refs = 0
    for p in lives + other:
        new, n = rewrite_hrefs(p)
        total_refs += n
        if n:
            with open(p, "w", encoding="utf-8") as f:
                f.write(new)
    print("  пренасочени препратки: %d" % total_refs)

    # --- content.opf: махаме бележките И фантомните записи ---
    disk = {"Text/" + os.path.basename(p)
            for p in glob.glob(os.path.join(text_dir, "*.xhtml"))}
    opf_src = open(opf_path, encoding="utf-8").read()
    listed = {h for h, _ in re.findall(r'<item href="([^"]+)" id="([^"]+)"', opf_src)
              if h.endswith(".xhtml")}
    phantom = listed - disk - {"Text/" + os.path.basename(notes[n]) for n in notes}
    note_hrefs = {"Text/" + os.path.basename(notes[n]) for n in notes}

    new_opf, dropped = patch_opf(opf_path, note_hrefs | phantom)
    with open(opf_path, "w", encoding="utf-8") as f:
        f.write(new_opf)
    print("  премахнати от manifest: %d (от тях фантомни: %d)"
          % (dropped, len(phantom)))

    # --- триене на вече обединените файлове ---
    for n in notes:
        os.remove(notes[n])

    # ------------------------- ПРОВЕРКИ -------------------------
    ok = True

    after_notes = visible_text(open(notes_path, encoding="utf-8").read())
    if after_notes != before_notes:
        print("  ✗ текстът на бележките се разминава преди/след!")
        ok = False

    for p in lives + other:
        s = open(p, encoding="utf-8").read()
        if visible_text(s) != before_text[p]:
            print("  ✗ променен видим текст: %s" % os.path.basename(p))
            ok = False
        if len(RE_PARAGRAPH.findall(s)) != before_paras[p]:
            print("  ✗ променен брой параграфи (буквица!): %s"
                  % os.path.basename(p))
            ok = False

    # Стиловете на книгата се закачат ПОЗИЦИОННО (nth-of-type), затова не
    # стига текстът да съвпада — всеки .paragraph трябва да е останал на
    # същия пореден номер сред div-овете на своя родител, иначе се сменя
    # външният вид (виж докстринга на build_notes_file).
    merged_src = open(notes_path, encoding="utf-8").read()
    blocks = re.findall(r'<div class="note">(.*?)\n</div>', merged_src, re.S)
    if len(blocks) != len(notes):
        print("  ✗ обвивки: %d, а бележки: %d" % (len(blocks), len(notes)))
        ok = False
    else:
        for blk, nid in zip(blocks, sorted(notes, key=lambda x: int(x[4:]))):
            if positions(blk) != before_pos[nid]:
                print("  ✗ разместен стил при %s: %s → %s"
                      % (nid, before_pos[nid], positions(blk)))
                ok = False
                break

    merged_ids = set(re.findall(r'<h1[^>]*id="(note\d+)"', merged_src))
    unresolved = set()
    for p in lives + other:
        s = open(p, encoding="utf-8").read()
        for nid in re.findall(r'href="[^"]*#(note\d+)"', s):
            if nid not in merged_ids:
                unresolved.add(nid)
    new_broken = unresolved - already_broken
    if new_broken:
        print("  ✗ висящи препратки: %d %s"
              % (len(new_broken), sorted(new_broken)[:5]))
        ok = False
    if already_broken:
        nums = sorted(int(x[4:]) for x in already_broken)
        print("  ⚠ %d счупени препратки ОТ ИЗТОЧНИКА (бележки %d–%d липсват "
              "в оригиналния .epub) — оставени както са"
              % (len(already_broken), nums[0], nums[-1]))

    final_disk = {"Text/" + os.path.basename(p)
                  for p in glob.glob(os.path.join(text_dir, "*.xhtml"))}
    final_opf = open(opf_path, encoding="utf-8").read()
    final_listed = {h for h, _ in re.findall(r'<item href="([^"]+)" id="([^"]+)"',
                                             final_opf) if h.endswith(".xhtml")}
    # Всеки xhtml от манифеста трябва да е и в spine-а: файл извън реда на
    # четене е недостижим за много четци, дори да има връзка към него.
    spine_ids = set(re.findall(r'<itemref idref="([^"]+)"', final_opf))
    man_ids = {i for h, i in re.findall(r'<item href="([^"]+)" id="([^"]+)"',
                                        final_opf) if h.endswith(".xhtml")}
    if man_ids - spine_ids:
        print("  ✗ в манифеста, но ИЗВЪН spine: %s"
              % sorted(man_ids - spine_ids)[:5])
        ok = False

    if final_listed != final_disk:
        print("  ✗ manifest не съвпада с диска: липсват %s | излишни %s"
              % (sorted(final_listed - final_disk)[:3],
                 sorted(final_disk - final_listed)[:3]))
        ok = False

    print("  бележки в общия файл: %d | файлове след: %d"
          % (len(merged_ids), len(final_disk)))
    print("  %s" % ("✓ всички проверки минаха" if ok else "✗ ИМА ПРОБЛЕМИ"))
    return ok


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--vol", help="номер на том, напр. 09")
    ap.add_argument("--all", action="store_true", help="всички 12 тома")
    args = ap.parse_args()

    # В Input/ стои и НЕразцепената книга („Жития святых - Димитрий
    # Ростовский.epub", без номер на месец). Тя не е том за превод — служи
    # само като източник за 01b_repair_notes.py. Разпознава се по липсата
    # на „- NN(" в името и се пропуска тук.
    epubs = sorted(e for e in glob.glob(os.path.join(INPUT_DIR, "*.epub"))
                   if re.search(r"- \d+\(", os.path.basename(e)))
    if not epubs:
        print("Няма .epub файлове с номер на месец в %s" % INPUT_DIR)
        sys.exit(1)

    if args.vol:
        epubs = [e for e in epubs
                 if re.search(r"- (\d+)\(", os.path.basename(e))
                 and re.search(r"- (\d+)\(", os.path.basename(e)).group(1) == args.vol]
        if not epubs:
            print("Няма том %s в %s" % (args.vol, INPUT_DIR))
            sys.exit(1)
    elif not args.all:
        print("Подай --vol NN или --all")
        sys.exit(1)

    for e in epubs:
        m = re.search(r"- (\d+\([^)]+\))", os.path.basename(e))
        process(e, m.group(1) if m else os.path.splitext(os.path.basename(e))[0])


if __name__ == "__main__":
    main()
