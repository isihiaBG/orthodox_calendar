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
