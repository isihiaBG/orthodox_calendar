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
import re
import pathlib
import sqlite3
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[2] / 'bible_refs'))
import linkify  # noqa: E402

_карта = linkify.abbreviations()

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


# ⚠ Пред неделите, закачени за ЕВАНГЕЛИЕТО си (`G:…`): номерът е по реда на
# неделните евангелия и понякога не съвпада с неделята в календара — бележката
# казва защо. Същият текст (с „главата" вместо „поучението") стои и в
# `tools/lives_plus/scripts/03_build_db.py` — мени ги заедно.
# (Искане на потребителя, 30.09.2026.)
БЕЛЕЖКА_НЕДЕЛЯ = (
    '<p class="memorydate">Номерът на неделята следва реда на неделните '
    'евангелия. След Въздвижение той понякога се разминава с броя на '
    'неделите след Петдесетница в календара (т.нар. отстъпка и преступка '
    'на четивата), затова главата излиза в деня, в който се чете самото '
    'евангелие.</p>\n')


def _неделна(адр: list[str]) -> bool:
    """Неделя след Петдесетница, от ВТОРАТА нататък (първата е Вси светии и
    носи свое заглавие) — по номер или по евангелие."""
    for а in адр:
        m = re.fullmatch(r'W(\d+):7', а)
        if а.startswith('G:') or (m and int(m.group(1)) >= 2):
            return True
    return False


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
        адр = адреси.get(u['id'], [])
        # ⚠ Голото числително („Двадесета") стоеше странно в списъка и в
        # четеца — става „Двадесета неделя". Тук, а не в кеша на превода,
        # за да оцелее при нов превод. (Искане на потребителя, 30.09.2026.)
        if _неделна(адр) and 'недел' not in загл.lower():
            загл += ' неделя'
        # ⚠ Библейските препратки → ДЕЙСТВАЩИ връзки (общият модул
        # tools/bible_refs/linkify.py). До 27.09.2026 тук липсваше и 688
        # препратки у Дебольски стояха като обикновен текст.
        тяло = '<h3>%s</h3>\n' % html.escape(загл) + (
            БЕЛЕЖКА_НЕДЕЛЯ if any(а.startswith('G:') for а in адр) else '') + '\n'.join(
            '<p>%s</p>' % linkify.link(html.escape(b.strip()), _карта)
            for b in bg if b and b.strip())
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
