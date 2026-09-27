#!/usr/bin/env python3
"""Преведените слова → assets/db/lives_plus.db.

    python3 02_build_db.py --dry-run
    python3 02_build_db.py

⚠⚠ РЕДЪТ НА КОНВЕЙЕРИТЕ: пуска се СЛЕД `tools/lives_plus/scripts/03_build_db.py`
(той прави `DROP TABLE slova` и `slovo_days`) — също както
`tools/slova_bg/scripts/02_apply.py`. Двата вече НЕ пресъздават
`slovo_saints`/`slovo_notes`, а трият само своите редове, тъй че помежду си
редът им е без значение.

⚠ ИДЕМПОТЕНТЕН: нашите редове се познават по `book` (`justin`,
`zl-svyatii`) и се трият в началото на всяко пускане.

⚠⚠ ПРОВЕРКИТЕ СА ПРЕДИ ЗАПИСА: липсващ превод, разминат брой блокове,
слъг, който го няма в календара — спира, преди да е пипнато нещо.

Какво се вписва:
  • slova         — текстът (голи <p>, за да има буквица);
  • slovo_notes   — бележките, а в текста номер с връзка „note://N";
  • slovo_saints  — беседите на Златоуст като ред под светията;
  • slovo_days    — словото на прп. Юстин в „Слова за деня" в дните на
                    съборите на светии, и беседата на Златоуст за всички
                    светии — в Неделята на всички светии.
"""
import argparse
import html
import importlib.util
import json
import re
import shutil
import sqlite3
import sys
import time
from pathlib import Path

КОРЕН = Path(__file__).resolve().parents[1]
ПРОЕКТ = КОРЕН.parents[1]
РАБОТА = КОРЕН / 'work'
БАЗА = ПРОЕКТ / 'assets' / 'db' / 'lives_plus.db'
СЕМЕ = ПРОЕКТ / 'tools' / 'calendar_gen' / 'input' / 'db' / 'calendar_old.db'
КОПИЯ = КОРЕН / 'backups'

# Библейските връзки — СЪЩАТА функция като в словата на свт. Димитрий.
_сп = importlib.util.spec_from_file_location(
    'bl', ПРОЕКТ / 'tools' / 'lives_plus' / 'scripts' / '05_bible_links.py')
_bl = importlib.util.module_from_spec(_сп)
_сп.loader.exec_module(_bl)

КНИГА = {'justin': 'justin', 'zl': 'zl-svyatii'}

# ⚠ Заглавия, които в книгата стоят като подзаглавия на група и сами не
# казват за кого са („Беседа вторая") — за списъка и за лентата на четеца.
ЗАГЛАВИЯ = {
    'zl-14': 'Първа похвална беседа за света мъченица Пелагия Антиохийска',
    'zl-15': 'Втора беседа за света мъченица Пелагия Антиохийска',
    'zl-16': 'Първо похвално слово за свети мъченик Роман',
    'zl-24': 'Беседа в памет на свети Вас',
}

З = 'свт. Йоан Златоуст'
# Беседите на Златоуст → светиите (слъг в календара, етикет на реда).
# ⚠ Етикетът казва честно, когато словото е само ПРИПИСВАНО на Златоуст —
# самото издание го отбелязва (Spuria / съмнително по слог).
КЪМ_СВЕТИИ = {
    'zl-01': [('sv-lukian-antiohijskij', f'Похвално слово от {З}')],
    'zl-02': [('svv-sem-muchenikov-makkaveev', f'Първа беседа за светите Макавеи от {З}')],
    'zl-03': [('svv-sem-muchenikov-makkaveev', f'Втора беседа за светите Макавеи от {З}')],
    'zl-04': [('svv-sem-muchenikov-makkaveev', f'Трета беседа за светите Макавеи от {З}')],
    'zl-05': [('sv-meletij-antiohijskij', f'Похвално слово от {З}')],
    'zl-09': [('sv-stefan-pervomuchenik', f'Слово, приписвано на {З}')],
    'zl-10': [('sv-evstafij-antiohijskij', f'Похвално слово от {З}')],
    'zl-11': [('sv-foka-sinopskij', f'Беседа от {З}')],
    'zl-12': [('sv-ignatij-bogonosec', f'Похвално слово от {З}'),
              ('prazdnik-perenesenie-moshhej-sshhmch-ignatija-bogonosca',
               f'Похвално слово от {З}')],
    'zl-13': [('sv-mchci-juventin-i-maksim', f'Похвална беседа от {З}')],
    'zl-14': [('sv-pelagija', f'Първа беседа от {З}')],
    'zl-15': [('sv-pelagija', f'Втора беседа от {З}')],
    'zl-16': [('svv-roman-kesarijskij-varul-antiohijskij', f'Първо похвално слово от {З}')],
    'zl-17': [('svv-roman-kesarijskij-varul-antiohijskij',
               f'Второ похвално слово, приписвано на {З}')],
    'zl-18': [('svv-vavila-urvan-prilidian-eppolonij-hristodula-antiohijskie',
               f'Слово от {З}')],
    'zl-19': [('svv-vavila-urvan-prilidian-eppolonij-hristodula-antiohijskie',
               f'Слово за блажени Вавила и против Юлиан от {З}')],
    'zl-21': [('sv-iulian-tarsijskij', f'Похвално слово от {З}')],
    'zl-23': [('sv-varlaam-antiohiec', f'Похвално слово от {З}')],
}
# ⚠ Беседите „за мъчениците" — в дните с МНОГО мъченици (искане на
# потребителя). Похвалата на египетските мъченици (zl-08) също е тук: тя е
# за мощи, пренесени от Египет, но без имена — тоест обща за мъчениците, а в
# календара конкретен ден за нея няма (решение на потребителя, 27.09.2026).
МНОГО_МЪЧЕНИЦИ = [
    'svv-40-muchenikov-v-sevastijskom-ozere-muchivshihsja',
    'svv-muchenikov-20000-v-nikomidii-v-cerkvi-sozhzhennyh-i-prochih-tamo-zhe-vne-cerkvi-postradavshih',
    'sv-novomachenici-batashki',
    'svv-leontij-mavrikij-daniil-antonij-nikopolskie-armjanskie',
    'sv-hiljada-i-trima-v',
    'svv-konstantin-aetij-feofil-feodor-ammorejskie-frigijskie',
    'sv-mchci-1000-i-azat',
    'sv-meletij-stratilat-i-s',
]
for s in МНОГО_МЪЧЕНИЦИ:
    КЪМ_СВЕТИИ.setdefault('zl-06', []).append(
        (s, f'Беседа за мъчениците от {З}'))
    КЪМ_СВЕТИИ.setdefault('zl-07', []).append(
        (s, f'Беседа за мъчениците, за съкрушението и милостинята от {З}'))
    КЪМ_СВЕТИИ.setdefault('zl-08', []).append(
        (s, f'Похвала на египетските мъченици от {З}'))

# Неделята на всички светии (Пасха+56) и втората неделя след Петдесетница
# (Пасха+63 — руските, атонските и българските светии). Адресите са мерени
# с readingAddress / ключ() в tools/tipikon/scripts/build.py.
ВСИЧКИ_СВЕТИИ = 'W1:7'
ВТОРА_НЕДЕЛЯ = 'W2:7'


def дни_на_съборите() -> list[str]:
    """Адресите на съборите на светии — за словото на прп. Юстин.

    ⚠ Неподвижните — по ЦЪРКОВНА дата: в семето датата е гражданска по
    стар стил за 2026 = църковната + 13 дни.
    ⚠ Подвижните (Всички светии, руските, атонските, българските) са
    извън тази заявка — те са литургичните адреси горе.
    """
    c = sqlite3.connect(f'file:{СЕМЕ}?mode=ro', uri=True)
    out = [ВСИЧКИ_СВЕТИИ, ВТОРА_НЕДЕЛЯ]
    for (гр, име) in c.execute(
            "SELECT date, name FROM saints WHERE name LIKE 'Събор на%'"):
        if not re.search(r'светии|новомъченици|старци|отци', име):
            continue
        if re.search(r'всички светии|Атонска', име, re.I) or 'български светии' in име:
            continue                         # подвижните — горе
        d = time.strptime(гр, '%Y-%m-%d')
        ц = time.localtime(time.mktime(d) - 13 * 86400 + 3600)
        out.append(f'{ц.tm_mon:02d}-{ц.tm_mday:02d}')
    # Денят на самия прп. Юстин (Попович) Челийски.
    (гр,) = c.execute("SELECT date FROM saints WHERE slug = "
                      "'sv-iustin-popovich-chelijskij'").fetchone()
    d = time.strptime(гр, '%Y-%m-%d')
    ц = time.localtime(time.mktime(d) - 13 * 86400 + 3600)
    out.append(f'{ц.tm_mon:02d}-{ц.tm_mday:02d}')
    return sorted(set(out))


СУПЕР = {ch: str(i) for i, ch in enumerate('⁰¹²³⁴⁵⁶⁷⁸⁹')}


def абзац(t: str, бел: dict[str, str]) -> str:
    """Преведен абзац → HTML: екраниран, с библейски връзки и бележки."""
    t = html.escape(t, quote=False)
    t = _bl.свържи(t, _bl_карта, {})

    def номер(m):
        n = ''.join(СУПЕР[c] for c in m.group(0))
        if n not in бел:
            return m.group(0)           # горен индекс без бележка — оставя се
        return ('<sup><a href="note://%s" title="%s">%s</a></sup>'
                % (n, html.escape(бел[n]), n))
    return re.sub('[⁰¹²³⁴⁵⁶⁷⁸⁹]+', номер, t)


def сглоби(r: dict) -> dict:
    """Четиво от readings.json + преводите на частите му → запис."""
    части = sorted(РАБОТА.glob('translated/%s*.json' % r['id']))
    части = [p for p in части
             if p.stem == r['id'] or p.stem.startswith(r['id'] + '-')]
    bg = []
    for p in части:
        bg += json.loads(p.read_text(encoding='utf-8'))['blocks_bg']
    if len(bg) != len(r['blocks_ru']):
        raise SystemExit(f'{r["id"]}: {len(bg)} преведени блока срещу '
                         f'{len(r["blocks_ru"])} — непреведено или разминато')
    бел = {}
    for k, t in zip(r['kinds'], bg):
        if k == 'note':
            m = re.match(r'\s*(\d+)\.\s*(.*)', t, re.S)
            if m:
                бел[m.group(1)] = m.group(2).strip()
    заглавие = ЗАГЛАВИЯ.get(r['id']) or bg[r['kinds'].index('title')]
    тяло = [f'<h3>{html.escape(заглавие, quote=False)}</h3>']
    for k, t, ru in zip(r['kinds'], bg, r['blocks_ru']):
        if k == 'h' and служебно_заглавие(ru):
            continue
        if k == 'titlenote':
            # ⚠ Кога и къде е произнесена — указание, не разказ: курсив, без
            # буквица (класът я пропуска).
            тяло.append(f'<p class="memorydate">{html.escape(t, quote=False)}</p>')
        elif k == 'h':
            тяло.append(f'<h3>{html.escape(t, quote=False)}</h3>')
        elif k == 'p':
            тяло.append(f'<p>{абзац(t, бел)}</p>')
    body = ''.join(тяло)
    return {**r, 'title_bg': заглавие, 'body': body, 'notes': бел,
            'blocks_bg_all': bg,
            'book': КНИГА[r['id'].split('-')[0]]}


def служебно_заглавие(ru: str) -> bool:
    """Заглавие от ШАБЛОНА на изданието, а не от текста.

    ⚠ Книгата носи английския надпис „notes" над бележките под линия, а
    преводачът го оставя непреведен. Бележките и без това си имат място —
    изскачащ панел в четеца, отделен дял накрая на тома, — тъй че
    заглавието е излишно и се изписваше като голо „notes" накрая на
    словото (забелязано от потребителя, 27.09.2026). Гледа се ОРИГИНАЛЪТ,
    не преводът: така признакът не зависи от прищявката на модела.
    """
    return ru.strip().lower() in {'notes', 'примечания'}


ПРЕДГОВОР = РАБОТА / 'preface_justin.json'
ПРЕДГОВОР_ЗАГЛАВИЕ = 'Предговор от преп. Юстин Попович'


def предговор(ч: dict) -> dict:
    """Словото на прп. Юстин като ПРЕДГОВОР към 12-те тома на житията.

    ⚠ Записва се тук, а се ВМЪКВА от `tools/Translate_lives/scripts/
    04_build_epub.py` (`add_preface`) — при всяко сглобяване на томовете,
    за да оцелява при пресглобяване.
    ⚠ В тома няма схемата „note://" — бележката стои накрая като абзац, а в
    текста остава гол горен индекс. Библейските връзки са към azbyka.ru с
    `&amp;` — четецът на книги ги отваря вътре в приложението.
    """
    абзаци = []
    for k, t, ru in zip(ч['kinds'], ч['blocks_bg_all'], ч['blocks_ru']):
        if k == 'h' and служебно_заглавие(ru):
            continue
        if k == 'p':
            x = _bl.свържи(html.escape(t, quote=False), _bl_карта, {})
            абзаци.append(x)
        elif k == 'h':
            абзаци.append('<b>%s</b>' % html.escape(t, quote=False))
    бел = ['%s. %s' % (n, html.escape(t, quote=False))
           for n, t in sorted(ч['notes'].items(), key=lambda kv: int(kv[0]))]
    return {'title': ПРЕДГОВОР_ЗАГЛАВИЕ, 'subtitle': ч['title_bg'],
            'source': ч['source'], 'paragraphs': абзаци, 'notes': бел}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('--dry-run', action='store_true')
    # Само предговорът за томовете — без базата (за да не се чака Златоуст).
    ap.add_argument('--preface-only', action='store_true')
    a = ap.parse_args()
    global _bl_карта
    _bl_карта = _bl.съкращения()
    if a.preface_only:
        r = next(r for r in json.loads((РАБОТА / 'readings.json').read_text(
            encoding='utf-8')) if r['id'] == 'justin-01')
        ПРЕДГОВОР.write_text(json.dumps(предговор(сглоби(r)), ensure_ascii=False,
                                        indent=1), encoding='utf-8')
        print(f'предговор: {ПРЕДГОВОР.relative_to(ПРОЕКТ)}')
        return 0

    четива = [сглоби(r) for r in
              json.loads((РАБОТА / 'readings.json').read_text(encoding='utf-8'))]

    # ⚠ Слъговете — ПРЕДИ записа.
    c = sqlite3.connect(f'file:{СЕМЕ}?mode=ro', uri=True)
    има = {s for (s,) in c.execute('SELECT DISTINCT slug FROM saints')}
    липсват = [s for v in КЪМ_СВЕТИИ.values() for s, _ in v if s not in има]
    if липсват:
        raise SystemExit(f'слъгове, каквито в календара няма: {липсват}')
    дни_ю = дни_на_съборите()

    for ч in четива:
        св = КЪМ_СВЕТИИ.get(ч['id'], [])
        print(f'{ч["id"]:10} {len(ч["body"]):7}  бел.{len(ч["notes"]):2}  '
              f'светии {len(св):2}  {ч["title_bg"][:60]}')
    print(f'прп. Юстин в „Слова за деня": {len(дни_ю)} дни — {дни_ю}')
    if a.dry_run:
        print('--dry-run: нищо не е записано')
        return 0

    ю = next(ч for ч in четива if ч['id'] == 'justin-01')
    ПРЕДГОВОР.write_text(json.dumps(предговор(ю), ensure_ascii=False, indent=1),
                         encoding='utf-8')
    print(f'предговор за томовете: {ПРЕДГОВОР.relative_to(ПРОЕКТ)}')

    КОПИЯ.mkdir(exist_ok=True)
    копие = КОПИЯ / f'lives_plus.db.bak-{time.strftime("%Y%m%d_%H%M%S")}'
    shutil.copy2(БАЗА, копие)
    print(f'копие: {копие.relative_to(ПРОЕКТ)}')

    db = sqlite3.connect(БАЗА)
    db.executescript('''
        CREATE TABLE IF NOT EXISTS slovo_saints (
            slug TEXT NOT NULL, id TEXT NOT NULL, label TEXT NOT NULL,
            ord INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (slug, id));
        CREATE INDEX IF NOT EXISTS idx_slovo_saints_slug ON slovo_saints(slug);
        CREATE TABLE IF NOT EXISTS slovo_notes (
            id TEXT NOT NULL, n TEXT NOT NULL, text TEXT NOT NULL,
            PRIMARY KEY (id, n));
    ''')
    for книга in set(КНИГА.values()):
        ids = [i for (i,) in db.execute('SELECT id FROM slova WHERE book = ?', (книга,))]
        for i in ids:
            for т in ('slovo_saints', 'slovo_notes', 'slovo_days'):
                db.execute(f'DELETE FROM {т} WHERE id = ?', (i,))
        db.execute('DELETE FROM slova WHERE book = ?', (книга,))
    for ч in четива:
        db.execute(
            'INSERT INTO slova (id, book, address, title_bg, title_ru, body,'
            ' source, chars, why) VALUES (?,?,?,?,?,?,?,?,?)',
            (ч['id'], ч['book'], '', ч['title_bg'], ч['title_ru'], ч['body'],
             ч['source'], len(ч['body']), 'tools/Slova'))
        for n, t in ч['notes'].items():
            db.execute('INSERT INTO slovo_notes (id, n, text) VALUES (?,?,?)',
                       (ч['id'], n, t))
        for ред, (slug, етикет) in enumerate(КЪМ_СВЕТИИ.get(ч['id'], [])):
            # ⚠ ord: при няколко беседи за един светия — по реда в книгата.
            db.execute('INSERT OR REPLACE INTO slovo_saints (slug, id, label, ord)'
                       ' VALUES (?,?,?,?)', (slug, ч['id'], етикет, ч['order']))
    for адрес in дни_ю:
        db.execute('INSERT OR IGNORE INTO slovo_days (id, address) VALUES (?,?)',
                   ('justin-01', адрес))
    db.execute('INSERT OR IGNORE INTO slovo_days (id, address) VALUES (?,?)',
               ('zl-22', ВСИЧКИ_СВЕТИИ))
    db.commit()
    print('slova: %d | slovo_saints: %d | slovo_days: %d | бележки: %d' % tuple(
        db.execute(f'SELECT count(*) FROM {т}').fetchone()[0]
        for т in ('slova', 'slovo_saints', 'slovo_days', 'slovo_notes')))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
