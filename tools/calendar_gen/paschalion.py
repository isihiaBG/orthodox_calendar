"""Python порт на lib/paschalion.dart — трябва да смята абсолютно същото."""
import datetime


def julian_gregorian_offset(year: int) -> int:
    c = year // 100
    return c - c // 4 - 2


def pascha_julian(year: int) -> tuple[int, int]:
    a = year % 4
    b = year % 7
    c = year % 19
    d = (19 * c + 15) % 30
    e = (2 * a + 4 * b - d + 34) % 7
    month = (d + e + 114) // 31
    day = (d + e + 114) % 31 + 1
    return month, day


def pascha_civil(year: int) -> datetime.date:
    m, d = pascha_julian(year)
    return datetime.date(year, m, d) + datetime.timedelta(
        days=julian_gregorian_offset(year))


def civil_from_church(year: int, month: int, day: int, old_style: bool) -> datetime.date:
    d = datetime.date(year, month, day)
    if old_style:
        return d + datetime.timedelta(days=julian_gregorian_offset(year))
    return d
