// book_last_read_store.dart
//
// Кое житие е било отваряно последно във всеки том.
//
// ⚠ ОТДЕЛНО от [BookPositionStore] и напълно независимо от отметките.
// Онзи пази ДОКЪДЕ е стигнал човек в едно четиво (абзац и знак), но само
// за жития С ОТМЕТКА — няма отметка, нищо не се записва. Тъй че от него не
// може да се извлече „последно отваряното": ако човек чете, без да
// отбелязва, там няма да има нито един запис.
//
// Тук се пази САМО кое е четивото, без позиция в него. Опашката под
// заглавната страница отваря житието от НАЧАЛОТО; ако то има отметка,
// обичайната подкана за връщане изскача както при всяко друго отваряне.
// Двете подредби не се знаят една друга и това е нарочно.
//
// Ползватели:
//   • опашката на заглавната страница — текстът ѝ и накъде води;
//   • съдържанието — кой ред да е маркиран и до кой да се скролне.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Последно отваряното четиво в един том.
@immutable
class LastRead {
  /// Индекс в списъка с ГЛАВИ (тези от съдържанието), не в spine-а —
  /// същата номерация като [BookPosition.chapter].
  final int chapter;

  /// Пътят на главата в архива. Пази се заедно с индекса, защото индексът
  /// сам по себе си не е устойчив: прегенериране на тома може да размести
  /// съдържанието. При разминаване href-ът е меродавен.
  final String href;

  /// Заглавието — за да може опашката да каже къде връща, без да отваря
  /// архива само за да го прочете.
  final String title;

  const LastRead({
    required this.chapter,
    required this.href,
    required this.title,
  });

  Map<String, dynamic> toJson() => {
        'chapter': chapter,
        'href': href,
        'title': title,
      };

  factory LastRead.fromJson(Map<String, dynamic> j) => LastRead(
        chapter: (j['chapter'] as num?)?.toInt() ?? 0,
        href: (j['href'] as String?) ?? '',
        title: (j['title'] as String?) ?? '',
      );
}

class BookLastReadStore {
  BookLastReadStore._();

  static const String _prefix = 'book_last_';

  static String _key(String assetPath) => '$_prefix$assetPath';

  static Future<LastRead?> load(String assetPath) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _key(assetPath);
    final raw = prefs.getString(key);
    if (raw == null) return null;
    try {
      // ⚠ JSON, а не плосък запис с разделител: заглавията са изречения с
      // интервали („Памет на св. Иван Рилски"), тъй че разцепване по знак
      // ги накъсва.
      return LastRead.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (e) {
      // Повреден запис не бива да чупи отварянето на тома — по-добре
      // опашката да каже „към първото четиво", отколкото книгата да не се
      // отвори.
      debugPrint('[book_last] повреден запис за $key: $e');
      await prefs.remove(key);
      return null;
    }
  }

  /// ⚠ Заглавната страница НЕ се записва: тя не е четиво и „връщане" към
  /// нея няма смисъл. Пази се само глава с индекс над нулевия.
  static Future<void> save(String assetPath, LastRead value) async {
    if (value.chapter <= 0) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(assetPath), jsonEncode(value.toJson()));
  }

  static Future<void> clear(String assetPath) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(assetPath));
  }
}
