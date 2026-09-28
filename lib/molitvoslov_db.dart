// molitvoslov_db.dart
//
// Четене на `assets/db/molitvoslov.db` — секцията „Молитвослов".
//
// ⚠ ОТДЕЛНА база от bible.db, нарочно: езиците, запомненото място и всичко
// останало тук не бива да пипа Библията (изрично искане на потребителя).
// Прави се от tools/Molitvoslov/scripts/05_build_db.py.

import 'package:sqflite/sqflite.dart';

import 'asset_db.dart';

/// Един език на молитвослова — с мерките на шрифта си (взети от bible.db,
/// за да изглежда цс текстът еднакво в двата раздела).
class MolLanguage {
  final String code;
  final String title;
  final String abbr;
  final String? font;
  final double sizeDelta;
  final double lineDelta;
  final bool rubricate;

  const MolLanguage({
    required this.code,
    required this.title,
    required this.abbr,
    this.font,
    this.sizeDelta = 0,
    this.lineDelta = 0,
    this.rubricate = false,
  });
}

class MolTab {
  final String code;
  final String title;
  const MolTab(this.code, this.title);
}

class MolSection {
  final int id;
  final String tab;
  final String titleBg;
  final String? titleCsl;

  /// Изворът на църковнославянския текст (адрес).
  final String? sourceCsl;
  const MolSection(this.id, this.tab, this.titleBg, this.titleCsl,
      [this.sourceCsl]);
}

/// Един абзац: указание (винено) или текст.
class MolBlock {
  final String kind; // 'rubric' | 'text'
  final String html;
  const MolBlock(this.kind, this.html);
  bool get isRubric => kind == 'rubric';
}

/// Една молитва — с текста си по езици.
class MolUnit {
  final int n;
  final String? titleBg;
  final String? titleCsl;

  /// Адресите на българските извори, по един на ред.
  final String? sourceBg;
  final Map<String, List<MolBlock>> blocks;

  const MolUnit({
    required this.n,
    this.titleBg,
    this.titleCsl,
    this.sourceBg,
    required this.blocks,
  });

  List<MolBlock> of(String lang) => blocks[lang] ?? const [];
  /// Заглавието на единицата на даден език — `csl` и `csr` делят цс
  /// заглавието (то е едно и също, само в различна графика).
  String? titleFor(String lang) => lang == 'bg' ? titleBg : titleCsl;
}

class MolitvoslovDb {
  MolitvoslovDb._();

  static Database? _db;
  static Future<Database>? _opening;

  static Future<Database> get database {
    if (_db != null) return Future.value(_db);
    // ⚠ Пазач срещу две едновременни отваряния — същият капан, платен при
    // BibleDb (виж „Три бъга при отваряне по външен линк" в CLAUDE.md).
    return _opening ??= openAssetDatabase('molitvoslov.db').then((d) {
      _db = d;
      return d;
    }).whenComplete(() {
      _opening = null;
    });
  }

  static List<MolLanguage>? _langs;

  static Future<List<MolLanguage>> languages() async {
    if (_langs != null) return _langs!;
    final db = await database;
    final rows = await db.query('languages', orderBy: 'ord');
    return _langs = [
      for (final r in rows)
        MolLanguage(
          code: r['code'] as String,
          title: r['bg_title'] as String,
          abbr: r['bg_abbr'] as String,
          font: r['font'] as String?,
          sizeDelta: (r['size_delta'] as num).toDouble(),
          lineDelta: (r['line_delta'] as num).toDouble(),
          rubricate: (r['rubricate'] as int) == 1,
        ),
    ];
  }

  static Future<List<MolTab>> tabs() async {
    final db = await database;
    final rows = await db.query('tabs', orderBy: 'ord');
    return [
      for (final r in rows) MolTab(r['code'] as String, r['title'] as String),
    ];
  }

  static Future<List<MolSection>> sections() async {
    final db = await database;
    final rows = await db.query('sections', orderBy: 'ord');
    return [
      for (final r in rows)
        MolSection(r['id'] as int, r['tab'] as String,
            r['title_bg'] as String, r['title_csl'] as String?,
            r['source_csl'] as String?),
    ];
  }

  /// Молитвите на един раздел, с текста им по езици.
  static Future<List<MolUnit>> units(int sectionId) async {
    final db = await database;
    final us = await db.query('units',
        where: 'section_id = ?', whereArgs: [sectionId], orderBy: 'n');
    final bs = await db.query('blocks',
        where: 'section_id = ?', whereArgs: [sectionId], orderBy: 'n, lang, ord');
    final byUnit = <int, Map<String, List<MolBlock>>>{};
    for (final b in bs) {
      byUnit
          .putIfAbsent(b['n'] as int, () => {})
          .putIfAbsent(b['lang'] as String, () => [])
          .add(MolBlock(b['kind'] as String, b['html'] as String));
    }
    return [
      for (final u in us)
        MolUnit(
          n: u['n'] as int,
          titleBg: u['title_bg'] as String?,
          titleCsl: u['title_csl'] as String?,
          sourceBg: u['source_bg'] as String?,
          blocks: byUnit[u['n'] as int] ?? const {},
        ),
    ];
  }
}
