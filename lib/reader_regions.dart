// reader_regions.dart
//
// Делението на четивото на РЕГИОНИ — ОБЩО за четеца на жития и за четеца на
// книги.
//
// Регионът е единицата, с която работят и търсенето, и отметките, и
// точното позициониране: всеки получава свой ключ, а оттам и реална
// геометрия в скрола. Вътре в него редът се намира с TextPainter (виж
// text_line_locator.dart) — но за да има „вътре в него", първо трябва да го
// има самия регион.
//
// Изнесено от reader_screen.dart, когато същото потрябва и на книгите.
// Правилото за втория абзац при буквицата е тънко и не бива да се пише
// втори път: единственият начин да останат еднакви е да е едно място.

/// Един „регион" от документа.
///
/// [isHtml] true → рисува се през flutter_html (обикновен абзац/блок).
/// [isHtml] false → буквицата (плосък текст, собствен рендер).
class ReaderRegion {
  final bool isHtml;
  final String content;

  /// САМО за региона с буквицата: следващият абзац, който може да влезе
  /// вдясно от нея, ако първият не запълва редовете ѝ. Той се маха от
  /// списъка с обикновени региони, за да не се изпише два пъти.
  final String second;

  const ReaderRegion.html(this.content)
      : isHtml = true,
        second = '';
  const ReaderRegion.dropcapPlain(this.content, {this.second = ''})
      : isHtml = false;
}

/// Дели HTML на блокове по абзаци/заглавия.
List<String> splitBlocks(String html) {
  final blocks = <String>[];
  final re = RegExp(
    r'<(p|h[1-6])\b[^>]*>.*?</\1>',
    dotAll: true,
    caseSensitive: false,
  );
  int cursor = 0;
  for (final m in re.allMatches(html)) {
    if (m.start > cursor) {
      final gap = html.substring(cursor, m.start).trim();
      if (gap.isNotEmpty) blocks.add(gap);
    }
    blocks.add(m.group(0)!);
    cursor = m.end;
  }
  if (cursor < html.length) {
    final tail = html.substring(cursor).trim();
    if (tail.isNotEmpty) blocks.add(tail);
  }
  return blocks.isEmpty ? [html] : blocks;
}

/// Сглобява регионите на едно четиво.
///
/// Редът е: каквото стои преди буквицата (заглавие, ред с паметта), после
/// самата буквица (с евентуалния изтеглен до нея втори абзац), после
/// останалите блокове.
List<ReaderRegion> computeRegions(
  String beforeHtml,
  String dropCap,
  String firstP,
  String afterHtml,
) {
  final regions = <ReaderRegion>[];
  if (dropCap.isNotEmpty) {
    if (beforeHtml.trim().isNotEmpty) regions.add(ReaderRegion.html(beforeHtml));
    final blocks = splitBlocks(afterHtml);
    // Следващият блок отива при буквицата САМО ако е обикновен абзац:
    // заглавие или центриран курсив не бива да се притискат в тясната
    // колона. Ако не потрябва, кутията си го изписва под буквицата — на
    // мястото, където би стоял и без това.
    var second = '';
    if (blocks.isNotEmpty) {
      final m = RegExp(r'^<p>(.*)</p>$', dotAll: true).firstMatch(blocks.first);
      if (m != null) {
        second = m.group(1)!;
        blocks.removeAt(0);
      }
    }
    regions.add(ReaderRegion.dropcapPlain(firstP, second: second));
    for (final block in blocks) {
      regions.add(ReaderRegion.html(block));
    }
  } else {
    for (final block in splitBlocks(beforeHtml)) {
      regions.add(ReaderRegion.html(block));
    }
  }
  return regions;
}
