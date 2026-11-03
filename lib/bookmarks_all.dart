// bookmarks_all.dart
//
// Събира отметките от ДВАТА четеца в един списък.
//
// Този файл е единственото място, което познава и двете страни: житията
// (reader_screen) и книгите (book_reader). Затова самият списък
// (bookmarks.dart) остава чист — иначе се получава кръгов внос, защото
// четците на свой ред отварят списъка.
//
// Подредбата (автора, 03.11.2026): по РАЗДЕЛИ според извора — „Жития от
// azbyka.ru", „Български жития", „Жития по Димитрий Ростовски" (в него по
// месеци), „Читалня" (по книги) и т. н. Редовете — заглавието, а отдолу
// „Памет на …". Разделите, групите и записите — най-скорошното отгоре.

import 'package:flutter/material.dart';

import 'azbyka_article.dart' show isArticleSlug;
import 'book_position_store.dart';
import 'book_reader.dart';
import 'bookmarks.dart';
import 'chitalnya_books.dart';
import 'database_helper.dart';
import 'epub_source.dart';
import 'lives_plus.dart' show isDniSlug, isSlovoSlug, isTipikonSlug;
import 'reader_screen.dart';
import 'reference_text.dart' show isReferenceSlug, isTeofanNoteSlug;
import 'saint_expandable_tile.dart' show SaintLookup;

const _months = [
  'януари', 'февруари', 'март', 'април', 'май', 'юни', 'юли', 'август',
  'септември', 'октомври', 'ноември', 'декември'
];

const _secAzbyka = 'Жития от azbyka.ru';
const _secBg = 'Български жития';
const _secDmitry = 'Жития по Димитрий Ростовски';
const _secHymns = 'Служби, тропари и кондаци';
const _secChitalnya = 'Читалня';

/// Месецът на тома по Димитрий Ростовски („… - 10(окт) - …" → „Октомври").
String? _dmitryMonth(String assetPath) {
  if (!assetPath.contains('Димитрий Ростовски')) return null;
  final m = RegExp(r' - (\d\d)\(').firstMatch(assetPath);
  final i = m == null ? 0 : int.parse(m[1]!);
  if (i < 1 || i > 12) return '';
  final w = _months[i - 1];
  return w[0].toUpperCase() + w.substring(1);
}

/// Заглавието на тома, както се изписва над групата.
///
/// Вади се от името на файла, а не от самия .epub: така списъкът се показва
/// мигновено, без да отваря дузина архива само за да напише заглавия.
String bookTitleFromPath(String assetPath) {
  var name = assetPath.split('/').last;
  if (name.endsWith('.epub')) {
    name = name.substring(0, name.length - '.epub'.length);
  }
  // Книгите от „Читалня" са с латински имена на файловете („razgovori") —
  // над групата стои краткото им име.
  for (final b in kChitalnyaBooks) {
    if (b.epub == assetPath) return b.short;
  }
  return name.replaceAll(' - Димитрий Ростовски', '');
}

/// Старите отметки, записани върху САМИЯ ДЕН в тома („Памет на 20
/// октомври", без светията): денят и първото му житие са един файл, тъй че
/// отметката е на житието. Поправя се веднъж и се записва наново.
Future<void> _repairDayTitles(
    List<({String assetPath, String href, BookPosition pos})> records) async {
  final broken = [
    for (var i = 0; i < records.length; i++)
      if (records[i].pos.parentTitle.isEmpty &&
          _dmitryMonth(records[i].assetPath) != null)
        i
  ];
  final books = <String, EpubBook?>{};
  for (final i in broken) {
    final r = records[i];
    try {
      books[r.assetPath] ??= await EpubBook.open(r.assetPath);
    } catch (e) {
      debugPrint('Отметки: томът не се отвори ($e)');
      continue;
    }
    final (title, parent) = epubEntryTitles(books[r.assetPath]!, r.href, r.pos.chapterTitle);
    if (parent.isEmpty) continue;
    final p = r.pos;
    final fixed = BookPosition(
      chapter: p.chapter,
      offset: p.offset,
      region: p.region,
      charInRegion: p.charInRegion,
      chapterTitle: title,
      parentTitle: parent,
      savedAtMs: p.savedAtMs,
    );
    await BookPositionStore.save(r.assetPath, r.href, fixed);
    records[i] = (assetPath: r.assetPath, href: r.href, pos: fixed);
  }
}

/// Отметките от книгите, преведени към общия вид на списъка.
Future<List<BookmarkEntry>> bookBookmarkEntries() async {
  final records = [...await BookPositionStore.loadAll()];
  await _repairDayTitles(records);
  String section(String path) {
    if (_dmitryMonth(path) != null) return _secDmitry;
    if (kChitalnyaBooks.any((b) => b.epub == path)) return _secChitalnya;
    return bookTitleFromPath(path);
  }

  String group(String path) =>
      _dmitryMonth(path) ??
      (kChitalnyaBooks.any((b) => b.epub == path) ? bookTitleFromPath(path) : '');
  return [
    for (final r in records)
      BookmarkEntry(
        id: 'book:${r.assetPath}|${r.href}',
        title: r.pos.chapterTitle,
        // Денят е адресът на четивото в тома („Памет на 19 октомври").
        typeLabel: r.pos.parentTitle,
        section: section(r.assetPath),
        group: group(r.assetPath),
        savedAtMs: r.pos.savedAtMs,
        delete: () => BookPositionStore.clear(r.assetPath, r.href),
        open: (context) async {
          // Томът се отваря чак сега — иначе списъкът би чакал всички.
          final book = await EpubBook.open(r.assetPath);
          if (!context.mounted) return;
          // ⚠ ЧЕТИВОТО, не дневният възел — виж [chapterForHref].
          final start = chapterForHref(book, r.href);
          if (start == null) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Четивото вече го няма в книгата.')),
            );
            return;
          }
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => BookReader(book: book, start: start),
          ));
        },
      ),
  ];
}

/// Отметките от първия четец (базите), сложени в раздела на извора си.
Future<List<BookmarkEntry>> _placedLives(SaintLookup lookup) async {
  final lives = await livesBookmarkEntries(lookup);
  // id: „life:<режим>:<слъг>" (reader_screen.livesBookmarkEntries).
  (String, String) modeSlug(BookmarkEntry e) {
    final rest = e.id.substring('life:'.length);
    final i = rest.indexOf(':');
    return (rest.substring(0, i), rest.substring(i + 1));
  }

  // Изворът и денят на житията — с една заявка.
  final info = <String, (String, String)>{};
  final slugs = {for (final e in lives) modeSlug(e).$2}.toList();
  if (slugs.isNotEmpty) {
    try {
      final db = await DatabaseHelper.database;
      final rows = await db.rawQuery(
          'SELECT slug, source, dates_own FROM lives.texts '
          'WHERE slug IN (${List.filled(slugs.length, '?').join(',')})',
          slugs);
      for (final r in rows) {
        info[r['slug'] as String] =
            ((r['source'] as String?) ?? '', (r['dates_own'] as String?) ?? '');
      }
    } catch (e) {
      debugPrint('Отметки: изворът не се прочете ($e)');
    }
  }
  // „Памет на 14 октомври" — само при ЕДИН личен ден; при няколко не се
  // знае кой.
  String memory(String slug) {
    final days = (info[slug]?.$2 ?? '').split(';').where((d) => d.isNotEmpty).toList();
    if (days.length != 1) return '';
    final p = days.single.split('-');
    final m = int.tryParse(p[0]) ?? 0, d = int.tryParse(p.length > 1 ? p[1] : '') ?? 0;
    if (m < 1 || m > 12 || d < 1) return '';
    return 'Памет на $d ${_months[m - 1]}';
  }

  return [
    for (final e in lives)
      () {
        final (mode, slug) = modeSlug(e);
        if (mode != 'life') {
          final mem = memory(slug);
          return e.placed(
              section: _secHymns,
              typeLabel: [e.typeLabel, if (mem.isNotEmpty) mem].join(' · '));
        }
        if (isReferenceSlug(slug)) return e.placed(section: 'Справочник');
        if (isTeofanNoteSlug(slug)) return e.placed(section: 'Свт. Теофан Затворник');
        if (isSlovoSlug(slug)) return e.placed(section: 'Слова');
        if (isDniSlug(slug) || isTipikonSlug(slug)) {
          return e.placed(section: 'Богослужебни указания');
        }
        if (isArticleSlug(slug)) return e.placed(section: 'Статии от azbyka.ru');
        final src = info[slug]?.$1 ?? '';
        return e.placed(
          section: src.contains('azbyka.ru') ? _secAzbyka : _secBg,
          typeLabel: memory(slug),
        );
      }(),
  ];
}

/// Всички отметки — по раздели, в разделите по групи.
Future<List<BookmarkEntry>> allBookmarkEntries(SaintLookup lookup) async {
  final all = [
    ...await _placedLives(lookup),
    ...await bookBookmarkEntries(),
  ];
  // Разделът и групата се нареждат по най-скорошната си отметка — така
  // четеното сега стои най-отгоре.
  final newestSection = <String, int>{}, newestGroup = <String, int>{};
  for (final e in all) {
    final g = '${e.section}\u0000${e.group}';
    if ((newestSection[e.section] ?? 0) < e.savedAtMs) newestSection[e.section] = e.savedAtMs;
    if ((newestGroup[g] ?? 0) < e.savedAtMs) newestGroup[g] = e.savedAtMs;
  }
  return all
    ..sort((a, b) {
      if (a.section != b.section) {
        final c = newestSection[b.section]!.compareTo(newestSection[a.section]!);
        return c != 0 ? c : a.section.compareTo(b.section);
      }
      final ga = '${a.section}\u0000${a.group}', gb = '${b.section}\u0000${b.group}';
      if (ga != gb) {
        final c = newestGroup[gb]!.compareTo(newestGroup[ga]!);
        return c != 0 ? c : ga.compareTo(gb);
      }
      return b.savedAtMs.compareTo(a.savedAtMs);
    });
}
