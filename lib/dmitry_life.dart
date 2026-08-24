// dmitry_life.dart
//
// Отваря житие по Димитрий Ростовски по номер (id на статията в
// azbyka.ru, същият, който вече ползва lives_index.dart за кръстосаните
// препратки вътре в книгите) — от ЪГЪЛ извън BookReader (дневния изглед,
// „Празници", „Пости"). Винаги отваря НОВ четец, директно (push), БЕЗ
// графичния Cover Flow преход на библиотеката — огледално на
// BookReader._openLife(), но там има и допълнителен клон за "същия том",
// който тук няма смисъл (няма "текущ том" извън самия четец).
//
// Бутонът "назад" се грижи сам за себе си — BookReader си ползва обикновен
// BackButton()/pop(), връща се в екрана, който е направил push-а.

import 'package:flutter/material.dart';

import 'book_reader.dart';
import 'epub_source.dart';
import 'lives_index.dart';

/// Връща false, ако номерът липсва в указателя или главата не се намери
/// (напр. томовете са презаписани и href-ите вече не съвпадат).
Future<bool> openDmitryLife(BuildContext context, int num) async {
  final index = await LivesIndex.load();
  final ref = index[num.toString()];
  if (ref == null) return false;

  final book = await EpubBook.open('assets/books/${ref.book}');
  final entry = book.toc
      .expand((e) => e.flattened())
      .where((e) => e.href == ref.href)
      .firstOrNull;
  if (entry == null || !context.mounted) return false;

  await Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => BookReader(book: book, start: entry),
  ));
  return true;
}
