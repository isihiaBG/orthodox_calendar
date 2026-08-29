// bible_ref.dart
//
// Разчитане на библейска препратка от вида, с който са записани линковете
// в житията и в томовете по св. Димитрий Ростовски:
//
//     https://azbyka.ru/biblia/?Apok.12:3,20:2&bg~utfcs
//                              ^^^^^^^^^^^^^^
//
// Тук се разчита само подчертаната част — книгата и местата в нея. Езиците
// след „&" НЕ се пипат: коя двойка преводи да се покаже решава четецът, по
// избора на човека, а не препратката отпреди сто години.
//
// ⚠ ЗАЩО СОБСТВЕН ПАРСЪР, а не един регекс. Формите са четиринайсет и се
// разминават по смисъл, не само по вид — виж таблицата в `parseBibleRef`.
// Един израз, който ги хване всичките, не може да ги РАЗЛИЧИ, а точно
// различаването е работата тук.

import 'package:meta/meta.dart';

bool _sameRanges(List<VerseRange> a, List<VerseRange> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Диапазон стихове ВЪТРЕ в една глава. Единичен стих е диапазон с [from]
/// == [to] — така подир това няма два случая, а един.
@immutable
class VerseRange {
  final int from;
  final int to;

  const VerseRange(this.from, this.to);
  const VerseRange.single(int v)
      : from = v,
        to = v;

  bool contains(int verse) => verse >= from && verse <= to;
  bool get isSingle => from == to;

  /// „3" или „3-12" — както се пише в съкратената препратка.
  String get label => isSingle ? '$from' : '$from-$to';

  @override
  bool operator ==(Object other) =>
      other is VerseRange && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(from, to);

  @override
  String toString() => label;
}

/// Един ПАСАЖ — местата, поискани в ЕДНА глава на ЕДНА книга.
///
/// ⚠ Пасажът е групиран по ГЛАВА, не по диапазон: „Мк.9:43,45" е ЕДИН пасаж
/// с два диапазона, а не два пасажа. Така „чети в контекст" има точно един
/// смисъл — главата, — а маркираните места в нея може да са колкото искат.
@immutable
class BiblePassage {
  /// Кодът на книгата, както е в `books.code` — „Mt", „Ps", „1Pet".
  final String book;
  final int chapter;

  /// Празен списък значи ЦЯЛАТА глава („Лк.15") — там няма какво да се
  /// маркира, защото цитатът е самата глава.
  final List<VerseRange> ranges;

  const BiblePassage({
    required this.book,
    required this.chapter,
    this.ranges = const [],
  });

  bool get isWholeChapter => ranges.isEmpty;

  bool marks(int verse) {
    for (final r in ranges) {
      if (r.contains(verse)) return true;
    }
    return false;
  }

  /// Стиховете, поискани тук, по ред и без повторения — за екрана „цитат
  /// без контекст".
  List<int> get verses {
    final out = <int>[];
    for (final r in ranges) {
      for (var v = r.from; v <= r.to; v++) {
        if (!out.contains(v)) out.add(v);
      }
    }
    out.sort();
    return out;
  }

  /// „5:3-12" / „12:3" / „15" — БЕЗ името на книгата. То се долепя от
  /// [BibleRef.label], който има достъп до съкращенията ѝ.
  String get whereLabel =>
      isWholeChapter ? '$chapter' : '$chapter:${ranges.map((r) => r.label).join(',')}';

  @override
  bool operator ==(Object other) =>
      other is BiblePassage &&
      other.book == book &&
      other.chapter == chapter &&
      _sameRanges(other.ranges, ranges);

  @override
  int get hashCode => Object.hash(book, chapter, Object.hashAll(ranges));

  @override
  String toString() => '$book.$whereLabel';
}

/// Цялата препратка — един или няколко пасажа.
@immutable
class BibleRef {
  final List<BiblePassage> passages;

  const BibleRef(this.passages);

  bool get isEmpty => passages.isEmpty;

  /// Вярно, когато препратката иска ЕДНА глава изцяло — „Лк.15".
  ///
  /// ⚠ Такива са 303 от 6369-те препратки в проекта и за тях междинният
  /// екран „цитат без контекст" е безсмислен: той би показал буквално
  /// същото, което и контекстът. Отиват направо в главата.
  bool get isWholeChapterOnly =>
      passages.length == 1 && passages.first.isWholeChapter;

  /// Различните глави, засегнати от препратката, по реда на срещане.
  List<BiblePassage> get byChapter => passages;
}

/// Разчита тялото на препратка към azbyka.ru.
///
/// Формите, срещани в проекта (сверено срещу всичките 6369 линка в
/// `lives.db` и дванайсетте тома):
///
///     Mt.5:17              глава 5, стих 17
///     Jn.4:5-42            глава 4, стихове 5–42
///     Rom.8:35,38          глава 8, стихове 35 и 38
///     Apok.12:3,20:2       глава 12 стих 3 И глава 20 стих 2
///     Jn.15:20-21,26-27    глава 15, стихове 20–21 и 26–27
///     Lk.15                цялата глава 15
///     Act.14,22            глава 14, стих 22        ⚠ виж по-долу
///     Act.15,20-29         глава 15, стихове 20–29  ⚠ виж по-долу
///     1King.5-7            главите 5 до 7
///     Act.13:4-14:28       от глава 13 стих 4 до глава 14 стих 28
///
/// ⚠ ЗАПЕТАЯТА ЗНАЧИ ДВЕ РАЗЛИЧНИ НЕЩА и това е най-лесното място за тиха
/// грешка. В „Act.14,22" тя стои ВМЕСТО двоеточие (глава 14, стих 22), а в
/// „Mk.9:43,45" въвежда ВТОРИ стих в същата глава. Различават се по това
/// дали ПРЕДИ нея вече е имало двоеточие. Формата с 197 срещания я има само
/// в `lives.db`; в томовете не се среща.
///
/// Връща празен [BibleRef], ако нищо не се разчита — викащият тогава пуска
/// препратката навън, вместо да отвори празен екран.
BibleRef parseBibleRef(String raw) {
  // Отрязваме езиците: „Ps.111:2&bg~utfcs" → „Ps.111:2".
  var body = raw.trim();
  final amp = body.indexOf('&');
  if (amp >= 0) body = body.substring(0, amp);
  if (body.isEmpty) return const BibleRef([]);

  final dot = body.indexOf('.');
  if (dot <= 0) return const BibleRef([]);
  final book = body.substring(0, dot);
  final rest = body.substring(dot + 1).trim();
  if (rest.isEmpty) return const BibleRef([]);

  final parts = rest.split(',');
  final out = <BiblePassage>[];
  int? current; // главата, към която се отнасят парчетата без двоеточие

  for (var i = 0; i < parts.length; i++) {
    final part = parts[i].trim();
    if (part.isEmpty) continue;

    if (part.contains(':')) {
      final cross = _parseCrossChapter(book, part);
      if (cross != null) {
        out.addAll(cross);
        current = cross.last.chapter;
        continue;
      }
      final colon = part.indexOf(':');
      final ch = int.tryParse(part.substring(0, colon).trim());
      final range = _parseRange(part.substring(colon + 1));
      if (ch == null || range == null) continue;
      current = ch;
      _add(out, book, ch, range);
      continue;
    }

    // Парче БЕЗ двоеточие.
    if (current == null) {
      // Първото парче. Ако подире му има още, то обикновено е ГЛАВАТА, а те
      // са нейните стихове („Act.14,22" = глава 14, стих 22).
      //
      // ⚠ ОСВЕН когато следващото носи СВОЕ двоеточие. „1Sam.1,2:1-21" значи
      // цялата глава 1 И глава 2 стихове 1–21 — там първото парче е
      // самостоятелен пасаж, не префикс. Без тази проверка глава 1 изчезваше
      // мълчаливо: препратката се отваряше, показваше по-малко от искането и
      // нищо не подсказваше, че липсва.
      final nextHasColon =
          i + 1 < parts.length && parts[i + 1].contains(':');
      if (i + 1 < parts.length && !nextHasColon) {
        current = int.tryParse(part);
        if (current == null) return const BibleRef([]);
        continue;
      }
      if (nextHasColon) {
        final only = int.tryParse(part);
        if (only == null) return const BibleRef([]);
        out.add(BiblePassage(book: book, chapter: only));
        continue;
      }
      // Едно-единствено парче: цяла глава или диапазон ГЛАВИ.
      final dash = part.indexOf('-');
      if (dash > 0) {
        final a = int.tryParse(part.substring(0, dash).trim());
        final b = int.tryParse(part.substring(dash + 1).trim());
        if (a == null || b == null || b < a) return const BibleRef([]);
        for (var c = a; c <= b; c++) {
          out.add(BiblePassage(book: book, chapter: c));
        }
        return BibleRef(out);
      }
      final only = int.tryParse(part);
      if (only == null) return const BibleRef([]);
      out.add(BiblePassage(book: book, chapter: only));
      return BibleRef(out);
    }

    // Следващо парче без двоеточие — стих(ове) в текущата глава.
    final range = _parseRange(part);
    if (range == null) continue;
    _add(out, book, current, range);
  }

  return BibleRef(out);
}

/// „13:4-14:28" — от глава 13 стих 4 до глава 14 стих 28.
///
/// ⚠ Разпознава се по това, че СЛЕД тирето пак има двоеточие. Само 5
/// срещания в целия проект, но без тази проверка „13:4-14:28" се чете като
/// „глава 13, стихове 4 до 14" — тихо и правдоподобно грешно.
List<BiblePassage>? _parseCrossChapter(String book, String part) {
  final dash = part.indexOf('-');
  if (dash < 0) return null;
  final left = part.substring(0, dash);
  final right = part.substring(dash + 1);
  if (!left.contains(':') || !right.contains(':')) return null;

  final l = left.split(':');
  final r = right.split(':');
  final ch1 = int.tryParse(l[0].trim());
  final v1 = int.tryParse(l[1].trim());
  final ch2 = int.tryParse(r[0].trim());
  final v2 = int.tryParse(r[1].trim());
  if (ch1 == null || v1 == null || ch2 == null || v2 == null) return null;
  if (ch2 < ch1) return null;

  // Първата глава — от стиха до края; средните — цели; последната — до стиха.
  //
  // ⚠ „До края" се пише като голямо число, а не като истинския брой стихове:
  // той зависи от превода (Септуагинтата и Масоретският текст се разминават),
  // а тук няма достъп до базата. Маркирането и без това пита „в диапазона ли
  // е този стих", тъй че таван над всяка възможна номерация върши работа.
  const toEnd = 999;
  final out = <BiblePassage>[];
  if (ch1 == ch2) {
    out.add(BiblePassage(
        book: book, chapter: ch1, ranges: [VerseRange(v1, v2)]));
    return out;
  }
  out.add(BiblePassage(
      book: book, chapter: ch1, ranges: [VerseRange(v1, toEnd)]));
  for (var c = ch1 + 1; c < ch2; c++) {
    out.add(BiblePassage(book: book, chapter: c));
  }
  out.add(BiblePassage(book: book, chapter: ch2, ranges: [VerseRange(1, v2)]));
  return out;
}

/// „3" или „3-12" → диапазон. Връща null при боклук.
VerseRange? _parseRange(String s) {
  final t = s.trim();
  if (t.isEmpty) return null;
  final dash = t.indexOf('-');
  if (dash > 0) {
    final a = int.tryParse(t.substring(0, dash).trim());
    final b = int.tryParse(t.substring(dash + 1).trim());
    if (a == null || b == null) return null;
    return b < a ? VerseRange(a, a) : VerseRange(a, b);
  }
  final v = int.tryParse(t);
  return v == null ? null : VerseRange.single(v);
}

/// Добавя диапазон, като слива с вече започнатия пасаж за същата глава.
///
/// ⚠ Групирането е по ГЛАВА, за да има „чети в контекст" точно един смисъл.
/// Без него „Мк.9:43,45" би дало два пасажа и два еднакви бутона една под
/// друг, сочещи към една и съща глава.
void _add(List<BiblePassage> out, String book, int chapter, VerseRange range) {
  for (var i = 0; i < out.length; i++) {
    if (out[i].book == book && out[i].chapter == chapter) {
      final merged = [...out[i].ranges, range];
      out[i] = BiblePassage(book: book, chapter: chapter, ranges: merged);
      return;
    }
  }
  out.add(BiblePassage(book: book, chapter: chapter, ranges: [range]));
}

/// Сглобява резултат от търсене в пасажи, ГРУПИРАНИ ПО ГЛАВА.
///
/// ⚠ Групирането не е разкрасяване, а условие за скоростта: четецът чете
/// всяка група с отделна заявка, тъй че 300 отделни стиха биха значели 300
/// заявки към базата. Групирани, те падат до толкова, колкото са засегнатите
/// глави. Пътьом излиза и по-добрият надпис — „Мат. 5:3,7,9" вместо три пъти
/// „Мат. 5".
///
/// Редът на първо срещане се пази — той идва подреден от [BibleDb.searchText]
/// (по каноничния ред на книгите, после по глава и стих).
List<BiblePassage> groupFoundVerses(
    List<({String book, int chapter, String verse})> found) {
  final byChapter = <String, List<int>>{};
  final order = <String>[];
  for (final r in found) {
    final n = int.tryParse(r.verse);
    if (n == null) continue;
    final key = '${r.book}|${r.chapter}';
    final list = byChapter[key];
    if (list == null) {
      order.add(key);
      byChapter[key] = [n];
    } else {
      list.add(n);
    }
  }

  final out = <BiblePassage>[];
  for (final key in order) {
    final parts = key.split('|');
    final verses = byChapter[key]!..sort();
    out.add(BiblePassage(
      book: parts[0],
      chapter: int.parse(parts[1]),
      ranges: [for (final v in verses) VerseRange.single(v)],
    ));
  }
  return out;
}
