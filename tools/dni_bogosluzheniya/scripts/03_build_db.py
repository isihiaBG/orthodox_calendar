#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Главите → таблици `dni` и `dni_days` в `assets/db/lives_plus.db`.

⚠ В СЪЩАТА база като словата, но в СВОИ таблици. `lives_plus/03_build_db.py`
прави `DROP TABLE slova`, не и тези — тъй че двата конвейера не се тъпчат.

⚠⚠ АБЗАЦИТЕ СА ГОЛИ `<p>`. Всеки клас отменя буквицата (`splitDropCap`
търси буквално `<p>…</p>`) — точно така стоте слова бяха без инициал цял
месец (виж CLAUDE.md, 19.09.2026).

⚠ Слъгът Е самият id (`dni-0061`). Трябва да се регистрира на ДВЕ места в
приложението — `lookupBySlug` и `_slugForFingerprint` — инак отметка или
споделен цитат се пазят, но не се отварят.

⚠ Скриптът ПРОВЕРЯВА ПРЕДИ `DROP`: липсващ превод, разминат брой блокове или
липсващо заглавие спират всичко, преди таблицата да е пипната.
"""
import html
import json
import pathlib
import sqlite3
import sys

КОРЕН = pathlib.Path(__file__).resolve().parent.parent
РАБОТА = КОРЕН / 'work'
БАЗА = КОРЕН.parent.parent / 'assets' / 'db' / 'lives_plus.db'
ИЗТОЧНИК = ('https://azbyka.ru/otechnik/Grigorij_Debolskij/'
            'dni-bogosluzhenija-pravoslavnoj-kafolicheskoj-vostochnoj-tserkvi-tom-2/')

# Видимите имена на дяловете — за „Читалня" и за подзаглавието.
ДЯЛОВЕ = {
    'Часть III. Дни постные': 'Постни дни',
    'Часть IV. Дни богослужения церковные': 'Църковни дни на богослужение',
    'Часть V. Недели и другие дни цветной триоди или пятидесятницы':
        'Недели и дни на Цветния триод',
    'Страстная седмица': 'Страстна седмица',
    'Часть VI. Дни седмицы': 'Дни от седмицата',
    'Дни поминовения ежегодные': 'Годишни дни за поменаване',
}


def main() -> int:
    units = [json.loads(f.read_text(encoding='utf-8'))
             for f in sorted((РАБОТА / 'units').glob('*.json'))]
    заглавия = json.loads((РАБОТА / 'titles_bg.json').read_text(encoding='utf-8'))
    адреси = json.loads((РАБОТА / 'addresses.json').read_text(encoding='utf-8'))

    редове, грешки = [], []
    for u in units:
        f = РАБОТА / 'translated' / (u['id'] + '.json')
        if not f.exists():
            грешки.append('няма превод: ' + u['id']); continue
        bg = json.loads(f.read_text(encoding='utf-8')).get('blocks_bg') or []
        if len(bg) != len(u['blocks_ru']):
            грешки.append('%s: %d блока руски, %d български'
                          % (u['id'], len(u['blocks_ru']), len(bg))); continue
        if u['id'] not in заглавия:
            грешки.append('няма заглавие: ' + u['id']); continue
        загл = заглавия[u['id']].strip()
        тяло = '<h3>%s</h3>\n' % html.escape(загл) + '\n'.join(
            '<p>%s</p>' % html.escape(b.strip()) for b in bg if b and b.strip())
        дял = ДЯЛОВЕ.get((u['path'] or [''])[-1], '')
        редове.append((u['id'], int(u['order']), дял, загл, u['title_ru'],
                       тяло, ИЗТОЧНИК, sum(len(b) for b in bg)))
    if грешки:
        print('\n'.join('⚠ ' + g for g in грешки), file=sys.stderr)
        raise SystemExit('НЕ пипам базата — %d проблема' % len(грешки))

    db = sqlite3.connect(БАЗА)
    db.executescript('''
        DROP TABLE IF EXISTS dni;
        DROP TABLE IF EXISTS dni_days;
        CREATE TABLE dni (
            id        TEXT PRIMARY KEY,   -- и слъг: dni-0061
            ord       INTEGER NOT NULL,   -- редът в книгата
            part_bg   TEXT NOT NULL,      -- дялът, на български
            title_bg  TEXT NOT NULL,
            title_ru  TEXT,
            body      TEXT NOT NULL,      -- готово HTML, голи <p>
            source    TEXT NOT NULL DEFAULT '',
            chars     INTEGER NOT NULL
        );
        CREATE TABLE dni_days (
            id      TEXT NOT NULL,
            address TEXT NOT NULL,        -- същата схема като словата
            PRIMARY KEY (id, address)
        );
        CREATE INDEX idx_dni_days_address ON dni_days(address);
    ''')
    db.executemany('INSERT INTO dni VALUES (?,?,?,?,?,?,?,?)', редове)
    db.executemany('INSERT INTO dni_days VALUES (?,?)',
                   [(i, a) for i, aa in адреси.items() for a in aa])
    db.commit()
    n, d = db.execute('SELECT count(*) FROM dni').fetchone()[0], \
        db.execute('SELECT count(*) FROM dni_days').fetchone()[0]
    print('глави: %d | връзки към дни: %d | знаци: %s'
          % (n, d, format(sum(r[7] for r in редове), ',').replace(',', ' ')))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
