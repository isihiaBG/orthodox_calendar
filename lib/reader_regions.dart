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

/// Какъв е регионът.
///
/// ⚠ Добавен, когато видовете станаха три. Дотук стигаше булево `isHtml`;
/// то остава като изведено свойство, за да не се пипат местата, които го
/// четат — но НОВ код да пита `kind`, инак илюстрацията се обърква с
/// буквицата (и двете не са html).
enum RegionKind {
  /// Обикновен абзац или блок — рисува се през flutter_html.
  html,

  /// Буквицата: плосък текст със собствен рендер и обтичане.
  dropCap,

  /// Илюстрация с надпис, около която текстът се обтича (само в ЛЕГНАЛО
  /// положение — в изправено тя си остава обикновен блок).
  illustration,
}

/// Един „регион" от документа.
class ReaderRegion {
  final RegionKind kind;
  final String content;

  /// САМО за региона с буквицата: следващите абзаци, по ред, които МОГАТ
  /// да влязат вдясно от нея, ако мястото стигне (при по-голяма буквица —
  /// по няколко наведнъж, виж drop_cap.dart). Махат се от списъка с
  /// обикновени региони, за да не се изпишат втори път — самата буквица
  /// решава колко от тях реално застават до нея, а остатъкът пада в
  /// собствената ѝ опашка.
  ///
  /// При [RegionKind.illustration] значи същото, но за текста, който
  /// обтича картинката отстрани.
  final List<String> rest;

  /// САМО за илюстрация: пътят до изображението, надписът под него и
  /// съотношението му (ширина/височина).
  ///
  /// ⚠ Съотношението идва от атрибутите в текста, а не от файла: `Image`
  /// не знае размера си, преди да се зареди, а мястото се смята преди това.
  final String? imageAsset;
  final String? captionHtml;
  final double imageAspect;

  const ReaderRegion.html(this.content)
      : kind = RegionKind.html,
        rest = const [],
        imageAsset = null,
        captionHtml = null,
        imageAspect = 0;

  const ReaderRegion.dropcapPlain(this.content, {this.rest = const []})
      : kind = RegionKind.dropCap,
        imageAsset = null,
        captionHtml = null,
        imageAspect = 0;

  /// Илюстрация с обтичащ текст.
  ///
  /// [content] е първият абзац след картинката, [rest] — следващите, които
  /// също влизат в обтичането.
  const ReaderRegion.illustration({
    required String asset,
    required this.imageAspect,
    this.captionHtml,
    this.content = '',
    this.rest = const [],
  })  : kind = RegionKind.illustration,
        imageAsset = asset;

  /// Стар флаг — пази се, за да не се пипат местата, които вече го четат.
  ///
  /// ⚠ Илюстрацията НЕ е html регион (тя има собствен рендер), тъй че се
  /// държи като буквицата тук. Нов код да пита [kind].
  bool get isHtml => kind == RegionKind.html;

  /// Регионът, сглобен обратно като HTML — картинка, надпис, абзаци.
  ///
  /// ⚠ Ползва се при ТЕСЕН екран, където обтичане няма смисъл: тогава
  /// блокът се изписва точно както преди групирането. Така тесният случай
  /// минава по вече изпитания път (flutter_html), а не по нов код — и
  /// търсенето, отметките и позиционирането там остават непроменени.
  String get illustrationHtml {
    final b = StringBuffer();
    if (imageAsset != null) {
      b.write('<img src="$imageAsset"');
      if (imageAspect > 0) {
        // Съотношението се връща като двойка числа — четецът смята с тях,
        // а не с файла (виж LivesImageExtension защо).
        b.write(' width="1000" height="${(1000 / imageAspect).round()}"');
      }
      b.write('>');
    }
    if (captionHtml != null && captionHtml!.isNotEmpty) b.write(captionHtml);
    if (content.isNotEmpty) b.write(wrapFlowBlock(content));
    for (final p in rest) {
      b.write(wrapFlowBlock(p));
    }
    return b.toString();
  }

  /// Текстът, който обтича картинката — за рисуване и за броене на
  /// съвпаденията при търсене.
  ///
  /// ⚠ Блокът може да е и ЗАГЛАВИЕ, не само абзац (виж `_groupIllustrations`).
  /// Заглавието носи своя таг и минава както е; само голият текст на абзац
  /// се обвива в `<p>`. Обвито и заглавието, то би загубило стила си и би
  /// изглеждало като обикновен ред.
  String get flowHtml {
    final b = StringBuffer();
    if (content.isNotEmpty) b.write(wrapFlowBlock(content));
    for (final p in rest) {
      b.write(wrapFlowBlock(p));
    }
    return b.toString();
  }
}

/// Връща блока готов за изписване: заглавието носи своя таг, съдържанието на
/// абзац се обвива обратно в `<p>`.
///
/// ⚠ РЕШАВА СЕ ПО БЛОКОВИЯ ТАГ, не по „започва ли с '<'". Дотук условието
/// беше второто и абзац, започващ с вътрешен таг — `<em>Запази вярата
/// непорочна…</em>` — оставаше БЕЗ обвивка. Тогава flutter_html го слепваше
/// със следващите такива в един параграф: три отделни молитвени абзаца се
/// изписваха като един, без отстояние помежду им. (Открито при мерене на
/// геометрията, 31.08.2026 — там трите излизаха като един блок от 441 знака.)
String wrapFlowBlock(String s) {
  final head = s.trimLeft().toLowerCase();
  final isBlock = RegExp(r'^<(p|h[1-6]|div|img|ul|ol|blockquote)\b').hasMatch(head);
  return isBlock ? s : '<p>$s</p>';
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

/// Групира илюстрациите с надписа и текста, който ще ги обтича.
///
/// ⚠ Групирането се прави ВИНАГИ, независимо от ширината на екрана.
/// Решението „обтичане или не" се взима при РИСУВАНЕТО, защото зависи от
/// наличното място, а то се мени в движение (завъртане, разделен екран).
/// Регионите се строят веднъж и не бива да зависят от текущата геометрия —
/// инак всяко завъртане би искало пресъздаването им, а върху тях стъпват
/// търсенето, отметките и позиционирането.
///
/// Взимат се най-много [maxFlow] абзаца: толкова се побират до картинка,
/// висока колкото 8–10 реда. Останалите си остават самостоятелни региони —
/// така виртуализацията не глътва половин житие в един widget.
/// Групиране на илюстрациите с текста, който ги обтича.
///
/// ⚠ Първият подход даваше на картинката ДЯЛ от ТЕКУЩАТА ширина, тъй че при
/// всяко завъртане тя се преоразмеряваше и височината ѝ се менеше. А
/// `SliverVariedExtentList` заковава височината на региона предварително, по
/// оценка — и оценката гонеше движеща се цел. Оттам преливането: текст и
/// заглавия минаваха ВЪРХУ картинките (31.08.2026).
///
/// Сега основата е `shortestSide` — ширината от ИЗПРАВЕНО положение, която НЕ
/// се мени при завъртане (идея на потребителя). Височината е известна
/// предварително, а текстовата колона е предвидима и еднаква за всички
/// илюстрации. Виж [illustrationFlowWidth].
/// ⚠ ЧЕТИРИ ОПИТА СЕ ПРОВАЛИХА, преди причината да излезе наяве
/// (31.08.2026) — записано, за да не се тръгне пак по грешния път:
///
///   1. дял от текущата ширина      → текстът преливаше върху картинката
///   2. + оценка с височината       → преливането остана
///   3. + широките на цял ред       → добави изрязване от кутията
///   4. база от изправено (45%)     → картинките се смалиха и в изправено
///
/// Всичките четири гонеха ЧИСЛА, а причината беше СТРУКТУРНА и на съвсем
/// друго място: измерващият (Offstage) слой в `reader_screen.dart` имаше
/// само два клона — html и „всичко останало" → буквицата. Илюстрационният
/// регион не е html, тъй че се МЕРЕШЕ КАТО БУКВИЦА: премерваше се съвсем
/// друг widget от нарисувания.
///
/// ⚠ Оттам идваха НАВЕДНЪЖ и трите симптома — текст върху картинката,
/// изрязване и празни полета. Търсени бяха като три отделни бъга.
///
/// Поуката: при разминаване между премерено и нарисувано, първо провери
/// дали двете строят ЕДИН И СЪЩ widget, преди да пипаш сметките.
const bool kIllustrationFlowEnabled = true;

List<ReaderRegion> _groupIllustrations(List<String> blocks) {
  if (!kIllustrationFlowEnabled) {
    return [for (final b in blocks) ReaderRegion.html(b)];
  }
  final out = <ReaderRegion>[];
  // ⚠ Атрибутите се вадят с ОТДЕЛНИ изрази, не с един лаком.
  //
  // Първата версия беше един израз с НЕЗАДЪЛЖИТЕЛНИ групи за `width`/`height`
  // и `[^>]*` накрая. Той съвпадаше, без да ги улови — поглъщаше ги в
  // остатъка — и съотношението излизаше НУЛА. Оттам картинката получаваше
  // кутия с произволна пропорция, `BoxFit.contain` я вписваше по височина и
  // тя се свиваше до ~половината от реда. Симптомът се четеше като „не се
  // разпъва", а разтягането изобщо не се стигаше (31.08.2026).
  final imgRe = RegExp(r'^<img\b[^>]*>$', caseSensitive: false);
  final srcRe = RegExp(r'src="([^"]+)"', caseSensitive: false);
  final wRe = RegExp(r'width="(\d+)"', caseSensitive: false);
  final hRe = RegExp(r'height="(\d+)"', caseSensitive: false);
  final capRe = RegExp(r'^<p class="caption">', caseSensitive: false);
  final pRe = RegExp(r'^<p>(.*)</p>$', dotAll: true);
  // ⚠ Взимат се ПОВЕЧЕ кандидати, отколкото реално ще влязат в зоната до
  // картинката. Кои от тях застават там решава РИСУВАНЕТО — то единствено
  // знае колко е висока картинката при текущата ширина. Останалите изтичат
  // под нея, на пълен ред.
  //
  // Същият похват като при буквицата (`rest` в drop_cap.dart): регионът
  // подава кандидатите, а самият widget решава колко се побират.
  const maxFlow = 8;

  var i = 0;
  while (i < blocks.length) {
    final block = blocks[i];
    final m = imgRe.firstMatch(block.trim());
    if (m == null) {
      out.add(ReaderRegion.html(block));
      i++;
      continue;
    }

    // ⚠ Всеки атрибут със СВОЙ израз — виж бележката при [imgRe] защо.
    final tag = m.group(0)!;
    final srcM = srcRe.firstMatch(tag);
    if (srcM == null) {
      out.add(ReaderRegion.html(block));
      i++;
      continue;
    }
    final asset = srcM.group(1)!;
    final w = double.tryParse(wRe.firstMatch(tag)?.group(1) ?? '') ?? 0;
    final h = double.tryParse(hRe.firstMatch(tag)?.group(1) ?? '') ?? 0;
    i++;

    // Надписът, ако го има — той принадлежи на картинката и върви с нея.
    String? caption;
    if (i < blocks.length && capRe.hasMatch(blocks[i].trim())) {
      caption = blocks[i];
      i++;
    }

    // Блоковете, които ще обтичат картинката.
    //
    // ⚠ ЗАГЛАВИЯТА ВЕЧЕ ВЛИЗАТ (31.08.2026, по искане на потребителя).
    // Дотук поредицата спираше на първото заглавие — с довода, че в тясна
    // колона то се разсипва. На практика излизаше обратното: зоната до
    // картинката оставаше полупразна, а заглавието се озоваваше под
    // изображението с голямо бяло поле над себе си.
    //
    // ⚠ Спира само на ДРУГА КАРТИНКА: две илюстрации една до друга нямат
    // къде да съберат текст помежду си.
    final flow = <String>[];
    final imgAhead = RegExp(r'^<img\b', caseSensitive: false);
    while (i < blocks.length && flow.length < maxFlow) {
      final block = blocks[i].trim();
      if (imgAhead.hasMatch(block)) break;
      final pm = pRe.firstMatch(block);
      // Абзац влиза без обвивката си, заглавие — както е (то носи тага си).
      flow.add(pm != null ? pm.group(1)! : block);
      i++;
    }

    out.add(ReaderRegion.illustration(
      asset: asset,
      imageAspect: (w > 0 && h > 0) ? w / h : 0,
      captionHtml: caption,
      content: flow.isNotEmpty ? flow.first : '',
      rest: flow.length > 1 ? flow.sublist(1) : const [],
    ));
  }
  return out;
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
    regions.addAll(_groupIllustrations(blocks));
  } else {
    for (final block in splitBlocks(beforeHtml)) {
      regions.add(ReaderRegion.html(block));
    }
  }
  return regions;
}
