#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Маха изрично изключени илюстрации ЗАЕДНО с надписите им.

Вход/изход: `work/parsed/*.json` (пипа ги на място)
⚠ ПОСЛЕДНА стъпка — след `10_captions.py`, преди `06_apply.py`.

## Защо накрая, а не по-рано

Опитано е и двете други места, и двете не работят:

  в `09_place_images.py` — там надписът е още обикновен `<p>` (класът
      `caption` се слага чак в 10-та стъпка), тъй че не се разпознава. А
      картинката вече я няма и 10-та стъпка услужливо премята осиротелия
      надпис под СЪСЕДНОТО изображение — при св. Кирил той се озова под
      снимката на гроба, където описваше съвсем друго.

  вътре в `10_captions.py` — същото, само че в друг ред: каквото и да се
      направи, едната от двете операции работи с непълни данни.

⚠ Затова изключването е ОТДЕЛНА, ПОСЛЕДНА стъпка. Тогава всичко е вече
съотнесено — надписите стоят под картинките си и с готов клас — и махането
е просто изрязване на съседна двойка. Идеята е на потребителя (30.08.2026).

## Кое се маха

`input/exclude_images.csv`, колони `file,note`. Всеки ред е РЕДАКТОРСКО
решение и носи обяснението си — виж бележките там.
"""

from __future__ import annotations

import argparse
import csv
import json
import re

from common import INPUT, WORK


def load_excluded() -> list[dict]:
    """Редовете от `input/exclude_images.csv`.

    Колони: `file` (име в assets), `caption_contains` (по избор — част от
    надписа), `note` (защо).

    ⚠ `caption_contains` НЕ Е излишен. Стъпка 10 премества надписите под
    най-близката картинка — и когато две изображения стоят едно до друго,
    надписът на изключеното може да се озове под СЪСЕДНОТО. При св. Кирил
    точно това стана: надписът за папата слезе под снимката на гроба и
    вече не се разпознаваше като негов. Посочен изрично, той се маха
    независимо къде е попаднал.
    """
    path = INPUT / 'exclude_images.csv'
    if not path.exists():
        return []
    with path.open(encoding='utf-8') as fh:
        return [{'file': r['file'].strip(),
                 'caption': (r.get('caption_contains') or '').strip(),
                 'note': (r.get('note') or '').strip()}
                for r in csv.DictReader(fh) if r.get('file')]


def strip_image(html: str, filename: str, caption: str = '') -> tuple[int, int]:
    """Маха картинката и надписа ѝ. Връща (нов html, махнати картинки,
    махнати надписи) — виж повикващия."""
    esc = re.escape(filename)

    # 1. Картинката, заедно с надписа веднага под нея (обичайният случай).
    pattern = re.compile(
        r'<img[^>]*src="[^"]*' + esc + r'"[^>]*>\s*'
        r'(?:<p class="caption">.*?</p>\s*)?',
        re.S | re.I)
    out, n_img = pattern.subn('', html)

    # 2. Или надписът е стоял ПРЕД нея и не се е преместил.
    pattern_before = re.compile(
        r'<p class="caption">.*?</p>\s*<img[^>]*src="[^"]*' + esc + r'"[^>]*>\s*',
        re.S | re.I)
    out, n2 = pattern_before.subn('', out)
    n_img += n2

    # 3. ⚠ Надписът, посочен ИЗРИЧНО — където и да е попаднал. Това е
    # спасителната мрежа за случая, в който стъпка 10 го е преместила под
    # съседна картинка. Без нея той остава да описва чуждо изображение.
    n_cap = 0
    if caption:
        # ⚠ БЕЗ ИЗИСКВАНЕ за клас `caption`. Надписът невинаги го получава:
        # когато до картинката стои ДРУГ надпис (при св. Кирил — този за
        # гроба), той заема мястото ѝ, а нежеланият остава обикновен абзац.
        # Търсен само като `<p class="caption">`, той оцеляваше и се появяваше
        # в четивото БЕЗ своята картинка. (Докладвано 31.08.2026.)
        cap_pattern = re.compile(
            r'<p(?:\s+class="[^"]*")?>(?:(?!</p>).)*?' + re.escape(caption) +
            r'.*?</p>\s*', re.S | re.I)
        out, n_cap = cap_pattern.subn('', out)

    return re.sub(r'\n{3,}', '\n\n', out), n_img, n_cap


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument('--dry-run', action='store_true')
    args = ap.parse_args()

    excluded = load_excluded()
    if not excluded:
        print('няма изключени илюстрации (input/exclude_images.csv е празен)')
        return

    print(f'изключени по решение: {len(excluded)}')
    for row in excluded:
        print(f'   {row["file"]}')
        if row['caption']:
            print(f'      надпис: „{row["caption"]}…"')
    print()

    removed = touched = 0
    for path in sorted((WORK / 'parsed').glob('*.json')):
        rec = json.loads(path.read_text(encoding='utf-8'))
        html = rec['life_html']
        if '<img' not in html:
            continue
        new_html = html
        got = caps = 0
        for row in excluded:
            new_html, n_img, n_cap = strip_image(
                new_html, row['file'], row['caption'])
            got += n_img
            caps += n_cap
        if not got and not caps:
            continue
        removed += got
        touched += 1
        print(f'  {rec["name_core"][:42]:44} картинки {got}, надписи {caps}')
        if not args.dry_run:
            rec['life_html'] = new_html
            path.write_text(json.dumps(rec, ensure_ascii=False, indent=2),
                            encoding='utf-8')

    print(f'\nмахнати илюстрации: {removed}  в {touched} жития')
    if args.dry_run:
        print('--dry-run: нищо не е записано')
    else:
        print('\n⚠ Файловете в assets/lives_images/ ОСТАВАТ — чистят се при '
              'следващото пускане на 09_place_images.py (осиротелите).')


if __name__ == '__main__':
    main()
