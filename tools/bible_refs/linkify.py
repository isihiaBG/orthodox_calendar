"""Библейските препратки в текст → ДЕЙСТВАЩИ връзки. ОБЩО за всички конвейери.

Изнесено от `tools/lives_plus/scripts/05_bible_links.py` (27.09.2026), след
като се оказа, че всеки конвейер правеше това сам — или изобщо не го правеше:
в справочника, у Дебольски и в част от житията препратките стояха като
обикновен текст (683 само у Дебольски). Един списък съкращения, едно правило.

⚠⚠ ЕМИТИРА СЕ СЪЩИЯТ ВИД АДРЕС КАТО В ТОМОВЕТЕ:

    <a href="https://azbyka.ru/biblia/?Mt.5:1-7&amp;bg~utfcs">Мат. 5:1-7</a>

— така препратката се отваря ВЪТРЕ в приложението по вече наличния път.

⚠ Кодовете на книгите се четат от `bible.db` (`books.bg_abbr`/`bg_short`),
плюс изрични допълнения, всяко СВЕРЕНО срещу съществуващ код.
"""
import re
import sqlite3
from pathlib import Path

BIBLE_DB = Path(__file__).resolve().parents[2] / 'assets' / 'db' / 'bible.db'

# ⚠ Формите, които текстовете реално пишат, но ги няма в базата.
EXTRA = {
    # руски къси форми, които моделът понякога оставя
    'мт': 'Mt', 'мк': 'Mk', 'лк': 'Lk', 'ин': 'Jn', 'йн': 'Jn',
    'быт': 'Gen', 'исх': 'Ex', 'иез': 'Ezek', 'иов': 'Job',
    # български форми, които базата не дава в този вид
    'бит': 'Gen', 'як': 'Jac', 'яков': 'Jac', 'юда': 'Juda',
    'йов': 'Job', 'сирах': 'Sir', 'песен': 'Song', 'плач': 'Lam',
    'фил': 'Phil', 'флп': 'Phil', 'откр': 'Apok', 'апок': 'Apok',
    '1пет': '1Pet', '2пет': '2Pet',
    '1йоан': '1Jn', '2йоан': '2Jn', '3йоан': '3Jn',
    'иоан': 'Jn', 'лука': 'Lk', 'деяния': 'Act',
    # ⚠⚠ ЦАРСТВАТА СА КАПАН: българското „1 Царе" е 1 Царства (1Sam), а
    # „3 Царе" е 3 Царства (1King) — номерът се РАЗМЕСТВА спрямо западното
    # броене. Сверено срещу `books.bg_short` в bible.db.
    '1цар': '1Sam', '1царе': '1Sam', '2цар': '2Sam', '2царе': '2Sam',
    '3цар': '1King', '3царе': '1King', '4цар': '2King', '4царе': '2King',
    '1езд': 'Ezr', '2езд': '2Ezr', 'неем': 'Nehem',
    '1парал': '1Chron', '2парал': '2Chron', '1пар': '1Chron',
    '1мак': '1Mac', '2мак': '2Mac', '3мак': '3Mac',
    'иис': 'Nav', 'нав': 'Nav', 'съд': 'Judg', 'рут': 'Rth',
    'тов': 'Tov', 'иудит': 'Judf', 'юдит': 'Judf', 'ест': 'Est',
    'екл': 'Eccl', 'еккл': 'Eccl', 'прем': 'Solom',
    'иса': 'Is', 'исаия': 'Is', 'числ': 'Num', 'йер': 'Jer',
    'иерем': 'Jer', 'йез': 'Ezek', 'йоил': 'Joel', 'йон': 'Jona',
    '2пар': '2Chron', '2лет': '2Chron', '1лет': '1Chron',
    'филип': 'Phil', '3езд': '3Ezr', 'пес': 'Song', 'ефес': 'Eph',
    'прит': 'Prov', '1солун': '1Thes', '2солун': '2Thes',
    # двусловни имена („Прем. Солом. 2:1", „Иис. Нав. 8:34", 18.10.2026)
    'премсолом': 'Solom', 'ииснав': 'Nav',
    # голото „Ездр.“ е (1) Ездра; „Ион.“ е пророк Иона
    'езд': 'Ezr', 'ездр': 'Ezr', 'ион': 'Jona',
    # пълни имена пред скоби: „Естир (9:30)“, „от Марк (15:1–41)“
    'марк': 'Mk', 'софония': 'Zeph', 'притчисоломонови': 'Prov',
    'йеремия': 'Jer', 'ерем': 'Jer',
    # ⚠ НАРОЧНО ЛИПСВАТ:
    #   голото „Цар."/„Кор."/„Сол."/„Тим." — не се знае коя от книгите е;
    #   „псалми" — „псалми 41, 45 и 46" са ТРИ псалма, а запетаята би се
    #   прочела като глава 41, стих 45. По-добре без връзка, отколкото към
    #   чуждо място.
}


def _key(s: str) -> str:
    return re.sub(r'[^0-9a-zа-я]', '', s.lower().replace('ё', 'е'))


def abbreviations() -> dict:
    db = sqlite3.connect(BIBLE_DB)
    out = {}
    for code, abbr, short in db.execute('SELECT code, bg_abbr, bg_short FROM books'):
        for v in (abbr, short):
            if v:
                out[_key(v)] = code
    for k, v in EXTRA.items():
        out.setdefault(k, v)
    return out


# „Мат. 5:1-7", „1 Кор. 13:1", „Пс. 33:9", „Бит. 1:1-3, 5", „4 Цар. 6:17"
# ⚠ Номерът пред книгата е 1–4, не 1–3: инак „4 Цар." не се хващаше изобщо.
_NAME = r'([А-Яа-яЁё]{2,8}(?:\.\s*(?:Солом|Нав))?)'
# ⚠ Диапазон през глави с опашка „18:28–19:1–16" (18.10.2026) = до 19:16.
_RANGE = r'(?:\s*[-–]\s*\d{1,3}(?::\d{1,3})?(?:\s*[-–]\s*\d{1,3})?)?'
# ⚠ След запетаята може да дойде и ДРУГА ГЛАВА („Мат.10:38, 16:24“, 16.10.2026):
# bible_ref.dart разчита „10:38,16:24“ като два пасажа (сверено).
# ⚠⚠ Но НЕ и номер на СЛЕДВАЩА КНИГА: „Еф. 6:11–17, 2 Тим. 2:3" — двойката
# хващаше „2" и връзката сочеше Еф. 6:11–17 и стих 2 (18.10.2026).
_MORE = (r'(?:\s*,\s*\d{1,3}(?::\d{1,3})?' + _RANGE +
         r'(?!\d)(?!\s*[А-Яа-яЁё]))*')
_PLACES = r'\d{1,3}\s*[:,]\s*\d{1,3}' + _RANGE + _MORE
RE_REF = re.compile(r'(?<![\w])([1-4]\s*)?' + _NAME + r'\.?\s*(' + _PLACES + ')')

# Продължение СЪС СЪЩАТА КНИГА след „;" (или „." в скоби): „Йер. 39:2; 52:6–7",
# „Мих. 4:2–3, 5; 6:5; 8:5, 4" (18.10.2026). ⚠ Само с ДВОЕТОЧИЕ — голото
# „; 14–26" не се знае какво е (у Дебольски така е и в руския извор).
RE_CONT = re.compile(
    r'(<a href="https://azbyka\.ru/biblia/\?([0-9A-Za-z]+)\.[^"]*"[^>]*>[^<]*</a>)'
    r'(\s*[;.]\s*)(\d{1,3}:\d{1,3}' + _RANGE + _MORE + r')(?![\d:])')

# Цяла глава: „(Пс. 5)", „Йер. 50 и 51", „4 Цар. 17" (18.10.2026). ⚠ Само с
# ТОЧКА след книгата и само ако главата я има — инак „Зач. 9" и подобни.
RE_CHAPTER = re.compile(
    r'(?<![\w])([1-4]\s*)?' + _NAME + r'\.\s*(\d{1,3})(?![\d:,.–-])'
    r'(?:(\s+и\s+)(\d{1,3})(?![\d:,]))?')


# Името на книгата ИЗВЪН скобите, само мястото в тях: „Естир (9:30)",
# „книга Изход (13:1–31. 15:1–10)" (18.10.2026). ⚠ Името трябва да е
# ПЪЛНО и с главна буква — „книга Царства (17:8)" не се знае коя е и остава.
_SEG = r'\d{1,3}:\d{1,3}' + _RANGE + _MORE
RE_NAMED = re.compile(
    r'(?<![\w])([1-4]\s*)?([А-ЯЁ][а-яё]{2,12}(?:\s+(?:Навин|Соломонови))?)'
    r'(\s*\()(' + _SEG + r'(?:\s*[;.]\s*' + _SEG + r')*)(\))')


def _verses() -> dict:
    db = sqlite3.connect(BIBLE_DB)
    out = {}
    for b, c, v in db.execute(
            "SELECT book, chapter, MAX(CAST(verse AS INTEGER)) FROM verses "
            "WHERE lang='bg' GROUP BY book, chapter"):
        out[(b, c)] = v
    return out


_VS = None


def valid(code: str, addr: str) -> bool:
    """Има ли ТАКОВА място в Писанието — „Мих. 8:5" (Михей има 7 глави)
    е грешка в извора и не бива да става връзка към празна глава."""
    global _VS
    if _VS is None:
        _VS = _verses()
    if ':' not in addr:                  # цели глави: „50", „5"
        return all((code, int(c)) in _VS for c in re.split(r'[,-]', addr))
    ch = None
    for part in re.split(r'[,-]', addr):
        if ':' in part:
            c, v = part.split(':')
            ch = int(c)
        else:
            v = part
        if ch is None or not (1 <= int(v) <= _VS.get((code, ch), 0)):
            return False
    return True


def _chapters() -> dict:
    db = sqlite3.connect(BIBLE_DB)
    return dict(db.execute(
        "SELECT book, MAX(chapter) FROM verses WHERE lang='bg' GROUP BY book"))


def _addr(places: str) -> str:
    # ⚠ Запетаята между глава и стих е руският запис („Лк.2, 21"); в
    # адреса тя трябва да е ДВОЕТОЧИЕ, инак се чете като втори пасаж.
    # ⚠⚠ ДЪЛГОТО ТИРЕ НЕ ВЪРВИ В АДРЕСА — видимият текст го пази.
    addr = places.replace(' ', '').replace('–', '-').replace('—', '-')
    addr = re.sub(r'^(\d{1,3}),', r'\1:', addr)
    # „18:28-19:1-16" → „18:28-19:16"
    addr = re.sub(r'(\d+:\d+-\d+:)\d+-(\d+)', r'\1\2', addr)
    return addr


def _a(code: str, addr: str, shown: str) -> str:
    return (f'<a href="https://azbyka.ru/biblia/?{code}.{addr}'
            f'&amp;bg~utfcs">{shown}</a>')


def link(text: str, table: dict, stats: dict | None = None) -> str:
    """Обвива препратките във връзки. ИДЕМПОТЕНТНО: пипа само текста ИЗВЪН
    вече съществуващите <a>…</a>, тъй че повторно пускане не обвива двойно."""
    stats = stats if stats is not None else {}
    chapters = _chapters_cached()

    def repl(m):
        num, name, places = m.group(1), m.group(2), m.group(3)
        key = _key((num or '') + name)
        code = table.get(key)
        if not code:
            stats.setdefault('unknown', {})
            stats['unknown'][key] = stats['unknown'].get(key, 0) + 1
            return m.group(0)
        stats['links'] = stats.get('links', 0) + 1
        return _a(code, _addr(places), m.group(0))

    def repl_chapter(m):
        num, name, ch, sep, ch2 = m.groups()
        code = table.get(_key((num or '') + name))
        last = chapters.get(code, 0) if code else 0
        if not code or not (1 <= int(ch) <= last) or \
                (ch2 and not (1 <= int(ch2) <= last)):
            return m.group(0)
        stats['chapters'] = stats.get('chapters', 0) + 1
        head = m.group(0)[:m.end(3) - m.start(0)]
        out = _a(code, ch, head)
        if ch2:
            out += sep + _a(code, ch2, ch2)
        return out

    def each_text(s, fn):
        parts = re.split(r'(<a\b[^>]*>.*?</a>|<[^>]+>)', s, flags=re.S)
        out = []
        for p in parts:
            if p.startswith('<a'):
                out.append(re.sub(
                    r'(href="https://azbyka\.ru/biblia/\?[^"]*)',
                    lambda m: m.group(1).replace('–', '-').replace('—', '-'), p))
            elif p.startswith('<'):
                out.append(p)            # таг — атрибутите му не се пипат
            else:
                out.append(fn(p))
        return ''.join(out)

    text = each_text(text, lambda p: RE_REF.sub(repl, p))

    def repl_cont(m):
        addr = _addr(m.group(4))
        if not valid(m.group(2), addr):
            stats.setdefault('invalid', []).append(f'{m.group(2)}.{addr}')
            return m.group(0)
        stats['cont'] = stats.get('cont', 0) + 1
        return m.group(1) + m.group(3) + _a(m.group(2), addr, m.group(4))

    def repl_named(m):
        num, name, op, places, cl = m.groups()
        code = table.get(_key((num or '') + name))
        if not code:
            return m.group(0)
        segs = re.split(r'(\s*[;.]\s*)', places)
        out = []
        for k, seg in enumerate(segs):
            if k % 2:
                out.append(seg)
                continue
            addr = _addr(seg)
            if not valid(code, addr):
                stats.setdefault('invalid', []).append(f'{code}.{addr}')
                out.append(seg)
            else:
                stats['named'] = stats.get('named', 0) + 1
                out.append(_a(code, addr, seg))
        return m.group(0)[:m.start(3) - m.start(0)] + op + ''.join(out) + cl

    while True:                          # вериги: „; 6:5; 8:5, 4"
        new = RE_CONT.sub(repl_cont, text)
        if new == text:
            break
        text = new
    text = each_text(text, lambda p: RE_NAMED.sub(repl_named, p))
    return each_text(text, lambda p: RE_CHAPTER.sub(repl_chapter, p))


_CH = None


def _chapters_cached() -> dict:
    global _CH
    if _CH is None:
        _CH = _chapters()
    return _CH
