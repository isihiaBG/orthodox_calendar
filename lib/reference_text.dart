// reference_text.dart
//
// Общото между секцията "Справочник" (reference_book_screen.dart) и всеки
// друг път, който може да стигне до справочна статия — най-вече списъкът с
// отметки в четеца, който отваря четиво само по неговия слъг.
//
// Две неща живеят тук, защото ТРЯБВА да важат навсякъде:
//
//  1. Разпознаването на справочните слъгове. Те са с представка "ref-" и
//     сочат към assets/db/reference.db, а не към lives.db, откъдето се
//     четат житията. Без това списъкът с отметки намираше запазената
//     статия, но не можеше да я отвори.
//
//  2. Заместването на запушалките в текста. ⟦пост⟧ се пресмята ПРИ ВСЯКО
//     отваряне (виж fastPhrase) — ако се правеше само в екрана на
//     справочника, отворената от отметките статия щеше да показва самата
//     запушалка.

import 'package:flutter/material.dart';

import 'database_helper.dart';
import 'saint_expandable_tile.dart' show SaintTexts;

/// Представка на слъговете от справочника: `ref-<id на статията>`.
const String kReferenceSlugPrefix = 'ref-';

/// Многодневните пости — само те стават за „започналия/предстоящия … пост".
/// Период 1 е обикновен постен ден (сряда/петък), 0 е блажене.
const Set<int> _multiDayFastPeriods = {2, 3, 4, 5};

const String _fastPlaceholder = '⟦пост⟧';

bool isReferenceSlug(String slug) => slug.startsWith(kReferenceSlugPrefix);

/// „започналия вече Богородичен пост" или „предстоящия Велик пост".
///
/// Нищо не се смята наново: календарната база вече носи `fast_period` за
/// всеки ден, а коя база е отворена (стар или нов стил) решава
/// DatabaseHelper. Тоест сметката сама се съобразява със стила.
Future<String> fastPhrase() async {
  try {
    final db = await DatabaseHelper.database;
    final today = DateTime.now();
    final iso = '${today.year.toString().padLeft(4, '0')}-'
        '${today.month.toString().padLeft(2, '0')}-'
        '${today.day.toString().padLeft(2, '0')}';
    final inList = _multiDayFastPeriods.join(',');

    final now = await db.rawQuery(
        'SELECT fast_period FROM calendar_days WHERE date = ? LIMIT 1', [iso]);
    if (now.isNotEmpty) {
      final p = now.first['fast_period'] as int? ?? 0;
      if (_multiDayFastPeriods.contains(p)) {
        return 'започналия вече ${DatabaseHelper.fastPeriods[p]}';
      }
    }

    var next = await db.rawQuery(
        'SELECT fast_period FROM calendar_days WHERE date > ? '
        'AND fast_period IN ($inList) ORDER BY date LIMIT 1',
        [iso]);
    // След Рождество напред в базата няма какво да се намери — тогава се
    // обръщаме към началото ѝ. Първият многодневен пост в която и да е
    // календарна година е Великият, тъй че отговорът пак е верният.
    next = next.isNotEmpty
        ? next
        : await db.rawQuery(
            'SELECT fast_period FROM calendar_days WHERE fast_period IN '
            '($inList) ORDER BY date LIMIT 1');
    if (next.isNotEmpty) {
      final p = next.first['fast_period'] as int? ?? 0;
      final name = DatabaseHelper.fastPeriods[p];
      if (name != null) return 'предстоящия $name';
    }
  } catch (e) {
    debugPrint('[reference] не можах да определя поста: $e');
  }
  // Ако нещо не потръгне, изречението пак трябва да е смислено.
  return 'предстоящия пост';
}

/// Замества запушалките в тялото на статия. Извиква се при ВСЯКО отваряне.
Future<String> expandPlaceholders(String body) async {
  if (!body.contains(_fastPlaceholder)) return body;
  return body.replaceAll(_fastPlaceholder, await fastPhrase());
}

/// Статия от справочника по слъг ("ref-12") — вече с разгънати запушалки.
Future<SaintTexts?> loadReferenceArticle(String slug) async {
  final id = int.tryParse(slug.substring(kReferenceSlugPrefix.length));
  if (id == null) return null;
  try {
    final db = await DatabaseHelper.referenceDatabase;
    final rows = await db.query('ref_articles',
        columns: ['title', 'body'], where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return SaintTexts(
      name: rows.first['title'] as String,
      sluzhba: await expandPlaceholders(rows.first['body'] as String),
      slug: slug,
    );
  } catch (e) {
    debugPrint('[reference] не можах да заредя статия $slug: $e');
    return null;
  }
}
