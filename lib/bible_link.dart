// bible_link.dart
//
// Библейските препратки в житията вече се отварят ВЪТРЕ в приложението.
//
// Дотук всяка от тях беше външна: тапваш „(Мт. 25:40)" насред житие, питат
// те дали да излезеш навън, отваря се браузър, зарежда се azbyka.ru — и,
// ако си без мрежа, не се случва нищо. А текстът го има на устройството:
// приложението носи цялото Писание на два превода.
//
// ⚠ ЕДНО МЯСТО ЗА ТРИТЕ ЧЕТЕЦА. Житията (`reader_screen`), томовете
// (`book_reader`) и мини четецът в дневния изглед минават през `openExternal`
// — тъй че и прихващането стои тук, до него, а не преписано на три места.
// Първата поправка, която мине само през едното, ражда мълчаливо разминаване
// (точно както се случи с менюто зад трите точки, виж CLAUDE.md).

import 'package:flutter/material.dart';

import 'bible_db.dart';
import 'bible_reader.dart';
import 'bible_ref.dart';
import 'external_link.dart';

/// Разпознава адрес към Писанието в azbyka.ru и вади разчетената препратка.
///
/// ⚠ Адресът се РАЗКОДИРА пръв. В томовете „&" вътре в атрибут стои като
/// `&amp;`, тъй че без това тялото на препратката би включвало „amp;" и
/// разчитането щеше да се спъне в него — същият капан, който вече веднъж
/// накара azbyka.ru да отваря всичко на църковнославянски (виж
/// external_link.dart).
BibleRef? bibleRefFromUrl(String rawUrl) {
  final url = decodeHref(rawUrl);
  final m = RegExp(r'azbyka\.ru/biblia/\?([^&\s"]+)').firstMatch(url);
  if (m == null) return null;
  final ref = parseBibleRef(m.group(1)!);
  return ref.isEmpty ? null : ref;
}

/// Отваря библейска препратка вътрешно. Връща `false`, ако не е поела — тогава
/// викащият я праща навън, както преди.
///
/// ⚠ Проверява се, че книгата НАИСТИНА я има в `bible.db`, преди да се отвори
/// каквото и да е. Разчитането е чиста работа с низове и ще приеме „Xyz.1:1"
/// за напълно редовна препратка; без проверката тук четецът би се отворил на
/// празен екран, вместо препратката просто да излезе навън. Четири от
/// 4109-те препратки в проекта са и повредени в самия източник
/// („Lev.4-775-785"), тъй че този път не е теоретичен.
Future<bool> openBibleLink(BuildContext context, String rawUrl) async {
  final ref = bibleRefFromUrl(rawUrl);
  if (ref == null) return false;

  final book = await BibleDb.book(ref.passages.first.book);
  if (book == null) return false;
  if (!context.mounted) return false;

  await Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => BibleReader.forRef(ref)),
  );
  return true;
}
