import 'package:shared_preferences/shared_preferences.dart';

class AppSettings {
  // true = стар стил (Юлиански), false = нов стил (Григориански)
  static bool isOldStyle = true;
  // true = стар стил е водещ (вляво), false = нов стил е водещ
  static bool oldStyleFirst = true;
  // Текуща страница
  static int currentPage = 0;
  // Днешната дата (по нов стил) — постоянно маркирана
  static DateTime? today;
  // Временен flash при навигация до дата
  static DateTime? flashDate;

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
}
