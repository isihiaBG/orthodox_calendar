// asset_db.dart
//
// ЕДНО място, което слага база от `assets/db/` там, откъдето SQLite може да я
// отвори — на телефона и в браузъра.
//
// ⚠⚠ ЗАЩО ИЗОБЩО Е ОТДЕЛНО. Дотук всяка от базите се копираше с `dart:io`
// (`File.exists` → `delete` → `writeAsBytes`), преписано на девет места в
// четири файла. В браузъра `dart:io` компилира, но гърми при изпълнение —
// тъй че уеб версията падаше още ПРЕДИ SQLite и отвън се виждаше само
// вечният спинер. Сега всичко минава през `databaseFactory`
// (`writeDatabaseBytes`, `databaseExists`), което знае и двата свята: на
// телефона пише файл (буквално като досегашния код — създава папката и
// пише), в браузъра — в IndexedDB през WASM SQLite.
//
// ⚠ КОПИРА СЕ ВЕДНЪЖ НА СЕСИЯ. Досегашното „винаги презаписва" имаше смисъл
// само при ПУСКАНЕ — за да стигне поправка в `assets/db/` до устройството, —
// а базите се отварят многократно в една сесия (календарната се затваря
// след 3 сек. покой и се отваря наново при следващото прелистване). Всяко
// отваряне значеше ново копие на calendar_*.db И на 30-мегабайтовата
// lives.db. Assets се менят само с нов билд, тоест с нова сесия, така че
// обещанието остава същото. Базите се четат само — сверено: никъде в
// `lib/` няма INSERT/UPDATE/DELETE върху тях.
//
// ⚠ В БРАУЗЪРА — и между сесии, по ОТПЕЧАТЪК. Там „копие" значи запис на
// десетки мегабайти в IndexedDB при всяко отваряне на страницата. Затова
// байтовете от assets се сравняват по отпечатък с последно записаните и се
// пише само при разлика.

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

/// Кои бази вече са копирани в тази сесия.
final Set<String> _copied = {};

/// Текущите копирания — две едновременни повиквания за една и съща база
/// чакат едно и също, вместо да пишат файла два пъти наведнъж.
final Map<String, Future<String>> _inFlight = {};

/// Пътят, под който живее базата [name].
///
/// ⚠ В браузъра е ГОЛО ИМЕ: там няма файлова система, а SQLite пише в
/// IndexedDB под това име. ATTACH също го приема като име.
Future<String> assetDatabasePath(String name) async =>
    kIsWeb ? name : p.join(await getDatabasesPath(), name);

/// Слага `assets/db/<name>` на мястото му и връща пътя.
Future<String> ensureAssetDatabase(String name) {
  if (_copied.contains(name)) return assetDatabasePath(name);
  // ⚠⚠ ТЯЛО С ФИГУРНИ СКОБИ, НЕ `=>`. `remove` ВРЪЩА премахнатото — тоест
  // самия този Future, — а `whenComplete` чака Future-а, върнат от
  // функцията си. Със стрелка копирането чакаше само себе си ЗАВИНАГИ:
  // „done" се изписваше, а викащият висеше на спинера. (Хванато на уеб,
  // 27.09.2026; щеше да заключи и телефона.)
  return _inFlight[name] ??= _copy(name).whenComplete(() {
    _inFlight.remove(name);
  });
}

/// Отваря база от assets (по подразбиране само за четене).
Future<Database> openAssetDatabase(String name, {bool readOnly = true}) async {
  final path = await ensureAssetDatabase(name);
  return openDatabase(path, readOnly: readOnly);
}

Future<String> _copy(String name) async {
  final path = await assetDatabasePath(name);
  final data = await rootBundle.load('assets/db/$name');
  final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);

  if (kIsWeb) {
    final prefs = await SharedPreferences.getInstance();
    final key = 'web_db_sig_$name';
    final sig = _signature(bytes);
    if (prefs.getString(key) == sig && await databaseExists(path)) {
      _copied.add(name);
      return path;
    }
    await databaseFactory.writeDatabaseBytes(path, bytes);
    await prefs.setString(key, sig);
  } else {
    // ⚠ Презаписът е безопасен: пише се само веднъж на сесия, тоест преди
    // първото отваряне на тази база — отворена връзка към нея още няма.
    await databaseFactory.writeDatabaseBytes(path, bytes);
  }
  _copied.add(name);
  return path;
}

/// Отпечатък на съдържанието: дължина + FNV-1a върху извадка.
///
/// ⚠ ИЗВАДКА, не целият файл: хеш на 30 MB в браузъра се бави осезаемо, а
/// за отговора „това ли е същото издание" стига. Страниците на SQLite са по
/// 4 KB и всяка промяна пренаписва поне една цяла страница, тъй че стъпката
/// (1021 — просто число, за да не се нарежда със страниците) я улучва с
/// голяма вероятност; дължината хваща всичко, което добавя или маха
/// страници. Заглавието на базата (първите 100 байта, с брояча на
/// промените) влиза изцяло.
String _signature(List<int> b) {
  var h = 0x811c9dc5;
  void mix(int v) {
    h ^= v;
    h = (h * 0x01000193) & 0xffffffff;
  }

  final head = b.length < 100 ? b.length : 100;
  for (var i = 0; i < head; i++) {
    mix(b[i]);
  }
  for (var i = head; i < b.length; i += 1021) {
    mix(b[i]);
  }
  return '${b.length}:${h.toRadixString(16)}';
}
