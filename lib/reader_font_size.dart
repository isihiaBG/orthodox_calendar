// reader_font_size.dart
//
// Размерът на шрифта при четене — ОБЩ за всеки екран, на който се чете
// свързан текст: житията и службите (reader_screen.dart) и книгите от
// „Читанка" (book_reader.dart).
//
// Изнесено от reader_screen.dart. Стойността е static нарочно: човек си
// нагласява шрифта веднъж и очаква следващото четиво да се отвори с него,
// без значение откъде идва. Ако всеки четец си държеше свой размер,
// прескачането между жития и книги щеше да мени буквите под очите му.
//
// Записът на диска е ОТЛОЖЕН (3 сек. покой), защото хората почти никога не
// уцелват желания размер от първия тап — иначе всяко натискане на +/- би
// било запис.

import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

class ReaderFontSize {
  ReaderFontSize._();

  static const double min = 13.0;
  static const double max = 30.0;
  static const double step = 1.5;

  static const String _prefsKey = 'reader_font_size';

  static double _value = 22.0;
  static bool _loadedFromDisk = false;

  /// Последно ЗАПИСАНАТА стойност, пазена в паметта — сравняваме с нея,
  /// вместо да четем от диска, за да пропускаме излишни записи (напр.
  /// потребителят увеличава и после пак намалява до същото).
  static double? _lastSaved;

  static Timer? _saveTimer;

  static double get value => _value;

  /// Зарежда запазения размер — САМО веднъж на сесия. Следващите екрани
  /// вече го виждат направо в статичното поле.
  static Future<void> loadOnce() async {
    if (_loadedFromDisk) return;
    _loadedFromDisk = true;
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getDouble(_prefsKey);
    if (saved != null) {
      _value = saved.clamp(min, max);
      _lastSaved = _value;
    }
  }

  /// Променя размера с [delta] в допустимите граници и отлага записа.
  /// Връща новата стойност.
  static double nudge(double delta) {
    _value = (_value + delta).clamp(min, max);
    _scheduleSave();
    return _value;
  }

  static void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 3), flush);
  }

  /// Записва веднага, ако има какво. Вика се и при затваряне на екрана —
  /// иначе последната промяна се губи, ако човек излезе преди изтичането
  /// на покоя.
  static void flush() {
    _saveTimer?.cancel();
    _saveTimer = null;
    if (_lastSaved == _value) return;
    _lastSaved = _value;
    SharedPreferences.getInstance()
        .then((prefs) => prefs.setDouble(_prefsKey, _value));
  }
}
