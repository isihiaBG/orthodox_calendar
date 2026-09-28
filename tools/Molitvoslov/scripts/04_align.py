"""Цс молитвите + българските блокове → подравнени по МОЛИТВА.

    work/csl_units.json  +  work/bg_pages/*.json  +  input/map_prayers.csv
      → work/aligned.json
      → отчет за преглед: какво е хванал всеки ред от картата

КАРТАТА Е ИЗРИЧНА (input/map_prayers.csv), не се гади по заглавия: на
pravoslavieto.com заглавията са непоследователни (h2 / h4 / никакви), а
засичането по име вече е струвало скъпо в този проект.

Всеки ред сочи ОБХВАТ от блокове на една бг страница — от блока, който
започва с `first`, до блока, който започва с `last` (празно = само един блок).
Една цс молитва може да има НЯКОЛКО реда: частите се слепват по реда им
(„И тази молитва към Пресвета Троица" е на една страница, „Дойдете да се
поклоним" — на друга).

⚠ Търсенето на `first` тръгва от мястото, където е спрял ПРЕДИШНИЯТ ред на
същата страница — изразите се повтарят („Слава на Отца" стои няколко пъти), а
редът на молитвите в двата извора съвпада. Не се ли намери напред, търси се
от началото и това се съобщава.

⚠ Празен `title_bg` значи „без заглавие" — само за увода на раздела (n = 0).
"""
import csv
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
W = os.path.join(ROOT, 'work')


def load_page(name, cache={}):
    if name not in cache:
        # Пълното име (bgp__…, molitvi__…) има превес; голото се търси като
        # страница на pravoslavieto.com, после по окончание.
        path = os.path.join(W, 'bg_pages', '%s.json' % name)
        if not os.path.exists(path):
            path = os.path.join(W, 'bg_pages', 'molitvi__%s.json' % name)
        if not os.path.exists(path):
            for alt in os.listdir(os.path.join(W, 'bg_pages')):
                if alt.endswith('__%s.json' % name):
                    path = os.path.join(W, 'bg_pages', alt)
                    break
        cache[name] = json.load(open(path, encoding='utf-8'))
    return cache[name]


def page_url(name):
    """Адресът на страницата — за посочването на източника в четеца."""
    if name.startswith('bgp__'):
        return 'https://bg-patriarshia.bg/liturgical-prayer/' + name[5:]
    base = name[len('molitvi__'):] if name.startswith('molitvi__') else name
    return 'https://www.pravoslavieto.com/molitvoslov/molitvi/%s.htm' % base


def find(blocks, phrase, start):
    for b in blocks[start:]:
        if b['text'].startswith(phrase):
            return b['i']
    return None


def main():
    csl = json.load(open(os.path.join(W, 'csl_units.json'), encoding='utf-8'))
    rows = list(csv.DictReader(open(os.path.join(ROOT, 'input', 'map_prayers.csv'), encoding='utf-8')))

    by_unit, titles, notes, sources = {}, {}, {}, {}
    cursor, problems = {}, 0
    for r in rows:
        key = (int(r['sec']), int(r['n']))
        page = load_page(r['page'])
        start = cursor.get(r['page'], 0)
        a = find(page, r['first'], start)
        if a is None:
            a = find(page, r['first'], 0)
            if a is not None:
                print('  ⚠ %s/%s: „%s" намерено ПРЕДИ курсора' % (key + (r['first'],)))
        if a is None:
            print('  ✗ %s/%s: няма „%s" в %s' % (key + (r['first'], r['page'])))
            problems += 1
            continue
        b = a if not r['last'] else find(page, r['last'], a)
        if b is None:
            print('  ✗ %s/%s: няма края „%s" след блок %d' % (key + (r['last'], a)))
            problems += 1
            continue
        cursor[r['page']] = b + 1
        # ⚠ Заглавията вътре в обхвата отпадат (цс заглавието казва същото);
        # заглавие, посочено САМО като обхват, влиза като указание — у
        # Патриаршията началото на помянника е <h2>, а по смисъл е указание.
        if a == b and page[a]['kind'] == 'head':
            part = [dict(kind='rubric', text=page[a]['text'])]
        else:
            part = [dict(kind=x['kind'], text=x['text'])
                    for x in page[a:b + 1] if x['kind'] != 'head']
        by_unit.setdefault(key, []).extend(part)
        url = page_url(r['page'])
        if url and url not in sources.setdefault(key, []):
            sources[key].append(url)
        if r['title_bg']:
            titles[key] = r['title_bg']
        if r['note']:
            notes[key] = r['note']

    out, missing = [], 0
    for s in csl:
        units = []
        for u in s['units']:
            key = (s['sec'], u['n'])
            if key not in by_unit and s['sec'] in {k[0] for k in by_unit}:
                missing += 1
                print('  · %s/%s без бг: %s' % (key + ((u['title'] or '(увод)')[:50],)))
            units.append({'n': u['n'], 'title_csl': u['title'], 'title_bg': titles.get(key),
                          'csl': u['blocks'], 'bg': by_unit.get(key, []),
                          'note': notes.get(key), 'sources': sources.get(key, [])})
        out.append({'sec': s['sec'], 'title_csl': s['title'], 'units': units})

    json.dump(out, open(os.path.join(W, 'aligned.json'), 'w', encoding='utf-8'),
              ensure_ascii=False, indent=1)

    # отчетът за преглед — за разделите, които вече имат карта
    for s in out:
        if not any(u['bg'] for u in s['units']):
            continue
        print('\n=== %d  %s' % (s['sec'], s['title_csl'][:60]))
        for u in s['units']:
            bg = u['bg']
            first = bg[0]['text'][:48] if bg else '—'
            last = bg[-1]['text'][:30] if len(bg) > 1 else ''
            flag = '  ⚑ ' + u['note'] if u['note'] else ''
            print('  %2d  цс %2d бл. | бг %2d бл.  %s … %s%s' % (
                u['n'], len(u['csl']), len(bg), first, last, flag))
    print('\n→ work/aligned.json   проблеми: %d   без бг: %d' % (problems, missing))
    sys.exit(1 if problems else 0)


if __name__ == '__main__':
    main()
