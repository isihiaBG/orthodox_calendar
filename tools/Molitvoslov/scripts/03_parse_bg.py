"""Страниците на pravoslavieto.com (cache/bg/*.htm) → поредица от блокове.

    → work/bg_pages/<страница>.json
      [ {"i": 0, "kind": "head"|"rubric"|"text", "text": "…"} ]

Устройството на страниците (сверено на „Начални молитви" и „Вечерни молитви"):

    <h2>/<h4>                 заглавие                 → head
    <span class="note">       указание                 → rubric (винено)
    <table id=AutoNumberN><td>  текстът на молитвата   → text, по <p>
                              (номерът е различен по страници; заглавката със
                              знака на сайта се познава по logo.gif)
    <div CLICKFOR=…>          скрито ОБЯСНЕНИЕ: речниче, тълкуване,
                              картинка с цс текста     → ПРОПУСКА СЕ
    <p class="content">       също обяснение           → пропуска се

⚠ `<br>` дели СМИСЛОВИ редове, а не абзаци — става интервал. Абзацът е `<p>`.
Цс текстът в приложението също е проза, тъй че двете колони изглеждат еднакво.

⚠ Кодировката е РАЗЛИЧНА по страници — едни са utf-8, други windows-1251 —
и `meta charset` на някои лъже. Пробва се utf-8 и чак после 1251.
"""
import glob
import html
import json
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, 'cache', 'bg')
OUT = os.path.join(ROOT, 'work', 'bg_pages')


def read(path: str) -> str:
    raw = open(path, 'rb').read()
    try:
        return raw.decode('utf-8')
    except UnicodeDecodeError:
        return raw.decode('cp1251', errors='replace')


def flat(s: str) -> str:
    s = re.sub(r'<br\s*/?>', ' ', s, flags=re.I)
    s = re.sub(r'<[^>]+>', '', s)
    s = html.unescape(s).replace('\xa0', ' ')
    return re.sub(r'\s+', ' ', s).strip()


def strip_hidden(t: str) -> str:
    """Маха скритите обяснения <div CLICKFOR…>…</div>, с вложените div-ове."""
    out, i = [], 0
    low = t.lower()
    while True:
        j = low.find('<div clickfor', i)
        if j < 0:
            out.append(t[i:])
            break
        out.append(t[i:j])
        depth, k = 0, j
        while k < len(t):
            if low.startswith('<div', k):
                depth += 1
                k += 4
            elif low.startswith('</div', k):
                depth -= 1
                k += 5
                if depth == 0:
                    k = low.find('>', k) + 1
                    break
            else:
                k += 1
        i = k
    return ''.join(out)


RE_ITEM = re.compile(
    r'<h[2-6][^>]*>(?P<h>.*?)</h[2-6]>'
    r'|<span\s+class="?note"?[^>]*>(?P<n>.*?)</span>'
    r'|<table[^>]*AutoNumber\d+[^>]*>(?P<t>.*?)</table>',
    re.S | re.I)


RE_FOREIGN = re.compile(r'[ыэѣЫЭѢ]')


def parse(t: str) -> list:
    body = re.search(r'<body[^>]*>(.*)</body>', t, re.S | re.I)
    t = body.group(1) if body else t
    t = strip_hidden(t)
    # ⚠ <p class="content"> (обяснения) НЕ се махат с регекс: част от тях са
    # НЕЗАТВОРЕНИ и `.*?</p>` поглъщаше чак до следващия абзац — така изчезна
    # „Царю небесни". Обясненията живеят в скритите div-ове, махнати по-горе,
    # а останалите стоят във ВТОРАТА клетка на таблицата, която не се чете.
    blocks = []

    def add(kind, text):
        if text:
            blocks.append({'i': len(blocks), 'kind': kind, 'text': text})

    for m in RE_ITEM.finditer(t):
        if m.group('h') is not None:
            h = flat(m.group('h'))
            if h and h != 'Православен молитвослов':
                add('head', h)
        elif m.group('n') is not None:
            add('rubric', flat(m.group('n')))
        else:
            if 'logo.gif' in m.group('t'):
                continue                  # заглавката на сайта
            # ⚠ Клетката свършва при </td>, при СЛЕДВАЩА клетка или при края на
            # реда: част от страниците не затварят <td> (50-ият псалом).
            cell = re.search(r'<td[^>]*>(.*?)(?=</td>|<td\b|</tr>|$)',
                             m.group('t'), re.S | re.I)
            if not cell:
                continue
            # ⚠ Двойното <br><br> отделя НОВА молитва вътре в един абзац
            # („Просвети очите ми" е долепен до молитвата на св. Йоан
            # Дамаскин, „Огради ме" — до тази към Кръста).
            for para in re.split(r'<p[^>]*>|<br\s*/?>\s*<br\s*/?>', cell.group(1), flags=re.I):
                text = flat(para)
                # ⚠ Руски/цс редове (цитатите на оригинала) се отсяват по
                # буквите, които българският НЯМА — единственият сигурен признак.
                if RE_FOREIGN.search(text):
                    continue
                add('text', text)
    return blocks


def main():
    os.makedirs(OUT, exist_ok=True)
    for path in sorted(glob.glob(os.path.join(SRC, '*.htm'))):
        name = os.path.basename(path)[:-4]
        blocks = parse(read(path))
        json.dump(blocks, open(os.path.join(OUT, name + '.json'), 'w', encoding='utf-8'),
                  ensure_ascii=False, indent=1)
        print('%4d блока  %s' % (len(blocks), name))


if __name__ == '__main__':
    main()
