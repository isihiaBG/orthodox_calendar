// drop_cap.dart
//
// Абзац с водеща буква (буквица) и ИСТИНСКО обтичане — знакът на
// приложението при четене.
//
// Изнесено от reader_screen.dart, за да го ползва и четецът на книги от
// „Месецослов": там буквицата се явява в началото на всяка глава/житие.
// Две реализации биха се разминали неусетно — механиката тук е фина
// (мери се с TextPainter, а празните полета се наследяват при изписване,
// но НЕ и при мерене), и точно такова нещо не бива да съществува два пъти.
//
// Widget-ът е самостоятелен: всичко влиза през конструктора — цветове,
// размери, търсене, обработка на тапнат линк. Не знае нищо за светии,
// книги и бази.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'reader_text_utils.dart';
import 'reader_theme.dart';

/// Едно парче текст с еднакво оформление — резултатът от разлагането на
/// HTML-а на началния абзац.
///
/// Наборът тагове там е ЗАКРИТ и проверен по цялата база: <a href>,
/// <strong>, <em> и <br>. Друг таг и друг атрибут не се срещат, затова
/// разборът е нарочно плосък, без дърво.
class HtmlRun {
  final String text;
  final bool bold;
  final bool italic;
  /// Горен индекс — номерът на бележка под линия. Рисува се смален и
  /// повдигнат; виж коментара при [kSupScale].
  final bool sup;
  final String? href;
  const HtmlRun(this.text,
      {this.bold = false, this.italic = false, this.sup = false, this.href});
}

/// Колко от размера на текста заема горният индекс. Същата стойност както в
/// reader_styles.dart, за да изглеждат еднакво в двата начина на рисуване.
const double kSupScale = 0.62;

/// Ляво/дясно изключение за буквицата — само за буквите, чийто дизайн в
/// Bukvica видимо ги избутва надясно (стърчащи орнаменти/връхчета), тъй че
/// без корекция изглеждат разместени спрямо лявата граница на текста. НЕ е
/// правило за всяка буква — само изрични изключения, установени на око от
/// потребителя (23.08.2026). Дял от РАЗМЕРА на буквицата (отрицателно =
/// наляво); прилага се еднакво в двата четеца и в PDF експорта, всеки
/// върху собствения си мащаб — виж [dropCapOffsetX].
///
/// „Д" винаги навлиза надясно заради острите си връхчета — нужна е по-
/// осезаема корекция наляво, дори с риск лявото връхче да излезе извън
/// подравняването на текста. „М" почти не се нуждае, но десните ѝ
/// орнаменти леко избутват основната лява линия — съвсем лека корекция.
/// Нова буква се добавя тук; стойността ѝ се определя ЕКСПЕРИМЕНТАЛНО
/// (на око), не по формула — виж бележката в CLAUDE.md.
const Map<String, double> kDropCapOffsetFactor = {
  'Д': -0.09,
  'М': -0.00,
  'В': -0.07,
  'Р': -0.04,
  'Ш': -0.13,
  'Щ': -0.02,
  'С': -0.02,
  'К': -0.01,
  'Ж':  0.00,
  'Ф':  0.00,
  'Ю': -0.00,
  'Х':  0.02,
};

/// Хоризонталното отместване (в пиксели/точки) за буквата [letter] при
/// размер [size] — dropCapSize в двата четеца, capFontSize в PDF-а.
/// Буква без изключение в [kDropCapOffsetFactor] дава 0 (без корекция).
///
/// [scaleMultiplier] — допълнителна корекция по МАЩАБА на буквицата (виж
/// DropCapScaleMetrics.offsetMultiplier в drop_cap_scale.dart): оптичните
/// поправки не е задължително да растат линейно с размера, затова има
/// собствена ос, а не просто по-голямо [size]. По подразбиране 1.0 (без
/// допълнителна корекция) — PDF експортът засега винаги подава 1.0, тъй
/// като все още няма трите размера.
double dropCapOffsetX(String letter, double size, {double scaleMultiplier = 1.0}) =>
    (kDropCapOffsetFactor[letter] ?? 0) * size * scaleMultiplier;

/// Три групи по РЕАЛНА ширина на глифа в Bukvica (от `hmtx`, не на око) —
/// виж измерването с fontTools в разговора от 24.08.2026. Буквите в
/// шрифта имат голяма амплитуда по ширина (от 0.224 до 0.555 от em, а Ъ/Ь
/// стигат чак 1.229 — практически неизползваеми като буквица, но все пак
/// класифицирани), а бялото петно за буквицата е ЕДНА обща ширина —
/// затова тесните букви зейват в него, а широките се притискат.
enum DropCapWidthGroup { narrow, normal, wide }

/// Границите (в дял от em, `hmtx`/`unitsPerEm`):
///   тесни   0.224–0.281  З Я Х Ч Ж С О У К Н И Й
///   средни  0.281–0.363  Т Ц П Ф Щ Е Л Р Г А Б В
///   широки  0.408+       Ю М Д Ш Ъ Ь
/// Разделено по ЕСТЕСТВЕНИ разриви в данните (виж разговора), не на равни
/// части — между „средни" и „широки" има реален скок (+0.045 при Ю, после
/// +0.118 при Д), докато тесни/средни са по-плавно разделени по средата.
const Map<String, DropCapWidthGroup> kDropCapWidthGroup = {
  'З': DropCapWidthGroup.narrow,
  'Я': DropCapWidthGroup.narrow,
  'Х': DropCapWidthGroup.narrow,
  'Ч': DropCapWidthGroup.narrow,
  'Ж': DropCapWidthGroup.narrow,
  'С': DropCapWidthGroup.narrow,
  'О': DropCapWidthGroup.narrow,
  'У': DropCapWidthGroup.narrow,
  'К': DropCapWidthGroup.narrow,
  'Н': DropCapWidthGroup.narrow,
  'И': DropCapWidthGroup.narrow,
  'Й': DropCapWidthGroup.narrow,
  'Т': DropCapWidthGroup.normal,
  'Ц': DropCapWidthGroup.normal,
  'П': DropCapWidthGroup.normal,
  'Ф': DropCapWidthGroup.normal,
  'Щ': DropCapWidthGroup.normal,
  'Е': DropCapWidthGroup.normal,
  'Л': DropCapWidthGroup.normal,
  'Р': DropCapWidthGroup.normal,
  'Г': DropCapWidthGroup.normal,
  'А': DropCapWidthGroup.normal,
  'Б': DropCapWidthGroup.normal,
  'В': DropCapWidthGroup.normal,
  'Ю': DropCapWidthGroup.wide,
  'М': DropCapWidthGroup.wide,
  'Д': DropCapWidthGroup.wide,
  'Ш': DropCapWidthGroup.wide,
  'Ъ': DropCapWidthGroup.wide,
  'Ь': DropCapWidthGroup.wide,
};

/// Буква без запис в [kDropCapWidthGroup] пада в „нормална" — безопасно по
/// подразбиране, а не изключение (за разлика от [kDropCapOffsetFactor]).
DropCapWidthGroup dropCapWidthGroupOf(String letter) =>
    kDropCapWidthGroup[letter] ?? DropCapWidthGroup.normal;

/// Множител върху ШИРИНАТА на бялото петно за буквицата — по група, за
/// ЧЕТЦИТЕ (двата). „Нормална" е нарочно 1.0: множителят възпроизвежда
/// сегашната ширина, не задава нова — за да е сравним между трите размера
/// на буквицата (dropCapSize), които вече се менят от настройките.
///
/// PDF експортът има СВОЙ, ОТДЕЛЕН комплект (виж pdf_export.dart) —
/// потвърдено от потребителя 24.08.2026, че пропорциите там се разминават
/// достатъчно от екрана, за да не може един комплект да свърши работа и на
/// двете места.
const Map<DropCapWidthGroup, double> kDropCapWidthFactor = {
  DropCapWidthGroup.narrow: 0.7,
  DropCapWidthGroup.normal: 0.8,
  DropCapWidthGroup.wide: 1.1,
};

/// Множителят за буквата [letter], готов за директно умножение по
/// сегашната ширина на бялото петно.
double dropCapWidthFactorFor(String letter) =>
    kDropCapWidthFactor[dropCapWidthGroupOf(letter)] ?? 1.0;

/// Разлага HTML на парчета. Публична, защото по същите парчета мери и
/// text_line_locator.dart — двете трябва да виждат ЕДИН И СЪЩ текст., като разкодира entity-тата и слепва поредните
/// интервали — точно както го прави и чистият текст, по който се мери.
List<HtmlRun> htmlRuns(String html) {
  final runs = <HtmlRun>[];
  var bold = 0;
  var italic = 0;
  var sup = 0;
  final hrefs = <String>[];
  var lastWasSpace = true; // началните интервали отпадат, както при trim
  final hrefRe = RegExp(r'href="([^"]*)"', caseSensitive: false);

  void push(String t) {
    if (t.isEmpty) return;
    runs.add(HtmlRun(t,
        bold: bold > 0,
        italic: italic > 0,
        sup: sup > 0,
        href: hrefs.isEmpty ? null : hrefs.last));
  }

  for (final m in RegExp(r'<[^>]*>|[^<]+').allMatches(html)) {
    final piece = m.group(0)!;
    if (piece.startsWith('<')) {
      final t = piece.toLowerCase();
      if (t.startsWith('<strong') || t.startsWith('<b>')) {
        bold++;
      } else if (t.startsWith('</strong') || t.startsWith('</b>')) {
        if (bold > 0) bold--;
      } else if (t.startsWith('<em') || t.startsWith('<i>')) {
        italic++;
      } else if (t.startsWith('</em') || t.startsWith('</i>')) {
        if (italic > 0) italic--;
      } else if (t.startsWith('<a')) {
        hrefs.add(hrefRe.firstMatch(piece)?.group(1) ?? '');
      } else if (t.startsWith('</a')) {
        if (hrefs.isNotEmpty) hrefs.removeLast();
      } else if (t.startsWith('<sup')) {
        sup++;
      } else if (t.startsWith('</sup')) {
        if (sup > 0) sup--;
      } else if (t.startsWith('<br')) {
        push('\n');
        lastWasSpace = true;
      }
      continue;
    }
    var text = decodeEntities(piece).replaceAll(RegExp(r'\s+'), ' ');
    if (lastWasSpace) text = text.trimLeft();
    if (text.isEmpty) continue;
    lastWasSpace = text.endsWith(' ');
    push(text);
  }
  return runs;
}

/// Началата на всички съвпадения в чист текст.
///
/// Ползва се отвън (reader_screen), за да разбере на кой ЗНАК стои k-тото
/// съвпадение в абзаца с буквицата — и оттам, чрез
/// [DropCapParagraphState.dyForChar], на кой пиксел.
List<int> matchStartsOf(String text, String foldedQuery) =>
    [for (final r in _matchRanges(text, foldedQuery)) r.$1];

/// Началото и краят на всяко съвпадение в чистия текст.
List<(int, int)> _matchRanges(String text, String foldedQuery) {
  if (foldedQuery.isEmpty) return const [];
  final folded = fold(text);
  final out = <(int, int)>[];
  var from = 0;
  while (true) {
    final at = folded.text.indexOf(foldedQuery, from);
    if (at < 0) break;
    final endIdx = at + foldedQuery.length - 1;
    out.add((folded.origIndex[at], folded.origIndex[endIdx] + 1));
    from = endIdx + 1;
  }
  return out;
}

/// Геометрията на ЕДИН от „следващите" абзаци (не първия — той си остава
/// отделно в [_CapGeometry], защото винаги носи буквицата). Виж
/// [_CapGeometry.rest] — списък от точно такива, по един на абзац от
/// [DropCapParagraph.restParagraphs].
///
/// Само ЕДИН елемент от списъка може да е „прерязан" (cut < plainLength,
/// lines > 0) — той е границата: всички ПРЕДИ него се побират ЦЕЛИ до
/// буквицата, всички СЛЕД него изобщо не стигат дотам (lines == 0,
/// cut == 0) и отиват направо в опашката. Естествена последица от това, че
/// редовете се раздават ПОРЕДНО, отгоре надолу — виж цикъла в build().
class _RestParaGeom {
  final List<InlineSpan> narrowSpans; // целият абзац, за мерене
  final List<InlineSpan> tailSpans;   // от cut нататък, за мерене
  final int cut;      // 0 = изобщо не е влизал; == plainLength = влязъл цял
  final int plainLength;
  final int lines;    // колко реда до буквицата (0 = никакви)
  // Кумулативни отмествания — ГОТОВИ ПРЕДВАРИТЕЛНО, за да не пресмята
  // dyForCharInRest/charAtDy наново геометрията на предишните абзаци всеки
  // път (би било O(n²) при много абзаци, а и по-лесно се разминава).
  final double besideTop; // Y ВЪТРЕ в „тясната" колона, откъдето тръгва
  final double tailTop;   // Y ВЪТРЕ в опашката, откъдето тръгва (ПРЕДИ padTop)

  const _RestParaGeom({
    required this.narrowSpans,
    required this.tailSpans,
    required this.cut,
    required this.plainLength,
    required this.lines,
    required this.besideTop,
    required this.tailTop,
  });
}

/// Каквото трябва да се знае, за да се каже на кой пиксел стои даден знак от
/// абзаца с буквицата. Пълни се при рисуването (виж [DropCapParagraphState]).
class _CapGeometry {
  final List<InlineSpan> narrowSpans; // първият абзац, целият
  final List<InlineSpan> tailSpans;   // същият, от отреза нататък
  final int cut;                      // докъде стига обтичащата зона
  final double narrowWidth;
  final double fullWidth;
  final double rowHeight;             // височината на реда с буквицата
  final TextStyle base;
  final TextScaler scaler;

  /// Следващите абзаци (0..N) — виж [_RestParaGeom]. Влизат вдясно от
  /// буквицата, докато има място; остатъкът пада в опашката.
  final List<_RestParaGeom> rest;
  final double firstNarrowHeight; // височината на първия абзац в колоната
  final double tail1Height;       // опашката на първия абзац, ако има
  final double paraGap;
  final double lineHeightPx;

  /// Дължината (в знаци) на самия ПЪРВИ абзац — границата, от която нататък
  /// [DropCapParagraphState.dyForChar]/[DropCapParagraphState.charAtDy]
  /// адресират [rest] вместо него. Виж бележката там защо е нужна отделно
  /// поле, а не просто `cut` (той спира на отреза, не на края на абзаца).
  final int firstLength;

  const _CapGeometry({
    required this.narrowSpans,
    required this.tailSpans,
    required this.cut,
    required this.narrowWidth,
    required this.fullWidth,
    required this.rowHeight,
    required this.base,
    required this.scaler,
    required this.rest,
    required this.firstNarrowHeight,
    required this.tail1Height,
    required this.paraGap,
    required this.lineHeightPx,
    required this.firstLength,
  });
}

/// Абзац с водеща буква и ИСТИНСКО обтичане.
///
/// Механика: буквата заема N реда височина. С TextPainter измерваме колко
/// от чистия текст на първия абзац се побира в N реда при СТЕСНЕНАТА
/// ширина (екран минус буквата). Тази част се рендва вдясно от буквата;
/// всичко останало — на пълна ширина отдолу. Линковете в обтичащата зона
/// се пазят, защото тя се рендва пак като Html.
/// Първият абзац на житието — с орнаментирана водеща буква, около която
/// текстът обтича.
///
/// Текстът тук се изписва с Text.rich, а НЕ с flutter_html като останалите
/// региони. Причината е измерването: трябва да знаем къде свършва петият
/// ред, за да продължим остатъка под буквицата, а flutter_html не казва
/// къде чупи редовете си. Мерихме с TextPainter и рисувахме с него — двата
/// подреждаха малко различно и на границата между двете кутии изчезваше по
/// дума-две. Сега мерещият и рисуващият са един и същ двигател, тъй че
/// разминаване няма по построение, а maxLines сам отрязва.
///
/// Таговете, които се срещат в началните абзаци, са проверени по цялата
/// база и са само четири (виж htmlRuns).
class DropCapParagraph extends StatefulWidget {
  final String dropCap;
  final double dropCapSize;
  /// Множител по мащаба (малка/средна/голяма) върху ляво/дясната корекция
  /// на отделни букви — виж [dropCapOffsetX]. 1.0 = без допълнителна
  /// корекция (сегашното поведение).
  final double offsetScale;
  final double lineHeight;   // в ПИКСЕЛИ — за сметките (колко реда до буквата)
  final double lineFactor;   // коефициентът за TextStyle.height (напр. 1.25)
  final String firstParagraph; // HTML съдържанието на първия <p> (без буквата)
  /// Отваряща кавичка ПРЕДИ буквицата ("„Думи…" → буквицата е "Д", тук е
  /// „). Празен низ — обичайният случай, без кавичка. Виси вляво от
  /// буквицата (виж build()), не заема отделен ред в потока на текста.
  final String leadingQuote;
  /// Следващите абзаци, по ред. Влизат вдясно от буквицата, докато остава
  /// място (при по-голяма буквица — по няколко наведнъж); щом свърши
  /// мястото — от там нататък всичко се изписва под нея на пълна ширина,
  /// както би стояло и без това. Виж [_RestParaGeom].
  final List<String> restParagraphs;
  final double fontSize;
  final Color capColor;
  final Color inkColor;
  final Color linkColor;
  // Търсене: празен searchQuery = няма активно търсене.
  final String searchQuery;
  final int firstGlobalMatchIndex;
  final int currentGlobalMatch;
  final Color hitColor;

  /// ⚠ Цитатът, заради който четивото е отворено — буквицата получава СИН
  /// фон, ако той започва от нея. Без това цитат от началото на житие
  /// изглежда като започващ от втората буква: инициалът се рисува отделно
  /// и не минава през маркирането на HTML-а.
  /// (Докладвано от потребителя, 03.09.2026: „буквицата също трябва да може
  /// да се маркира!")
  final String quoteText;
  final Color quoteColor;
  final Color hitCurrentColor;
  final void Function(String?) onLinkTap;

  const DropCapParagraph({
    super.key,
    required this.dropCap,
    required this.dropCapSize,
    required this.lineHeight,
    required this.lineFactor,
    required this.firstParagraph,
    this.restParagraphs = const [],
    required this.fontSize,
    required this.capColor,
    required this.inkColor,
    required this.linkColor,
    required this.onLinkTap,
    this.offsetScale = 1.0,
    this.leadingQuote = '',
    this.searchQuery = '',
    this.firstGlobalMatchIndex = 0,
    this.currentGlobalMatch = -1,
    this.hitColor = const Color(0x00000000),
    this.quoteText = '',
    this.quoteColor = const Color(0x00000000),
    this.hitCurrentColor = const Color(0x00000000),
  });

  @override
  State<DropCapParagraph> createState() => DropCapParagraphState();
}

class DropCapParagraphState extends State<DropCapParagraph> {
  // Разпознавателите на тап живеят колкото кадъра, в който са създадени.
  // Старите се освобождават СЛЕД кадъра — докато той се рисува, все още са
  // закачени за spans-овете.
  List<TapGestureRecognizer> _recognizers = [];

  // ── Геометрията от последното рисуване ────────────────────────────────
  //
  // Запомня се, за да може търсенето да пита „на кой пиксел е този знак".
  // Нарочно се взима ОТТУК, а не се пресмята наново отвън: кутията вече е
  // мерила всичко това, за да реши къде да пречупи обтичащата зона, и
  // всяко второ пресмятане би се разминало с нея при първата промяна на
  // константите (ширина на буквицата, луфт, ред за букви с опашка).
  _CapGeometry? _geometry;

  /// Отместването (в пиксели, спрямо върха на този абзац) на реда, в който
  /// стои знак [charIndex] от ВИРТУАЛНАТА обща номерация на региона: от 0
  /// до дължината на ПЪРВИЯ абзац е самият той; нататък — поред всеки от
  /// [_CapGeometry.rest] (виж [charAtDy], обратната посока — там е и защо
  /// номерацията е точно такава).
  ///
  /// null, ако още не е рисувано (значи няма геометрия) — тогава
  /// извикващият да ползва началото на абзаца.
  double? dyForChar(int charIndex) {
    final g = _geometry;
    if (g == null) return null;
    if (charIndex < g.firstLength) {
      // Обтичащата зона: знакът е в тясната колона до буквицата.
      if (charIndex < g.cut) {
        final tp = TextPainter(
          text: TextSpan(style: g.base, children: g.narrowSpans),
          textDirection: TextDirection.ltr,
          textScaler: g.scaler,
          textAlign: TextAlign.justify,
        )..layout(maxWidth: g.narrowWidth);
        final dy = tp
            .getOffsetForCaret(TextPosition(offset: charIndex), Rect.zero)
            .dy;
        tp.dispose();
        return dy;
      }
      // Опашката под буквицата — цяла ширина, започва наново от отреза.
      final tp = TextPainter(
        text: TextSpan(style: g.base, children: g.tailSpans),
        textDirection: TextDirection.ltr,
        textScaler: g.scaler,
        textAlign: TextAlign.justify,
      )..layout(maxWidth: g.fullWidth);
      final dy = tp
          .getOffsetForCaret(TextPosition(offset: charIndex - g.cut), Rect.zero)
          .dy;
      tp.dispose();
      // 2 пиксела отстъп отгоре — виж Padding-а при опашката в build().
      return g.rowHeight + 2 + dy;
    }
    // Отвъд първия абзац — поред всеки следващ, докато не попаднем в
    // неговия обхват. Пресмятането Е СЪЩОТО, каквото вече ползва
    // търсенето (dyForCharInRest) — не се повтаря тук.
    var offset = g.firstLength;
    for (var i = 0; i < g.rest.length; i++) {
      final len = g.rest[i].plainLength;
      if (charIndex < offset + len) return dyForCharInRest(i, charIndex - offset);
      offset += len;
    }
    // Отвъд всичко видяно (напр. текстът е бил поправен междувременно) —
    // залепва се за края на последния абзац, не за началото на региона.
    if (g.rest.isNotEmpty) {
      final last = g.rest.length - 1;
      return dyForCharInRest(last, g.rest[last].plainLength);
    }
    return null;
  }

  /// Обратното на [dyForChar]: кой знак стои на пиксел [dy].
  ///
  /// Нужно е на отметките (записват ЗНАК, не пиксел и не ред — само той не
  /// се мени при смяна на размера на шрифта, виж text_line_locator.dart за
  /// същото при обикновените абзаци) И на улавянето на позицията при смяна
  /// на шрифта/завъртане/затваряне на търсенето (_topmostLine в двата
  /// четеца) — затова връща индекс във ВИРТУАЛНАТА обща номерация на целия
  /// регион (виж [dyForChar]), а не само в първия абзац.
  ///
  /// ⚠ До 24.08.2026 тук спираше при първия абзац: dy отвъд него (обтичащ
  /// или опашка) се „лепеше" към неговия край, БЕЗ значение колко далеч
  /// надолу в следващите абзаци всъщност е бил pixel-ът. За четиво с малко
  /// абзаци до буквицата грешката минаваше незабелязано; откакто
  /// [computeRegions] изтегля ПОДРЕД всички водещи `<p>` (не само първите
  /// два), региони с дълга поредица кратки абзаци в началото натрупваха
  /// огромно разминаване — точно бъгът с „+/- винаги ме връща на един и
  /// същ абзац, без значение откъде съм тръгнал", докладван от потребителя.
  int? charAtDy(double dy) {
    final g = _geometry;
    if (g == null) return null;
    int at(List<InlineSpan> spans, double width, double y) {
      final tp = TextPainter(
        text: TextSpan(style: g.base, children: spans),
        textDirection: TextDirection.ltr,
        textScaler: g.scaler,
        textAlign: TextAlign.justify,
      )..layout(maxWidth: width);
      final pos = tp
          .getPositionForOffset(Offset(0, y.clamp(0, tp.height)))
          .offset;
      tp.dispose();
      return pos;
    }

    int restOffset(int i) {
      var off = g.firstLength;
      for (var k = 0; k < i; k++) {
        off += g.rest[k].plainLength;
      }
      return off;
    }

    if (dy < g.rowHeight) {
      // Обтичащата (тясна) колона: първо самият първи абзац, после
      // следващите — едно под друго, в реда, в който реално застават до
      // буквицата (виж besideCursor в build()).
      final firstPos = at(g.narrowSpans, g.narrowWidth, dy);
      var best = firstPos > g.cut ? g.cut : firstPos;
      final besideIdxs = [
        for (var i = 0; i < g.rest.length; i++)
          if (g.rest[i].lines > 0) i,
      ];
      var nextStart =
          besideIdxs.isEmpty ? double.infinity : g.rest[besideIdxs.first].besideTop;
      if (dy < nextStart) return best;
      for (var k = 0; k < besideIdxs.length; k++) {
        final i = besideIdxs[k];
        final rp = g.rest[i];
        final local = at(rp.narrowSpans, g.narrowWidth, dy - rp.besideTop);
        best = restOffset(i) + (local > rp.cut ? rp.cut : local);
        nextStart = k + 1 < besideIdxs.length
            ? g.rest[besideIdxs[k + 1]].besideTop
            : double.infinity;
        if (dy < nextStart) return best;
      }
      return best;
    }
    // Опашката под буквицата: първо тази на първия абзац (ако има; 2
    // пиксела отстъп отгоре, виж build), после следващите — по реда, в
    // който бяха сглобени там.
    final tailIdxs = [
      for (var i = 0; i < g.rest.length; i++)
        if (!(g.rest[i].tailTop <= 0 && g.rest[i].cut >= g.rest[i].plainLength))
          i,
    ];
    if (g.cut < g.firstLength) {
      final best = g.cut + at(g.tailSpans, g.fullWidth, dy - g.rowHeight - 2);
      final nextStart =
          tailIdxs.isEmpty ? double.infinity : g.rest[tailIdxs.first].tailTop;
      if (dy < nextStart) return best;
    }
    var best = g.firstLength;
    for (var k = 0; k < tailIdxs.length; k++) {
      final i = tailIdxs[k];
      final rp = g.rest[i];
      final padTop = rp.lines > 0 ? 2.0 : g.paraGap / 2;
      final local = at(rp.tailSpans, g.fullWidth, dy - rp.tailTop - padTop);
      final maxLocal = rp.plainLength - rp.cut;
      best = restOffset(i) + rp.cut + (local > maxLocal ? maxLocal : local);
      final nextStart =
          k + 1 < tailIdxs.length ? g.rest[tailIdxs[k + 1]].tailTop : double.infinity;
      if (dy < nextStart) return best;
    }
    return best;
  }

  /// Същото, но за знак от един от СЛЕДВАЩИТЕ абзаци (тези, които при
  /// достатъчно място влизат вдясно от буквицата — виж
  /// [DropCapParagraph.restParagraphs]). [paraIndex] е индексът в него
  /// (0 = първият следващ абзац). Без това съвпаденията точно на границата
  /// между два абзаца се целеха по началото на региона — оттам и
  /// „дупката" в чертичките там.
  double? dyForCharInRest(int paraIndex, int charIndex) {
    final g = _geometry;
    if (g == null || paraIndex < 0 || paraIndex >= g.rest.length) return null;
    final rp = g.rest[paraIndex];
    double caret(List<InlineSpan> spans, double width, int at) {
      final tp = TextPainter(
        text: TextSpan(style: g.base, children: spans),
        textDirection: TextDirection.ltr,
        textScaler: g.scaler,
        textAlign: TextAlign.justify,
      )..layout(maxWidth: width);
      final dy =
          tp.getOffsetForCaret(TextPosition(offset: at), Rect.zero).dy;
      tp.dispose();
      return dy;
    }

    // В тясната колона, вдясно от буквицата — под всичко, влязло преди него.
    if (rp.lines > 0 && charIndex < rp.cut) {
      return rp.besideTop + caret(rp.narrowSpans, g.narrowWidth, charIndex);
    }
    // Иначе — в опашката, след всичко, влязло преди него там.
    final padTop = rp.lines > 0 ? 2.0 : g.paraGap / 2;
    return rp.tailTop + padTop + caret(rp.tailSpans, g.fullWidth, charIndex - rp.cut);
  }

  @override
  void dispose() {
    for (final r in _recognizers) {
      r.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fresh = <TapGestureRecognizer>[];

    final widgetTree = LayoutBuilder(
      builder: (context, constraints) {
        // Приблизителна ширина, коригирана по група (тясна/средна/широка
        // буква) — виж dropCapWidthFactorFor и бележката при
        // kDropCapWidthFactor.
        final capWidth = widget.dropCapSize *
            0.40 *
            dropCapWidthFactorFor(widget.dropCap);
        const gap = 4.0;
        final narrowWidth = constraints.maxWidth - capWidth - gap;

        // Системната настройка за едър шрифт увеличава изписвания текст —
        // измерването трябва да я знае, иначе бърка броя редове.
        final scaler = MediaQuery.textScalerOf(context);

        // Букви с descender (опашка под базовата линия) заемат повече
        // височина от останалите — обтичащата зона им дава още един ред,
        // за да не застъпи глифът първия ред под буквицата.
        const descenderCaps = {'Ч', 'Д', 'Ц', 'Щ', 'У', 'Р'};
        final extraLine = descenderCaps.contains(widget.dropCap) ? 1 : 0;
        final capLines =
            (widget.dropCapSize / widget.lineHeight).ceil() + extraLine;

        final runs = htmlRuns(widget.firstParagraph);
        final plain = runs.map((r) => r.text).join();

        // ⚠ ТЪРСЕНЕТО БРОИ И БУКВИЦАТА, макар тя да се рисува отделно.
        //
        // Инициалът е отрязан от `firstParagraph` (виж splitDropCap) и се
        // изписва с отделен `Text` в `Stack` по-долу. Без него търсене на
        // дума, започваща с първата буква на четивото — „Свети Иоан" в
        // житие, което започва точно така — намираше НУЛА съвпадения тук.
        // (Докладвано от потребителя, 02.09.2026: „буквицата и в сърча не
        // излиза".)
        //
        // ⚠ Затова съвпаденията се търсят в ПЪЛНИЯ текст, а после се местят
        // назад за парчетата, които рисуват само остатъка. Диапазон, който
        // започва в буквицата, се отрязва до 0 — там нейният дял вече е
        // изписан от самия инициал.
        final capLen = widget.dropCap.length;
        final fullMatches =
            _matchRanges(widget.dropCap + plain, widget.searchQuery);
        final matches = <(int, int)>[
          for (final m in fullMatches)
            if (m.$2 > capLen) (m.$1 < capLen ? 0 : m.$1 - capLen, m.$2 - capLen),
        ];

        // Кое поред съвпадение (глобално) започва В БУКВИЦАТА — за да се
        // оцвети тя, и то като ТЕКУЩО, ако обхождането е стигнало до него.
        final capMatchLocal =
            fullMatches.indexWhere((m) => m.$1 < capLen && m.$2 > 0);

        // ⚠ Колко съвпадения са ИЗЦЯЛО в буквицата — те не влизат в `matches`
        // (няма какво да се маркира в остатъка), но СЕ БРОЯТ от четеца, тъй
        // че номерирането на следващите трябва да ги отчете. Без това
        // обхождането се разминава с едно и „3/8" осветява осмото.
        final capOnlyMatches =
            fullMatches.where((m) => m.$2 <= capLen).length;
        final capIsHit = capMatchLocal >= 0;
        final capIsCurrent = capIsHit &&
            widget.firstGlobalMatchIndex + capMatchLocal ==
                widget.currentGlobalMatch;

        // ⚠ Къде в ТЕКСТА пада цитатът — за фона. Търси се сгънато, защото
        // цитатът идва от друга формула на плоския текст (виж
        // wrapQuoteByText в quote_link.dart).

        // ⚠ Къде в ТЕКСТА пада цитатът — за синия фон.
        //
        // Този регион се рисува с `Text.rich`, а НЕ през flutter_html, тъй че
        // маркирането по HTML (`wrapQuoteByText`) изобщо не стига дотук. А
        // точно тук пада ПЪРВИЯТ абзац на четивото — най-често цитираният.
        // (Докладвано от потребителя, 03.09.2026.)
        // ⚠⚠ ДИАПАЗОНИТЕ НА ЦИТАТА СЕ СМЯТАТ ЗА ВСЕКИ АБЗАЦ ПООТДЕЛНО.
        //
        // Регионът рисува първия абзац И всеки изтеглен до буквицата
        // (`restParagraphs`), а всички минават през ЕДНА И СЪЩА `spansOf`.
        // Смятани веднъж — за първия абзац — числата се прилагаха и върху
        // изтеглените, но там те значат СЪВСЕМ ДРУГИ знаци: диапазон
        // (10,30) от първия абзац оцветяваше знаци 10–30 на всеки следващ.
        // Оттам „маркира от буквицата до Свети Константин И МАЛКО СЛЕД
        // ТОВА" — последното е точно чуждият диапазон, паднал в съседен
        // абзац. (Докладвано от потребителя, 03.09.2026.)
        //
        // И обратното: цитат, който живее в ИЗТЕГЛЕН абзац, не се търсеше
        // никъде — `plain` е само първият — тъй че не светваше нищо.
        // Вдига се САМО в клона, който е разпознал буквицата — виж долу.
        // ⚠ „Диапазонът започва на 0" НЕ Е достатъчен признак: цитат,
        // маркиран от втората буква нататък, също започва на 0 в `plain`
        // (буквицата е отрязана оттам), а тогава тя НЕ е част от него.
        var capIsInQuote = false;

        List<(int, int)> quoteRangesIn(String paraText, {bool first = false}) {
          if (widget.quoteText.isEmpty) return const [];
          final full = fold(widget.quoteText).text;
          if (full.isEmpty) return const [];
          final f = fold(paraText);

          // ⚠⚠ БУКВИЦАТА СЕ ПРИЗНАВА ЗА ЧАСТ ОТ ЦИТАТА САМО АКО ОСТАТЪКЪТ
          // ЗАПОЧВА ТОЧНО В НАЧАЛОТО НА ПЪРВИЯ АБЗАЦ.
          //
          // Дотук условието беше просто „сгънатият цитат започва със
          // сгънатата буквица" — тоест ЕДНА БУКВА. В четиво с буквица „С"
          // това е вярно за ВСЕКИ цитат, започващ със „С" („Скоро при
          // императора", „Свети Константин"), където и да стои той. Тогава
          // от цитата се отрязваше водеща буква, която не му принадлежи,
          // окълцаният остатък не се намираше, и на екрана светваше САМО
          // инициалът. (Точно двата случая, докладвани от потребителя на
          // 03.09.2026 — „нещо го обърква тотално".)
          //
          // Сега проверката се самопотвърждава: махаме буквата И искаме
          // остатъкът да седне на позиция 0. Не седне ли — буквицата не е
          // част от този цитат и се търси целият текст, както обикновено.
          if (first && widget.dropCap.isNotEmpty) {
            final cap = fold(widget.dropCap).text;
            if (cap.isNotEmpty && full.startsWith(cap)) {
              final rest = full.substring(cap.length);
              if (rest.isEmpty) return const [];
              if (f.text.startsWith(rest)) {
                capIsInQuote = true;
                return [(0, f.origIndex[rest.length - 1] + 1)];
              }
            }
          }

          final at = f.text.indexOf(full);
          if (at < 0) return const [];
          return [(f.origIndex[at], f.origIndex[at + full.length - 1] + 1)];
        }

        final quoteRanges = quoteRangesIn(plain, first: true);

        // Буквицата свети само когато остатъкът наистина е седнал в
        // началото — виж дългата бележка горе.
        final capInQuote = capIsInQuote;

        // Стилът е ПЪЛЕН нарочно: дебелина, наклон и разредка са изрично
        // зададени, а не оставени празни. Празно поле се попълва от
        // околния DefaultTextStyle при изписването, но не и при мерещия
        // TextPainter, който няма такъв — и двата подреждаха различно,
        // заради което между двете кутии се губеше по дума.
        final base = TextStyle(
          fontFamily: kBodyFamily,
          fontSize: widget.fontSize,
          height: widget.lineFactor,
          color: widget.inkColor,
          fontWeight: FontWeight.w400,
          fontStyle: FontStyle.normal,
          letterSpacing: 0,
          wordSpacing: 0,
        );

        // Парчетата от [from, to) — с оформлението си, с връзките си и с
        // маркировката от търсенето. Номерата на съвпаденията са ГЛОБАЛНИ,
        // затова двете кутии не се разминават в броенето.
        /// [forMeasure] — при мерене с TextPainter горните индекси се
        /// изписват като обикновен, но СМАЛЕН текст, вместо като WidgetSpan.
        ///
        /// Причината: TextPainter не може да оформи WidgetSpan, без да са му
        /// подадени размерите на запълнителите (setPlaceholderDimensions), а
        /// тук се мери само за да се реши докъде стига текстът до буквицата.
        /// Ширината е ЕДНАКВА в двата случая (повдигането е чисто вертикално
        /// отместване), тъй че резът пада на същото място.
        // ⚠ `qRanges` е ЗА ТОЗИ абзац. По подразбиране — на първия; всеки
        // изтеглен подава своите (виж quoteRangesIn). Оставено ли беше
        // общо, чуждите числа оцветяваха произволни знаци в съседните
        // абзаци — виж дългата бележка при quoteRangesIn.
        List<InlineSpan> spansOf(List<HtmlRun> src, String text,
            List<(int, int)> hits, int matchBase, int from, int to,
            {bool forMeasure = false, List<(int, int)>? qRanges}) {
          final ranges = qRanges ?? quoteRanges;
          final out = <InlineSpan>[];
          var pos = 0;
          for (final run in src) {
            final start = pos;
            final end = pos + run.text.length;
            pos = end;
            final lo = start < from ? from : start;
            final hi = end > to ? to : end;
            if (lo >= hi) continue;

            var style = base.copyWith(
              fontWeight: run.bold ? FontWeight.w600 : FontWeight.w400,
              fontStyle:
                  run.italic ? FontStyle.italic : FontStyle.normal,
              color: run.href != null ? widget.linkColor : widget.inkColor,
            );
            if (run.sup) {
              style = style.copyWith(
                  fontSize: (base.fontSize ?? widget.fontSize) * kSupScale);
            }
            TapGestureRecognizer? tap;
            if (run.href != null && run.href!.isNotEmpty) {
              tap = TapGestureRecognizer()
                ..onTap = () => widget.onLinkTap(run.href);
              fresh.add(tap);
            }

            // Горният индекс при РИСУВАНЕ е WidgetSpan с отместване нагоре
            // — същият похват, който ползва и flutter_html за <sup> (виж
            // VerticalAlignBuiltIn в пакета). Нарочно НЕ разчитаме на
            // таблицата „sups" на шрифта: сменим ли го утре с такъв без нея,
            // повдигането щеше да отпадне тихо.
            //
            // Не се насича по съвпаденията, но СЕ ОЦВЕТЯВА, ако попада в
            // намереното. Номерът на бележка наистина не е текст, който
            // човек търси нарочно, но търсачката го брои и обхожда — и
            // остане ли неоцветен, човекът стига дотам и не вижда нищо.
            if (run.sup && !forMeasure) {
              Color? hitBg;
              for (var i = 0; i < hits.length; i++) {
                final (ms, me) = hits[i];
                if (me <= lo || ms >= hi) continue;
                hitBg = matchBase + i == widget.currentGlobalMatch
                    ? widget.hitCurrentColor
                    : widget.hitColor;
                // Текущото има превес над обикновеното.
                if (matchBase + i == widget.currentGlobalMatch) break;
              }
              final label = Text(text.substring(lo, hi),
                  style: hitBg == null
                      ? style
                      : style.copyWith(backgroundColor: hitBg),
                  textScaler: TextScaler.noScaling);
              out.add(WidgetSpan(
                alignment: PlaceholderAlignment.baseline,
                baseline: TextBaseline.alphabetic,
                child: Transform.translate(
                  offset: Offset(0, -(base.fontSize ?? widget.fontSize) * 0.34),
                  // Тапът се закача с GestureDetector, а НЕ с
                  // TapGestureRecognizer: разпознавачът работи върху
                  // TextSpan, а тук съдържанието е widget. Без това номерът
                  // изглежда като връзка, но не се отваря.
                  //
                  // Зоната за докосване се разширява, защото повдигнатият
                  // номер е дребен — иначе иска прицелване.
                  child: run.href == null || run.href!.isEmpty
                      ? label
                      : GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => widget.onLinkTap(run.href),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 2, vertical: 4),
                            child: label,
                          ),
                        ),
                ),
              ));
              continue;
            }

            // ⚠ ФОНЪТ НА ЦИТАТА се слага на нивото на СТИЛА, преди
            // насичането по съвпадения.
            //
            // Причината е структурна: този регион се рисува с `Text.rich`, а
            // НЕ през flutter_html, тъй че маркирането по HTML
            // (`wrapQuoteByText`) изобщо не стига дотук. А точно тук пада
            // ПЪРВИЯТ абзац на четивото — най-често цитираният. Отвън
            // изглеждаше като „намира цитата, но не го маркира".
            // (Докладвано от потребителя, 03.09.2026.)
            //
            // ⚠ Търсенето има превес: жълтият фон се слага ПОДИР този и го
            // презаписва там, където двете се застъпват. „Намерено сега"
            // побеждава „това поиска да видиш".

            // ⚠ Фонът на ЦИТАТА се слага на нивото на стила; жълтото на
            // търсенето се налага ПОДИР него и го презаписва, където двете се
            // застъпват — „намерено сега" побеждава „това поиска да видиш".
            Color? quoteBgAt(int a, int b) {
              for (final (qs, qe) in ranges) {
                if (a < qe && b > qs) return widget.quoteColor;
              }
              return null;
            }

            // Парчето се насича допълнително по границите на съвпаденията.
            var cursor = lo;
            for (var i = 0; i < hits.length; i++) {
              final (ms, me) = hits[i];
              if (me <= cursor || ms >= hi) continue;
              final s0 = ms < cursor ? cursor : ms;
              final e0 = me > hi ? hi : me;
              if (s0 > cursor) {
                out.add(TextSpan(
                    text: text.substring(cursor, s0),
                    style: style.copyWith(
                        backgroundColor: quoteBgAt(cursor, s0)),
                    recognizer: tap));
              }
              final isCurrent = matchBase + i == widget.currentGlobalMatch;
              out.add(TextSpan(
                text: text.substring(s0, e0),
                style: style.copyWith(
                    backgroundColor:
                        isCurrent ? widget.hitCurrentColor : widget.hitColor),
                recognizer: tap,
              ));
              cursor = e0;
            }
            if (cursor < hi) {
              out.add(TextSpan(
                  text: text.substring(cursor, hi),
                  style:
                      style.copyWith(backgroundColor: quoteBgAt(cursor, hi)),
                  recognizer: tap));
            }
          }
          return out;
        }

        // Номерата на съвпаденията в ОСТАТЪКА започват след онези, които са
        // изцяло в буквицата — виж [capOnlyMatches].
        final firstInRest = widget.firstGlobalMatchIndex + capOnlyMatches;
        final base2 = firstInRest + matches.length;
        final measure1 = spansOf(
            runs, plain, matches, firstInRest, 0, plain.length,
            forMeasure: true);
        final spans1 =
            spansOf(runs, plain, matches, firstInRest, 0, plain.length);

        /// Докъде стига текстът, ако му дадем най-много [limit] реда, и
        /// колко реда всъщност заема. Мярката е със СЪЩИТЕ парчета, ширина
        /// и maxLines, с които после рисува Text.rich — затова отрязването
        /// пада точно там, докъдето стига видимото.
        ({int cut, int lines}) fit(List<InlineSpan> spans, int limit,
            int textLength) {
          final tp = TextPainter(
            text: TextSpan(style: base, children: spans),
            textDirection: TextDirection.ltr,
            textScaler: scaler,
            textAlign: TextAlign.justify,
            maxLines: limit,
          )..layout(maxWidth: narrowWidth);
          final metrics = tp.computeLineMetrics();
          if (!tp.didExceedMaxLines) {
            return (cut: textLength, lines: metrics.length);
          }
          final last =
              metrics[(limit < metrics.length ? limit : metrics.length) - 1];
          return (
            cut: tp
                .getPositionForOffset(Offset(narrowWidth, last.baseline))
                .offset,
            lines: limit,
          );
        }

        final f1 = fit(measure1, capLines, plain.length);

        // Отстоянието между два абзаца — същото, каквото дава flutter_html
        // на останалите (8 отдолу + 8 отгоре).
        const paraGap = 16.0;
        final lineHeightPx = scaler.scale(widget.fontSize) * widget.lineFactor;
        final firstNarrowHeight = f1.lines * lineHeightPx;

        // Следващите абзаци — влизат вдясно от буквицата, докато остава
        // място (при по-голяма буквица: по няколко наведнъж). Раздават се
        // РЕДОВЕ ПОРЕДНО, отгоре надолу: щом някой не се побере ЦЯЛ,
        // той е границата — прерязва се, а всичко СЛЕД него пада направо
        // в опашката (виж бележката при _RestParaGeom). Съвпаденията им
        // продължават номерацията от първия абзац, за да не се разминат
        // броячите на търсенето.
        final restGeoms = <_RestParaGeom>[];
        final restBesideSpans = <List<InlineSpan>>[]; // само за draw, lines>0
        var remainingLines = capLines - f1.lines;
        var besideCursor = firstNarrowHeight;
        var tailCursor = 0.0; // попълва се СЛЕД като знаем tail1Height
        var stillFitting = true;
        var matchBase = base2;
        final restTailWidgets = <Widget>[]; // сглобяват се веднага, по ред

        for (final p in widget.restParagraphs) {
          final runsI = htmlRuns(p);
          final plainI = runsI.map((r) => r.text).join();
          final matchesI = _matchRanges(plainI, widget.searchQuery);
          // ⚠ СВОИТЕ диапазони — не тези на първия абзац.
          final qRangesI = quoteRangesIn(plainI);
          final matchBaseI = matchBase;
          matchBase += matchesI.length;

          var cut = 0;
          var lines = 0;
          if (stillFitting) {
            final gapLines = (paraGap / lineHeightPx).ceil();
            final freeLines = remainingLines - gapLines;
            if (freeLines >= 1) {
              final measureI = spansOf(runsI, plainI, matchesI, matchBaseI, 0,
                  plainI.length, forMeasure: true, qRanges: qRangesI);
              final fI = fit(measureI, freeLines, plainI.length);
              cut = fI.cut;
              lines = fI.lines;
              remainingLines -= gapLines + lines;
              if (cut < plainI.length) stillFitting = false; // прерязан тук
            } else {
              stillFitting = false;
            }
          }

          final besideTop = besideCursor + paraGap;
          if (lines > 0) {
            restBesideSpans.add(spansOf(
                runsI, plainI, matchesI, matchBaseI, 0, cut,
                qRanges: qRangesI));
            besideCursor = besideTop + lines * lineHeightPx;
          } else {
            restBesideSpans.add(const <InlineSpan>[]);
          }

          final tailMeasure = cut < plainI.length
              ? spansOf(runsI, plainI, matchesI, matchBaseI, cut,
                  plainI.length, forMeasure: true, qRanges: qRangesI)
              : const <InlineSpan>[];
          var tailTop = 0.0;
          if (cut < plainI.length) {
            // ПЪРВИЯТ ред от опашката тръгва СЛЕД тази на първия абзац
            // (tailCursor е инициализиран точно за това по-долу).
            tailTop = tailCursor;
            final padTop = lines > 0 ? 2.0 : paraGap / 2;
            final tp = TextPainter(
              text: TextSpan(style: base, children: tailMeasure),
              textDirection: TextDirection.ltr,
              textScaler: scaler,
              textAlign: TextAlign.justify,
            )..layout(maxWidth: constraints.maxWidth);
            tailCursor = tailTop + padTop + tp.height;
            tp.dispose();
            restTailWidgets.add(Padding(
              padding: EdgeInsets.only(top: padTop),
              child: Text.rich(
                TextSpan(
                    style: base,
                    children: spansOf(runsI, plainI, matchesI, matchBaseI,
                        cut, plainI.length,
                        qRanges: qRangesI)),
                textAlign: TextAlign.justify,
              ),
            ));
          }

          restGeoms.add(_RestParaGeom(
            narrowSpans: spansOf(runsI, plainI, matchesI, matchBaseI, 0,
                plainI.length, forMeasure: true, qRanges: qRangesI),
            tailSpans: tailMeasure,
            cut: cut,
            plainLength: plainI.length,
            lines: lines,
            besideTop: besideTop,
            tailTop: tailTop,
          ));
        }

        final narrowColumnHeight = besideCursor;
        final tailSpans1 = spansOf(runs, plain, matches,
            widget.firstGlobalMatchIndex, f1.cut, plain.length,
            forMeasure: true);
        // Височината на опашката на първия абзац — нужна, за да знаем къде
        // започва опашката на следващите. Мери се само когато има такава.
        var tail1Height = 0.0;
        if (f1.cut < plain.length) {
          final tp = TextPainter(
            text: TextSpan(style: base, children: tailSpans1),
            textDirection: TextDirection.ltr,
            textScaler: scaler,
            textAlign: TextAlign.justify,
          )..layout(maxWidth: constraints.maxWidth);
          tail1Height = tp.height + 2; // + Padding(top: 2)
          tp.dispose();
        }
        final rowHeight = widget.dropCapSize > narrowColumnHeight
            ? widget.dropCapSize
            : narrowColumnHeight;
        // tailCursor по-горе тръгна от 0 — сега се измества с rowHeight и
        // опашката на първия абзац, точно както rowHeight+tail1Height
        // правеше за „втория" абзац в старата (двойна) версия.
        for (var i = 0; i < restGeoms.length; i++) {
          final rp = restGeoms[i];
          if (rp.tailTop == 0.0 && rp.cut >= rp.plainLength) continue; // без опашка
          restGeoms[i] = _RestParaGeom(
            narrowSpans: rp.narrowSpans,
            tailSpans: rp.tailSpans,
            cut: rp.cut,
            plainLength: rp.plainLength,
            lines: rp.lines,
            besideTop: rp.besideTop,
            tailTop: rp.tailTop + rowHeight + tail1Height,
          );
        }

        _geometry = _CapGeometry(
          narrowSpans: measure1,
          tailSpans: tailSpans1,
          cut: f1.cut,
          narrowWidth: narrowWidth,
          fullWidth: constraints.maxWidth,
          rowHeight: rowHeight,
          base: base,
          scaler: scaler,
          rest: restGeoms,
          firstNarrowHeight: firstNarrowHeight,
          tail1Height: tail1Height,
          paraGap: paraGap,
          lineHeightPx: lineHeightPx,
          firstLength: plain.length,
        );

        // Какво остава ПОД буквицата: опашката на първия абзац (ако е
        // прерязан), после опашките на следващите — по РЕДА, в който бяха
        // сглобени в цикъла по-горе (вече Widget-и, готови).
        final tail = <Widget>[];
        if (f1.cut < plain.length) {
          tail.add(Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text.rich(
              TextSpan(
                  style: base,
                  children: spansOf(runs, plain, matches,
                      widget.firstGlobalMatchIndex, f1.cut, plain.length)),
              textAlign: TextAlign.justify,
            ),
          ));
        }
        tail.addAll(restTailWidgets);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: capWidth,
                  // Stack, не просто Transform: кавичката виси ОТВЪН тази
                  // кутия (отрицателен `left`), а Stack по подразбиране
                  // изрязва децата си по границите си — clipBehavior.none
                  // го спира.
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Transform.translate(
                        offset: Offset(
                            dropCapOffsetX(widget.dropCap, widget.dropCapSize,
                                scaleMultiplier: widget.offsetScale),
                            2),
                        child: Text(
                          widget.dropCap,
                          style: TextStyle(
                            fontFamily: kDropCapFamily,
                            fontSize: widget.dropCapSize,
                            height: 1.0,
                            color: widget.capColor,
                            // ⚠ Намереното свети И В БУКВИЦАТА — със същия
                            // ФОН като останалия текст, а не с промяна на
                            // цвета ѝ: `hitColor` е фоново жълто и сложено
                            // като цвят на глифа би направило инициала
                            // нечетим върху кремавата страница.
                            //
                            // ⚠ Фонът обхваща кутията на глифа, а тя е висока
                            // няколко реда — петното е едро. Прието: то трае
                            // само докато върви търсенето и казва
                            // недвусмислено, че намереното е тук.
                            // ⚠ Търсенето има превес пред цитата: жълтото
                            // казва „намерено СЕГА", а синьото — „това
                            // поиска да видиш". Активното действие печели.
                            backgroundColor: capIsHit
                                ? (capIsCurrent
                                    ? widget.hitCurrentColor
                                    : widget.hitColor)
                                : (capInQuote ? widget.quoteColor : null),
                          ),
                        ),
                      ),
                      if (widget.leadingQuote.isNotEmpty)
                        Positioned(
                          // ⚠ Тези три числа са "на око" — буквицата има
                          // голямо празно поле над истинския си глиф
                          // (затова визуално стърчи над реда въпреки
                          // Offset(0,2) по-горе), а кавичката трябва да
                          // излезе на височината на ПЪРВИЯ ред от
                          // текста, не на върха на буквицата. Провери
                          // визуално и подкарай тези константи, ако не
                          // паснат за конкретния шрифт/размер.
                          top: widget.fontSize * -0.5,
                          left: -widget.fontSize * 0.25, //0.95,
                          child: Text(
                            widget.leadingQuote,
                            style: TextStyle(
                              fontSize: widget.fontSize * 1.35,
                              height: 1.0,
                              // Пунктуация от основния текст, не част от
                              // орнамента на буквицата — затова inkColor,
                              // не capColor.
                              color: widget.capColor, //color: widget.inkColor,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: gap),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // maxLines реже точно там, където мярката е казала —
                      // и когато текстът продължава отвъд, последният видим
                      // ред не е "последен за абзаца" и се разпъва.
                      Text.rich(
                        TextSpan(style: base, children: spans1),
                        maxLines: f1.lines,
                        textAlign: TextAlign.justify,
                      ),
                      for (var i = 0; i < restGeoms.length; i++)
                        if (restGeoms[i].lines > 0) ...[
                          const SizedBox(height: paraGap),
                          Text.rich(
                            TextSpan(
                                style: base, children: restBesideSpans[i]),
                            maxLines: restGeoms[i].lines,
                            textAlign: TextAlign.justify,
                          ),
                        ],
                    ],
                  ),
                ),
              ],
            ),
            ...tail,
          ],
        );
      },
    );

    final old = _recognizers;
    _recognizers = fresh;
    if (old.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        for (final r in old) {
          r.dispose();
        }
      });
    }
    return widgetTree;
  }
}

/// Отделя: (HTML преди абзаца с буквицата; евентуална отваряща кавичка ПРЕДИ
/// буквата; самата буква; текстът на този абзац без кавичката и буквата;
/// останалият HTML).
///
/// Обхожда абзаците, докато намери такъв, който започва с истинска буква —
/// евентуално предшествана от отваряща кавичка от какъвто и да е вид ( „ “
/// ” « ‹ ‘ ’ и правите " ' ). Преди кавичка от този вид просто ИЗХВЪРЛЯШЕ
/// целия абзац (буквицата кацаше на следващия, съвсем различен абзац —
/// точно оплакването, което доведе до тази поправка). Сега кавичката не
/// отменя буквицата: тя пада на буквата ВЕДНАГА след кавичката, а самата
/// кавичка се връща отделно (3-тия резултат по-долу), за да увисне вляво
/// от буквицата — виж рисуването ѝ в DropCapParagraph.build().
(String, String, String, String, String) splitDropCap(String html) {
  // Тези наистина нямат какво да търсят до буквица — редакторски бележки в
  // скоби, звездички, наклонена черта за разделител на сцена.
  const skipChars = {'(', '*', '/', '['};
  // Отварящи кавички от всякакъв вид — третират се по-специално, виж горе.
  const openQuotes = {
    '„', '\u201c', '\u201d', '«', '\u2039', '\u2018', '\u2019', '"', "'",
  };
  final italicStart = RegExp(r'^\s*<(?:em|i)\b[^>]*>', caseSensitive: false);

  int scanned = 0;
  int cursor = 0; // докъдето е "преписан" html в before
  final before = StringBuffer();

  for (final m in RegExp(r'<p>(.*?)</p>', dotAll: true).allMatches(html)) {
    if (++scanned > 3) break; // буквица само в началото, не насред текста
    final inner = m.group(1)!;

    // Пропускаме абзаци, започващи с курсивен таг, но ги центрираме.
    if (italicStart.hasMatch(inner)) {
      before.write(html.substring(cursor, m.start));
      before.write('<p class="italic-center">$inner</p>');
      cursor = m.end;
      continue;
    }

    // Първите ДВА значими символа, прескачайки HTML тагове и интервали —
    // вторият е нужен само за да проверим какво стои зад евентуална
    // кавичка на позиция първа.
    final cm = RegExp(r'^(?:\s|<[^>]+>)*(\S)(?:\s|<[^>]+>)*(\S)?')
        .firstMatch(inner);
    if (cm == null) continue;
    final ch = cm.group(1)!;

    if (skipChars.contains(ch)) continue;

    var quote = '';
    var capChar = ch;
    // ⚠ cm.end е краят на ЦЕЛИЯ регекс, включително втория, незадължителен
    // символ — регексът е лаком и го поглъща, щом го намери, а той стои
    // почти винаги. RegExpMatch няма end(group) (само group(n) за
    // СЪДЪРЖАНИЕТО, не за позицията), тъй че краят само на първия знак се
    // мери с отделен, по-къс регекс — същият префикс, отрязан преди втория
    // \S. cm.end тук беше бъгът, докладван на 21.08.2026: всички четива БЕЗ
    // кавичка тръгваха от ТРЕТИЯ знак вместо от втория — правилото за
    // кавичката (клонът по-долу, където cm.end Е верен, защото трябва да
    // среже и кавичката, и буквата) се бе качило мълчаливо и върху
    // обичайния случай.
    var matchEnd = RegExp(r'^(?:\s|<[^>]+>)*\S').firstMatch(inner)!.end;

    if (openQuotes.contains(ch)) {
      final second = cm.group(2);
      if (second == null ||
          !RegExp(r'[А-Яа-яA-Za-zЀ-ӿ]').hasMatch(second)) {
        // Кавичка, последвана от нещо друго освен буква (напр. тире или
        // край на абзаца) — старото поведение: пропускаме абзаца.
        continue;
      }
      quote = ch;
      capChar = second;
      matchEnd = cm.end; // сега режем кавичката И буквата заедно
    } else if (!RegExp(r'[А-Яа-яA-Za-zЀ-ӿ]').hasMatch(ch)) {
      continue; // не е буква (цифра, тире и пр.)
    }

    before.write(html.substring(cursor, m.start));
    return (
      before.toString(),
      quote,
      capChar,
      // Запазваме таговете преди буквата (напр. отварящ <strong>), за да
      // не се загуби форматирането на останалия текст.
      inner.substring(0, cm.start) + inner.substring(matchEnd),
      html.substring(m.end),
    );
  }
  // Няма подходящ абзац за буквица — връщаме html, но със запазени
  // центрирания за курсивните абзаци, засечени дотук.
  return (before.toString() + html.substring(cursor), '', '', '', '');
}
