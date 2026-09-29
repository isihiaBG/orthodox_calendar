#!/usr/bin/env python3
"""Ирмологий (част 1) → work/irmologii.json — последната от богослужебните книги.

    python3 10_irmologii.py        # после 05_build_db.py

⚠ Книгата е на ЦЪРКОВНОСЛАВЯНСКИ С ГРАЖДАНСКИ ШРИФТ (с ударения) — езикът е
`csr`, НЕ `csl`. За разлика от останалите богослужебни книги тук НЯМА Ucs и
текстът не минава през `ucs.decode`. Не се превежда (решение на
потребителя); превеждат се само ЗАГЛАВИЯТА в съдържанието — по същия кеш
като другите книги (`work/bogosl_titles_bg.json`).

Устройството на извора (azbyka.ru, calibre):
  <h2>…</h2>                          заглавие на главата
  <p><span>Песнь 1</span></p>         нова ПЕСЕН → заглавие на молитва
  <p><span>Святых Богоявлений:</span></p>  указание → червен ред
  <p><span>На 8:</span> Тогда́ …</p>  указание в началото на текста
  <p>…</p>                            текст
"""
import html
import importlib.util
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
W = ROOT / 'work'
SRC_FILE = ROOT / 'input' / 'newBooks2' / 'Ирмологий. Часть 1_ Богородичны всего лета.gen.epub'
SRC = 'https://azbyka.ru/otechnik/Pravoslavnoe_Bogosluzhenie/irmologij-bogorodichny-vsego-leta/'
BOOK = 'Ирмологий'
FIRST_ID = 2001        # богослужебните книги са 1001…; тук — отделен обхват

spec = importlib.util.spec_from_file_location('b09', Path(__file__).with_name('09_bogosluzhebni.py'))
b09 = importlib.util.module_from_spec(spec)
spec.loader.exec_module(b09)

RE_P = re.compile(r'<p\b[^>]*>(.*?)</p>', re.S)
RE_LEAD = re.compile(r'^\s*<span[^>]*>(.*?)</span>\s*(.*)$', re.S)


def plain(h):
    return html.unescape(re.sub(r'<[^>]+>', '', h)).replace('\xa0', ' ').strip()


def units_of(body):
    units = [{'title': None, 'blocks': []}]
    for inner in RE_P.findall(body):
        m = RE_LEAD.match(inner)
        if m and not plain(m.group(2)):
            lab = re.sub(r'\s+', ' ', plain(m.group(1)))
            if not lab:
                continue
            if re.fullmatch(r'Пе́?снь \d+', lab):
                units.append({'title': lab, 'blocks': []})
            else:
                units[-1]['blocks'].append({'kind': 'rubric', 'html': html.escape(lab, quote=False)})
            continue
        if m:
            lab = re.sub(r'\s+', ' ', plain(m.group(1)))
            txt = re.sub(r'\s+', ' ', plain(m.group(2)))
            h = '<span class="rubric">%s</span> %s' % (html.escape(lab, quote=False),
                                                      html.escape(txt, quote=False))
        else:
            txt = re.sub(r'\s+', ' ', plain(inner))
            if not txt:
                continue
            h = html.escape(txt, quote=False)
        units[-1]['blocks'].append({'kind': 'text', 'html': h})
    return [u for u in units if u['blocks']]


def main():
    raw = []
    for label, body in b09.chapters(SRC_FILE):
        us = units_of(body)
        # Заглавната страница и обвивките („Ирмологий часть 1") нямат текст.
        if not any(b['kind'] == 'text' for u in us for b in u['blocks']):
            continue
        raw.append((label, us))
    titles = b09.translate_titles([r[0] for r in raw])
    out = []
    for i, (label, us) in enumerate(raw):
        tbg = titles.get(label, label).strip().rstrip('.')
        out.append({'sec': FIRST_ID + i, 'tab': 'bogosluzhebni', 'book': BOOK, 'grp': None,
                    'title_bg': tbg, 'title_csl': None, 'csr_source': SRC, 'csl_source': None,
                    'units': [{'n': k, 'title_csl': u['title'], 'title_bg': None, 'title_cs': None,
                               'csr': u['blocks'], 'csl': [], 'bg': [], 'sources': []}
                              for k, u in enumerate(us)]})
    if not out:
        sys.exit('⚠ нищо не е разчетено')
    (W / 'irmologii.json').write_text(json.dumps(out, ensure_ascii=False, indent=1),
                                      encoding='utf-8')
    print('→ work/irmologii.json: %d глави, %d блока' % (
        len(out), sum(len(u['csr']) for s in out for u in s['units'])))
    for s in out:
        print('  ', s['title_bg'])


if __name__ == '__main__':
    main()
