#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Добавя „ѝ" (U+045D) и „Ѝ" (U+040D) в Tamburin Modern.

За какво е. Заглавието на четивото се пише с Tamburin
(`lib/reader_theme.dart`, `kTitleFamily`), но шрифтът покрива само 229
знака и няма нито „ѝ", нито „Ѝ". Без резервен шрифт Flutter сам решава с
какво да ги замени — обикновено системният, изправен и по-едър, в явен спор
със стила на Tamburin (виж коментара за `kTitleFallback` в
`reader_theme.dart`). Резервът върши работа, но смесва два шрифта в един
надпис; тук вместо това ги ВГРАЖДАМЕ в самия Tamburin.

Как. Tamburin няма нито един СЪСТАВЕН глиф (проверено — целият шрифт е на
ръка изчертани контури), тъй че няма готов „и + ударение" за копиране. Затова
двата нови знака се сглобяват геометрично от съществуващи парчета:

    ѝ = afii10074 (и) + grave, центрирано отгоре
    Ѝ = afii10026 (И) + grave, центрирано отгоре, изместено по-нависоко

`grave` вече Е в шрифта — картографиран на обратната кавичка `` ` `` (U+0060,
клавишът горе вляво), не е добавен тук. Ползва се самò, без промяна на
формата му.

⚠ Комбиниращото ударение U+0301 (среща се веднъж, в „Тео́фил") НЕ е тук.
В шрифта няма никакъв елемент за акутно ударение — нито `acute` (U+00B4),
нито каквото и да е друго, годно да мине за такова без огледално обръщане
на `grave` (а то би излязло неубедително при калиграфски шрифт с чувствителна
дебелина на щриха). Остава на резервния Charis SIL, както си беше.

Вертикалното място на новия акцент: 25/1000 em луфт над върха на буквата,
освен ако собственото положение на `grave` вече е по-високо (случаят при
малкото „ѝ" — там почти не се мести). Хоризонтално — центрирано спрямо
буквата. Виж `_състави()` за точната сметка.

Идемпотентен е: пуснат втори път, не добавя нищо повторно.

Употреба:
    python3 tools/fonts/patch_tamburin_izh.py
    python3 tools/fonts/patch_tamburin_izh.py --dry-run
"""

import argparse
import os
import shutil
import time

from fontTools.ttLib import TTFont
from fontTools.ttLib.tables._g_l_y_f import Glyph, GlyphComponent

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
ШРИФТ = os.path.join(ROOT, 'assets', 'fonts', 'Tamburin Modern.ttf')

ЛУФТ = 25  # 1/1000 em луфт между върха на буквата и долния ръб на акцента

# (име на новия глиф, базова буква, юникод)
ДВОЙКИ = [
    ('afii10074.grave', 'afii10074', 0x045D),  # ѝ = и + `
    ('afii10026.grave', 'afii10026', 0x040D),  # Ѝ = И + `
]
ДИАКРИТИК = 'grave'


def _състави(glyf, база, диакритик):
    б, д = glyf[база], glyf[диакритик]

    dx = round((б.xMin + б.xMax) / 2 - (д.xMin + д.xMax) / 2)
    dy = max(0, round(б.yMax + ЛУФТ - д.yMin))

    нов = Glyph()
    нов.numberOfContours = -1
    нов.xMin = min(б.xMin, д.xMin + dx)
    нов.yMin = min(б.yMin, д.yMin + dy)
    нов.xMax = max(б.xMax, д.xMax + dx)
    нов.yMax = max(б.yMax, д.yMax + dy)
    нов.components = []

    к1 = GlyphComponent()
    к1.glyphName, к1.x, к1.y, к1.flags = база, 0, 0, 0x0004
    к2 = GlyphComponent()
    к2.glyphName, к2.x, к2.y, к2.flags = диакритик, dx, dy, 0x0004
    нов.components = [к1, к2]
    return нов


def кърпи(път=ШРИФТ, пиши=True):
    f = TTFont(път)
    glyf, hmtx, cmap = f['glyf'], f['hmtx'], f['cmap']

    if ДИАКРИТИК not in glyf.glyphOrder:
        raise SystemExit('няма глиф „%s" в шрифта — нищо за сглобяване'
                          % ДИАКРИТИК)

    направени = []
    for ново_име, база, юник in ДВОЙКИ:
        вече_има = any(юник in т.cmap for т in cmap.tables)
        if вече_има:
            print('  U+%04X вече присъства — пропускам' % юник)
            continue
        нов = _състави(glyf, база, ДИАКРИТИК)
        glyf[ново_име] = нов
        hmtx[ново_име] = hmtx[база]
        for т in cmap.tables:
            т.cmap[юник] = ново_име
        направени.append('U+%04X (%s) <- %s + %s' % (юник, chr(юник), база, ДИАКРИТИК))

    if not направени:
        print('нищо ново — шрифтът вече е кърпен')
        return

    for р in направени:
        print('  + %s' % р)

    if пиши:
        щампа = time.strftime('%Y%m%d_%H%M%S')
        shutil.copy2(път, '%s.bak-%s' % (път, щампа))
        glyf.compile(f)
        f.save(път)
        print('записано: %s' % път)
    else:
        print('(--dry-run — нищо не е записано)')


if __name__ == '__main__':
    ap = argparse.ArgumentParser()
    ap.add_argument('--dry-run', action='store_true')
    args = ap.parse_args()
    кърпи(пиши=not args.dry_run)
