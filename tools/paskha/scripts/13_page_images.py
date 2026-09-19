#!/usr/bin/env python3
"""Сваля картинките от статиите → assets/lives_images/ + work/pages_img.json.

    python3 13_page_images.py --stage 1

⚠ Размерите се четат ПРАВО ОТ БАЙТОВЕТЕ (без Pillow) и ВЛИЗАТ В ТАГА: без
тях четецът смята мястото по подразбиране и портретните излизат свити.

⚠ Името носи отпечатък на адреса — един и същ файл стои под различни имена
в различни статии, а различни файлове — под едно име.

⚠ Отсяват се дребните: иконки, аватари и разделители под 120 px са
обзавеждане на сайта, не илюстрация към текста.
"""
import argparse, csv, hashlib, html as _html, json, os, re, sys
from pathlib import Path
import requests

КОРЕН = Path(__file__).resolve().parents[1]
КЕШ = КОРЕН / 'cache' / 'pages'
РАБОТА = КОРЕН / 'work'
ПРОЕКТ = КОРЕН.parents[1]
ЦЕЛ = ПРОЕКТ / 'assets' / 'lives_images'
СПИСЪК = КОРЕН / 'input' / 'pages.csv'
МИН_СТРАНА = 120

_spec_img = Path(__file__).with_name('07_image.py')
import importlib.util
_s = importlib.util.spec_from_file_location('img07', _spec_img)
_m = importlib.util.module_from_spec(_s)
_s.loader.exec_module(_m)
размер = _m.размер            # ⚠ същата функция, за да не се разминат

RE_IMG = re.compile(r'<img[^>]+>', re.I)
RE_SRC = re.compile(r'\ssrc="([^"]+)"', re.I)
RE_ALT = re.compile(r'\salt="([^"]*)"', re.I)
# Обзавеждане на сайта, не илюстрация.
ПРОПУСКАЙ = ('/avatar', 'logo', 'icon', 'smile', 'banner', 'cropped-')


def тяло(h: str) -> str:
    m = re.search(r'<div[^>]*class="[^"]*main-page-content[^"]*"', h, re.I)
    if not m:
        return ''
    m2 = re.search(r'<h2[^>]*id="literature"', h[m.start():], re.I)
    return h[m.start(): m.start() + m2.start() if m2 else len(h)]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('--stage', type=int, required=True)
    a = ap.parse_args()
    ЦЕЛ.mkdir(parents=True, exist_ok=True)
    карта = {}
    п = РАБОТА / 'pages_img.json'
    if п.exists():
        карта = json.loads(п.read_text(encoding='utf-8'))

    редове = [r for r in csv.DictReader(open(СПИСЪК, encoding='utf-8'))
              if int(r['stage']) == a.stage]
    нови = дребни = стари = 0
    for r in редове:
        f = КЕШ / (r['slug'] + '.html')
        if not f.exists():
            continue
        свои = карта.get(r['slug'], [])
        имам = {x['url'] for x in свои}
        for таг in RE_IMG.findall(тяло(f.read_text(encoding='utf-8'))):
            ms = RE_SRC.search(таг)
            if not ms:
                continue
            url = _html.unescape(ms.group(1))
            if url.startswith('//'):
                url = 'https:' + url
            if not url.startswith('http') or any(x in url.lower() for x in ПРОПУСКАЙ):
                continue
            if url in имам:
                стари += 1
                continue
            try:
                resp = requests.get(url, timeout=60,
                                    headers={'User-Agent': 'Mozilla/5.0'})
                resp.raise_for_status()
                b = resp.content
            except Exception as e:                        # noqa: BLE001
                print('  ⚠ %s: %s' % (url[:60], e)); continue
            w, hh = размер(b)
            if w and hh and (w < МИН_СТРАНА or hh < МИН_СТРАНА):
                дребни += 1
                continue
            ext = '.png' if b[:8] == b'\x89PNG\r\n\x1a\n' else '.jpg'
            основа = re.sub(r'[^a-z0-9]+', '_',
                            os.path.basename(url).rsplit('.', 1)[0].lower())[:40].strip('_')
            име = 'azb_%s_%s%s' % (основа, hashlib.md5(url.encode()).hexdigest()[:8], ext)
            (ЦЕЛ / име).write_bytes(b)
            ma = RE_ALT.search(таг)
            свои.append({'url': url, 'file': име, 'width': w, 'height': hh,
                         'alt': _html.unescape(ma.group(1)) if ma else ''})
            нови += 1
            print('  ✅ %-26s %s  %sx%s' % (r['slug'], име[:44], w, hh))
        if свои:
            карта[r['slug']] = свои
    п.write_text(json.dumps(карта, ensure_ascii=False, indent=1), encoding='utf-8')
    print('нови %d | вече свалени %d | отсети дребни %d' % (нови, стари, дребни))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
