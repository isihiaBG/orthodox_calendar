#!/usr/bin/env python3
"""Преведеното → `assets/db/lives_plus.db`.

⚠ ОТДЕЛНА БАЗА, не се ATTACH-ва — както `teofan.db` и `optina.db`. Секцията
„Слова за деня" я чете сама и нищо в календарната база не се пипа.

⚠ АДРЕСЪТ Е СЪЩИЯТ КАТО НА ЧЕТИВАТА (`lib/readings_lookup.dart`):

    W<седм>:<ден>   по Петдесетница        P<седм>:<ден>   Пентикостар
    T<седм>:<ден>   Триод                  ММ-ДД           ЦЪРКОВНА дата
    ММ-ДД|ден|before/after                 fast | memorial

Тъй че приложението не въвежда втора система за адресиране, а пита същата.

    python3 03_build_db.py
"""
import html as _html
import json
import re
import sqlite3
import sys
from pathlib import Path

КОРЕН = Path(__file__).resolve().parents[1]
РАБОТА = КОРЕН / 'work'
ЦЕЛ = КОРЕН.parents[1] / 'assets' / 'db' / 'lives_plus.db'

СХЕМА = """
DROP TABLE IF EXISTS slova;
CREATE TABLE slova (
    id        TEXT PRIMARY KEY,
    book      TEXT NOT NULL,      -- vosk / nepe / pril
    address   TEXT NOT NULL,
    title_bg  TEXT NOT NULL,
    title_ru  TEXT,
    body      TEXT NOT NULL,      -- готово HTML, както го чака четецът
    -- ⚠ Адресът на оригинала в azbyka.ru. Четецът го изписва накрая през
    -- `_sourceHtml()` — сайтът изисква коректно цитиране.
    source    TEXT NOT NULL DEFAULT '',
    chars     INTEGER NOT NULL,
    why       TEXT                -- как е стигнал до този адрес
);
CREATE INDEX idx_slova_address ON slova(address);
"""


RE_КОТВА = re.compile(r'(<a\b[^>]*>.*?</a>)', re.S)


def тяло(блокове: list[str]) -> str:
    """Абзаците → HTML за четеца на жития.

    ⚠ Класът е `paragraph`, същият като в томовете — оттам идват и буквицата,
    и мерките. Нов клас би искал ред в `reader_styles.dart`.

    ⚠⚠ ЕКРАНИРА СЕ САМО ТЕКСТЪТ ИЗВЪН КОТВИТЕ. Дотук тук стоеше голо
    `html.escape(b)` — вярно, докато абзаците бяха гол текст, но след като
    `05_bible_links.py` започна да слага `<a>` тагове, то ги превръщаше в
    `&lt;a href=…&gt;` и те се ИЗПИСВАХА на екрана като текст вместо да са
    връзки. (Забелязано от потребителя върху готов билд, 13.09.2026.)

    ⚠ Котвата се оставя както е — вътре в нея стои само препратка към
    Писанието („Мат. 5:1“), а `&amp;` в адреса вече е в правилния си вид и
    повторно екраниране би го счупило.
    """
    def _абзац(b: str) -> str:
        части = RE_КОТВА.split(b)
        тяло_ = ''.join(ч if ч.startswith('<a') else _html.escape(ч)
                        for ч in части)
        return f'<p class="paragraph">{тяло_}</p>'

    return '\n'.join(_абзац(b) for b in блокове if b.strip())


def main() -> int:
    преведени = sorted((РАБОТА / 'translated').glob('*.json'))
    if not преведени:
        sys.exit('няма преводи в work/translated/')
    заглавия = {}
    п = РАБОТА / 'titles_bg.json'
    if п.exists():
        заглавия = json.loads(п.read_text(encoding='utf-8'))
    връзки = {}
    в = РАБОТА / 'source_links.json'
    if в.exists():
        връзки = json.loads(в.read_text(encoding='utf-8'))

    ЦЕЛ.parent.mkdir(parents=True, exist_ok=True)
    db = sqlite3.connect(ЦЕЛ)
    db.executescript(СХЕМА)
    без_заглавие, изхвърлени, без_връзка = [], [], []
    # ⚠⚠ АДРЕСЪТ СЕ ЧЕТЕ ОТ `units/`, НЕ ОТ ПРЕВОДА. Преводът носи копие на
    # дяла отпреди часове; поправка в адресирането след това не би стигнала
    # до базата и щеше да мине мълчаливо. Адресът е свойство на ДЯЛА, не на
    # превода му — тъй че се взима от единствения му източник.
    for f in преведени:
        x = json.loads(f.read_text(encoding='utf-8'))
        прясно = РАБОТА / 'units' / f.name
        # ⚠ Няма ли го вече в `units/`, дялът е ИЗХВЪРЛЕН след превода си —
        # преводът остава на диска, но в базата не влиза.
        if not прясно.exists():
            изхвърлени.append(x['id'])
            continue
        u = json.loads(прясно.read_text(encoding='utf-8'))
        x['address'], x['why'] = u['address'], u.get('why', '')
        x['title_ru'] = u['title_ru']
        bg = заглавия.get(x['id'])
        if not bg:
            без_заглавие.append(x['id'])
            bg = x['title_ru']
        тяло_ = тяло(x['blocks_bg'])
        src = (връзки.get(x['id']) or {}).get('url', '')
        if not src:
            без_връзка.append(x['id'])
        db.execute(
            'INSERT INTO slova (id, book, address, title_bg, title_ru, body,'
            ' chars, why, source) VALUES (?,?,?,?,?,?,?,?,?)',
            (x['id'], x['book'], x['address'], bg, x['title_ru'], тяло_,
             len(тяло_), x.get('why', ''), src))
    db.commit()

    n = db.execute('SELECT COUNT(*) FROM slova').fetchone()[0]
    по_вид = db.execute("""
        SELECT CASE
            WHEN address IN ('fast','memorial') THEN 'повод'
            WHEN instr(address,'|') > 0 THEN 'закотвен'
            WHEN substr(address,1,1) IN ('T','P','W') THEN 'подвижен'
            ELSE 'неподвижен' END AS вид, COUNT(*)
        FROM slova GROUP BY вид ORDER BY 2 DESC""").fetchall()
    print(f'{n} слова → {ЦЕЛ.relative_to(КОРЕН.parents[1])}'
          f'  ({ЦЕЛ.stat().st_size / 1024:.0f} KB)')
    for вид, брой in по_вид:
        print(f'  {вид:12} {брой:>4}')
    if без_връзка:
        print(f'⚠ БЕЗ ВРЪЗКА КЪМ ИЗТОЧНИКА: {len(без_връзка)} '
              f'— пусни 04_source_links.py')
    if изхвърлени:
        print(f'преводи на изхвърлени дялове (не влизат): {изхвърлени}')
    if без_заглавие:
        print(f'⚠ без преведено заглавие: {len(без_заглавие)} '
              f'— пусни 02b_translate_titles.py')
    # ⚠ Дни с ПО НЯКОЛКО слова са нормални (първо и второ слово за същия
    # празник) — изписват се, за да личи, че не са грешка.
    много = db.execute('SELECT address, COUNT(*) c FROM slova GROUP BY address'
                       ' HAVING c > 1 ORDER BY c DESC').fetchall()
    if много:
        print(f'адреси с повече от едно слово: {len(много)}')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
