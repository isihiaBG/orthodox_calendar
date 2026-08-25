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

  /// САМО за региона с буквицата: следващите абзаци, по ред, които МОГАТ
  /// да влязат вдясно от нея, ако мястото стигне (при по-голяма буквица —
  /// по няколко наведнъж, виж drop_cap.dart). Махат се от списъка с
  /// обикновени региони, за да не се изпишат втори път — самата буквица
  /// решава колко от тях реално застават до нея, а остатъкът пада в
  /// собствената ѝ опашка.
  final List<String> rest;

  const ReaderRegion.html(this.content)
      : isHtml = true,
        rest = const [];
  const ReaderRegion.dropcapPlain(this.content, {this.rest = const []})
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
    // Всички ПОРЕДНИ обикновени абзаци в началото отиват при буквицата —
    // не само първият: с по-голяма буквица може да им стигне мястото на
    // повече от един. Заглавие или центриран курсив СПИРАТ поредицата
    // (не бива да се притискат в тясната колона) — оттам нататък блоковете
    // остават обикновени региони, изписват се където биха стояли и без
    // това. Самата буквица (drop_cap.dart) после решава колко от
    // изтеглените реално застават до нея — тук само ги подаваме готови.
    final rest = <String>[];
    final pRe = RegExp(r'^<p>(.*)</p>$', dotAll: true);
    // Таван на изтеглените абзаци — дори при най-голямата буквица (≈11 реда,
    // виж drop_cap_scale.dart) реално се побират най-много 3-4 до нея, а
    // всичко след първия непобрал се цял пада в опашката без значение колко
    // абзаца следват. Без таван поредица от много кратки абзаци в началото
    // (както при житие без подзаглавия) би „погълнала" почти целия текст в
    // региона на буквицата — един-единствен, невиртуализиран widget вместо
    // много малки региони, преизмерван изцяло при всяка смяна на шрифта.
    const maxRest = 6;
    while (blocks.isNotEmpty && rest.length < maxRest) {
      final m = pRe.firstMatch(blocks.first);
      if (m == null) break;
      rest.add(m.group(1)!);
      blocks.removeAt(0);
    }
    regions.add(ReaderRegion.dropcapPlain(firstP, rest: rest));
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
