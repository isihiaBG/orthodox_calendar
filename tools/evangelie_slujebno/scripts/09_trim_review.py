"""Списък за ПРЕГЛЕД на отрязването по език.

  python3 09_trim_review.py --lang bg     # → input/prokimen_trim_<език>.csv

⚠⚠ ЗАЩО ИМА ПРЕГЛЕД. За църковнославянския отрязването се МЕРИ — текстът
на прокимена е същият, само в друга графика. За българския се ПРЕНАСЯ по
дял от стиха и препинателна граница ([08_trim_other_langs]), а СЛОВОРЕДЪТ
на двата езика се разминава: цс „Исповѣдятъ небеса чудеса твоя, Господи"
слага „чудеса" пред звателното, а българският го слага СЛЕД него, тъй че
автоматичната граница реже твърде рано.

⚠ Случаите са само 80 различни при 876 повиквания (най-честият се среща 31
пъти), тъй че ръчният преглед е по джоба ни, а гаданието — не.

⚠ КОЛОНАТА ЗА ПОПРАВКА Е САМИЯТ ТЕКСТ, не отместване в знаци. Числата не
се проверяват с очи, а текстът — да; а и при следваща поправка в превода
отместването остарява мълчаливо, докато текстът се намира наново.
"""
import argparse
import csv
import json
import pathlib
import re
import sqlite3
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from _fold import сгъни  # noqa: E402

КОРЕН = pathlib.Path(__file__).resolve().parents[3]
ГНЕЗДО = pathlib.Path(__file__).resolve().parents[1]

RE_ДУМА = re.compile(r'(?:[^\W\d_]|[̀-ͯ҃-҉ⷠ-ⷿ꙯])+', re.UNICODE)


def брой_думи(s: str) -> int:
    return len(RE_ДУМА.findall(s))


def main() -> None:
    ап = argparse.ArgumentParser()
    ап.add_argument('--lang', default='bg')
    арг = ап.parse_args()
    db = sqlite3.connect(КОРЕН / 'assets/db/bible.db')

    def карта(език):
        return {f'{k}.{g}:{s}': x for k, g, s, x in db.execute(
            "SELECT book, chapter, verse, text FROM verses WHERE lang = ?",
            (език,))}
    цс, цел = карта('utfcs'), карта(арг.lang)

    данни = json.loads(
        (ГНЕЗДО / 'work/prokimen_trim.json').read_text(encoding='utf-8'))
    случаи: dict[tuple, dict] = {}
    for r in данни:
        за = r['prokimena'] + ([r['alliluia']] if 'alliluia' in r else [])
        for k in за:
            for поле, tr in (k.get('trim') or {}).items():
                ref = (k['ref'] if поле == 'ref'
                       else k['verse_refs'][int(поле[5:])]['ref'])
                a, b = tr['utfcs']
                if (a, b) == (0, 0):
                    continue
                ключ = (ref, a, b)
                зап = случаи.setdefault(ключ, {'n': 0})
                зап['n'] += 1
                зап['cs'] = цс[ref][a:len(цс[ref]) - b]
                зап['full'] = цел.get(ref, '')
                п = tr.get(арг.lang)
                зап['proposal'] = (
                    зап['full'][п[0]:len(зап['full']) - п[1]] if п else '')

    редове = []
    for (ref, a, b), з in sorted(случаи.items(), key=lambda x: -x[1]['n']):
        if not з['full']:
            белег = 'НЯМА СТИХ'
        elif not з['proposal']:
            белег = 'НЕ Е ПРЕНЕСЕНО'
        else:
            # ⚠ Дял на думите — цс срещу целевия. Разминат ли се силно,
            # границата почти сигурно е паднала на грешно място.
            дцс = брой_думи(з['cs']) / max(брой_думи(цс[ref]), 1)
            дц = брой_думи(з['proposal']) / max(брой_думи(з['full']), 1)
            белег = 'ПРОВЕРИ' if abs(дцс - дц) > 0.15 else ''
        редове.append({
            'ref': ref, 'n': з['n'], 'flag': белег,
            'cs': з['cs'], 'proposal': з['proposal'], 'full': з['full'],
        })

    път = ГНЕЗДО / f'input/prokimen_trim_{арг.lang}.csv'
    with път.open('w', encoding='utf-8', newline='') as f:
        w = csv.writer(f)
        w.writerow(['ref', 'срещания', 'белег',
                    'църковнославянски (мерен)',
                    f'{арг.lang} — ПОПРАВИ ТУК', 'целият стих'])
        for r in редове:
            w.writerow([r['ref'], r['n'], r['flag'], r['cs'],
                        r['proposal'], r['full']])
    зап = sum(1 for r in редове if r['flag'])
    print(f'случаи с отрязване: {len(редове)}   за проверка: {зап}')
    print(f'→ {път.relative_to(ГНЕЗДО)}')


if __name__ == '__main__':
    main()
