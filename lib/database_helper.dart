import 'package:flutter/services.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'app_settings.dart';

class DatabaseHelper {
  static Database? _database;
  static bool _initializing = false;
  static bool? _lastStyle;

  // Кеш за периоди и типове пост
  static Map<int, String> fastPeriods = {};
  static Map<int, String> fastTypes = {};

  // Реалните граници на наличните данни в текущо отворената база
  // (винаги по нов стил, защото calendar_days.date е по нов стил).
  // Изчисляват се динамично при всяко (пре)отваряне на базата — затова
  // винаги отразяват действителното съдържание, без значение колко
  // години напред/назад е разширена базата при бъдещи актуализации.
  static DateTime? dataMinDate;
  static DateTime? dataMaxDate;

  static Future<Database> get database async {
    if (_database != null && _lastStyle == AppSettings.isOldStyle) {
      return _database!;
    }

    while (_initializing) {
      await Future.delayed(const Duration(milliseconds: 50));
    }

    if (_database != null && _lastStyle == AppSettings.isOldStyle) {
      return _database!;
    }

    _initializing = true;
    try {
      if (_database != null) {
        await _database!.close();
        _database = null;
      }
      _database = await _initDatabase();
      _lastStyle = AppSettings.isOldStyle;
      await _loadLookupTables(_database!);
      await _loadDataBounds(_database!);
    } finally {
      _initializing = false;
    }
    return _database!;
  }

  static Future<void> _loadLookupTables(Database db) async {
    // Зарежда fast_periods
    final periods = await db.query('fast_periods', orderBy: 'id');
    fastPeriods = {
      for (var row in periods) row['id'] as int: row['name'] as String
    };

    // Зарежда fast_types
    final types = await db.query('fast_types', orderBy: 'id');
    fastTypes = {
      for (var row in types) row['id'] as int: row['name'] as String
    };
  }

  // Изчислява реалните граници на данните в calendar_days.
  // Извиква се при всяко (пре)отваряне на базата — стар/нов стил,
  // а в бъдеще и при смяна на език — затова винаги е актуално,
  // без значение колко данни реално съдържа конкретната база.
  static Future<void> _loadDataBounds(Database db) async {
    final result = await db.rawQuery(
      'SELECT MIN(date) as min_date, MAX(date) as max_date FROM calendar_days'
    );
    if (result.isNotEmpty) {
      final minStr = result.first['min_date'] as String?;
      final maxStr = result.first['max_date'] as String?;
      dataMinDate = minStr != null ? DateTime.utc(
          int.parse(minStr.substring(0, 4)),
          int.parse(minStr.substring(5, 7)),
          int.parse(minStr.substring(8, 10))) : null;
      dataMaxDate = maxStr != null ? DateTime.utc(
          int.parse(maxStr.substring(0, 4)),
          int.parse(maxStr.substring(5, 7)),
          int.parse(maxStr.substring(8, 10))) : null;    
    } else {
      dataMinDate = null;
      dataMaxDate = null;
    }
  }

  // Името на SharedPreferences ключа, в който пазим версията на
  // последно копираната база — поотделно за всеки стил, защото
  // calendar_old.db и calendar_new.db се обновяват независимо.
  static String _versionPrefKey(String dbName) => 'db_version_$dbName';

  static Future<Database> _initDatabase() async {
    
    // print('_initDatabase started');
    final dbName = AppSettings.isOldStyle ? 'calendar_old.db' : 'calendar_new.db';
    // print('dbName: $dbName');
    final dbPath = await getDatabasesPath();
    // print('dbPath: $dbPath');
    
    // final dbName = AppSettings.isOldStyle ? 'calendar_old.db' : 'calendar_new.db';
    // final dbPath = await getDatabasesPath();
    final path = join(dbPath, dbName);

    final file = File(path);
    final fileExists = await file.exists();

    // Версията на базата в assets — текстов файл до самата база,
    // напр. assets/db/calendar_old.version, съдържащ само число.
    // Увеличава се ръчно само когато реално подмениш .db файла
    // с нова версия на данните (нов extract/clean/import).
    String assetVersion = '0';
    try {
      assetVersion = (await rootBundle.loadString('assets/db/$dbName.version')).trim();
    } catch (_) {
      // Ако няма version файл — третираме като версия "0" (винаги презаписва).
    }

    final prefs = await SharedPreferences.getInstance();
    final savedVersion = prefs.getString(_versionPrefKey(dbName));

    //final needsCopy = !fileExists || savedVersion != assetVersion;
    final needsCopy = true; // винаги презаписва
    
    // print('dbName: $dbName.version');
    // print('assetVersion: $assetVersion');
    // print('savedVersion: $savedVersion');
    // print('needsCopy: $needsCopy');
    
    if (needsCopy) {
      if (fileExists) {
        await file.delete();
      }
      final data = await rootBundle.load('assets/db/$dbName');
      final bytes = data.buffer.asUint8List();
      await file.writeAsBytes(bytes);
      await prefs.setString(_versionPrefKey(dbName), assetVersion);
    }

    return await openDatabase(path);
  }

  static Future<void> resetDatabase() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
    _lastStyle = null;
    fastPeriods = {};
    fastTypes = {};
    dataMinDate = null;
    dataMaxDate = null;
  }
}
