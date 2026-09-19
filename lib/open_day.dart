// open_day.dart
//
// Отваряне на КАЛЕНДАРА на определен ден — от четиво.
//
// ⚠ Защо кука, а не пряко повикване: четецът е екран НАД календара, а
// навигацията до дата живее в състоянието на `CalendarPageView`. Пряк внос
// оттам би затворил кръг (main.dart вече внася четеца). Същият похват вече
// се ползва за `AppSettings.captureMonthMiddleDate` и за флъшването на
// избора на стил.
//
// ⚠ Куката се закача в `initState` на календара и се маха в `dispose` —
// така не остава да сочи разрушено състояние.
library;

import 'package:flutter/material.dart';

/// Закача се от календара. `null` значи „календарът не е построен".
void Function(DateTime date)? openCalendarAtDate;

/// Разпознава „day://ГГГГ-ММ-ДД" и отваря календара на този ден.
///
/// Връща `false`, ако адресът не е от този вид — тогава повикващият
/// продължава по обичайния път (Писание, външна връзка).
bool openDayLink(BuildContext context, String url) {
  if (!url.startsWith('day://')) return false;
  final d = DateTime.tryParse(url.substring('day://'.length));
  final hook = openCalendarAtDate;
  if (d == null || hook == null) return false;
  // ⚠ Първо СЕ ЗАТВАРЯТ четците над календара, чак после навигацията:
  // инак денят се сменя под тях и човек остава да гледа същото четиво.
  Navigator.of(context).popUntil((r) => r.isFirst);
  hook(DateTime(d.year, d.month, d.day));
  return true;
}
