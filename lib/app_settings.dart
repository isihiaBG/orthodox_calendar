import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

class AppSettings {
  // true = стар стил (Юлиански), false = нов стил (Григориански)
  static bool isOldStyle = true;
  // true = стар стил е водещ (вляво), false = нов стил е водещ.
  // По подразбиране нов стил, защото повечето хора очакват точно него.
  static bool oldStyleFirst = false;
  // Текуща страница
  static int currentPage = 0;
  // Днешната дата (по нов стил) — постоянно маркирана
  static DateTime? today;
  // Временен flash при навигация до дата
  static DateTime? flashDate;

  /// Улавя коя дата в момента е "по средата" на месечния изглед — вика се
  /// от settings_screen.dart ПРЕДИ да се мутира isOldStyle. Редът има
  /// значение: getMiddleDate() тълкува текущо показаните редове през
  /// призмата на isOldStyle към момента на извикването, а базата се сменя
  /// асинхронно — ако го извикаме СЛЕД мутацията, ще тълкува старите
  /// редове през новата настройка и ще върне грешен ден. Връща null
  /// извън месечен изглед (виж main.dart._CalendarPageViewState.initState).
  static DateTime? Function()? captureMonthMiddleDate;

  // --- Запис в потребителските настройки -----------------------------
  // Пазят се САМО двете реални настройки (стил и кой е водещ). Останалите
  // полета горе са сесийно състояние (текуща страница, flash) — те нямат
  // работа на диска.
  static const String _kIsOldStyle = 'settings_is_old_style';
  static const String _kOldStyleFirst = 'settings_old_style_first';

  /// Зарежда запазените настройки. Вика се ВЕДНЪЖ, преди runApp (виж
  /// main.dart) — базата данни се избира според isOldStyle, така че
  /// стойността трябва да е известна още преди първото ѝ отваряне.
  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    isOldStyle = prefs.getBool(_kIsOldStyle) ?? isOldStyle;
    oldStyleFirst = prefs.getBool(_kOldStyleFirst) ?? oldStyleFirst;
  }

  static Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kIsOldStyle, isOldStyle);
    await prefs.setBool(_kOldStyleFirst, oldStyleFirst);
  }

  // --- Отложен запис ---------------------------------------------------
  // Потребителят може просто да разцъква настройките напред-назад за да
  // види как се променя изгледът "на живо" — това НЕ трябва да удря
  // диска при всяко тапване. scheduleSave() отлага записа; всяко ново
  // повикване презарежда таймера. saveNow() пише веднага и се вика при
  // затваряне на панела с настройки (виж onEndDrawerChanged в main.dart
  // и app_drawer.dart), за да не се изгуби последната промяна.
  static Timer? _saveDebounce;

  static void scheduleSave({Duration delay = const Duration(seconds: 2)}) {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(delay, save);
  }

  static Future<void> saveNow() async {
    _saveDebounce?.cancel();
    _saveDebounce = null;
    await save();
  }
}
