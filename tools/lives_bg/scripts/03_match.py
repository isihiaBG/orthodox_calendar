#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Съпоставя българските светии от календара със страниците в сайта.

Изход: `work/candidates.json` + четим отчет `work/match_report.md`.

⚠ ДАТАТА Е ВОДЕЩА, името — второстепенно. Обратното не работи: в сайта един и
същ светия стои под друго прозвище („Ромил Видински" / „Romil_Bdinski") или
със съкратено име („Димитрий Сливенски" / „D_Slivenski"). Датата ги хваща и
двете, а името само ги подрежда, когато на един ден има няколко кандидата.

⚠ Затова пък датата сама по себе си НЕ СТИГА: на 15 януари сайтът има четири
жития, от които две са наши. Оттам и двустепенното решение — първо ден, после
прилика ВЪТРЕ в деня. Същият похват като в `tools/match_dmitry_lives`.

⚠ Прозорецът е ±1 ден, не точен. Различните извори понякога слагат паметта с
ден разлика, а сгрешена с ден дата е много по-вероятна от съвпадение на двама
непознати светии със същото име в съседни дни.

Ръчните решения се вписват в `input/manual_map.csv` (колони: key,path,note) и
имат ПРЕВЕС над всичко — там отиват случаите, които засечката не хваща.
"""

from __future__ import annotations

import csv
import json
from datetime import date, timedelta
from difflib import SequenceMatcher

from common import INPUT, WORK, fold, name_tokens

# Под този праг двойката не се смята за същия светия дори в един и същи ден.
# Нагласен емпирично: истинските съвпадения („Онуфрий Габровски" срещу
# „Onufrij Gabrovski" през транслитерацията) излизат много над него.
MIN_SCORE = 0.34
DAY_WINDOW = 1


def similarity(saint: dict, page: dict) -> float:
    """Колко си приличат имената — по ДВЕ мерки, взима се по-добрата.

    Едната сравнява българското име със заглавието на страницата (то също е
    на български), другата — транслитерираното с латинското име на файла.
    Двете хващат различни случаи: заглавието понякога е пълно изречение, а
    файлът носи голото име.
    """
    best = 0.0

    # 1. По заглавието на страницата.
    if page.get('title_fold'):
        best = max(best, SequenceMatcher(
            None, fold(saint['name_core']), page['title_fold']).ratio())
        # Дял на общите значещи думи — по-щедро от чистото сравнение на низове
        # при дълги заглавия („Житие на преподобни…").
        a, b = set(name_tokens(saint['name_core'])), set(page['title_fold'].split())
        if a:
            best = max(best, len(a & b) / len(a))

    # 2. По латинското име на файла.
    if page.get('stem'):
        stem = page['stem'].lower().replace('_', ' ')
        for junk in ('sv ', 'svv ', 'prep ', 'st '):
            if stem.startswith(junk):
                stem = stem[len(junk):]
        # ⚠ „ъ" се маха от нашата транслитерация, а сайтът го пише „u"
        # („Търновски" → наше „trnovski", тяхно „Turnovski"). Затова се
        # сравнява и вариант с махнати гласни-разделители.
        ours = saint['name_latin'].replace(',', ' ')
        best = max(best, SequenceMatcher(None, ours, stem).ratio())
        squeeze = lambda s: s.replace('u', '').replace('y', '').replace(' ', '')
        best = max(best, SequenceMatcher(
            None, squeeze(ours), squeeze(stem)).ratio())

    return best


def shared_tokens(saint: dict, page: dict) -> int:
    """Колко ЗНАЧЕЩИ думи от името се срещат в страницата.

    ⚠ Това е защитата срещу фалшивите съвпадения по чиста прилика на низове.
    „Анастасий Български" и „Anastasij Perski" си приличат 0.82, а са двама
    различни светии; „Игнатий Старозагорски" и „Triendafil Starozagorski" —
    0.80, при съвпадащ САМО град. И в двата случая съвпада ЕДНА дума.

    Истинското съвпадение носи и двете половини — лично име И прозвище:
    „Злата Мъгленска" ↔ „Zlata Muglenska", „Климент Охридски" ↔
    „Kliment Ohridski". Оттам и правилото: далечна по дата страница се приема
    само при ДВЕ или повече общи думи.

    Брои се и по заглавието (кирилица), и по името на файла (латиница) —
    едно и също име, две азбуки.
    """
    from common import NAME_VARIANTS, transliterate

    ours = set(name_tokens(saint['name_core']))
    if not ours:
        return 0

    # ⚠ `stem` е None за деветте страници в подпапки (bg_ierei, icons…) —
    # там датата не е в името. `or ''` е задължително, инак се спъва точно
    # на тях.
    #
    # ⚠ Нормализацията се прилага и на ДВЕТЕ страни. Сведе ли се само нашето
    # „Иван" до „Йоан", а тяхното остане „Иван", двете престават да съвпадат
    # изобщо — по-лошо, отколкото без нормализация.
    norm = lambda ws: {NAME_VARIANTS.get(w, w) for w in ws}
    theirs_cyr = norm((page.get('title_fold') or '').split())
    theirs_lat = norm((page.get('stem') or '').lower().replace('_', ' ').split())

    hits = 0
    for word in ours:
        if len(word) < 4:            # „св", „нов" съвпадат навсякъде
            continue
        lat = transliterate(word)
        if word in theirs_cyr:
            hits += 1
        elif any(lat and (lat in t or t in lat) and len(t) > 3
                 for t in theirs_lat):
            hits += 1
    return hits


def near_dates(mmdd: str, window: int) -> set[str]:
    """Датите в прозорец ±window около дадената. Годината е без значение —
    2001 е невисокосна, тъй че 29 февруари се пази отделно."""
    if mmdd == '02-29':
        return {'02-28', '02-29', '03-01'}
    m, d = (int(x) for x in mmdd.split('-'))
    base = date(2001, m, d)
    return {(base + timedelta(days=k)).strftime('%m-%d')
            for k in range(-window, window + 1)}


def load_manual() -> dict[str, dict]:
    path = INPUT / 'manual_map.csv'
    if not path.exists():
        return {}
    with path.open(encoding='utf-8') as fh:
        return {r['key']: r for r in csv.DictReader(fh) if r.get('key')}


def main() -> None:
    saints = json.loads((WORK / 'saints_bg.json').read_text(encoding='utf-8'))
    pages = json.loads((WORK / 'site_index.json').read_text(encoding='utf-8'))
    manual = load_manual()
    by_path = {p['path']: p for p in pages}

    by_date: dict[str, list] = {}
    for p in pages:
        if p['date']:
            by_date.setdefault(p['date'], []).append(p)

    results = []
    for s in saints:
        rec = {**s, 'matches': [], 'how': None}

        # 1. Ръчното решение печели над всичко.
        if s['key'] in manual:
            path = manual[s['key']]['path'].strip()
            if path and path in by_path:
                rec['matches'] = [{'path': path, 'score': 1.0,
                                   'titles': by_path[path]['titles'],
                                   'url': by_path[path]['url']}]
                rec['how'] = 'manual'
            else:
                # Празен path в CSV = „нарочно НЯМА страница" (виж README).
                rec['how'] = 'manual_none'
            results.append(rec)
            continue

        # 2. Кандидати от деня (и съседните).
        pool: list[dict] = []
        dates = ([s['church_date']] if s['church_date'] else s['church_dates'])
        seen = set()
        for d in dates:
            for near in near_dates(d, DAY_WINDOW):
                for p in by_date.get(near, []):
                    if p['path'] not in seen:
                        seen.add(p['path'])
                        pool.append(p)

        scored = sorted(
            ((similarity(s, p), p) for p in pool),
            key=lambda t: -t[0])
        hits = [{'path': p['path'], 'score': round(sc, 3),
                 'titles': p['titles'], 'url': p['url'],
                 'date': p['date']}
                for sc, p in scored if sc >= MIN_SCORE]

        # 3. Търсене по ИМЕ из целия указател.
        #
        # ⚠ Прави се ВИНАГИ, а не само когато денят е празен. Първата версия
        # го пускаше само при нула кандидати и точно затова изпускаше Злата
        # Мъгленска: у нас е 13 октомври, в сайта — 18-и (пет дни разлика,
        # извън прозореца), а в нейния ден стоеше ЧУЖД светия със слаба
        # прилика (Козма Маюмски, 0.429). Слабото съвпадение потискаше
        # търсенето, което би намерило верния — тих провал, при това
        # изглеждащ като „намерено".
        wide = sorted(((similarity(s, p), p) for p in pages),
                      key=lambda t: -t[0])[:6]
        # ⚠ ДВЕ условия, не едно: прилика И поне две общи значещи думи.
        # Само приликата пуска „Анастасий Български" → „Anastasij Perski".
        wide_hits = [{'path': p['path'], 'score': round(sc, 3),
                      'titles': p['titles'], 'url': p['url'],
                      'date': p['date'], 'by': 'name',
                      'shared': shared_tokens(s, p)}
                     for sc, p in wide
                     if sc >= 0.60 and shared_tokens(s, p) >= 2]

        best_day = hits[0]['score'] if hits else 0.0
        best_wide = wide_hits[0]['score'] if wide_hits else 0.0

        if hits and best_day >= 0.55:
            # Уверено съвпадение в самия ден — датата е най-силният признак.
            rec['matches'] = hits[:4]
            rec['how'] = 'date+name'
        elif best_wide > best_day + 0.10:
            # Името сочи другаде ЯВНО по-добре И носи двете си половини.
            # Прагът +0.10 е нарочен: при почти равни печели денят, защото
            # датата е по-надеждният ключ.
            rec['matches'] = wide_hits + hits[:2]
            rec['how'] = 'name_only'
        elif hits:
            rec['matches'] = hits[:4]
            rec['how'] = 'weak'
        else:
            rec['matches'] = wide_hits
            rec['how'] = 'name_only' if wide_hits else 'none'

        results.append(rec)

    (WORK / 'candidates.json').write_text(
        json.dumps(results, ensure_ascii=False, indent=2), encoding='utf-8')

    # ── Отчет за четене с очи ─────────────────────────────────────────────
    lines = ['# Засечка: български светии ↔ pravoslavieto.com', '',
             'Подредено по увереност. ⚠ Редовете „слаба" и „само по име" се',
             'гледат ПЪРВИ — там грешките са; сигурните минават на бърз поглед.',
             '']
    order = {'manual': 0, 'date+name': 1, 'weak': 2, 'name_only': 3,
             'none': 4, 'manual_none': 5}
    label = {'manual': 'ръчно', 'date+name': 'дата+име', 'weak': 'слаба',
             'name_only': 'само по име', 'none': 'НЯМА',
             'manual_none': 'ръчно: няма'}
    for how in sorted(order, key=order.get):
        group = [r for r in results if r['how'] == how]
        if not group:
            continue
        lines += [f'## {label[how]} — {len(group)}', '']
        for r in group:
            d = r['church_date'] or '/'.join(r['church_dates'])
            top = r['matches'][0] if r['matches'] else None
            mark = {'no_slug': '🔴', 'short': '🟡', 'ok': '⚪'}[r['need']]
            lines.append(f'- {mark} **{d}** {r["name_core"]}')
            for m in r['matches']:
                lines.append(f'    - `{m["score"]}` {m["path"]}')
            if not top:
                lines.append('    - _(нищо)_')
        lines.append('')
    (WORK / 'match_report.md').write_text('\n'.join(lines), encoding='utf-8')

    counts: dict[str, int] = {}
    for r in results:
        counts[r['how']] = counts.get(r['how'], 0) + 1
    print('засечка по увереност:')
    for how in sorted(counts, key=lambda h: order[h]):
        print(f'  {label[how]:14} {counts[how]:3}')
    need_hit = sum(1 for r in results
                   if r['need'] != 'ok' and r['matches'])
    need_all = sum(1 for r in results if r['need'] != 'ok')
    print(f'\nот нуждаещите се ({need_all}) имат кандидат: {need_hit}')
    print(f'\n→ work/candidates.json,  work/match_report.md')


if __name__ == '__main__':
    main()
