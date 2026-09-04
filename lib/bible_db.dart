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

import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' show join;

import 'search_match.dart';
import 'package:sqflite/sqflite.dart';

import 'bible_packs.dart';

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

  /// ⚠⚠ ПАЗАЧ СРЕЩУ ЕДНОВРЕМЕННИ ИЗВИКВАНИЯ (single-flight).
  ///
  /// Без него две паралелни повиквания влизат ЗАЕДНО: и двете виждат
  /// `_db == null`, и двете виждат файла на място, ПЪРВОТО го трие, а
  /// второто гърми с
  /// `PathNotFoundException: Cannot delete file … (errno = 2)` — и екранът
  /// остава празен със „Грешка при четене". Оттам и подвеждащото
  /// „първия път се отвори, всеки следващ дава грешка": паралелният
  /// повикващ се появява чак когато четецът вече е построен.
  ///
  /// `DatabaseHelper` открай време има такъв пазач; тук липсваше.
  /// (Докладвано от потребителя, 03.09.2026, при отваряне на линк към
  /// Евангелието.)
  static Future<Database>? _opening;

  static Future<Database> get database async {
    final ready = _db;
    if (ready != null) return ready;
    // ⚠ `whenComplete` чисти пазача И при грешка — инак един провал би
    // заключил базата до рестарт.
    return _opening ??= _open().whenComplete(() => _opening = null);
  }

  static Future<Database> _open() async {
    final dbPath = await getDatabasesPath();
    // ⚠ Папката `databases/` може да я няма изобщо при отваряне ПО ЛИНК:
    // приложението стига дотук, без да е минало по обичайния път, който я
    // създава. Тогава записът гърми със същия errno = 2, само че на друг
    // ред.
    await Directory(dbPath).create(recursive: true);
    final path = join(dbPath, _dbName);
    final file = File(path);
    if (await file.exists()) {
      // Винаги презаписва — както другите бази. ⚠ Без това поправка в
      // assets/db/ не стига до устройството: копието отпреди остава и
      // приложението чете стария текст, докато данните не се изчистят на
      // ръка. Точно този капан беше платен веднъж с томовете (виж CLAUDE.md).
      //
      // ⚠ Изтриването е ТОЛЕРАНТНО: файлът може да си е отишъл между
      // проверката и самото триене (друг повикващ, чистене на паметта).
      // Целта е „да го няма", а не „аз да съм го изтрил".
      try {
        await file.delete();
      } on FileSystemException catch (_) {
        // вече го няма — точно каквото искахме
      }
    }
    final data = await rootBundle.load('assets/db/$_dbName');
    await file.writeAsBytes(data.buffer.asUint8List());
    final db = await openDatabase(path, readOnly: true);
    _db = db;
    return db;
  }

  /// Отворените езикови пакети — по един на свален превод.
  ///
  /// ⚠ Държат се отворени за сесията. Отварянето на SQLite файл е евтино, но
  /// не е безплатно, а плъзгането между два превода мени показвания език по
  /// няколко пъти в секунда.
  static final Map<String, Database> _packs = {};

  /// Коя база отговаря за този превод — основната или неговият пакет.
  ///
  /// ⚠ ЕДИНСТВЕНАТА точка, която знае за разделението. Всички заявки по език
  /// минават оттук, тъй че никоя от тях не се променя, когато превод се
  /// свали или изтрие; и нито един ВИКАЩ (четецът, съдържанието) не знае
  /// откъде идва текстът.
  ///
  /// ⚠ Липсващ пакет НЕ гърми — връща се основната база. Тогава заявката
  /// просто не намира стихове и екранът казва „Тази глава още не е свалена",
  /// вместо да се срине. Това е важно: пакет може да изчезне между две
  /// пускания (човек чисти паметта на приложението), а последно ползваният
  /// език се помни в настройките.
  static Future<Database> _dbFor(String lang) async {
    if (kBuiltInLangs.contains(lang)) return database;
    final open = _packs[lang];
    if (open != null) return open;
    final path = await BiblePacks.pathFor(lang);
    if (!await File(path).exists()) return database;
    return _packs[lang] = await openDatabase(path, readOnly: true);
  }

  /// Затваря пакет — при изтриване от настройките.
  /// ⚠ НЕ известява — само забравя кеша. Вика се ПРЕДИ самото изтриване на
  /// файла, тъй че в този миг [BiblePacks.installed] още го брои за налично
  /// и [languages] би сглобил списък с превод, който след миг го няма.
  /// Сигналът се бута от викащия, СЛЕД като файлът наистина е изтрит — виж
  /// `_remove` в bible_packs_screen.dart.
  static Future<void> closePack(String lang) async {
    final db = _packs.remove(lang);
    await db?.close();
    _languages = null; // списъкът с преводи се сглобява наново
  }

  /// Забравя запомнения списък с преводи — след сваляне или изтриване на
  /// пакет — и ИЗВЕСТЯВА за това.
  static void forgetLanguages() {
    _languages = null;
    languagesRevision.value++;
  }

  /// Расте при всяка промяна в НАБОРА от налични преводи.
  ///
  /// ⚠ Изчистването на кеша само по себе си НЕ Е достатъчно, макар да
  /// изглежда така: то върши работа за следващия, който извика [languages] —
  /// но четецът не вика. Той пази списъка от `initState`, а панелът с
  /// настройките (откъдето се свалят преводите) стои НАД него и НЕ го
  /// затваря, тъй че `initState` няма да се повика втори път. Без този
  /// сигнал новосвален превод се появява в менюто чак при следващо пускане
  /// на приложението.
  ///
  /// Същият урок вече беше платен два пъти — виж [ReaderDropCapScale]
  /// (drop_cap_scale.dart) и [BibleZachala] (bible_settings.dart).
  static final ValueNotifier<int> languagesRevision = ValueNotifier<int>(0);

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
  /// ⚠ ОСНОВНИТЕ ПЛЮС СВАЛЕНИТЕ. Основната база носи само двата вградени
  /// превода; всеки свален пакет носи СВОЯ ред от `languages` в себе си,
  /// тъй че описанието му (шрифт, междуредие, рубрикация) пътува заедно с
  /// текста и не се дублира тук.
  ///
  /// Подредбата е по `ord` — същата, каквато е и в източника, независимо кой
  /// пакет кога е свален.
  static Future<List<BibleLanguage>> languages() async {
    if (_languages != null) return _languages!;
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT l.* FROM languages l
      WHERE EXISTS (SELECT 1 FROM verses v WHERE v.lang = l.code)
      ORDER BY l.ord
    ''');
    final out = rows.map(BibleLanguage.fromRow).toList();

    for (final code in await BiblePacks.installed()) {
      final pack = await _dbFor(code);
      if (identical(pack, await database)) continue; // не се е отворил
      final r = await pack.query('languages', where: 'code = ?',
          whereArgs: [code], limit: 1);
      if (r.isNotEmpty) out.add(BibleLanguage.fromRow(r.first));
    }
    out.sort((a, b) => a.ord.compareTo(b.ord));
    return _languages = out;
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
    final db = await _dbFor(lang);
    final rows = await db.rawQuery(
      'SELECT DISTINCT chapter FROM verses WHERE book = ? AND lang = ?',
      [book, lang],
    );
    return rows.map((r) => r['chapter'] as int).toSet();
  }

  /// Търси дума или израз В САМИЯ ТЕКСТ на Писанието.
  ///
  /// Връща намереното като (книга, глава, стих), подредено по каноничния ред
  /// на книгите, после по глава и стих. `books` ограничава обхвата — подава
  /// се от настройката „само в този дял"; празен списък значи цялото
  /// Писание.
  ///
  /// ⚠ БЕЗ `LOWER()` и без нормализирана колона, ВЪПРЕКИ че на десктопа
  /// `LIKE` с кирилица е чувствителен към регистъра. Меродавен е SQLite-ът
  /// НА УСТРОЙСТВОТО, а там същата заявка намира и „Йоан", и „йоан"
  /// (проверено на живо; виж CLAUDE.md, „Два капана, които струваха часове").
  /// Добавен, `LOWER()` не поправя нищо и струва пълен обход с преобразуване.
  ///
  /// ⚠ ЕКРАНИРА СЕ, преди да влезе в `LIKE`. Иначе човек, който потърси
  /// „100%", получава всичко: `%` и `_` са шаблонни знаци, а не букви.
  ///
  /// ⚠ ТАВАН САМО НА ПОКАЗВАНОТО, не на броенето. Дума като „и" стои в 36 948
  /// стиха; списък с толкова редове не е резултат, а цялата книга разбъркана.
  /// Броят обаче трябва да е ТОЧЕН („Общо 36948"), тъй че заявката минава
  /// БЕЗ `LIMIT` и редовете се режат чак тук, след преброяването. Цената е
  /// един пълен обход, който и без това се прави — `LIKE` по цял текст няма
  /// как да спре по-рано, освен ако не срещне тавана, а точно това не искаме.
  /// Екранира шаблонните знаци на `LIKE`.
  ///
  /// ⚠ Без това търсене на „100%" връща всичко: `%` и `_` са шаблон, не букви.
  static String _escapeLike(String w) => w
      .replaceAll(r'\', r'\\')
      .replaceAll('%', r'\%')
      .replaceAll('_', r'\_');

  static const int searchLimit = 5000;

  static Future<({List<({String book, int chapter, String verse})> verses, int total})>
      searchText(
    String lang,
    String query, {
    List<String> books = const [],
    /// Глави от една книга, когато обхватът е по-тесен от цяла книга — днес
    /// само Псалтирът, избран по катизми.
    ///
    /// ⚠ Стои ОТДЕЛНО от [books], а не като „книга с глави": двете се
    /// обединяват с ИЛИ. Човек може да е избрал Евангелията ЦЕЛИ и от
    /// Псалтира — само трета катизма; смесени в едно условие, двете биха се
    /// изключили взаимно.
    Map<String, Set<int>> chapters = const {},
  }) async {
    final q = query.trim();
    if (q.isEmpty) {
      return (verses: <({String book, int chapter, String verse})>[], total: 0);
    }
    final db = await _dbFor(lang);

    // ⚠ ПО КЛЮЧОВИ ДУМИ, НЕ ПО ФРАЗА: написаното се дели по интервали и всяка
    // дума става свое условие, свързано с И. „содом гомор" така намира
    // „…Содомски и Гоморски…", което като фраза не се среща никъде — между
    // двете стои „и", а и двете са в друга форма. Виж [searchTerms].
    final terms = searchTerms(q);
    if (terms.isEmpty) {
      return (verses: <({String book, int chapter, String verse})>[], total: 0);
    }
    final where = StringBuffer('v.lang = ?');
    final args = <Object>[lang];
    for (final t in terms) {
      where.write(" AND v.text LIKE ? ESCAPE '\\'");
      args.add('%${_escapeLike(t)}%');
    }
    // Обхватът: цели книги ИЛИ отделни глави от книга.
    final scope = <String>[];
    if (books.isNotEmpty) {
      scope.add('v.book IN (${List.filled(books.length, '?').join(',')})');
      args.addAll(books);
    }
    chapters.forEach((book, chs) {
      if (chs.isEmpty) return;
      scope.add('(v.book = ? AND v.chapter IN '
          '(${List.filled(chs.length, '?').join(',')}))');
      args.add(book);
      args.addAll(chs);
    });
    if (scope.isNotEmpty) where.write(' AND (${scope.join(' OR ')})');

    // ⚠ Подредбата минава през `books.ord`, а не по кода на книгата: „Gen"
    // и „Gal" са съседни по азбука и на километри в Писанието. Таблицата
    // `books` стои в основната база, а стиховете може да идват от пакет —
    // затова редът се възстановява ТУК, а не в SQL-а с JOIN през две бази.
    final rows = await db.rawQuery(
      'SELECT v.book, v.chapter, v.verse, v.ord FROM verses v'
      ' WHERE ${where.toString()}',
      args,
    );

    // ⚠ `BibleDb.books()`, а не голо `books()` — параметърът на този метод
    // се казва също `books` и засенчва статичния.
    final order = {for (final b in await BibleDb.books()) b.code: b.ord};
    final out = [
      for (final r in rows)
        (
          book: r['book'] as String,
          chapter: r['chapter'] as int,
          verse: r['verse'] as String,
        )
    ];
    out.sort((a, b) {
      final ba = order[a.book] ?? 9999;
      final bb = order[b.book] ?? 9999;
      if (ba != bb) return ba.compareTo(bb);
      if (a.chapter != b.chapter) return a.chapter.compareTo(b.chapter);
      return (int.tryParse(a.verse) ?? 0).compareTo(int.tryParse(b.verse) ?? 0);
    });
    // ⚠ `total` е ПРЕДИ рязането — той отива в заглавието на екрана и трябва
    // да казва колко има, а не колко се показват.
    final total = out.length;
    return (
      verses: out.length > searchLimit ? out.sublist(0, searchLimit) : out,
      total: total,
    );
  }

  /// Стиховете на една глава в един превод, по реда на показване.
  static Future<List<BibleVerse>> chapter(
      String book, int chapter, String lang) async {
    final db = await _dbFor(lang);
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
              // ⚠ Вграденото зачало се маха ТУК, на входа, а не при рисуване.
              // В базата църковнославянските стихове го носят в самия текст
              // („[Заⷱ҇ 1] Зача́ло…"), а другите преводи — не. Оставен вътре,
              // той се рисува веднъж вграден и веднъж отгоре, и то само в
              // едната колона. Изчистен на входа, зачалото има ЕДИН път до
              // екрана — картата от [zachala] — тъй че всички преводи го
              // получават еднакво, а изключването му от настройките важи
              // навсякъде.
              text: stripEmbeddedZachalo(r['text'] as String),
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
    final db = await _dbFor(lang);
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

  /// Номерът на зачалото в надпис като „Зач. 125А." или „Заⷱ҇ 1".
  ///
  /// ⚠ Пази и буквения суфикс („125А") — той е част от означението, не
  /// украса, и различава двете половини на разделено зачало.
  static final RegExp _zachaloNumber = RegExp(r'\d+[А-ЯA-Z]?');

  /// Разпознава зачало, ВГРАДЕНО в началото на самия стих — „[Заⷱ҇ 1] …".
  ///
  /// ⚠ Признакът е съдържанието на скобата, а не самата скоба. Квадратни
  /// скоби в началото на стих служат за ДВЕ различни неща: 674 са зачала, а
  /// 132 са вмъквания на преводача („[Сыновья же] Симовы…", „[Псалом Давида
  /// о сотворении мира.]"). Вторите са част от четивото и не бива да се
  /// бъркат с указател към него.
  ///
  /// ⚠ НЕ Е ЗАКОТВЕН В НАЧАЛОТО, и това е нарочно. В 49 стиха (всичките на
  /// църковнославянски) зачалото стои НАСРЕД текста — „…ст҃ы̑мъ: [Заⷱ҇]
  /// блгⷣть ва́мъ…". Със закотвен `^` те оцеляваха от пречистването и
  /// показваха скобата дори при ИЗКЛЮЧЕНА настройка „Показвай зачалата".
  ///
  /// ⚠ Лимитът `{0,10}` върши цялата работа по различаването и точно затова
  /// не бива да се разхлабва: без него разкотвеният израз би сметнал за
  /// зачало и вмъкване на преводача, започващо със „За". Проверено върху
  /// базата — измежду скобите насред текста НЯМА нито едно вмъкване,
  /// а по-дълги от лимита изобщо не се срещат.
  static final RegExp _embeddedZachalo = RegExp(r'\[(За[^\]]{0,10})\]\s*');

  /// Отрязва вграденото зачало от текста на стиха, ако има такова.
  ///
  /// ⚠ Текстът се пречиства ВИНАГИ, а зачалото се рисува отделно и еднакво
  /// за всички преводи. Инак църковнославянският го носеше вграден и
  /// червен, а българският до него — никакъв, при това една и съща заявка
  /// даваше различен резултат според това кой превод стои отсреща.
  static String stripEmbeddedZachalo(String text) =>
      text.replaceAll(_embeddedZachalo, '');

  /// Богослужебните зачала в главата, по стих — ОБЕДИНЕНИ от всички
  /// източници и БЕЗ оглед на показвания превод.
  ///
  /// ⚠ ЗАЧАЛОТО Е СВОЙСТВО НА МЯСТОТО В ПИСАНИЕТО, не на превода. Дотук се
  /// търсеше по език и оттам идваше бъг, който се виждаше отвън като
  /// прищявка: сложиш ли отдясно руския, зачалата се появяваха и в лявата
  /// българска колона; сложиш ли църковнославянския — изчезваха. Причината
  /// е, че таблицата `zachala` пази редове САМО за руския (725), а
  /// църковнославянският носи зачалата ВГРАДЕНИ в текста си (674), тъй че
  /// при двойка без руски нямаше откъде да се вземат.
  ///
  /// Затова тук се четат и двата източника, за цялата глава наведнъж:
  ///   • таблицата `zachala`, без филтър по език;
  ///   • скобата със зачало в текста на всеки стих, на който и да е превод
  ///     (тя невинаги стои в началото — виж [_embeddedZachalo]).
  /// Обединението покрива 747 места — повече от всеки поотделно (таблицата
  /// пропуска 22, вграденото — 73).
  ///
  /// Връща `стих → номер` („1", „125А"). Как се ИЗПИСВА номерът решава
  /// четецът, защото формата зависи от азбуката на превода.
  static Future<Map<String, String>> zachala(String book, int chapter) async {
    final db = await database;
    final out = <String, String>{};

    for (final r in await db.query(
      'zachala',
      columns: ['verse', 'label'],
      where: 'book = ? AND chapter = ?',
      whereArgs: [book, chapter],
    )) {
      final n = _zachaloNumber.firstMatch(r['label'] as String)?.group(0);
      if (n != null) out[r['verse'] as String] = n;
    }

    // ⚠ Заявката е БЕЗ филтър по език — за да улови и превод, който в
    // момента не се показва. Редовете са шепа: скобата е рядка, а тук се
    // търси само в една глава.
    //
    // ⚠ Шаблонът е '%[За%', не '[За%' — в 49 стиха зачалото стои насред
    // текста. Закотвен, той ги пропускаше тук, а [stripEmbeddedZachalo] ги
    // пропускаше и в пречистването: скобата им се виждаше винаги, независимо
    // от настройката.
    for (final r in await db.query(
      'verses',
      columns: ['verse', 'text'],
      where: "book = ? AND chapter = ? AND text LIKE '%[За%'",
      whereArgs: [book, chapter],
    )) {
      final m = _embeddedZachalo.firstMatch(r['text'] as String);
      if (m == null) continue;
      final n = _zachaloNumber.firstMatch(m.group(1)!)?.group(0);
      // ⚠ Таблицата има превес: там номерът е гол текст, а във вградения
      // вид е минал през разчитане на скоба и съкращение.
      if (n != null) out.putIfAbsent(r['verse'] as String, () => n);
    }

    return out;
  }
}
