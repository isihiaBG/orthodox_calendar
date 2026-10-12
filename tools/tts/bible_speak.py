"""Библейските препратки — с думи, за четене на глас (11.10.2026).

„3 Цар. 5:15" → „Трета книга Царства, пета глава, петнадесети стих".

Книгите се разпознават със СЪЩИТЕ съкращения като връзките в приложението
(`tools/bible_refs/linkify.py`), а пълното име идва от `books.bg_title` в
bible.db. Псалтирът се чете „псалом N", не „Псалтир, N-та глава".

Пуска се ПРЕДИ съкращенията: имената носят „св. ап.", които после стават
„свети апостол".
"""

import re
import sqlite3
import sys
from pathlib import Path

from numbers_bg import ordinal

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools' / 'bible_refs'))
import linkify  # noqa: E402

_TABLE = linkify.abbreviations()
# Руски форми, които се срещат в томовете, а ги няма в linkify.
_TABLE.setdefault('мф', 'Mt')
_TITLES = dict(sqlite3.connect(linkify.BIBLE_DB).execute('SELECT code, bg_title FROM books'))
# В базата е „Марко“; авторът го чете „Марк“ (12.10.2026).
_TITLES['Mk'] = _TITLES['Mk'].replace('Марко', 'Марк')

_D = r'\s*[-–—]\s*'
# Книга + място. Мястото: глава:стих(ове), със запетаи, диапазони и
# следващи глави („Мал. 3:1–3, 6–7, 4:4–6"), или руското „Лк.2, 21".
RE = re.compile(
    r'(?<![\w])([1-4]\s*)?([А-Яа-яЁё]{2,8})\.?\s*'
    r'(\d{1,3}\s*[:,]\s*\d{1,3}'
    r'(?:(?:' + _D + r'|\s*,\s*)\d{1,3}(?:\s*:\s*\d{1,3})?)*)')


def _v(n):
    return ordinal(n, 'm')


def _verses(items):
    """[(a, b)] → „петнадесети стих" / „стихове от първи до трети, шести"."""
    if len(items) == 1 and items[0][0] == items[0][1]:
        return f'{_v(items[0][0])} стих'
    if len(items) == 1 and items[0][1] == items[0][0] + 1:
        a, b = items[0]
        return f'стихове {_v(a)} и {_v(b)}'
    words = [_v(a) if a == b else f'от {_v(a)} до {_v(b)}' for a, b in items]
    body = words[0] if len(words) == 1 else ', '.join(words[:-1]) + ' и ' + words[-1]
    return 'стихове ' + body


def _chapter(code, c):
    return f'{_v(c)} псалом' if code == 'Ps' else f'{ordinal(c)} глава'


def speak_place(code, place):
    """„5:15" → „пета глава, петнадесети стих". None, ако не се разчита."""
    p = re.sub(r'\s+', '', place).replace('–', '-').replace('—', '-')
    p = re.sub(r'^(\d+),', r'\1:', p)          # руското „2, 21"
    # Глава през глава: „13:4-14:28"
    m = re.fullmatch(r'(\d+):(\d+)-(\d+):(\d+)', p)
    if m:
        c1, v1, c2, v2 = map(int, m.groups())
        return (f'от {_chapter(code, c1)}, {_v(v1)} стих, '
                f'до {_chapter(code, c2)}, {_v(v2)} стих')
    groups, cur = [], None
    for tok in p.split(','):
        mm = re.fullmatch(r'(?:(\d+):)?(\d+)(?:-(\d+))?', tok)
        if not mm:
            return None
        c, a, b = mm.group(1), int(mm.group(2)), int(mm.group(3) or mm.group(2))
        if b < a:
            return None
        if c:
            cur = (int(c), [])
            groups.append(cur)
        elif cur is None:
            return None
        cur[1].append((a, b))
    return ', '.join(f'{_chapter(code, c)}, {_verses(vs)}' for c, vs in groups)


def bible_text(txt):
    def repl(m):
        num, name, place = m.group(1), m.group(2), m.group(3)
        code = _TABLE.get(linkify._key((num or '') + name))
        if not code:
            return m.group(0)
        spoken = speak_place(code, place)
        if not spoken:
            return m.group(0)
        if code == 'Ps':
            return spoken[0].upper() + spoken[1:]
        return f'{_TITLES[code]}, {spoken}'
    return RE.sub(repl, txt)


if __name__ == '__main__':
    checks = {
        '3Цар. 5:15': 'Трета книга Царства, пета глава, петнадесети стих',
        '( Мат. 14:15–21 )': '( Евангелие от Матей, четиринадесета глава, стихове от петнадесети до двадесет и първи )',
        'Пс. 21:17–18': 'Двадесет и първи псалом, стихове седемнадесети и осемнадесети',
        'Мал. 3:1–3, 6–7, 12, 4:4–6': 'Книга на пророк Малахия, трета глава, стихове от първи до трети, от шести до седми и дванадесети, четвърта глава, стихове от четвърти до шести',
        '1 Кор. 15:55': 'Първо послание до коринтяни, петнадесета глава, петдесет и пети стих',
        'Лк.2, 21': 'Евангелие от Лука, втора глава, двадесет и първи стих',
        '2 Кор. 4:17-5:5': 'Второ послание до коринтяни, от четвърта глава, седемнадесети стих, до пета глава, пети стих',
        'Йоан. 21:16–17 .': 'Евангелие от Йоан, двадесет и първа глава, стихове шестнадесети и седемнадесети .',
    }
    bad = 0
    for s, want in checks.items():
        got = bible_text(s)
        if got != want:
            bad += 1
            print('✗', s, '\n   →', got, '\n   ≠', want)
    print('грешки:', bad, 'от', len(checks))
