"""Цс молитвословът (work/csl_book.html, от 01) → раздели и отделни молитви.

    → work/csl_units.json
      [ { "sec": 1, "title": "Мл҃твы ѹ҆́трєннїѧ.",
          "units": [ { "n": 0, "title": null | "Мл҃тва мытарѧ̀:",
                       "blocks": [ {"kind": "text"|"rubric", "html": "…"} ] } ] } ]

ЕДИНИЦАТА Е МОЛИТВАТА (<h3>). Текстът преди първото <h3> на раздела влиза в
единица без заглавие (n = 0) — там стоят уводните указания („Воспрѧнꙋ́въ без̾
лѣ́ности…").

⚠ Разделите се познават по котвата <a name="N"/> в <h2>, а НЕ по самото <h2>:
„Канѡ́нъ, гла́съ в҃." е <h2> без котва и е ЧАСТ от последованието към
причастие. Тук той става заглавие на единица, както всяко <h3>.

⚠ Абзац, който е ИЗЦЯЛО указание (само <span class="rubric">), е блок
„rubric"; указание насред текста остава вътре в „text" като span — така
четецът го рисува винено на място, без да се губи редът на думите.
"""
import json
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, 'work', 'csl_book.html')
OUT = os.path.join(ROOT, 'work', 'csl_units.json')

RE_ITEM = re.compile(r'<(h2|h3|p)\b[^>]*>(.*?)</\1>', re.S)
RE_ANCHOR = re.compile(r'<a name="(\d+)"\s*/>')
RE_ONLY_RUBRIC = re.compile(r'^\s*<span class="rubric">((?:(?!<span).)*?)</span>\s*$', re.S)


def clean(s: str) -> str:
    s = RE_ANCHOR.sub('', s)
    s = re.sub(r'\s+', ' ', s).strip()
    return s


def plain(s: str) -> str:
    return re.sub(r'<[^>]+>', '', s).strip()


def main():
    src = open(SRC, encoding='utf-8').read()
    sections, sec, unit = [], None, None

    for m in RE_ITEM.finditer(src):
        tag, inner = m.group(1), m.group(2)
        anchor = RE_ANCHOR.search(inner)
        if tag == 'h2' and anchor:
            sec = {'sec': int(anchor.group(1)), 'title': plain(clean(inner)),
                   'units': []}
            sections.append(sec)
            unit = None
            continue
        if sec is None:
            continue                      # съдържанието най-отгоре
        if tag in ('h2', 'h3'):
            unit = {'n': len(sec['units']) + 1 if sec['units'] or unit else 1,
                    'title': plain(clean(inner)), 'blocks': []}
            sec['units'].append(unit)
            continue
        body = clean(inner)
        if not plain(body):
            continue
        if unit is None:                  # уводът преди първото заглавие
            unit = {'n': 0, 'title': None, 'blocks': []}
            sec['units'].append(unit)
        r = RE_ONLY_RUBRIC.match(body)
        if r:
            unit['blocks'].append({'kind': 'rubric', 'html': r.group(1).strip()})
        else:
            unit['blocks'].append({'kind': 'text', 'html': body})

    # номерата наново, за да са поредни и без дупки
    for s in sections:
        k = 0
        for u in s['units']:
            if u['title'] is None:
                u['n'] = 0
            else:
                k += 1
                u['n'] = k

    json.dump(sections, open(OUT, 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
    print('→', OUT)
    for s in sections:
        nb = sum(len(u['blocks']) for u in s['units'])
        print('  %2d  %3d молитви  %4d блока  %s' % (s['sec'], len(s['units']), nb, s['title'][:60]))


if __name__ == '__main__':
    main()
