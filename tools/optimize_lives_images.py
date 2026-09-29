#!/usr/bin/env python3
"""Свива илюстрациите в assets/lives_images/ — ВСИЧКИ, не само azb_*.

    python3 tools/optimize_lives_images.py --dry-run
    python3 tools/optimize_lives_images.py

⚠ ЗАЩО ОТДЕЛНО ОТ tools/paskha/scripts/16_optimize_images.py: онзи пипа само
своите `azb_*`/`pascha_*` и пази PNG като PNG — а 17 от тях са RGBA БЕЗ
ползвана прозрачност, тоест снимки, записани като PNG (до 810 KB на файл).

Правилата:
  • JPEG — таван 1400 px по дългата страна, качество 82; записва се САМО ако
    излиза поне 10% по-лек (иначе повторното кодиране само губи качество).
  • PNG/BMP без ползвана прозрачност — стават .jpg. Името се сменя, тъй че
    препратките се подменят в lives.db (texts.life, articles.body) И в
    изворите на конвейерите (paskha/work/pages_img.json,
    lives_bg/work/images.json и parsed/*.json) — инак следващото сглобяване
    връща старото име към файл, който вече го няма.
  • PNG с истинска прозрачност и GIF — не се пипат.

⚠ Идемпотентен: втори път няма какво да спечели и не пипа нищо.
⚠ Пропорцията се пази, а четецът смята мястото по СЪОТНОШЕНИЕТО в тага.
⚠ Резервно копие на базата — ИЗВЪН хранилището (~/orthodox_calendar_backups).
"""
import argparse, io, json, shutil, sqlite3, sys, time
from pathlib import Path

from PIL import Image

ПРОЕКТ = Path(__file__).resolve().parents[1]
ПАПКА = ПРОЕКТ / 'assets' / 'lives_images'
БАЗА = ПРОЕКТ / 'assets' / 'db' / 'lives.db'
КОПИЯ = Path.home() / 'orthodox_calendar_backups'
ИЗВОРИ = [ПРОЕКТ / 'tools/paskha/work/pages_img.json',
          ПРОЕКТ / 'tools/lives_bg/work/images.json',
          *sorted((ПРОЕКТ / 'tools/lives_bg/work/parsed').glob('*.json'))]

ТАВАН = 1400
КАЧЕСТВО = 82
ПЕЧАЛБА = 0.90      # новото трябва да е под 90% от старото


def jpeg(im: Image.Image) -> bytes:
    w, h = im.size
    if max(w, h) > ТАВАН:
        k = ТАВАН / max(w, h)
        im = im.resize((round(w * k), round(h * k)), Image.LANCZOS)
    if im.mode not in ('RGB', 'L'):
        im = im.convert('RGB')
    b = io.BytesIO()
    im.save(b, 'JPEG', quality=КАЧЕСТВО, optimize=True, progressive=True)
    return b.getvalue()


def прозрачно(im: Image.Image) -> bool:
    if im.mode in ('RGBA', 'LA') or (im.mode == 'P' and 'transparency' in im.info):
        return im.convert('RGBA').getchannel('A').getextrema()[0] < 255
    return False


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('--dry-run', action='store_true')
    a = ap.parse_args()

    преди = после = 0
    презаписи, преименувания = [], {}
    for p in sorted(ПАПКА.iterdir()):
        стар = p.stat().st_size
        преди += стар
        ext = p.suffix.lower()
        im = Image.open(p)
        if ext == '.gif' or прозрачно(im):
            после += стар
            continue
        данни = jpeg(im)
        if ext in ('.jpg', '.jpeg'):
            if len(данни) < стар * ПЕЧАЛБА:
                презаписи.append((p, данни))
                после += len(данни)
            else:
                после += стар
        else:                                   # png / bmp без прозрачност
            нов = p.with_suffix('.jpg')
            if нов.exists():
                sys.exit('сблъсък на имена: %s' % нов.name)
            преименувания[p.name] = (нов, данни)
            после += len(данни)

    print('файлове: %d; презаписани JPEG: %d; превърнати в JPEG: %d'
          % (len(list(ПАПКА.iterdir())), len(презаписи), len(преименувания)))
    print('преди: %.1f MB → след: %.1f MB' % (преди / 1e6, после / 1e6))
    if a.dry_run:
        print('(пробно — нищо не е записано)')
        return 0

    if преименувания:
        КОПИЯ.mkdir(exist_ok=True)
        shutil.copy2(БАЗА, КОПИЯ / ('lives.db.bak-%s' % time.strftime('%Y%m%d_%H%M%S')))

    for p, данни in презаписи:
        p.write_bytes(данни)

    # Първо препратките, после файловете: прекъсне ли се по средата, старите
    # файлове още стоят и нищо не сочи в празното.
    if преименувания:
        con = sqlite3.connect(БАЗА)
        смени = 0
        for таблица, колона in (('texts', 'life'), ('articles', 'body')):
            for старо, (нов, _) in преименувания.items():
                c = con.execute('UPDATE %s SET %s = replace(%s, ?, ?) WHERE %s LIKE ?'
                                % (таблица, колона, колона, колона),
                                (старо, нов.name, '%' + старо + '%'))
                смени += c.rowcount
        con.commit()
        con.close()
        print('реда в lives.db с подменено име: %d' % смени)
        for f in ИЗВОРИ:
            if not f.exists():
                continue
            t = f.read_text(encoding='utf-8')
            t2 = t
            for старо, (нов, _) in преименувания.items():
                t2 = t2.replace(старо, нов.name)
            if t2 != t:
                f.write_text(t2, encoding='utf-8')
                print('извор: %s' % f.relative_to(ПРОЕКТ))
        for старо, (нов, данни) in преименувания.items():
            нов.write_bytes(данни)
            (ПАПКА / старо).unlink()

    # Останали препратки към старите имена = счупена картинка на екрана.
    if преименувания:
        con = sqlite3.connect(БАЗА)
        for старо in преименувания:
            for т, к in (('texts', 'life'), ('articles', 'body')):
                n = con.execute('SELECT count(*) FROM %s WHERE %s LIKE ?' % (т, к),
                                ('%' + старо + '%',)).fetchone()[0]
                if n:
                    print('⚠ ОСТАНАЛА ПРЕПРАТКА: %s в %s.%s' % (старо, т, к))
        con.close()
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
