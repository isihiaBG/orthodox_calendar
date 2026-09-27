"""Молитвеникът на Патриаршията (bg-patriarshia.bg/liturgical-prayer) → блокове.

    cache/bgp/*.html  →  work/bg_pages/bgp__<страница>.json
      [ {"i": 0, "kind": "head"|"rubric"|"text", "text": "…"} ]

Същият вид като 03_parse_bg.py, тъй че картата (input/map_prayers.csv) сочи
двата сайта еднакво — по името на страницата.

Устройството (сверено на „Причастни молитви"):

    <div class="col-12 col-lg-8">   самото съдържание; всичко преди е менюто
    <h2>, <address>                 заглавие (молитва, псалом, дял)
    <p><em>…</em></p>               указание (винено)
    <p>                             абзац

⚠ Причастните молитви тук са ПЪЛНИ (канонът и всичките 11 молитви), за
разлика от съкратеното на pravoslavieto.com. (Източникът е посочен от
потребителя, 27.09.2026.)
"""
import glob
import html
import json
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, 'cache', 'bgp')
OUT = os.path.join(ROOT, 'work', 'bg_pages')

RE_ITEM = re.compile(r'<(h[1-6]|address|p)\b[^>]*>(.*?)</\1>', re.S | re.I)


def flat(s: str) -> str:
    s = re.sub(r'<br\s*/?>', ' ', s, flags=re.I)
    s = re.sub(r'<[^>]+>', '', s)
    s = html.unescape(s).replace('\xa0', ' ')
    return re.sub(r'\s+', ' ', s).strip()


def parse(t: str) -> list:
    i = t.find('class="col-12 col-lg-8"')
    if i < 0:
        return []
    t = t[i:]
    # край: първият странична колона / подвал
    for stop in ('class="col-12 col-lg-4"', '<footer'):
        j = t.find(stop)
        if j > 0:
            t = t[:j]
            break
    blocks = []
    for m in RE_ITEM.finditer(t):
        tag, inner = m.group(1).lower(), m.group(2)
        text = flat(inner)
        if not text:
            continue
        if tag != 'p':
            kind = 'head'
        elif re.fullmatch(r'\s*<(em|i)>.*</\1>\s*', inner, re.S | re.I):
            kind = 'rubric'
        else:
            kind = 'text'
        blocks.append({'i': len(blocks), 'kind': kind, 'text': text})
    return blocks


def main():
    os.makedirs(OUT, exist_ok=True)
    for path in sorted(glob.glob(os.path.join(SRC, '*.html'))):
        name = os.path.basename(path)[:-5]
        if name == 'index':
            continue
        blocks = parse(open(path, encoding='utf-8', errors='replace').read())
        json.dump(blocks, open(os.path.join(OUT, 'bgp__%s.json' % name), 'w', encoding='utf-8'),
                  ensure_ascii=False, indent=1)
        heads = sum(1 for b in blocks if b['kind'] == 'head')
        print('%4d блока (%3d заглавия)  %s' % (len(blocks), heads, name))


if __name__ == '__main__':
    main()
