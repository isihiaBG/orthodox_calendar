#!/usr/bin/env python3
"""Разчита разделите „Литература по теме" и „Близкие понятия" → work/links.json.

    python3 08_parse_links.py

⚠ Двата раздела са РАЗЛИЧНО устроени:

    Литература   <ul class="literature-list">, с подзаглавия <li class="li-title">
                 и автор/издание в <span class="stairsQwerty1">
    Близки       <section class="related-posts"> → <ul class="related-posts-item">

⚠ Вътре в `span`-а с автора има ВТОРА връзка (към страницата на автора).
Тя не е част от четивото и се сваля до текст — инак в списъка се явяват по
две връзки на ред и не се разбира коя накъде води.
"""
import html, json, re
from pathlib import Path

КОРЕН = Path(__file__).resolve().parents[1]
КЕШ = КОРЕН / 'cache'
РАБОТА = КОРЕН / 'work'


# ⚠⚠ АДРЕСИТЕ В ИЗВОРА НЕ СА ВИНАГИ ПЪЛНИ. Сайтът пише и „//azbyka.ru/…"
# (без схема), и „/pashalnoe-…" (само път). Такъв адрес стига до четеца,
# той пита „да отворя ли", човек казва „да" — и НЕ СЕ СЛУЧВА НИЩО, защото
# браузърът няма какво да отвори. Тих отказ, забелязан от практиката:
# „Пасхални часове", „Пасхално евангелие на различни езици" и още 21.
БАЗА = 'https://azbyka.ru'


def пълен_адрес(u: str) -> str:
    u = (u or '').strip()
    if not u:
        return u
    if u.startswith('//'):
        return 'https:' + u
    if u.startswith('/'):
        return БАЗА + u
    if not re.match(r'^[a-zA-Z][a-zA-Z0-9+.\-]*:', u):
        return БАЗА + '/' + u.lstrip('/')
    return u


def гол(s: str) -> str:
    s = re.sub(r'<[^>]+>', '', s)
    return re.sub(r'\s+', ' ', html.unescape(s)).strip()


def литература(h: str):
    m = re.search(r'<h2[^>]*id="literature".*?</h2>\s*(<ul.*?</ul>)', h, re.S)
    if not m:
        return []
    групи, текуща = [], None
    for li in re.finditer(r'<li([^>]*)>(.*?)</li>', m.group(1), re.S):
        атр, тяло = li.group(1), li.group(2)
        if 'li-title' in атр:
            текуща = {'title_ru': гол(тяло), 'items': []}
            групи.append(текуща)
            continue
        a = re.search(r'<a[^>]*href="([^"]+)"[^>]*>(.*?)</a>', тяло, re.S)
        if not a:
            continue
        # ⚠ Авторът се взима БЕЗ вложената връзка към неговата страница.
        sp = re.search(r'<span[^>]*>(.*?)</span>', тяло, re.S)
        ако = {'url': пълен_адрес(html.unescape(a.group(1))), 'title_ru': гол(a.group(2)),
               'by_ru': гол(sp.group(1)) if sp else ''}
        if текуща is None:
            текуща = {'title_ru': '', 'items': []}
            групи.append(текуща)
        текуща['items'].append(ако)
    return групи


def близки(h: str):
    m = re.search(r'related-posts-title[^>]*>\s*Близкие понятия\s*</h2>(.*?)</section>',
                  h, re.S)
    if not m:
        return []
    out = []
    for a in re.finditer(r'<a[^>]*href="([^"]+)"[^>]*>(.*?)</a>', m.group(1), re.S):
        out.append({'url': пълен_адрес(html.unescape(a.group(1))), 'title_ru': гол(a.group(2))})
    return out


def main() -> int:
    h = (КЕШ / 'page.html').read_text(encoding='utf-8')
    рец = {'literature': литература(h), 'related': близки(h)}
    (РАБОТА / 'links.json').write_text(
        json.dumps(рец, ensure_ascii=False, indent=1), encoding='utf-8')
    n = sum(len(г['items']) for г in рец['literature'])
    print(f"литература: {len(рец['literature'])} групи, {n} заглавия")
    for г in рец['literature']:
        print(f"   • {г['title_ru']}: {len(г['items'])}")
    print(f"близки понятия: {len(рец['related'])}")
    print('записано:', (РАБОТА / 'links.json'))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
