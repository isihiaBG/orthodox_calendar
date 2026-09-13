// lives_plus.dart
//
// „СЛОВА ЗА ДЕНЯ" — словата и поученията на свт. Димитрий Ростовски, които
// НЕ са жития: проповеди за неделите по Петдесетница, за Триода и Великия
// пост, за неподвижните празници и за паметта на светии.
//
// ⚠⚠ ВСИЧКИТЕ СА В ЕДНА СЕКЦИЯ, а не закачени за светията на деня. Мерено
// преди да се реши (13.09.2026): от 101 слова само 23 падат на ден, който
// изобщо known запис със слъг — и то без да е сигурно, че слъгът е на ВЕРНИЯ
// светия, а тъкмо тази засечка по име вече е струвала скъпо в този проект
// (виж `tools/match_dmitry_lives/`). Останалите 78 нямат за какво да се
// закачат: неделите по Петдесетница нямат ред в `saints` изобщо.
//
// ⚠ АДРЕСЪТ Е СЪЩИЯТ КАТО НА ЧЕТИВАТА (`readings_lookup.dart`) — нарочно, за
// да няма втора система:
//
//     W<седм>:<ден>  по Петдесетница      ММ-ДД                 church дата
//     T<седм>:<ден>  Триод                ММ-ДД|ден|before      закотвена
//     P<седм>:<ден>  Пентикостар                    |after      събота/неделя
//
// ⚠ Базата е ОТДЕЛНА и не се ATTACH-ва — както `teofan.db` и `optina.db`.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'readings_lookup.dart';
import 'saint_expandable_tile.dart';

/// Префиксът на слъга — пази отметките и цитатите на словата настрани от
/// тези на светиите и на справочника.
///
/// ⚠ Разпознава се в `lookupBySlug`. Без това отметка към слово се записва,
/// но не се отваря — капанът, платен веднъж при справочните четива.
const String kSlovoSlugPrefix = 'slovo-';

bool isSlovoSlug(String slug) => slug.startsWith(kSlovoSlugPrefix);

/// Едно слово — БЕЗ тялото.
///
/// ⚠ Тялото е десетки хиляди знака, а списъкът се чете за ВСЕКИ отворен ден,
/// само за да се реши дали секцията изобщо да се покаже. Затова се вади при
/// отваряне ([LivesPlusDb.bodyOf]), не наготово.
class Slovo {
  final String id;
  final String title;
  final String address;

  const Slovo({
    required this.id,
    required this.title,
    required this.address,
  });

  String get slug => '$kSlovoSlugPrefix$id';
}

class LivesPlusDb {
  static Database? _db;
  static Future<Database>? _opening;

  /// ⚠ Single-flight, както при [BibleDb]: две едновременни повиквания иначе
  /// влизат заедно, първото трие файла, а второто гърми с
  /// `PathNotFoundException` — и то само когато екранът се отвори по път,
  /// който не минава през обичайното зареждане.
  static Future<Database> get database {
    if (_db != null) return Future.value(_db!);
    return _opening ??= _open().whenComplete(() => _opening = null);
  }

  static Future<Database> _open() async {
    final dir = await getApplicationSupportDirectory();
    final path = p.join(dir.path, 'lives_plus.db');
    // ⚠ Презаписва се при ВСЯКО пускане, за да стига поправка в `assets/db/`
    // до устройството — същото правило като при `bible.db`.
    final data = await rootBundle.load('assets/db/lives_plus.db');
    final f = File(path);
    try {
      if (await f.exists()) await f.delete();
    } on FileSystemException {
      // целта е „да го няма", не „аз да съм го изтрил"
    }
    await f.create(recursive: true);
    await f.writeAsBytes(data.buffer.asUint8List(), flush: true);
    return _db = await openDatabase(path, readOnly: true);
  }

  /// Всички addrs, на които може да падне този ден.
  ///
  /// ⚠ ЦЪРКОВНАТА дата се подава отвън — тя се смята от гражданската по
  /// правилото на СТИЛА и това вече живее на едно място
  /// ([SaintTexts.churchDateOf]). Втора сметка тук би се разминала с него.
  static List<String> addressesFor(DateTime date, String churchMonthDay,
      {required bool oldStyle}) {
    final out = <String>[readingAddress(date).key, churchMonthDay];
    // Закотвените — по същата сметка като [anchoredFor], за да не се
    // разминат при първата промяна в нея.
    final d = DateTime.utc(date.year, date.month, date.day);
    if (d.weekday == DateTime.saturday || d.weekday == DateTime.sunday) {
      for (final feast in kAnchorFeasts) {
        final m = int.parse(feast.substring(0, 2));
        final day = int.parse(feast.substring(3));
        for (final y in [d.year - 1, d.year, d.year + 1]) {
          final fd = civilDateOfChurch(y, m, day, oldStyle: oldStyle);
          final diff = d.difference(fd).inDays;
          if (diff.abs() > 7 || diff == 0) continue;
          out.add('$feast|${d.weekday}|${diff < 0 ? 'before' : 'after'}');
        }
      }
    }
    return out;
  }

  /// Словата за деня, или празен списък.
  static Future<List<Slovo>> forDate(DateTime date, String churchMonthDay,
      {required bool oldStyle}) async {
    final addrs = addressesFor(date, churchMonthDay, oldStyle: oldStyle);
    final db = await database;
    final rows = await db.query(
      'slova',
      columns: ['id', 'title_bg', 'address'],
      where: 'address IN (${List.filled(addrs.length, '?').join(',')})',
      whereArgs: addrs,
      orderBy: 'id',
    );
    return [
      for (final r in rows)
        Slovo(
          id: r['id'] as String,
          title: r['title_bg'] as String,
          address: r['address'] as String,
        ),
    ];
  }

  /// Гражданските дати в обхвата, които knownт поне едно слово.
  ///
  /// ⚠⚠ ЗАЩО НЕ Е EXISTS В SQL. `lives_plus.db` НЕ се ATTACH-ва към
  /// календарната (както `teofan.db` и `optina.db`), тъй че подзаявка към
  /// нея е невъзможна. Затова множеството дати се смята тук и се подава на
  /// търсенето като `s.date IN (…)`.
  ///
  /// ⚠ Адресите са ЛИТУРГИЧНИ („W27:7", „T5:7", church „ММ-ДД"), тъй че
  /// кои ГРАЖДАНСКИ дати им отговарят зависи от годината И от стила —
  /// затова се обхожда самият обхват, а не се пази готов списък.
  ///
  /// ⚠ Евтино е: addrsте са около сто, а дните в базата — към хиляда.
  static Future<Set<String>> datesWithSlova({
    required DateTime from,
    required DateTime to,
    required bool oldStyle,
  }) async {
    final db = await database;
    final rows = await db.rawQuery('SELECT DISTINCT address FROM slova');
    final known = {for (final r in rows) r['address'] as String};
    if (known.isEmpty) return const {};
    final out = <String>{};
    for (var d = DateTime.utc(from.year, from.month, from.day);
        !d.isAfter(to);
        d = d.add(const Duration(days: 1))) {
      final church =
          oldStyle ? d.subtract(const Duration(days: 13)) : d;
      final key = '${church.month.toString().padLeft(2, '0')}-'
          '${church.day.toString().padLeft(2, '0')}';
      final addrs = addressesFor(d, key, oldStyle: oldStyle);
      if (addrs.any(known.contains)) {
        out.add(d.toIso8601String().substring(0, 10));
      }
    }
    return out;
  }

  /// Тялото на едно слово — вади се при ОТВАРЯНЕ.
  static Future<SaintTexts?> load(String slug) async {
    if (!isSlovoSlug(slug)) return null;
    final db = await database;
    final rows = await db.query('slova',
        columns: ['title_bg', 'body', 'source'],
        where: 'id = ?',
        whereArgs: [slug.substring(kSlovoSlugPrefix.length)],
        limit: 1);
    if (rows.isEmpty) return null;
    return SaintTexts(
      name: rows.first['title_bg'] as String,
      lifeHtml: rows.first['body'] as String,
      slug: slug,
      // ⚠ Адресът на ОРИГИНАЛА в azbyka.ru — четецът го изписва накрая през
      // `_sourceHtml()`. Сайтът изисква коректно цитиране, а общ надпис за
      // цялата книга не сочи къде точно е това слово.
      source: (rows.first['source'] as String?) ?? '',
    );
  }
}
