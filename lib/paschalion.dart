// paschalion.dart
//
// Пасхалия — датата на Пасха за произволна година, изчислена, а не взета
// от базата. Така секциите, които зависят от Пасха (постите и подвижните
// празници), работят и за години назад/напред, извън обхвата на текущата
// календарна база.
//
// Формулата (Meeus, юлиански вариант) дава датата по ЮЛИАНСКИ календар —
// точно каквато е православната пасхалия. Гражданската (григорианска)
// дата се получава с добавяне на разликата между двата календара.

import 'app_settings.dart';

/// Разликата юлиански→григориански календар в дни за дадена година.
/// 13 дни важи за 1900–2099; формулата покрива и извън този период.
int julianGregorianOffset(int year) {
  final c = (year / 100).floor();
  return c - (c / 4).floor() - 2;
}

/// Пасха по ЮЛИАНСКИ календар (както я дава пасхалията).
({int month, int day}) paschaJulian(int year) {
  final a = year % 4;
  final b = year % 7;
  final c = year % 19;
  final d = (19 * c + 15) % 30;
  final e = (2 * a + 4 * b - d + 34) % 7;
  final month = ((d + e + 114) / 31).floor(); // 3 = март, 4 = април
  final day = ((d + e + 114) % 31) + 1;
  return (month: month, day: day);
}

/// Пасха в ГРАЖДАНСКА номерация (нов стил) — това е форматът, с който
/// работи цялото приложение (виж коментара при calendar_days.date).
DateTime paschaCivil(int year) {
  final j = paschaJulian(year);
  return DateTime.utc(year, j.month, j.day)
      .add(Duration(days: julianGregorianOffset(year)));
}

/// Църковна (юлианска) дата → гражданската, с която работи показването.
///
/// КЛЮЧОВО: отместването се прилага САМО в режим "стар стил". Тогава
/// църковната дата е различна от гражданската и двете се показват една до
/// друга. В режим "нов стил" църковният календар СЪВПАДА с гражданския —
/// затова датата се цитира каквато е, без никакво отместване.
DateTime civilFromChurch(int year, int month, int day) {
  final d = DateTime.utc(year, month, day);
  return AppSettings.isOldStyle
      ? d.add(Duration(days: julianGregorianOffset(year)))
      : d;
}
