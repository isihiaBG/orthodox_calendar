// text_line_locator.dart
//
// „На кой ПИКСЕЛ вътре в този абзац пада тази буква?"
//
// Заради това съществува файлът. Дотук и двата четеца позиционираха груба
// сметка: четецът на жития подкарваше `ensureVisible` върху цял регион (а
// регионът може да е 89% от четивото — тогава съвпадение в средата му пада
// извън екрана), а четецът на книги умножаваше съотношение по
// `maxScrollExtent`, което приема, че всички редове са еднакво високи.
//
// Тук се мери истински, с `TextPainter`, при ТЕКУЩИЯ размер на шрифта и
// ТЕКУЩАТА ширина на колоната. Затова резултатът е точен, а не пропорция:
// `getOffsetForCaret` връща горния ръб на реда, в който стои буквата.
//
// ⚠ Мерещият TextPainter трябва да е огледален на рисуването — същият
// шрифт, размер, междуредие, ширина и същите парчета (получер, курсив,
// горен индекс сменят ширината на текста и местят пренасянията). Затова
// парчетата идват от [htmlRuns] в drop_cap.dart, а не от гол текст: така
// мерещият и рисуващият виждат едно и също.
//
// Какво НЕ се пази никъде: номер на ред. Той се мени с размера на шрифта и
// записан в отметка след време сочи другаде. Пази се индекс на ЗНАК —
// единственото инвариантно спрямо мащаба — а редът и пикселът се смятат
// наново при всяко отваряне.

import 'package:flutter/material.dart';

import 'drop_cap.dart';
import 'reader_text_utils.dart';

/// Измерен абзац: знае за всяка своя буква на кой ред и на кой пиксел е.
class LineLocator {
  final TextPainter _painter;

  /// Чистият текст, така както го вижда мерещият — слепените парчета от
  /// [htmlRuns]. Индексите навън са в ТОЗИ текст.
  final String text;

  /// Парчетата и началото на всяко от тях в [text].
  final List<HtmlRun> _runs;
  final List<int> _runStarts;

  LineLocator._(this._painter, this.text, this._runs, this._runStarts);

  /// Мери един абзац HTML.
  ///
  /// [base] носи шрифта, размера и междуредието на абзаца — те трябва да са
  /// същите като в `readerStyles`, иначе пренасянията се разминават.
  factory LineLocator.forHtml({
    required String html,
    required TextStyle base,
    required double maxWidth,
    TextAlign align = TextAlign.justify,
  }) {
    final runs = htmlRuns(html);
    final buf = StringBuffer();
    final starts = <int>[];
    final spans = <InlineSpan>[];
    for (final r in runs) {
      starts.add(buf.length);
      buf.write(r.text);
      spans.add(TextSpan(
        text: r.text,
        style: base.copyWith(
          fontWeight: r.bold ? FontWeight.bold : null,
          fontStyle: r.italic ? FontStyle.italic : null,
          // Горният индекс се РИСУВА повдигнат, но за пренасянията значение
          // има само че е по-дребен. Повдигането не мени ширината.
          fontSize: r.sup ? (base.fontSize ?? 16) * kSupScale : null,
        ),
      ));
    }
    final painter = TextPainter(
      text: TextSpan(children: spans, style: base),
      textDirection: TextDirection.ltr,
      textAlign: align,
    )..layout(maxWidth: maxWidth);
    return LineLocator._(painter, buf.toString(), runs, starts);
  }

  /// Горният ръб на реда, в който попада знак [charIndex].
  double dyForChar(int charIndex) {
    final i = charIndex.clamp(0, text.length);
    return _painter
        .getOffsetForCaret(TextPosition(offset: i), Rect.zero)
        .dy;
  }

  /// Височината на реда, в който попада знак [charIndex] — за да може
  /// извикващият да поиска да се покаже целият ред, не само горният му ръб.
  double lineHeightForChar(int charIndex) {
    final dy = dyForChar(charIndex);
    for (final m in _painter.computeLineMetrics()) {
      final top = m.baseline - m.ascent;
      if (dy >= top - 0.5 && dy < top + m.height + 0.5) return m.height;
    }
    return _painter.preferredLineHeight;
  }

  /// Първият знак на реда, който се пада на пиксел [dy].
  ///
  /// Обратното на [dyForChar] — с него отметката записва знак вместо
  /// пиксел и така преживява смяна на размера на шрифта.
  int charAtDy(double dy) =>
      _painter.getPositionForOffset(Offset(0, dy.clamp(0, height))).offset;

  double get height => _painter.height;

  int get lineCount => _painter.computeLineMetrics().length;

  /// Началото на [ordinal]-тото (броено от 0) срещане на заявката.
  ///
  /// ⚠ Броенето е ПО ПАРЧЕТА (по едно между два тага), не по слепения текст.
  /// Не е прищявка: четците броят съвпаденията точно така
  /// (`_countMatchesHtml`) и маркирането ги номерира така. Броим ли иначе,
  /// поредността тук се разминава с тяхната и стрелките „напред/назад"
  /// започват да сочат съседно съвпадение. Цената е, че съвпадение,
  /// разкрачено през таг, не се вижда — но то не се вижда и при тях.
  int? charOfMatch(String foldedQuery, int ordinal) {
    if (foldedQuery.isEmpty || ordinal < 0) return null;
    var seen = 0;
    for (int i = 0; i < _runs.length; i++) {
      final folded = fold(_runs[i].text);
      var from = 0;
      while (true) {
        final at = folded.text.indexOf(foldedQuery, from);
        if (at < 0) break;
        if (seen == ordinal) return _runStarts[i] + folded.origIndex[at];
        seen++;
        from = at + foldedQuery.length;
      }
    }
    return null;
  }

  /// Позициите на ВСИЧКИ съвпадения — с ЕДНО обхождане.
  ///
  /// ⚠⚠ [charOfMatch] сканира от начало за всяко поредно съвпадение И
  /// СГЪВА текста на всяко парче наново. Извикан в цикъл по `k` (както
  /// правеха и двата четеца), той е квадратичен на два пъти: по брой
  /// съвпадения и по сгъване. Регион с 50 съвпадения значеше 50 обхождания
  /// на целия абзац с 50 пълни сгъвания на всяко негово парче.
  ///
  /// ⚠ Резултатът е ЕДИН КЪМ ЕДИН с `[for (k) charOfMatch(q, k)]` — същият
  /// ред на обхождане, същото броене. Сменен е само редът на работа.
  /// (Измерено на реална глава от 100 KB, 04.09.2026: 954 ms → 93 ms само
  /// от изнасянето на locator-а от цикъла, и още толкова оттук.)
  List<int> allMatchChars(String foldedQuery) {
    if (foldedQuery.isEmpty) return const [];
    final out = <int>[];
    for (int i = 0; i < _runs.length; i++) {
      final folded = fold(_runs[i].text);
      var from = 0;
      while (true) {
        final at = folded.text.indexOf(foldedQuery, from);
        if (at < 0) break;
        out.add(_runStarts[i] + folded.origIndex[at]);
        from = at + foldedQuery.length;
      }
    }
    return out;
  }

  /// Колко съвпадения има в този абзац — по същото броене като [charOfMatch].
  int countMatches(String foldedQuery) {
    if (foldedQuery.isEmpty) return 0;
    var n = 0;
    for (final r in _runs) {
      final folded = fold(r.text);
      var from = 0;
      while (true) {
        final at = folded.text.indexOf(foldedQuery, from);
        if (at < 0) break;
        n++;
        from = at + foldedQuery.length;
      }
    }
    return n;
  }

  void dispose() => _painter.dispose();
}
