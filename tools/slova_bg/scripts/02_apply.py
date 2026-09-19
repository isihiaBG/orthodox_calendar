#!/usr/bin/env python3
"""Нанася разчетеното в assets/db/lives_plus.db.

    python3 02_apply.py            # всичко от work/
    python3 02_apply.py --dry-run

⚠⚠ ПУСКА СЕ СЛЕД `tools/lives_plus/scripts/03_build_db.py`, НИКОГА ПРЕДИ.
Той прави `DROP TABLE slova` и сглобява таблицата наново от СВОЯТА папка —
нашият ред не е в нея и изчезва мълчаливо. Същият ред на конвейерите, както
при песнопенията (`16_build_hymns_table.py` преди `06_hymns.py`).

⚠ ИДЕМПОТЕНТЕН ПО УСТРОЙСТВО: нашите редове се разпознават по `book` и се
трият В НАЧАЛОТО на всяко пускане. Оттам повторно пускане дава същото, а не
втори запис — капанът, платен три пъти в другите конвейери.

⚠ БЕЗ РЕД В `slovo_days` — НАРОЧНО. Двете таблици са независими: сложи ли се
и там, словото ще излезе И като ред под светията, И в секцията „СЛОВА ЗА
ДЕНЯ" на същия ден. Изрично искане на потребителя (18.09.2026).
"""
import argparse, json, os, shutil, sqlite3, sys, time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WORK = os.path.join(ROOT, 'work')
PROJ = os.path.dirname(os.path.dirname(ROOT))
DB = os.path.join(PROJ, 'assets', 'db', 'lives_plus.db')
CAL = os.path.join(PROJ, 'assets', 'db', 'calendar_old.db')
# ⚠ Копието ляга ТУК, а не до базата: `pubspec.yaml` включва цялата
# `assets/db/`, тъй че всяко `.bak-…` там пътува в APK-то.
BACKUPS = os.path.join(ROOT, 'backups')

BOOK = 'zlat'          # признакът, по който трием СВОИТЕ редове
ID = {'sv-drosida-rimskaja': 'zlat-001'}

# ⚠⚠ ЕТИКЕТЪТ НА РЕДА В ПЛОЧКАТА — не е заглавието на словото.
#
# Заглавието („Похвала за света великомъченица Дросида, и относно паметта за
# смъртта") е дълго и не казва ЧИЕ е словото; редът под светията трябва да
# се чете от пръв поглед. Затова е отделно поле, зададено на ръка.
# (Изрично искане на потребителя, 18.09.2026.)
LABEL = {'sv-drosida-rimskaja': 'Похвално слово от свт. Йоан Златоуст'}

# ⚠ Таблицата е ИЗЦЯЛО НАША и се пресъздава при всяко пускане — нищо чуждо
# не живее в нея, тъй че няма какво да се загуби, а схемата може да расте,
# без да се пише миграция.
SCHEMA = """
DROP TABLE IF EXISTS slovo_saints;
CREATE TABLE slovo_saints (
    slug  TEXT NOT NULL,         -- слъгът на СВЕТИЯТА (saints.slug)
    id    TEXT NOT NULL,         -- slova.id
    label TEXT NOT NULL,         -- как се казва РЕДЪТ в плочката
    ord   INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (slug, id)
);
CREATE INDEX idx_slovo_saints_slug ON slovo_saints(slug);

-- ⚠ Бележките под линия — СВОИ записи, не опашка в текста. Номерът в
-- четивото е връзка „note://N"; четецът показва текста в изскачащ панел
-- отдолу, както в четеца на книги. Изписани най-долу, същият текст стоеше
-- два пъти и прекъсваше четенето.
DROP TABLE IF EXISTS slovo_notes;
CREATE TABLE slovo_notes (
    id   TEXT NOT NULL,          -- slova.id
    n    TEXT NOT NULL,          -- номерът, както стои в текста
    text TEXT NOT NULL,
    PRIMARY KEY (id, n)
);
"""


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--dry-run', action='store_true')
    a = ap.parse_args()

    recs = []
    for f in sorted(os.listdir(WORK)):
        if f.endswith('.json'):
            recs.append(json.load(open(os.path.join(WORK, f), encoding='utf-8')))
    if not recs:
        sys.exit('няма нищо в work/ — пусни първо 01_parse_odt.py')

    # ⚠ Слъгът се сверява срещу КАЛЕНДАРА, не се приема на доверие: сгрешен,
    # редът влиза в базата и просто никога не се показва — тих отказ.
    cal = sqlite3.connect(CAL)
    for r in recs:
        row = cal.execute(
            'SELECT name FROM saints WHERE slug = ? LIMIT 1', (r['slug'],)).fetchone()
        if not row:
            sys.exit('⚠ слъгът %r го няма в календара' % r['slug'])
        r['saint'] = row[0]
        if r['slug'] not in ID:
            sys.exit('⚠ няма зададен id за %r — впиши го в ID' % r['slug'])
        if r['slug'] not in LABEL:
            sys.exit('⚠ няма етикет за %r — впиши го в LABEL' % r['slug'])
        r['id'] = ID[r['slug']]
        r['label'] = LABEL[r['slug']]
    cal.close()

    for r in recs:
        print('%s → %s' % (r['id'], r['saint']))
        print('   „%s"' % r['title_bg'])
        print('   ред в плочката: „%s"' % r['label'])
        print('   %d знака, източник %s' % (r['chars'], r['source'] or '(няма)'))
    if a.dry_run:
        print('\n--dry-run: нищо не е записано'); return

    os.makedirs(BACKUPS, exist_ok=True)
    bak = os.path.join(BACKUPS, 'lives_plus.db.bak-%s' % time.strftime('%Y%m%d_%H%M%S'))
    shutil.copy2(DB, bak)
    print('\nкопие: %s' % os.path.relpath(bak, PROJ))

    db = sqlite3.connect(DB)
    db.executescript(SCHEMA)
    ids = [r['id'] for r in recs]
    db.execute('DELETE FROM slova WHERE book = ?', (BOOK,))
    for r in recs:
        db.execute(
            'INSERT INTO slova (id, book, address, title_bg, title_ru, body,'
            ' source, chars, why) VALUES (?,?,?,?,?,?,?,?,?)',
            (r['id'], BOOK, '', r['title_bg'], None, r['body'],
             r['source'], r['chars'],
             'собствен превод; прикрепено към %s' % r['slug']))
        db.execute(
            'INSERT INTO slovo_saints (slug, id, label, ord) VALUES (?,?,?,?)',
            (r['slug'], r['id'], r['label'], 0))
        for б in r.get('notes') or []:
            db.execute('INSERT INTO slovo_notes (id, n, text) VALUES (?,?,?)',
                       (r['id'], str(б['n']), б['text']))
    db.commit()

    n_s = db.execute('SELECT count(*) FROM slova').fetchone()[0]
    n_l = db.execute('SELECT count(*) FROM slovo_saints').fetchone()[0]
    n_b = db.execute('SELECT count(*) FROM slovo_notes').fetchone()[0]
    print('бележки:', n_b)
    n_d = db.execute('SELECT count(*) FROM slovo_days WHERE id IN (%s)'
                     % ','.join('?' * len(ids)), ids).fetchone()[0]
    print('слова общо: %d | връзки към светии: %d | дни (трябва 0): %d' % (n_s, n_l, n_d))
    db.close()


if __name__ == '__main__':
    main()
