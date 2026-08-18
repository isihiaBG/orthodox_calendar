import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:shared_preferences/shared_preferences.dart';

class AppSettings {
  // true = стар стил (Юлиански), false = нов стил (Григориански)
  static bool isOldStyle = true;
  // true = стар стил е водещ (вляво), false = нов стил е водещ.
  // По подразбиране нов стил, защото повечето хора очакват точно него.
  static bool oldStyleFirst = false;

  /// Показва ли се въвеждащият екран с изборa на стил при стартиране.
  ///
  /// По подразбиране ДА: човек, който отваря календара за пръв път, трябва
  /// да реши по кой стил да го чете, а това решение не бива да е скрито в
  /// настройките зад таблица, която вече е избрала вместо него.
  ///
  /// Изключва се от чекбокса на самия екран или от суича в настройките —
  /// двете пипат едно и също поле.
  static bool showWelcome = true;
  // Текуща страница
  static int currentPage = 0;
  // Днешната дата (по нов стил) — постоянно маркирана
  static DateTime? today;
  // Временен flash при навигация до дата
  static DateTime? flashDate;

  /// Кой светия да просветне в ДНЕВНИЯ изглед — `saints.id` от избрания
  /// резултат в търсенето. Месечният изглед флашва цял ред (един ден), а
  /// там датата стига; в дневния на един ден се падат по няколко светии и
  /// трябва да се знае кой точно е бил търсен.
  ///
  /// ⚠ ValueNotifier, а НЕ обикновено поле като [flashDate]. Флашът е
  /// сигнал, не начално състояние: дневните страници живеят в PageView и
  /// съседните вече са построени: за тях `initState` няма да се повика
  /// втори път и прочетена веднъж стойност би останала невидяна. Всеки
  /// ден слуша и просветва онзи от своите светии, чийто id дойде.
  static final ValueNotifier<int?> flashSaintId = ValueNotifier<int?>(null);

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
  static const String _kShowWelcome = 'settings_show_welcome';

  /// Зарежда запазените настройки. Вика се ВЕДНЪЖ, преди runApp (виж
  /// main.dart) — базата данни се избира според isOldStyle, така че
  /// стойността трябва да е известна още преди първото ѝ отваряне.
  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    isOldStyle = prefs.getBool(_kIsOldStyle) ?? isOldStyle;
    oldStyleFirst = prefs.getBool(_kOldStyleFirst) ?? oldStyleFirst;
    showWelcome = prefs.getBool(_kShowWelcome) ?? showWelcome;
  }

  static Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kIsOldStyle, isOldStyle);
    await prefs.setBool(_kOldStyleFirst, oldStyleFirst);
    await prefs.setBool(_kShowWelcome, showWelcome);
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
