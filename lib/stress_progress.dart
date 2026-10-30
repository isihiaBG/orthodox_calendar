// Напредъкът на речника на ударенията — за тома на месеца.
//
// Мерено на 30.10.2026 върху седем напълно оправени жития (15–17 октомври,
// томът + вариантите от azbyka): поправка искат ≈ 12,4 % от уникалните
// словоформи. Нужните за тома са толкова от неговите форми; оправените —
// формите му, които речникът знае (пакетът + неизпратените от устройството).
// Скриптът на сметката: docs/notes/tts-audio.md.

import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const kStressNeedShare = 0.124;

const _months = ['яну', 'фев', 'мар', 'апр', 'май', 'юни', 'юли', 'авг', 'сеп', 'окт', 'ное', 'дек'];
/// Месецът на тома за днес — по стар стил (томовете са по него).
int churchMonth([DateTime? now]) =>
    (now ?? DateTime.now()).subtract(const Duration(days: 13)).month;

final _formsCache = <int, Future<Set<String>>>{};

/// Уникалните словоформи (с гласна, малки букви) в тома на месеца [m].
Future<Set<String>> volumeForms(int m) => _formsCache[m] ??= () async {
      final mm = m.toString().padLeft(2, '0');
      final data = await rootBundle
          .load('assets/books/Жития на светиите - $mm(${_months[m - 1]}) - Димитрий Ростовски.epub');
      return compute(_forms, data.buffer.asUint8List());
    }();

Set<String> _forms(Uint8List bytes) {
  final word = RegExp(r'[А-Яа-яЍѝ]+');
  final vowel = RegExp('[аеиоуъюяѝ]');
  final out = <String>{};
  for (final f in ZipDecoder().decodeBytes(bytes).files) {
    if (!f.isFile || !f.name.endsWith('.xhtml')) continue;
    final s = utf8.decode(f.content as List<int>, allowMalformed: true)
        .replaceAll(RegExp(r'<sup.*?</sup>', dotAll: true), '')
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .replaceAll('́', '');
    for (final m in word.allMatches(s)) {
      final w = m[0]!.toLowerCase();
      if (vowel.hasMatch(w)) out.add(w);
    }
  }
  return out;
}
