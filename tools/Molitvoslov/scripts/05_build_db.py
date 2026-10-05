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
import re
import json
import os
import sqlite3
import unicodedata

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APP = os.path.dirname(os.path.dirname(ROOT))
W = os.path.join(ROOT, 'work')
OUT = os.path.join(APP, 'assets', 'db', 'molitvoslov.db')
BIBLE = os.path.join(APP, 'assets', 'db', 'bible.db')

TABS = [('molitvi', 'Молитви'), ('kanonnik', 'Канонник'),
        ('akatisti', 'Акатисти'), ('psaltir', 'Псалтир'), ('bogosluzhebni', 'Богослужебни')]

# Българските имена на разделите от цс молитвослова (ред = редът в книгата).
SECTION_BG = {
    1: 'Утринни молитви',
    2: 'Помянник',
    3: 'Вечерни молитви',
    4: 'Три канона: покаен към Господ Иисус Христос, молебен към Пресвета '
       'Богородица и към Ангела пазител',
    5: 'Последование с молитви преди свето Причастие',
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
    title_bg TEXT NOT NULL, title_csl TEXT, source_csl TEXT, source_csr TEXT,
    book TEXT,   -- „Богослужебни": книгата (Часослов, Минеи…) — първото ниво
    grp TEXT,    -- подгрупа в книгата (месецът на Минеята, гласът в Октоиха)
    langs TEXT,  -- наличните езици („bg,csl,csr") — за етикета в съдържанието
    notitle INTEGER);  -- 1 = без горно заглавие (заглавието е в самия текст)
CREATE TABLE units (section_id INTEGER NOT NULL, n INTEGER NOT NULL,
    title_bg TEXT, title_csl TEXT, source_bg TEXT,
    title_cs TEXT,   -- заглавието в ЦС ШРИФТ, където цс текстът е отделен от
                     -- гражданския (акатистите); иначе NULL и важи title_csl
    PRIMARY KEY (section_id, n));
CREATE TABLE blocks (section_id INTEGER NOT NULL, n INTEGER NOT NULL,
    lang TEXT NOT NULL, ord INTEGER NOT NULL, kind TEXT NOT NULL, html TEXT NOT NULL,
    PRIMARY KEY (section_id, n, lang, ord));
"""


RE_BG_PRIPEV = re.compile(r'^Припев:\s*(.+)$', re.S)
# „(поклон)" е указание — винено, както „[Поклон.]" в цс (искане на потребителя).
RE_BG_POKLON = re.compile(r'\((поклон)\)')
RE_BG_DOXA = re.compile(r'^(Слава\.\.\.|И сега\.\.\.)\s+(\S.*)$', re.S)


# Българските текстове, които изворът няма (преводи на потребителя) —
# вмъкват се в съответната единица, за да не зее бг колоната срещу цс.
_MANUAL = json.load(open(os.path.join(os.path.dirname(os.path.dirname(
    os.path.abspath(__file__))), 'input', 'manual_bg.json'), encoding='utf-8'))


def with_manual(sec, n, blocks):
    """⚠ Връща (вид, html); ръчните блокове носят ГОТОВ html (с винени
    указания като „[Трижди]"), затова не минават през bg_blocks."""
    out = bg_blocks(blocks)
    m = _MANUAL.get('%s:%s' % (sec, n))
    if m and m.get('split'):
        # Абзацът се дели пред дадените фрази, КАКТО Е В ЦС (там всеки член
        # на Символа и всяко от 24-те моления стоят на свой ред). Всеки нов
        # ред почва с главна буква — инак остава без червената.
        plain_ = [re.escape(x) for x in m['split'] if not x.startswith('!')]
        bare = [re.escape(x[1:]) for x in m['split'] if x.startswith('!')]
        alts = []
        if plain_:
            alts.append(r'(?<=[.;:!,]) (?=(?:%s))' % '|'.join(plain_))
        if bare:  # „!фраза" — дели се и без препинателен знак пред нея
            alts.append(r' (?=(?:%s))' % '|'.join(bare))
        rx = re.compile('|'.join(alts))
        split = []
        for kind, h in out:
            parts = [x.strip() for x in rx.split(h) if x.strip()] if kind == 'text' else [h]
            split += [(kind, x[:1].upper() + x[1:]) for x in parts]
        out = split
    if m and m.get('blocks'):
        ins = [(b['kind'], b['html']) for b in m['blocks']]
        out = out[:m['after']] + ins + out[m['after']:]
    return out


def bg_blocks(blocks):
    """Българските блокове → (вид, html), в СЪЩОТО построение като цс.

    ⚠ Съответствие между двата езика (указание на потребителя): припевът е
    винен етикет + по-дребен текст, а „Слава..."/„И сега..." стоят на свой
    ред, отделно от тропара след тях — както в цс.
    """
    out = []
    for b in blocks:
        if 'html' in b:
            # ⚠ Готов html (Канонникът: винени „Ирмос:", редове с <br>).
            out.append((b['kind'], b['html']))
            continue
        t = b['text']
        m = RE_BG_PRIPEV.match(t)
        if m:
            out.append(('refrain', '<span class="rubric">Припев:</span> '
                        + html.escape(m.group(1), quote=False)))
            continue
        m = RE_BG_DOXA.match(t) if b['kind'] == 'text' else None
        if m:
            out.append(('text', m.group(1)))
            out.append(('text', html.escape(m.group(2), quote=False)))
            continue
        out.append((b['kind'], html.escape(t, quote=False)))
    return [(k, RE_BG_POKLON.sub(r'<span class="rubric">(\1)</span>', h))
            for k, h in out]


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
    # ⚠ Трети език: цс с ГРАЖДАНСКИ шрифт (с ударения) — „Канонник". Шрифтът
    # е Charis SIL: носи комбиниращото ударение, а системният го слага криво.
    db.execute('INSERT INTO languages VALUES (?,?,?,?,?,?,?,?)',
               ('csr', 3, 'Църковнославянски (граждански шрифт)', 'цс', 'charis', 0, 0, 1))
    for i, (code, title) in enumerate(TABS, 1):
        db.execute('INSERT INTO tabs VALUES (?,?,?)', (code, i, title))

    n_units = n_blocks = 0
    for ord_, s in enumerate(aligned, 1):
        sid = s['sec']
        db.execute('INSERT INTO sections VALUES (?,?,?,?,?,?,?,?,?,NULL,NULL)',
                   (sid, 'molitvi', ord_, SECTION_BG[sid], s['title_csl'],
                    'https://azbyka.ru/molitvoslov/molitvoslov-cerkovnoslavjanskim-shriftom.html',
                    None, None, None))
        for u in s['units']:
            # Адресите на бг изворите, по един на ред — като `texts.source`.
            db.execute('INSERT INTO units VALUES (?,?,?,?,?,NULL)',
                       (sid, u['n'], u['title_bg'], u['title_csl'],
                        '\n'.join(u.get('sources') or []) or None))
            n_units += 1
            for k, blk in enumerate(u['csl']):
                db.execute('INSERT INTO blocks VALUES (?,?,?,?,?,?)',
                           (sid, u['n'], 'csl', k, blk['kind'], blk['html']))
                n_blocks += 1
            for k, (kind, h) in enumerate(with_manual(sid, u['n'], u['bg'])):
                db.execute('INSERT INTO blocks VALUES (?,?,?,?,?,?)',
                           (sid, u['n'], 'bg', k, kind, h))
                n_blocks += 1
    # Акатистите (06_akatisti.py) — цс с граждански шрифт + бг.
    # Акатистите и Канонникът (07_kanonnik.py) — един и същ вид.
    # ⚠ Редът е ОБЩ за всички файлове: Ирмологият (10_irmologii.py) е в таба
    # „Богослужебни" СЛЕД книгите от bogosluzhebni.json — номериран отначало,
    # той би се вмъкнал между тях.
    extra = []
    notitle = []
    for name in ('akatisti.json', 'kanonnik.json', 'psaltir.json', 'bogosluzhebni.json',
                 'parimii.json', 'irmologii.json', 'katavasiinik.json',
                 # Миней празничен, Миней общ, Псалтир с последования (14_hip_books.py).
                 # ⚠ Той чете справката за червеното ОТ ТАЗИ база — затова
                 # сглобяването е два пъти: 05 → 14 → 05.
                 'hip_books.json'):
        path = os.path.join(W, name)
        if os.path.exists(path):
            extra += [(len(extra) + i, s) for i, s in
                      enumerate(json.load(open(path, encoding='utf-8')), 1)]
    for ord_, s in extra:
        sid = s['sec']
        notitle.append(sid) if s.get('notitle') else None
        db.execute('INSERT INTO sections VALUES (?,?,?,?,?,?,?,?,?,NULL,NULL)',
                   (sid, s['tab'], ord_, s['title_bg'], s['title_csl'],
                    s.get('csl_source'), s['csr_source'], s.get('book'), s.get('grp')))
        for u in s['units']:
            db.execute('INSERT INTO units VALUES (?,?,?,?,?,?)',
                       (sid, u['n'], u['title_bg'], u['title_csl'],
                        '\n'.join(u.get('sources') or []) or None, u.get('title_cs')))
            n_units += 1
            # Цс шрифт (06b_akatisti_csl.py) — само за трите основни акатиста.
            for k, blk in enumerate(u.get('csl') or []):
                db.execute('INSERT INTO blocks VALUES (?,?,?,?,?,?)',
                           (sid, u['n'], 'csl', k, blk['kind'], blk['html']))
                n_blocks += 1
            for k, blk in enumerate(u['csr']):
                db.execute('INSERT INTO blocks VALUES (?,?,?,?,?,?)',
                           (sid, u['n'], 'csr', k, blk['kind'], blk['html']))
                n_blocks += 1
            for k, (kind, h) in enumerate(with_manual(sid, u['n'], u['bg'])):
                db.execute('INSERT INTO blocks VALUES (?,?,?,?,?,?)',
                           (sid, u['n'], 'bg', k, kind, h))
                n_blocks += 1
    # Припевите, които изворът не е отбелязал като такива (в Минеите
    # „Припѣ́въ:" стои като гол текст, а на места етикетът е червен, но
    # блокът е минал за обикновен). Четецът ги рисува посивени, тъй че иначе
    # тъкмо те се сливат с тропарите. Признакът е НАЧАЛОТО на блока.
    fold = lambda s: ''.join(ch for ch in unicodedata.normalize('NFD', s)
                             if not unicodedata.combining(ch))
    lead = re.compile(r'^\s*(?:<span class="rubric">)?\s*(Прип[^\s:<]*:)\s*(?:</span>)?\s*')
    for rowid, h in db.execute(
            "SELECT rowid, html FROM blocks WHERE kind = 'text'").fetchall():
        m = lead.match(h)
        if not m or not re.fullmatch(r'Прип[еѣ]въ?:', fold(m.group(1))):
            continue
        db.execute("UPDATE blocks SET kind = 'refrain', html = ? WHERE rowid = ?",
                   ('<span class="rubric">%s</span> %s' % (m.group(1), h[m.end():]),
                    rowid))
    # „пРⷣте́чи", „сРⷣце", „ПРⷣте́чꙋ" — изворите пишат ГЛАВНО Р пред
    # надредното „д" (1660 места, всичките точно „Рⷣ"). Следва ли малка
    # буква, то е малко: „прⷣте́чи", „Прⷣте́чꙋ". Голям надпис („ПРЕДТЕЧИ")
    # не се засяга — там и следващата буква е главна.
    LOWER = 'а-яѐ-џѡѣѥѧѩѫѭѯѱѳѵѹѻѽѿꙁꙃꙅꙇꙉꙋꙍꙏꙑꙓꙕꙗ'
    small_r = re.compile(r'Р(?=\u2de3[\u0300-\u036f\u0483-\u0489]*[%s])' % LOWER)
    for rowid, h in db.execute(
            "SELECT rowid, html FROM blocks WHERE html LIKE '%Р' || char(11747) || '%'"
            ).fetchall():
        db.execute('UPDATE blocks SET html = ? WHERE rowid = ?',
                   (small_r.sub('р', h), rowid))
    for col in ('title_csl', 'title_bg'):
        for sid, t in db.execute('SELECT id, %s FROM sections WHERE %s LIKE ?' % (col, col),
                                 ('%Рⷣ%',)).fetchall():
            db.execute('UPDATE sections SET %s = ? WHERE id = ?' % col,
                       (small_r.sub('р', t), sid))
    for col in ('title_cs', 'title_csl'):
        for rowid, t in db.execute('SELECT rowid, %s FROM units WHERE %s LIKE ?' % (col, col),
                                   ('%Рⷣ%',)).fetchall():
            db.execute('UPDATE units SET %s = ? WHERE rowid = ?' % col,
                       (small_r.sub('р', t), rowid))
    # Раздели, преместени СЛЕД друг (`after`, 14_hip_books.py): редът се
    # пренарежда наново, за да остане `ord` цяло число.
    moves = [(s['sec'], s['after']) for _, s in extra if s.get('after')]
    if moves:
        ids = [r[0] for r in db.execute('SELECT id FROM sections ORDER BY ord')]
        moved = {a for a, _ in moves}
        ids = [x for x in ids if x not in moved]
        for a, after in moves:
            if after not in ids:
                raise SystemExit('⚠ няма раздел %d, след който да застане %d' % (after, a))
            # след `after` и след вече сложените там (пазят реда си)
            i = ids.index(after) + 1
            while i < len(ids) and ids[i] in moved:
                i += 1
            ids.insert(i, a)
        db.executemany('UPDATE sections SET ord = ? WHERE id = ?',
                       [(k, x) for k, x in enumerate(ids, 1)])
    # Раздели без горно заглавие — „Молитви след ставане" в Часослова, където
    # „ЧАСОСЛО́ВЪ" е заглавие на самия текст (виж 09_bogosluzhebni.py).
    db.executemany('UPDATE sections SET notitle = 1 WHERE id = ?',
                   [(x,) for x in notitle])
    # Наличните езици по раздел — изведени от САМИТЕ блокове, за да не се
    # разминат с текста (ред: бг, цс, цс гр.).
    db.execute("""UPDATE sections SET langs = (
        SELECT group_concat(lang) FROM (
          SELECT DISTINCT b.lang FROM blocks b WHERE b.section_id = sections.id
          ORDER BY CASE b.lang WHEN 'bg' THEN 1 WHEN 'csl' THEN 2 ELSE 3 END))""")
    db.commit()
    print('→', OUT)
    print('  раздели %d · молитви %d · блокове %d' % (len(aligned), n_units, n_blocks))
    for sid, t, nb in db.execute(
            "SELECT s.id, s.title_bg, (SELECT count(*) FROM blocks WHERE section_id=s.id AND lang='bg') "
            "FROM sections s ORDER BY ord"):
        print('  %3d  бг блокове %3d  %s' % (sid, nb, t[:60]))


if __name__ == '__main__':
    main()
