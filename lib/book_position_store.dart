// book_position_store.dart
//
// Докъде е стигнал читателят във всяка книга — глава и отместване в нея.
//
// Отделно от отметките на житията (_BookmarkStore в reader_screen.dart),
// защото позицията в книга е ДРУГО НЕЩО: там е индекс на регион в едно
// четиво, тук са глава + пиксели в нея. Общото между двете — прозорчето с
// обратното броене — вече е изнесено в reader_resume_prompt.dart.
//
// Ключът е пътят до тома в assets ПЛЮС пътя на главата вътре в него.
//
// Отметката е на ниво ЖИТИЕ, не на ниво том — един том носи стотици жития и
// една обща отметка за цялата книга би значела, че отбелязването на второто
// житие мълчаливо изтрива мястото в първото. Освен това бутонът за отметка
// в лентата показва състоянието на ТЕКУЩОТО четиво; при обща отметка той
// светеше и в жития, които човек изобщо не е отбелязвал.
//
// И двете части са устойчиви: не зависят от заглавието (то се мени при
// поправка в превода) и не зависят от реда в библиотеката.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BookPosition {
  /// Индекс в списъка с ГЛАВИ (тези от съдържанието), не в spine-а.
  final int chapter;

  /// Отместване в пиксели вътре в главата.
  ///
  /// ⚠ ОСТАРЯЛО. Пазено само за да се четат стари записи: пикселът зависи от
  /// размера на шрифта, тъй че записан при един размер, при друг сочи
  /// другаде. Новите записи носят [region] и [charInRegion] — виж тях.
  final double offset;

  /// Абзац в главата и индекс на ЗНАКА в него — първата буква на най-горния
  /// видим ред в мига на записа.
  ///
  /// Това е инвариантното: не се мени при смяна на шрифта, ширината или
  /// завъртането. Редът и пикселът се смятат наново при отваряне (виж
  /// text_line_locator.dart). -1 значи „няма такъв запис" (стар формат).
  final int region;
  final int charInRegion;

  /// Заглавието на главата — за да може прозорчето да каже къде връща.
  final String chapterTitle;

  /// Денят, под който стои това четиво в съдържанието („Памет на 1 август").
  /// Заглавието на житието само по себе си не казва кога се чете, а в
  /// списъка с отметки двете заедно се четат като адрес.
  final String parentTitle;

  final int savedAtMs;

  const BookPosition({
    required this.chapter,
    required this.offset,
    this.region = -1,
    this.charInRegion = 0,
    required this.chapterTitle,
    this.parentTitle = '',
    required this.savedAtMs,
  });

  Map<String, dynamic> toJson() => {
        'chapter': chapter,
        'offset': offset,
        'region': region,
        'charInRegion': charInRegion,
        'chapterTitle': chapterTitle,
        'parentTitle': parentTitle,
        'savedAtMs': savedAtMs,
      };

  static BookPosition? fromJson(Map<String, dynamic> m) {
    final chapter = m['chapter'];
    if (chapter is! int) return null;
    return BookPosition(
      chapter: chapter,
      offset: (m['offset'] as num?)?.toDouble() ?? 0,
      region: m['region'] is int ? m['region'] as int : -1,
      charInRegion: m['charInRegion'] is int ? m['charInRegion'] as int : 0,
      chapterTitle: m['chapterTitle'] as String? ?? '',
      parentTitle: m['parentTitle'] as String? ?? '',
      savedAtMs: m['savedAtMs'] is int ? m['savedAtMs'] as int : 0,
    );
  }
}

class BookPositionStore {
  BookPositionStore._();

  static const String _prefix = 'book_pos_';

  static String _key(String assetPath, String chapterHref) =>
      '$_prefix$assetPath|$chapterHref';

  static Future<BookPosition?> load(String assetPath, String chapterHref) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _key(assetPath, chapterHref);
    try {
      final raw = prefs.getString(key);
      if (raw == null) return null;
      return BookPosition.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (e) {
      // Повреден или несъвместим стар запис — трием го, вместо да чупим
      // отварянето на книгата.
      debugPrint('[book_pos] повреден запис за $key: $e');
      await prefs.remove(key);
      return null;
    }
  }

  static Future<void> save(
      String assetPath, String chapterHref, BookPosition pos) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _key(assetPath, chapterHref), jsonEncode(pos.toJson()));
  }

  static Future<void> clear(String assetPath, String chapterHref) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(assetPath, chapterHref));
  }

  /// Всички запазени позиции — за общия списък с отметки.
  ///
  /// Ключът носи два пътя, разделени с „|": на тома в assets и на главата
  /// вътре в него. Записите от СТАРАТА подредба (без „|", една отметка за
  /// цял том) се прескачат — те и без друго вече не се четат никъде.
  static Future<List<({String assetPath, String href, BookPosition pos})>>
      loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final out = <({String assetPath, String href, BookPosition pos})>[];
    for (final key in prefs.getKeys()) {
      if (!key.startsWith(_prefix)) continue;
      final rest = key.substring(_prefix.length);
      final sep = rest.lastIndexOf('|');
      if (sep <= 0) continue;
      try {
        final raw = prefs.getString(key);
        if (raw == null) continue;
        final pos =
            BookPosition.fromJson(jsonDecode(raw) as Map<String, dynamic>);
        if (pos == null) continue;
        out.add((
          assetPath: rest.substring(0, sep),
          href: rest.substring(sep + 1),
          pos: pos,
        ));
      } catch (e) {
        debugPrint('[book_pos] повреден запис за $key: $e');
      }
    }
    return out;
  }

  /// Изтрива запис от старата подредба (една отметка за цял том).
  ///
  /// Такива останаха у хората, пробвали четеца преди отметките да слязат на
  /// ниво житие. Без това те висят в настройките завинаги, невидими и
  /// недостижими.
  static Future<void> clearLegacy(String assetPath) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_prefix$assetPath');
  }
}
