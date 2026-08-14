// drop_cap.dart
//
// Абзац с водеща буква (буквица) и ИСТИНСКО обтичане — знакът на
// приложението при четене.
//
// Изнесено от reader_screen.dart, за да го ползва и четецът на книги от
// „Читанка": там буквицата се явява в началото на всяка глава/житие.
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

  // Вторият абзац — влиза вдясно от буквицата, когато първият е къс.
  final List<InlineSpan> narrowSpans2;
  final List<InlineSpan> tailSpans2;
  final int cut2;      // докъде от него е в тясната колона
  final int lines2;    // колко негови реда са там (0 = не е влизал)
  final int startsAt2; // откъде започва опашката му
  final double firstNarrowHeight; // височината на първия абзац в колоната
  final double tail1Height;       // опашката на първия абзац, ако има
  final double paraGap;

  const _CapGeometry({
    required this.narrowSpans,
    required this.tailSpans,
    required this.cut,
    required this.narrowWidth,
    required this.fullWidth,
    required this.rowHeight,
    required this.base,
    required this.scaler,
    required this.narrowSpans2,
    required this.tailSpans2,
    required this.cut2,
    required this.lines2,
    required this.startsAt2,
    required this.firstNarrowHeight,
    required this.tail1Height,
    required this.paraGap,
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
  final double lineHeight;   // в ПИКСЕЛИ — за сметките (колко реда до буквата)
  final double lineFactor;   // коефициентът за TextStyle.height (напр. 1.25)
  final String firstParagraph; // HTML съдържанието на първия <p> (без буквата)
  /// Следващият абзац. Влиза вдясно от буквицата, ако първият не запълва
  /// петте реда; иначе се изписва под нея, както би стоял и без това.
  final String secondParagraph;
  final double fontSize;
  final Color capColor;
  final Color inkColor;
  final Color linkColor;
  // Търсене: празен searchQuery = няма активно търсене.
  final String searchQuery;
  final int firstGlobalMatchIndex;
  final int currentGlobalMatch;
  final Color hitColor;
  final Color hitCurrentColor;
  final void Function(String?) onLinkTap;

  const DropCapParagraph({
    super.key,
    required this.dropCap,
    required this.dropCapSize,
    required this.lineHeight,
    required this.lineFactor,
    required this.firstParagraph,
    required this.secondParagraph,
    required this.fontSize,
    required this.capColor,
    required this.inkColor,
    required this.linkColor,
    required this.onLinkTap,
    this.searchQuery = '',
    this.firstGlobalMatchIndex = 0,
    this.currentGlobalMatch = -1,
    this.hitColor = const Color(0x00000000),
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
  /// стои знак [charIndex] от ПЪРВИЯ абзац.
  ///
  /// null, ако още не е рисувано (значи няма геометрия) — тогава
  /// извикващият да ползва началото на абзаца.
  double? dyForChar(int charIndex) {
    final g = _geometry;
    if (g == null) return null;
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

  /// Обратното на [dyForChar]: кой знак стои на пиксел [dy].
  ///
  /// Нужно е на отметките — те записват ЗНАК, не пиксел и не ред, защото
  /// само знакът не се мени при смяна на размера на шрифта. Виж
  /// text_line_locator.dart за същото при обикновените абзаци.
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

    // Обтичащата зона до инициала.
    if (dy < g.rowHeight) {
      final pos = at(g.narrowSpans, g.narrowWidth, dy);
      // Отвъд отреза текстът вече е в опашката — там горе го няма.
      return pos > g.cut ? g.cut : pos;
    }
    // Опашката под буквицата; 2 пиксела отстъп отгоре (виж build).
    return g.cut + at(g.tailSpans, g.fullWidth, dy - g.rowHeight - 2);
  }

  /// Същото, но за знак от ВТОРИЯ абзац (онзи, който при къс първи абзац се
  /// изтегля вдясно от буквицата). Без него съвпаденията точно на границата
  /// между двата абзаца се целеха по началото на региона — оттам и
  /// „дупката" в чертичките там.
  double? dyForCharInSecond(int charIndex) {
    final g = _geometry;
    if (g == null) return null;
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

    // В тясната колона, под първия абзац и луфта помежду им.
    if (g.lines2 > 0 && charIndex < g.cut2) {
      return g.firstNarrowHeight +
          g.paraGap +
          caret(g.narrowSpans2, g.narrowWidth, charIndex);
    }
    // Иначе — в опашката под буквицата, след опашката на първия абзац.
    final padTop = g.lines2 > 0 ? 2.0 : g.paraGap / 2;
    return g.rowHeight +
        g.tail1Height +
        padTop +
        caret(g.tailSpans2, g.fullWidth, charIndex - g.startsAt2);
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
        final capWidth = widget.dropCapSize * 0.40; // приблизителна ширина
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
        final matches = _matchRanges(plain, widget.searchQuery);
        // Вторият абзац — може да влезе вдясно от буквицата, ако първият
        // не стигне до петия ред. Съвпаденията му продължават номерацията
        // на първия, за да не се разминат броячите.
        final runs2 = widget.secondParagraph.isEmpty
            ? const <HtmlRun>[]
            : htmlRuns(widget.secondParagraph);
        final plain2 = runs2.map((r) => r.text).join();
        final matches2 = _matchRanges(plain2, widget.searchQuery);

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
        List<InlineSpan> spansOf(List<HtmlRun> src, String text,
            List<(int, int)> hits, int matchBase, int from, int to,
            {bool forMeasure = false}) {
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
                    style: style,
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
                  style: style,
                  recognizer: tap));
            }
          }
          return out;
        }

        final base2 = widget.firstGlobalMatchIndex + matches.length;
        final measure1 = spansOf(runs, plain, matches,
            widget.firstGlobalMatchIndex, 0, plain.length, forMeasure: true);
        final spans1 = spansOf(runs, plain, matches,
            widget.firstGlobalMatchIndex, 0, plain.length);

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

        // Вторият абзац влиза вдясно САМО ако след първия остава място за
        // поне един негов ред заедно с отстоянието помежду им.
        var spans2 = <InlineSpan>[];
        var lines2 = 0;
        var cut2 = 0;
        if (runs2.isNotEmpty && f1.cut >= plain.length) {
          final freeLines =
              capLines - f1.lines - (paraGap / lineHeightPx).ceil();
          if (freeLines >= 1) {
            spans2 = spansOf(runs2, plain2, matches2, base2, 0, plain2.length);
            final f2 = fit(
                spansOf(runs2, plain2, matches2, base2, 0, plain2.length,
                    forMeasure: true),
                freeLines,
                plain2.length);
            lines2 = f2.lines;
            cut2 = f2.cut;
          }
        }

        // Запомняме измереното, за да може търсенето да пита „на кой пиксел
        // стои този знак". Пише се по време на build нарочно: това е
        // кеширане на мярката, която ТОКУ-ЩО направихме — второ смятане
        // отвън неизбежно би се разминало с тукашните константи.
        final firstNarrowHeight = f1.lines * lineHeightPx;
        final narrowColumnHeight = firstNarrowHeight +
            (lines2 > 0 ? paraGap + lines2 * lineHeightPx : 0.0);
        final tailSpans1 = spansOf(runs, plain, matches,
            widget.firstGlobalMatchIndex, f1.cut, plain.length,
            forMeasure: true);
        // Височината на опашката на първия абзац — нужна, за да знаем къде
        // започва опашката на втория. Мери се само когато има такава.
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
        final startsAt2 = lines2 > 0 ? cut2 : 0;
        _geometry = _CapGeometry(
          narrowSpans: measure1,
          tailSpans: tailSpans1,
          cut: f1.cut,
          narrowWidth: narrowWidth,
          fullWidth: constraints.maxWidth,
          rowHeight: widget.dropCapSize > narrowColumnHeight
              ? widget.dropCapSize
              : narrowColumnHeight,
          base: base,
          scaler: scaler,
          narrowSpans2: runs2.isEmpty
              ? const <InlineSpan>[]
              : spansOf(runs2, plain2, matches2, base2, 0, plain2.length,
                  forMeasure: true),
          tailSpans2: runs2.isEmpty || startsAt2 >= plain2.length
              ? const <InlineSpan>[]
              : spansOf(runs2, plain2, matches2, base2, startsAt2,
                  plain2.length, forMeasure: true),
          cut2: cut2,
          lines2: lines2,
          startsAt2: startsAt2,
          firstNarrowHeight: firstNarrowHeight,
          tail1Height: tail1Height,
          paraGap: paraGap,
        );

        // Какво остава ПОД буквицата. Трите случая се изключват взаимно:
        // или първият абзац е пресечен (тогава вторият изобщо не е влизал),
        // или е влязла част от втория, или вторият стои цял отдолу.
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
        if (runs2.isNotEmpty) {
          final startsAt = lines2 > 0 ? cut2 : 0;
          if (startsAt < plain2.length) {
            tail.add(Padding(
              // Продължение на започнат абзац или съвсем нов — оттам и
              // различното отстояние отгоре.
              padding: EdgeInsets.only(top: lines2 > 0 ? 2 : paraGap / 2),
              child: Text.rich(
                TextSpan(
                    style: base,
                    children: spansOf(runs2, plain2, matches2, base2, startsAt,
                        plain2.length)),
                textAlign: TextAlign.justify,
              ),
            ));
          }
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: capWidth,
                  child: Transform.translate(
                    offset: const Offset(0, 2),
                    child: Text(
                      widget.dropCap,
                      style: TextStyle(
                        fontFamily: kDropCapFamily,
                        fontSize: widget.dropCapSize,
                        height: 1.0,
                        color: widget.capColor,
                      ),
                    ),
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
                      if (lines2 > 0) ...[
                        const SizedBox(height: paraGap),
                        Text.rich(
                          TextSpan(style: base, children: spans2),
                          maxLines: lines2,
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

/// Отделя: (HTML преди абзаца с буквицата; първата буква; текстът на
/// този абзац без буквата; останалият HTML).
///
/// Обхожда абзаците, докато намери такъв, който започва с истинска буква.
/// Така редакторски бележки в скоби ("(не путать с …)"), стоящи между
/// заглавието и житието, отиват в beforeHtml и се рендват нормално, а
/// буквицата пада върху първия същински абзац.
(String, String, String, String) splitDropCap(String html) {
  // Абзац се ПРОПУСКА, ако същинският му текст започва с един от тези
  // знаци — редакторски бележки, цитати, бележки под линия и др. —
  // ИЛИ ако абзацът започва с курсивен таг (<em>/<i>): акцент/курсив
  // не бива да носи буквица. Курсивните абзаци допълнително се
  // центрират (клас .italic-center, виж readerStyles).
  const skipChars = {'(', "'", '*', '/', '«', '"', '['};
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

    // Търсим първия ЗНАЧИМ символ, като прескачаме HTML таговете.
    // Така заглавие в <strong>/<b> в началото на абзаца не пречи —
    // буквицата пада върху първата истинска буква след тага.
    final cm = RegExp(r'^(?:\s|<[^>]+>)*(\S)').firstMatch(inner);
    if (cm == null) continue;
    final ch = cm.group(1)!;

    // Пропускаме абзаца при изрично изброените знаци.
    if (skipChars.contains(ch)) continue;
    // Пропускаме и ако не е буква (цифри, тирета и пр.).
    if (!RegExp(r'[А-Яа-яA-Za-zЀ-ӿ]').hasMatch(ch)) continue;

    before.write(html.substring(cursor, m.start));
    return (
      before.toString(),
      ch,
      // Запазваме таговете преди буквата (напр. отварящ <strong>),
      // за да не се загуби форматирането на останалия текст.
      inner.substring(0, cm.start) + inner.substring(cm.end),
      html.substring(m.end),
    );
  }
  // Няма подходящ абзац за буквица — връщаме html, но със запазени
  // центрирания за курсивните абзаци, засечени дотук.
  return (before.toString() + html.substring(cursor), '', '', '');
}
