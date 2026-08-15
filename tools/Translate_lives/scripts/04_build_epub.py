#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
04_build_epub.py — Стъпка 4 (МЕХАНИЧНА, без DeepSeek): сглобява преведения
.epub от подготвената книга и преведените групи.

Върши точно обратното на 02_extract.py: там блоковете се разглобяват на чист
текст + номерирани запушалки, тук преводът се връща по местата си, а
запушалките се заменят обратно с истинските тагове.

ТАГОВЕТЕ СЕ ВАДЯТ НАНОВО ОТ КНИГАТА, а не от извлечените JSON-и. Това не е
дреболия: JSON-ите пазят таговете такива, каквито са били в мига на
разглобяването, а книгата се поправя и след това (01b върна липсващи
бележки, 01c оживи 164 вътрешни връзки). Ако вземехме таговете от JSON-а,
готовият .epub щеше да излезе със старите, счупени href-ове — и то безшумно.
Затова JSON-ът дава САМО превода, а разметката идва винаги от src/.

Бележките се попълват на ДВЕ места от един и същ превод: самата бележка в
notes.xhtml и title="..." атрибутът на всяка препратка към нея. Затова не са
превеждани два пъти и затова изскачащото описание не може да се разминае с
бележката.

Проверки преди записа (счупят ли се, файлът не се пише):
  • брой и ред на блоковете — непроменени спрямо src/
  • брой .paragraph във всеки файл — непроменен (буквицата виси на реда им)
  • всяка запушалка има съответен таг и обратно
  • нито един блок не е останал непреведен

Вход:
  ../work/<том>/src/
  ../work/<том>/translated/*.json

Изход:
  ../Output/Жития на светиите - NN(мес) - Димитрий Ростовски.epub
  (същата конвенция като изходните книги в Input/)

Употреба:
  python3 04_build_epub.py --vol 09
  python3 04_build_epub.py --all
"""

import argparse
import glob
import html
import json
import os
import re
import shutil
import sys
import time
import xml.etree.ElementTree as ET
import zipfile

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.dirname(SCRIPT_DIR)
WORK_DIR = os.path.join(PROJECT_DIR, "work")
OUTPUT_DIR = os.path.join(PROJECT_DIR, "Output")

# Готовите книги се именуват по СЪЩАТА конвенция като изходните в Input/:
#   „Жития на светиите - 09(сеп) - Димитрий Ростовски.epub"
# Така преведените и оригиналните стоят едно до друго в библиотеката и се
# подреждат по месеци. Името НЕ идва от преведеното заглавие: то се мени при
# всяка поправка по превода и всяка промяна ражда нов файл, а старият остава
# да виси (точно това се случи, докато заглавията се разминаваха).
MONTH_ABBR = {"01": "яну", "02": "фев", "03": "мар", "04": "апр",
              "05": "май", "06": "юни", "07": "юли", "08": "авг",
              "09": "сеп", "10": "окт", "11": "ное", "12": "дек"}
NAME_TPL = "Жития на светиите - %s(%s) - Димитрий Ростовски.epub"

RE_BLOCK = re.compile(
    r'<h1\b[^>]*>.*?</h1>|<div class="paragraph"[^>]*>.*?</div>', re.S)
RE_INNER_H1 = re.compile(r'^(<h1\b[^>]*>)(.*)(</h1>)$', re.S)
RE_INNER_DIV = re.compile(r'^(<div class="paragraph"[^>]*>)(.*)(</div>)$', re.S)
RE_TAG = re.compile(r'<[^>]+>')
RE_PARA = re.compile(r'<div class="paragraph"')
PH = re.compile(r"⟦(\d+)⟧")

# ── Тропарите и кондаците накрая на житието ──────────────────────────────
#
# В книгата те стоят като два обикновени абзаца: заглавие („Тропарь, глас 8:")
# и текст. Тук се разгъват на ТРИ, за да изглеждат както в дневния изглед:
#
#     <p class="prayerhead">Тропар, глас 8</p>
#     <p class="csl">Слез твоих теченьми…</p>          ← оригиналът
#     <p class="trans"><span class="translabel">Превод:</span> …</p>
#
# „Оригиналът" е църковнославянски в руска гражданска азбука — точно това, за
# което служи класът .csl в стария четец. Затова тук се пренася както си е,
# а не се превежда.
#
# ⚠ Класът НЕ се пише в class="paragraph …", а в отделен атрибут
# data-prayer. Причината е в проверките отдолу: RE_PARA търси буквално
# `class="paragraph"` и добавен клас би я подвел, че абзаците са намалели —
# а на техния брой виси буквицата. С отделен атрибут всички изрази работят
# непроменени.
RE_PRAYER_HEAD = re.compile(
    r'^(?:(?:Ин|Друг|Иный|Другой)\s+)?(?:[Тт]ропар|[Кк]ондак)\b'
    r'[^:]{0,60}:\s*$')
# Препратка към бележка вътре в текста на молитвата (20 случая от 595).
# Маха се САМО от оригинала: инак номерчето излиза два пъти — веднъж на
# църковнославянския ред и веднъж на превода, — а бележката е една и съща.
RE_NOTE_REF = re.compile(
    r'<a[^>]*#note\d+[^>]*>\s*<sup[^>]*>.*?</sup>\s*</a>', re.S)


def split_tags(inner):
    """Същото разглобяване като в 02_extract.py — но върху ТЕКУЩАТА книга."""
    tags = []

    def repl(m):
        tags.append(m.group(0))
        return "⟦%d⟧" % len(tags)

    return RE_TAG.sub(repl, inner), tags


def plain(text):
    """Преводът без запушалки и без тагове — за title атрибута."""
    return " ".join(html.unescape(RE_TAG.sub("", PH.sub("", text))).split())


def attr(text):
    return (text.replace("&", "&amp;").replace("<", "&lt;")
                .replace(">", "&gt;").replace('"', "&quot;"))


def load_translations(work):
    """(файл, номер на блок) → превод; noteID → превод; target → превод."""
    blocks, meta = {}, {}
    for f in sorted(glob.glob(os.path.join(work, "translated", "*.json"))):
        g = json.load(open(f, encoding="utf-8"))
        for u in g["units"]:
            if "translated" not in u:
                continue
            if u.get("target"):
                # Пази се и оригиналът: за <title> в главите замяната става по
                # съвпадение с руския текст, а не сляпо (файловете може да имат
                # различни заглавия, напр. „Cover").
                meta[u["target"]] = (u["text"], u["translated"])
            else:
                blocks[(u["file"], u["block"])] = u["translated"]
    return blocks, meta


def note_translations(oebps, blocks):
    """noteID → преведеният текст на бележката (чист, за title атрибута)."""
    rel = "Text/notes.xhtml"
    path = os.path.join(oebps, rel)
    if not os.path.exists(path):
        return {}
    s = open(path, encoding="utf-8").read()
    out, current = {}, None
    for idx, m in enumerate(RE_BLOCK.finditer(s)):
        block = m.group(0)
        if block.startswith("<h1"):
            hm = re.search(r'id="(note\d+)"', block)
            current = hm.group(1) if hm else None
        elif current and (rel, idx) in blocks:
            out.setdefault(current, plain(blocks[(rel, idx)]))
    return out


RE_BODY_SPAN = re.compile(r'<body[^>]*>.*?</body>', re.S)
RE_TEXT_NODE = re.compile(r'>([^<>]+)<')
CYR = re.compile(r'[А-Яа-яЁё]')


def extra_nodes(s):
    """Текстови възли с кирилица в <body>, но ИЗВЪН блоковете. Копие на
    същата функция в 02c_extract_extra.py — номерацията трябва да съвпада
    точно, иначе преводът ще влезе на грешно място."""
    body = RE_BODY_SPAN.search(s)
    if not body:
        return []
    lo, hi = body.start(), body.end()
    spans = [(m.start(), m.end()) for m in RE_BLOCK.finditer(s)]
    out = []
    for m in RE_TEXT_NODE.finditer(s):
        a, b = m.start(1), m.end(1)
        if a < lo or b > hi or any(bs <= a < be for bs, be in spans):
            continue
        if CYR.search(html.unescape(m.group(1))):
            out.append((a, b, m.group(1)))
    return out


# Библейските препратки водят към РУСКИ текст („&cr&rus"). За книга на
# български целта е българският с успореден църковнославянски („&bg~utfcs").
# Замяната живее и в 01d_bible_links.py, което я прави върху src/. Тук е
# ВТОРИ ПОЯС: 01_merge_notes.py пресъздава src/ от оригиналните .epub-и и
# пуснат наново, връща руските опашки. Така готовата книга излиза вярна
# независимо от реда, в който са пускани стъпките.
# Действието е безопасно за повтаряне — вече сменена връзка не се пипа.
# Пипат се САМО връзките към /biblia/; другите azbyka връзки (към светите
# отци и правилата на съборите) нямат такъв превключвател.
RE_BIBLE_HREF = re.compile(r'href="([^"]*azbyka\.ru/biblia/[^"]*)"')
BIBLE_OLD, BIBLE_NEW = "&amp;cr&amp;rus", "&amp;bg~utfcs"


def bulgarian_bible_links(s):
    """Всяка библейска препратка да завършва на &bg~utfcs — със ЗАМЯНА там,
    където стои руската опашка, и с ДОБАВЯНЕ там, където опашка липсва
    (една такава има в октомври: „?Jac.1", сочи към цяла глава). Връща
    (нов текст, брой сменени)."""
    n = 0

    def repl(m):
        nonlocal n
        href = m.group(1)
        if "bg~utfcs" in href:
            return m.group(0)
        n += 1
        if BIBLE_OLD in href:
            return 'href="%s"' % href.replace(BIBLE_OLD, BIBLE_NEW)
        return 'href="%s%s"' % (href, BIBLE_NEW)

    return RE_BIBLE_HREF.sub(repl, s), n


def rebuild_file(path, rel, blocks, notes_bg, html_title, extra, problems):
    s = open(path, encoding="utf-8").read()
    before_paras = len(RE_PARA.findall(s))
    before_blocks = len(RE_BLOCK.findall(s))

    # Текстът извън блоковете се заменя ПЪРВИ и ОТЗАД НАПРЕД, за да останат
    # валидни отместванията на все още незаменените възли. Тези възли са
    # извън блоковете, тъй че поредните номера на блоковете не се влияят.
    for i, (a, b, _) in reversed(list(enumerate(extra_nodes(s)))):
        tr = extra.get("extra:%s:%d" % (rel, i))
        if tr:
            s = s[:a] + attr(tr) + s[b:]

    def repl(m):
        idx = repl.i
        repl.i += 1
        block = m.group(0)
        tr = blocks.get((rel, idx))
        if tr is None:
            return block                      # непреводим блок (номер и т.н.)
        im = RE_INNER_H1.match(block) or RE_INNER_DIV.match(block)
        if not im:
            return block
        open_tag, inner, close_tag = im.group(1), im.group(2), im.group(3)
        _, tags = split_tags(inner)

        used = sorted(int(x) for x in set(PH.findall(tr)))
        if used and (used[-1] > len(tags) or used[0] < 1):
            problems.append("%s блок %d: запушалка ⟦%d⟧, а таговете са %d"
                            % (rel, idx, used[-1], len(tags)))
            return block

        new_inner = PH.sub(lambda p: tags[int(p.group(1)) - 1], tr)

        # ── Молитвите накрая на житието ──────────────────────────────────
        # Заглавието вдига флаг; следващият блок С ПРЕВОД е текстът на
        # молитвата. Между тях в книгата често стои празен абзац — той няма
        # превод и не се брои, тъй че флагът го прескача от само себе си.
        if repl.prayer_pending:
            repl.prayer_pending = False
            repl.added += 1
            csl = RE_NOTE_REF.sub("", inner).strip()
            return ('<div class="paragraph" data-prayer="csl">%s</div>'
                    '<div class="paragraph" data-prayer="trans">'
                    '<span class="translabel">Превод:</span> %s</div>'
                    % (csl, new_inner))
        if RE_PRAYER_HEAD.match(plain(tr)):
            repl.prayer_pending = True
            # Двоеточието отпада — старият четец реже заглавието по „: " и
            # рисува „Тропар, глас 8" без него.
            head = plain(tr).rstrip().rstrip(":").rstrip()
            return '<div class="paragraph" data-prayer="head">%s</div>' % head

        return open_tag + new_inner + close_tag

    repl.i = 0
    repl.prayer_pending = False
    repl.added = 0
    out = RE_BLOCK.sub(repl, s)

    # title="..." на препратките към бележки — от превода на самата бележка.
    # И двете групи са ИМЕНУВАНИ: със смесени именувани и номерирани групи
    # номерацията се измества и лесно се хваща префиксът вместо номера.
    def fix_title(m):
        nid = m.group("nid")
        bg = notes_bg.get(nid)
        return ('href="%s#%s" title="%s"' % (m.group("pre"), nid, attr(bg))
                if bg else m.group(0))

    out = re.sub(r'href="(?P<pre>[^"]*)#(?P<nid>note\d+)"\s+title="[^"]*"',
                 fix_title, out)

    # Библейските препратки към български текст (втори пояс — виж горе).
    out, _ = bulgarian_bible_links(out)

    # <title> в главата на файла — заменя се само ако съвпада с оригинала,
    # за да не пипнем чужди заглавия (напр. „Cover" на корицата).
    if html_title:
        ru, bg = html_title
        out = out.replace("<title>%s</title>" % ru, "<title>%s</title>" % bg)

    # Проверките остават СТРОГИ — само знаят колко абзаца е добавило
    # разгъването на молитвите. Те са накрая на главата, след житието, тъй
    # че буквицата на първия абзац не може да бъде засегната.
    if len(RE_PARA.findall(out)) != before_paras + repl.added:
        problems.append("%s: сменен брой .paragraph (буквицата!)" % rel)
        return s
    if len(RE_BLOCK.findall(out)) != before_blocks + repl.added:
        problems.append("%s: сменен брой блокове" % rel)
        return s
    if repl.prayer_pending:
        problems.append("%s: заглавие на молитва без текст след него" % rel)
    return out


# Всяка бележка да започва на НОВА СТРАНИЦА. В оригинала бележките бяха по
# една на файл и щракването върху препратка отваряше екран точно с нея. След
# обединяването скокът е към котва насред дълъг документ и е неточен — при
# леко разминаване четецът показва ПРЕДИШНАТА бележка. Страницирането връща
# старото поведение: котвата пада на началото на страница, а съседните
# бележки остават физически на другите екрани.
#
# Правилото се слага в <head> на самия notes.xhtml, а НЕ в stylesheet.css —
# така потребителският CSS остава непокътнат байт по байт. Първата бележка е
# изключена, за да няма празна страница в началото.
# Основният текст на книгата няма зададен шрифт — .calibre (класът на <body>)
# не носи font-family и четецът ползва каквото си е по подразбиране. Вграждаме
# Charis SIL от приложението, за да изглежда книгата еднакво навсякъде.
#
# ТУК СТОЕШЕ CAMBRIA — не я връщай. Тя е на Microsoft и лицензът ѝ не
# позволява разпространяване на файла извън продукт на Microsoft, а тези
# томове се раздават. Charis SIL е под SIL OFL 1.1.
#
# Подрязването е позволено: OFL-FAQ 1.12 казва, че шрифт може да се вгради в
# документ „either in full or a subset", като ограниченията за промяна и
# преименуване НЕ важат, защото шрифтът не е предназначен за употреба извън
# документа. Все пак слагаме и OFL.txt в тома — FAQ 1.15 настоява шрифтът да
# не губи авторството и лиценза си, дори когато пътува вътре в документ.
#
# Правилата се ДОБАВЯТ в края на stylesheet.css, а нищо съществуващо не се
# пипа. Буквицата и заглавията не са застрашени: .paragraph:...:first-letter
# е по-специфичен от .calibre, а .calibre9 (заглавията) си има собствен
# font-family, който бие наследяването.
#
# Българските корици. Слагат се ВЪРХУ извлечените от руския том — той си
# носи своята и без подмяна тя пътува в готовата книга. Файлът е с
# точно същото име и тип (cover.jpg, image/jpeg), тъй че манифестът в
# content.opf и препратката в titlepage.xhtml не се пипат.
COVERS_DIR = os.path.join(PROJECT_DIR, "Covers_BG")

FONT_DIR = os.path.join(os.path.dirname(os.path.dirname(PROJECT_DIR)),
                        "assets", "fonts")
LICENSE_FILE = "OFL-CharisSIL.txt"
# ПОЛУЧЕРЪТ НАРОЧНО ЛИПСВА. Проверено: в тези книги няма нито един получер
# знак — класовете с font-weight:bold (calibre5, calibre7) не се срещат
# никъде, няма и <strong>/<b>. Получерът би тежал стотици килобайта на том
# за нищо. Курсивът се ползва (~3% от текста, главно библейските цитати) и се
# вгражда, за да не го наклонява четецът по сметка.
CHARIS = [("CharisSIL-Regular.ttf", "normal", "normal"),
          ("CharisSIL-Italic.ttf", "normal", "italic")]
# Получерът стои ОТДЕЛНО, защото се подрязва по друг набор знаци. В тези
# книги единственото получерно нещо са заглавията на тропарите и кондаците
# („Тропар, глас 8"), тъй че му трябват няколко десетки букви вместо целия
# том: 42 KB вместо 786. Без него четецът дорисува получер сам и буквите
# излизат размазани.
CHARIS_BOLD = ("CharisSIL-Bold.ttf", "bold", "normal")

# Оформлението на молитвите В САМАТА КНИГА — за когато томът се отвори в
# чужд четец. В приложението те се рисуват от reader_styles.dart и този CSS
# не се чете; тук е, за да не изглежда книгата гола другаде.
#
# Цветовете са същите като в четеца при светла тема: виненото на заглавията
# и приглушеното сиво на превода (reader_theme.dart, `wine` и `dim`).
# Тялото на молитвата НЕ се пипа — остава като основния текст.
PRAYER_CSS = """
/* — тропарите и кондаците накрая на житието (добавено при сглобяването) — */
div.paragraph[data-prayer="head"] {
	font-weight: bold;
	color: #B83333;
	margin-top: 1.2em;
	margin-bottom: 0.2em;
	}
div.paragraph[data-prayer="trans"] {
	font-style: italic;
	color: #6B675F;
	}
div.paragraph[data-prayer="trans"] .translabel {
	font-style: normal;
	font-weight: bold;
	}
"""

FONT_CSS = """
/* — вградена Charis SIL за основния текст (добавено при сглобяването) — */
%s.calibre {
	font-family: "CharisSIL", serif;
	}
"""

FACE = """@font-face {
	font-family: "CharisSIL";
		src: url("../Fonts/%s");
	font-weight: %s;
	font-style: %s;
	}
"""


def used_characters(oebps):
    """Всички знаци, които книгата наистина изписва. Основа за подрязването —
    така всеки том носи точно своите глифи и нищо повече."""
    chars = set()
    for p in glob.glob(os.path.join(oebps, "Text", "*.xhtml")):
        s = open(p, encoding="utf-8").read()
        body = RE_BODY_SPAN.search(s)
        txt = body.group(0) if body else s
        chars |= set(html.unescape(RE_TAG.sub(" ", txt)))
        # title атрибутите също се изписват (изскачащите бележки).
        for t in re.findall(r'title="([^"]*)"', s):
            chars |= set(html.unescape(t))
    return chars


def subset_font(src, dst, chars):
    """Подрязва шрифта до подадените знаци. Връща True при успех; при липсващ
    fontTools просто копира целия файл — по-добре голям, отколкото никакъв."""
    try:
        from fontTools import subset
    except ImportError:
        shutil.copy2(src, dst)
        return False
    opts = subset.Options()
    opts.layout_features = ["*"]      # лигатури и кернинг остават
    opts.notdef_outline = True
    font = subset.load_font(src, opts)
    s = subset.Subsetter(options=opts)
    s.populate(text="".join(sorted(chars)))
    s.subset(font)
    subset.save_font(font, dst, opts)
    font.close()
    return True


def prayer_head_characters(oebps):
    """Знаците, изписани в заглавията на молитвите. Основа за подрязването на
    получера: той се ползва само там и няма защо да носи целия том."""
    chars = set()
    for p in glob.glob(os.path.join(oebps, "Text", "*.xhtml")):
        s = open(p, encoding="utf-8").read()
        for m in re.finditer(
                r'<div class="paragraph" data-prayer="head"[^>]*>(.*?)</div>',
                s, re.S):
            chars |= set(html.unescape(RE_TAG.sub(" ", m.group(1))))
    return chars


# Трите числа на заглавната страница. Стоят тук, защото се нагласяват с
# ОКО в обикновен четец и почти сигурно ще се пипат пак.
#
# TITLE_SIZE      кеглите на „ЖИТИЯ/на/СВЕТИИТЕ". Оригиналът е 68px за един
#                 ред; на три реда толкова е прекалено.
# TITLE_LEADING   междуредие. В книгата стоеше 46px — при 68px шрифт това е
#                 застъпване, което не личеше само защото редът беше един.
# TITLE_NA_LIFT   повдигане на „на". При еднакъв кегел то е с x-височина, а
#                 съседите му са с главни букви, тъй че стои ниско в реда си
#                 и горното разстояние ИЗГЛЕЖДА по-голямо. Изравнява видяното,
#                 не измереното. ⚠ `position` не се поддържа от flutter_html —
#                 важи за чуждите четци, в приложението редът си остава.
TITLE_SIZE = "58px"
TITLE_LEADING = "0.62"
TITLE_NA_LIFT = "-0.12em"
# Редът с месеца („месец януари") и кръстчетата над него — изравнени с
# подзаглавието „по изложението на…". В книгата бяха 30px и 1.0em.
#
# ⚠ 2.16em, а НЕ 1.2em, колкото пише при подзаглавието. Уловката е, че
# подзаглавието е <span> ВЪТРЕ в div.calibre9, тъй че неговите 1.2em се
# умножават по класовите 1.8em и дават 2.16. Месецът и кръстчетата са
# самите div.calibre9 — там инлайн размерът ЗАМЕСТВА 1.8em, не се умножава
# с тях. Сложи ли се 1.2em и на тях, излизат по-дребни и от оригинала.
MONTH_SIZE = "1.85em"
CROSSES_SIZE = "1.55em"


def fix_titlepage(oebps):
    """Приближава заглавната страница до корицата. Връща True при промяна.

    Две неща, и двете само в оформлението — текстът си остава преводът:

      1. Заглавието се разчупва на ТРИ реда, както е на корицата:
             ЖИТИЯ
               на          (с малки букви, но със СЪЩИЯ кегел)
             СВЕТИИТЕ
         Разчупването е с <br/> ВЪТРЕ в същия <span>, не с нови абзаци —
         иначе редовете се разделят и се получават три заглавия.

         „на" се повдига с 0.10em. Причината е типографска: при еднакъв
         кегел то е с x-височина, а съседните редове са с главни букви, тъй
         че стои ниско в реда си и горното разстояние ИЗГЛЕЖДА по-голямо от
         долното, без да е. Повдигането изравнява видяното, не измереното.
         ⚠ `position` не се поддържа от flutter_html — в приложението редът
         си остава както е бил; повдигането важи за чуждите четци.
      2. „според изложението на" → „по изложението на".

    ⚠ Междуредието се сменя от `46px` на множител. При 68-пикселов шрифт
    46 пиксела ред значеше застъпване — не личеше, докато заглавието беше на
    един ред. (В нашия четец е без значение: book_reader._normalize маха
    инлайн line-height, защото flutter_html го чете като множител. Но томът
    се отваря и в чужди четци.)
    """
    changed = 0
    for path in glob.glob(os.path.join(oebps, "Text", "*.xhtml")):
        s = open(path, encoding="utf-8").read()
        if "ЖИТИЯ НА СВЕТИИТЕ" not in s:
            continue
        # Разчупването е с <br/> ВЪТРЕ в същия <span>. Пробвано беше и с три
        # блокчета — flutter_html ги подрежда правилно, но те попадат под
        # общото му правило за `div` и заглавието излиза с друг шрифт
        # (Charis SIL вместо Tamburin) и по-дребно. Инлайн font-family не
        # помага: книгата обявява шрифта като „Tamburin Modern", а
        # приложението го знае като „TamburinModern".
        #
        # С <br/> и двете се наследяват сами — в книгата от .calibre9, в
        # приложението от правилото за h3 — и нищо не се пипа в кода, тъй че
        # утрешна нова книга няма да иска промени.
        out = s.replace(
            "ЖИТИЯ НА СВЕТИИТЕ",
            'ЖИТИЯ<br/><span style="position: relative; top: %s;">на'
            '</span><br/>СВЕТИИТЕ' % TITLE_NA_LIFT)
        out = out.replace(
            "font-size: 68px; line-height: 46px;",
            "font-size: %s; line-height: %s;" % (TITLE_SIZE, TITLE_LEADING))
        out = out.replace("font-size: 30px; line-height: 0.8em;",
                          "font-size: %s; line-height: 0.8em;" % MONTH_SIZE)
        out = out.replace("font-size: 1.0em; line-height: 0.8em; text-align",
                          "font-size: %s; line-height: 0.8em; text-align"
                          % CROSSES_SIZE)
        out = out.replace("според изложението на", "по изложението на")
        if out != s:
            with open(path, "w", encoding="utf-8") as f:
                f.write(out)
            changed += 1
    return changed


def replace_cover(oebps, vol):
    """Слага българската корица на тома. Връща True, ако е сменена.

    Липсва ли файл за този месец, книгата излиза с руската корица и това се
    съобщава — по-добре стара корица, отколкото том без корица.
    """
    # Томът се казва „01(яну)", а корицата — просто „01.jpg": в папката
    # номерът на месеца стига, а руското съкращение в скобите само би карало
    # човек да го помни при преименуване.
    src = os.path.join(COVERS_DIR, "%s.jpg" % vol[:2])
    dst = os.path.join(oebps, "Images", "cover.jpg")
    if not os.path.exists(src):
        print("  ⚠ няма българска корица %s — остава руската" % src)
        return False
    if not os.path.exists(dst):
        print("  ⚠ томът няма Images/cover.jpg — корицата не е сменена")
        return False
    shutil.copyfile(src, dst)
    return True


def embed_fonts(oebps):
    """Копира Charis SIL в книгата, добавя @font-face и я задава за основен
    шрифт. Шрифтовете се ПОДРЯЗВАТ до знаците, които томът наистина ползва —
    Charis SIL носи стотици глифи за езици, които тези книги не пипат, а на
    тях им трябват само кирилица, латиница и пунктуация. Наборът се смята от
    самата книга, тъй че не може да се получи липсващ глиф."""
    css_path = os.path.join(oebps, "Styles", "stylesheet.css")
    css = open(css_path, encoding="utf-8").read()
    if '"CharisSIL"' in css:
        return 0

    chars = used_characters(oebps)
    fonts_dir = os.path.join(oebps, "Fonts")
    faces, added, sub_ok = "", [], True
    for fn, weight, style in CHARIS:
        src = os.path.join(FONT_DIR, fn)
        if not os.path.exists(src):
            print("  ⚠ липсва шрифт: %s" % src)
            continue
        dst = os.path.join(fonts_dir, fn)
        if not subset_font(src, dst, chars):
            sub_ok = False
        faces += FACE % (fn, weight, style)
        added.append(fn)
    if not added:
        return 0

    # Лицензът пътува заедно с шрифта — OFL-FAQ 1.15: дори когато шрифтът е
    # вътре в документ, „it should not lose its authorship information and
    # licensing".
    lic_src = os.path.join(FONT_DIR, LICENSE_FILE)
    if os.path.exists(lic_src):
        shutil.copyfile(lic_src, os.path.join(fonts_dir, LICENSE_FILE))
        added.append(LICENSE_FILE)
    else:
        print("  ⚠ липсва %s — томът ще излезе без лиценза на шрифта" % lic_src)

    if not sub_ok:
        print("  ⚠ няма fontTools — шрифтовете са вградени НЕподрязани")
    else:
        print("  знаци в тома: %d" % len(chars))

    # Получерът — само ако томът има заглавия на молитви, и подрязан по тях.
    bold_chars = prayer_head_characters(oebps)
    extra_css = ""
    if bold_chars:
        fn, weight, style = CHARIS_BOLD
        src = os.path.join(FONT_DIR, fn)
        if os.path.exists(src):
            if not subset_font(src, os.path.join(fonts_dir, fn), bold_chars):
                sub_ok = False
            faces += FACE % (fn, weight, style)
            added.append(fn)
            print("  получер за заглавията на молитвите: %d знака"
                  % len(bold_chars))
        else:
            print("  ⚠ липсва %s — заглавията ще са с дорисуван получер" % src)
        extra_css = PRAYER_CSS

    with open(css_path, "w", encoding="utf-8") as f:
        f.write(css.rstrip("\n") + "\n" + (FONT_CSS % faces) + extra_css)

    # Всеки файл в архива трябва да е и в манифеста, иначе .epub-ът не е
    # валиден и четците може да не заредят шрифта.
    opf_path = os.path.join(oebps, "content.opf")
    o = open(opf_path, encoding="utf-8").read()
    items = ""
    for fn in added:
        if 'href="Fonts/%s"' % fn in o:
            continue
        # Лицензът не е шрифт — с грешен media-type томът не е валиден.
        mime = ("text/plain" if fn.endswith(".txt")
                else "application/x-font-ttf")
        items += ('    <item href="Fonts/%s" id="%s" media-type="%s"/>\n'
                  % (fn, fn, mime))
    if items:
        o = re.sub(r'([ \t]*)</manifest>', lambda m: items + m.group(0),
                   o, count=1)
        with open(opf_path, "w", encoding="utf-8") as f:
            f.write(o)
    return len(added)


def split_notes(oebps):
    """Разцепва общия notes.xhtml обратно на ПО ЕДИН ФАЙЛ НА БЕЛЕЖКА — така,
    както беше в оригиналната книга.

    Защо се наложи: обединяването е удобно за конвейера (един файл вместо
    773 при разглобяване и сглобяване), но за читателя е по-лошо. Скокът към
    котва насред документ от ~360 KB се оказва неточен на практика — четците
    попадат една-две страници ПРЕДИ търсената бележка. Опитът да се поправи
    със страниране (page-break-before на всяка бележка) НЕ помогна: четецът
    смята позицията приблизително независимо от преходите. Отделният файл
    премахва проблема по устройство — котвата е в началото на мъничък
    документ и няма какво да се сгреши.

    Обвивката <div class="note"> отпада: във файл сам за себе си .paragraph
    отново е първият div, тоест хваща .paragraph:nth-of-type(1) — центрирания
    курсив, с който бележките се изписваха в оригинала.

    Прави се ЧАК ТУК, при сглобяването. В work/<том>/src/ бележките остават в
    един файл, което пази простото адресиране по номер на блок, на което
    стъпват всички вече направени преводи.
    """
    notes_path = os.path.join(oebps, "Text", "notes.xhtml")
    if not os.path.exists(notes_path):
        return 0
    s = open(notes_path, encoding="utf-8").read()

    head = s[:re.search(r'<body[^>]*>', s).end()]
    tail = "\n</body>\n</html>\n"

    # НЕ с нежаден израз до първото „\n</div>“. Съдържанието на бележката
    # може само да съдържа такова място — напр. note8129 в декември има три
    # параграфа и затварящият таг на последния стои на собствен ред. Тогава
    # изразът се спира ТАМ вместо при обвивката, файлът излиза с несдвоени
    # тагове и следващата бележка изчезва заедно с препратката към нея.
    # Затова режем по началния маркер (той е еднозначен, слагаме го ние в
    # 01_merge_notes.py) и махаме последния </div> отзад.
    body = re.search(r"<body[^>]*>(.*)</body>", s, re.S).group(1)
    blocks = []
    for chunk in body.split('<div class="note">\n')[1:]:
        inner = chunk.rstrip()
        if not inner.endswith("</div>"):
            problems_note = "notes.xhtml: обвивка без затварящ таг"
            print("  ✗ %s" % problems_note)
            return 0
        blocks.append(inner[: -len("</div>")].rstrip("\n"))

    written = []
    for b in blocks:
        m = re.search(r'<h1[^>]*id="(note\d+)"', b)
        if not m:
            continue
        nid = m.group(1)
        fn = "%s.xhtml" % nid
        with open(os.path.join(oebps, "Text", fn), "w", encoding="utf-8") as f:
            f.write(head + "\n" + b + tail)
        written.append((nid, fn))
    if not written:
        return 0

    # Препратките сочат към notes.xhtml — насочваме всяка към своя файл.
    for p in glob.glob(os.path.join(oebps, "Text", "*.xhtml")):
        if os.path.basename(p).startswith("note"):
            continue
        t = open(p, encoding="utf-8").read()
        new = re.sub(r'href="([^"]*?)notes\.xhtml#(note\d+)"',
                     lambda m: 'href="%s%s.xhtml#%s"'
                               % (m.group(1), m.group(2), m.group(2)), t)
        if new != t:
            with open(p, "w", encoding="utf-8") as f:
                f.write(new)

    os.remove(notes_path)

    # Манифестът и spine-ът: махаме notes.xhtml и добавяме файловете по номер
    # в края — точно където стояха бележките и в оригинала.
    opf_path = os.path.join(oebps, "content.opf")
    o = open(opf_path, encoding="utf-8").read()
    o = re.sub(r'[ \t]*<item href="Text/notes\.xhtml"[^>]*/>\s*\n?', "", o)
    o = re.sub(r'[ \t]*<itemref idref="notes\.xhtml"[^>]*/>\s*\n?', "", o)
    items = "".join('    <item href="Text/%s" id="%s" '
                    'media-type="application/xhtml+xml"/>\n' % (fn, nid)
                    for nid, fn in written)
    refs = "".join('    <itemref idref="%s"/>\n' % nid for nid, _ in written)
    o = re.sub(r'([ \t]*)</manifest>', lambda m: items + m.group(0), o, count=1)
    o = re.sub(r'([ \t]*)</spine>', lambda m: refs + m.group(0), o, count=1)
    with open(opf_path, "w", encoding="utf-8") as f:
        f.write(o)
    return len(written)


def apply_meta(oebps, meta):
    """Надписите на съдържанието и описанието на книгата."""
    ncx_path = os.path.join(oebps, "toc.ncx")
    s = open(ncx_path, encoding="utf-8").read()
    i = [0]

    def repl(m):
        pair = meta.get("ncx:%d" % i[0])
        i[0] += 1
        return "<text>%s</text>" % attr(pair[1]) if pair else m.group(0)

    s = re.sub(r"<text>.*?</text>", repl, s, flags=re.S)
    with open(ncx_path, "w", encoding="utf-8") as f:
        f.write(s)

    opf_path = os.path.join(oebps, "content.opf")
    o = open(opf_path, encoding="utf-8").read()
    for tag in ("dc:title", "dc:creator", "dc:subject"):
        pair = meta.get("opf:%s" % tag)
        if pair:
            t = pair[1]
            o = re.sub(r"(<%s[^>]*>)[^<]+(</%s>)" % (tag, tag),
                       lambda m: m.group(1) + attr(t) + m.group(2), o, count=1)
    # Езикът е механичен, не се превежда.
    o = re.sub(r"(<dc:language[^>]*>)[^<]+(</dc:language>)",
               r"\1bg\2", o, count=1)
    with open(opf_path, "w", encoding="utf-8") as f:
        f.write(o)
    pair = meta.get("opf:dc:title")
    return pair[1] if pair else None


EPUB_NS = "http://www.idpf.org/2007/ops"
DOCTYPE3 = "<!DOCTYPE html>"
RE_DOCTYPE = re.compile(r"<!DOCTYPE[^>]*>", re.S)
RE_HTML_TAG = re.compile(r"<html\b[^>]*>")


def _epub3_head(s):
    """HTML5 DOCTYPE + epub пространството на имената. И двете са условие
    четецът да зачете epub:type изобщо.

    Заедно с това &nbsp; се заменя с &#160;. В EPUB 2 файловете носят DOCTYPE
    на XHTML 1.1 и този обект е дефиниран от DTD-то. С <!DOCTYPE html> обаче
    документът се чете като чист XML, където предефинирани са само &amp;,
    &lt;, &gt;, &quot; и &apos; — и &nbsp; става НЕВАЛИДЕН. В набора има 37
    такива места (най-вече „+ + +" по заглавните страници) и всяко едно би
    счупило разбора на файла. Числената форма значи същото и е винаги валидна."""
    s = s.replace("&nbsp;", "&#160;")
    s = RE_DOCTYPE.sub(DOCTYPE3, s, count=1)
    m = RE_HTML_TAG.search(s)
    if m and "xmlns:epub" not in m.group(0):
        s = s[:m.start()] + m.group(0)[:-1] + ' xmlns:epub="%s">' % EPUB_NS \
            + s[m.end():]
    return s


def to_epub3(oebps, dc_id):
    """Превръща книгата от EPUB 2 в EPUB 3 с ИЗСКАЧАЩИ БЕЛЕЖКИ.

    Смисълът е един: щракването върху бележка да НЕ отвежда никъде. В EPUB 3
    препратка с epub:type="noteref" към елемент с epub:type="footnote" се
    показва от четеца в малко прозорче върху текста. Няма отиване, значи няма
    и връщане — а точно връщането се разминаваше с една-две страници, защото
    в преформатиращ се текст „страница" не е записана в книгата, а се смята
    наново всеки път.

    Пропадането е меко: четец, който не разбира epub:type, просто следва
    връзката както досега. Затова промяната не може да влоши нищо.

    Прави се ЧАК тук и само при --epub3 — изходните книги и преводът не се
    пипат.
    """
    n_ref = n_note = 0

    for p in sorted(glob.glob(os.path.join(oebps, "Text", "*.xhtml"))):
        s = open(p, encoding="utf-8").read()
        orig = s
        s = _epub3_head(s)

        base = os.path.basename(p)
        if base.startswith("note") and base != "notes.xhtml":
            # Самата бележка: обвива се в <aside>, а котвата се мести върху
            # него — четецът показва в прозорчето точно елемента, към който
            # сочи връзката.
            m = re.search(r'<h1([^>]*)id="(note\d+)"([^>]*)>', s)
            if m:
                nid = m.group(2)
                s = s[:m.start()] + "<h1%s%s>" % (m.group(1), m.group(3)) \
                    + s[m.end():]
                body = re.search(r"(<body[^>]*>)(.*)(</body>)", s, re.S)
                s = (s[:body.start()] + body.group(1)
                     + '\n<aside epub:type="footnote" id="%s">' % nid
                     + body.group(2) + "</aside>\n" + body.group(3)
                     + s[body.end():])
                n_note += 1
        else:
            # Препратката към бележка.
            s, k = re.subn(r'<a href="([^"]*#note\d+)"',
                           r'<a epub:type="noteref" href="\1"', s)
            n_ref += k

        if s != orig:
            with open(p, "w", encoding="utf-8") as f:
                f.write(s)

    # --- nav.xhtml: задължителен в EPUB 3, прави се от toc.ncx ---
    ncx = open(os.path.join(oebps, "toc.ncx"), encoding="utf-8").read()
    root = ET.fromstring(ncx)
    ns = {"n": "http://www.daisy.org/z3986/2005/ncx/"}

    def build(points, depth):
        out = ["  " * depth + "<ol>"]
        for np in points:
            label = np.find("n:navLabel/n:text", ns).text or ""
            src = np.find("n:content", ns).get("src")
            kids = np.findall("n:navPoint", ns)
            out.append("  " * depth + '  <li><a href="%s">%s</a>'
                       % (src, attr(label)))
            if kids:
                out.append(build(kids, depth + 2))
            out.append("  " * depth + "  </li>")
        out.append("  " * depth + "</ol>")
        return "\n".join(out)

    nav_body = build(root.find("n:navMap", ns).findall("n:navPoint", ns), 1)
    title = root.find("n:docTitle/n:text", ns)
    nav = ('<!DOCTYPE html>\n<html xmlns="http://www.w3.org/1999/xhtml" '
           'xmlns:epub="%s" lang="bg" xml:lang="bg">\n<head>\n'
           '<meta charset="utf-8"/>\n<title>%s</title>\n</head>\n<body>\n'
           '<nav epub:type="toc" id="toc">\n%s\n</nav>\n</body>\n</html>\n'
           % (EPUB_NS, attr(title.text if title is not None else "Съдържание"),
              nav_body))
    with open(os.path.join(oebps, "nav.xhtml"), "w", encoding="utf-8") as f:
        f.write(nav)

    # --- content.opf: версия 3.0, nav в манифеста, задължителният dcterms ---
    opf_path = os.path.join(oebps, "content.opf")
    o = open(opf_path, encoding="utf-8").read()
    o = re.sub(r'(<package[^>]*)version="2\.0"', r'\1version="3.0"', o, count=1)
    if 'properties="nav"' not in o:
        o = re.sub(r'([ \t]*)</manifest>',
                   lambda m: '    <item href="nav.xhtml" id="nav" '
                             'media-type="application/xhtml+xml" '
                             'properties="nav"/>\n' + m.group(0), o, count=1)
    if "dcterms:modified" not in o:
        stamp = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
        o = re.sub(r'([ \t]*)</metadata>',
                   lambda m: '    <meta property="dcterms:modified">%s</meta>\n'
                             % stamp + m.group(0), o, count=1)
    with open(opf_path, "w", encoding="utf-8") as f:
        f.write(o)

    return n_ref, n_note


def pack(src_root, out_path):
    """mimetype ПЪРВИ и НЕкомпресиран — иначе .epub-ът не е валиден."""
    if os.path.exists(out_path):
        os.remove(out_path)
    with zipfile.ZipFile(out_path, "w", zipfile.ZIP_DEFLATED) as z:
        mt = os.path.join(src_root, "mimetype")
        if os.path.exists(mt):
            z.write(mt, "mimetype", compress_type=zipfile.ZIP_STORED)
        for root, _, files in os.walk(src_root):
            for fn in sorted(files):
                full = os.path.join(root, fn)
                rel = os.path.relpath(full, src_root)
                if rel == "mimetype":
                    continue
                z.write(full, rel)


def process(vol, dry, epub3=False):
    work = os.path.join(WORK_DIR, vol)
    src = os.path.join(work, "src")

    # Работи се върху КОПИЕ, не върху src/. Иначе сглобяването е еднопосочно:
    # веднъж заменен, руският текст го няма и второ пускане би вкарвало
    # българския превод в already български блокове. Копието се пресъздава
    # при всяко пускане, тъй че src/ остава чистият руски оригинал и
    # сглобяването може да се повтаря колкото пъти трябва.
    build = os.path.join(work, "build")
    if not dry:
        if os.path.isdir(build):
            shutil.rmtree(build)
        shutil.copytree(src, build)
        root = build
    else:
        root = src                     # при --dry-run нищо не се записва

    oebps = os.path.dirname(glob.glob(os.path.join(root, "**", "content.opf"),
                                      recursive=True)[0])

    n_ext = len(glob.glob(os.path.join(work, "extract", "*.json")))
    n_tr = len(glob.glob(os.path.join(work, "translated", "*.json")))
    print("  групи: преведени %d от %d" % (n_tr, n_ext))
    if n_tr < n_ext:
        print("  ✗ томът не е преведен докрай — пропускам")
        return

    blocks, meta = load_translations(work)
    # Преводите с ключ extra: се държат отделно — те не са блокове и се
    # адресират по пореден текстов възел, а не по номер на блок.
    extra = {k: v[1] for k, v in meta.items() if k.startswith("extra:")}
    notes_bg = note_translations(oebps, blocks)
    print("  блокове с превод: %d | бележки за title: %d | мета: %d | "
          "текст извън блокове: %d"
          % (len(blocks), len(notes_bg), len(meta) - len(extra), len(extra)))

    problems, touched = [], 0
    for path in sorted(glob.glob(os.path.join(oebps, "Text", "*.xhtml"))):
        rel = "Text/" + os.path.basename(path)
        out = rebuild_file(path, rel, blocks, notes_bg,
                           meta.get("html:title"), extra, problems)
        if out != open(path, encoding="utf-8").read():
            touched += 1
            if not dry:
                with open(path, "w", encoding="utf-8") as f:
                    f.write(out)
    print("  променени файлове: %d" % touched)

    if problems:
        print("  ✗ ПРОБЛЕМИ: %d" % len(problems))
        for p in problems[:8]:
            print("     %s" % p)
        print("  .epub НЕ е записан")
        return

    if dry:
        print("  (--dry-run: нищо не е записано)")
        return

    if fix_titlepage(oebps):
        print("  заглавната страница е приближена до корицата")

    if replace_cover(oebps, vol):
        print("  корица: българската от Covers_BG/%s.jpg" % vol[:2])

    n_font = embed_fonts(oebps)
    if n_font:
        print("  вградени шрифтове: %d (Charis SIL за основния текст)" % n_font)

    n_split = split_notes(oebps)
    if n_split:
        print("  бележки, изнесени в отделни файлове: %d" % n_split)

    # ВНИМАНИЕ на реда: apply_meta превежда toc.ncx, а to_epub3 прави
    # nav.xhtml ОТ него. Обърнати, съдържанието в EPUB 3 излиза на руски.
    title = apply_meta(oebps, meta)

    if epub3:
        n_ref, n_note = to_epub3(oebps, None)
        print("  EPUB 3: %d препратки noteref, %d бележки в <aside>"
              % (n_ref, n_note))
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    num = vol[:2]
    if num in MONTH_ABBR:
        name = NAME_TPL % (num, MONTH_ABBR[num])
    else:
        name = "%s.epub" % (title or vol)          # непознат том — по заглавие
    if epub3:
        name = name[:-len(".epub")] + " (EPUB3).epub"
    out_path = os.path.join(OUTPUT_DIR, name.replace("/", "-"))
    pack(root, out_path)

    # --- проверка на готовия файл ---
    with zipfile.ZipFile(out_path) as z:
        names = z.namelist()
        bad = z.testzip()
        first_ok = names[0] == "mimetype"
        ru = 0
        for n in names:
            if n.endswith(".xhtml"):
                t = z.read(n).decode("utf-8", "replace")
                ru += len(re.findall(r"[ыэё]", RE_TAG.sub("", t)))
    print("  → %s" % out_path)
    print("  файлове в архива: %d | mimetype пръв: %s | повреден запис: %s"
          % (len(names), "да" if first_ok else "НЕ", bad or "няма"))
    print("  останали руски букви (ы/э/ё) в текста: %d" % ru)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--vol")
    ap.add_argument("--all", action="store_true")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--epub3", action="store_true",
                    help="EPUB 3 с изскачащи бележки (експеримент)")
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
        process(v, args.dry_run, args.epub3)


if __name__ == "__main__":
    main()
