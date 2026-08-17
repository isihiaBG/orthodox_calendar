// reader_theme.dart
//
// Видът на четенето — палитрата, шрифтовете и нощният режим. ОБЩО за всеки
// екран, на който се чете свързан текст: житията и службите
// (reader_screen.dart) и книгите от „Месецослов" (book_reader.dart).
//
// Изнесено от reader_screen.dart, за да не се разминат двата четеца.
// Дотогава тези стойности живееха вътре в състоянието на екрана и всяка
// промяна трябваше да се повтори на второ място — точно начинът, по който
// днес се получи разминаването с междуредието в PDF-а.
//
// ПАЛИТРАТА Е НЕЗАВИСИМА ОТ ТЕМАТА НА ПРИЛОЖЕНИЕТО. Приложението може да е
// тъмно, а четецът светъл (или обратното) — при четене на дълъг текст
// човек иска друго от очите си, отколкото при преглеждане на календар.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_theme.dart';

// Шрифтовете (family имената от pubspec.yaml):
const String kTitleFamily = 'TamburinModern'; // заглавието на четивото
const String kDropCapFamily = 'Bukvica';      // орнаментираният инициал
const String kBodyFamily = 'CharisSIL';       // основният текст и молитвите

/// Резервният шрифт за заглавията — подава се като `fontFamilyFallback`
/// НАВСЯКЪДЕ, където се ползва [kTitleFamily].
///
/// ⚠ Без него Flutter сам избира с какво да замени липсващия знак, и то
/// почти винаги е системният: изправен, по-едър и в спор със стила на
/// Tamburin. В „Прмч. Евдокѝя" едната буква изведнъж изглежда от друг
/// текст.
///
/// Измерено: Tamburin покрива 229 знака, а в имената на светиите липсват
/// точно ТРИ — „ѝ" (U+045D, 4 срещания), „Ѝ" (U+040D) и комбиниращото
/// ударение (U+0301). Charis SIL има и трите и е далеч по-близо по дух,
/// понеже с него е набран самият текст под заглавието.
///
/// Резервът важи ЗА ОТДЕЛЕН ГЛИФ, не за целия надпис: заглавието си остава
/// Tamburin, само тези знаци идват от Charis.
const List<String> kTitleFallback = [kBodyFamily];

/// Междуредието на основния текст, в кратни на размера на шрифта.
const double kReaderLineHeight = 1.25;

/// Нощен режим на четеца — СЕСИЕН и общ за всички екрани, на които се чете.
///
/// Нарочно static: човек нагласява четенето веднъж и очаква следващото
/// четиво да се отвори по същия начин, без значение дали идва от календара
/// или от „Месецослов".
class ReaderTheme {
  static const String _prefsKey = 'reader_dark';

  static bool _dark = true;
  static bool _loaded = false;

  /// Тъмно ли се чете. ОБЩО за двата четеца — за човека това е един четец
  /// и настройката му не бива да се иска два пъти.
  static bool get dark => _dark;

  /// ⚠ Записва се на диска, но ОТЛОЖЕНО — 3 секунди покой, както при
  /// [ReaderFontSize] и при настройките на приложението. Човек може да
  /// разцъка превключвателя няколко пъти, докато прецени; всяко натискане
  /// не бива да удря диска.
  ///
  /// Дотогава темата беше обикновено поле, което изобщо не се пазеше:
  /// превключиш на светла, излезеш от приложението и при следващото
  /// пускане пак си на тъмна. Размерът на шрифта се пази отдавна, тъй че
  /// липсата тук изглеждаше като случайност.
  static set dark(bool v) {
    if (_dark == v) return;
    _dark = v;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 3), flush);
  }

  static Timer? _saveTimer;
  static bool? _lastSaved;

  /// Записва веднага, ако има какво. Вика се при затваряне на четеца —
  /// иначе последната промяна се губи, ако човек излезе преди изтичането
  /// на покоя.
  static void flush() {
    _saveTimer?.cancel();
    _saveTimer = null;
    if (_lastSaved == _dark) return;
    _lastSaved = _dark;
    SharedPreferences.getInstance().then((p) => p.setBool(_prefsKey, _dark));
  }

  /// Вика се веднъж при отваряне на четец, заедно с
  /// `ReaderFontSize.loadOnce()`.
  static Future<void> loadOnce() async {
    if (_loaded) return;
    _loaded = true;
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getBool(_prefsKey);
    if (saved != null) {
      _dark = saved;
      _lastSaved = saved;
    }
  }

  static ReaderPalette get palette => ReaderPalette(_dark);
}

/// Дебелината на палеца на скролбара. Ползва се и от лентата с чертичките
/// за намерените съвпадения, за да легнат точно върху него.
const double kReaderScrollThumb = 10.0;

/// Темата на скролбара при четене — ОБЩА за двата четеца.
///
/// Палецът следва темата на ЧЕТЕЦА, не на приложението. Изнесена е, защото
/// зададена наум на две места веднага се разминава: в книгите отначало беше
/// само дебелина и палецът излизаше видимо по-светъл.
ScrollbarThemeData readerScrollbarTheme(ReaderPalette palette) {
  return ScrollbarThemeData(
    thumbColor: WidgetStatePropertyAll(palette.dim.withValues(alpha: 0.44)),
    radius: const Radius.circular(5),
    thickness: const WidgetStatePropertyAll(kReaderScrollThumb),
    // Палецът не бива да става твърде къс при дълго четиво — иначе е
    // неуловим с пръст.
    minThumbLength: 48,
    crossAxisMargin: 2,
    mainAxisMargin: 4,
  );
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

  /// Връзките и номерата на бележките.
  ///
  /// В тъмен режим това е синьото на секциите от дневния изглед. На светлия
  /// кремав фон обаче то избледнява до нечетимост — там се ползва
  /// по-наситено синьо, същото като в изнесените PDF-и (виж _linkBlue в
  /// pdf_export.dart), за да е един и същ цветът на екрана и на хартия.
  Color get link =>
      dark ? const Color(0xFF8A9BB0) : const Color(0xFF2F5C8F);

  /// Лентата на ТЕКУЩАТА глава в съдържанието.
  ///
  /// Същият тон синьо (212°) като хедъра на делничен ден в дневния изглед
  /// (`AppColors.appBarWeekday` = #2C3B4D), но по-бледо от него: в тъмния
  /// четец просветлено, в светлия — избеляло до нежен син оттенък, за да не
  /// спори с кремавия фон. Нарочно НЕ е жълтото на съвпаденията — то значи
  /// „намерено", а тук се сочи „ти си тук".
  Color get here => dark ? const Color(0xFF3F556F) : const Color(0xFFBFCEE0);

  /// Фонът на изскачащите неща ВЪРХУ страницата — подканата за връщане
  /// към прекъснато четене и всяко подобно прозорче.
  ///
  /// ⚠ СИВО в двете теми, и то нарочно: „изскочилото" се чете по разликата
  /// със страницата, не по конкретния цвят. Затова е по-СВЕТЛО от почти
  /// черната страница и по-ТЪМНО от кремавата.
  ///
  /// Дотогава тук стоеше `AppColors.toolbar` (#1A1A1A) — закован тъмен. В
  /// тъмна тема той е само с една степен по-светъл от страницата (#121212)
  /// и прозорчето се сливаше с нея; в СВЕТЛА беше същинска грешка — черно
  /// прозорче с тъмен текст върху него, защото надписите идват от [ink],
  /// който там е тъмен. Тоест нечетимо.
  Color get sheet => dark ? const Color(0xFF33322F) : const Color(0xFFDED9CC);

  /// Фонът зад намерените съвпадения при търсене в текста.
  ///
  /// ⚠ Самите цветове живеят в [AppColors] — общи са с екрана за търсене,
  /// за да свети едно и също жълто в списъка с резултати и в отвореното
  /// от него житие. Тук стои само изборът светла/тъмна.
  Color get hit => dark ? AppColors.hitDark : AppColors.hitLight;
  Color get hitCurrent =>
      dark ? AppColors.hitCurrentDark : AppColors.hitCurrentLight;

  /// Чертичките по скролбара. В светъл режим жълтото на [hit] е добро като
  /// фон зад текст, но на тънка чертичка почти изчезва — затова там е
  /// по-наситено.
  Color get tickHit => dark ? hit : const Color(0xFF9C7A1A);
  Color get tickCurrent => hitCurrent;
}
