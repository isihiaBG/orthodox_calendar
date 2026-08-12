// reader_theme.dart
//
// Видът на четенето — палитрата, шрифтовете и нощният режим. ОБЩО за всеки
// екран, на който се чете свързан текст: житията и службите
// (reader_screen.dart) и книгите от „Читанка" (book_reader.dart).
//
// Изнесено от reader_screen.dart, за да не се разминат двата четеца.
// Дотогава тези стойности живееха вътре в състоянието на екрана и всяка
// промяна трябваше да се повтори на второ място — точно начинът, по който
// днес се получи разминаването с междуредието в PDF-а.
//
// ПАЛИТРАТА Е НЕЗАВИСИМА ОТ ТЕМАТА НА ПРИЛОЖЕНИЕТО. Приложението може да е
// тъмно, а четецът светъл (или обратното) — при четене на дълъг текст
// човек иска друго от очите си, отколкото при преглеждане на календар.

import 'package:flutter/material.dart';

// Шрифтовете (family имената от pubspec.yaml):
const String kTitleFamily = 'TamburinModern'; // заглавието на четивото
const String kDropCapFamily = 'Bukvica';      // орнаментираният инициал
const String kBodyFamily = 'CharisSIL';       // основният текст и молитвите

/// Междуредието на основния текст, в кратни на размера на шрифта.
const double kReaderLineHeight = 1.25;

/// Нощен режим на четеца — СЕСИЕН и общ за всички екрани, на които се чете.
///
/// Нарочно static: човек нагласява четенето веднъж и очаква следващото
/// четиво да се отвори по същия начин, без значение дали идва от календара
/// или от „Читанка".
class ReaderTheme {
  static bool dark = true;

  static ReaderPalette get palette => ReaderPalette(dark);
}

/// Цветовете при даден режим. Държат се заедно, за да не се задава някой от
/// тях на ръка и да изпадне от съгласие с останалите.
class ReaderPalette {
  final bool dark;
  const ReaderPalette(this.dark);

  Color get bg => dark ? const Color(0xFF121212) : const Color(0xFFF5E6C5);
  Color get ink => dark ? const Color(0xFFE6E1D8) : const Color(0xFF1A1A1A);
  Color get dim => dark ? const Color(0xFF9A948A) : const Color(0xFF6B675F);
  Color get wine => dark ? const Color(0xFFA0555B) : const Color(0xFFB83333);

  /// Фонът зад намерените съвпадения при търсене в текста.
  Color get hit => dark ? const Color(0xFF6B5B1E) : const Color(0xFFFFF176);
  Color get hitCurrent =>
      dark ? const Color(0xFFCC8A2E) : const Color(0xFFFFA726);

  /// Чертичките по скролбара. В светъл режим жълтото на [hit] е добро като
  /// фон зад текст, но на тънка чертичка почти изчезва — затова там е
  /// по-наситено.
  Color get tickHit => dark ? hit : const Color(0xFF9C7A1A);
  Color get tickCurrent => hitCurrent;
}
