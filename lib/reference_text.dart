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

import 'dart:convert' show HtmlEscape, HtmlEscapeMode;

import 'database_helper.dart';
import 'saint_expandable_tile.dart' show SaintTexts;

/// Представка на слъговете от справочника: `ref-<id на статията>`.
const String kReferenceSlugPrefix = 'ref-';

/// Представка на бележките под линия от „Мисли от Теофан Затворник":
/// `teofan-note-*5`. Ключът е такъв, какъвто е в книгата — авторовите
/// бележки са „*5", редакционните са само число.
const String kTeofanNoteSlugPrefix = 'teofan-note-';

/// Многодневните пости — само те стават за „започналия/предстоящия … пост".
/// Период 1 е обикновен постен ден (сряда/петък), 0 е блажене.
const Set<int> _multiDayFastPeriods = {2, 3, 4, 5};

const String _fastPlaceholder = '⟦пост⟧';

bool isReferenceSlug(String slug) => slug.startsWith(kReferenceSlugPrefix);

bool isTeofanNoteSlug(String slug) =>
    slug.startsWith(kTeofanNoteSlugPrefix);

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

/// Бележка под линия от мислите на свт. Теофан, по слъг `teofan-note-*5`.
///
/// Текстът в базата е ЧИСТ (без разметка) — там влиза така от
/// 02b_translate_notes.py. Затова се обвива в <p> тук: четецът рисува
/// тялото през flutter_html и без таг би получил един слепен ред.
Future<SaintTexts?> loadTeofanNote(String slug) async {
  final key = slug.substring(kTeofanNoteSlugPrefix.length);
  if (key.isEmpty) return null;
  try {
    final db = await DatabaseHelper.teofanDatabase;
    final rows = await db.query('notes',
        columns: ['body'], where: 'key = ?', whereArgs: [key], limit: 1);
    if (rows.isEmpty) return null;
    final body = (rows.first['body'] as String).trim();
    return SaintTexts(
      name: 'Бележка',
      sluzhba: '<p>${const HtmlEscape(HtmlEscapeMode.element).convert(body)}</p>',
      slug: slug,
    );
  } catch (e) {
    debugPrint('[teofan] не можах да заредя бележка $slug: $e');
    return null;
  }
}
