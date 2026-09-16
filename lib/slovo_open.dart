// slovo_open.dart
//
// Отваряне на едно слово в четеца — ЕДНО място за всички повикващи.
//
// ⚠ По образеца на [openDmitryLife] в `dmitry_life.dart`. Изнесено е тук,
// защото словата вече се отварят от ДВА екрана: секцията „СЛОВА ЗА ДЕНЯ" в
// дневния изглед и плочката на празника в „Празници". Преписано на две
// места, първата поправка (друг режим, друг етикет) би ги разминала
// мълчаливо.

import 'package:flutter/material.dart';

import 'lives_plus.dart';
import 'reader_screen.dart';
import 'saint_expandable_tile.dart';

/// Отваря словото; при липсващо четиво не прави нищо.
Future<void> openSlovo(BuildContext context, Slovo s) async {
  final nav = Navigator.of(context);
  final texts = await LivesPlusDb.load(s.slug);
  if (texts == null) return;
  await nav.push(MaterialPageRoute(
    // ⚠ Режимът е `life`, не `sluzhba`: словата са свързан разказ и
    // получават буквица, както житията.
    builder: (_) => ReaderScreen.life(
      texts: texts,
      lookup: lookupBySlug,
      lifeTitle: s.title,
      typeLabel: 'Слово',
    ),
  ));
}
