// molitvoslov_settings.dart
//
// Настройките на „Молитвослов" — СВОИ, отделни от тези на Библията.
//
// ⚠⚠ Изрично искане на потребителя: изборът на език, запомненият екран и
// всичко останало тук не бива да влияе на библейския четец (и обратно).
// Затова ключовете са с представка `molitvoslov_` и нищо тук не чете
// BibleLanguages/BibleLastPart/BibleFontSize.

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'reader_font_size.dart';

/// Коя колона се гледа в изправено: 0 = българската, 1 = църковнославянската.
///
/// ⚠ ValueNotifier по установения образец (ReaderDropCapScale, BibleZachala):
/// отворен екран трябва да разбере за смяната, без да се строи наново.
class MolitvoslovLanguages {
  MolitvoslovLanguages._();

  static const String _key = 'molitvoslov_active';
  static final ValueNotifier<int> active = ValueNotifier<int>(0);
  static bool _loaded = false;

  static Future<void> loadOnce() async {
    if (_loaded) return;
    _loaded = true;
    final p = await SharedPreferences.getInstance();
    active.value = (p.getInt(_key) ?? 0).clamp(0, 1);
  }

  static Future<void> set(int v) async {
    if (active.value == v) return;
    active.value = v;
    final p = await SharedPreferences.getInstance();
    await p.setInt(_key, v);
  }
}

/// Последно избраният таб — за да се отваря там, където човек е бил.
class MolitvoslovLastTab {
  MolitvoslovLastTab._();

  static const String _key = 'molitvoslov_last_tab';
  static int value = 0;
  static bool _loaded = false;

  static Future<void> loadOnce() async {
    if (_loaded) return;
    _loaded = true;
    final p = await SharedPreferences.getInstance();
    value = p.getInt(_key) ?? 0;
  }

  static Future<void> set(int v) async {
    if (value == v) return;
    value = v;
    final p = await SharedPreferences.getInstance();
    await p.setInt(_key, v);
  }
}

/// Последно отвореният РАЗДЕЛ (id от `sections`) — маркира се в синьо в
/// съдържанието, както последно четената глава в Библията. `null` — още
/// нищо не е отваряно, тогава нищо не се маркира.
class MolitvoslovLastSection {
  MolitvoslovLastSection._();

  static const String _key = 'molitvoslov_last_section';
  static int? value;
  static bool _loaded = false;

  static Future<void> loadOnce() async {
    if (_loaded) return;
    _loaded = true;
    final p = await SharedPreferences.getInstance();
    value = p.getInt(_key);
  }

  static Future<void> set(int v) async {
    if (value == v) return;
    value = v;
    final p = await SharedPreferences.getInstance();
    await p.setInt(_key, v);
  }
}

/// „Богослужебни": последно отвореният раздел ЗА ВСЯКА КНИГА поотделно —
/// човек, който кара службата, скача между Часослова, Октоиха и Минеята и
/// всяка трябва да го върне там, където е спрял в нея.
class MolitvoslovBookLast {
  MolitvoslovBookLast._();

  static const String _key = 'molitvoslov_book_last';
  static final Map<String, int> value = {};
  static bool _loaded = false;

  static Future<void> loadOnce() async {
    if (_loaded) return;
    _loaded = true;
    final p = await SharedPreferences.getInstance();
    for (final e in p.getStringList(_key) ?? const <String>[]) {
      final i = e.lastIndexOf('|');
      final id = int.tryParse(e.substring(i + 1));
      if (i > 0 && id != null) value[e.substring(0, i)] = id;
    }
  }

  /// Маха записите, чието id вече не е от своята книга. Базата се
  /// пресглобява и номерата на разделите се разместват, а записът на
  /// телефона остава — тогава „последно четеното" в една книга сочи чужд
  /// раздел (и съдържанието тръгваше да плъзга към несъществуващ ред).
  /// [bookOf] връща книгата на раздела с това id или null, ако го няма.
  static void prune(String? Function(int id) bookOf) {
    value.removeWhere((book, id) => bookOf(id) != book);
  }

  static Future<void> set(String book, int id) async {
    if (value[book] == id) return;
    value[book] = id;
    final p = await SharedPreferences.getInstance();
    await p.setStringList(
        _key, [for (final e in value.entries) '${e.key}|${e.value}']);
  }
}

/// Кои книги и в какъв ред стоят в плаващото копче — нагласява се от
/// човека (режим на редактиране). null = всички, в подразбиращия се ред.
///
/// ⚠ [known] — кои книги СЪЩЕСТВУВАХА, когато човекът е нагласил списъка.
/// Книга, която я няма там, е НОВА (дошла с по-нов билд) и влиза в списъка
/// сама, накрая; иска ли я вън, я маха с редактирането (указание на
/// потребителя). Без това всяка нова книга оставаше извън списъка, защото
/// записаното изглеждаше като съзнателен избор без нея.
class MolitvoslovSwitcherBooks {
  MolitvoslovSwitcherBooks._();

  static const String _key = 'molitvoslov_switcher_books';
  static const String _knownKey = 'molitvoslov_switcher_known';
  static List<String>? value;
  static List<String>? known;
  static bool _loaded = false;

  static Future<void> loadOnce() async {
    if (_loaded) return;
    _loaded = true;
    final p = await SharedPreferences.getInstance();
    value = p.getStringList(_key);
    known = p.getStringList(_knownKey);
  }

  static Future<void> set(List<String> books, List<String> knownBooks) async {
    value = List.of(books);
    known = List.of(knownBooks);
    final p = await SharedPreferences.getInstance();
    await p.setStringList(_key, books);
    await p.setStringList(_knownKey, knownBooks);
  }
}

/// „Богослужебни": ТОЧНОТО място във всеки раздел — (молитва, дял от
/// височината ѝ). Човек, който кара службата, скача за всяка стихира между
/// Часослова, Октоиха и Минеята; приблизително място прави това неизползваемо
/// (указание на потребителя). Дялът, а не пикселът — пикселът се разминава при
/// друг шрифт или завъртане.
class MolitvoslovPlaces {
  MolitvoslovPlaces._();

  static const String _key = 'molitvoslov_places';
  static final Map<int, (int, double)> value = {};
  static bool _loaded = false;

  static Future<void> loadOnce() async {
    if (_loaded) return;
    _loaded = true;
    final p = await SharedPreferences.getInstance();
    for (final e in p.getStringList(_key) ?? const <String>[]) {
      final f = e.split('|');
      if (f.length != 3) continue;
      final id = int.tryParse(f[0]), u = int.tryParse(f[1]), d = double.tryParse(f[2]);
      if (id != null && u != null && d != null) value[id] = (u, d);
    }
  }

  static Future<void> set(int section, (int, double) place) async {
    value[section] = place;
    final p = await SharedPreferences.getInstance();
    await p.setStringList(_key, [
      for (final e in value.entries)
        '${e.key}|${e.value.$1}|${e.value.$2.toStringAsFixed(5)}'
    ]);
  }
}

/// Размерът на шрифта в четеца на молитвослова — свой, както Библията има
/// свой. Механизмът е общият [PersistedFontSize].
class MolitvoslovFontSize {
  MolitvoslovFontSize._();

  static final PersistedFontSize _it = PersistedFontSize(
    prefsKey: 'molitvoslov_font_size',
    initial: 18.0,
    min: 12.0,
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
