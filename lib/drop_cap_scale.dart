// drop_cap_scale.dart
//
// Размерът на буквицата — ОБЩ за двата четеца (жития и книги), по същия
// принцип като reader_font_size.dart: избира се веднъж, пази се, и следващото
// отваряне на четиво го заварва без да пита пак.
//
// За разлика от размера на шрифта, тук няма плавен диапазон — само ТРИ
// стъпки (малка/средна/голяма), затова записът е директен, не отложен: смяна
// на размер е рядко, съзнателно действие в настройките, не поредица от
// нетърпеливи тапвания като +/- на шрифта.
//
// Всяка стъпка носи ДВЕ числа (виж DropCapScaleMetrics по-долу):
//   - linesMultiplier: колко реда обхваща буквицата (заедно с фиксираната
//     0.82 корекция за ascender в reader_screen.dart/book_reader.dart).
//   - offsetMultiplier: допълнителен множител върху ляво/дясната корекция
//     на отделни букви (виж kDropCapOffsetFactor в drop_cap.dart) — пусната
//     е като отделна ос, защото оптичните поправки не е задължително да
//     растат линейно с размера; стойностите се нагласят експериментално.

import 'dart:async';

import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:shared_preferences/shared_preferences.dart';

enum DropCapScale { small, medium, large }

/// Числата зад всяка стъпка — виж бележката най-отгоре. И двете се
/// определят НА ОКО (потвърдено от потребителя, 24.08.2026), не по формула;
/// подкарай ги тук, ако не паснат визуално.
extension DropCapScaleMetrics on DropCapScale {
  double get linesMultiplier => switch (this) {
        DropCapScale.small => 5.5, // ≈5 реда (6 с опашка) — сегашният вид
        DropCapScale.medium => 7.5, // ≈7 реда (8 с опашка)
        DropCapScale.large => 10.5, // ≈10 реда (11 с опашка)
      };

  double get offsetMultiplier => switch (this) {
        DropCapScale.small => 1.0,
        DropCapScale.medium => 1.0,
        DropCapScale.large => 1.0,
      };

  String get label => switch (this) {
        DropCapScale.small => 'Малка',
        DropCapScale.medium => 'Средна',
        DropCapScale.large => 'Голяма',
      };
}

class ReaderDropCapScale {
  ReaderDropCapScale._();

  static const _prefsKey = 'reader_drop_cap_scale';
  static bool _loaded = false;

  /// Слушаем, за да могат отворените четци да се преначертаят веднага
  /// щом изборът се смени в настройките (drawer-ът стои НАД четеца, не
  /// го затваря) — без слушател смяната се виждаше едва при следващо
  /// отваряне на четивото.
  static final ValueNotifier<DropCapScale> notifier =
      ValueNotifier(DropCapScale.small);

  static DropCapScale get value => notifier.value;

  /// Зарежда запазения избор — САМО веднъж на сесия, както при
  /// [ReaderFontSize]/[ReaderTheme].
  static Future<void> loadOnce() async {
    if (_loaded) return;
    _loaded = true;
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefsKey);
    if (saved == null) return;
    for (final s in DropCapScale.values) {
      if (s.name == saved) {
        notifier.value = s;
        return;
      }
    }
  }

  /// Сменя избора и записва веднага — виж бележката най-отгоре защо тук
  /// (за разлика от шрифта) няма нужда от отложен запис.
  static Future<void> set(DropCapScale v) async {
    if (notifier.value == v) return;
    notifier.value = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, v.name);
  }
}
