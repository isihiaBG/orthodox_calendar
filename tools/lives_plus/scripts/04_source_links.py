#!/usr/bin/env python3
"""Адресът на всяко слово в azbyka.ru → `work/source_links.json`.

⚠ Източникът изисква коректно цитиране; под всяко четиво трябва да стои
връзка към оригинала. Досегашните жития я носят в `texts.source` и четецът я
изписва накрая (`_sourceHtml()`), тъй че тук се пази същото поле.

⚠⚠ СЪПОСТАВЯНЕТО Е ПО ЗАГЛАВИЕ И СЕ ПРОВЕРЯВА. Заглавието в .epub-а понякога
е ОТРЯЗАНО („Слово в субботу четвертой недели великого"), а на сайта е пълно
и носи и началния стих в скоби. Затова се мери приликата на СГЪНАТИТЕ
низове и всяко съответствие под прага излиза за преглед, вместо да се приеме
мълчаливо — грешна връзка сочи чуждо четиво и е по-лоша от липсваща.

    python3 04_source_links.py            # чете от cache/, без мрежа
    python3 04_source_links.py --fetch     # тегли съдържанията наново
"""
import argparse
import difflib
import json
import os
import re
import sys
from pathlib import Path

sys.path.insert(0, os.path.dirname(__file__))
from address import infer   # noqa: E402

КОРЕН = Path(__file__).resolve().parents[1]
КЕШ = КОРЕН / 'cache'
РАБОТА = КОРЕН / 'work'

КНИГИ = {
    'pril': 'https://azbyka.ru/otechnik/Dmitrij_Rostovskij/'
            'prilozhenija-zhitija-svjatyh/',
    'vosk': 'https://azbyka.ru/otechnik/Dmitrij_Rostovskij/'
            'pouchenija-i-propovedi/',
    'nepe': 'https://azbyka.ru/otechnik/Dmitrij_Rostovskij/'
            'pouchenija-i-slova/',
}
ПРАГ = 0.72


def сгъни(s: str) -> str:
    """Само букви и цифри, малки — за сравнение по съдържание."""
    s = s.lower().replace('ё', 'е')
    return re.sub(r'[^0-9a-zа-я]+', '', s)


def прилика(a: str, b: str) -> float:
    return difflib.SequenceMatcher(None, сгъни(a), сгъни(b)).ratio()


def тегли():
    import requests
    КЕШ.mkdir(parents=True, exist_ok=True)
    h = {'User-Agent': 'Mozilla/5.0 (orthodox-calendar research)'}
    for k, u in КНИГИ.items():
        r = requests.get(u, headers=h, timeout=60)
        r.raise_for_status()
        (КЕШ / f'toc-{k}.html').write_text(r.text, encoding='utf-8')
        print(f'  {k}: {len(r.text):,} байта')


def дялове(k: str) -> list[tuple[str, str]]:
    """(адрес, заглавие) за всеки дял на книгата."""
    t = (КЕШ / f'toc-{k}.html').read_text(encoding='utf-8')
    i = t.find('Содержание')
    if i < 0:
        sys.exit(f'⚠ в toc-{k}.html няма „Содержание" — променен ли е сайтът?')
    # ⚠⚠ ДВА РАЗЛИЧНИ ВИДА СЪДЪРЖАНИЕ, и това не личи отвън:
    #
    #   „Поучения и слова"  → всяка глава е СВОЯ страница: <a href="./7">
    #   другите две         → ЦЯЛАТА книга е една страница, а главите са
    #                          КОТВИ в нея: <a href="#0_7">
    #
    # Писан само за първия вид, изразът връщаше НУЛА дяла за другите две —
    # тихо, защото „нула намерени" изглежда като празна книга.
    тяло = t[i:]
    out = []
    for href, име in re.findall(
            r'<a href="\./(\d+)">\s*<span class="h2o">(.*?)</span>',
            тяло, re.S):
        out.append((КНИГИ[k] + href, _чист(име)))
    if out:
        return out
    # ⚠ Само `h3o`: в „Приложения" месеците (Март, Апрель…) стоят като `h2o`
    # и са дялове на книгата, не четива.
    for клас, котва, име in re.findall(
            r'<span class="(h[23]o)">\s*<a href="#(0_\d+)">(.*?)</a>',
            тяло, re.S):
        if клас == 'h3o':
            out.append((f'{КНИГИ[k]}#{котва}', _чист(име)))
    return out


def _чист(s: str) -> str:
    return re.sub(r'\s+', ' ', re.sub(r'<[^>]+>', '', s)).strip()


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('--fetch', action='store_true')
    a = ap.parse_args()
    if a.fetch:
        тегли()

    единици = [json.loads(f.read_text(encoding='utf-8'))
               for f in sorted((РАБОТА / 'units').glob('*.json'))]
    по_книга = {}
    for k in КНИГИ:
        по_книга[k] = дялове(k)
        print(f'{k}: {len(по_книга[k])} дяла на сайта')

    # ⚠⚠ СЪПОСТАВЯ СЕ ПО ЛИТУРГИЧЕН АДРЕС, НЕ ПО ПРАВОПИС.
    #
    # Сайтът и книгата назовават един и същ ден РАЗЛИЧНО: „в неделю двадцать
    # вторую по Пятидесятнице" срещу „в неделю 22-ю по Святом Духе". Мерена
    # по низове, приликата е плоска за цяла редица недели — при първия опит
    # ЕДИН адрес се залепи за ШЕСТ слова, тихо и правдоподобно.
    #
    # Адресът го няма този недостатък: и двете страни минават през същия
    # `address.infer()`, тъй че сравняваме ДНИ, а не изписвания. Правописът
    # остава само за избор ВЪТРЕ в един ден („първо" и „второ" слово).
    links, слаби, липсващи = {}, [], []
    for book, кандидати in по_книга.items():
        наши = [x for x in единици if x['book'] == book]
        техни = [(u, t, infer(t)[0]) for u, t in кандидати]
        заети = set()
        for x in наши:
            същия_ден = [c for c in техни
                         if c[2] and c[2] == x['address'] and c[0] not in заети]
            избор = същия_ден or [c for c in техни if c[0] not in заети]
            ако = max(избор, key=lambda c: прилика(x['title_ru'], c[1])) \
                if избор else None
            if ако is None:
                липсващи.append(x)
                continue
            r = прилика(x['title_ru'], ако[1])
            # ⚠ При съвпаднал АДРЕС прагът по правопис не важи: там въпросът е
            # само кое от двете слова за деня е кое, а не дали е този ден.
            if not същия_ден and r < ПРАГ:
                слаби.append((x, ако, r))
                continue
            заети.add(ако[0])
            links[x['id']] = {'url': ако[0], 'title_ru': ако[1],
                              'ratio': round(r, 3),
                              'by': 'адрес' if същия_ден else 'правопис'}

    # ⚠ Един адрес на две слова значи сбъркана засечка — изписва се изрично.
    обратно = {}
    for i, v in links.items():
        обратно.setdefault(v['url'], []).append(i)
    двойни = {u: ids for u, ids in обратно.items() if len(ids) > 1}

    (РАБОТА / 'source_links.json').write_text(
        json.dumps(links, ensure_ascii=False, indent=1), encoding='utf-8')
    print(f'\nсвързани {len(links)} от {len(единици)}')
    if двойни:
        print(f'⚠ ЕДИН АДРЕС НА НЯКОЛКО СЛОВА: {len(двойни)}')
        for u, ids in list(двойни.items())[:6]:
            print(f'   {u} ← {ids}')
    if слаби:
        print(f'⚠ ПОД ПРАГА ({ПРАГ}) — за преглед: {len(слаби)}')
        for x, най, r in слаби:
            print(f'   {r:.2f} {x["id"]} | наше: {x["title_ru"][:52]}')
            print(f'          сайт: {най[1][:52]}')
    if липсващи:
        print(f'⚠ без книга: {[x["id"] for x in липсващи]}')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
