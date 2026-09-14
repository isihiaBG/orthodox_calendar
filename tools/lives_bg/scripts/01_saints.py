#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Вади българските светии от календара и ги свежда до търсими имена.

Изход: `work/saints_bg.json` — по един запис на СВЕТИЯ (не на ред в базата).

⚠ Календарната база носи ПО НЯКОЛКО ГОДИНИ (2025–2027), тъй че всеки светия
има по един ред за всяка от тях — 207 реда за 68 души. Дедупликацията е по
ядрото на името, а не по `id`: той е AUTOINCREMENT и се преномерира при всяко
пускане на `merge_years.py` (виж CLAUDE.md).

⚠ Църковната дата се извежда от гражданската с −13 дни, но САМО за
неподвижните. Подвижните („преходно празнуване в неделя 3-та след Пасха")
падат на различен ден всяка година; за тях `church_date` остава None и
съпоставянето по дата не важи. Разпознават се емпирично: щом трите години
дават три различни църковни дати, денят е подвижен.
"""

from __future__ import annotations

import json
import sqlite3
from collections import defaultdict
from datetime import date, timedelta

from common import (CALENDAR_DB, JULIAN_OFFSET, LIVES_DB, WORK, core_name,
                    fold, transliterate)

# Житие под този праг е кратка бележка, а не четиво — такъв светия също влиза
# в списъка за търсене. Прагът е на око, но разделя ясно: наличните са или под
# 3 300 знака (едноредови справки), или над 6 800 (същински жития).
SHORT_LIFE = 3500


def church_date(civil: str) -> str:
    """Гражданска дата „ГГГГ-ММ-ДД" → църковна „ММ-ДД"."""
    y, m, d = (int(x) for x in civil.split('-'))
    return (date(y, m, d) - timedelta(days=JULIAN_OFFSET)).strftime('%m-%d')


def main() -> None:
    con = sqlite3.connect(f'file:{CALENDAR_DB}?mode=ro', uri=True)
    con.execute(f"ATTACH DATABASE 'file:{LIVES_DB}?mode=ro' AS lives")

    rows = con.execute("""
        SELECT s.id, s.date, s.name, s.rank, s.slug,
               COALESCE(LENGTH(t.life), 0) AS life_len
          FROM saints s
     LEFT JOIN lives.texts t ON t.slug = s.slug
         WHERE s.group_code = 'BG'
      ORDER BY s.date
    """).fetchall()
    con.close()

    # Групиране по ядрото на името — то е общото между годините.
    grouped: dict[str, list] = defaultdict(list)
    for row in rows:
        grouped[fold(core_name(row[2]))].append(row)

    saints = []
    for key, group in grouped.items():
        # Най-дългото изписване е и най-подробното — него пазим за показване.
        full = max((r[2] for r in group), key=len)
        core = core_name(full)

        civil_dates = sorted({r[1] for r in group})
        church = sorted({church_date(d) for d in civil_dates})
        # Един и същ църковен ден през всичките години → неподвижен.
        movable = len(church) > 1
        slug = next((r[4] for r in group if r[4]), None)
        life_len = max(r[5] for r in group)

        saints.append({
            'key': key,
            'name_full': full,
            'name_core': core,
            'name_latin': transliterate(core),
            'rank': min(r[3] for r in group if r[3] is not None) if any(
                r[3] is not None for r in group) else None,
            'slug': slug,
            'life_len': life_len,
            'church_date': None if movable else church[0],
            'church_dates': church,
            'movable': movable,
            'civil_dates': civil_dates,
            'rows': len(group),
            # Защо търсим този светия — влиза в отчета, за да е ясно от пръв
            # поглед кои са същинските празноти.
            'need': ('no_slug' if not slug
                     else 'short' if life_len < SHORT_LIFE
                     else 'ok'),
        })

    saints.sort(key=lambda s: (s['church_date'] or 'zz', s['name_core']))

    WORK.mkdir(parents=True, exist_ok=True)
    out = WORK / 'saints_bg.json'
    out.write_text(json.dumps(saints, ensure_ascii=False, indent=2),
                   encoding='utf-8')

    need = defaultdict(int)
    for s in saints:
        need[s['need']] += 1

    print(f'редове в базата:        {len(rows)}')
    print(f'различни светии:        {len(saints)}')
    print(f'  без слъг (нищо):      {need["no_slug"]}')
    print(f'  кратка бележка:       {need["short"]}  (< {SHORT_LIFE} знака)')
    print(f'  със същинско житие:   {need["ok"]}')
    print(f'  от тях подвижни:      {sum(1 for s in saints if s["movable"])}')
    print(f'\n→ {out.relative_to(out.parents[2])}')


if __name__ == '__main__':
    main()
