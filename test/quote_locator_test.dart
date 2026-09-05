// Разгъването на свития локатор — [resolveQuoteLocator].
//
// ⚠⚠ ТУК СЕ ПРОЯВИ РЕАЛЕН БЪГ (06.09.2026): при свиването префиксът „OEBPS/"
// се губеше и разгънатият адрес сочеше „Text/index_split_NNN.xhtml" вместо
// „OEBPS/Text/…". Четивото не се намираше в тома и при всеки споделен цитат
// от „Месецослов" излизаше „Четивото вече го няма в книгата."
//
// ⚠ Свиването (`compactBookLocator`) беше ИЗПРАВНО и тест за него минаваше;
// сгрешена беше само обратната посока. Оттам поуката: при двупосочно
// преобразуване се проверява КРЪГЪТ, не едната посока.

import 'package:flutter_test/flutter_test.dart';
import 'package:orthodox_calendar/quote_link.dart';
import 'package:orthodox_calendar/quote_locator.dart';
import 'package:orthodox_calendar/quotes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const realPath = 'assets/books/Жития на светиите - 09(сеп) - Димитрий '
      'Ростовски.epub|OEBPS/Text/index_split_397.xhtml';

  QuoteAnchor book(String locator) => QuoteAnchor(
      source: QuoteSource.book,
      locator: locator,
      block: 3,
      charStart: 10,
      charLength: 20);

  test('⚠⚠ КРЪГЪТ: свиване → разгъване дава СЪЩИЯ път', () async {
    final c = compactBookLocator(realPath)!;
    final marker =
        '$kLocatorMarker${c.$1.toString().padLeft(2, '0')}/${c.$2}';
    final back = await resolveQuoteLocator(book(marker));
    expect(back.locator, realPath);
  });

  test('⚠ разгънатото носи префикса „OEBPS/"', () async {
    final back = await resolveQuoteLocator(book('${kLocatorMarker}09/397'));
    expect(back.locator, endsWith('|OEBPS/Text/index_split_397.xhtml'));
  });

  test('номерът на главата се допълва до ТРИ цифри', () async {
    final back = await resolveQuoteLocator(book('${kLocatorMarker}01/4'));
    expect(back.locator, endsWith('index_split_004.xhtml'));
  });

  test('немаркиран локатор минава непокътнат', () async {
    final back = await resolveQuoteLocator(book(realPath));
    expect(back.locator, realPath);
  });

  test('непознат том не гърми — връща се какъвто е', () async {
    final back = await resolveQuoteLocator(book('${kLocatorMarker}99/1'));
    expect(back.locator, '${kLocatorMarker}99/1');
  });
}
