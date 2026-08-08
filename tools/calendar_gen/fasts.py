"""fast_period и fast_type за calendar_days — пренесено от
lib/fasts_screen.dart (fast_period) + Указания за постите.txt (fast_type).

fast_period: 0=Блажи се, 1=Постен ден (сряда/петък извън поста),
             2=Велик пост, 3=Петров пост, 4=Богородичен(Успенски) пост,
             5=Рождественски пост

fast_type:   0=(без указания), 1=без месо, 2=риба, 3=хайвер, 4=олио,
             5=олио след вечерня, 6=без олио, 7=сухоядение (НЕ се ползва —
             навсякъде в изходния текст "сухоядение" се третира като 6),
             8=хляб/смокини/вино, 9=пълно въздържание
"""
import datetime

from paschalion import civil_from_church, pascha_civil

# ── fast_period ──────────────────────────────────────────────────────────

# Петровден — 29 юни църковно.
def _petrovden(year: int, old_style: bool) -> datetime.date:
    return civil_from_church(year, 6, 29, old_style)


def petrov_range(year: int, old_style: bool):
    """(start, end) на Петровия пост, или None ако е нулев/отрицателен —
    при късна Пасха. Започва в понеделника след Неделя на всички светии
    (Пасха+57), свършва в деня преди Петровден."""
    start = pascha_civil(year) + datetime.timedelta(days=57)
    end = _petrovden(year, old_style) - datetime.timedelta(days=1)
    if end < start:
        return None
    return start, end


def fast_period(date: datetime.date, year: int, old_style: bool) -> int:
    p = pascha_civil(year)

    # ── Свободни седмици (проверяват се ПЪРВИ — имат превес над всичко) ──
    free_ranges = [
        (civil_from_church(year - 1, 12, 25, old_style),
         civil_from_church(year, 1, 4, old_style)),
        (p + datetime.timedelta(days=-69), p + datetime.timedelta(days=-63)),
        (p + datetime.timedelta(days=-55), p + datetime.timedelta(days=-49)),
        (p + datetime.timedelta(days=1), p + datetime.timedelta(days=7)),
        (p + datetime.timedelta(days=50), p + datetime.timedelta(days=56)),
    ]
    for start, end in free_ranges:
        if start <= date <= end:
            return 0

    # ── Четирите многодневни поста ──
    if p + datetime.timedelta(days=-48) <= date <= p + datetime.timedelta(days=-1):
        return 2
    pr = petrov_range(year, old_style)
    if pr and pr[0] <= date <= pr[1]:
        return 3
    if civil_from_church(year, 8, 1, old_style) <= date <= civil_from_church(year, 8, 14, old_style):
        return 4
    if civil_from_church(year, 11, 15, old_style) <= date <= civil_from_church(year, 12, 24, old_style):
        return 5

    # ── Еднодневни пости (виж _singleDayFasts в fasts_screen.dart) ──
    single_day = [
        (1, 5),   # Навечерие на Богоявление
        (8, 29),  # Отсичане главата на св. Йоан Предтеча
        (9, 14),  # Въздвижение
    ]
    for m, dd in single_day:
        if civil_from_church(year, m, dd, old_style) == date:
            return 1

    # ── Обикновен постен ден (сряда/петък) ──
    if date.weekday() in (2, 4):  # сряда=2, петък=4
        return 1
    return 0


# ── fast_type ────────────────────────────────────────────────────────────
#
# Три слоя, всеки следващ има превес:
#   1) базов тип по (период, ден от седмицата)
#   2) фиксирани именувани дни (само в рамките на Велики пост/Рождественски)
#   3) омекотяване по светия (ECUMENICAL/BG, бдение/полиелей/славословие) —
#      само върху ден, който вече има предвиден пост; никога не създава
#      пост от нищото.
#
# Кодове (виж fast_types в базата): 2=риба 3=хайвер 4=олио 6=без олио
# 8=хляб/смокини/вино 9=пълно въздържание

_WD = {'mon': 0, 'tue': 1, 'wed': 2, 'thu': 3, 'fri': 4, 'sat': 5, 'sun': 6}


def _base_type(date: datetime.date, year: int, weekday: int, period: int) -> int:
    """Слой 1 — виж таблицата в диалога с потребителя."""
    if period == 2:  # Велик пост
        return 4 if weekday in (_WD['sat'], _WD['sun']) else 6
    if period == 3:  # Петров — вт/чет позволяват хайвер, не само олио
        if weekday in (_WD['sat'], _WD['sun']):
            return 2
        if weekday in (_WD['tue'], _WD['thu']):
            return 3
        return 6  # пон/сряда/пет
    if period == 5:  # Рождественски — вт/чет хайвер, също като Петров
        if weekday in (_WD['sat'], _WD['sun']):
            return 2
        if weekday in (_WD['tue'], _WD['thu']):
            return 3
        return 6  # пон/сряда/пет
    if period == 4:  # Успенски — Типиконът не споменава вт/чет отделно;
        # третираме ги като делник (без олио), а не като вт/чет на
        # Петров/Рождественски — постът е сред най-строгите, само съб/нед
        # получават олио. Ако това се окаже грешно, ще го коригираме.
        return 4 if weekday in (_WD['sat'], _WD['sun']) else 6
    if period == 1:  # обикновена сряда/петък извън поста
        # От Томина неделя (Пасха+7) до Петдесетница (Пасха+49) базата е
        # олио, не без олио — по-лек период (Периода от Томина неделя до
        # Петдесетница в текста).
        offset = (date - pascha_civil(year)).days
        if 7 <= offset <= 49:
            return 4
        return 6
    return 0  # период 0 — блажи се


def _base_key(date: datetime.date, year: int, weekday: int, period: int) -> str:
    """Ключът на Слой 1 — паралелен на _base_type, виж него за смисъла на
    всеки клон."""
    if period == 2:
        return 'lent_weekend' if weekday in (_WD['sat'], _WD['sun']) else 'lent_weekday'
    if period == 3:
        if weekday in (_WD['sat'], _WD['sun']):
            return 'petrov_weekend'
        if weekday in (_WD['tue'], _WD['thu']):
            return 'petrov_tue_thu'
        return 'petrov_weekday'
    if period == 5:
        if weekday in (_WD['sat'], _WD['sun']):
            return 'nativity_weekend'
        if weekday in (_WD['tue'], _WD['thu']):
            return 'nativity_tue_thu'
        return 'nativity_weekday'
    if period == 4:
        return 'dormition_weekend' if weekday in (_WD['sat'], _WD['sun']) else 'dormition_weekday'
    if period == 1:
        offset = (date - pascha_civil(year)).days
        if 7 <= offset <= 49:
            return 'antipascha_pentecost'
        return 'ordinary_weekday'
    return 'free'


def _fixed_day_detail(date: datetime.date, year: int, old_style: bool,
                       period: int) -> tuple[int, str] | None:
    """Слой 2 — именувани дни с точно предписан тип, независимо от Слой 1.
    Връща (type, key) или None ако денят не е сред тях (тогава важи Слой
    1 + Слой 3). `key` е стабилен низ, идентифициращ ТОЧНО кое правило от
    Устава определи резултата — служи за външен ключ в fast_explanations
    (вместо да се гадае по (period,type), които могат да съвпаднат за
    няколко различни правила, напр. четири различни поводи за "Велик пост
    с олио")."""
    p = pascha_civil(year)
    offset = (date - p).days

    FIXED_PASCHA_OFFSETS = {
        -48: (9, 'full_abstinence'),      # 1-ви ден на Велики пост
        -43: (4, 'lent_weekend'),         # Тодорова събота — вече е събота
        -17: (4, 'lent_week5_thursday'),  # четвъртък на 5-та седм. (Мариино стоене)
        -8: (3, 'lazarus_saturday'),      # Лазарова събота — хайвер
        -7: (2, 'lent_fish'),             # Цветница — риба
        -3: (4, 'lent_holy_thursday'),    # Велики четвъртък
        -2: (9, 'full_abstinence'),       # Велики петък — пълно въздържание
        -1: (8, 'holy_saturday'),         # Велика събота — хляб/зеленчуци/вино
    }
    if offset in FIXED_PASCHA_OFFSETS:
        return FIXED_PASCHA_OFFSETS[offset]

    # Благовещение (25.III църковно): риба, ОСВЕН ако падне в Страстната
    # седмица (тогава маслo — потвърдено от бележката за 2026 в текста).
    if civil_from_church(year, 3, 25, old_style) == date:
        return (4, 'annunciation_holy_week') if -6 <= offset <= -1 else (2, 'lent_fish')

    # Предпразненство на Благовещение (24.III църковно, навечерието на
    # празника) — олио, ако предпразненството е ПРЕДИ Страстната седмица
    # (до Лазарева събота включително). Ако попадне В Страстната седмица,
    # постът НЕ се облекчава — нищо не връщаме тук, пада към обичайния тип
    # за деня (Велики понеделник/вторник/сряда, вече покрити по-горе или
    # от общото правило на Велики пост).
    if period == 2 and civil_from_church(year, 3, 24, old_style) == date:
        if not (-6 <= offset <= -1):
            return (4, 'annunciation_forefeast')

    # Обретение главата на Йоан Предтеча (24.II църковно) и Св. 40 мчч.
    # Севастийски (9.III църковно) — олио, само ако падат В РАМКИТЕ на
    # Велики пост тази година (иначе Слой 1/3 не важат тук изобщо). Ако
    # денят се падне в събота/неделя, общото правило за уикенда вече дава
    # същото олио — светията тогава практически не променя нищо, затова
    # ключът остава 'lent_weekend', а не се приписва на него.
    if period == 2 and civil_from_church(year, 2, 24, old_style) == date:
        return (4, 'lent_weekend') if date.weekday() in (5, 6) else (4, 'lent_obretenie_40mch')
    if period == 2 and civil_from_church(year, 3, 9, old_style) == date:
        return (4, 'lent_weekend') if date.weekday() in (5, 6) else (4, 'lent_obretenie_40mch')

    # Въздвижение и Преображение са Господски празници, но НЕ се блажат —
    # и двата остават постни дори в самия си ден (различно от другите 6
    # Господски). Фиксирано тук, за да не влизат в общото "Господски ->
    # блажи се" правило по-долу.
    if civil_from_church(year, 9, 14, old_style) == date:
        return (4, 'exaltation_cross')  # Въздвижение — олио
    if civil_from_church(year, 8, 6, old_style) == date:
        return (2, 'transfiguration')  # Преображение — риба (в Успенския пост)

    # Навечерие Рождество Христово (24.XII църковно) — олио след вечерня,
    # ЗАВИНАГИ същия тип, без значение от деня на седмицата.
    if civil_from_church(year, 12, 24, old_style) == date:
        return (5, 'nativity_eve')

    # Денят преди Навечерието (23.XII църковно) — изрично указание в
    # Типикона: сухоядение (7), по-строго от общото "без олио" на
    # предпразненството. Единственото място, където 7 не се заменя с 6.
    if civil_from_church(year, 12, 23, old_style) == date:
        return (7, 'day_before_nativity_eve')

    return None


# ── Слой 3: омекотяване по светия ──────────────────────────────────────
#
# `saints_today` е списък от (rank, group_code) за деня — ИЗВЕЖДА СЕ ОТВЪН
# (от прясно генерираните saints за целевата година в build.py, не се пита
# база директно тук), за да е функцията чиста и преизползваема.
#
# Рангове от saint_ranks, отброяващи като "празник" за целите на постите:
# 1=Бдение на голям празник, 2=Бдение, 3=Полиелей, 4=Славословна.
FEAST_RANKS = {1, 2, 3, 4}
FEAST_GROUPS = {'ECUMENICAL', 'BG'}

# Велики дати в Рождественския пост (църковно) — потвърдено в текста, че
# ЧИСЛАТА остават същите и по нов стил (само гражданското им число се
# мести, не самите дати).
NATIVITY_FAST_GREAT_DATES = {
    (11, 16), (11, 25), (11, 30),
    (12, 4), (12, 5), (12, 6), (12, 9), (12, 17), (12, 20),
}

# Осемте Господски празника, при които постът се вдига НАПЪЛНО — но само
# ИЗВЪН Велики пост (вътре в него, Слой 2 решава всичко изрично именувано;
# извън изрично именуваните дни, Великият пост никога не се "блажи").
LORDLY_FIXED = [(1, 6), (3, 25), (8, 6), (9, 14), (12, 25)]
LORDLY_PASCHA_OFFSETS = {0, 39, 49}


def _has_feast(saints_today: list[tuple[int, str]]) -> bool:
    return any(rank in FEAST_RANKS and group in FEAST_GROUPS
               for rank, group in saints_today)


def _is_lordly(date: datetime.date, year: int, old_style: bool) -> bool:
    p = pascha_civil(year)
    if (date - p).days in LORDLY_PASCHA_OFFSETS:
        return True
    return any(civil_from_church(y, m, d, old_style) == date
               for m, d in LORDLY_FIXED
               for y in (date.year - 1, date.year, date.year + 1))


def _is_theotokos(saints_today: list[tuple[int, str]]) -> bool:
    # Богородичен празник = rank=1 запис, но не е сред 8-те Господски —
    # различаването реално е чрез самата дата, не чрез ранга (виж tone()
    # в weeks_sundays.py — там сме извели точно кои rank=1 НЕ гасят гласа,
    # а именно Богородичните). Преизползваме същия принцип: rank=1 запис,
    # който НЕ е в LORDLY списъка за деня.
    return any(rank == 1 for rank, _ in saints_today)


def _period_relax_key(period: int) -> str:
    return {3: 'petrov_relax', 4: 'dormition_relax', 5: 'nativity_relax'}[period]


def _fast_type_detail(date: datetime.date, year: int, old_style: bool,
                       period: int, saints_today: list[tuple[int, str]]
                       ) -> tuple[int, str]:
    """Връща (type, key). `key` е стабилен низ, показващ ТОЧНО кое правило
    от Устава определи резултата — служи за пряк външен ключ в
    fast_explanations.key, вместо (period,type) сами по себе си (които не
    са достатъчни: и четирите повода за "Велик пост с олио" например
    делят едно и също (2,4))."""
    if period == 0:
        # Сирната седмица е особен случай сред петте свободни седмици:
        # НЕ е напълно свободна — забранено е месото, но млечно/яйца са
        # разрешени (тип=1 "без месо"), включително в сряда/петък. Виж
        # реда за нея в Указания за постите.txt.
        p = pascha_civil(year)
        if p + datetime.timedelta(days=-55) <= date <= p + datetime.timedelta(days=-49):
            return 1, 'cheese_week'
        return 0, 'free'  # блажи се — няма какво да омекотяваме

    fixed = _fixed_day_detail(date, year, old_style, period)
    if fixed is not None:
        return fixed  # Слой 2 винаги печели — 1-ва седмица/Страстна не се пипат

    weekday = date.weekday()
    # Господски празник вдига поста напълно — НЕ и през Велики пост, там
    # Слой 2 вече покрива изрично именуваните изключения (Цветница,
    # Благовещение); извън тях Великият пост никога не се "блажи".
    if _is_lordly(date, year, old_style) and period != 2:
        return 0, 'lordly_free'

    base = _base_type(date, year, weekday, period)
    base_key = _base_key(date, year, weekday, period)

    # Предпразненство на Рождество (20-24.XII църковно вкл., до самото
    # Навечерие): рибата и хайверът СПИРАТ, но постът не се усилва отвъд
    # това — просто пада до олио. Не се отнася за 23/24.XII, те вече
    # излязоха с точния си тип през Слой 2 по-горе.
    if period == 5:
        d20 = civil_from_church(year, 12, 20, old_style)
        d22 = civil_from_church(year, 12, 22, old_style)  # 23/24 покрити от Слой 2
        if d20 <= date <= d22 and base in (2, 3):
            base = 4
            base_key = 'nativity_forefeast'

    # Богородичен празник на сряда/петък извън Велики пост — риба, не пълно
    # освобождаване. (Забележка: по-рано тук пишеше `max(base, 2)`, но
    # base никога не е под 2 в тези периоди, значи max() никога не
    # променяше нищо — правилото реално не действаше. Върнато е директно
    # 2, каквото е било намерението според бележката по-горе.)
    if period != 2 and weekday in (_WD['wed'], _WD['fri']) and \
            _is_theotokos(saints_today):
        return 2, 'theotokos_wed_fri'

    if not _has_feast(saints_today):
        return base, base_key

    # ── Има подходящ светия (ECUMENICAL/BG, бдение/полиелей/славословие) ──

    # Велики пост: светия НЕ омекотява — само изрично именуваните дни от
    # Типикона (Слой 2, вече проверен по-горе) правят изключение. Базовият
    # ритъм на седмицата важи непроменен през целия пост.
    if period == 2:
        return base, base_key

    # Рождественски пост, велики дати: вт/чет риба вместо хайвер, пон/сряда/
    # пет олио вместо без олио. НЕ важи в прозореца на предпразненството
    # (base вече е ограничен до максимум олио по-горе — там рибата пак е
    # спряна дори на велика дата).
    if period == 5 and (date.month, date.day) in _nativity_great_dates_this_year(year, old_style):
        if weekday in (_WD['tue'], _WD['thu']):
            # base==4 значи вече сме в прозореца на предпразненството
            # (рибата спряна) — там великата дата не я връща обратно.
            return (4, 'nativity_relax') if base == 4 else (2, 'nativity_great_date_fish')
        if weekday in (_WD['mon'], _WD['wed'], _WD['fri']):
            return 4, 'nativity_relax'
        return base, base_key

    # Петров/Успенски/Рождественски (общо правило): пон/сряда/пет без олио
    # -> олио. Останалите дни (вт/чет с базово олио, съб/нед с базова риба)
    # си остават непроменени — омекотяването няма какво да добави там.
    if period in (3, 4, 5) and weekday in (_WD['mon'], _WD['wed'], _WD['fri']):
        return 4, _period_relax_key(period)

    # Обикновен постен ден (сряда/петък извън поста): без олио -> олио.
    # Ако вече е олио (периода Томина неделя-Петдесетница), няма какво
    # повече да омекоти.
    if period == 1 and base == 6:
        return 4, 'relax_ordinary_wed_fri'

    return base, base_key


def fast_type(date: datetime.date, year: int, old_style: bool,
              period: int, saints_today: list[tuple[int, str]]) -> int:
    return _fast_type_detail(date, year, old_style, period, saints_today)[0]


def fast_explanation_key(date: datetime.date, year: int, old_style: bool,
                          period: int, saints_today: list[tuple[int, str]]) -> str:
    return _fast_type_detail(date, year, old_style, period, saints_today)[1]


def _nativity_great_dates_this_year(year: int, old_style: bool) -> set[tuple[int, int]]:
    """Гражданските (месец,ден) на 'великите дати' от Рождественския пост
    за тази конкретна (година,стил) — числата църковно са фиксирани, но
    гражданското им число зависи от стила."""
    return {
        (d.month, d.day)
        for m, dd in NATIVITY_FAST_GREAT_DATES
        for d in [civil_from_church(year, m, dd, old_style)]
    }
