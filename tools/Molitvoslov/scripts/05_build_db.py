"""work/aligned.json → assets/db/molitvoslov.db — базата на секция „Молитвослов".

    languages  code, ord, bg_title, bg_abbr, font, size_delta, line_delta, rubricate
    tabs       code, ord, title
    sections   id, tab, ord, title_bg, title_csl
    units      section_id, n, title_bg, title_csl, source_bg
    blocks     section_id, n, lang, ord, kind, html

⚠ ОТДЕЛНА база, не таблици в bible.db: изборът на езици, запомненото място и
всичко останало в молитвослова НЕ бива да пипа Библията (изрично искане на
потребителя). Отделна база прави смесването невъзможно по устройство.

⚠ Мерките на цс шрифта се ВЗИМАТ от bible.db (реда `utfcs`), не се пишат
наново: цс текстът трябва да изглежда еднакво в двата раздела, а там вече са
нагласени на око.

⚠ Раздел без нито един бг блок се пази — четецът скрива бг колоната
(„когато цял раздел няма даден език, тази част от екрана се скрива").
"""
import html
import json
import os
import sqlite3

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APP = os.path.dirname(os.path.dirname(ROOT))
W = os.path.join(ROOT, 'work')
OUT = os.path.join(APP, 'assets', 'db', 'molitvoslov.db')
BIBLE = os.path.join(APP, 'assets', 'db', 'bible.db')

TABS = [('molitvi', 'Молитви'), ('kanonnik', 'Канонник'),
        ('akatisti', 'Акатисти'), ('bogosluzhebni', 'Богослужебни')]

# Българските имена на разделите от цс молитвослова (ред = редът в книгата).
SECTION_BG = {
    1: 'Утринни молитви',
    2: 'Помянник',
    3: 'Вечерни молитви',
    4: 'Три канона: покаен към Господ Иисус Христос, молебен към Пресвета '
       'Богородица и към Ангела пазител',
    5: 'Последование за светото Причастие',
    6: 'Благодарствени молитви след светото Причастие',
    7: 'Правило при осквернение',
    8: 'Часове на света Пасха',
    9: 'Чин на литията за починалите, когато няма свещеник',
    10: 'Чин на литията за починалите, когато няма свещеник — от Томина '
        'неделя до Отдание на Пасха',
    11: 'Чин на дванадесетте псалма',
}

SCHEMA = """
CREATE TABLE languages (code TEXT PRIMARY KEY, ord INTEGER NOT NULL,
    bg_title TEXT NOT NULL, bg_abbr TEXT NOT NULL, font TEXT,
    size_delta REAL NOT NULL DEFAULT 0, line_delta REAL NOT NULL DEFAULT 0,
    rubricate INTEGER NOT NULL DEFAULT 0);
CREATE TABLE tabs (code TEXT PRIMARY KEY, ord INTEGER NOT NULL, title TEXT NOT NULL);
CREATE TABLE sections (id INTEGER PRIMARY KEY, tab TEXT NOT NULL, ord INTEGER NOT NULL,
    title_bg TEXT NOT NULL, title_csl TEXT);
CREATE TABLE units (section_id INTEGER NOT NULL, n INTEGER NOT NULL,
    title_bg TEXT, title_csl TEXT, source_bg TEXT,
    PRIMARY KEY (section_id, n));
CREATE TABLE blocks (section_id INTEGER NOT NULL, n INTEGER NOT NULL,
    lang TEXT NOT NULL, ord INTEGER NOT NULL, kind TEXT NOT NULL, html TEXT NOT NULL,
    PRIMARY KEY (section_id, n, lang, ord));
"""


def main():
    aligned = json.load(open(os.path.join(W, 'aligned.json'), encoding='utf-8'))

    if os.path.exists(OUT):
        os.remove(OUT)
    db = sqlite3.connect(OUT)
    db.executescript(SCHEMA)

    b = sqlite3.connect(BIBLE)
    bg = b.execute("SELECT font, size_delta, line_delta FROM languages WHERE code='bg'").fetchone()
    cs = b.execute("SELECT font, size_delta, line_delta FROM languages WHERE code='utfcs'").fetchone()
    db.execute('INSERT INTO languages VALUES (?,?,?,?,?,?,?,?)',
               ('bg', 1, 'Български', 'бг', bg[0], bg[1], bg[2], 1))
    db.execute('INSERT INTO languages VALUES (?,?,?,?,?,?,?,?)',
               ('csl', 2, 'Църковнославянски', 'цс', cs[0], cs[1], cs[2], 1))
    for i, (code, title) in enumerate(TABS, 1):
        db.execute('INSERT INTO tabs VALUES (?,?,?)', (code, i, title))

    n_units = n_blocks = 0
    for ord_, s in enumerate(aligned, 1):
        sid = s['sec']
        db.execute('INSERT INTO sections VALUES (?,?,?,?,?)',
                   (sid, 'molitvi', ord_, SECTION_BG[sid], s['title_csl']))
        for u in s['units']:
            # Адресите на бг изворите, по един на ред — като `texts.source`.
            db.execute('INSERT INTO units VALUES (?,?,?,?,?)',
                       (sid, u['n'], u['title_bg'], u['title_csl'],
                        '\n'.join(u.get('sources') or []) or None))
            n_units += 1
            for k, blk in enumerate(u['csl']):
                db.execute('INSERT INTO blocks VALUES (?,?,?,?,?,?)',
                           (sid, u['n'], 'csl', k, blk['kind'], blk['html']))
                n_blocks += 1
            for k, blk in enumerate(u['bg']):
                db.execute('INSERT INTO blocks VALUES (?,?,?,?,?,?)',
                           (sid, u['n'], 'bg', k, blk['kind'],
                            html.escape(blk['text'], quote=False)))
                n_blocks += 1
    db.commit()
    print('→', OUT)
    print('  раздели %d · молитви %d · блокове %d' % (len(aligned), n_units, n_blocks))
    for sid, t, nb in db.execute(
            "SELECT s.id, s.title_bg, (SELECT count(*) FROM blocks WHERE section_id=s.id AND lang='bg') "
            "FROM sections s ORDER BY ord"):
        print('  %2d  бг блокове %3d  %s' % (sid, nb, t[:60]))


if __name__ == '__main__':
    main()
