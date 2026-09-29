#!/usr/bin/env python3
"""Паримии → work/parimii.json (книга в „Богослужебни") + work/parimii_days.json
(картата ден → четива за „Евангелие и Апостол").

    python3 11_parimii.py          # после 05_build_db.py и 12_gen_parimii_dart.py

⚠⚠ ТЕКСТЪТ НЕ СЕ ПРЕВЕЖДА — СГЛОБЯВА СЕ ОТ НАШАТА БИБЛИЯ. Изворът („Паримии
на все дни года", azbyka.ru) е на руски, но всяко четиво завършва с
препратка, която е връзка с кодовете на `bible.db` (`?Is.61:1-9`). От нея
се вадят българският и църковнославянският текст. Превеждат се с DeepSeek
само: заглавията на дните, тропарите на пророчеството и шепата СВОБОДНИ
компилации (препратка със „ср." или „?") — там стиховете са преразказани и
не могат да се сглобят. Те остават само на български.

⚠ ПОЛОВИНКИТЕ СТИХОВЕ („Пс 1:6, 1А", „2:21Б") — изворът казва КОЯ половина,
не КЪДЕ е границата, а тя е различна във всеки превод. Стихът се реже на
препинателния знак най-близо до средата (силните знаци — . ; : — с
предимство). Не се ли намери чист разрез, остава целият стих: по-добре
малко повече, отколкото откъснато насред мисълта.

⚠ ПРЕПРАЩАНИЯТА („Паремии святителю") водят към общите паримии в края на
книгата — в книгата разделът получава техните четива наготово, в картата на
дните — същите препратки.

⚠ Руски местни памети остават в книгата; в дневния изглед излизат само ако
светията го има в деня (виж `keys` — сверяват се в приложението).
"""
import html
import importlib.util
import json
import re
import sqlite3
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PROJ = ROOT.parents[1]
W = ROOT / 'work'
SRC_FILE = ROOT / 'input' / 'newBooks2' / 'Паримии на все дни года.gen.epub'
SRC = 'https://azbyka.ru/otechnik/Pravoslavnoe_Bogosluzhenie/paremii-na-vse-dni-goda/'
BIBLE = PROJ / 'assets' / 'db' / 'bible.db'
BOOK = 'Паримии'
FIRST_ID = 3001
TR_CACHE = W / 'parimii_tr.json'

MONTHS_RU = ['января', 'февраля', 'марта', 'апреля', 'мая', 'июня', 'июля', 'августа',
             'сентября', 'октября', 'ноября', 'декабря']
MONTHS_BG = ['Януари', 'Февруари', 'Март', 'Април', 'Май', 'Юни', 'Юли', 'Август',
             'Септември', 'Октомври', 'Ноември', 'Декември']
MONTH_NOM = ('Сентябрь', 'Октябрь', 'Ноябрь', 'Декабрь', 'Январь', 'Февраль', 'Март',
             'Апрель', 'Май', 'Июнь', 'Июль', 'Август')
CS_NUM = ['', 'а҃', 'в҃', 'г҃', 'д҃', 'є҃', 'ѕ҃', 'з҃', 'и҃']

# Препращанията към общите паримии → заглавието на общия раздел в книгата.
POINTERS = {
    'Пресвятой Богородице': 'Пресвятой Богородице',
    'священному Кресту': 'Священному и животворящему Кресту',
    'свв. бесплотным Силам': 'Святым бесплотным Силам',
    'свв. Отцам': 'Святым отцам',
    'Иоанну Предтече': 'Святому Иоанну Предтече',
    'Пророку': 'Пророку',
    'Апостолу': 'Апостолу',
    'Апостолам': 'Апостолам',
    'святителю': 'Святителю',
    'святителям': 'Святителям',
    'мученику': 'Мученику',
    'мученикам': 'Мученикам',
    'мученицам': 'Мученикам',
    'преподобному': 'Преподобному',
    'преподобным': 'Преподобному',
    'преподобной': 'Преподобному',
    'юродивому': 'Преподобному',
}

LENT_WEEK = {'первой': 1, 'второй': 2, 'третьей': 3, 'четвертой': 4, 'четвёртой': 4,
             'пятой': 5, 'шестой': 6}
WEEKDAY = {'Понедельник': 0, 'Вторник': 1, 'Среда': 2, 'Четверг': 3, 'Пятница': 4}
FIXED_MOVABLE = {
    'Среда сырной седмицы': -53, 'Пятница сырной седмицы': -51,
    'Суббота Ваий': -8, 'Великий понедельник': -6, 'Великий вторник': -5,
    'Великая среда': -4, 'Великий четверг': -3, 'Великая пятница': -2,
    'Великая суббота': -1,
    'Среда 4-й седмицы по Пасхе': 24, 'Четверг 6-й седмицы по Пасхе': 39,
    'Неделя 7-я по Пасхе': 42, 'Неделя Пятидесятницы': 49,
    'Неделя 1-я по Пятидесятнице': 56, 'Неделя 2-я по Пятидесятнице': 63,
}
# Четива, чиято препратка липсва в извора. Шестото четиво на Великата
# събота преминава направо в Песента на Мойсей (Изх. 15) и затова няма свой
# ред с препратка — по Типикона то е Изх. 13:20–15:19.
MANUAL_REFS = {'6. Исхода чтение': 'Исх 13:20–15:19'}

# Руска местна памет — в книгата да, в дневния изглед не.
RUSSIAN_MOVABLE = {63}


# ───────────────────────── изворът ─────────────────────────

def items():
    z = zipfile.ZipFile(SRC_FILE)
    t = z.read('toc.ncx').decode()
    out, depth = [], 0
    for m in re.finditer(r'<navPoint\b|</navPoint>|<text>([^<]*)</text>\s*</navLabel>\s*'
                         r'<content src="([^"]*)"', t):
        g = m.group(0)
        if g.startswith('<navPoint'):
            depth += 1
        elif g == '</navPoint>':
            depth -= 1
        else:
            h = z.read(m.group(2).split('#')[0]).decode()
            h = h[h.find('<body'):]
            paras = re.findall(r'<(?:div|p)\b[^>]*class="paragraph"[^>]*>(.*?)</(?:div|p)>', h, re.S)
            # ⚠ Заглавията носят НЕРАЗДЕЛЕН интервал („4\xa0сентября") — без
            # това датата не се разпознава и денят изчезва мълчаливо.
            title = re.sub(r'\s+', ' ', html.unescape(m.group(1)).replace('\xa0', ' ')).strip()
            # Препращането („Паремии святителю") не е в „paragraph" — към
            # абзаците се добавя като отделен ред.
            ptr = re.search(r'>\s*(Паремии [^<]{3,40})<', h)
            if ptr and not any('Паремии' in pp for pp in paras):
                paras = paras + [ptr.group(1)]
            out.append((depth, title, paras))
    return out


def plain(h):
    return re.sub(r'\s+', ' ', html.unescape(re.sub(r'<[^>]+>', '', h))).strip()


def abbr_map(its):
    """Руско съкращение → код, извлечено от САМИТЕ връзки в книгата."""
    m = {}
    for _, _, paras in its:
        for p in paras:
            for code, vis in re.findall(r'href="https://azbyka.ru/biblia/\?([A-Za-z0-9]+)\.[^"]*"'
                                        r'[^>]*>([^<]*)</a>', p):
                a = re.match(r'\s*([1-4]?\s?[А-ЯЁа-яё]+)', html.unescape(vis))
                if a:
                    m[a.group(1).replace(' ', '')] = code
    return m


# ───────────────────────── препратките ─────────────────────────

def parse_ref(vis, abbrs):
    """„Ис 63:15–19; 64:1–5А, 8–9" → [(код, гл1, ст1, част1, гл2, ст2, част2)].
    `None`, ако не се разчита. Втори резултат: свободна ли е компилацията."""
    s = vis.replace('–', '-').replace('—', '-').replace('\xa0', ' ')
    s = re.sub(r'\bC(?=р\.)', 'С', s)                 # латинско „C" в „Cр."
    s = re.sub(r'\(\?\)', '?', s)
    free = bool(re.search(r'ср\.|\?', s, re.I))
    s = re.sub(r'(?i)ср\.\s*', '', s).replace('[?]', '').replace('?', '')
    segs, code = [], None
    ch = None
    for grp in [g.strip() for g in s.split(';') if g.strip()]:
        # „Ис Нав" — съкращение от две думи.
        m = re.match(r'([1-4]?\s?[А-ЯЁ][а-яё]+(?:\s[А-ЯЁ][а-яё]+)?)\s*(.*)$', grp)
        if m:
            key = m.group(1).replace(' ', '')
            if key not in abbrs:
                key = m.group(1).split()[-1]
            if key not in abbrs:
                return None, free
            if abbrs[key] != code:
                ch = None
            code, grp = abbrs[key], m.group(2)
        if code is None:
            return None, free
        grp = grp.replace(' ', '')
        mm = re.match(r'(\d+):(.*)$', grp)
        if not mm:
            if re.fullmatch(r'\d+', grp) and ch is None:  # цяла глава
                segs.append((code, int(grp), 1, '', int(grp), 999, ''))
                continue
            if ch is None or not re.fullmatch(r'[\dАБВ,\-:]+', grp):
                return None, free
            rest = grp                                    # „Иуд 1:1–7; 20–25"
        else:
            ch, rest = int(mm.group(1)), mm.group(2)
        for item in [x for x in rest.split(',') if x]:
            r = re.fullmatch(r'(\d+)([АБВ]?)(?:-(?:(\d+):)?(\d+)([АБВ]?))?', item)
            if not r:
                return None, free
            v1, p1 = int(r.group(1)), r.group(2)
            ch2 = int(r.group(3)) if r.group(3) else ch
            v2 = int(r.group(4)) if r.group(4) else v1
            p2 = r.group(5) if r.group(4) else p1
            segs.append((code, ch, v1, p1, ch2, v2, p2))
            ch = ch2
    return segs, free


class Bible:
    def __init__(self):
        self.db = sqlite3.connect(BIBLE)
        self.books = {c: (t, s, a) for c, t, s, a in
                      self.db.execute('SELECT code, bg_title, bg_short, bg_abbr FROM books')}

    def verses(self, lang, code, ch1, v1, ch2, v2):
        rows = self.db.execute(
            "SELECT chapter, verse, text FROM verses WHERE lang=? AND book=? AND chapter BETWEEN ? AND ? "
            "ORDER BY chapter, ord", (lang, code, ch1, ch2)).fetchall()
        out = []
        for ch, v, t in rows:
            if not v.isdigit() or v == '0':
                continue
            v = int(v)
            if (ch, v) < (ch1, v1) or (ch, v) > (ch2, v2):
                continue
            t = re.sub(r'\[За[^\]]{0,10}\]\s*', '', t)
            # ⚠ Вътрешни номера на допълнителните стихове по Септуагинтата
            # („42:17aПи́сано…" в Йов) — в четивото не се четат.
            t = re.sub(r'\s*\d+:\d+[a-zа-я]\s*', ' ', t).strip()
            out.append(t)
        return out


def cut(text, part, first):
    """Половин стих. `first` — това е ПЪРВИЯТ стих на отрязъка (иска се
    краят му), иначе последният."""
    if not part:
        return text
    marks = [m.end() for m in re.finditer(r'[.;:!?·]\s', text)]
    weak = [m.end() for m in re.finditer(r',\s', text)]
    n = len(text)
    target = {'А': 0.5, 'Б': 0.5, 'В': 0.67}[part]

    def best(c, lo, hi):
        c = [i for i in c if lo * n <= i <= hi * n]
        return min(c, key=lambda i: abs(i - target * n)) if c else None
    i = best(marks, 0.25, 0.75) or best(weak, 0.3, 0.7)
    if i is None:
        return text
    return text[:i].rstrip(' ,;:') + ('.' if part == 'А' else '') if part == 'А' \
        else text[i:].lstrip()


def assemble(bible, lang, segs):
    """Текстът на отрязъците — по абзац на отрязък."""
    out = []
    for code, ch1, v1, p1, ch2, v2, p2 in segs:
        vs = bible.verses(lang, code, ch1, v1, ch2, v2)
        if not vs:
            return None
        # „А" при началния стих значи „от началото до средата", т.е. при
        # единичен стих — първата половина; при диапазон отрязва КРАЯ.
        if p1 and v1 == v2 and ch1 == ch2:
            vs = [cut(vs[0], p1, True)]
        else:
            if p1 == 'Б':
                vs[0] = cut(vs[0], 'Б', False)
            if p2 == 'А':
                vs[-1] = cut(vs[-1], 'А', True)
        out.append(' '.join(vs))
    return out


def ref_label(bible, segs):
    """„Ис. 61:1-9; 64:1-5, 8-9" — с българските съкращения, без половинките."""
    parts, last_code, last_ch = [], None, None
    for code, ch1, v1, _, ch2, v2, _ in segs:
        v = ('%d' % v1 if (ch1, v1) == (ch2, v2) else
             '%d-%d' % (v1, v2) if ch1 == ch2 else '%d-%d:%d' % (v1, ch2, v2))
        if v2 == 999:
            v = None
        if code != last_code:
            parts.append('%s %d%s' % (bible.books[code][2], ch1, ':' + v if v else ''))
        elif ch1 != last_ch:
            parts.append('%d%s' % (ch1, ':' + v if v else ''))
        else:
            parts[-1] += ', ' + v
        last_code, last_ch = code, ch2
    return '; '.join(parts)


def ref_code(segs):
    """„Is.63:15-19,64:1-5,8-9" — във вида, който разчита bible_ref.dart."""
    out, last_code, last_ch = [], None, None
    for code, ch1, v1, _, ch2, v2, _ in segs:
        if v2 == 999:
            part = '%d' % ch1
        elif (ch1, v1) == (ch2, v2):
            part = '%d:%d' % (ch1, v1)
        elif ch1 == ch2:
            part = '%d:%d-%d' % (ch1, v1, v2)
        else:
            part = '%d:%d-%d:%d' % (ch1, v1, ch2, v2)
        if code != last_code:
            out.append('%s.%s' % (code, part))
        elif ch1 == last_ch and ':' in part:
            out[-1] += ',' + part.split(':', 1)[1]
        else:
            out[-1] += ',' + part
        last_code, last_ch = code, ch2
    return out


# ───────────────────────── преводите ─────────────────────────

TITLE_PROMPT = """Ти си опитен преводач на православна богослужебна литература от руски на български.

Превеждаш ЗАГЛАВИЯ от книга с паримии (старозаветни четива на вечернята и часовете): имена на празници, памети на светии, дни от Великия пост, указания за службата.

Правила:
1. Утвърден български църковен стил: „Рождество на Пресвета Богородица“, „Въздвижение на Честния и Животворящ Кръст Господен“, „Преподобни Сергий Радонежки“.
2. Имената — в утвърдените български форми („Йоан“, не „Иоанн“; „Теодор“, не „Феодор“; „Атанасий“; „Тимотей“; „Евтимий“; „Теодосий“).
3. „седмица“ остава „седмица“; „на шестом часе“ → „на шестия час“; „на вечерне“ → „на вечернята“; „Тропарь пророчества“ → „Тропар на пророчеството“; „Прокимен, глас 4“ → „Прокимен, глас 4“.
4. Не добавяй нищо, не съкращавай, без точка накрая.

Входът е номериран списък, по едно заглавие на ред. Отговори със същите номера, същия ред и същия брой редове."""

TEXT_PROMPT = """Ти си опитен преводач на православна богослужебна литература от руски на български.

Превеждаш кратки богослужебни текстове (тропари, указания) и старозаветни четива от книга с паримии.

Правила:
1. Езикът е този на българския синодален превод на Библията и на богослужебните книги: тържествен, но ясен.
2. Имената — в утвърдените български форми (Йоан, Иаков, Израил, Иерусалим, Мойсей).
3. „Слава, и ныне“ → „Слава, и сега“.
4. Не добавяй нищо и не съкращавай.

Входът е номериран списък. Отговори със същите номера, същия ред и същия брой редове."""


def translator():
    spec = importlib.util.spec_from_file_location(
        'tr', ROOT.parent / 'lives_plus' / 'scripts' / '02_translate_deepseek.py')
    tr = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(tr)
    return tr


DRY = '--dry' in sys.argv


def translate(strings, prompt, kind):
    if DRY:
        return {x: x for x in strings}
    cache = json.loads(TR_CACHE.read_text(encoding='utf-8')) if TR_CACHE.exists() else {}
    done = cache.setdefault(kind, {})
    missing = [x for x in dict.fromkeys(strings) if x not in done]
    if missing:
        tr = translator()
        tr.ПРОМПТ = prompt
        k = tr.ключ()
        rep = {'повиквания': 0, 'вход': 0, 'изход': 0}
        step = 40 if kind == 'titles' else 8
        for i in range(0, len(missing), step):
            part = missing[i:i + step]
            for ru, bg in zip(part, tr.преведи(k, part, '', rep)):
                done[ru] = bg.strip()
            TR_CACHE.write_text(json.dumps(cache, ensure_ascii=False, indent=1), encoding='utf-8')
            print('  %s %d/%d' % (kind, i + len(part), len(missing)), flush=True)
    return done


# ───────────────────────── устройството ─────────────────────────

SERVICE_BG = {
    'на вечерне': 'На вечернята', 'на великой вечерне': 'На великата вечерня',
    'на утрени': 'На утренята', 'на первом часе': 'На първия час',
    'на третьем часе': 'На третия час', 'на шестом часе': 'На шестия час',
    'на девятом часе': 'На деветия час', 'на водоосвящении': 'При водосвета',
    'на литургии': 'На литургията',
}


def service_of(title):
    """„…, на шестом часе. Тропарь…" / „На третьем часе. Прокимен" → служба."""
    if not title:
        return None
    m = re.search(r'(?i)(?:^|[,.]\s*)(на (?:великой )?(?:вечерне|утрени|первом часе|третьем часе|'
                  r'шестом часе|девятом часе|водоосвящении|литургии))', title)
    return m.group(1).lower() if m else None

def day_of(title):
    """Заглавие → (ключ на деня, частта-име, частта-служба). None, ако не е
    заглавие на ден."""
    m = re.match(r'^(?:(?:%s) )?(\d+) (%s)\. (.*)$' % ('|'.join(MONTH_NOM), '|'.join(MONTHS_RU)), title)
    if m:
        name, svc = m.group(3), None
        sm = re.search(r'\. (На .*)$', name)          # „Навечерие… На первом часе. Прокимен"
        if sm:
            name, svc = name[:sm.start()], sm.group(1)
        return ('%02d-%02d' % (MONTHS_RU.index(m.group(2)) + 1, int(m.group(1))), name, svc)
    for name, off in FIXED_MOVABLE.items():
        if title.startswith(name):
            rest = title[len(name):].lstrip('.,; ')
            return ('P%+d' % off, name + ('. ' + rest if rest and not re.match(r'(?i)на ', rest) else ''),
                    rest if re.match(r'(?i)на ', rest) else None)
    m = re.match(r'^(Понедельник|Вторник|Среда|Четверг|Пятница) (\S+) седмицы(.*)$', title)
    if m and m.group(2) in LENT_WEEK:
        off = -48 + 7 * (LENT_WEEK[m.group(2)] - 1) + WEEKDAY[m.group(1)]
        return ('P%+d' % off, '%s %s седмицы' % (m.group(1), m.group(2)),
                m.group(3).lstrip('.,; ') or None)
    return None


GROUP_PREFIX = re.compile(r'^(Паремии (?:сырной седмицы и святого Великого поста|святой Пятидесятницы|'
                          r'общие на праздники и святым)|[А-ЯЁ][а-яё]+(?: [а-яё]+)?,? ?(?:[а-яё]+ )?'
                          r'седмица святого Великого поста) (?=[А-ЯЁ])')


def main():
    its = items()
    abbrs = abbr_map(its)
    abbrs.setdefault('Иф', 'Judf')          # Иудит — единствената без връзка в книгата
    bible = Bible()

    # 1. Разделите — ред по ред, както в книгата.
    sections, cur, group = [], None, None
    for depth, title, paras in its[1:]:
        m = GROUP_PREFIX.match(title)
        if m:
            p = m.group(1)
            group = ('Великият пост' if 'Великого поста' in p and 'Страстная' not in p else
                     'Пентикостар' if 'Пятидесятницы' in p else
                     'Общи паримии' if 'общие' in p else group)
            if p.startswith('Страстная'):
                group = 'Страстната седмица'
            title = title[m.end():]
        if re.match(r'^(%s) ' % '|'.join(MONTH_NOM), title) and group not in (None,) and \
                group.startswith(('Великият', 'Страстната', 'Пентикостар', 'Общи')) is False:
            pass
        d = day_of(title) if depth == 1 else None
        reading_like = depth == 2 or 'чтение' in title or title.startswith(
            ('Прокимен', 'Тропарь', 'Песнь', 'На ', 'В тот же'))
        if d and not (cur and cur['key'] == d[0] and cur['name_ru'] == d[1]):
            key, name, svc = d
            if key[0] != 'P':
                group = MONTHS_BG[int(key[:2]) - 1]
            elif group is None or group.startswith(tuple(MONTHS_BG)):
                group = 'Великият пост'
            cur = {'key': key, 'name_ru': name, 'group': group, 'items': []}
            sections.append(cur)
            if svc:
                cur['items'].append({'title_ru': svc, 'paras': paras})
            elif paras:
                cur['items'].append({'title_ru': None, 'paras': paras})
            continue
        if d:                                   # същият ден, друга служба
            cur['items'].append({'title_ru': d[2] or title, 'paras': paras})
            continue
        if group == 'Общи паримии' and depth == 1:
            cur = {'key': None, 'name_ru': title, 'group': group, 'items': []}
            sections.append(cur)
            continue
        if depth == 1 and not reading_like:
            # Втора памет на същия ден („Преподобного Силуана Афонского").
            key = cur['key'] if cur else None
            cur = {'key': key, 'name_ru': title, 'group': group, 'items': []}
            sections.append(cur)
            if paras:
                cur['items'].append({'title_ru': None, 'paras': paras})
            continue
        cur['items'].append({'title_ru': title, 'paras': paras})

    # 2. Заглавията и текстовете за превод.
    titles = set()
    texts = []
    for s in sections:
        titles.add(s['name_ru'])
        for it in s['items']:
            if it['title_ru'] and 'чтение' not in it['title_ru']:
                titles.add(it['title_ru'])
    tt = translate(sorted(titles), TITLE_PROMPT, 'titles')

    # 3. Сглобяване.
    commons = {s['name_ru']: s for s in sections if s['group'] == 'Общи паримии'}
    stats = {'четива': 0, 'свободни': 0, 'прокимени': 0, 'тропари': 0, 'непрочетени': []}

    def build_item(it, n_read):
        """→ (unit, reading_for_day | None)."""
        paras = [p for p in it['paras'] if plain(p)]
        title_ru = it['title_ru'] or ''
        body = paras[1:] if paras and plain(paras[0]).rstrip(' .') == title_ru.rstrip(' .') else paras
        body = [p for p in body if plain(p) not in ('В тот же день:',)]
        ref_p = body[-1] if body and ('azbyka.ru/biblia' in body[-1] or re.fullmatch(
            r'[1-4]?\s?[А-ЯЁ][а-яё]+\s\d+:[\d\s–\-,;:АБВ]+', plain(body[-1]))) else None
        ref_vis = plain(ref_p) if ref_p else ''
        text_ps = [plain(p) for p in (body[:-1] if ref_p else body)]
        if not ref_vis and title_ru in MANUAL_REFS:
            ref_vis = MANUAL_REFS[title_ru]
        ttl_bg = tt.get(title_ru, title_ru) if title_ru else None
        if 'чтение' in title_ru:
            segs, free = parse_ref(ref_vis, abbrs) if ref_vis else (None, False)
            num = re.match(r'(\d+)\.', title_ru)
            if free:
                # Свободна компилация: стиховете са преразказани и сглобяване
                # няма — текстът се превежда. За връзката стигат главите от
                # самите връзки в препратката.
                hrefs = list(dict.fromkeys(re.findall(
                    r'azbyka.ru/biblia/\?([A-Za-z0-9]+)\.(\d+)', ref_p or '')))
                if not hrefs:
                    stats['непрочетени'].append(title_ru + ' | ' + ref_vis)
                    return None, None
                segs = [(c, int(ch), 1, '', int(ch), 999, '') for c, ch in hrefs]
                code = segs[0][0]
                lab = '%s (сборно четиво)' % bible.books[code][1]
                head = '%s%s (сборно четиво)' % (num.group(1) + '. ' if num else '',
                                                 bible.books[code][0])
                stats['свободни'] += 1
                bgt = [translate_text(t) for t in text_ps]
                return ({'title_bg': head, 'title_csl': lab,
                         'bg': [('text', html.escape(t, quote=False)) for t in bgt]
                         + [('rubric', html.escape('(срв. ' + ref_vis.lstrip('CcСс').lstrip('р. ') + ')',
                                                   quote=False))],
                         'csl': []}, (lab, ref_code(segs), code))
            if not segs:
                stats['непрочетени'].append(title_ru + ' | ' + ref_vis)
                return None, None
            lab = ref_label(bible, segs)
            code = segs[0][0]
            head = '%s%s (%s)' % (num.group(1) + '. ' if num else '', bible.books[code][0], lab)
            if free:
                stats['свободни'] += 1
                bgt = [translate_text(t) for t in text_ps]
                return ({'title_bg': head, 'title_csl': lab, 'bg': [('text', html.escape(t, quote=False))
                                                                     for t in bgt],
                         'csl': []}, (lab, ref_code(segs), code))
            bgt = assemble(bible, 'bg', segs)
            cst = assemble(bible, 'utfcs', segs)
            if bgt is None or cst is None:
                stats['непрочетени'].append(title_ru + ' | ' + ref_vis)
                return None, None
            stats['четива'] += 1
            return ({'title_bg': head, 'title_csl': lab,
                     'bg': [('text', html.escape(t, quote=False)) for t in bgt],
                     'csl': [('text', html.escape(t, quote=False)) for t in cst]},
                    (lab, ref_code(segs), code))
        if 'Прокимен' in title_ru and ref_vis:
            segs, _ = parse_ref(ref_vis, abbrs)
            glas = re.search(r'глас (\d)', title_ru)
            if not segs or not glas:
                stats['непрочетени'].append(title_ru + ' | ' + ref_vis)
                return None, None
            stats['прокимени'] += 1
            g = int(glas.group(1))
            bg, cs = [], []
            for i, sg in enumerate(segs[:2]):
                b = assemble(bible, 'bg', [sg])
                c = assemble(bible, 'utfcs', [sg])
                if not b or not c:
                    continue
                if i == 0:
                    bg.append(('text', html.escape(b[0], quote=False)))
                    cs.append(('text', html.escape(c[0], quote=False)))
                else:
                    bg.append(('text', '<span class="rubric">Стих:</span> ' + html.escape(b[0], quote=False)))
                    cs.append(('text', '<span class="rubric">Сті́хъ:</span> ' + html.escape(c[0], quote=False)))
            pre = ttl_bg.rsplit('Прокимен', 1)[0].strip(' .') if 'Прокимен' in (ttl_bg or '') else ''
            return ({'title_bg': ttl_bg, 'title_csl': ((pre + '. ') if pre else '') +
                     'Прокі́менъ, гла́съ %s' % CS_NUM[g], 'bg': bg, 'csl': cs}, None)
        # Тропар на пророчеството, песен, указание — превежда се.
        if not text_ps:
            return None, None
        stats['тропари'] += 1
        bgt = []
        for t in text_ps:
            if re.match(r'^[А-ЯЁ][^:]{0,40}:?$', t) and ref_p is None and len(t) < 45:
                bgt.append(('rubric', html.escape(translate_text(t), quote=False)))
            else:
                bgt.append(('text', html.escape(translate_text(t), quote=False)))
        if ref_vis:
            bgt.append(('rubric', html.escape(ref_vis, quote=False)))
        return ({'title_bg': ttl_bg, 'title_csl': ttl_bg, 'bg': bgt, 'csl': []}, None)

    # Текстовете за превод се събират с предварителен проход.
    pending = []

    def translate_text(t):
        pending.append(t)
        return TEXTS.get(t, t)

    global TEXTS
    TEXTS = {}
    for s in sections:                       # проход 1 — само събира текстовете
        for it in s['items']:
            build_item(it, 0)
    TEXTS = translate(pending, TEXT_PROMPT, 'texts')
    stats = {'четива': 0, 'свободни': 0, 'прокимени': 0, 'тропари': 0, 'непрочетени': []}

    out, days = [], {}
    sid = FIRST_ID
    for s in sections:
        units, readings = [], []
        items_ = s['items']
        ptr = None
        # ⚠ СЛУЖБАТА на всяко четиво (изрично поискано): изворът я пише само
        # там, където не е вечерня — Царските часове, Великият пост, Великата
        # събота. Иначе паримиите на празника са на ВЕЧЕРНЯТА.
        service = 'на вечерне'
        first = next((it['title_ru'] for it in items_ if it['title_ru']), None)
        service = service_of(first) or service
        # ⚠ И В САМАТА КНИГА: пред първото четиво на всяка служба и при всяка
        # смяна стои червен ред „На вечернята" / „При водосвета"… Дотук
        # службата стигаше само до календара, а книгата беше без указания.
        # (Докладвано от потребителя, 29.09.2026.) На български и в двете
        # колони — указание за служещия, не част от четивото.
        shown = None

        def mark(sv):
            nonlocal shown
            if sv == shown:
                return
            shown = sv
            lab = SERVICE_BG.get(sv, sv)
            units.append({'title_bg': None, 'title_csl': None,
                          'bg': [('rubric', lab)], 'csl': [('rubric', lab)]})

        for it in items_:
            sv = service_of(it['title_ru'])
            if sv:
                service = sv
            txt = ' '.join(plain(p) for p in it['paras'])
            m = re.search(r'Паремии (%s)' % '|'.join(map(re.escape, POINTERS)), txt)
            if m and not any('azbyka.ru/biblia' in p for p in it['paras']):
                ptr = POINTERS[m.group(1)]
                continue
            u, r = build_item(it, len(readings))
            if u:
                mark(service)
                units.append(u)
            if r:
                readings.append(r + (service,))
        name_bg = tt.get(s['name_ru'], s['name_ru'])
        if ptr:
            # Имената на общите раздели са дълги („Преподобному, преподобным,
            # …") — търси се по началото.
            c = next((v for k, v in commons.items() if k.startswith(ptr)), None)
            if c is None:
                sys.exit('⚠ няма общ раздел „%s"' % ptr)
            cu = [build_item(it, 0) for it in c['items']]
            vesp = SERVICE_BG['на вечерне']
            # Общите паримии са на вечернята; ако собствените на деня започват
            # със същата служба, второто указание е излишно.
            if units and units[0]['bg'] == [('rubric', vesp)]:
                units = units[1:]
            units = [{'title_bg': None, 'title_csl': None,
                      # Името е това на общия раздел в съдържанието — до
                      # първата запетая, инак редът става на три реда.
                      'bg': [('rubric', 'Общи паримии: %s'
                              % tt.get(c['name_ru'], c['name_ru']).split(',')[0])],
                      'csl': []},
                     {'title_bg': None, 'title_csl': None,
                      'bg': [('rubric', vesp)], 'csl': [('rubric', vesp)]}] + \
                [u for u, _ in cu if u] + units
            readings = [r + ('на вечерне',) for _, r in cu if r] + readings
        if not units:
            continue
        key = s['key']
        if key and key[0] != 'P':
            mm, dd = int(key[:2]), int(key[3:])
            title_bg = '%d %s: %s' % (dd, MONTHS_BG[mm - 1].lower(), name_bg)
        else:
            title_bg = name_bg
        out.append({'sec': sid, 'tab': 'bogosluzhebni', 'book': BOOK, 'grp': s['group'],
                    'title_bg': title_bg, 'title_csl': None, 'csr_source': None,
                    'csl_source': SRC,
                    'units': [{'n': k, 'title_bg': u['title_bg'], 'title_csl': u['title_csl'],
                               'title_cs': None, 'csr': [],
                               'csl': [{'kind': a, 'html': b} for a, b in u['csl']],
                               'bg': [{'kind': a, 'html': b} for a, b in u['bg']],
                               'sources': []}
                              for k, u in enumerate(units)]})
        if key and readings and s['group'] != 'Общи паримии':
            off = int(key[1:]) if key[0] == 'P' else None
            days.setdefault(key, []).append({
                'title': name_bg, 'sec': sid,
                'russian': off in RUSSIAN_MOVABLE,
                'movable': key[0] == 'P',
                'readings': [{'label': lab, 'refs': rc, 'book': bible.books[code][1],
                              'service': SERVICE_BG.get(sv, sv)}
                             for lab, rc, code, sv in readings]})
        sid += 1

    (W / 'parimii.json').write_text(json.dumps(out, ensure_ascii=False, indent=1), encoding='utf-8')
    (W / 'parimii_days.json').write_text(json.dumps(days, ensure_ascii=False, indent=1),
                                         encoding='utf-8')
    print('→ work/parimii.json: %d раздела; дни с паримии: %d' % (len(out), len(days)))
    print('  четива %(четива)d (свободни компилации %(свободни)d), прокимени %(прокимени)d, '
          'тропари/текстове %(тропари)d' % stats)
    if stats['непрочетени']:
        print('  ⚠ непрочетени %d:' % len(stats['непрочетени']))
        for x in stats['непрочетени'][:30]:
            print('     ', x)


TEXTS = {}

if __name__ == '__main__':
    main()
