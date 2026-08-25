// reader_font_size.dart
//
// Размерът на шрифта при четене — ОБЩ за всеки екран, на който се чете
// свързан текст: житията и службите (reader_screen.dart) и книгите от
// „Месецослов" (book_reader.dart).
//
// Изнесено от reader_screen.dart. Стойността е static нарочно: човек си
// нагласява шрифта веднъж и очаква следващото четиво да се отвори с него,
// без значение откъде идва. Ако всеки четец си държеше свой размер,
// прескачането между жития и книги щеше да мени буквите под очите му.
//
// Записът на диска е ОТЛОЖЕН (3 сек. покой), защото хората почти никога не
// уцелват желания размер от първия тап — иначе всяко натискане на +/- би
// било запис.
//
// МЕХАНИЗМЪТ е в PersistedFontSize и е един за всички; отделните размери са
// само негови настройки. Съдържанието на книгите (TocFontSize) си има свой,
// независим от този на четенето: то е указател, не четиво, и човек го иска
// сбито дори когато чете с едри букви.

import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

/// Един запомнящ се размер на шрифт: граници, стъпка, ключ на диска и
/// отложен запис. Всеки екземпляр е независим от останалите.
class PersistedFontSize {
  final double min;
  final double max;
  final double step;
  final String prefsKey;

  double _value;
  bool _loadedFromDisk = false;

  /// Последно ЗАПИСАНАТА стойност, пазена в паметта — сравняваме с нея,
  /// вместо да четем от диска, за да пропускаме излишни записи (напр.
  /// потребителят увеличава и после пак намалява до същото).
  double? _lastSaved;

  Timer? _saveTimer;

  PersistedFontSize({
    required this.prefsKey,
    required double initial,
    required this.min,
    required this.max,
    required this.step,
  }) : _value = initial;

  double get value => _value;

  /// Зарежда запазения размер — САМО веднъж на сесия. Следващите екрани
  /// вече го виждат направо в полето.
  Future<void> loadOnce() async {
    if (_loadedFromDisk) return;
    _loadedFromDisk = true;
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getDouble(prefsKey);
    if (saved != null) {
      _value = saved.clamp(min, max);
      _lastSaved = _value;
    }
  }

  /// Променя размера с [delta] в допустимите граници и отлага записа.
  /// Връща новата стойност.
  double nudge(double delta) {
    _value = (_value + delta).clamp(min, max);
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 3), flush);
    return _value;
  }

  /// Записва веднага, ако има какво. Вика се и при затваряне на екрана —
  /// иначе последната промяна се губи, ако човек излезе преди изтичането
  /// на покоя.
  void flush() {
    _saveTimer?.cancel();
    _saveTimer = null;
    if (_lastSaved == _value) return;
    _lastSaved = _value;
    SharedPreferences.getInstance()
        .then((prefs) => prefs.setDouble(prefsKey, _value));
  }
}

/// Размерът на ЧЕТИВОТО — жития, служби, глави от книги.
class ReaderFontSize {
  ReaderFontSize._();

  static final PersistedFontSize _it = PersistedFontSize(
    prefsKey: 'reader_font_size',
    initial: 22.0,
    min: 13.0,
    max: 30.0,
    step: 1.5,
  );

  static double get min => _it.min;
  static double get max => _it.max;
  static double get step => _it.step;
  static double get value => _it.value;

  static Future<void> loadOnce() => _it.loadOnce();
  static double nudge(double delta) => _it.nudge(delta);
  static void flush() => _it.flush();
}

/// Размерът в секцията „Библия" — СВОЙ, независим от този на четенето.
///
/// ⚠ Нарочно НЕ е общият [ReaderFontSize], макар и двете да са четене. Тук
/// подредбата е съвсем друга: до всеки стих стои колонка с номер, а в легнало
/// положение на екрана се събират ДВА превода един до друг. При 22 пункта (по
/// подразбиране за житията) двете колони излизат по няколко думи на ред и
/// сравняването става безсмислено.
///
/// Подразбирането 16 не е избрано на око — това е размерът на имената на
/// светиите в дневния изглед (`day_screen.dart`), тоест мярката, по която
/// приложението вече показва сбит списъчен текст.
///
/// ⚠ Следствие, което трябва да се знае: нагласиш ли шрифта тук, това НЕ се
/// пренася върху житията и книгите, нито обратно. Ако някой ден се реши, че
/// трябва да е общо, сменя се само този обект — механизмът е един.
class BibleFontSize {
  BibleFontSize._();

  static final PersistedFontSize _it = PersistedFontSize(
    prefsKey: 'bible_font_size',
    initial: 16.0,
    min: 12.0,
    max: 28.0,
    step: 1.5,
  );

  static double get min => _it.min;
  static double get max => _it.max;
  static double get step => _it.step;
  static double get value => _it.value;

  static Future<void> loadOnce() => _it.loadOnce();
  static double nudge(double delta) => _it.nudge(delta);
  static void flush() => _it.flush();
}

/// Размерът в СЪДЪРЖАНИЕТО на секцията „Библия" — указателят с книгите,
/// дяловете и решетките с номера.
///
/// ⚠ Свой, а не [TocFontSize]: съдържанието на томовете е списък от заглавия
/// на жития, а тук има три различни неща наведнъж (заглавие на дял, име на
/// книга, номер в решетка) и всичките се движат ЗАЕДНО от едни и същи
/// бутони. Общ размер с друг екран щеше да значи, че нагласата за единия
/// разбърква другия.
///
/// Подразбирането 18 е с две степени над предишните твърди 16 — по изрична
/// молба текстът да е по-едър, БЕЗ редовете да порастват. Затова редът си
/// има отделен под (`_kBookRowMinHeight`), а междуредието вътре в реда е
/// свито: при 18 пункта текстът заема към 21, а подът е 44 — тоест редът не
/// мърда, докато шрифтът не мине 26.
class BibleTocFontSize {
  BibleTocFontSize._();

  /// Заглавието на дял е с толкова над името на книга.
  ///
  /// ⚠ НУЛА — тоест еднакъв размер. Минахме през +2 и +1 и накрая се оказа,
  /// че ПОЛУЧЕРЪТ и ГЛАВНИТЕ БУКВИ сами вършат работата по йерархията, а
  /// всеки допълнителен пункт прави заглавието по-натрапчиво от книгите под
  /// него — при положение че то е указател, не съдържание.
  ///
  /// Полето остава (вместо да се махне), защото е кръстеното място, ако
  /// някога отново потрябва разлика.
  static const double groupBonus = 0.0;

  static final PersistedFontSize _it = PersistedFontSize(
    prefsKey: 'bible_toc_font_size',
    initial: 18.0,
    min: 14.0,
    max: 28.0,
    // Стъпка 1.0, не 1.5 като при четенето: тук се търси точен размер, при
    // който всичко се събира, а не удобство за четене.
    step: 1.0,
  );

  static double get min => _it.min;
  static double get max => _it.max;
  static double get step => _it.step;
  static double get value => _it.value;

  static Future<void> loadOnce() => _it.loadOnce();
  static double nudge(double delta) => _it.nudge(delta);
  static void flush() => _it.flush();
}

/// Размерът в СЪДЪРЖАНИЕТО на книгите — общ за всички томове.
///
/// Стойността е на реда с житието; денят над него стои с [dayBonus] по-едро
/// (виж _TocSheet). Двете вървят заедно нарочно: разликата в ръста прави
/// деня разделител и без линия, тъй че тя не бива да се губи при уголемяване.
class TocFontSize {
  TocFontSize._();

  static const double dayBonus = 2.0;

  static final PersistedFontSize _it = PersistedFontSize(
    prefsKey: 'toc_font_size',
    initial: 16.0,
    min: 12.0,
    max: 26.0,
    step: 1.5,
  );

  static double get min => _it.min;
  static double get max => _it.max;
  static double get step => _it.step;
  static double get value => _it.value;

  static Future<void> loadOnce() => _it.loadOnce();
  static double nudge(double delta) => _it.nudge(delta);
  static void flush() => _it.flush();
}
