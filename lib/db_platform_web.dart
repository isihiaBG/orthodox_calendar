// В браузъра SQLite идва като WASM (`web/sqlite3.wasm`) и работи в shared
// worker (`web/sqflite_sw.js`); базите живеят в IndexedDB. Двата файла се
// слагат в `web/` с `dart run sqflite_common_ffi_web:setup`. Виж
// db_platform.dart.
import 'package:sqflite/sqflite.dart' show databaseFactory;
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

void initDatabasePlatform() {
  databaseFactory = databaseFactoryFfiWeb;
}
