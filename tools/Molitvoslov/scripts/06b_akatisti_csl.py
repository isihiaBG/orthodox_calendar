"""Трите основни акатиста в ЦЪРКОВНОСЛАВЯНСКИ ШРИФТ → work/akatisti_csl.json.

    input/akafist_csl/<страница>.html   (свалени от azbyka.ru, кодиране Ucs)

azbyka.ru дава в цс шрифт само трите основни акатиста — към Богородица, към
Иисус Христос и към св. Николай (раздел „Церковнославянский шрифт" на
молитвослова). Текстът е в кодирането Ucs и минава през СЪЩИЯ `ucs.py`, с
който се разчита цс молитвословът.

⚠ Страниците носят само акатиста и молитвите — канона (песни 1–9) го няма.
Затова `06_akatisti.py` сдвоява ПО ВИД И НОМЕР (кондак/икос N), а не по ред:
    тропар            → нова единица най-отпред (Канонникът го няма тук)
    кондак N / икос N → едноименната единица
    повторените накрая Икос 1 и Кондак 1 → при Кондак 13 (Канонникът дава
                        само първите им думи, страницата — целите)
    молитва k         → k-тата „Молитва" по ред
"""
import html
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(__file__))
import ucs  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
IN = os.path.join(ROOT, 'input', 'akafist_csl')
OUT = os.path.join(ROOT, 'work', 'akatisti_csl.json')

PAGES = {
    101: 'akafist-sladchajshemu-gospodu-nashemu-iisusu-hristu',
    102: 'akafist-prechistoj-vladychice-nashej-bogorodice',
    103: 'akafist-svjatitelju-nikolaju-chudotvorcu',
}
URL = 'https://azbyka.ru/molitvoslov/%s-cerkovnoslavjanskim-shriftom.html'

MARKS = re.compile('[̀-ͯ҃-҉ⷠ-ⷿ꙯-ꙿ]')
# Цс числата: буква + титла; „а҃і" = 11 и т.н.
DIGIT = {'а': 1, 'в': 2, 'г': 3, 'д': 4, 'є': 5, 'ѕ': 6, 'з': 7, 'и': 8,
         'ѳ': 9, 'і': 10}
RE_RUBRIC_P = re.compile(r'^(?:Се́й конда́къ|И҆ па́ки:?$|Та́же)')
RE_ITEM = re.compile(r'<(h3|p)\b[^>]*>(.*?)</\1>', re.S)


def plain(s):
    return html.unescape(re.sub(r'<[^>]+>', '', s)).strip()


def cs_number(word):
    """„в҃і" → 12, „г҃" → 3."""
    letters = [c for c in MARKS.sub('', word) if c in DIGIT]
    return sum(DIGIT[c] for c in letters) or None


def key_of(title):
    t = MARKS.sub('', title).lower()
    m = re.search(r'(кондакъ|ікосъ|икосъ)\s+(\S+?)[.,:]', t + '.')
    if m:
        kind = 'kondak' if m.group(1).startswith('конд') else 'ikos'
        return (kind, cs_number(m.group(2)))
    if 'тропарь' in t:
        return ('troparion', 0)
    if t.startswith('млтв'):
        return ('prayer', 0)
    return None


def para_html(inner):
    """Абзац → текст в Unicode; буквицата (<span class="letter">) се слива с
    думата — четецът сам оцветява първата буква."""
    inner = re.sub(r'<span class="letter">(.*?)</span>', r'\1', inner, flags=re.S)
    return ucs.decode(plain(inner))


RAW = []


def slavic_div(t):
    """Само вътрешността на <div class="slavic"> — по ВЛОЖЕНОСТТА на div-овете.

    ⚠ Отрязано „от началото до края на файла", след последната молитва
    влизаше обзавеждането на сайта („Пожертвовать", „к содержанию", броячите),
    при това прекарано през Ucs таблицата — тоест като безсмислица."""
    start = t.find('<div class="slavic">')
    depth, i = 0, start
    for m in re.finditer(r'<(/?)div\b', t[start:]):
        depth += -1 if m.group(1) else 1
        if depth == 0:
            return t[start:start + m.start()]
    return t[start:]


def parse(page):
    t = open(os.path.join(IN, page + '.html'), encoding='utf-8').read()
    body = slavic_div(t)
    units, cur, seen, prayer_n = [], None, set(), 0
    for m in RE_ITEM.finditer(body):
        tag, inner = m.group(1), m.group(2)
        if tag == 'h3':
            if 'slavic' not in m.group(0)[:30]:
                continue
            title = ucs.decode(plain(inner)).rstrip(':')
            if not title:
                continue
            key = key_of(title)
            if key and key[0] == 'prayer':
                prayer_n += 1
                key = ('prayer', prayer_n)
            repeat = key in seen and key[0] in ('kondak', 'ikos')
            if key:
                seen.add(key)
            cur = {'title': title, 'key': list(key) if key else None,
                   'repeat': repeat, 'blocks': []}
            units.append(cur)
            continue
        if cur is None:
            continue
        RAW.append(plain(re.sub(r'<span class="letter">(.*?)</span>', r'\1', inner)))
        txt = para_html(inner)
        if txt:
            # ⚠ Указанията („Се́й конда́къ глаго́ли три́жды.", „И҆ па́ки:")
            # стоят в страницата като обикновен абзац — тук стават винени.
            kind = 'rubric' if RE_RUBRIC_P.match(txt) else 'text'
            cur['blocks'].append({'kind': kind, 'html': html.escape(txt, quote=False)})
    return units


def main():
    out = {}
    for sid, page in PAGES.items():
        RAW.clear()
        units = parse(page)
        out[str(sid)] = {'source': URL % page, 'units': units}
        print('  %d  %2d единици, %3d абзаца  (повторени: %s)' % (
            sid, len(units), sum(len(u['blocks']) for u in units),
            [u['title'] for u in units if u['repeat']]))
        # ⚠ Проверява се СУРОВИЯТ текст — декодираният е пълен с „непознати"
        # по определение (истинските цс знаци).
        unknown = ucs.unknown_chars(''.join(RAW))
        if unknown:
            print('     ⚠ непознати знаци:', unknown)
    json.dump(out, open(OUT, 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
    print('→', OUT)


if __name__ == '__main__':
    main()
