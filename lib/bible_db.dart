// bible_db.dart
//
// Достъпът до `assets/db/bible.db` — Свещеното Писание за секцията „Библия".
//
// Отделна база, която НЕ се ATTACH-ва към календарната, по същия ред като
// reference.db, teofan.db и optina.db: Писанието не зависи нито от стила
// (стар/нов), нито от годината.
//
// ⚠ ЕЗИЦИТЕ СА РЕДОВЕ, НЕ КОЛОНИ. Един ред в `verses` = един стих в един
// превод. Причината е записана в tools/bible_gen/README.md, но накратко:
// преводите са 12 и списъкът не е затворен, покритието на всеки е различно
// (Септуагинтата няма Нов завет, ивритът няма второканоничните книги), а
// четецът показва по един-два наведнъж. Същият урок вече беше платен веднъж
// в този проект с осемте колони за тропари и кондаци — виж `hymns`.
//
// Оттук следва и главната работа на този файл: ПОДРАВНЯВАНЕТО. Двата
// показвани превода имат различен брой стихове и понякога различна
// номерация, тъй че редовете се сглобяват по ключ, а не по пореден номер —
// виж [alignChapter].

import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' show join;
import 'package:sqflite/sqflite.dart';

/// Книга от Писанието.
class BibleBook {
  final String code;        // „Gen", „Ps", „Mt" — ключът на източника
  final int ord;
  final String testament;   // „OT" / „NT"
  final int chapters;
  /// ⚠ ТРИ форми на името, всяка за свое място. Не ги смесвай:
  ///   [title]  „Евангелие от Матей" — заглавия, търсене
  ///   [short]  „Матей"               — списъкът в съдържанието
  ///   [abbr]   „Мат."                — хедърът на четеца и препратките
  ///
  /// Късата е отделна, защото списъкът с книги се чете на един поглед, а там
  /// „Евангелие от" се повтаря четири пъти подред и не различава нищо.
  final String title;
  final String short;
  final String abbr;

  const BibleBook({
    required this.code,
    required this.ord,
    required this.testament,
    required this.chapters,
    required this.title,
    required this.short,
    required this.abbr,
  });

  bool get isOldTestament => testament == 'OT';

  factory BibleBook.fromRow(Map<String, Object?> r) => BibleBook(
        code: r['code'] as String,
        ord: r['ord'] as int,
        testament: r['testament'] as String,
        chapters: r['chapters'] as int,
        title: r['bg_title'] as String,
        short: r['bg_short'] as String,
        abbr: r['bg_abbr'] as String,
      );
}

/// Превод.
class BibleLanguage {
  final String code;
  final int ord;
  final String title;       // „Български (синодален)"
  final String short;       // „Български"
  /// Двубуквено съкращение („бг", „цс", „ру") — за полето в лентата, където
  /// пълното име изяжда половината ширина.
  final String abbr;
  final String scope;       // „all" / „ot" / „nt"
  final String direction;   // „ltr" / „rtl"
  final String? font;       // условно име на шрифт, ако иска свой

  /// Добавка към размера на шрифта САМО за този превод.
  ///
  /// ⚠ Свойство на ШРИФТА, не на езика. Църковнославянските шрифтове са с
  /// по-ниска редова буква и при еднакъв кегел изглеждат осезаемо по-дребни
  /// от системния до тях — при паралелен изглед разликата боде. Стои при
  /// превода, защото шрифтът се избира по превод.
  final double sizeDelta;

  /// Добавка към МЕЖДУРЕДИЕТО само за този превод. Виж [sizeDelta] — пак е
  /// свойство на шрифта: цсл глифовете носят свой въздух и при общото
  /// междуредие текстът се разрежда прекомерно.
  final double lineDelta;

  /// Първата буква на стиха да се изписва в червено.
  ///
  /// ⚠ РУБРИКАЦИЯ — установеният начин за открояване на началото в
  /// славянските богослужебни книги, а не украса, хрумнала на приложението.
  /// Затова е свойство на ПРЕВОДА: важи за църковнославянския, не за текста
  /// изобщо.
  final bool rubricate;

  const BibleLanguage({
    required this.code,
    required this.ord,
    required this.title,
    required this.short,
    required this.abbr,
    required this.scope,
    required this.direction,
    this.font,
    this.sizeDelta = 0,
    this.lineDelta = 0,
    this.rubricate = false,
  });

  /// Дали този превод изобщо покрива дадената книга. Не значи, че я ИМА
  /// свалена — значи, че има смисъл да се търси.
  bool covers(BibleBook book) {
    if (scope == 'ot') return book.isOldTestament;
    if (scope == 'nt') return !book.isOldTestament;
    return true;
  }

  bool get isRtl => direction == 'rtl';

  factory BibleLanguage.fromRow(Map<String, Object?> r) => BibleLanguage(
        code: r['code'] as String,
        ord: r['ord'] as int,
        title: r['bg_title'] as String,
        short: r['bg_short'] as String,
        abbr: (r['bg_abbr'] as String?) ?? '',
        scope: (r['scope'] as String?) ?? 'all',
        direction: (r['direction'] as String?) ?? 'ltr',
        font: r['font'] as String?,
        sizeDelta: (r['size_delta'] as num?)?.toDouble() ?? 0,
        lineDelta: (r['line_delta'] as num?)?.toDouble() ?? 0,
        rubricate: (r['rubricate'] as int? ?? 0) == 1,
      );
}

/// Един стих в един превод.
class BibleVerse {
  final String verse;   // ⚠ ТЕКСТ, не число — започва от 0 при надписание
  final int ord;        // редът на показване; НЕ се извежда от номера
  final String text;
  final String? html;

  const BibleVerse({
    required this.verse,
    required this.ord,
    required this.text,
    this.html,
  });
}

/// Един РЕД от главата: номерът на стиха и текстът му във всеки от
/// показваните преводи.
///
/// Това е сърцевината на подравняването. В легнало положение редът се рисува
/// като ред от таблица — двете клетки се разтеглят по по-високата, тъй че
/// стих 5 на български и стих 5 на църковнославянски стоят един срещу друг,
/// колкото и да се различават по дължина.
class BibleRow {
  final String verse;

  /// Този ред е НАДПИСАНИЕ на псалом („Началнику на хора. Псалом Давидов."),
  /// не стих от Писанието.
  ///
  /// ⚠ Свойство на РЕДА, не на превода — затова стои тук, а не в
  /// [BibleVerse]. Източникът го бележи надеждно само в руския и в
  /// църковнославянския; те служат за указател, а стилът се прилага във
  /// всички преводи по общия ключ. Виж таблицата `headings`.
  final bool isHeading;
  /// Текстът по код на превод. Липсва ли ключ, този превод няма такъв стих —
  /// клетката остава празна, а редът пак се пази.
  final Map<String, BibleVerse> byLang;

  const BibleRow({
    required this.verse,
    required this.byLang,
    this.isHeading = false,
  });

  BibleVerse? operator [](String lang) => byLang[lang];
}

/// Достъпът до базата. Статичен, както останалите помощници в проекта.
class BibleDb {
  static const String _dbName = 'bible.db';
  static Database? _db;

  static Future<Database> get database async {
    if (_db != null) return _db!;
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, _dbName);
    final file = File(path);
    if (await file.exists()) {
      // Винаги презаписва — както другите бази. ⚠ Без това поправка в
      // assets/db/ не стига до устройството: копието отпреди остава и
      // приложението чете стария текст, докато данните не се изчистят на
      // ръка. Точно този капан беше платен веднъж с томовете (виж CLAUDE.md).
      await file.delete();
    }
    final data = await rootBundle.load('assets/db/$_dbName');
    await file.writeAsBytes(data.buffer.asUint8List());
    _db = await openDatabase(path, readOnly: true);
    return _db!;
  }

  // ── Указатели, кеширани за сесията ─────────────────────────────────────
  // Книгите са 77, преводите — дузина. Четат се веднъж и стоят: съдържанието
  // ги иска при всяко отваряне, а падащото меню за езика — при всеки тап.

  static List<BibleBook>? _books;
  static List<BibleLanguage>? _languages;

  static Future<List<BibleBook>> books() async {
    if (_books != null) return _books!;
    final db = await database;
    final rows = await db.query('books', orderBy: 'ord');
    return _books = rows.map(BibleBook.fromRow).toList();
  }

  /// Преводите, които РЕАЛНО имат стихове в базата.
  ///
  /// ⚠ Нарочно не се връщат всички редове от `languages`: докато конвейерът
  /// тегли, таблицата вече ги описва, но текст още няма. Показан в менюто,
  /// такъв превод отваря празен екран без никакво обяснение.
  static Future<List<BibleLanguage>> languages() async {
    if (_languages != null) return _languages!;
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT l.* FROM languages l
      WHERE EXISTS (SELECT 1 FROM verses v WHERE v.lang = l.code)
      ORDER BY l.ord
    ''');
    return _languages = rows.map(BibleLanguage.fromRow).toList();
  }

  static Future<BibleBook?> book(String code) async {
    for (final b in await books()) {
      if (b.code == code) return b;
    }
    return null;
  }

  /// Кои глави на книгата изобщо ги има за този превод.
  ///
  /// Нужно е на съдържанието: матрицата с номерата свети само върху онези
  /// клетки, зад които стои текст. Липсите са ЗАКОННИ (Септуагинтата няма
  /// Нов завет), не са грешка.
  static Future<Set<int>> availableChapters(String book, String lang) async {
    final db = await database;
    final rows = await db.rawQuery(
      'SELECT DISTINCT chapter FROM verses WHERE book = ? AND lang = ?',
      [book, lang],
    );
    return rows.map((r) => r['chapter'] as int).toSet();
  }

  /// Стиховете на една глава в един превод, по реда на показване.
  static Future<List<BibleVerse>> chapter(
      String book, int chapter, String lang) async {
    final db = await database;
    final rows = await db.query(
      'verses',
      columns: ['verse', 'ord', 'text', 'html'],
      where: 'book = ? AND chapter = ? AND lang = ?',
      whereArgs: [book, chapter, lang],
      orderBy: 'ord',
    );
    return rows
        .map((r) => BibleVerse(
              verse: r['verse'] as String,
              ord: r['ord'] as int,
              text: r['text'] as String,
              html: r['html'] as String?,
            ))
        .toList();
  }

  /// Главата, подравнена между няколко превода.
  ///
  /// ⚠ ГРЪБНАКЪТ Е ПЪРВИЯТ ПРЕВОД, а не обединението на всички. Тъй че редът
  /// на четене е този на превода, който човекът гледа — а не някакъв трети,
  /// сглобен наум.
  ///
  /// ⚠ Стих, който го има САМО в някой от останалите, не се изхвърля. Той се
  /// вмъква след последния общ стих преди него, тъй че да не изскочи накрая
  /// на главата, откъснат от мястото си. Такива има: номерацията на
  /// Масоретския текст и на Септуагинтата се разминава, а надписанията на
  /// псалмите ту са стих 0, ту ги няма.
  static Future<List<BibleRow>> alignChapter(
      String book, int chapter, List<String> langs) async {
    if (langs.isEmpty) return const [];

    final headings = await headingVerses(book, chapter);
    final perLang = <String, List<BibleVerse>>{};
    for (final lang in langs) {
      // ⚠ През името на класа: параметърът `chapter` (int) засенчва
      // едноименния метод и голото `chapter(...)` се чете като опит да се
      // извика числото.
      perLang[lang] = await BibleDb.chapter(book, chapter, lang);
    }

    final spine = <String>[];
    final seen = <String>{};
    for (final v in perLang[langs.first] ?? const <BibleVerse>[]) {
      if (seen.add(v.verse)) spine.add(v.verse);
    }

    // Останалите преводи дописват своите стихове НА МЯСТОТО ИМ: всеки нов
    // ключ застава веднага след последния, който вече е в гръбнака.
    for (final lang in langs.skip(1)) {
      var anchor = -1; // индекс в spine на последния познат стих
      for (final v in perLang[lang] ?? const <BibleVerse>[]) {
        final at = spine.indexOf(v.verse);
        if (at >= 0) {
          anchor = at;
        } else if (seen.add(v.verse)) {
          anchor += 1;
          spine.insert(anchor, v.verse);
        }
      }
    }

    // Търсенето по ключ става през карти, а не с обхождане на списъка за
    // всеки ред: иначе при Пс. 118 (176 стиха × 2 превода) излиза квадратично
    // точно на екрана, който трябва да се отвори мигновено.
    final index = <String, Map<String, BibleVerse>>{
      for (final lang in langs)
        lang: {for (final v in perLang[lang] ?? const <BibleVerse>[]) v.verse: v},
    };

    final out = <BibleRow>[];
    for (final verse in spine) {
      final cells = <String, BibleVerse>{};
      for (final lang in langs) {
        final v = index[lang]?[verse];
        if (v != null) cells[lang] = v;
      }
      out.add(BibleRow(
        verse: verse,
        byLang: cells,
        isHeading: headings.contains(verse),
      ));
    }
    return out;
  }

  /// Кои стихове в главата са НАДПИСАНИЯ (заглавия), а не текст.
  ///
  /// Без език — надписанието е свойство на мястото в Писанието.
  static Future<Set<String>> headingVerses(String book, int chapter) async {
    final db = await database;
    final rows = await db.query(
      'headings',
      columns: ['verse'],
      where: 'book = ? AND chapter = ?',
      whereArgs: [book, chapter],
    );
    return {for (final r in rows) r['verse'] as String};
  }

  /// Подзаглавията на дяловете в главата (сръбският ги носи), по стих.
  static Future<Map<String, List<String>>> titles(
      String book, int chapter, String lang) async {
    final db = await database;
    final rows = await db.query(
      'titles',
      columns: ['verse', 'text'],
      where: 'book = ? AND chapter = ? AND lang = ?',
      whereArgs: [book, chapter, lang],
    );
    final out = <String, List<String>>{};
    for (final r in rows) {
      out.putIfAbsent(r['verse'] as String, () => []).add(r['text'] as String);
    }
    return out;
  }

  /// Богослужебните зачала в главата, по стих.
  ///
  /// Още не се показват никъде — вадят се и се пазят за дневните четива.
  static Future<Map<String, List<String>>> zachala(
      String book, int chapter, String lang) async {
    final db = await database;
    final rows = await db.query(
      'zachala',
      columns: ['verse', 'label'],
      where: 'book = ? AND chapter = ? AND lang = ?',
      whereArgs: [book, chapter, lang],
    );
    final out = <String, List<String>>{};
    for (final r in rows) {
      out.putIfAbsent(r['verse'] as String, () => []).add(r['label'] as String);
    }
    return out;
  }
}
