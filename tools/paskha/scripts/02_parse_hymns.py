#!/usr/bin/env python3
"""Пасхалните песнопения → `work/hymns.json`. Без мрежа.

    cache/hymns.html   → стихира, тропар, ипакои, кондак, задостойник, стихири
    cache/chasy.html   → пасхалните часове
    cache/kanon.html   → пасхалният канон (девет песни)

⚠⚠ СЪЩАТА СХЕМА КАТО В `tools/azbyka.ru/14_extract_hymns.py`: руският текст
С УДАРЕНИЯ е църковнославянският и влиза направо, БЕЗ превод; онова след
„Перевод:" е руски превод и се превежда на български.

⚠ Заглавието остава ЦЪРКОВНОСЛАВЯНСКО („Ипакои, глас 4"), както в целия
проект — то е част от славянския блок, а не негов превод.

    python3 02_parse_hymns.py
"""
import json
import re
from pathlib import Path

КОРЕН = Path(__file__).resolve().parents[1]
КЕШ = КОРЕН / 'cache'
РАБОТА = КОРЕН / 'work'

RE_TAG = re.compile(r'<[^>]+>')
# ⚠ Бележките под линия се махат КАТО ЕЛЕМЕНТ, не като цифри — инак номерът
# увисва като гол текст насред песнопението. (Същото правило като в
# `build_lives_index.py`.)
RE_FTN = re.compile(r'<a[^>]*href="#_ftn\d+"[^>]*>.*?</a>', re.S | re.I)
RE_PLAYER = re.compile(r'<span class="inline-player__wrap".*?</span>\s*</span>',
                       re.S)


def гол(html: str) -> str:
    s = RE_FTN.sub('', html)
    s = re.sub(r'<br\s*/?>', '\n', s, flags=re.I)
    s = RE_TAG.sub('', s)
    s = (s.replace('&nbsp;', ' ').replace('&#160;', ' ')
          .replace('&laquo;', '«').replace('&raquo;', '»')
          .replace('&amp;', '&').replace('&mdash;', '—')
          .replace('&ndash;', '–').replace('&quot;', '"'))
    # ⚠ Свиват се само ИНТЕРВАЛИТЕ, не новите редове: те делят стиховете.
    s = re.sub(r'[ \t]+', ' ', s)
    return '\n'.join(l.strip() for l in s.split('\n') if l.strip())


def раздели(html: str) -> tuple[str, str]:
    """(църковнославянски, руски превод) от ЕДИН абзац.

    ⚠⚠ ПРИЗНАКЪТ Е КУРСИВЪТ (`<em>`), НЕ ДУМАТА „Перевод:". При стихирата
    етикетът го има, при тропара и кондака — НЕ, а преводът е просто курсив
    след `<br>`. Търсен по думата, той излизаше празен за четири от шестте
    песнопения — тихо, защото полето просто оставаше празно.

    ⚠ Водещото „Перевод:" се отрязва, ако все пак е вътре в курсива.
    """
    # ⚠⚠ САМО АБЗАЦИТЕ. „<em>Аудио:</em>" стои в `div` до плеъра, не в `<p>`
    # — взето от целия дял, то се лепеше в НАЧАЛОТО на превода („Аудио:
    # Христос воскрес из мертвых…"). Личеше само ако човек прочете полето.
    html = RE_PLAYER.sub('', html)
    html = '\n'.join(f'<p>{x}</p>'
                     for x in re.findall(r'<p[^>]*>(.*?)</p>', html, re.S))
    курсив = re.findall(r'<em[^>]*>(.*?)</em>', html, re.S)
    рус = гол('\n'.join(курсив))
    рус = re.sub(r'^\s*Перевод\s*[:.]?\s*', '', рус)
    # ⚠ Църковнославянският е всичко ИЗВЪН курсива — маха се той, не се
    # реже по позиция: курсивът може да е и по средата.
    цсл = гол(re.sub(r'<em[^>]*>.*?</em>', '', html, flags=re.S))
    return цсл.strip(), рус.strip()


def дялове(html: str, ниво: str = 'h3') -> list[tuple[str, str]]:
    """(заглавие, HTML до следващото заглавие от същото ниво)."""
    части = re.split(rf'<{ниво}[^>]*>(.*?)</{ниво}>', html, flags=re.S)
    out = []
    for i in range(1, len(части) - 1, 2):
        out.append((гол(части[i]), части[i + 1]))
    return out


def тяло(html: str) -> str:
    """Само абзаците, без плеъра и без аудио надписите."""
    html = RE_PLAYER.sub('', html)
    пар = re.findall(r'<p[^>]*>(.*?)</p>', html, re.S)
    текст = '\n'.join(гол(p) for p in пар)
    # ⚠ „Аудио:" остава като гол ред след махането на плеъра.
    текст = re.sub(r'^\s*Аудио\s*:?\s*$', '', текст, flags=re.M)
    return '\n'.join(l for l in текст.split('\n') if l.strip())


def статия(файл: str) -> str:
    """Само същинската част, без навигацията и без коментарите."""
    t = (КЕШ / файл).read_text(encoding='utf-8')
    i = t.find('main-page-content')
    if i < 0:
        i = 0
    for край in ('Рекомендуемые статьи', 'комментариев', 'Литература по теме'):
        j = t.rfind(край)
        if j > i:
            t = t[:j]
    return t[i:]


def main() -> int:
    РАБОТА.mkdir(parents=True, exist_ok=True)
    out = []

    # ── песнопенията ──────────────────────────────────────────────────────
    for заглавие, html in дялове(статия('hymns.html')):
        цсл, рус = раздели(html)
        if not цсл:
            continue
        out.append({'kind_ru': заглавие, 'csl': цсл, 'ru': рус,
                    'src': 'https://azbyka.ru/pashalnye-pesnopeniya'})

    # ── канонът: девет песни ──────────────────────────────────────────────
    #
    # ⚠⚠ ДРУГО УСТРОЙСТВО, затова и друг път. Тук абзаците са РАЗДЕЛЕНИ по
    # клас — `p.gprayer` е църковнославянският, `p.translate` преводът — и се
    # редуват по няколко пъти в една песен. Взети както при песнопенията
    # (един блок, разделен по курсива), излизаха по 2–10 хиляди знака „превод",
    # защото поглъщаха цялата останала песен.
    #
    # ⚠ Има ДВА превода: прозаичен (`translate`) и стихотворен
    # (`translate translate-2`). Взима се ПЪРВИЯТ — той е обичайният; вторият
    # е поетичен преразказ и при две колони би се четял като друг текст.
    for заглавие, html in дялове(статия('kanon.html')):
        цсл_части, рус_части = [], []
        for cls, тяло_ in re.findall(
                r'<p class="([^"]*)"[^>]*>(.*?)</p>', html, re.S):
            t = гол(тяло_)
            if not t:
                continue
            if 'translate-2' in cls:
                continue
            if 'translate' in cls:
                рус_части.append(re.sub(r'^\s*Перевод\s*[:.]?\s*', '', t))
            elif 'gprayer' in cls:
                цсл_части.append(t)
        if not цсл_части:
            continue
        out.append({'kind_ru': f'Пасхален канон — {заглавие}',
                    'csl': '\n'.join(цсл_части),
                    'ru': '\n'.join(рус_части),
                    'src': 'https://azbyka.ru/molitvoslov/'
                           'pasxalnyj-kanon-tvorenie-ioanna-damaskina.html'})

    (РАБОТА / 'hymns.json').write_text(
        json.dumps(out, ensure_ascii=False, indent=1), encoding='utf-8')
    print(f'{len(out)} песнопения → work/hymns.json')
    for h in out:
        print(f'  {h["kind_ru"][:40]:42} цсл {len(h["csl"]):>5} | '
              f'рус {len(h["ru"]):>5}')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
