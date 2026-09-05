// Разгъване на СВИТИЯ локатор в споделен адрес.
//
// ⚠⚠ ЗАЩО ИЗОБЩО СЕ СВИВА. Локаторът е най-дългото поле в адреса и с разлика:
// слъгът „sv-kirill-konstantin-filosof" е 29 от 81-те байта на пакета, а
// пътят до том — над шейсет. Свит до четири байта (житие) или до „том/глава"
// (книга), адресът пада от 156 на около 70 знака.
// (Искане на потребителя, 05.09.2026: „да не е толкова дълъг".)
//
// ⚠ Свиването е НЕОБРАТИМО без данните: отпечатъкът на слъга се разгъва само
// като се обходят всички слъгове, а „09" — само срещу картата на томовете.
// Затова [parseQuoteLink] оставя МАРКЕР (виж [kLocatorMarker]), а истинският
// локатор се възстановява тук, преди четивото да се отвори.

import 'package:sqflite/sqflite.dart';

import 'database_helper.dart';
import 'library_screen.dart' show kEpubOf;
import 'quote_link.dart';
import 'quotes.dart';

/// Връща адрес с истински локатор. Немаркиран адрес се връща непокътнат.
///
/// ⚠ Не се ли разгъне, връща се какъвто е — маркерът няма да съвпадне с нищо
/// и повикващият ще каже „това четиво го няма", което Е верният отговор:
/// слъгът наистина липсва в тази версия на базата.
Future<QuoteAnchor> resolveQuoteLocator(QuoteAnchor a) async {
  if (!a.locator.startsWith(kLocatorMarker)) return a;
  final body = a.locator.substring(kLocatorMarker.length);

  final String? real = switch (a.source) {
    QuoteSource.life => await _slugForFingerprint(body),
    QuoteSource.book => _bookLocator(body),
    QuoteSource.bible => null,
  };
  if (real == null) return a;

  return QuoteAnchor(
    source: a.source,
    locator: real,
    block: a.block,
    charStart: a.charStart,
    charLength: a.charLength,
    blockEnd: a.blockEnd,
    charEnd: a.charEnd,
    occurrence: a.occurrence,
    occurrenceTotal: a.occurrenceTotal,
  );
}

/// „09/397" → „assets/books/…09(сеп)….epub|Text/index_split_397.xhtml".
///
/// ⚠ Номерът на главата се допълва до ТРИ цифри — така се казват файловете в
/// томовете (проверено срещу всичките дванайсет: 141 записа в първия, нито
/// един с друга форма).
String? _bookLocator(String body) {
  final parts = body.split('/');
  if (parts.length != 2) return null;
  final path = kEpubOf[parts[0]];
  final ch = int.tryParse(parts[1]);
  if (path == null || ch == null) return null;
  return '$path|Text/index_split_${ch.toString().padLeft(3, '0')}.xhtml';
}

/// Кой слъг дава този отпечатък.
///
/// ⚠ ОБХОЖДАТ СЕ ВСИЧКИ, а не се търси по индекс — отпечатъкът не е обратим.
/// Цената е една заявка и няколко хиляди хеша, тоест милисекунди, и то само
/// когато се отваря дошъл отвън линк.
///
/// ⚠ Гледат се и справочните статии: те също се четат в четеца на жития и
/// също могат да бъдат цитирани, а слъговете им („ref-12") живеят в ДРУГА
/// база, която не е ATTACH-ната към календарната.
///
/// ⚠ При СБЛЪСЪК се връща първият. Четири байта при около хиляда и шестстотин
/// слъга дават под 0,03% вероятност, а последицата е отваряне на съседно
/// четиво — не срив. Проверка при сглобяването не помага: тя би гледала
/// базата на ИЗПРАЩАЧА, а решава тази на получателя.
Future<String?> _slugForFingerprint(String fp) async {
  final want = fp.toLowerCase();

  final db = await DatabaseHelper.database;
  final rows = await db.rawQuery(
      "SELECT DISTINCT slug FROM lives.texts WHERE slug IS NOT NULL AND slug <> ''");
  for (final r in rows) {
    final s = r['slug'] as String?;
    if (s != null && locatorFingerprint(s) == want) return s;
  }

  try {
    final ref = await DatabaseHelper.referenceDatabase;
    final ids = await ref.rawQuery('SELECT id FROM ref_articles');
    for (final r in ids) {
      final s = 'ref-${r['id']}';
      if (locatorFingerprint(s) == want) return s;
    }
  } on DatabaseException {
    // Справочната база я няма или е повредена — житията вече са проверени.
  }
  return null;
}
