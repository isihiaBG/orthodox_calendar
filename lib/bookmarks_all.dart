// bookmarks_all.dart
//
// Събира отметките от ДВАТА четеца в един списък.
//
// Този файл е единственото място, което познава и двете страни: житията
// (reader_screen) и книгите (book_reader). Затова самият списък
// (bookmarks.dart) остава чист — иначе се получава кръгов внос, защото
// четците на свой ред отварят списъка.
//
// Подредбата: първо житията, после книгите, събрани по томове. Вътре във
// всяка част — най-скорошното отгоре.

import 'package:flutter/material.dart';

import 'book_position_store.dart';
import 'book_reader.dart';
import 'bookmarks.dart';
import 'epub_source.dart';
import 'reader_screen.dart';
import 'saint_expandable_tile.dart' show SaintLookup;

/// Заглавието на тома, както се изписва над групата.
///
/// Вади се от името на файла, а не от самия .epub: така списъкът се показва
/// мигновено, без да отваря дузина архива само за да напише заглавия.
String bookTitleFromPath(String assetPath) {
  var name = assetPath.split('/').last;
  if (name.endsWith('.epub')) {
    name = name.substring(0, name.length - '.epub'.length);
  }
  return name.replaceAll(' - Димитрий Ростовски', '');
}

/// Отметките от книгите, преведени към общия вид на списъка.
Future<List<BookmarkEntry>> bookBookmarkEntries() async {
  final records = await BookPositionStore.loadAll();
  return [
    for (final r in records)
      BookmarkEntry(
        id: 'book:${r.assetPath}|${r.href}',
        title: r.pos.chapterTitle,
        // Денят е адресът на четивото в тома; без него заглавието на
        // житието не казва кога се чете.
        typeLabel:
            r.pos.parentTitle.isEmpty ? 'Четиво от книга' : r.pos.parentTitle,
        group: bookTitleFromPath(r.assetPath),
        savedAtMs: r.pos.savedAtMs,
        delete: () => BookPositionStore.clear(r.assetPath, r.href),
        open: (context) async {
          // Томът се отваря чак сега — иначе списъкът би чакал всички.
          final book = await EpubBook.open(r.assetPath);
          if (!context.mounted) return;
          final chapters =
              book.toc.expand((e) => e.flattened()).where((e) => e.href.isNotEmpty);
          EpubTocEntry? start;
          for (final e in chapters) {
            if (e.href == r.href) {
              start = e;
              break;
            }
          }
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

/// Всички отметки — житията и книгите заедно.
Future<List<BookmarkEntry>> allBookmarkEntries(SaintLookup lookup) async {
  final lives = await livesBookmarkEntries(lookup);
  final books = await bookBookmarkEntries();

  lives.sort((a, b) => b.savedAtMs.compareTo(a.savedAtMs));

  // Книгите се подреждат по томове, а томовете — по най-скорошната отметка
  // в тях. Така книгата, която човек чете сега, стои най-отгоре.
  final byBook = <String, List<BookmarkEntry>>{};
  for (final e in books) {
    byBook.putIfAbsent(e.group, () => []).add(e);
  }
  final groups = byBook.keys.toList()
    ..sort((a, b) {
      int newest(String g) => byBook[g]!
          .map((e) => e.savedAtMs)
          .reduce((x, y) => x > y ? x : y);
      return newest(b).compareTo(newest(a));
    });

  return [
    ...lives,
    for (final g in groups)
      ...(byBook[g]!..sort((a, b) => b.savedAtMs.compareTo(a.savedAtMs))),
  ];
}
