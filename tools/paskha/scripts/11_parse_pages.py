#!/usr/bin/env python3
"""Разчита свалените страници → work/pages/<слъг>.json.

    python3 11_parse_pages.py --stage 1

⚠⚠ ПРЕИЗПОЛЗВА разчитането на основната страница (`04_parse_text.py`), а не
го преписва: двата разбора трябва да се менят заедно. Файлът започва с
цифра, тъй че се внася през `importlib`.

⚠ Отрязва се опашката („Литература по теме" и надолу) — тя е списък с
препратки, не част от статията.
"""
import argparse, csv, importlib.util, json, re, sys
from pathlib import Path

КОРЕН = Path(__file__).resolve().parents[1]
КЕШ = КОРЕН / 'cache' / 'pages'
РАБОТА = КОРЕН / 'work' / 'pages'
СПИСЪК = КОРЕН / 'input' / 'pages.csv'

_spec = importlib.util.spec_from_file_location(
    'parse_text', Path(__file__).with_name('04_parse_text.py'))
_pt = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_pt)
гол, абзаци = _pt.гол, _pt.абзаци


# ⚠⚠ ТЯЛОТО СЕ ТЪРСИ КАТО ТАГ, НЕ КАТО ИМЕ НА КЛАС. Половината страници
# споменават „main-page-content" по-рано, ВЪТРЕ В СКРИПТ, и търсенето по
# гол подниз хващаше него — тялото излизаше празно, без нито една грешка.
# (11 от 23 страници на първия етап.)
RE_ТЯЛО = re.compile(r'<div[^>]*class="[^"]*main-page-content[^"]*"', re.I)
RE_ТЯЛО2 = re.compile(r'<div[^>]*class="[^"]*article-single-content[^"]*"', re.I)


# ⚠⚠ КРАЯТ НА СТАТИЯТА — ПЪРВИЯТ ОТ НЯКОЛКО ПРИЗНАКА, НЕ САМО ЕДИН.
#
# Дотук се режеше само по `<h2 id="literature">`, а НЯМА ЛИ ГО, тялото
# стигаше до КРАЯ НА ФАЙЛА и поглъщаше блока с коментарите на сайта.
# При трите кръстословици това значеше статия, съставена ИЗЦЯЛО от
# „Уведомяване за отговори на този коментар" и остатъци от скрипт —
# 193 знака чуждо съдържание и нито ред същинско. (Докладвано от
# потребителя, 20.09.2026.)
#
# ⚠ Редът в списъка няма значение: взима се НАЙ-РАННОТО съвпадение.
# ⚠ Обвивките на коментарите са няколко („comments-area", „comment-respond",
# `id="respond"`), тъй че признакът е ОБЩ: елемент, чието id или class носи
# „comment" или „respond". Първият опит изброяваше конкретни имена и
# пропусна точно онова, с което почва формата при кръстословиците.
# ⚠⚠ ПРИЗНАКЪТ Е МНОЖЕСТВЕНОТО ЧИСЛО — „comments", не „comment".
#
# Първият опит режеше по всяко id/class, съдържащо „comment", и изяде 31
# абзаца от „Пасха и Светла седмица": там, на 1571 знака от началото, стои
# вътрешна кутийка `<div class="azv-default-comment">` — бележка в самото
# четиво, не блокът с коментарите. Обвивките на истинския блок са три
# („comments-area", „comment-respond", `id="respond"`) и всичките носят или
# множествено число, или „respond"; вътрешните кутийки — не.
#
# ⚠ Префикс се допуска: при една страница блокът е `id="llc-comments"`.
RE_КРАЙ = [
    re.compile(r'<h2[^>]*id="literature"', re.I),
    re.compile(r'<(?:div|section|aside|form)[^>]*(?:id|class)="[^"]*'
               r'(?:comments(?![a-z])|comment-respond|respond")', re.I),
]

# ⚠⚠ СКРИПТОВЕТЕ И СТИЛОВЕТЕ СЕ МАХАТ ПРЕДИ РАЗЧИТАНЕТО.
#
# До вграденото видео сайтът слага `<script type="application/ld+json">`
# с описанието му за търсачките. Изразът за абзаци не различава скрипт от
# текст, тъй че целият JSON влизаше в четивото като абзац:
# „{"@context":"https://schema.org/","@type":"VideoObject"…". Шест статии
# го носеха; в една от тях беше ПЪРВОТО, което човек вижда.
RE_СКРИПТ = re.compile(r'<(script|style)\b.*?</\1\s*>', re.I | re.S)

# ⚠⚠ СКРИТИТЕ ЕЛЕМЕНТИ НЕ СА СЪДЪРЖАНИЕ.
#
# Сайтът държи джаджата за влизане в скрит блок
# (`<div class="az-sso-messages" style="…display:none">`), а вътре в нея —
# два абзаца: „Входим…" и „Куки не обнаружены, не ЛК". Второто излизаше
# накрая на ПЕТНАЙСЕТ статии като последен ред от четивото, при това
# преведено на български.
#
# ⚠ Признакът е ОБЩ (`display:none`), а не името на класа: утрешна скрита
# джаджа ще отпадне сама.
RE_СКРИТО = re.compile(
    r'<(div|aside|section|p)\b[^>]*style="[^"]*display\s*:\s*none', re.I)
RE_ТАГ = re.compile(r'<(/?)(div|aside|section|p)\b[^>]*?(/?)>', re.I)


def махни_скритите(body: str) -> str:
    """Изрязва скритите блокове ЗАЕДНО със съдържанието им.

    ⚠ Вложеността се БРОИ, а не се реже до първия затварящ таг: скритият
    блок съдържа свои елементи и рязането до първото `</div>` би оставило
    опашка от чужди затварящи тагове.
    """
    while True:
        m = RE_СКРИТО.search(body)
        if not m:
            return body
        име = m.group(1).lower()
        дълбочина, край = 0, None
        for t in RE_ТАГ.finditer(body, m.start()):
            if t.group(2).lower() != име:
                continue
            if t.group(3):                 # самозатварящ се
                continue
            дълбочина += -1 if t.group(1) else 1
            if дълбочина == 0:
                край = t.end()
                break
        if край is None:                   # незатворен — маха се само тагът
            край = m.end()
        body = body[:m.start()] + ' ' + body[край:]


def разчети(html: str) -> dict:
    m = RE_ТЯЛО.search(html) or RE_ТЯЛО2.search(html)
    i = m.start() if m else -1
    if i < 0:
        return {'title_ru': '', 'sections': []}
    краища = [i + m2.start() for m2 in
              (rx.search(html[i:]) for rx in RE_КРАЙ) if m2]
    j = min(краища) if краища else len(html)
    body = махни_скритите(RE_СКРИПТ.sub(' ', html[i:j]))

    # Съдържанието с котвите отпада — инак заглавията влизат като текст.
    k = body.find('</ul>', body.find('id=toc'))
    if k > 0:
        body = body[k:]

    заглавие = ''
    m = re.search(r'<h1[^>]*>(.*?)</h1>', html, re.S)
    if m:
        заглавие = гол(m.group(1))

    части = re.split(r'<h2[^>]*>(.*?)</h2>', body, flags=re.S)
    дялове = [{'title_ru': '', 'blocks': абзаци(части[0])}]
    for n in range(1, len(части) - 1, 2):
        дялове.append({'title_ru': гол(части[n]),
                       'blocks': абзаци(части[n + 1])})
    дялове = [d for d in дялове if d['blocks'] or d['title_ru']]
    return {'title_ru': заглавие, 'sections': дялове}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('--stage', type=int, required=True)
    a = ap.parse_args()
    РАБОТА.mkdir(parents=True, exist_ok=True)
    редове = [r for r in csv.DictReader(open(СПИСЪК, encoding='utf-8'))
              if int(r['stage']) == a.stage]
    общо_знаци = общо_връзки = 0
    for r in редове:
        f = КЕШ / (r['slug'] + '.html')
        if not f.exists():
            print(f"  ⚠ {r['slug']}: не е свалена"); continue
        d = разчети(f.read_text(encoding='utf-8'))
        d['slug'] = r['slug']
        d['url'] = r['url']
        знаци = sum(len(b['ru']) for s in d['sections'] for b in s['blocks'])
        връзки = sum(len(b['links']) for s in d['sections'] for b in s['blocks'])
        d['chars'] = знаци
        общо_знаци += знаци
        общо_връзки += връзки
        (РАБОТА / (r['slug'] + '.json')).write_text(
            json.dumps(d, ensure_ascii=False, indent=1), encoding='utf-8')
        print(f"  {r['slug']:30} {len(d['sections']):3} дяла  "
              f"{знаци:6} знака  {връзки:3} връзки   „{d['title_ru'][:34]}")
    print(f'\nобщо: {общо_знаци} знака, {общо_връзки} връзки')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
