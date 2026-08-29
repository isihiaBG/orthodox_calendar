// search_match.dart
//
// Разчитането на търсената заявка и намирането ѝ в текст.
//
// ⚠ ТЪРСИ СЕ ПО КЛЮЧОВИ ДУМИ, НЕ ПО ТОЧНА ФРАЗА. Написаното се разделя по
// интервали и всяка дума се търси поотделно; стихът е намерен, когато ги
// съдържа ВСИЧКИТЕ, независимо в какъв ред и на какво разстояние.
//
// Причината е практическа: „содом гомор" трябва да намери „…Содомски и
// Гоморски…", а като фраза не намира нищо — между двете стои „и", а и двете
// думи са в друга форма. Търсенето в Писанието е асоциативно: човек помни две
// думи от стиха, не подредбата им.
//
// ⚠ Думите се търсят като ПОДНИЗ, не по цяла дума. Българският е силно
// флективен („Содом" → „Содомски", „содомската"), а човек пише основата.
// Цената е, че къса дума се среща и вътре в чужди („ад" в „адрес"); приема
// се, защото обратното — да не намери очевидното — дразни много повече.

import 'package:meta/meta.dart';

/// Думите от заявката, изчистени и снижени.
///
/// ⚠ Празните парчета отпадат — иначе двоен интервал ражда празна дума, която
/// съвпада навсякъде и обезсмисля цялото условие.
List<String> searchTerms(String query) => [
      for (final w in query.trim().toLowerCase().split(RegExp(r'\s+')))
        if (w.isNotEmpty) w
    ];

/// Едно съвпадение в текста: [start, end).
@immutable
class MatchRange {
  final int start;
  final int end;
  const MatchRange(this.start, this.end);

  @override
  bool operator ==(Object other) =>
      other is MatchRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);
}

/// Всички места в [text], където стои която и да е от [terms].
///
/// Резултатът е подреден по начало и БЕЗ застъпвания: съседни или преплетени
/// съвпадения се сливат в едно.
///
/// ⚠ Сливането е нужно, защото думите може да се застъпват в самия текст —
/// „сод одом" върху „Содом" дава две припокриващи се находки, а два фона един
/// върху друг рисуват по-тъмна ивица там, където се пресичат.
List<MatchRange> matchRanges(String text, List<String> terms) {
  if (terms.isEmpty || text.isEmpty) return const [];
  final hay = text.toLowerCase();
  final found = <MatchRange>[];
  for (final t in terms) {
    var from = 0;
    while (true) {
      final at = hay.indexOf(t, from);
      if (at < 0) break;
      found.add(MatchRange(at, at + t.length));
      from = at + 1; // +1, не +дължина: „аа" в „ааа" е на две места
    }
  }
  if (found.isEmpty) return const [];
  found.sort((a, b) => a.start.compareTo(b.start));

  final out = <MatchRange>[found.first];
  for (final r in found.skip(1)) {
    final last = out.last;
    if (r.start <= last.end) {
      if (r.end > last.end) out[out.length - 1] = MatchRange(last.start, r.end);
    } else {
      out.add(r);
    }
  }
  return out;
}

/// Съдържа ли текстът ВСИЧКИ думи.
bool containsAllTerms(String text, List<String> terms) {
  if (terms.isEmpty) return false;
  final hay = text.toLowerCase();
  for (final t in terms) {
    if (!hay.contains(t)) return false;
  }
  return true;
}
