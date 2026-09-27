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
RE_REF = re.compile(
    r'(?<![\w])([1-4]\s*)?([А-Яа-яЁё]{2,8})\.?\s*'
    r'(\d{1,3}\s*[:,]\s*\d{1,3}(?:\s*[-–]\s*\d{1,3}(?::\d{1,3})?)?'
    r'(?:\s*,\s*\d{1,3}(?:\s*[-–]\s*\d{1,3})?)*)')


def link(text: str, table: dict, stats: dict | None = None) -> str:
    """Обвива препратките във връзки. ИДЕМПОТЕНТНО: пипа само текста ИЗВЪН
    вече съществуващите <a>…</a>, тъй че повторно пускане не обвива двойно."""
    stats = stats if stats is not None else {}

    def repl(m):
        num, name, places = m.group(1), m.group(2), m.group(3)
        key = _key((num or '') + name)
        code = table.get(key)
        if not code:
            stats.setdefault('unknown', {})
            stats['unknown'][key] = stats['unknown'].get(key, 0) + 1
            return m.group(0)
        # ⚠ Запетаята между глава и стих е руският запис („Лк.2, 21"); в
        # адреса тя трябва да е ДВОЕТОЧИЕ, инак се чете като втори пасаж.
        # ⚠⚠ ДЪЛГОТО ТИРЕ НЕ ВЪРВИ В АДРЕСА — видимият текст го пази.
        addr = places.replace(' ', '').replace('–', '-').replace('—', '-')
        addr = re.sub(r'^(\d{1,3})\s*,\s*', r'\1:', addr)
        stats['links'] = stats.get('links', 0) + 1
        return (f'<a href="https://azbyka.ru/biblia/?{code}.{addr}'
                f'&amp;bg~utfcs">{m.group(0)}</a>')

    parts = re.split(r'(<a\b[^>]*>.*?</a>|<[^>]+>)', text, flags=re.S)
    out = []
    for p in parts:
        if p.startswith('<a'):
            out.append(re.sub(
                r'(href="https://azbyka\.ru/biblia/\?[^"]*)',
                lambda m: m.group(1).replace('–', '-').replace('—', '-'), p))
        elif p.startswith('<'):
            out.append(p)            # таг — атрибутите му не се пипат
        else:
            out.append(RE_REF.sub(repl, p))
    return ''.join(out)
