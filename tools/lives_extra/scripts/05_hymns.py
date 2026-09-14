#!/usr/bin/env python3
"""Изнася песнопенията от разчетените жития в таблица `lives.hymns`.

⚠⚠ ЗАЩО ОТДЕЛНА СТЪПКА, а не част от `apply.py`: текстът на песнопението
влиза в `texts.life` (то е част от четивото и се чете там), но секцията
„Тропар и кондак" в ДНЕВНИЯ изглед се храни от съвсем друга таблица —
`hymns`. Без този запис песнопенията се виждат само ако човек отвори
цялото житие. (Докладвано от потребителя, 05.09.2026.)

⚠ РАБОТИ ВЪРХУ БАЗАТА, не върху разчетеното — затова се пуска СЛЕД
`apply.py`. Признакът е класът `prayerhead`, който apply.py вече слага:
заглавието дава ВИДА и ГЛАСА, а следващият абзац — текста.

⚠ НЕ ПИПА слъгове, които ВЕЧЕ имат песнопения. При 29 от 32-та жития те
идват от azbyka.ru с църковнославянски оригинал и превод — далеч
по-пълни от тукашните. Тази стъпка допълва само празните места.

⚠ АКАТИСТ СЕ ПРОПУСКА. Иверската Монреалска икона има 26 заглавия
(„Кондак 1", „Икос 1", „Кондак 2"…) — това е ЕДНО произведение, а не 26
песнопения. Вкарани поотделно, те биха дали етикет „26 кондака" в дневния
изглед. Признакът е наличието на „Икос".

Пуска се:
    python3 05_hymns.py [--dry-run]
"""
import argparse
import re
import sqlite3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
LIVES_DB = ROOT / 'assets' / 'db' / 'lives.db'

RE_HEAD = re.compile(
    r'<p class="prayerhead"[^>]*>(.*?)</p>\s*(?:<p[^>]*>(.*?)</p>)?', re.S)
RE_TAG = re.compile(r'<[^>]+>')

# ⚠ По тази бележка се разпознават НАШИТЕ редове — виж защо в `main()`.
OUR_NOTE = 'Текстът е от същия източник, от който е и житието.'

# Видът за таблицата — машинният ключ, по който брои `prayersLabel()`.
KINDS = (
    ('tropar', r'тропар'),
    ('kondak', r'кондак'),
    ('velichanie', r'величание'),
    ('molitva', r'молитв'),
    ('stihira', r'стихир'),
    ('ikos', r'икос'),
)


def kind_of(head: str) -> str:
    low = head.lower()
    for key, pat in KINDS:
        if re.search(pat, low):
            return key
    return 'pesnopenie'


def glas_of(head: str) -> str:
    """Гласът, изписан ЕДНАКВО с останалите редове в таблицата.

    ⚠ В базата стои „глас 4", а изворите пишат и „гл. 4", и „глас 4".
    Без уеднаквяване двата вида стоят един до друг в един и същ екран.
    """
    m = re.search(r'(?:глас|гл\.)\s*(\d+)', head, re.I)
    return f'глас {m.group(1)}' if m else ''


def _akatist_body(life: str) -> str:
    """Целият акатист като едно парче — от първия „Кондак 1" до края му.

    ⚠ Взима се ОТ ЧЕТИВОТО, а не се сглобява наново: така редът на
    кондаците и икосите е точно както в източника.

    ⚠ Спира на първия блок СЛЕД акатиста, който не е част от него —
    признакът е, че вече не следват „Кондак"/„Икос"/техните текстове.
    Практически акатистът стои НАКРАЯ на четивото, тъй че краят му е и
    краят на текста; проверката е предпазна мрежа.
    """
    m = re.search(r'<p class="prayerhead"[^>]*>\s*Кондак\s*1\s*</p>', life)
    if not m:
        return ''
    tail = life[m.start():]
    # ⚠ Реже се преди бележките за източник и нашата атрибуция — те не са
    # част от молитвата.
    cut = re.search(r'<p class="(?:source|credit)"', tail)
    if cut:
        tail = tail[:cut.start()]
    return tail.strip()


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument('--dry-run', action='store_true')
    args = ap.parse_args()

    con = sqlite3.connect(LIVES_DB)
    rows = con.execute(
        'SELECT slug, life FROM texts WHERE life LIKE \'%class="prayerhead"%\''
    ).fetchall()

    added = skipped_have = skipped_akat = 0
    for slug, life in rows:
        heads = [RE_TAG.sub('', m.group(1)).strip()
                 for m in RE_HEAD.finditer(life)]
        # ⚠⚠ АКАТИСТЪТ ВЛИЗА КАТО ЕДИН РЕД, не като 26.
        #
        # Той е ЕДНО произведение (13 кондака и 12 икоса), а не сбор от
        # песнопения: вкаран поотделно, дневният изглед би показал етикет
        # „26 кондака". Признакът е наличието на „Икос" — само акатистът
        # редува кондаци с икоси.
        #
        # ⚠ Целият текст влиза в едно поле, със заглавията вътре като
        # получер ред. Така секцията го показва наведнъж, а човек го чете
        # както е в книгата.
        if any(h.lower().startswith('икос') for h in heads):
            body = _akatist_body(life)
            if not body:
                skipped_akat += 1
                continue
            print(f'  + {slug}  #1 akatist  ({len(body)} знака, {len(heads)} части)')
            if not args.dry_run:
                con.execute(
                    'INSERT OR REPLACE INTO hymns '
                    '(slug, ord, kind, kind_ru, seq, glas, csl, bg, note) '
                    'VALUES (?,?,?,?,?,?,?,?,?)',
                    (slug, 1, 'akatist', 'Акатист', 1, '', '', body,
                     OUR_NOTE))
                added += 1
            else:
                added += 1
            continue
        # ⚠⚠ ЧУЖДИТЕ записи се пазят, НАШИТЕ се обновяват.
        #
        # Слъг с песнопения от azbyka.ru (църковнославянски + превод) НЕ се
        # пипа — те са далеч по-пълни. Но собствените ни записи трябва да
        # следват четивото: смени ли се разчитането, текстът в `hymns`
        # остава стар и двете се разминават мълчаливо.
        #
        # Признакът е бележката, с която ги пишем — виж [OUR_NOTE].
        foreign = con.execute(
            'SELECT COUNT(*) FROM hymns WHERE slug=? AND '
            '(note IS NULL OR note <> ?)', (slug, OUR_NOTE)).fetchone()[0]
        if foreign:
            skipped_have += 1
            continue
        con.execute('DELETE FROM hymns WHERE slug=? AND note=?',
                    (slug, OUR_NOTE))

        seq: dict[str, int] = {}
        ordn = 0
        for m in RE_HEAD.finditer(life):
            head = RE_TAG.sub('', m.group(1)).strip()
            body = RE_TAG.sub('', m.group(2) or '').strip()
            if not body:
                continue
            kind = kind_of(head)
            ordn += 1
            seq[kind] = seq.get(kind, 0) + 1
            print(f'  + {slug}  #{ordn} {kind}  «{head}»')
            if not args.dry_run:
                con.execute(
                    'INSERT OR REPLACE INTO hymns '
                    '(slug, ord, kind, kind_ru, seq, glas, csl, bg, note) '
                    'VALUES (?,?,?,?,?,?,?,?,?)',
                    (slug, ordn, kind, head, seq[kind], glas_of(head),
                     # ⚠ ЦЪРКОВНОСЛАВЯНСКИЯТ Е ПРАЗЕН — тези извори дават
                     # само български. Има прецедент: осем превода в
                     # таблицата стоят така (виж CLAUDE.md).
                     '', body,
                     OUR_NOTE))
                added += 1

    if not args.dry_run:
        con.commit()
    print(f'\nдобавени: {added}   пропуснати (вече имат): {skipped_have}   '
          f'акатист: {skipped_akat}')
    if args.dry_run:
        print('--dry-run: НИЩО не е записано')


if __name__ == '__main__':
    main()
