// Проверка на parseBibleRef срещу ВСИЧКИ реални препратки в проекта.
//
// Не проверява само „не гърми ли" — това е слаба проверка. За всяка
// препратка се прави ОБРАТНО сглобяване от разчетеното и се сравнява със
// самата нея; разминаването се показва. Така тиха грешка в смисъла (напр.
// „Act.14,22" прочетено като две глави) излиза наяве.

import 'dart:io';
import '../../lib/bible_ref.dart';

/// Сглобява обратно съкратения запис от разчетеното.
String rebuild(BibleRef ref) {
  if (ref.isEmpty) return '';
  final book = ref.passages.first.book;
  final parts = <String>[];
  int? prev;
  for (final p in ref.passages) {
    if (p.isWholeChapter) {
      parts.add('${p.chapter}');
      prev = p.chapter;
      continue;
    }
    for (var i = 0; i < p.ranges.length; i++) {
      final r = p.ranges[i];
      if (i == 0 && p.chapter != prev) {
        parts.add('${p.chapter}:${r.label}');
      } else {
        parts.add(r.label);
      }
    }
    prev = p.chapter;
  }
  return '$book.${parts.join(',')}';
}

void main() {
  // Списъкът се прави от `extract_refs.py` до този файл.
  final lines = File('tools/bible_refs/refs.txt')
      .readAsLinesSync()
      .where((l) => l.trim().isNotEmpty)
      .toList();

  var ok = 0, empty = 0;
  final mismatches = <String>[];
  final wholeChapter = <String>[];

  for (final raw in lines) {
    final ref = parseBibleRef(raw);
    if (ref.isEmpty) {
      empty++;
      mismatches.add('ПРАЗЕН   $raw');
      continue;
    }
    if (ref.isWholeChapterOnly) wholeChapter.add(raw);
    final back = rebuild(ref);
    if (back == raw) {
      ok++;
    } else {
      mismatches.add('$raw  ->  $back');
    }
  }

  print('препратки      : ${lines.length}');
  print('обратно същите : $ok');
  print('празни         : $empty');
  print('цяла глава     : ${wholeChapter.length}');
  print('разминавания   : ${mismatches.length}');
  print('--- ПРАЗНИ (нищо не се разчете) ---');
  for (final m in mismatches.where((m) => m.startsWith('ПРАЗЕН'))) {
    print('   $m');
  }

  // Смисловите случаи, които трябва да са ТОЧНО така.
  print('\n--- смислови проверки ---');
  void check(String raw, String expect) {
    final got = parseBibleRef(raw).passages.toString();
    print('${got == expect ? "OK " : "ГРЕШКА "} $raw\n     очаквано $expect\n     полу'
        'чено  $got');
  }

  check('Act.14,22', '[Act.14:22]');
  check('Mk.9:43,45', '[Mk.9:43,45]');
  check('Apok.12:3,20:2', '[Apok.12:3, Apok.20:2]');
  check('Act.15,20-29', '[Act.15:20-29]');
  check('Lk.15', '[Lk.15]');
  check('1King.5-7', '[1King.5, 1King.6, 1King.7]');
  check('Jn.15:20-21,26-27', '[Jn.15:20-21,26-27]');
  check('Mt.5:17', '[Mt.5:17]');
  check('1Sam.1,2:1-21', '[1Sam.1, 1Sam.2:1-21]');
  print('Mt.22,:21 -> ' + parseBibleRef('Mt.22,:21').passages.toString());
  print('Ps.33,20  -> ' + parseBibleRef('Ps.33,20').passages.toString());
  print('Mk.12:35-37,14:62 -> ' + parseBibleRef('Mk.12:35-37,14:62').passages.toString());
  print('Jn.3:1-21,7:50-52,19:38-42 -> ' + parseBibleRef('Jn.3:1-21,7:50-52,19:38-42').passages.toString());
}
