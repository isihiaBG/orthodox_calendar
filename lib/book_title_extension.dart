// book_title_extension.dart
//
// Заглавието на заглавната страница — рисувано от НАС, не от flutter_html.
//
// Защо изобщо:
//
// Заглавието е на три реда, като средният („на") е с малки букви. При
// еднакъв кегел той е с x-височина, а съседите му — с главни, тъй че стои
// ниско в реда си и разстоянието над него ИЗГЛЕЖДА по-голямо от долното,
// без да е. В .epub-а това се изравнява с `position: relative; top:-0.12em`
// и в обикновен четец излиза точно.
//
// В приложението — не. Изчерпани са четири пътя (15.08.2026):
//   • `position` от книгата         — flutter_html не го поддържа;
//   • вложени горни индекси         — не се сумират;
//   • отрицателно поле над средния  — не се прилага;
//   • положително поле под средния  — също не се прилага.
//
// Затова заглавието излиза изцяло от HTML-а и се строи с Column и Text, а
// повдигането е Transform.translate — там пиксел значи пиксел.
//
// ⚠ ЗАЩИТА ЗА ДРУГИ КНИГИ. Разширението се задейства само за таг
// <booktitle>, а book_reader._normalize го слага САМО когато заглавието
// започва с „жития на светиите". Утрешна нова книга минава по общия път и
// не се докосва от нищо тук.

import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';

import 'reader_theme.dart';

/// Кеглите спрямо размера на текста в четеца.
const double kBookTitleScale = 3.3;

/// Разстоянието между редовете, спрямо кегела на заглавието.
const double kBookTitleGap = 0.0;

/// Височината на реда. Под 1.0 стяга кутията на всеки ред — шрифтът носи
/// достатъчно въздух и при 1.0 трите реда се разливат.
const double kBookTitleLineHeight = 0.78;

/// Колко нагоре се мести средният ред, спрямо кегела му. Само визуално —
/// Transform.translate не мени подредбата, тъй че блокът не се разлюлява.
const double kBookTitleMidLift = 0.14;

/// Отстоянието под заглавието, спрямо кегела.
const double kBookTitleBottom = 0.34;

class BookTitleExtension extends HtmlExtension {
  final ReaderPalette palette;
  final double fontSize;

  const BookTitleExtension({required this.palette, required this.fontSize});

  @override
  Set<String> get supportedTags => {'booktitle'};

  @override
  InlineSpan build(ExtensionContext context) {
    // Редовете идват разделени с „|" — book_reader ги сглобява така, за да
    // не се налага тук да се разчита HTML.
    final lines = context.styledElement!.element!.text
        .split('|')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (lines.isEmpty) return const TextSpan(text: '');

    final size = fontSize * kBookTitleScale;
    final color = palette.dark
        ? const Color(0xFFFFFAF0)
        : const Color(0xFF000000);
    final style = TextStyle(
      fontFamily: kTitleFamily,
      fontFamilyFallback: kTitleFallback,
      fontSize: size,
      height: kBookTitleLineHeight,
      color: color,
    );

    Widget line(String text, {bool lifted = false}) {
      final t = Text(text, style: style, textAlign: TextAlign.center);
      if (!lifted) return t;
      return Transform.translate(
        offset: Offset(0, -size * kBookTitleMidLift),
        child: t,
      );
    }

    // Средният ред се повдига само ако е с МАЛКИ букви — при три реда с
    // главни няма разминаване и не бива да се мести нищо.
    bool lowercase(String s) =>
        s.toLowerCase() != s.toUpperCase() && s == s.toLowerCase();

    final children = <Widget>[];
    for (var i = 0; i < lines.length; i++) {
      if (i > 0) children.add(SizedBox(height: size * kBookTitleGap));
      children.add(line(lines[i],
          lifted: i == 1 && lines.length == 3 && lowercase(lines[i])));
    }
    children.add(SizedBox(height: size * kBookTitleBottom));

    return WidgetSpan(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: children,
      ),
    );
  }
}
