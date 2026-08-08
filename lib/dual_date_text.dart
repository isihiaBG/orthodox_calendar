// dual_date_text.dart
//
// Показване на дата според потребителските предпочитания — само нов стил,
// или стар/нов с иконки църква/телевизор (същата конвенция като в
// месечния изглед). Изнесено тук, за да е ЕДНО И СЪЩО в "Празници",
// "Пости" и всяка бъдеща секция — иначе копията се разминават при първата
// корекция.

import 'package:flutter/material.dart';

import 'app_settings.dart';

// Съвпада с month_screen.dart._monthNamesShort — за консистентност на
// съкратените имена на месеците в цялото приложение.
const List<String> monthAbbr = [
  '', 'яну', 'фев', 'мар', 'апр', 'май', 'юни',
  'юли', 'авг', 'сеп', 'окт', 'ное', 'дек'
];

String fmtDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}.${monthAbbr[d.month]}';

/// Датата като inline-спанове: единична (чист нов стил) или двойна
/// (стар/нов). Водещата част е в основния цвят, справочната (заедно с
/// разделителя "/") — по-бледа. Иконките са НАРОЧНО малко по-големи от
/// текста, за да не изглеждат дребни до него.
///
/// civilDate е в гражданска номерация (нов стил) — старият се получава от
/// нея, както навсякъде в приложението.
List<InlineSpan> dualDateSpans(
  DateTime civilDate,
  double fontSize, {
  required Color ink,
  required Color dim,
  required String fontFamily,
}) {
  final iconSize = fontSize + 4;
  final leadStyle = TextStyle(
      color: ink,
      fontFamily: fontFamily,
      fontSize: fontSize,
      fontWeight: FontWeight.w600);
  final dimStyle = TextStyle(
      color: dim,
      fontFamily: fontFamily,
      fontSize: fontSize,
      fontWeight: FontWeight.w600);

  if (!AppSettings.isOldStyle) {
    return [TextSpan(text: fmtDate(civilDate), style: leadStyle)];
  }

  final oldStyleDate = civilDate.subtract(const Duration(days: 13));
  final oldIsLeading = AppSettings.oldStyleFirst;

  WidgetSpan iconSpan(IconData icon, Color color) => WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: Padding(
          padding: const EdgeInsets.only(right: 2),
          // Леко повдигане — само визуално подравняване спрямо текста,
          // не мести нищо друго около себе си.
          child: Transform.translate(
            offset: const Offset(0, -3),
            child: Icon(icon, size: iconSize, color: color),
          ),
        ),
      );

  if (oldIsLeading) {
    return [
      iconSpan(Icons.church, ink),
      TextSpan(text: fmtDate(oldStyleDate), style: leadStyle),
      TextSpan(text: '  /  ', style: dimStyle),
      iconSpan(Icons.live_tv, dim),
      TextSpan(text: fmtDate(civilDate), style: dimStyle),
    ];
  }
  return [
    TextSpan(text: fmtDate(civilDate), style: leadStyle),
    TextSpan(text: '  /  ', style: dimStyle),
    iconSpan(Icons.church, dim),
    TextSpan(text: fmtDate(oldStyleDate), style: dimStyle),
  ];
}

/// Същото, но за ПЕРИОД: една иконка на целия период, а не на всяка дата
/// поотделно — "dd.mmm-dd.mmm / [църква] dd.mmm-dd.mmm". Иначе редът се
/// задръства от четири иконки и трудно се чете.
List<InlineSpan> dualDateRangeSpans(
  DateTime civilStart,
  DateTime civilEnd,
  double fontSize, {
  required Color ink,
  required Color dim,
  required String fontFamily,
}) {
  final iconSize = fontSize + 4;
  final leadStyle = TextStyle(
      color: ink,
      fontFamily: fontFamily,
      fontSize: fontSize,
      fontWeight: FontWeight.w600);
  final dimStyle = TextStyle(
      color: dim,
      fontFamily: fontFamily,
      fontSize: fontSize,
      fontWeight: FontWeight.w600);

  String range(DateTime a, DateTime b) => '${fmtDate(a)}-${fmtDate(b)}';

  if (!AppSettings.isOldStyle) {
    return [TextSpan(text: range(civilStart, civilEnd), style: leadStyle)];
  }

  final oldStart = civilStart.subtract(const Duration(days: 13));
  final oldEnd = civilEnd.subtract(const Duration(days: 13));
  final oldIsLeading = AppSettings.oldStyleFirst;

  WidgetSpan iconSpan(IconData icon, Color color) => WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: Padding(
          padding: const EdgeInsets.only(right: 2),
          child: Transform.translate(
            offset: const Offset(0, -3),
            child: Icon(icon, size: iconSize, color: color),
          ),
        ),
      );

  if (oldIsLeading) {
    return [
      iconSpan(Icons.church, ink),
      TextSpan(text: range(oldStart, oldEnd), style: leadStyle),
      TextSpan(text: '  /  ', style: dimStyle),
      iconSpan(Icons.live_tv, dim),
      TextSpan(text: range(civilStart, civilEnd), style: dimStyle),
    ];
  }
  return [
    TextSpan(text: range(civilStart, civilEnd), style: leadStyle),
    TextSpan(text: '  /  ', style: dimStyle),
    iconSpan(Icons.church, dim),
    TextSpan(text: range(oldStart, oldEnd), style: dimStyle),
  ];
}
