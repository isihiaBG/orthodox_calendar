import 'package:flutter/services.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'dart:io';
import 'app_settings.dart';

class DatabaseHelper {
  static Database? _database;
  static bool _initializing = false;
  static bool? _lastStyle;

  // Кеш за периоди и типове пост
  static Map<int, String> fastPeriods = {};
  static Map<int, String> fastTypes = {};

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

  static Future<Database> _initDatabase() async {
    final dbName = AppSettings.isOldStyle ? 'calendar_old.db' : 'calendar_new.db';
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, dbName);

    if (await File(path).exists()) {
      await File(path).delete();
    }

    final data = await rootBundle.load('assets/db/$dbName');
    final bytes = data.buffer.asUint8List();
    await File(path).writeAsBytes(bytes);

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
  }
}
