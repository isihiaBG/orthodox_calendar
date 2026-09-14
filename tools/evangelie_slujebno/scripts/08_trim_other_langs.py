"""Пренася отрязването на прокимена от църковнославянския към другите езици.

  python3 08_trim_other_langs.py --lang bg --sample 25

⚠⚠ ДРУГ ЕЗИК = ДРУГИ ДУМИ, тъй че отрязването НЕ може да се измери както за
църковнославянския (там текстът на прокимена е същият, само в друга
графика). Тук се ПРЕНАСЯ по два признака наведнъж:

  1. ДЯЛЪТ от стиха — прокименът покрива думи `от`..`до` от общо `n`;
  2. СНАП към препинателна граница — прокименът почти винаги свършва на
     край на изреченска част (мерено: 253 от 332).

⚠ Само дялът не стига: преводите са с различна дължина и границата пада
насред дума. Само частите не стигат: броят им съвпада едва в 51% от
случаите (мерено). Двата заедно дават граница, която е и на верния дял, и
на естествено място в изречението.

⚠ Не се ли намери граница достатъчно близо, отрязване НЕ се записва и се
показва ЦЕЛИЯТ стих — по установеното правило при цитатите: по-добре малко
повече, отколкото откъс, срязан насред дума.
"""
import argparse
import json
import pathlib
import re
import sqlite3
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from _fold import сгъни  # noqa: E402

КОРЕН = pathlib.Path(__file__).resolve().parents[3]
РАБОТА = pathlib.Path(__file__).resolve().parents[1] / 'work'

RE_ДУМА = re.compile(
    r'(?:[^\W\d_]|[̀-ͯ҃-҉ⷠ-ⷿ꙯])+',
    re.UNICODE)
# ⚠ И ТОЧКАТА Е ГРАНИЦА, когато стихът продължава след нея. Първата версия
# я изключваше („тя е краят на стиха") и с това отказваше пренасяне на
# най-честия прокимен изобщо — Пс. 18:5 (31 срещания), чийто български
# завършва „…до краищата на вселената." насред стиха. Същото за „?" и „!".
RE_ГРАНИЦА = re.compile(r'[,;:.?!]\s|\s[—–-]\s')

# Колко може да се разминат дяловете, преди да се откажем (виж докстринга).
ДОПУСК = 0.18


def дял(текст: str, знак: int) -> float:
    """Каква част от думите на текста стоят преди този знак."""
    думи = list(RE_ДУМА.finditer(текст))
    if not думи:
        return 0.0
    преди = sum(1 for m in думи if m.end() <= знак)
    return преди / len(думи)


def граници(текст: str) -> list[int]:
    """Знаковите места, на които текстът може да се среже."""
    вън = [m.start() + 1 for m in RE_ГРАНИЦА.finditer(текст)]
    return вън


def пренеси(цс: str, отрязване: tuple[int, int], цел: str):
    """(отпред, отзад) за `цел`, или None ако не се намери граница."""
    a, b = отрязване
    if (a, b) == (0, 0):
        return (0, 0)
    нач = дял(цс, a) if a else 0.0
    кр = дял(цс, len(цс) - b) if b else 1.0
    гр = граници(цел)
    нов_a = 0
    нов_b = 0
    if a:
        най = min(гр, key=lambda p: abs(дял(цел, p) - нач), default=None)
        if най is None or abs(дял(цел, най) - нач) > ДОПУСК:
            return None
        нов_a = най
    if b:
        най = min(гр, key=lambda p: abs(дял(цел, p) - кр), default=None)
        if най is None or abs(дял(цел, най) - кр) > ДОПУСК:
            return None
        нов_b = len(цел) - най
    if нов_a + нов_b >= len(цел):
        return None
    return (нов_a, нов_b)


def main() -> None:
    ап = argparse.ArgumentParser()
    ап.add_argument('--lang', default='bg')
    ап.add_argument('--sample', type=int, default=0)
    арг = ап.parse_args()

    db = sqlite3.connect(КОРЕН / 'assets/db/bible.db')
    def карта(език):
        return {f'{k}.{g}:{s}': x for k, g, s, x in db.execute(
            "SELECT book, chapter, verse, text FROM verses WHERE lang = ?",
            (език,))}
    цс, цел = карта('utfcs'), карта(арг.lang)

    данни = json.loads(
        (РАБОТА / 'prokimen_trim.json').read_text(encoding='utf-8'))
    общо = ok = цели = липсва = отказ = 0
    проби = []
    for r in данни:
        за = r['prokimena'] + ([r['alliluia']] if 'alliluia' in r else [])
        for k in за:
            for поле, tr in (k.get('trim') or {}).items():
                ref = (k['ref'] if поле == 'ref'
                       else k['verse_refs'][int(поле[5:])]['ref'])
                общо += 1
                v, w = цс.get(ref), цел.get(ref)
                if not v or not w:
                    липсва += 1
                    continue
                нов = пренеси(v, tuple(tr['utfcs']), w)
                if нов is None:
                    отказ += 1
                    continue
                ok += 1
                if нов == (0, 0):
                    цели += 1
                elif len(проби) < арг.sample:
                    проби.append((ref, v[tr['utfcs'][0]:len(v) - tr['utfcs'][1]],
                                  w[нов[0]:len(w) - нов[1]], w))
                tr[арг.lang] = list(нов)
    (РАБОТА / 'prokimen_trim.json').write_text(
        json.dumps(данни, ensure_ascii=False, indent=1), encoding='utf-8')
    print(f'══ {арг.lang}: общо {общо}')
    print(f'   пренесено : {ok}  (от тях без отрязване: {цели})')
    print(f'   отказано  : {отказ}   няма стих: {липсва}')
    for ref, a, b, цял in проби:
        print(f'\n  {ref}')
        print(f'    цс: {a[:100]}')
        print(f'    {арг.lang}: {b[:100]}')
        print(f'    (цял: {цял[:100]})')


if __name__ == '__main__':
    main()
