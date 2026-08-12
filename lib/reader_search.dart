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
/// <a href="...">...</a> се третира като ЦЯЛОСТЕН блок, обработван ОТДЕЛНО
/// от _anchorText — flutter_html принудително презаписва стила на
/// ВСЕКИ вложен span вътре в котва със собствения стил на котвата (виж
/// InteractiveElementBuiltIn._processInteractableChild в пакета), затова
/// <span class="hit"> вътре в <a> губи жълтия си фон и изчезва визуално.
/// Вместо да вмъкваме span, разделяме самата котва на съседни <a> тагове
/// със същия href — само фрагментът със съвпадението носи class="hit",
/// получавайки собствен смесен стил (синьо + жълт фон). Всичко останало
/// продължава по старата таг/текст логика, непроменена.
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
        final at = folded.text.indexOf(foldedQuery, from);
        if (at < 0) break;
        final origStart = folded.origIndex[at];
        final endFoldedIdx = at + foldedQuery.length - 1;
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

  final anchorRe = RegExp(
    r'<a\b[^>]*?href="([^"]*)"[^>]*>(.*?)</a>',
    caseSensitive: false,
    dotAll: true,
  );
  int cursor = 0;
  for (final am in anchorRe.allMatches(html)) {
    if (am.start > cursor) {
      highlightPlainSegment(html.substring(cursor, am.start));
    }
    local = _anchorText(
      am.group(1)!,
      am.group(2)!,
      foldedQuery,
      firstGlobalIndex,
      local,
      currentGlobalIndex,
      buf,
    );
    cursor = am.end;
  }
  if (cursor < html.length) {
    highlightPlainSegment(html.substring(cursor));
  }
  return buf.toString();
}

/// Маркиране на съвпадение ВЪТРЕ в линк (виж коментара на highlightHtml).
/// Приема, че вътрешността на <a> е чист текст (важи за всички линкове в
/// това приложение — saint:// и източник-атрибуцията, без вложено
/// форматиране). Връща новата стойност на local (брояча за "текущо"
/// съвпадение), за да продължи броенето непрекъснато след котвата.
int _anchorText(
  String href,
  String innerText,
  String foldedQuery,
  int firstGlobalIndex,
  int localStart,
  int currentGlobalIndex,
  StringBuffer buf,
) {
  final hrefAttr = 'href="$href"';
  final folded = fold(innerText);
  int from = 0, lastEnd = 0, local = localStart;
  while (true) {
    final at = folded.text.indexOf(foldedQuery, from);
    if (at < 0) break;
    final origStart = folded.origIndex[at];
    final endFoldedIdx = at + foldedQuery.length - 1;
    final origEnd = folded.origIndex[endFoldedIdx] + 1;
    if (origStart > lastEnd) {
      buf.write('<a $hrefAttr>');
      buf.write(innerText.substring(lastEnd, origStart));
      buf.write('</a>');
    }
    final isCurrent = (firstGlobalIndex + local) == currentGlobalIndex;
    buf.write('<a $hrefAttr class="${isCurrent ? 'hit-current' : 'hit'}">');
    buf.write(innerText.substring(origStart, origEnd));
    buf.write('</a>');
    lastEnd = origEnd;
    local++;
    from = endFoldedIdx + 1;
  }
  if (lastEnd < innerText.length) {
    buf.write('<a $hrefAttr>');
    buf.write(innerText.substring(lastEnd));
    buf.write('</a>');
  } else if (lastEnd == 0) {
    // Няма съвпадение в тази котва — оставяме я непроменена (един таг).
    buf.write('<a $hrefAttr>');
    buf.write(innerText);
    buf.write('</a>');
  }
  return local;
}
