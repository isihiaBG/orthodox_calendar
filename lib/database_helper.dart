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

  // Житията, службите и молитвите живеят в ОТДЕЛНА база, обща за двата
  // стила. Причината: текстът за св. Атанасий Атонски не зависи нито от
  // стила, нито от годината — календарът зависи, текстът не. Ако стоеше
  // в календара, щеше да е дублиран и в calendar_old.db, и в
  // calendar_new.db, а догодина — още веднъж във всяка нова.
  //
  // Връзката е slug. Календарен ред без slug просто няма партньор:
  // LEFT JOIN връща NULL и в приложението нищо не се показва — точно
  // както беше при празни колони.
  static const String _livesDbName = 'lives.db';

  // Четивата за секцията "Справочник" (указания, пояснения, речник) —
  // трета, отделна база. Не се ATTACH-ва към календарната: с нея няма
  // какво да се JOIN-ва, а и не зависи нито от стила, нито от годината,
  // тъй че живее на собствена връзка, отваряна при първа нужда.
  static const String _referenceDbName = 'reference.db';
  static Database? _referenceDatabase;

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

  /// Осигурява lives.db на диска и връща пътя до нея.
  /// Копира се веднъж — обща е за двата стила, затова не зависи от
  /// AppSettings.isOldStyle.
  static Future<String> _ensureLivesDb() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, _livesDbName);
    final file = File(path);

    String assetVersion = '0';
    try {
      assetVersion =
          (await rootBundle.loadString('assets/db/$_livesDbName.version')).trim();
    } catch (_) {
      // няма version файл → третираме като "0"
    }

    final prefs = await SharedPreferences.getInstance();
    final savedVersion = prefs.getString(_versionPrefKey(_livesDbName));

    //final needsCopy = !await file.exists() || savedVersion != assetVersion;
    final needsCopy = true; // винаги презаписва (както при календара)

    if (needsCopy) {
      if (await file.exists()) {
        await file.delete();
      }
      final data = await rootBundle.load('assets/db/$_livesDbName');
      await file.writeAsBytes(data.buffer.asUint8List());
      await prefs.setString(_versionPrefKey(_livesDbName), assetVersion);
    }
    return path;
  }

  /// Базата на "Справочник" — копира се от assets при първо повикване,
  /// по същия ред като lives.db, и остава отворена за сесията.
  static Future<Database> get referenceDatabase async {
    if (_referenceDatabase != null) return _referenceDatabase!;
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, _referenceDbName);
    final file = File(path);
    if (await file.exists()) {
      await file.delete(); // винаги презаписва — както другите бази
    }
    final data = await rootBundle.load('assets/db/$_referenceDbName');
    await file.writeAsBytes(data.buffer.asUint8List());
    _referenceDatabase = await openDatabase(path, readOnly: true);
    return _referenceDatabase!;
  }

  // ───────────────────────────────────────────────────────────────────────
  // „Мисли от Теофан Затворник" — четвърта, отделна база.
  //
  // Не се ATTACH-ва, както и reference.db: не зависи нито от стила, нито от
  // годината. Причината е, че поученията НЕ се адресират по дата, а по
  // литургичен адрес — „Неделя на Митаря и Фарисея", „петък от седмица 12
  // след Петдесетница", „6 януари". Свт. Теофан ги е писал за 1887 г., но
  // самите адреси са вечни; коя дата им се пада, се смята при всяко
  // отваряне на секцията.
  // ───────────────────────────────────────────────────────────────────────
  static const String _teofanDbName = 'teofan.db';
  static Database? _teofanDatabase;

  static Future<Database> get teofanDatabase async {
    if (_teofanDatabase != null) return _teofanDatabase!;
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, _teofanDbName);
    final file = File(path);
    if (await file.exists()) {
      await file.delete(); // винаги презаписва — както другите бази
    }
    final data = await rootBundle.load('assets/db/$_teofanDbName');
    await file.writeAsBytes(data.buffer.asUint8List());
    _teofanDatabase = await openDatabase(path, readOnly: true);
    return _teofanDatabase!;
  }

  /// Юлианската Пасха за годината, върната като ГРАЖДАНСКА (григорианска)
  /// дата. Пасхалията е обща за двата стила, тъй че тази дата е една и съща
  /// и в calendar_old.db, и в calendar_new.db.
  static DateTime paschaOf(int year) {
    final a = year % 4, b = year % 7, c = year % 19;
    final d = (19 * c + 15) % 30;
    final e = (2 * a + 4 * b - d + 34) % 7;
    final month = (d + e + 114) ~/ 31;
    final day = (d + e + 114) % 31 + 1;
    // юлианска → григорианска, през юлианския ден (без твърдо „+13", за да
    // не се счупи през 2100 г., когато разликата става 14 дни)
    final aa = (14 - month) ~/ 12;
    final yy = year + 4800 - aa;
    final mm = month + 12 * aa - 3;
    final jdn = day + (153 * mm + 2) ~/ 5 + 365 * yy + yy ~/ 4 - 32083;
    return DateTime.utc(1970, 1, 1).add(Duration(days: jdn - 2440588));
  }

  /// Мисълта на свт. Теофан за деня — готово HTML тяло, или null.
  ///
  /// Книгата не покрива всеки ден от всяка година: тя има 353 поучения за
  /// една конкретна църковна година, а броят на седмиците между
  /// Петдесетница и Триода се мени (отстъпката). Затова null е нормален
  /// отговор, не грешка.
  static Future<String?> teofanThought(DateTime date) async {
    final candidates = await _teofanCandidates(date);
    if (candidates.isEmpty) return null;

    final db = await teofanDatabase;
    // Нарочно OR, а НЕ „(kind, key) IN ((?,?),…)". Ред-стойностите работят
    // в sqlite3 на десктопа, но SQLite-ът на Android ги отхвърля с
    // „row value misused" — а меродавен е той. Проверката трябва да е на
    // устройството, не в конзолата.
    final where = List.filled(candidates.length, '(kind=? AND key=?)')
        .join(' OR ');
    final args = <Object?>[];
    for (final c in candidates) {
      args..add(c.$1)..add(c.$2);
    }
    final rows = await db.rawQuery(
      'SELECT kind, key, body FROM thoughts WHERE $where',
      args,
    );
    if (rows.isEmpty) return null;

    // Кандидатите вече са подредени по веригата на приоритета — връщаме
    // първия, който е намерил ред.
    for (final c in candidates) {
      for (final row in rows) {
        if (row['kind'] == c.$1 && row['key'] == c.$2) {
          return row['body'] as String;
        }
      }
    }
    return null;
  }

  /// Адресите-кандидати за деня, подредени по веригата на приоритета:
  ///
  ///   1 Господски празник     печели над всичко, включително над неделята
  ///   2 подвижен спрямо Пасха Триод и Пентикостар
  ///   3 неделя                по Петдесетница или спрямо неподвижен празник
  ///   4 Богородичен/светийски под неделята — всяка неделя е малка Пасха
  ///   5 делник по седмица     броене напред от Петдесетница
  static Future<List<(String, String)>> _teofanCandidates(DateTime date) async {
    final out = <(String, String)>[];

    // Църковната дата. По нов стил съвпада с гражданската; по стар изостава
    // с 13 дни (предпразненството на Рождество е 20.XII църковно = 2.I
    // гражданско в calendar_old.db).
    final church = AppSettings.isOldStyle
        ? date.subtract(const Duration(days: 13))
        : date;
    final mmdd = '${church.month.toString().padLeft(2, '0')}-'
        '${church.day.toString().padLeft(2, '0')}';

    final pascha = paschaOf(date.year);
    final offset = DateTime.utc(date.year, date.month, date.day)
        .difference(DateTime.utc(pascha.year, pascha.month, pascha.day))
        .inDays;

    // ── 1. Господски празници ────────────────────────────────────────────
    const lordly = {'01-01', '01-06', '02-02', '08-06', '09-14', '12-25'};
    if (lordly.contains(mmdd)) out.add(('fixed', mmdd));
    if (offset == 39) out.add(('pascha', '39')); // Възнесение

    // ── 2. Подвижни спрямо Пасха ─────────────────────────────────────────
    // От Митаря и Фарисея (-70) до съботата подир Всички светии (+62).
    if (offset >= -70 && offset <= 62) out.add(('pascha', '$offset'));

    // ── 3-5. Седмица, неделя и котвите — от календарната база ────────────
    final key = '${date.year}-${date.month.toString().padLeft(2, '0')}'
        '-${date.day.toString().padLeft(2, '0')}';
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT w.name AS week, s.name AS sunday,
             (SELECT group_concat(name, '|') FROM saints WHERE date = d.date)
               AS saints
      FROM calendar_days d
      LEFT JOIN weeks w ON w.id = d.week_id
      LEFT JOIN sundays s ON s.id = d.sunday_id
      WHERE d.date = ?
      LIMIT 1
    ''', [key]);
    if (rows.isEmpty) return out;

    final week = rows.first['week'] as String?;
    final sunday = rows.first['sunday'] as String?;
    final saints = (rows.first['saints'] as String?) ?? '';

    // ── 3. Неделите и котвите ────────────────────────────────────────────
    if (sunday != null) {
      if (sunday.contains('преди Богоявление')) {
        out.add(('anchor', 'sunday_before_theophany'));
      } else if (sunday.contains('след Богоявление')) {
        out.add(('anchor', 'sunday_after_theophany'));
      }
      if (sunday.contains('Праотци')) out.add(('anchor', 'forefathers'));
      final n = RegExp(r'Неделя (\d+) след Петдесетница').firstMatch(sunday);
      if (n != null) out.add(('pent', 'sunday:${n.group(1)}'));
    }
    if (saints.contains('Събота преди Богоявление')) {
      out.add(('anchor', 'saturday_before_theophany'));
    } else if (saints.contains('Събота след Богоявление')) {
      out.add(('anchor', 'saturday_after_theophany'));
    }

    // ── 4. Богородичните и светийските неподвижни ────────────────────────
    const lesser = {'01-07', '08-15', '11-21'};
    if (lesser.contains(mmdd)) out.add(('fixed', mmdd));

    // ── 5. Делник по седмица след Петдесетница ───────────────────────────
    if (week != null && date.weekday >= DateTime.monday &&
        date.weekday <= DateTime.saturday) {
      final n = RegExp(r'Седмица (\d+) след Петдесетница').firstMatch(week);
      if (n != null) out.add(('pent', '${n.group(1)}:${date.weekday}'));
    }

    return out;
  }

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

    final livesPath = await _ensureLivesDb();
    final db = await openDatabase(path);

    // ATTACH прикачва втората база към същата връзка — оттук нататък
    // заявките могат да JOIN-ват през двете, все едно са в една база:
    //     LEFT JOIN lives.texts l ON l.slug = s.slug
    // Прикачването е за ВРЪЗКАТА, не за файла; при всяко преотваряне
    // (смяна на стила) минава оттук наново, тъй че е автоматично.
    await db.execute("ATTACH DATABASE ? AS lives", [livesPath]);

    return db;
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
