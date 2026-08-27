#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Прави assets/lives_index.json — указател номер → житие в томовете.

За какво е. В томовете по св. Димитрий Ростовски има 1342 кръстосани
препратки във вида `../zhitija-svjatykh/1143`, където числото е номерът на
статията в azbyka.ru. Същият номер стои и като `id` на заглавието на всяко
житие, тъй че съпоставянето е еднозначно и препратките могат да се отварят
ВЪТРЕ в приложението, вместо да водят навън.

⚠ Указателят се прави ТУК, а не в движение. Съставянето му иска обхождане
на дванайсетте архива по 2 MB — при отваряне на всяко житие това би било
видимо забавяне точно в мига, в който човек чака текст.

⚠ `id`-то има ДВЕ форми. Обикновено е голото число (`id="642"`), но при
първите единайсет жития на януари calibre е сложил свой знак за нова
страница и е презаписал атрибута (`id="calibre_pb_2"`). Номерът е същият —
сверено срещу сайта. Пропусне ли се тази форма, точно първите страници на
книгата остават без съответствие.

Пуска се наново, когато се прегенерират томовете:

    python3 tools/build_lives_index.py
"""

import glob
import json
import os
import re
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BOOKS = os.path.join(ROOT, 'assets', 'books')
OUT = os.path.join(ROOT, 'assets', 'lives_index.json')

RE_H1 = re.compile(r'<h1\b[^>]*\bid="(?:calibre_pb_)?(\d+)"[^>]*>(.*?)</h1>',
                   re.S)
RE_TAG = re.compile(r'<[^>]+>')
RE_REF = re.compile(r'href="\.\./zhitija-svjatykh/(\d+)"')

# ⚠ БЕЛЕЖКАТА ПОД ЛИНИЯ СЕ МАХА ЦЯЛА, преди да се свалят таговете.
#
# 64 от 1155 заглавия носят препратка към бележка ВЪТРЕ в самото <h1>.
# Номерът ѝ е ТЕКСТЪТ на връзката, тъй че голото сваляне на таговете го
# оставяше залепен за последната дума: „…архиепископ Сръбски245",
# „…Предтеча Господен 5295.". В книгата това е горен индекс и се чете
# правилно; в дневния изглед, където заглавието се показва като ред за
# второто и третото четиво по св. Димитрий Ростовски, излизаше гола цифра
# насред името.
#
# ⚠ СТРУКТУРНО, а не по цифри. Изкушението е регекс за „цифри в края" —
# но заглавията носят и ИСТИНСКИ числа („светите 42 мъченици", „с него
# 1318 воини", „1000-те и Азат", „3618-те мъченици"), а те не се различават
# от номер на бележка по вид. Различават се по МЯСТО: истинското число е
# гол текст, а номерът на бележката е съдържание на <a href="…noteN…">.
# Затова се маха елементът, не низът — така легитимно число не може да
# пострада, каквото и да е.
RE_NOTE_LINK = re.compile(
    r'<a\b[^>]*href="[^"]*note\d+[^"]*"[^>]*>.*?</a>', re.S | re.I)


def plain(s):
    s = re.sub(r'\s+', ' ', RE_TAG.sub('', RE_NOTE_LINK.sub('', s))).strip()
    # ⚠ Махнатата бележка оставя ДУПКА, ако е стояла пред пунктуация:
    # „…Предтеча Господен <a>5295</a>." става „…Предтеча Господен ." —
    # увиснал интервал пред точката. Свива се обратно.
    return re.sub(r'\s+([.,;:!?)»”])', r'\1', s)


def main():
    index, refs = {}, set()
    for path in sorted(glob.glob(os.path.join(BOOKS, '*.epub'))):
        book = os.path.basename(path)
        with zipfile.ZipFile(path) as z:
            for name in z.namelist():
                if '/Text/' not in name or not name.endswith('.xhtml'):
                    continue
                s = z.read(name).decode('utf-8', 'ignore')
                refs.update(RE_REF.findall(s))
                m = RE_H1.search(s)
                if not m:
                    continue
                num, title = m.group(1), plain(m.group(2))
                if num in index:
                    print('  ⚠ номер %s се среща втори път (%s и %s)'
                          % (num, index[num]['book'], book))
                    continue
                index[num] = {'book': book, 'href': name, 'title': title}

    with open(OUT, 'w', encoding='utf-8') as f:
        json.dump(index, f, ensure_ascii=False, indent=0, sort_keys=True)

    липсват = sorted(refs - set(index), key=int)
    print('=' * 60)
    print('жития в указателя: %d' % len(index))
    print('различни номера в препратките: %d' % len(refs))
    print('без съответствие: %d %s' % (len(липсват), липсват[:10]))
    print('→ %s (%.0f KB)' % (OUT, os.path.getsize(OUT) / 1024))


if __name__ == '__main__':
    main()
