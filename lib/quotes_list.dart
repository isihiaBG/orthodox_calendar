// Любимите цитати като списък — превежда [Quote] към общия [BookmarkEntry].
//
// ⚠ Отделен файл по същата причина като `bookmarks_all.dart`: той е
// единственото място, което познава И списъка, И четците. Сложено вътре в
// `bookmarks.dart`, това затваря кръгов внос — четците на свой ред отварят
// списъка.

import 'package:flutter/material.dart';

import 'bookmarks.dart';
import 'book_reader.dart';
import 'epub_source.dart';
import 'quote_link.dart';
import 'quotes.dart';
import 'reader_screen.dart';
import 'saint_expandable_tile.dart' show SaintLookup;

/// Запазените цитати, готови за общия екран.
///
/// ⚠ Подредбата е НАЙ-СКОРОШНОТО ОТГОРЕ и БЕЗ ГРУПИ. Отметките се събират по
/// томове, защото един том носи стотици четива и без заглавия списъкът се
/// чете като каша. Цитатите са малко и идват отвсякъде — група „Жития",
/// „Книги", „Библия" би сложила по два реда под всяко заглавие.
Future<List<BookmarkEntry>> quoteEntries(SaintLookup lookup) async {
  final quotes = await QuotesStore.load();
  quotes.sort((a, b) => b.savedAtMs.compareTo(a.savedAtMs));

  return [
    for (final q in quotes)
      BookmarkEntry(
        id: 'quote:${q.id}',
        // ⚠ САМИЯТ ЦИТАТ е заглавието на реда, а четивото — подзаглавието.
        // Обратното (както е при отметките) би било грешка тук: човек търси
        // в този списък откъса, който е харесал, а не къде го е намерил.
        title: q.text,
        typeLabel: q.title,
        group: '',
        savedAtMs: q.savedAtMs,
        delete: () => QuotesStore.remove(q.id),
        open: (context) async {
          // ⚠ СЪЩИЯТ ПЪТ, ПО КОЙТО ЩЕ МИНАВА И СПОДЕЛЕНИЯТ ЛИНК — затова
          // четецът получава `ParsedQuoteLink`, а не самия [Quote]: така
          // единият механизъм служи и на двата случая и не могат да се
          // разминат.
          switch (q.anchor.source) {
            case QuoteSource.life:
              final texts = await lookup(q.anchor.locator);
              if (!context.mounted) return;
              if (texts == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Няма запис за този светия.')),
                );
                return;
              }
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => ReaderScreen.life(
                  texts: texts,
                  lookup: lookup,
                  // ⚠ И САМИЯТ ТЕКСТ, не само отпечатъкът. Без него четецът
                  // го вади от блока ПО КООРДИНАТИ — а те може да са
                  // разместени и тогава маркирането търси грешно нещо.
                  // Тук текстът е налице; няма причина да се гадае.
                  openAtQuote: ParsedQuoteLink(
                    anchor: q.anchor,
                    fingerprint: fingerprint(q.text),
                    text: q.text,
                  ),
                ),
              ));
            case QuoteSource.book:
              await openBookQuote(context, q.anchor, fingerprint(q.text),
                  text: q.text);
            case QuoteSource.bible:
              // ⚠ Още не е свързано — казва се направо.
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Отварянето от Библията още не е готово'),
                ),
              );
          }
        },
      ),
  ];
}

/// Отваря цитат от том на „Месецослов".
///
/// ⚠ `locator` е „път до тома|href на главата" — двете заедно, защото един
/// том носи стотици четива, а href сам по себе си не казва от коя книга е.
Future<void> openBookQuote(BuildContext context, QuoteAnchor anchor, String fp,
    {String text = ''}) async {
  final parts = anchor.locator.split('|');
  if (parts.length < 2) return;
  final book = await EpubBook.open(parts[0]);
  if (!context.mounted) return;
  final entry = book.toc
      .expand((e) => e.flattened())
      .where((e) => e.href == parts[1])
      .firstOrNull;
  if (entry == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Четивото вече го няма в книгата.')),
    );
    return;
  }
  Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => BookReader(
      book: book,
      start: entry,
      openAtQuote:
          ParsedQuoteLink(anchor: anchor, fingerprint: fp, text: text),
    ),
  ));
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

/// Отваря списъка с любими цитати.
void openQuotesList(BuildContext context, SaintLookup lookup) {
  Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => BookmarksListScreen(
      load: () => quoteEntries(lookup),
      screenTitle: 'Любими цитати',
      emptyText: 'Няма запазени цитати.\n'
          'Маркирай текст в четиво и избери „Запази цитат".',
    ),
  ));
}
