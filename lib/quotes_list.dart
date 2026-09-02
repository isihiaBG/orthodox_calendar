// Любимите цитати като списък — превежда [Quote] към общия [BookmarkEntry].
//
// ⚠ Отделен файл по същата причина като `bookmarks_all.dart`: той е
// единственото място, което познава И списъка, И четците. Сложено вътре в
// `bookmarks.dart`, това затваря кръгов внос — четците на свой ред отварят
// списъка.

import 'package:flutter/material.dart';

import 'bookmarks.dart';
import 'quotes.dart';

/// Запазените цитати, готови за общия екран.
///
/// ⚠ Подредбата е НАЙ-СКОРОШНОТО ОТГОРЕ и БЕЗ ГРУПИ. Отметките се събират по
/// томове, защото един том носи стотици четива и без заглавия списъкът се
/// чете като каша. Цитатите са малко и идват отвсякъде — група „Жития",
/// „Книги", „Библия" би сложила по два реда под всяко заглавие.
Future<List<BookmarkEntry>> quoteEntries() async {
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
          // ⚠ ОТВАРЯНЕТО ОЩЕ НЕ Е СВЪРЗАНО. Ще мине по същия път, по който
          // ще минава и споделеният линк — през [locateQuote], за да е един
          // механизъм, а не два. Дотогава редът се показва и се трие, но не
          // води наникъде: по-честно от това да отвори четивото „някъде".
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Отварянето на цитат още не е готово'),
              duration: Duration(seconds: 2),
            ),
          );
        },
      ),
  ];
}

/// Отваря списъка с любими цитати.
void openQuotesList(BuildContext context) {
  Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => BookmarksListScreen(
      load: quoteEntries,
      screenTitle: 'Любими цитати',
      emptyText: 'Няма запазени цитати.\n'
          'Маркирай текст в четиво и избери „Запази цитат".',
    ),
  ));
}
