/// Кои четива се падат на даден ден — по АЛГОРИТЪМ, не от базата.
///
/// ⚠⚠ ЗАЩО. Таблицата `readings` е парсната за ЕДНА църковна година и е
/// ключирана по ГРАЖДАНСКА дата, тъй че не важи за друга година; а в
/// новостилната база е копирана непроменена и неподвижните четива излизат
/// с 13 дни встрани. Изместване НЕ върши работа: на един и същ физически
/// ден двата стила честват РАЗЛИЧНИ светии. (Изрично от потребителя.)
///
/// ⚠ ЧИСТ DART — никакъв Flutter и никаква база, за да се проверява с
/// `dart run` за части от секундата, както [bible_ref.dart].
library;

import 'readings_cycle.dart';

/// Литургичният адрес на деня.
enum ReadingCycle {
  /// Триод — десетте седмици преди Пасха.
  triodion,

  /// Пентикостар — от Пасха до Петдесетница.
  pentecostarion,

  /// Седмиците по Петдесетница.
  afterPentecost,
}

class ReadingAddress {
  final ReadingCycle cycle;
  final int week;
  final int weekday;
  const ReadingAddress(this.cycle, this.week, this.weekday);

  String get key {
    final letter = switch (cycle) {
      ReadingCycle.triodion => 'T',
      ReadingCycle.pentecostarion => 'P',
      ReadingCycle.afterPentecost => 'W',
    };
    return '$letter$week:$weekday';
  }
}

/// Юлианската Пасха за годината, върната като ГРАЖДАНСКА дата.
///
/// ⚠ Пасхалията е обща за двата стила, тъй че тази дата е една и съща и в
/// `calendar_old.db`, и в `calendar_new.db`. Преписана е от
/// [DatabaseHelper.paschaOf], за да остане този файл БЕЗ зависимости —
/// ⚠ променят се ЗАЕДНО.
DateTime paschaOf(int year) {
  final a = year % 4, b = year % 7, c = year % 19;
  final d = (19 * c + 15) % 30;
  final e = (2 * a + 4 * b - d + 34) % 7;
  final month = (d + e + 114) ~/ 31;
  final day = (d + e + 114) % 31 + 1;
  // юлианска → григорианска, през юлианския ден (без твърдо „+13", за да не
  // се счупи през 2100 г., когато разликата става 14 дни)
  final jdn = _julianDayFromJulian(year, month, day);
  return _gregorianFromJulianDay(jdn);
}

int _julianDayFromJulian(int y, int m, int d) {
  final a = (14 - m) ~/ 12;
  final yy = y + 4800 - a;
  final mm = m + 12 * a - 3;
  return d + (153 * mm + 2) ~/ 5 + 365 * yy + yy ~/ 4 - 32083;
}

/// ⚠⚠ ВРЪЩА UTC. Всички сметки тук са с UTC дати — виж [readingAddress].
DateTime _gregorianFromJulianDay(int jdn) {
  final a = jdn + 32044;
  final b = (4 * a + 3) ~/ 146097;
  final c = a - 146097 * b ~/ 4;
  final d = (4 * c + 3) ~/ 1461;
  final e = c - 1461 * d ~/ 4;
  final m = (5 * e + 2) ~/ 153;
  return DateTime.utc(100 * b + d - 4800 + m ~/ 10, m + 3 - 12 * (m ~/ 10),
      e - (153 * m + 2) ~/ 5 + 1);
}

/// Литургичният адрес на гражданска дата.
///
/// ⚠⚠ ТРИОДЪТ ИМА ПРЕВЕС. Последните 70 дни преди Пасха вече не са „по
/// Петдесетница", макар броенето от предната Пасха да продължава — инак
/// излизат 44 седмици, каквито година няма.
ReadingAddress readingAddress(DateTime date) {
  // ⚠⚠ UTC, НЕ МЕСТНО ВРЕМЕ. `difference().inDays` отрязва надолу, а
  // разликата между две МЕСТНИ дати през смяната на лятното часово време е
  // 42 дни и 23 часа — тоест 42, не 43. Така целият Триод излизаше с една
  // седмица напред (28.02.2026 даваше „T5:6" вместо „T4:6") и се
  // показваха четивата на ДРУГА седмица. Хванато от теста срещу базата.
  final d = DateTime.utc(date.year, date.month, date.day);
  final thisPascha = paschaOf(d.year);
  final next = d.isAfter(thisPascha) ? paschaOf(d.year + 1) : thisPascha;
  final until = next.difference(d).inDays;
  if (until > 0 && until <= 70) {
    return ReadingAddress(
        ReadingCycle.triodion, (70 - until) ~/ 7 + 1, d.weekday);
  }
  final prev = d.isBefore(thisPascha) ? paschaOf(d.year - 1) : thisPascha;
  final n = d.difference(prev).inDays;
  // ⚠⚠ ПЕТДЕСЕТНИЦА (Пасха+49) Е ПОСЛЕДНИЯТ ДЕН НА ПЕНТИКОСТАРА. Границата
  // беше 48 и денят падаше в „по Петдесетница" — а там Python смята
  // (49−50)//7+1 = 0, докато Dart дава (−1)~/7+1 = 1, защото Dart реже към
  // нулата, а Python надолу. Двете реализации се разминаваха точно на този
  // ден и тестът го хвана.
  if (n <= 49) {
    return ReadingAddress(
        ReadingCycle.pentecostarion, n ~/ 7 + 1, d.weekday);
  }
  // ⚠⚠ ЛИТУРГИЧНОТО НОМЕРИРАНЕ — виж бележката в 12_extract_cycle.py:
  // „Неделя N" е в КРАЯ на „седмица N", тъй че се брои от Пасха+50.
  return ReadingAddress(
      ReadingCycle.afterPentecost, (n - 50) ~/ 7 + 1, d.weekday);
}

/// Гражданската дата на неподвижен празник, според СТИЛА.
///
/// ⚠⚠ ЕДНА ЦЪРКОВНА ДАТА СА ДВА РАЗЛИЧНИ ФИЗИЧЕСКИ ДНИ. Въздвижение е
/// църковна 09-14: по СТАР стил това е гражданска 27 септември, по НОВ —
/// 14 септември. Пасхата пък е една и съща гражданска дата в двата стила.
///
/// ⚠ Оттам следва цялата разлика между стиловете в редовите четива:
/// подвижният кръг е общ, а точката, в която евангелският брояч скача
/// (Неделята по Въздвижение), пада на РАЗЛИЧНА неделя. Затова четивата
/// излизаха верни по стар стил и сбъркани по нов. (Наблюдение на
/// потребителя, 11.09.2026.)
///
/// ⚠ Превръщането минава през юлианския ден, а НЕ през твърдо „+13" —
/// същият довод като при [paschaOf]: през 2100 г. разликата става 14 дни.
DateTime civilDateOfChurch(int year, int month, int day,
    {required bool oldStyle}) {
  if (!oldStyle) return DateTime.utc(year, month, day);
  return _gregorianFromJulianDay(_julianDayFromJulian(year, month, day));
}

/// Първата неделя СЛЕД Въздвижение (църковна 09-14).
///
/// ⚠ Ключовият ден е НЕДЕЛЯТА, не празникът: падне ли Въздвижение в неделя,
/// преступката е чак след седмица (Устав, §1.7).
DateTime sundayAfterExaltation(int year, {required bool oldStyle}) {
  final feast = civilDateOfChurch(year, 9, 14, oldStyle: oldStyle);
  final ahead = (7 - feast.weekday) % 7;
  return feast.add(Duration(days: ahead == 0 ? 7 : ahead));
}

/// Номерът на седмицата за ЕВАНГЕЛИЕТО — може да се различава от този на
/// апостола.
///
/// ⚠⚠ ТОВА Е ВЪЗДВИЖЕНСКАТА ПРЕСТУПКА/ОТСТЪПКА (Устав, §1.7):
///
///   „След Неделя по Въздвижение започва редът от Лука: веднага се четат
///    редовите евангелия на 18-та седмица (в понеделник — Лк. зач. 10), и
///    нататък по ред" — НЕЗАВИСИМО какъв номер има тази неделя.
///
/// Апостолът върви непрекъснато; оттам и въпросът, който самият Устав дава
/// за пример: „защо в календара пише 16-та седмица, а евангелията са на
/// 18-та?"
///
/// ⚠ Пасха между 31.III и 6.IV → двете съвпадат и преступка няма. По-късна
/// Пасха → седмици се ПРОПУСКАТ (най-много три). По-ранна → седмици се
/// ПОВТАРЯТ. И трите случая излизат сами от тази сметка.
/// Докъде стига РЕДОВИЯТ кръг преди Въздвижение: 17 седмици.
///
/// ⚠ Делничните четива на тези седмици са от Матей (1–11) и от Марк
/// (12–17) — мерено върху данните за 2026 г.
const int kCycleWeeksBeforeExaltation = 17;

/// Колко седмици делнични четива дава МАТЕЙ.
///
/// ⚠⚠ ОТ ТОЗИ БЛОК СЕ ПОПЪЛВА ОТСТЪПКАТА, а не от края на целия кръг.
/// Наблюдение от календара на Oleksandr Kotyuk за 2026 г., потвърдено и от
/// втори календар: отстъпката от една седмица повтаря седмица **11** —
/// последната Матеева, — а не седмица 17 (която е от Марк).
///
/// ⚠ Уставът (§1.7) предписва другото: „на 18-й и 19-й седмицах повторить
/// зачала 16-й и 17-й седмиц". Двете правила са с ЕДНА И СЪЩА форма —
/// „повтори последните N седмици от блока, по ред" — и се различават само
/// по това кой блок броят за свой. Следваме реално ползвания календар.
const int kMatthewWeekdayWeeks = 11;

/// Номерът на седмицата за ЕВАНГЕЛИЕТО — може да се различава от този на
/// апостола.
///
/// ⚠⚠ ВЪЗДВИЖЕНСКАТА ПРЕСТУПКА/ОТСТЪПКА (Устав, §1.7):
///
///   „След Неделя по Въздвижение започва редът от Лука: веднага се четат
///    редовите евангелия на 18-та седмица (в понеделник — Лк. зач. 10), и
///    нататък по ред" — НЕЗАВИСИМО какъв номер има тази неделя.
///
/// Апостолът върви непрекъснато; оттам и въпросът, който самият Устав дава
/// за пример: „защо в календара пише 16-та седмица, а евангелията са на
/// 18-та?"
///
/// Сверено срещу календара на Kotyuk:
///
///   2024 (преступка 3 седм.)  23–28.IX → седмица 14 ✓
///                             30.IX–5.X → Лк. 10–15, тоест 18 ✓
///   2026 (отстъпка 1 седм.)   28.IX–3.X → Мат. 94–100, тоест 11 ✓
int gospelWeekFor(DateTime date, int apostleWeek, {required bool oldStyle}) {
  final d = DateTime.utc(date.year, date.month, date.day);
  // ⚠⚠ НЕДЕЛЯТА ОТ ТАЗИ ЦЪРКОВНА ГОДИНА, не от гражданската. Църковната
  // година тече от Пасха до Пасха, тъй че за ден през януари меродавна е
  // неделята от ПРЕДНАТА есен. Без това всеки януарски ден падаше в клона
  // „преди Въздвижение" с номер над 30 и се броеше за отстъпка.
  // ⚠⚠ НЕДЕЛИТЕ НЕ УЧАСТВАТ В НИТО ЕДНОТО. Неделният кръг е отделен (32
  // недели) и броячът му тече НЕПРЕКЪСНАТО през целия скок — проверено
  // срещу azbyka.ru за 2026 г.: 14, 15, 16, 17, 18, 19, 20 без прекъсване,
  // докато седмичният скача. Уставът казва същото: пропускат се или се
  // повтарят „седмици", а „в воскресные дни отступки нет".
  if (d.weekday == DateTime.sunday) return apostleWeek;

  final paschaYear = d.isBefore(paschaOf(d.year)) ? d.year - 1 : d.year;
  final sunday = sundayAfterExaltation(paschaYear, oldStyle: oldStyle);

  if (d.isAfter(sunday)) {
    final since = d.difference(sunday).inDays;
    return kExaltationWeek + (since - 1) ~/ 7;
  }
  if (apostleWeek <= kCycleWeeksBeforeExaltation) return apostleWeek;

  // ⚠ ОТСТЪПКА: Неделята по Въздвижение идва СЛЕД Неделя 17, тъй че между
  // тях остават седмици без свои четива. Попълват се с последните N
  // седмици на Матеевия блок, ПО РЕД — при N = 1 това е седмица 11.
  //
  // ⚠⚠ N = 2 Е ИЗВЕДЕНО ОТ ФОРМАТА, НЕ НАБЛЮДАВАНО: дава 10 и 11.
  // Другата възможност е седмица 11 да се повтори два пъти, но такъв вид
  // няма прецедент в уставната формулировка. Случаят е рядък — при стар
  // стил следващият е чак **2037** (после 2048), тъй че има време да се
  // провери по календарче за онази година, преди да потрябва.
  final sundayWeek = readingAddress(sunday).week;
  final extra = sundayWeek - kCycleWeeksBeforeExaltation;
  final step = apostleWeek - kCycleWeeksBeforeExaltation;
  return kMatthewWeekdayWeeks - extra + step;
}

/// Последната седмица от редовия кръг за ДЕЛНИЦИТЕ и СЪБОТИТЕ.
///
/// ⚠⚠ **34, НЕ 33.** Уставът говори за „33 седмици", но реално ползваният
/// календар брои назад от 34 — сверено с Kotyuk за 2024 (прозорец 5
/// седмици): първата седмица дава Мк. 33, 34, 36, 39, 41 и събота Лк. 74,
/// а това е ТОЧНО W30 в нашия указател. 34 − 5 + 1 = 30 ✓
///
/// ⚠ Указателят го потвърждава и отвътре: Лукините делнични зачала свършват
/// на W29 (Лк. 102–108), а от W30 поема Марк — тоест материал за 34 седмици
/// наистина има.
const int kLastCycleWeek = 34;

/// Последната НЕДЕЛЯ от редовия кръг — Закхей (Лк. зач. 94).
///
/// ⚠ Уставът е изричен: „при чтении во время отступки зачала располагают
/// таким образом, чтобы пред Неделей о мытаре и фарисее читалось непременно
/// Евангелие о Закхее (Лк. зач. 94), рядовое чтение Недели 32-й".
const int kZacchaeusSunday = 32;

/// Неделята, от която се брои зимната отстъпка, или `null` ако денят не е в
/// нейния прозорец.
///
/// ⚠⚠ ТРИ СЛУЧАЯ според деня, в който пада Богоявление (Устав, §1.7). И в
/// трите отправната точка е НЕДЕЛЯ, а редът тръгва от понеделника подир нея
/// (при случай 2 — от вторник, защото понеделникът Е Богоявление и редовите
/// зачала се отменят):
///
///   Богоявление вт–сб  → Неделята ПО Богоявление
///   Богоявление пон.   → Неделята ПРЕД Богоявление
///   Богоявление нед.   → самото Богоявление
DateTime? winterReferenceSunday(int year, {required bool oldStyle}) {
  final feast = civilDateOfChurch(year, 1, 6, oldStyle: oldStyle);
  if (feast.weekday == DateTime.sunday) return feast;
  if (feast.weekday == DateTime.monday) {
    return feast.subtract(const Duration(days: 1));
  }
  final ahead = (7 - feast.weekday) % 7;
  return feast.add(Duration(days: ahead == 0 ? 7 : ahead));
}

/// Неделните евангелия по реда на неделите след Петдесетница — 13-та до
/// 32-ра. Записът е като в [kReadingsGospel].
const Map<int, String> kSundayGospels = {
  13: 'Мат. 87 (21:33-42)', 14: 'Мат. 89 (22:1-14)',
  15: 'Мат. 92 (22:35-46)', 16: 'Мат. 105 (25:14-30)',
  17: 'Мат. 62 (15:21-28)', 18: 'Лк. 17 (5:1-11)', 19: 'Лк. 26 (6:31-36)',
  20: 'Лк. 30 (7:11-16)', 21: 'Лк. 35 (8:5-15)', 22: 'Лк. 83 (16:19-31)',
  23: 'Лк. 38 (8:26-39)', 24: 'Лк. 39 (8:41-56)', 25: 'Лк. 53 (10:25-37)',
  26: 'Лк. 66 (12:16-21)', 27: 'Лк. 71 (13:10-17)', 28: 'Лк. 76 (14:16-24)',
  29: 'Лк. 85 (17:12-19)', 30: 'Лк. 91 (18:18-27)', 31: 'Лк. 93 (18:35-43)',
  32: 'Лк. 94 (19:1-10)',
};

/// Кое НЕДЕЛНО евангелие се чете в неделя от „Неделя след Въздвижение" до
/// неделята на Закхей. `null` = денят не е такава неделя (важи таблицата);
/// `number == null` = редово неделно евангелие днес НЯМА (четат се само
/// тези на празника).
///
/// ⚠⚠ ДОТУК НЕДЕЛИТЕ СЕ ВЗИМАХА ОТ ТАБЛИЦАТА ПО НОМЕРА НА НЕДЕЛЯТА, а тя е
/// наредена по 2026 г. стар стил. През 2025 г. по стар стил това даваше
/// Лк. 5:1-11 на 19.X вместо на 5.X, а Мат. 62 (хананейката) и Лк. 94
/// (Закхей) не излизаха НИКОГА. (Сверено от потребителя с руско календарче,
/// 30.09.2026.)
///
/// ПРАВИЛАТА — изведени от ТРИ независими извора и сверени с всеки:
/// календарчето за 2025 г. (5.X Лк. 17, 19.X Лк. 30), данните за 2026 г.
/// (`test/fixtures/readings_2026.json`) и календара на Kotyuk за зимата на
/// 2024 г. (28.I Лк. 91, 4.II Лк. 93, 11.II Мат. 62, 18.II Лк. 94):
///
///   ЕСЕН — напред. Неделята след Въздвижение взима от таблицата (както
///   досега). Следващата е 18-та (Лк. 5:1-11), и нататък по ред, НЕЗАВИСИМО
///   от номера на неделята след Петдесетница.
///   • 28-то (Лк. 76) е на Неделята на св. Праотци (11–17.XII ц.). Падне ли
///     се редът на 28 в неделя ПРЕДИ нея, там се чете 30-о; в Праотците —
///     28 и 29 заедно; 30 после се прескача. (2026: 20.XII Лк. 91, 27.XII
///     Лк. 85 + Лк. 76, 10.I Лк. 93.)
///   • Неделята на св. Отци (18–24.XII ц.) и самото Рождество — само
///     празничното, редът не брои. Неделята след Рождество чете и редово.
///   ЗИМА — назад от Закхей, в неделите след отправната неделя около
///   Богоявление ([winterReferenceSunday]): последната е 32 (Закхей), преди
///   нея 17 (хананейката), после 31, 30, 29… — при по-малко недели само
///   32, 31. Какво е прочетено наесен, не се гледа (повторенията са законни).
({int? number})? sundayGospelAfterExaltation(DateTime date,
    {required bool oldStyle}) {
  final d = DateTime.utc(date.year, date.month, date.day);
  if (d.weekday != DateTime.sunday) return null;
  final paschaYear = d.isBefore(paschaOf(d.year)) ? d.year - 1 : d.year;
  final sae = sundayAfterExaltation(paschaYear, oldStyle: oldStyle);
  final zacchaeus =
      publicanSunday(paschaYear + 1).subtract(const Duration(days: 7));
  if (!d.isAfter(sae) || d.isAfter(zacchaeus)) return null;

  // ── ЗИМА: назад от Закхей ────────────────────────────────────────────
  final ref = winterReferenceSunday(paschaYear + 1, oldStyle: oldStyle);
  if (ref != null && d.isAfter(ref)) {
    final total = zacchaeus.difference(ref).inDays ~/ 7;
    final back = zacchaeus.difference(d).inDays ~/ 7; // 0 = самият Закхей
    final seq = total >= 3
        ? [32, 17, for (var k = 31; k >= 18; k--) k]
        : [for (var k = 32; k >= 18; k--) k];
    return (number: back < seq.length ? seq[back] : null);
  }
  if (d == zacchaeus) return (number: kZacchaeusSunday);

  // ── ЕСЕН: напред ─────────────────────────────────────────────────────
  // Църковната дата: при нов стил тя Е гражданската; при стар — 13 дни по-рано
  // (1900–2099). ⚠ Тук, а не през style_dates.dart: файлът е чист Dart.
  (int, int) church(DateTime s) {
    final c = oldStyle ? s.subtract(const Duration(days: 13)) : s;
    return (c.month, c.day);
  }

  bool isForefathers(DateTime s) {
    final (m, dd) = church(s);
    return m == 12 && dd >= 11 && dd <= 17;
  }

  // Праотците от тази есен — за да се знае дали една неделя е ПРЕДИ тях.
  var forefathers = sae;
  while (!isForefathers(forefathers)) {
    forefathers = forefathers.add(const Duration(days: 7));
  }

  var next = kExaltationWeek;
  var used30 = false, used28 = false;
  int? result;
  for (var s = sae.add(const Duration(days: 7));
      !s.isAfter(d);
      s = s.add(const Duration(days: 7))) {
    final (m, dd) = church(s);
    if (m == 12 && dd >= 18 && dd <= 25) {
      result = null; // св. Отци / Рождество — редът не брои
      continue;
    }
    while ((next == 28 && used28) || (next == 30 && used30)) {
      next++;
    }
    if (isForefathers(s)) {
      // Лк. 76 е евангелието на самия празник; редовото е поредното.
      used28 = true;
      result = next++;
    } else if (next == 28 && s.isBefore(forefathers)) {
      // 28 се пази за Праотците — тук 30, и редът продължава с 29.
      used28 = used30 = true;
      result = 30;
      next = 29;
    } else {
      result = next++;
    }
  }
  if (result != null && result > 31) result = null;
  return (number: result);
}

/// Неделята на митаря и фарисея — началото на Триода.
DateTime publicanSunday(int year) =>
    paschaOf(year).subtract(const Duration(days: 70));

/// Номерът на седмицата при ЗИМНАТА (кръщенска) отстъпка, или `null` ако
/// денят е извън нейния прозорец.
///
/// ⚠⚠ РЕДОВИТЕ ЗАЧАЛА СВЪРШВАТ ПРЕДИ НЕДЕЛЯ ПО БОГОЯВЛЕНИЕ. Кръгът дава 33
/// седмици, а между Богоявление и Неделя на митаря остават до пет. Уставът
/// (Типикон, 7 януари, 6-е „зри") предписва да се брои НАЗАД от 33-та
/// според разстоянието: при прозорец от четири седмици се взимат 30, 31, 32
/// и 33.
///
/// ⚠⚠ ВГРАДЕНО ПО УСТАВА, НО ОЩЕ НЕ СВЕРЕНО С КАЛЕНДАРЧЕ. Данните ни свършват
/// на 13.I.2027, тоест ПРЕДИ Богоявление, тъй че този прозорец не се пада
/// в покрития цикъл и тестът не може да го провери. Проверява се лесно:
/// 2024 дава прозорец от ПЕТ седмици (максимумът), 2025 — случай „неделя",
/// 2026 — случай „понеделник".
int? winterWeekFor(DateTime date, {required bool oldStyle}) {
  final d = DateTime.utc(date.year, date.month, date.day);
  final ref = winterReferenceSunday(d.year, oldStyle: oldStyle);
  if (ref == null) return null;
  final end = publicanSunday(d.year);
  if (!d.isAfter(ref) || !d.isBefore(end)) return null;
  final weeks = end.difference(ref).inDays ~/ 7;
  if (weeks <= 0) return null;
  final step = (d.difference(ref).inDays - 1) ~/ 7 + 1;
  // ⚠⚠ НЕДЕЛИТЕ СА С ЕДНА ПО-МАЛКО ОТ СЕДМИЦИТЕ. Между отправната неделя и
  // Неделята на митаря се падат `weeks − 1` недели — последната от тях е
  // тази ПРЕДИ митаря, а самият митар вече е Триод. Сверено с календара на
  // Kotyuk за 2024: прозорец 5 седмици, а недели са четири (28.I, 4.II,
  // 11.II, 18.II).
  final total = d.weekday == DateTime.sunday ? weeks - 1 : weeks;
  if (step < 1 || step > total) return null;
  // ⚠ Неделите свършват на Закхей (32), делниците — на 33. Уставът казва, че
  // в неделите отстъпка НЯМА: там се четат пропуснатите недели, подредени
  // тъй, че последната преди митаря да е непременно Закхей. Броенето назад
  // от 32 удовлетворява точно това условие.
  // ⚠ Неделите свършват на Закхей (32) — Уставът е изричен: „пред Неделей о
  // мытаре и фарисее читалось непременно Евангелие о Закхее (Лк. зач. 94),
  // рядовое чтение Недели 32-й". Сверено с Kotyuk 2024: 18.II = Лк. 94 ✓,
  // а първата неделя 28.I = Лк. 91, което при нас стои на W29:7 ✓ —
  // тоест редицата е 29, 30, 31, 32.
  final last = d.weekday == DateTime.sunday ? kZacchaeusSunday : kLastCycleWeek;
  return last - total + step;
}

/// Празниците, около които има ЗАКОТВЕНИ съботи и недели, с църковната им
/// дата.
///
/// ⚠ Църковна, не гражданска: тя е обща за двата стила, а гражданската се
/// смята от нея по стила (виж [civilDateOfChurch]).
const kAnchorFeasts = ['09-14', '12-25', '01-06'];

/// Закотвените четива за този ден, ако е събота или неделя до празник.
///
/// ⚠⚠ ТЕ НЕ СЛЕДВАТ СЕДМИЧНИЯ КРЪГ. „Събота по Въздвижение" се мести с деня
/// от седмицата на празника — тази година е 3 октомври, догодина друга дата.
/// (Посочено от потребителя, 11.09.2026: на 3.X.2026 евангелието е на
/// съботата подир Въздвижение, а не от седмичния кръг.)
///
/// ⚠ „Преди" и „след" са СТРОГИ: падне ли празникът в неделя, неделята подир
/// него е СЛЕДВАЩАТА — същото правило като при [sundayAfterExaltation].
List<R> anchoredFor(DateTime date, {required bool oldStyle}) {
  final d = DateTime.utc(date.year, date.month, date.day);
  if (d.weekday != DateTime.saturday && d.weekday != DateTime.sunday) {
    return const [];
  }
  final out = <R>[];
  for (final feast in kAnchorFeasts) {
    final m = int.parse(feast.substring(0, 2));
    final day = int.parse(feast.substring(3));
    // ⚠ Празникът може да е в СЪСЕДНАТА гражданска година: Рождество по
    // стар стил пада на 7 януари, тъй че за декемврийски ден трябва и
    // следващата, а за януарски — и предишната.
    for (final y in [d.year - 1, d.year, d.year + 1]) {
      final feastDate = civilDateOfChurch(y, m, day, oldStyle: oldStyle);
      final diff = d.difference(feastDate).inDays;
      // Търси се само в тясна околност — най-много седмица от двете страни.
      if (diff.abs() > 7 || diff == 0) continue;
      final dir = diff < 0 ? 'before' : 'after';
      final rows = kReadingsAnchored['$feast|${d.weekday}|$dir'];
      if (rows != null) out.addAll(rows);
    }
  }
  return out;
}

/// Четивата за деня: подвижните плюс тези на паметта.
///
/// [churchMonthDay] е ЦЪРКОВНАТА дата „ММ-ДД" — тя се смята от гражданската
/// по правилото на стила, тъй че всеки стил намира СВОИТЕ памети.
///
/// ⚠ Седмиците над [kStableWeeks] се взимат САМО ако [allowUnstable] — там
/// данните носят вградена отстъпката на 2026 г. и за друга година биха били
/// тихо сгрешени.
List<R> readingsFor(DateTime date, String churchMonthDay,
    {required bool oldStyle, bool allowUnstable = false}) {
  final addr = readingAddress(date);
  final out = <R>[];

  // ⚠⚠ ДВА ОТДЕЛНИ БРОЯЧА. Апостолът върви по своя номер, евангелието — по
  // своя, който след Неделята по Въздвижение скача на 18 (виж
  // [gospelWeekFor]). Ключирани на един адрес, те вкаменяват съвпадението
  // на една година като правило за всички.
  // ⚠ ЗИМНАТА ОТСТЪПКА има превес: там редовият кръг е изчерпан и се брои
  // назад от 33-та (виж [winterWeekFor]).
  final winter = addr.cycle == ReadingCycle.afterPentecost
      ? winterWeekFor(date, oldStyle: oldStyle)
      : null;
  final apostleWeek = winter ?? addr.week;
  final gospelWeek = winter ??
      (addr.cycle == ReadingCycle.afterPentecost
          ? gospelWeekFor(date, addr.week, oldStyle: oldStyle)
          : addr.week);
  final apostleKey =
      ReadingAddress(addr.cycle, apostleWeek, addr.weekday).key;
  final gospelKey = ReadingAddress(addr.cycle, gospelWeek, addr.weekday).key;

  void take(Map<String, List<R>> index, String key, String kind) {
    final rows = index[key];
    if (rows != null) out.addAll(rows);
    if (addr.cycle != ReadingCycle.afterPentecost) return;
    final week = kind == 'gospel' ? gospelWeek : apostleWeek;
    if (week > kStableWeeks && allowUnstable) {
      final tail = kReadingsUnstable['$kind:$key'];
      if (tail != null) out.addAll(tail);
    }
  }

  take(kReadingsApostle, apostleKey, 'apostle');
  // ⚠⚠ НЕДЕЛНОТО ЕВАНГЕЛИЕ СЛЕД ВЪЗДВИЖЕНИЕ — по свое правило, не по
  // таблицата: виж [sundayGospelAfterExaltation].
  final sunday = addr.cycle == ReadingCycle.afterPentecost
      ? sundayGospelAfterExaltation(date, oldStyle: oldStyle)
      : null;
  if (sunday == null) {
    take(kReadingsGospel, gospelKey, 'gospel');
  } else if (sunday.number != null) {
    out.add(R('gospel', kSundayGospels[sunday.number]!));
  }

  final fixed = kReadingsFixed[churchMonthDay];
  if (fixed != null) out.addAll(fixed);
  out.addAll(anchoredFor(date, oldStyle: oldStyle));
  return out;
}
