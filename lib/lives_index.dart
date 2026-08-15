// lives_index.dart
//
// Указателят номер → житие в томовете по св. Димитрий Ростовски.
//
// За какво служи: в томовете има 1342 кръстосани препратки във вида
// `../zhitija-svjatykh/1143`. Числото е номерът на статията в azbyka.ru, а
// същият номер стои и като `id` на заглавието на съответното житие, тъй че
// препратката може да се отвори ВЪТРЕ в приложението.
//
// ⚠ Нито една препратка не сочи в СЪЩИЯ том — проверено за всичките 1342.
// Житие от май праща към главното житие на светията, което е в декември.
// Затова прескокът почти винаги значи отваряне на ДРУГА книга.
//
// Указателят се прави от tools/build_lives_index.py и се пакетира като
// assets/lives_index.json (1155 записа, 293 KB). НЕ се сглобява в движение:
// това би значело да се разархивират дванайсет тома по 2 MB точно в мига,
// в който човек чака да види текст.

import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

/// Едно житие в указателя.
class LifeRef {
  /// Името на файла в assets/books/.
  final String book;

  /// Пътят на главата ВЪТРЕ в архива — точно както го дава EpubBook.
  final String href;

  final String title;

  const LifeRef({required this.book, required this.href, required this.title});
}

class LivesIndex {
  static Map<String, LifeRef>? _cache;

  /// Чете се веднъж и остава в паметта: 1155 записа са нищо, а препратките
  /// се тапват често.
  static Future<Map<String, LifeRef>> load() async {
    final cached = _cache;
    if (cached != null) return cached;
    final raw = await rootBundle.loadString('assets/lives_index.json');
    final data = json.decode(raw) as Map<String, dynamic>;
    final out = <String, LifeRef>{};
    data.forEach((k, v) {
      final m = v as Map<String, dynamic>;
      out[k] = LifeRef(
        book: m['book'] as String,
        href: m['href'] as String,
        title: m['title'] as String,
      );
    });
    _cache = out;
    return out;
  }

  /// Номерът от препратка към житие, или null.
  ///
  /// Хваща само формата `../zhitija-svjatykh/N`. Другите препратки към
  /// azbyka.ru — към Йоан Златоуст, Ефрем Сирин, деянията на съборите и към
  /// Писанието — НЕ се пипат: те сочат чужди издания и си остават външни.
  static String? numberOf(String href) =>
      RegExp(r'(?:^|/)zhitija-svjatykh/(\d+)$').firstMatch(href)?.group(1);
}
