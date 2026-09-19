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


def разчети(html: str) -> dict:
    m = RE_ТЯЛО.search(html) or RE_ТЯЛО2.search(html)
    i = m.start() if m else -1
    if i < 0:
        return {'title_ru': '', 'sections': []}
    # ⚠⚠ ОПАШКАТА СЕ РЕЖЕ ПО ЗАГЛАВИЕТО `<h2 id="literature">`, НЕ по текста
    # „Литература по теме": той се среща и в СКРИТИЯ блок със съдържанието
    # в началото на страницата, тъй че рязането по него изяждаше цялата
    # статия — 7 от 23 излизаха празни, без грешка.
    m2 = re.search(r'<h2[^>]*id="literature"', html[i:], re.I)
    j = i + m2.start() if m2 else len(html)
    body = html[i:j]

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
