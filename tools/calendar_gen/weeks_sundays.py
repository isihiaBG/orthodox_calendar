"""Генератор на weeks/sundays (тон, номер седмица/неделя) — Проход 1.

НЕ пренарежда съществуващите 53/52 реда от calendar_old.db — те са
построени САМО за разстоянието между Пасха 2025 и Пасха 2026, а то е
различно за всяка двойка последователни години. Затова тук СМЯТАМЕ
позицията на всеки ден отначало, за произволна година.

Обхваща само "простата" зона (виж README): всичко освен Богоявление и
опашката около Въздвижение/Рождество (Проход 2, отделно).
"""
import datetime

from paschalion import pascha_civil, civil_from_church
from rules import resolve as resolve_rule

# Тон, който съпровожда всеки понеделник (осемгласие, повтаря се). Взето
# директно от weeks.tone в calendar_old.db за simple диапазона — самият
# цикъл на гласовете е фиксиран спрямо Пасха, не зависи от годината.
TONE_AT_WEEK_START = {
    -88: 6, -83: 7, -76: 8, -69: 1, -62: 2, -55: 3, -48: 4, -41: 5, -34: 6,
    -27: 7, -20: 8, -13: 1, -6: 2, 1: None, 8: 1, 15: 2, 22: 3, 29: 4,
    36: 5, 43: 6, 50: 7,
}


def governing_pascha(date: datetime.date) -> datetime.date:
    """Коя Пасха управлява броенето на този ден. Периодът "N-та седмица/
    неделя след Петдесетница" продължава от МИНАЛОГОДИШНАТА Пасха чак до
    Неделя на Митаря и Фарисея (Пасха на текущия цикъл минус 70) —
    оттам започва броенето наново."""
    p = pascha_civil(date.year)
    if date >= p - datetime.timedelta(days=70):
        return p
    return pascha_civil(date.year - 1)


# ── Простите (нероднинени с неподвижен празник) именувани недели/седмици.
# offset спрямо управляващата Пасха -> (weeks_name, sundays_name, tone).
# None = денят не носи собствено име тук (напр. делник без специална
# неделя/седмица покрай него все още се смята чрез диапазона по-долу).
NAMED_SUNDAYS = {
    -70: 'Неделя на Митаря и Фарисея',
    -63: 'Неделя на Блудния син',
    -56: 'Неделя на Страшния съд. Месопустна',
    -49: 'Неделя Сиропустна. Възпоменание на Адамовото изгонване от рая. '
         'Неделя на прошката',
    -42: 'Неделя 1 на Великия пост - Православна. Тържество на Православието',
    -35: 'Неделя 2 на Великия пост',
    -28: 'Неделя 3 на Великия пост - Кръстопоклонна',
    -21: 'Неделя 4 на Великия пост',
    -14: 'Неделя 5 на Великия пост',
    -7: 'Неделя 6 на Великия пост (Цветница, Връбница)',
    0: '',  # Пасха самата — не носи "неделен" ред, тя Е празникът
    7: 'Неделя 2 след Пасха. Томина Неделя. Антипасха',
    14: 'Неделя 3 след Пасха, на Мироносиците',
    21: 'Неделя 4 след Пасха, на Разслабения',
    28: 'Неделя 5 след Пасха, на Самарянката',
    35: 'Неделя 6 след Пасха, на Слепия',
    42: 'Неделя 7 след Пасха, на св. отци от Първия вселенски събор (325г.)',
    49: 'Неделя 8 след Пасха',
}

NAMED_WEEKS = {
    # ВНИМАНИЕ: НЕ добавяй тук офсети за "опашката" (Седмица 32/33/34 след
    # Петдесетница, началото на изходните данни) — те принадлежат на
    # МИНАЛОГОДИШНАТА Пасха и governing_pascha() вече ги пренасочва
    # правилно към общата периодична формула по-долу. Първият ми опит
    # сложи тук офсети, смятани спрямо ТАЗИГОДИШНАТА Пасха по грешка
    # (-88/-83/-76, реално ≡3 а не ≡1 по мод 7 като всички истински
    # начала на седмица) — затова не мина проверката.
    -69: '1 подготвителна седмица пред Великия пост',
    -62: '2 подготвителна седмица пред Великия пост',
    -55: '3 подготвителна седмица пред Великия пост',
    -48: 'Седмица 1 на Великия пост',
    -41: 'Седмица 2 на Великия пост',
    -34: 'Седмица 3 на Великия пост',
    -27: 'Седмица 4 на Великия пост',
    -20: 'Седмица 5 на Великия пост',
    -13: 'Седмица 6 на Великия пост',
    -6: 'Страстна седмица',
    1: 'Светла седмица',
    8: 'Седмица 2 след Пасха',
    15: 'Седмица 3 след Пасха',
    22: 'Седмица 4 след Пасха',
    29: 'Седмица 5 след Пасха',
    36: 'Седмица 6 след Пасха',
    43: 'Седмица 7 след Пасха',
}

# Особени добавки към "Неделя {n} след Петдесетница" за конкретни n.
PENTECOST_SUNDAY_SUFFIX = {
    1: ', на всички светии',
    2: ', на всички български светии и на всички преп. и богоносни отци '
       'от Св. Гора',
    8: '. † Неделя на св. отци от Шестте вселенски събора',
}


def post_pentecost_n(offset: int) -> int:
    """N в "седмица/неделя N след Петдесетница" — офсетът 56 е неделята
    на Всички светии (Петдесетница+7, тя е N=1)."""
    return (offset - 49) // 7


# ── Проход 2: котвената опашка (Въздвижение → Рождество → Богоявление) ──
#
# Всеки анкер има църковна (месец,ден); гражданската му дата зависи от
# годината/стила (civil_from_church). За всяка неделя в тази опашка:
#   - ако неделята Е самият анкер (пада точно в неделя тази година) —
#     БЕЗ суфикс (потвърдено от данните: id37 при Въздвижение-в-неделя
#     остава чисто "Неделя 17 след Петдесетница", нищо повече).
#   - неделята веднага ПРЕДИ анкера получава "† Неделя преди {анкер}"
#   - неделята веднага СЛЕД анкера получава "† Неделя след {анкер}"
# Между "неделя след Въздвижение" и "2 преди Рождество" веригата се БРОИ
# НЕПРЕКЪСНАТО: "† Неделя {k} след Нед. подир Въздвижение" — дължината ѝ
# зависи от годината (колко недели се събират между двата анкера), затова
# не е таван, а изчислено разстояние.
# Богоявление е особен случай: заменя ЦЕЛИЯ текст (без номер отпред,
# без "†") — виж combine_sunday_name().
ANCHORS = {
    'Въздвижение': (9, 14),
    'Рождество Христово': (12, 25),
    'Богоявление': (1, 6),
}


def _nearest_sunday_offsets(anchor_civil: datetime.date) -> tuple[datetime.date, datetime.date]:
    """(неделята точно преди анкера, неделята точно след анкера). Ако
    анкерът сам е неделя, "преди" и "след" са седмица встрани от него —
    самият ден не получава суфикс (виж бележката горе)."""
    back = (anchor_civil.weekday() - 6) % 7  # дни назад до най-близката неделя <= анкера
    on_or_before = anchor_civil - datetime.timedelta(days=back)
    if on_or_before == anchor_civil:
        before = on_or_before - datetime.timedelta(days=7)
        after = on_or_before + datetime.timedelta(days=7)
    else:
        before = on_or_before
        after = on_or_before + datetime.timedelta(days=7)
    return before, after


def _anchor_sundays(feast: str, sunday_date: datetime.date, old_style: bool):
    """(before, after) недели около [feast], търсени в година±1 спрямо
    гражданската година на самата неделя — двата края на веригата
    (Богоявление в началото, Рождество/Въздвижение по-късно) идват от
    различни календарни години при броене назад/напред."""
    m, d = ANCHORS[feast]
    best = None
    for y in (sunday_date.year - 1, sunday_date.year, sunday_date.year + 1):
        anchor_civil = civil_from_church(y, m, d, old_style)
        before, after = _nearest_sunday_offsets(anchor_civil)
        if best is None or abs((before - sunday_date).days) < abs((best[0] - sunday_date).days):
            best = (before, after)
    return best


def anchor_qualifier(sunday_date: datetime.date, old_style: bool) -> str | None:
    """Суфиксът "† ..." (без началното "† " за Богоявление — виж
    combine_sunday_name) за тази неделя, или None ако не е близо до нито
    един анкер."""
    v_before, v_after = _anchor_sundays('Въздвижение', sunday_date, old_style)
    r_before, r_after = _anchor_sundays('Рождество Христово', sunday_date, old_style)
    b_before, b_after = _anchor_sundays('Богоявление', sunday_date, old_style)
    r_two_before = r_before - datetime.timedelta(days=7)

    if sunday_date == b_before:
        return 'Неделя преди Богоявление'
    if sunday_date == b_after:
        return 'Неделя след Богоявление'

    if sunday_date == v_before:
        return '† Неделя преди Въздвижение'
    if sunday_date == r_after:
        return '† Неделя след Рождество Христово'
    if sunday_date == r_two_before:
        return '† Неделя на св. Праотци Христови'
    if sunday_date == r_before:
        return '† Неделя преди Рождество Христово, на св. отци'
    if sunday_date == v_after:
        return '† Неделя след Въздвижение'
    if v_after < sunday_date < r_two_before:
        k = (sunday_date - v_after).days // 7
        return f'† Неделя {k} след Нед. подир Въздвижение'
    return None


def simple_position(date: datetime.date):
    """(week_name, sunday_name) за деня, или None ако е в "сложната"
    зона (Богоявление/Въздвижение/Рождество опашка — Проход 2).

    Конвенцията на calendar_old.db: week_id стои САМО на делник,
    sunday_id САМО на неделя (проверено по цялата таблица) — затова
    двете полета тук са взаимно изключващи се по дена от седмицата."""
    p = governing_pascha(date)
    offset = (date - p).days
    is_sunday = date.weekday() == 6

    sunday_name = None
    if is_sunday:
        if offset in NAMED_SUNDAYS:
            sunday_name = NAMED_SUNDAYS[offset]
        elif offset >= 56 and offset % 7 == 0:
            n = post_pentecost_n(offset)
            sunday_name = (f'Неделя {n} след Петдесетница'
                            + PENTECOST_SUNDAY_SUFFIX.get(n, ''))

    if offset < -70:
        # Все още не сме стигнали дори Митар и Фарисей на тази управляваща
        # Пасха — governing_pascha() винаги би трябвало да е избрал
        # по-ранна Пасха в такъв случай (виж теста в дъното на файла).
        return None

    week_name = None
    if not is_sunday:
        # Закръгляне НАДОЛУ до понеделника на седмицата: всички истински
        # начала на седмица са ≡1 по мод 7 спрямо Пасха (Великият пост
        # започва в понеделник = Пасха-48, -48 mod 7 == 1) — това важи за
        # ЦЕЛИЯ прост диапазон, проверено директно по данните.
        week_start = offset - ((offset - 1) % 7)
        if week_start in NAMED_WEEKS:
            week_name = NAMED_WEEKS[week_start]
        elif week_start >= 50:
            # Номерацията започва от "Седмица 1 след Петдесетница" веднага
            # след Петдесетница (id21) — там имаше печатна грешка ("2",
            # дублирано и на id22), потвърдена и вече поправена direkt в
            # calendar_old.db от потребителя.
            n = post_pentecost_n(week_start - 1) + 1
            week_name = f'Седмица {n} след Петдесетница'

    return week_name, sunday_name


# ── Отделни, независими подвижни памети, наслагващи се ВЪРХУ каквото и да
# е произвела anchor_qualifier за същата неделя — не заменят нищо, само
# добавят изречение. Правилото е външно знание (текстът в sundays.name
# не съдържа "11 октомври" никъде) — потвърдено с реалната гражданска
# дата (2026-10-25) и оставено като DSL израз, не гол офсет, защото е
# котвено към неподвижна дата, не към Пасха.
EXTRA_SUNDAY_MEMORIES = [
    ('10-11~нед', '† Неделя на св. отци от Седмия вселенски събор в Никея (787 г.)'),
]


def extra_qualifiers(sunday_date: datetime.date, old_style: bool) -> list[str]:
    out = []
    for rule_text, text in EXTRA_SUNDAY_MEMORIES:
        d = resolve_rule(rule_text, sunday_date.year, old_style, {})
        if d == sunday_date:
            out.append(text)
    return out


def position(date: datetime.date, old_style: bool) -> tuple[str | None, str | None]:
    """(week_name, sunday_name) за произволен ден, произволна година —
    цялата логика (Проход 1 + Проход 2) на едно място. Това е това,
    което build.py трябва да вика."""
    got = simple_position(date)
    if got is None:
        return None, None
    week_name, sunday_name = got
    if date.weekday() == 6:
        q = anchor_qualifier(date, old_style)
        if q:
            sunday_name = q if 'Богоявление' in q else (
                f'{sunday_name}. {q}' if sunday_name else q)
        for extra in extra_qualifiers(date, old_style):
            sunday_name = f'{sunday_name}. {extra}' if sunday_name else extra
    return week_name, sunday_name


# ── Гласове (Осмогласие) ────────────────────────────────────────────────
#
# Скрит НЕПРЕКЪСНАТ седмичен цикъл 1..8..1..., сменя се точно в неделя
# (седмицата Нед-Съб носи гласа на тази неделя). Рестартира се на 1 точно
# на Томина неделя (Пасха+7) — потвърдено empirически. Дали Митар и
# Фарисей (Пасха-70) е ОЩЕ един нарочен рестарт, или просто съвпада с
# непрекъснатия цикъл, потребителят проверява отделно — засега приемаме
# непрекъснат цикъл от последния Антипасхален рестарт назад/напред.
#
# Отгоре на скрития цикъл, КОНКРЕТНИЯТ ден показва 0 (без водещ глас),
# когато:
#   - в saints за деня има запис с rank=1 (Господски/Богородичен празник)
#   - денят е от Страстната седмица (Пасха-6 .. Пасха-1)
#   - денят е Цветница (Пасха-7) — самата седмица преди/след си пази
#     нормалния скрит глас, само тя денят показва 0
#   - денят е Петдесетница (Пасха+49) — същото, само този ден
#   - денят е неделята преди ИЛИ след Богоявление (двете заедно)
# Светлата седмица (Пасха 0..6) е отделен, дневен цикъл — не участва в
# скрития седмичен цикъл изобщо.
BRIGHT_WEEK_DAILY = [0, 2, 3, 4, 5, 6, 8]  # offset 0..6 спрямо Пасха


def _underlying_tone(date: datetime.date) -> int:
    """Скритият седмичен глас (1..8), без изключенията по-долу.

    ДВА нарочни рестарта на 1 във всеки Пасхален цикъл, не един:
    Митар и Фарисей (Пасха-70, откъдето Постният триод влиза в употреба —
    потвърдено от потребителя И от самите данни: непрекъснато броене само
    от Антипасха дава грешен резултат тук) и Томина неделя (Пасха+7)."""
    p = governing_pascha(date)
    offset = (date - p).days
    if 0 <= offset <= 6:
        return BRIGHT_WEEK_DAILY[offset]
    # Неделята, от която тръгва ТЕКУЩАТА седмица (Нед..Съб) на този ден.
    days_since_sunday = (date.weekday() + 1) % 7  # неделя=0
    sunday_offset = offset - days_since_sunday
    anchor = 7 if sunday_offset >= 7 else -70
    weeks = (sunday_offset - anchor) // 7
    return (weeks % 8) + 1


# НЕ всеки rank=1 (Бдение на голям празник) гаси гласа — проверено по
# ЦЯЛАТА 2026: чисто Богородичните измежду тях (Сретение, Успение,
# Рождество Богородично, Въведение) и Обрезание Господне НЕ гасят,
# останалите осем Господски — да. Точен списък, не категория.
LORDLY_FIXED = [  # (месец, ден) църковно
    (1, 6),    # Богоявление
    (3, 25),   # Благовещение
    (8, 6),    # Преображение
    (9, 14),   # Въздвижение
    (12, 25),  # Рождество Христово
]
LORDLY_PASCHA_OFFSETS = [0, 39, 49]  # Пасха, Възнесение, Петдесетница


def is_lordly_feast(date: datetime.date, old_style: bool) -> bool:
    p = governing_pascha(date)
    if (date - p).days in LORDLY_PASCHA_OFFSETS:
        return True
    # Рождество (25.XII църковно) пада в ЯНУАРИ граждански при стар стил —
    # различна година от date.year, затова проверяваме и година-1/+1,
    # както anchor_qualifier по-горе.
    return any(
        civil_from_church(y, m, d, old_style) == date
        for m, d in LORDLY_FIXED
        for y in (date.year - 1, date.year, date.year + 1))


def tone(date: datetime.date, old_style: bool = True) -> int:
    p = governing_pascha(date)
    offset = (date - p).days
    if -6 <= offset <= -1:  # Страстна седмица, цялата
        return 0
    if offset == -7:  # Цветница — rank=2, не 1, но пак гаси само деня
        return 0
    if is_lordly_feast(date, old_style):
        return 0
    if date.weekday() == 6:
        q = anchor_qualifier(date, old_style)
        if q in ('Неделя преди Богоявление', 'Неделя след Богоявление'):
            return 0
    return _underlying_tone(date)


def year_range(year: int, old_style: bool) -> tuple[datetime.date, datetime.date]:
    """Гражданските граници на църковната [year] (1 януари - 31 декември
    църковно) — същия обхват, който покрива и calendar_old.db."""
    start = civil_from_church(year, 1, 1, old_style)
    end = civil_from_church(year, 12, 31, old_style)
    return start, end


def generate_year(year: int, old_style: bool):
    """Генерира calendar_days/weeks/sundays за ЦЯЛАТА църковна [year].

    Връща (calendar_days_rows, weeks_rows, sundays_rows):
      calendar_days_rows: (date, tone, week_id, sunday_id) — fast_period/
        fast_type НЕ са тук, те са отделен, все още неизграден проход.
      weeks_rows / sundays_rows: (id, name, tone) — tone е СКРИТИЯТ,
        непрекъснат (без изключенията, виж _underlying_tone) — точно
        конвенцията в calendar_old.db (седмица/неделя пази истинската
        позиция в цикъла, дори когато calendar_days.tone показва 0).
    """
    start, end = year_range(year, old_style)
    calendar_days_rows = []
    weeks_rows, sundays_rows = [], []
    cur_week_id = None
    d = start
    while d <= end:
        week_name, sunday_name = position(d, old_style)
        t = tone(d, old_style)
        week_id = sunday_id = None
        # is not None, не истинностна проверка: Пасха носи sunday_name=''
        # (празен, но НАЛИЧЕН ред — виж NAMED_SUNDAYS[0]) — точно както в
        # изходната база.
        if d.weekday() == 6:  # неделя
            if sunday_name is not None:
                sundays_rows.append((len(sundays_rows) + 1, sunday_name,
                                      _underlying_tone(d)))
                sunday_id = len(sundays_rows)
        else:
            if d.weekday() == 0 or cur_week_id is None:  # понеделник — нова седмица
                if week_name is not None:
                    weeks_rows.append((len(weeks_rows) + 1, week_name,
                                        _underlying_tone(d)))
                    cur_week_id = len(weeks_rows)
                else:
                    cur_week_id = None
            week_id = cur_week_id
        calendar_days_rows.append((d.isoformat(), t, week_id, sunday_id))
        d += datetime.timedelta(days=1)
    return calendar_days_rows, weeks_rows, sundays_rows
