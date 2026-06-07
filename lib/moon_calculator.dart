import 'dart:math' as math;

// ─── Изчисления на фазите на луната ──────────────────────────────────────
// Използва пълния алгоритъм на Meeus (Astronomical Algorithms, Chapter 49)
// Точност: ~2 минути спрямо официалните данни на USNO
// Не изисква база данни или интернет — чисто математическо изчисление

class MoonPhase {
  final double age;           // Възраст в дни (0-29.53)
  final double illumination;  // Осветеност 0.0-1.0
  final MoonPhaseType type;   // Тип фаза

  const MoonPhase({
    required this.age,
    required this.illumination,
    required this.type,
  });

  int get illuminationPercent => (illumination * 100).round();

  int get daysToNext {
    const synodic = 29.53058867;
    double nextPhaseAge;
    if (age < 7.38) nextPhaseAge = 7.38;
    else if (age < 14.77) nextPhaseAge = 14.77;
    else if (age < 22.15) nextPhaseAge = 22.15;
    else nextPhaseAge = synodic;
    return (nextPhaseAge - age).ceil();
  }

  String get nextPhaseName {
    if (age < 7.38)  return 'Първа четвърт';
    if (age < 14.77) return 'Пълнолуние';
    if (age < 22.15) return 'Последна четвърт';
    return 'Новолуние';
  }
}

enum MoonPhaseType {
  newMoon,        // Новолуние
  waxingCrescent, // Нарастваща
  firstQuarter,   // Първа четвърт
  waxingGibbous,  // Нарастваща гърбица
  fullMoon,       // Пълнолуние
  waningGibbous,  // Намаляваща гърбица
  lastQuarter,    // Последна четвърт
  waningCrescent, // Намаляваща
}

class MoonCalculator {
  static const double _synodic = 29.53058867;

  // ─── Основна функция за фаза на луна ───────────────────────────────────
  static MoonPhase calculate(DateTime date) {
    final utcDate = DateTime.utc(date.year, date.month, date.day, 12);

    // Намираме последното новолуние преди или на тази дата
    final newMoonJde  = _nearestPhaseJde(utcDate, 0.0);
    final dateJde     = _dateToJde(utcDate);
    double age        = dateJde - newMoonJde;

    // Ако age е отрицателно — вземаме предишния лунен цикъл
    if (age < 0) age += _synodic;
    // Ограничаваме в [0, synodic)
    age = age % _synodic;

    // Осветеност
    final illumination = (1 - math.cos(age / _synodic * 2 * math.pi)) / 2;

    return MoonPhase(
      age: age,
      illumination: illumination,
      type: _getType(age),
    );
  }

  // ─── Проверява дали дадена дата е ден на ключова фаза ──────────────────
  // Връща true само ако точният момент на фазата се пада в това денонощие (UTC)
	static bool isKeyPhaseDay(DateTime date) {
	  final dayStart = DateTime.utc(date.year, date.month, date.day, 0, 0, 0);
	  final dayEnd   = DateTime.utc(date.year, date.month, date.day, 23, 59, 59);
	  final jdeStart = _dateToJde(dayStart);
	  final jdeEnd   = _dateToJde(dayEnd);

	  for (final phase in [0.0, 0.25, 0.5, 0.75]) {
		final phaseJde = _nearestPhaseJde(
			DateTime.utc(date.year, date.month, date.day, 12), phase);
		if (date.month == 6 && (date.day == 8 || date.day == 29 || date.day == 30)) {
		  final phaseDate = DateTime.fromMillisecondsSinceEpoch(
			  ((phaseJde - 2440587.5) * 86400000).round(), isUtc: true);
		  //print('${date.day} юни phase=$phase: phaseDate=$phaseDate');
		}
		if (phaseJde >= jdeStart && phaseJde <= jdeEnd) return true;
	  }
	  return false;
	}

  // ─── Връща типа фаза за иконката в месечния изглед ─────────────────────
	static MoonPhaseType? keyPhaseForDay(DateTime date) {
	  final dayStart = DateTime.utc(date.year, date.month, date.day, 0, 0, 0);
	  final dayEnd   = DateTime.utc(date.year, date.month, date.day, 23, 59, 59);
	  final jdeStart = _dateToJde(dayStart);
	  final jdeEnd   = _dateToJde(dayEnd);

	  if (date.month == 6 && (date.day == 8 || date.day == 29 || date.day == 30)) {
		//print('${date.day} юни: jdeStart=$jdeStart jdeEnd=$jdeEnd');
	  }

	  final phaseMap = {
		0.0:  MoonPhaseType.newMoon,
		0.25: MoonPhaseType.firstQuarter,
		0.5:  MoonPhaseType.fullMoon,
		0.75: MoonPhaseType.lastQuarter,
	  };

	  for (final entry in phaseMap.entries) {
		final phaseJde = _nearestPhaseJde(
			DateTime.utc(date.year, date.month, date.day, 12), entry.key);
		if (date.month == 6 && (date.day == 8 || date.day == 29 || date.day == 30)) {
		  //print('  phase=${entry.key}: phaseJde=$phaseJde');
		}
		if (phaseJde >= jdeStart && phaseJde <= jdeEnd) return entry.value;
	  }
	  return null;
	}

	static double _nearestPhaseJde(DateTime date, double phase) {
	  final year = date.year + (date.month - 1) / 12.0 + (date.day - 1) / 365.25;
	  final kBase = ((year - 2000) * 12.3685).roundToDouble();
	  final dateJde = _dateToJde(date);

	  // Проверяваме k-1, k и k+1 — взимаме най-близката
	  double bestJde = double.infinity;
	  for (int delta = -1; delta <= 1; delta++) {
		final k = kBase + phase + delta;
		final jde = _computePhaseJde(k, phase);
		if ((jde - dateJde).abs() < (bestJde - dateJde).abs()) {
		  bestJde = jde;
		}
	  }
	  return bestJde;
	}

  // ─── Пълен алгоритъм на Meeus (Chapter 49) ─────────────────────────────
  // Изчислява Julian Day на най-близката фаза (0=new, 0.25=FQ, 0.5=full, 0.75=LQ)
  static double _computePhaseJde(double k, double phase) {
    //final year  = date.year + (date.month - 1) / 12.0 + (date.day - 1) / 365.25;
    //final k     = ((year - 2000) * 12.3685).roundToDouble() + phase;

    final T  = k / 1236.85;
    final T2 = T * T;
    final T3 = T2 * T;
    final T4 = T3 * T;

    double JDE = 2451550.09766
        + 29.530588861 * k
        + 0.00015437   * T2
        - 0.000000150  * T3
        + 0.00000000073 * T4;

    final M = _rad(2.5534
        + 29.10535670 * k
        - 0.0000014   * T2
        - 0.00000011  * T3);

    final Mp = _rad(201.5643
        + 385.81693528 * k
        + 0.0107582    * T2
        + 0.00001238   * T3
        - 0.000000058  * T4);

    final F = _rad(160.7108
        + 390.67050284 * k
        - 0.0016118    * T2
        - 0.00000227   * T3
        + 0.000000011  * T4);

    final Omega = _rad(124.7746
        - 1.56375588 * k
        + 0.0020672  * T2
        + 0.00000215 * T3);

    final E  = 1 - 0.002516 * T - 0.0000074 * T2;

    if (phase == 0.0 || phase == 0.5) {
      // Новолуние и Пълнолуние
      final sign = (phase == 0.5) ? -0.40614 : -0.40720;
      JDE += sign       * math.sin(Mp)
          + 0.17241 * E * math.sin(M)
          + 0.01608     * math.sin(2 * Mp)
          + 0.01039     * math.sin(2 * F)
          + 0.00739 * E * math.sin(Mp - M)
          - 0.00514 * E * math.sin(Mp + M)
          + 0.00208 * E * E * math.sin(2 * M)
          - 0.00111     * math.sin(Mp - 2 * F)
          - 0.00057     * math.sin(Mp + 2 * F)
          + 0.00056 * E * math.sin(2 * Mp + M)
          - 0.00042     * math.sin(3 * Mp)
          + 0.00042 * E * math.sin(M + 2 * F)
          + 0.00038 * E * math.sin(M - 2 * F)
          - 0.00024 * E * math.sin(2 * Mp - M)
          - 0.00017     * math.sin(Omega)
          - 0.00007     * math.sin(Mp + 2 * M)
          + 0.00004     * math.sin(2 * Mp - 2 * F)
          + 0.00004     * math.sin(3 * M)
          + 0.00003     * math.sin(Mp + M - 2 * F)
          + 0.00003     * math.sin(2 * Mp + 2 * F)
          - 0.00003     * math.sin(Mp + M + 2 * F)
          + 0.00003     * math.sin(Mp - M + 2 * F)
          - 0.00002     * math.sin(Mp - M - 2 * F)
          - 0.00002     * math.sin(3 * Mp + M)
          + 0.00002     * math.sin(4 * Mp);
    } else {
      // Първа и Последна четвърт
      double W = 0.00306
          - 0.00038 * E * math.cos(M)
          + 0.00026 * math.cos(Mp)
          - 0.00002 * math.cos(Mp - M)
          + 0.00002 * math.cos(Mp + M)
          + 0.00002 * math.cos(2 * F);
      if (phase == 0.75) W = -W;

      JDE += -0.62801     * math.sin(Mp)
          + 0.17172 * E   * math.sin(M)
          - 0.01183 * E   * math.sin(Mp + M)
          + 0.00862        * math.sin(2 * Mp)
          + 0.00804        * math.sin(2 * F)
          + 0.00454 * E   * math.sin(Mp - M)
          + 0.00204 * E*E * math.sin(2 * M)
          - 0.00180        * math.sin(Mp - 2 * F)
          - 0.00070        * math.sin(Mp + 2 * F)
          - 0.00040        * math.sin(3 * Mp)
          - 0.00034 * E   * math.sin(2 * Mp - M)
          + 0.00032 * E   * math.sin(M + 2 * F)
          + 0.00032 * E   * math.sin(M - 2 * F)
          - 0.00028 * E*E * math.sin(Mp + 2 * M)
          + 0.00027 * E   * math.sin(2 * Mp + M)
          - 0.00017        * math.sin(Omega)
          - 0.00005        * math.sin(Mp - M - 2 * F)
          + 0.00004        * math.sin(2 * Mp + 2 * F)
          - 0.00004        * math.sin(Mp + M + 2 * F)
          + 0.00004        * math.sin(Mp - 2 * M)
          + 0.00003        * math.sin(Mp + M - 2 * F)
          + 0.00003        * math.sin(3 * M)
          + 0.00002        * math.sin(2 * Mp - 2 * F)
          + 0.00002        * math.sin(Mp - M + 2 * F)
          - 0.00002        * math.sin(3 * Mp + M)
          + W;
    }

    return JDE;
  }

  // ─── Помощни функции ───────────────────────────────────────────────────
  static double _rad(double deg) => deg * math.pi / 180.0;

  // Конвертира DateTime към Julian Day
  static double _dateToJde(DateTime date) {
    final jdUnixEpoch = 2440587.5;
    // TT-UTC корекция (~69 сек за 2026)
    return jdUnixEpoch + date.millisecondsSinceEpoch / 86400000.0 + 69.0 / 86400.0;
  }

  static MoonPhaseType _getType(double age) {
    if (age < 1.85 || age >= 27.68) return MoonPhaseType.newMoon;
    if (age < 7.38)  return MoonPhaseType.waxingCrescent;
    if (age < 9.22)  return MoonPhaseType.firstQuarter;
    if (age < 14.77) return MoonPhaseType.waxingGibbous;
    if (age < 16.61) return MoonPhaseType.fullMoon;
    if (age < 22.15) return MoonPhaseType.waningGibbous;
    if (age < 24.0)  return MoonPhaseType.lastQuarter;
    return MoonPhaseType.waningCrescent;
  }

  // ─── UI помощни функции ────────────────────────────────────────────────
  static bool isKeyPhase(MoonPhaseType type) {
    return type == MoonPhaseType.newMoon ||
           type == MoonPhaseType.firstQuarter ||
           type == MoonPhaseType.fullMoon ||
           type == MoonPhaseType.lastQuarter;
  }

  static String symbol(MoonPhaseType type) {
    switch (type) {
      case MoonPhaseType.newMoon:        return '●';
      case MoonPhaseType.waxingCrescent: return '☽';
      case MoonPhaseType.firstQuarter:   return '◑';
      case MoonPhaseType.waxingGibbous:  return '◕';
      case MoonPhaseType.fullMoon:       return '○';
      case MoonPhaseType.waningGibbous:  return '◔';
      case MoonPhaseType.lastQuarter:    return '◐';
      case MoonPhaseType.waningCrescent: return '☾';
    }
  }

  static String name(MoonPhaseType type) {
    switch (type) {
      case MoonPhaseType.newMoon:        return 'Новолуние';
      case MoonPhaseType.waxingCrescent: return 'Нарастваща луна';
      case MoonPhaseType.firstQuarter:   return 'Първа четвърт';
      case MoonPhaseType.waxingGibbous:  return 'Нарастваща гърбица';
      case MoonPhaseType.fullMoon:       return 'Пълнолуние';
      case MoonPhaseType.waningGibbous:  return 'Намаляваща гърбица';
      case MoonPhaseType.lastQuarter:    return 'Последна четвърт';
      case MoonPhaseType.waningCrescent: return 'Намаляваща луна';
    }
  }
}
