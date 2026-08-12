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
class _Run {
  final String text;
  final bool bold;
  final bool italic;
  final String? href;
  const _Run(this.text, {this.bold = false, this.italic = false, this.href});
}

/// Разлага HTML на парчета, като разкодира entity-тата и слепва поредните
/// интервали — точно както го прави и чистият текст, по който се мери.
List<_Run> _htmlRuns(String html) {
  final runs = <_Run>[];
  var bold = 0;
  var italic = 0;
  final hrefs = <String>[];
  var lastWasSpace = true; // началните интервали отпадат, както при trim
  final hrefRe = RegExp(r'href="([^"]*)"', caseSensitive: false);

  void push(String t) {
    if (t.isEmpty) return;
    runs.add(_Run(t,
        bold: bold > 0,
        italic: italic > 0,
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
/// база и са само четири (виж _htmlRuns).
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

        final runs = _htmlRuns(widget.firstParagraph);
        final plain = runs.map((r) => r.text).join();
        final matches = _matchRanges(plain, widget.searchQuery);
        // Вторият абзац — може да влезе вдясно от буквицата, ако първият
        // не стигне до петия ред. Съвпаденията му продължават номерацията
        // на първия, за да не се разминат броячите.
        final runs2 = widget.secondParagraph.isEmpty
            ? const <_Run>[]
            : _htmlRuns(widget.secondParagraph);
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
        List<InlineSpan> spansOf(List<_Run> src, String text,
            List<(int, int)> hits, int matchBase, int from, int to) {
          final out = <InlineSpan>[];
          var pos = 0;
          for (final run in src) {
            final start = pos;
            final end = pos + run.text.length;
            pos = end;
            final lo = start < from ? from : start;
            final hi = end > to ? to : end;
            if (lo >= hi) continue;

            final style = base.copyWith(
              fontWeight: run.bold ? FontWeight.w600 : FontWeight.w400,
              fontStyle:
                  run.italic ? FontStyle.italic : FontStyle.normal,
              color: run.href != null ? widget.linkColor : widget.inkColor,
            );
            TapGestureRecognizer? tap;
            if (run.href != null && run.href!.isNotEmpty) {
              tap = TapGestureRecognizer()
                ..onTap = () => widget.onLinkTap(run.href);
              fresh.add(tap);
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

        final f1 = fit(spans1, capLines, plain.length);

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
            final f2 = fit(spans2, freeLines, plain2.length);
            lines2 = f2.lines;
            cut2 = f2.cut;
          }
        }

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
