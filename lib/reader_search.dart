// reader_search.dart
//
// Търсенето в текст при четене — ОБЩОТО между четеца на жития и четеца на
// книги.
//
// Тук живее само това, което наистина е едно и също: маркирането на
// намереното. Останалото (лентата за въвеждане, движението между
// съвпаденията, скролът дотам) е различно в двата екрана, защото житието е
// разделено на региони с оценени височини, а главата от книга е един
// непрекъснат блок.
//
// Сравнението е БЕЗ ударения и регистър — виж fold() в
// reader_text_utils.dart. Затова се пази и картата на позициите: маркира
// се оригиналният откъс, с ударенията му, а не изгладеният.

import 'reader_text_utils.dart';

/// Маркира съвпаденията в HTML — обвива всяко в <span class="hit(-current)">.
///
/// Вътре във връзка намереното също се увива в span, а самата връзка остава
/// цяла — виж бележката при `anchorRe` защо не обратното.
String highlightHtml(
  String html,
  String foldedQuery,
  int firstGlobalIndex,
  int currentGlobalIndex,
) {
  if (foldedQuery.isEmpty) return html;
  final buf = StringBuffer();
  int local = 0;

  void highlightPlainSegment(String segment) {
    for (final m in RegExp(r'<[^>]+>|[^<]+').allMatches(segment)) {
      final piece = m.group(0)!;
      if (piece.startsWith('<')) {
        buf.write(piece);
        continue;
      }
      final folded = fold(piece);
      int from = 0, lastEnd = 0;
      while (true) {
        final mm = nextFoldedMatch(folded.text, foldedQuery, from);
        if (mm == null) break;
        final at = mm.$1, len = mm.$2;
        final origStart = folded.origIndex[at];
        final endFoldedIdx = at + len - 1;
        final origEnd = folded.origIndex[endFoldedIdx] + 1;
        buf.write(piece.substring(lastEnd, origStart));
        final isCurrent = (firstGlobalIndex + local) == currentGlobalIndex;
        buf.write('<span class="${isCurrent ? 'hit-current' : 'hit'}">');
        buf.write(piece.substring(origStart, origEnd));
        buf.write('</span>');
        lastEnd = origEnd;
        local++;
        from = endFoldedIdx + 1;
      }
      buf.write(piece.substring(lastEnd));
    }
  }

  // ⚠⚠ Връзката остава ЦЯЛА, а намереното вътре в нея се увива в
  // <span class="hit">, както навсякъде другаде. Дотук котвата се цепеше
  // на няколко <a>, а класът се слагаше върху самото <a> — и flutter_html
  // (3.0.0-beta.2) НЕ рисува фона на такъв клас: намереното във връзка се
  // броеше и обхождаше, но не светеше (докладвано от потребителя,
  // 03.10.2026). Измерено с тест по пикселите: `<a class="hit">` — 0 жълти
  // пиксела, `<a><span class="hit">` — 669.
  final anchorRe = RegExp(
    r'(<a\b[^>]*>)(.*?)</a>',
    caseSensitive: false,
    dotAll: true,
  );
  int cursor = 0;
  for (final am in anchorRe.allMatches(html)) {
    if (am.start > cursor) {
      highlightPlainSegment(html.substring(cursor, am.start));
    }
    buf.write(am.group(1));
    highlightPlainSegment(am.group(2)!);
    buf.write('</a>');
    cursor = am.end;
  }
  if (cursor < html.length) {
    highlightPlainSegment(html.substring(cursor));
  }
  return buf.toString();
}

