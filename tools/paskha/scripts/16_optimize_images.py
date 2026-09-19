#!/usr/bin/env python3
"""Свива илюстрациите от azbyka.ru до разумен размер за екран.

    python3 16_optimize_images.py --dry-run
    python3 16_optimize_images.py

⚠⚠ ЗАЩО. Сайтът дава снимките в печатна резолюция — до 1,3 MB на файл. В
пакета те влизат КАКТО СА и след 4-ти и 5-ти етап APK-то скочи от 84 на
120 MB. А потребителят тегли билда по мрежата.

⚠ Таванът е 1400 px по дългата страна. Четецът и без това ограничава
височината до 55% от екрана, а PDF-ът иска 150 ppi чак за пейзажните на
цяла ширина (виж kPdfFullWidthMinPpi) — при лист от 6 инча това е 900 px.

⚠⚠ ПРОПОРЦИЯТА СЕ ПАЗИ, тъй че `width`/`height` в тага остават верни по
СЪОТНОШЕНИЕ — а четецът смята мястото точно по него. Все пак новите мерки
се вписват в `work/pages_img.json`, за да не се разминат числата с файла;
след това се пуска наново `14_apply_pages.py`.

⚠ Идемпотентен: файл, който вече е по-малък от тавана И по-лек от прага,
се прескача. Пуснат втори път, не преработва нищо.

⚠ Пипа САМО нашите файлове (`azb_*`, `pascha_*`) — в същата папка живеят и
илюстрациите на българските жития, които идват от друг конвейер.
"""
import argparse, json, shutil, sys, time
from pathlib import Path

try:
    from PIL import Image
except ImportError:
    sys.exit('иска Pillow: pip install Pillow')

КОРЕН = Path(__file__).resolve().parents[1]
ПРОЕКТ = КОРЕН.parents[1]
ПАПКА = ПРОЕКТ / 'assets' / 'lives_images'
КАРТА = КОРЕН / 'work' / 'pages_img.json'
КОПИЯ = КОРЕН / 'backups'

ТАВАН = 1400        # px по дългата страна
КАЧЕСТВО = 82
ПРАГ = 120 * 1024   # под това не си струва да се пипа


def наши(p: Path) -> bool:
    return p.suffix.lower() in ('.jpg', '.jpeg', '.png') and \
        p.name.startswith(('azb_', 'pascha_'))


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('--dry-run', action='store_true')
    a = ap.parse_args()

    файлове = sorted(p for p in ПАПКА.iterdir() if наши(p))
    ново_мерки = {}
    преди = после = 0
    пипнати = 0

    for p in файлове:
        стар = p.stat().st_size
        преди += стар
        im = Image.open(p)
        w, h = im.size
        голям = max(w, h) > ТАВАН
        if not голям and стар < ПРАГ:
            после += стар
            continue
        if голям:
            k = ТАВАН / max(w, h)
            im = im.resize((max(1, round(w * k)), max(1, round(h * k))),
                           Image.LANCZOS)
        # ⚠ PNG-тата стават JPEG само ако НЯМАТ прозрачност — иначе фонът
        # им почернява, а част от тях са икони върху прозрачно.
        прозрачно = im.mode in ('RGBA', 'LA') or \
            (im.mode == 'P' and 'transparency' in im.info)
        if not a.dry_run:
            if прозрачно:
                im.save(p, optimize=True)
            elif p.suffix.lower() == '.png':
                im.convert('RGB').save(p, 'PNG', optimize=True)
            else:
                im.convert('RGB').save(p, 'JPEG', quality=КАЧЕСТВО,
                                       optimize=True, progressive=True)
        нов = p.stat().st_size if not a.dry_run else стар
        после += нов
        пипнати += 1
        ново_мерки[p.name] = im.size

    print('файлове: %d, преработени: %d' % (len(файлове), пипнати))
    print('преди: %.1f MB → след: %.1f MB' % (преди / 1e6, после / 1e6))
    if a.dry_run:
        print('(пробно — нищо не е записано)')
        return 0

    # Мерките в картата — за да не се разминат числата в тага с файла.
    if КАРТА.exists() and ново_мерки:
        КОПИЯ.mkdir(exist_ok=True)
        shutil.copy2(КАРТА, КОПИЯ / ('pages_img.json.bak-%s'
                                     % time.strftime('%Y%m%d_%H%M%S')))
        карта = json.loads(КАРТА.read_text(encoding='utf-8'))
        сменени = 0
        for списък in карта.values():
            for им in списък:
                мерки = ново_мерки.get(им.get('file'))
                if мерки and (им.get('width'), им.get('height')) != мерки:
                    им['width'], им['height'] = мерки
                    сменени += 1
        КАРТА.write_text(json.dumps(карта, ensure_ascii=False, indent=1),
                         encoding='utf-8')
        print('мерки, обновени в pages_img.json: %d' % сменени)
        print('⚠ сега пусни наново: python3 14_apply_pages.py')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
