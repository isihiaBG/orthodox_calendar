#!/usr/bin/env python3
"""Основните изчисления на православния календар — без зависимости.

    python3 church_calendar.py 2027            Пасха и подвижните празници
    python3 church_calendar.py 2026-10-25      ден: адрес, глас, църковна дата
    python3 church_calendar.py 2026-10-25 --new   същото, по нов стил

Сверено с генератора на проекта (tools/calendar_gen) и с lib/readings_lookup.dart.
Всички дати тук са ГРАЖДАНСКИ (григориански), освен изрично „църковна".

Стилове:
  стар (юлиански) — неподвижните празници са на църковната (юлианска) дата,
                    тоест 13 дни по-късно граждански (1900–2099; от 2100 — 14);
  нов (новоюлиански, БПЦ от 1968) — неподвижните са на гражданската дата.
  Пасхалията е ОБЩА: Пасха е един и същ граждански ден и в двата стила.
"""
import datetime
import sys

D = datetime.date
TD = datetime.timedelta


# ── Юлиански ден — превръщане без твърдо „+13" (през 2100 г. става 14) ──

def jdn_from_julian(y, m, d):
    a = (14 - m) // 12
    yy, mm = y + 4800 - a, m + 12 * a - 3
    return d + (153 * mm + 2) // 5 + 365 * yy + yy // 4 - 32083


def gregorian_from_jdn(j):
    a = j + 32044
    b = (4 * a + 3) // 146097
    c = a - 146097 * b // 4
    d = (4 * c + 3) // 1461
    e = c - 1461 * d // 4
    m = (5 * e + 2) // 153
    return D(100 * b + d - 4800 + m // 10, m + 3 - 12 * (m // 10),
             e - (153 * m + 2) // 5 + 1)


def julian_to_civil(y, m, d):
    """Юлианска (църковна по стар стил) дата → гражданска."""
    return gregorian_from_jdn(jdn_from_julian(y, m, d))


def civil_from_church(year, month, day, old_style=True):
    """Гражданската дата на неподвижен празник с църковна дата ММ-ДД."""
    return julian_to_civil(year, month, day) if old_style else D(year, month, day)


def church_from_civil(date, old_style=True):
    """Църковната дата (месец, ден) на граждански ден."""
    if not old_style:
        return date.month, date.day
    off = (julian_to_civil(date.year, 1, 1) - D(date.year, 1, 1)).days
    c = date - TD(days=off)
    return c.month, c.day


# ── Пасхалията (александрийска, по юлианския календар) ─────────────────

def pascha(year):
    """Православна Пасха като ГРАЖДАНСКА дата (обща за двата стила)."""
    a, b, c = year % 4, year % 7, year % 19
    d = (19 * c + 15) % 30
    e = (2 * a + 4 * b - d + 34) % 7
    month = (d + e + 114) // 31
    day = (d + e + 114) % 31 + 1
    return julian_to_civil(year, month, day)


MOVABLE = [  # (отместване от Пасха, име)
    (-70, 'Неделя на Митаря и Фарисея — начало на Триода'),
    (-63, 'Неделя на Блудния син'),
    (-57, 'Месопустна задушница'),
    (-56, 'Месопустна неделя (за Страшния съд)'),
    (-49, 'Сиропустна неделя (Неделя на прошката)'),
    (-48, 'Чист понеделник — начало на Великия пост'),
    (-43, 'Тодорова събота'),
    (-42, 'Неделя на Православието'),
    (-36, 'Родителска събота (2-ра седмица на поста)'),
    (-29, 'Родителска събота (3-та седмица)'),
    (-28, 'Кръстопоклонна неделя'),
    (-22, 'Родителска събота (4-та седмица)'),
    (-17, 'Мариино стоене (четвъртък на 5-та седмица)'),
    (-8, 'Лазарова събота'),
    (-7, 'Цветница (Връбница) — Вход Господен в Йерусалим'),
    (-6, 'Велики понеделник'),
    (-3, 'Велики четвъртък'),
    (-2, 'Велики петък'),
    (-1, 'Велика събота'),
    (0, 'ПАСХА — Възкресение Христово'),
    (5, 'Петък на Светлата седмица — Живоносен източник'),
    (7, 'Томина неделя (Антипасха)'),
    (14, 'Неделя на Мироносиците'),
    (21, 'Неделя на Разслабления'),
    (24, 'Преполовение'),
    (28, 'Неделя на Самарянката'),
    (35, 'Неделя на Слепия'),
    (39, 'Възнесение Господне'),
    (42, 'Неделя на отците от I Вселенски събор'),
    (48, 'Троицка (Петдесетнична) задушница'),
    (49, 'Петдесетница (Неделя Троицка)'),
    (50, 'Духовден'),
    (56, 'Неделя на Всички светии'),
    (57, 'Начало на Петровия пост (ако Петровден не е преди това)'),
    (63, 'Неделя на Всички български светии'),
]


def governing_pascha(date):
    """Пасхата, от която се брои денят: старата важи до деня преди
    Неделята на Митаря (Пасха − 70) на следващата."""
    p = pascha(date.year)
    return p if date >= p - TD(days=70) else pascha(date.year - 1)


# ── Литургичният адрес (как са ключирани четивата) ─────────────────────

def reading_address(date):
    """T<седм>:<ден> Триод, P<седм>:<ден> Пентикостар, W<седм>:<ден> по
    Петдесетница. Ден: 1 = понеделник … 7 = неделя.

    ⚠ Седмицата се брои по РАЗСТОЯНИЕТО ДО/ОТ ПАСХА и върви НЕДЕЛЯ→СЪБОТА:
    Сиропустна неделя (Пасха−49) е T4:7, а Чистият понеделник (Пасха−48) —
    пак T4:1, НЕ T5:1. В W „Неделя N“ е в КРАЯ на седмица N (W1:7 = Всички
    светии)."""
    nxt = pascha(date.year) if date <= pascha(date.year) else pascha(date.year + 1)
    until = (nxt - date).days
    wd = date.isoweekday()
    if 0 < until <= 70:
        return f'T{(70 - until) // 7 + 1}:{wd}'
    prev = pascha(date.year) if date >= pascha(date.year) else pascha(date.year - 1)
    n = (date - prev).days
    if n <= 49:
        return f'P{n // 7 + 1}:{wd}'
    return f'W{(n - 50) // 7 + 1}:{wd}'


# ── Гласът (осмогласие) ────────────────────────────────────────────────

BRIGHT_WEEK = [0, 2, 3, 4, 5, 6, 8]           # Пасха…Светла събота (0 = без глас)
LORDLY_FIXED = [(1, 6), (3, 25), (8, 6), (9, 14), (12, 25)]
LORDLY_FROM_PASCHA = {0, 39, 49}


def underlying_tone(date):
    """Скритият глас 1–8: сменя се в неделя (седмицата Нед–Съб носи гласа
    на своята неделя); рестарт на 1 в Томина неделя (Пасха+7) и в Неделята
    на Митаря (Пасха−70). Светлата седмица — свой дневен ред."""
    p = governing_pascha(date)
    off = (date - p).days
    if 0 <= off <= 6:
        return BRIGHT_WEEK[off]
    sunday_off = off - (date.isoweekday() % 7)
    anchor = 7 if sunday_off >= 7 else -70
    return (sunday_off - anchor) // 7 % 8 + 1


def tone(date, old_style=True):
    """Гласът, който се показва за деня; 0 = без глас (Страстната седмица,
    Цветница, Господски празник, неделите преди и след Богоявление)."""
    p = governing_pascha(date)
    off = (date - p).days
    if -7 <= off <= -1:
        return 0
    if off in LORDLY_FROM_PASCHA:
        return 0
    for y in (date.year - 1, date.year, date.year + 1):
        if any(civil_from_church(y, m, d, old_style) == date for m, d in LORDLY_FIXED):
            return 0
    if date.isoweekday() == 7:
        for y in (date.year - 1, date.year, date.year + 1):
            th = civil_from_church(y, 1, 6, old_style)
            back = (th.isoweekday() % 7)
            before = th - TD(days=back) if back else th - TD(days=7)
            after = before + TD(days=14) if not back else before + TD(days=7)
            if date in (before, after):
                return 0
    return underlying_tone(date)


# ── Най-близката неделя (Отците на шестте събора, на седмия събор) ────

def nearest_sunday(d):
    """Празник в чт–сб → следващата неделя; пн–ср → предишната; нед → самият."""
    fwd = (7 - d.isoweekday()) % 7
    back = d.isoweekday() % 7
    return d + TD(days=fwd) if fwd <= back else d - TD(days=back)


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return
    arg = sys.argv[1]
    old = '--new' not in sys.argv
    if len(arg) == 4:
        y = int(arg)
        p = pascha(y)
        print(f'Пасха {y}: {p} ({"стар" if old else "нов"} стил — една и съща дата)')
        for off, name in MOVABLE:
            d = p + TD(days=off)
            print(f'  {d}  Пасха{off:+d}  {name}')
        petr = civil_from_church(y, 6, 29, old)
        start = p + TD(days=57)
        print(f'  Петров пост: {start} … {petr - TD(days=1)}'
              f' ({max(0, (petr - start).days)} дни)')
        print(f'  Отците на шестте събора: {nearest_sunday(civil_from_church(y, 7, 16, old))}')
        print(f'  Отците на седмия събор:  {nearest_sunday(civil_from_church(y, 10, 11, old))}')
        return
    d = D.fromisoformat(arg)
    m, dd = church_from_civil(d, old)
    p = governing_pascha(d)
    print(f'{d} ({"стар" if old else "нов"} стил)')
    print(f'  църковна дата: {dd:02d}.{m:02d}')
    print(f'  от Пасха {p}: {(d - p).days:+d} дни')
    print(f'  адрес на четивата: {reading_address(d)}')
    print(f'  глас: {tone(d, old) or "—"} (скрит: {underlying_tone(d)})')


if __name__ == '__main__':
    main()
