// pdf_export.dart
//
// Споделяне на четиво като PDF (A4).
//
// ПЪТЯТ, КОЙТО НЕ ТРЪГНА: първо опитахме Printing.convertHtml — подаване
// на готовия HTML на системния WebView. Оказа се, че методът е обявен за
// остарял и на практика увисва: дори документ от един ред не се връща (20
// сек. timeout). Затова оформлението се строи тук ръчно, с pdf пакета.
//
// Предимства на този подход: истински номера на страници (MultiPage.footer)
// и правилно вграждане на шрифтовете — pdf пакетът ги ОРЯЗВА до реално
// ползваните знаци (виж TtfWriter.withChars), затова Charis SIL не надува
// файла и основният текст е със същия шрифт като в четеца.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

// Кеш на шрифтовете — зареждат се веднъж за целия живот на приложението.
pw.Font? _body, _bodyItalic, _bodyBold, _title, _dropCapFont;

Future<void> _ensureFonts() async {
  if (_body != null) return;
  _body = pw.Font.ttf(await rootBundle.load('assets/fonts/CharisSIL-Regular.ttf'));
  _bodyItalic = pw.Font.ttf(await rootBundle.load('assets/fonts/CharisSIL-Italic.ttf'));
  _bodyBold = pw.Font.ttf(await rootBundle.load('assets/fonts/CharisSIL-Bold.ttf'));
  _title = pw.Font.ttf(await rootBundle.load('assets/fonts/Tamburin Modern.ttf'));
  _dropCapFont = pw.Font.ttf(await rootBundle.load('assets/fonts/bukvica.ttf'));
}

const PdfColor _ink = PdfColor.fromInt(0xFF1A1A1A);
const PdfColor _wine = PdfColor.fromInt(0xFF8C2F39);
const PdfColor _dim = PdfColor.fromInt(0xFF555555);
/// Синьото на връзките — същото, с което са оцветени и в четеца
/// (AppColors.sectionTitle, виж 'a' в _htmlStyles там).
const PdfColor _linkBlue = PdfColor.fromInt(0xFF4673AA); //(0xFF8A9BB0);

/// Вътрешните препратки между житията са saint://<слъг> — те имат смисъл
/// само вътре в приложението. В PDF-а водят към същата страница в мрежата,
/// откъдето е и текстът.
String _absoluteHref(String href) => href.startsWith('saint://')
    ? 'https://azbyka.ru/days/${href.substring('saint://'.length)}'
    : href;

const double _bodySize = 20.0;
const double _lineHeight = 1.45;

/// Общият ред, който искаме — в кратни на размера на шрифта.
///
/// `lineSpacing` в pdf пакета е ДОБАВКА върху естествения ред на шрифта, а
/// не замяна. Естественият ред се смята от вертикалните мерки на шрифта
/// (ascender − descender) и е различен за всеки:
///
///     Cambria      1946 − (−455) = 1.172 em
///     Charis SIL   2450 − (−900) = 1.636 em      ← с 40% повече
///
/// Затова твърда добавка не върши работа: при смяната Cambria → Charis SIL
/// общият ред скочи от 1.62 на 2.09 em и житията станаха с една страница
/// по-дълги. Стойността 1.62 е тази, която даваше Cambria (1.172 + 0.45) и
/// се пази нарочно, за да не се промени видът на PDF-ите.
const double _targetLineEm = 1.62;

/// Добавката, която да подадем на pdf пакета, за да излезе общ ред
/// [_targetLineEm]. СМЯТА СЕ ОТ САМИЯ ШРИФТ, тъй че смяна на шрифт не иска
/// никаква промяна тук — точно това беше урокът от Cambria → Charis SIL.
double _lineSpacing(PdfFont font, double fontSize) =>
    (_targetLineEm - (font.ascent - font.descent)) * fontSize;

/// HTML entity-тата, срещани в текстовете (същият списък като в четеца).
String _decodeEntities(String s) {
  const named = {
    '&ndash;': '–', '&mdash;': '—', '&nbsp;': ' ',
    '&laquo;': '«', '&raquo;': '»', '&bdquo;': '„',
    '&ldquo;': '“', '&rdquo;': '”', '&lsquo;': '‘',
    '&rsquo;': '’', '&hellip;': '…', '&middot;': '·',
    '&deg;': '°', '&dagger;': '†', '&amp;': '&',
    '&lt;': '<', '&gt;': '>', '&quot;': '"', '&apos;': "'",
  };
  var out = s;
  named.forEach((k, v) => out = out.replaceAll(k, v));
  out = out.replaceAllMapped(
      RegExp(r'&#(\d+);'), (m) => String.fromCharCode(int.parse(m.group(1)!)));
  out = out.replaceAllMapped(RegExp(r'&#[xX]([0-9a-fA-F]+);'),
      (m) => String.fromCharCode(int.parse(m.group(1)!, radix: 16)));
  return out;
}

/// Един блок текст от HTML-а: абзац или заглавие.
class _Block {
  final String text;
  final bool isHeading;
  final bool isItalic;
  /// Абзацът започва с курсивен таг (<em>/<i>) — акцент/цитат, който не
  /// бива да носи буквица (същото правило като в четеца).
  final bool startsItalic;
  /// CSS класът от HTML-а (prayerhead, csl, trans, source…). По него се
  /// прилагат СЪЩИТЕ стилове като в четеца — виж _htmlStyles там.
  final String cls;
  /// Суровата вътрешност на тага — нужна за вложените <strong>/<em>
  /// (напр. богослужебните указания в службата).
  final String inner;
  const _Block(this.text,
      {this.isHeading = false,
      this.isItalic = false,
      this.startsItalic = false,
      this.cls = '',
      this.inner = ''});
}

/// Разделя HTML-а на абзаци/заглавия и маха таговете. Оформлението тук е
/// нарочно просто — PDF-ът е за четене и печат, не за пресъздаване на
/// всяка подробност от екрана.
List<_Block> _parseBlocks(String html) {
  final blocks = <_Block>[];
  final re = RegExp(r'<(p|h[1-6])\b([^>]*)>(.*?)</\1>',
      dotAll: true, caseSensitive: false);
  for (final m in re.allMatches(html)) {
    final tag = m.group(1)!.toLowerCase();
    final attrs = m.group(2) ?? '';
    final inner = m.group(3)!;
    final text = _decodeEntities(inner.replaceAll(RegExp(r'<[^>]+>'), ''))
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (text.isEmpty) continue;
    final clsMatch =
        RegExp(r'class="([^"]*)"', caseSensitive: false).firstMatch(attrs);
    final cls = clsMatch?.group(1) ?? ''; // <- беше пропуснато
    
    blocks.add(_Block(
      text,
      isHeading: tag != 'p',
      isItalic: attrs.contains('italic-center') ||
          attrs.contains('trans') ||
          attrs.contains('source') ||
          cls.contains('memorydate'), //My Bugfix #1
      startsItalic:
          RegExp(r'^\s*<(?:em|i)\b', caseSensitive: false).hasMatch(inner),
      cls: clsMatch?.group(1) ?? '',
      inner: inner,
    ));
  }
  // Ако HTML-ът няма нито един <p> (рядко, но възможно), пускаме всичко
  // като един абзац, вместо да върнем празен документ.
  if (blocks.isEmpty) {
    final text = _decodeEntities(html.replaceAll(RegExp(r'<[^>]+>'), ''))
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (text.isNotEmpty) blocks.add(_Block(text));
  }
  return blocks;
}

/// Разделя текста на "първите maxLines реда" и остатък, като мери
/// РЕАЛНАТА ширина на думите (PdfFont.stringMetrics), а не по средна
/// ширина на знак. Ползва се и от буквицата, и от задържането на
/// заглавен ред при него (виж _keepWithNext).
/// [firstIndent] е ширината на отстъпа на ПЪРВИЯ ред (кутията-таб пред
/// абзаца). Без него сметката излиза с един ред по-малко и остатъкът от
/// "първите два реда" пада на трети, полупразен ред — точно откъдето
/// абзацът изглеждаше разкъсан.
({String head, String rest}) _splitLines(
    String text, double width, PdfFont font, double fontSize, int maxLines,
    {double firstIndent = 0}) {
  final words = text.split(' ');
  final lines = <String>[];
  var current = '';
  for (final w in words) {
    final candidate = current.isEmpty ? w : '$current $w';
    final avail = lines.isEmpty ? width - firstIndent : width;
    if (font.stringMetrics(candidate).width * fontSize <= avail ||
        current.isEmpty) {
      current = candidate;
    } else {
      lines.add(current);
      current = w;
      if (lines.length >= maxLines) break;
    }
  }
  if (lines.length < maxLines && current.isNotEmpty) lines.add(current);
  final head = lines.take(maxLines).join(' ');
  final rest = text.length > head.length ? text.substring(head.length).trim() : '';
  return (head: head, rest: rest);
}

/// Разбива вътрешността на абзац на парчета според вложените тагове.
/// Нужно е за службата, където <strong> носи богослужебните указания (по
/// традиция в червено), и за превода, чийто етикет "Превод:" е получер и
/// прав, за разлика от курсивния текст около него — точно както в четеца.
///
/// Удебеляването е с ИСТИНСКИ получер шрифт (CharisSIL-Bold.ttf). Опитът да се
/// симулира с PdfTextRenderingMode.fillAndStroke се провали: pdf пакетът
/// изписва режима, но никога не го връща обратно (graphics.dart:538 —
/// пише само когато режимът е различен от "запълване"), затова
/// удебеляването изтичаше върху целия текст след него.
List<pw.InlineSpan> _inlineSpans(
  String inner,
  pw.TextStyle base, {
  required PdfColor strongColor,
  /// Целият блок вече е получер (напр. заглавният ред на тропара). Без
  /// това стиловете тук биха го върнали на нормален, защото вътре в него
  /// няма <strong> — точно това "изяде" удебеляването веднъж.
  bool baseBold = false,

  /// Целият блок е в курсив по клас (.trans, .source), а не заради <em>.
  /// Същият капан като при baseBold: без това всяко парче се връщаше на
  /// прав шрифт и преводът излизаше нормален вместо курсивен.
  bool baseItalic = false,
}) {
  final spans = <pw.InlineSpan>[];
  // strong = истинско <strong>/<b> (носи и цвят), label = етикетът
  // "Превод:" (получер и ПРАВ, но с цвета на абзаца, не на <strong>).
  var strong = 0;
  var label = 0;
  var italic = 0;
  // Номерата на бележките — <sup>. Рисуват се по-дребни и повдигнати:
  // `pdf` пакетът НЯМА superscript в TextStyle (проверено — там са само
  // fontSize, letterSpacing, lineSpacing, height), тъй че повдигането се
  // прави на ръка, с намален размер и вдигната основна линия.
  var sup = 0;
  // Стек с адресите на отворените <a> — вложени връзки няма, но стекът
  // пази реда и при неточно затворени тагове.
  final hrefs = <String>[];
  final stack = <String>[];
  for (final m in RegExp(r'<[^>]+>|[^<]+').allMatches(inner)) {
    final piece = m.group(0)!;
    if (piece.startsWith('<')) {
      final t = piece.toLowerCase();
      if (t.startsWith('<strong') || t.startsWith('<b>')) {
        strong++;
        stack.add('b');
      } else if (t.startsWith('</strong') || t.startsWith('</b>')) {
        if (strong > 0) strong--;
        if (stack.isNotEmpty) stack.removeLast();
      } else if (t.startsWith('<em') || t.startsWith('<i>')) {
        italic++;
        stack.add('i');
      } else if (t.startsWith('</em') || t.startsWith('</i>')) {
        if (italic > 0) italic--;
        if (stack.isNotEmpty) stack.removeLast();
      } else if (t.startsWith('<sup')) {
        sup++;
        stack.add('sup');
      } else if (t.startsWith('</sup')) {
        if (sup > 0) sup--;
        if (stack.isNotEmpty && stack.last == 'sup') stack.removeLast();
      } else if (t.startsWith('<a')) {
        final href = RegExp(r'''href=["']([^"']+)["']''', caseSensitive: false)
            .firstMatch(piece)
            ?.group(1);
        hrefs.add(href == null ? '' : _absoluteHref(href));
        stack.add('a');
      } else if (t.startsWith('</a')) {
        if (hrefs.isNotEmpty) hrefs.removeLast();
        if (stack.isNotEmpty && stack.last == 'a') stack.removeLast();
      } else if (t.contains('translabel')) {
        label++;
        stack.add('label');
      } else if (t.startsWith('</span')) {
        if (stack.isNotEmpty && stack.last == 'label') {
          stack.removeLast();
          if (label > 0) label--;
        }
      }
      continue;
    }
    final text = _decodeEntities(piece).replaceAll(RegExp(r'\s+'), ' ');
    if (text.isEmpty) continue;
    final isBold = strong > 0 || label > 0 || baseBold;
    // Етикетът "Превод:" е нарочно ПРАВ насред курсивния превод.
    final isItalic = (italic > 0 || baseItalic) && label == 0;
    final href = hrefs.isEmpty ? '' : hrefs.last;
    final link = href.isNotEmpty ? 1 : 0;
    final isSup = sup > 0;
    // Номерът на бележка е ВЪТРЕШНА връзка, не външна.
    //
    // ⚠ Дотогава тук минаваше AnnotationUrl със самия href от .epub-а —
    // „../Text/note5041.xhtml#note5041". В PDF това не значи нищо: номерът
    // излизаше син (тоест изглеждаше кликаем), а не водеше никъде. Сега
    // сочи към котвата на бележката в края на документа.
    final noteNum = isSup && _isNoteHref(href) ? text.trim() : null;
    if (noteNum != null) {
      // Котва НА МЯСТОТО в текста — за обратния път от бележката насам.
      // Anchor е widget, не span, затова минава през WidgetSpan.
      //
      // ⚠ Механизмът тук винаги си е бил наред. Истинският бъг, заради
      // който бележка 1–7 не водеха обратно, седеше в _spansAfter надолу
      // във файла: тя изхвърляше БЕЗУСЛОВНО всеки WidgetSpan (значи и тази
      // котва), щом абзацът се разцепваше след първите два реда — а точно
      // това се случваше с по-голямата част от позоваванията в дългите
      // абзаци. Вижте поправката и обяснението там.
      //
      // ⚠ Детето на котвата е SizedBox, НЕ Text('\u200B'): zero-width
      // space си е истински знак, за който шрифтът трябва да търси глиф —
      // и нямайки такъв, показва квадратче за непознат символ вместо да
      // го скрие. SizedBox няма никакъв текст за изчертаване, значи няма
      // и какво да се обърка.
      spans.add(pw.WidgetSpan(
        child: pw.Anchor(name: _refAnchor(noteNum), child: pw.SizedBox()),
      ));
    }

    // Истинско повдигане: НЕ местене на нормални цифри с baseline/
    // Transform (и двете опряха в тънки места на pdf пакета — baseline
    // мълчаливо не действаше в justify абзаци, а Transform.translate
    // буташе рисуването извън изрязващата рамка на WidgetSpan-а и
    // числото изчезваше). Вместо туй — истински Unicode superscript
    // знаци (¹ ² ³ …): те са малки и вдигнати по дизайн на шрифта,
    // изчертават се като обикновен текст, без нужда от каквато и да е
    // намеса в оразмеряването на реда.
    //
    // ⚠ След като преминахме към Unicode superscript, вече не ползваме
    // `fontSize` или `height` — знаците са проектирани да са малки
    // и повдигнати от самия шрифт. Това е най-чистото решение.
    final renderText = isSup ? _toSuperscriptDigits(text) : text;
    spans.add(pw.TextSpan(
      text: renderText,
      // Само това парче става кликаемо — не целият абзац.
      annotation: noteNum != null
          ? pw.AnnotationLink(_noteAnchor(noteNum))
          : (link > 0 ? pw.AnnotationUrl(href) : null),
      style: base.copyWith(
        // И font, И fontWeight: TextStyle пази отделни шрифтове за
        // нормален/получер/курсив и избира между тях по fontWeight —
        // само подаването на font може да се окаже недостатъчно.
        font: isItalic ? _bodyItalic : (isBold ? _bodyBold : _body),
        fontNormal: isItalic ? _bodyItalic : (isBold ? _bodyBold : _body),
        fontBold: _bodyBold,
        fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
        color: link > 0
            ? _linkBlue
            : (strong > 0 ? strongColor : base.color),
      ),
    ));
  }
  return spans;
}

/// Превръща ASCII цифри в техните Unicode superscript форми (¹ ² ³ …)
/// и добавя повдигнати скоби около тях, за да се улесни кликването.
///
/// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
/// БЪГФИКС #3: ДОБАВЯНЕ НА ПОВДИГНАТИ СКОБИ
/// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
/// Повдигнатите скоби (U+207D и U+207E) увеличават зоната за
/// докосване на номерата на бележките, което улеснява кликването
/// с пръст на мобилни устройства. Скобите са част от кликаемия
/// текст, така че целият повдигнат текст (скоби + номер) е активен.
///
/// Знаци извън 0–9 остават непипнати — по-добре да се изпише
/// нормално, отколкото да пропадне целият пасаж.
///
/// Charis SIL, като шрифт с научно/лингвистично предназначение,
/// носи всички тези Unicode superscript знаци — проверено визуално
/// в получения PDF.
/// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
String _toSuperscriptDigits(String s) {
  const map = {
    '0': '\u2070', '1': '\u00B9', '2': '\u00B2', '3': '\u00B3',
    '4': '\u2074', '5': '\u2075', '6': '\u2076', '7': '\u2077',
    '8': '\u2078', '9': '\u2079',
  };
  final buf = StringBuffer();
  bool hasDigit = false;
  for (final ch in s.split('')) {
    if (map.containsKey(ch)) {
      if (!hasDigit) {
        buf.write('\u207D'); // Лява повдигната скоба U+207D
        hasDigit = true;
      }
      buf.write(map[ch]);
    } else {
      if (hasDigit) {
        buf.write('\u207E'); // Дясна повдигната скоба U+207E
        hasDigit = false;
      }
      buf.write(ch);
    }
  }
  if (hasDigit) {
    buf.write('\u207E'); // Дясна повдигната скоба
  }
  return buf.toString();
}

/// Имената на котвите в PDF-а. Две за всяка бележка — едната при номера в
/// текста, другата при самата бележка в края, — за да се ходи в двете
/// посоки.
String _noteAnchor(String num) => 'note-$num';
String _refAnchor(String num) => 'ref-$num';

/// Връзка към бележка ли е това? В .epub-ите те сочат към note<NNNN>.xhtml.
bool _isNoteHref(String href) =>
    RegExp(r'note\d+', caseSensitive: false).hasMatch(href);

/// Една бележка под линия: номерът, както стои в текста, и текстът ѝ.
class _Note {
  final String number;
  final String text;
  const _Note(this.number, this.text);
}

/// Изважда бележките от HTML-а, по реда на срещането им.
///
/// ⚠ Текстът стои в `title` атрибута на връзката, не в отделен файл:
///
///     <a href="../Text/note5041.xhtml#note5041"
///        title="Лъв III Исаврянин – император от 716 до 741 г.">
///       <sup>5041</sup></a>
///
/// Затова PDF-ът не се нуждае от достъп до архива — всичко е в подадения
/// HTML. (В четеца същият `title` пълни изскачащото прозорче.)
///
/// Повторенията се пропускат: един и същ номер може да се срещне два пъти
/// в дълго житие, а в списъка накрая му е мястото веднъж.
List<_Note> _collectNotes(String html) {
  final out = <_Note>[];
  final seen = <String>{};

  // Търси и двата варианта:   [My Bugfix #2]
  // 1. <a title="..."><sup>...</sup></a>
  // 2. <sup><a title="...">...</a></sup>
  final re = RegExp(
    r'<a\b[^>]*?title="([^"]*)"[^>]*>\s*<sup[^>]*>(.*?)</sup>|'
    r'<sup[^>]*>\s*<a\b[^>]*?title="([^"]*)"[^>]*>(.*?)</a>\s*</sup>',

  // final re = RegExp(  // преди търсеше само единия вариант 
  //   r'<a\b[^>]*?title="([^"]*)"[^>]*>\s*<sup[^>]*>(.*?)</sup>',
    caseSensitive: false,
    dotAll: true,
  );
  
  for (final m in re.allMatches(html)) {
    final title   = m.group(1) ?? m.group(3) ?? '';
    final numText = m.group(2) ?? m.group(4) ?? '';
    final num = _decodeEntities(numText.replaceAll(RegExp(r'<[^>]+>'), '').trim());

  //   final title = _decodeEntities(m.group(1)!).trim();
  //   final num = _decodeEntities(m.group(2)!.replaceAll(RegExp(r'<[^>]+>'), ''))
  //       .trim();
    if (title.isEmpty || num.isEmpty || !seen.add(num)) continue;
    out.add(_Note(num, title));
  }
  return out;
}

/// Вярно, ако единствените тагове в абзаца са връзки (<a>). Тогава
/// шрифтът е един и същ по цялата дължина и мярката на редовете излиза
/// точна — а без това правилото за самотните редове не може да се приложи
/// безопасно.
bool _onlyLinkTags(String inner) =>
    !RegExp(r'<(?!/?a\b)[^>]*>', caseSensitive: false).hasMatch(inner);

/// Същите парчета, но без първите [skip] знака — с непокътнати цветове и
/// връзки. Така остатъкът от абзаца не се сглобява наново от HTML-а.
List<pw.InlineSpan> _spansAfter(List<pw.InlineSpan> spans, int skip) {
  final out = <pw.InlineSpan>[];
  var left = skip;
  for (final s in spans) {
    if (s is pw.WidgetSpan) {
      // Котвите (WidgetSpan) нямат текст и не влизат в мярката на редовете
      // — но затова пък позицията им спрямо прекъсването [skip] не личи от
      // дължина на текст, а само от това дали вече сме подминали [skip]
      // знака в останалите (текстовите) парчета.
      //
      // ⚠ ТУК беше истинският бъг зад "бележките не водят обратно": преди
      // се изхвърляха БЕЗУСЛОВНО, с идеята, че "целта им вече е в първата
      // половина". Вярно е само когато котвата наистина пада в първите два
      // реда. Номерата на бележки, паднали ПОСЛЕ прекъсването (какъвто е
      // случаят с почти всички позовавания в по-дългите абзаци — оттам и
      // защо само бележка 8, в кратко изречение, изобщо работеше), се
      // губеха именно тук: в PDF-а така и не излизаше цел „ref-N“, към
      // която бележката в края на документа да може да води обратно.
      if (left <= 0) out.add(s);
      continue;
    }
    if (s is! pw.TextSpan) continue;
    final t = s.text ?? '';
    if (left >= t.length) {
      left -= t.length;
      continue;
    }
    final cut = left > 0 ? t.substring(left) : t;
    left = 0;
    // Пренесеният ред не бива да започва с интервала от мястото на къса.
    final text = out.isEmpty ? cut.trimLeft() : cut;
    if (text.isEmpty) continue;
    out.add(pw.TextSpan(
        text: text, style: s.style, annotation: s.annotation));
  }
  return out;
}

/// Отваряща кавичка от какъвто и да е вид — виж коментара при
/// [_dropCapLetterInfo] по-долу.
const _openQuotes = {
  '„', '\u201c', '\u201d', '«', '\u2039', '\u2018', '\u2019', '"', "'",
};

/// Кой знак носи буквицата и колко знака трябва да отпаднат от началото на
/// текста, за да продължи нормалният поток. Обикновено е просто първият
/// знак (skip: 1). Ако абзацът започва с отваряща кавичка, последвана от
/// истинска буква ("„Да се пази…"), буквицата пада на БУКВАТА (не на
/// кавичката), а кавичката се връща отделно, за да увисне вляво от
/// буквицата — вижте употребата ѝ в [_dropCapWidgets].
///
/// Преди кавичка от този вид изхвърляше целия абзац от буквицата — тя
/// кацаше на следващия, съвсем различен абзац. Виж същия проблем и
/// поправка в четеца (drop_cap.dart, splitDropCap).
({String quote, String cap, int skip}) _dropCapLetterInfo(String text) {
  if (text.isEmpty) return (quote: '', cap: '', skip: 0);
  final first = text.substring(0, 1);
  if (_openQuotes.contains(first) && text.length > 1) {
    return (quote: first, cap: text.substring(1, 2), skip: 2);
  }
  return (quote: '', cap: first, skip: 1);
}

/// Кой абзац заслужава буквица — същите правила като в четеца
/// (_splitDropCap): пропускат се редакторски бележки в скоби, курсивни
/// акценти и всичко, което не започва с истинска буква (евентуално през
/// отваряща кавичка — виж [_dropCapLetterInfo]). Търси се само в началото
/// на текста, не насред него.
bool _eligibleForDropCap(_Block b) {
  if (b.isHeading || b.isItalic || b.startsItalic) return false;
  // ⚠ Редът с паметта („Памет на 9 август") е УКАЗАНИЕ, не начало на
  // разказа. В .epub-а той е обикновен `div.paragraph` — със същия клас
  // като истинските абзаци, — тъй че по нищо друго не се различава.
  // Четецът го подминава, защото `_normalize` му дава клас `memorydate`,
  // а splitDropCap търси ГОЛ `<p>`. Тук проверката трябва да е изрична:
  // без нея буквицата кацаше върху него и излизаше „П|амет на 9 август",
  // а истинското начало („Когато на престола…") оставаше без нея.
  if (b.cls.contains('memorydate')) return false;
  // Наистина "скипващи" знаци — бележки в скоби, звездички, разделител
  // на сцена. Кавичките НЕ са тук вече — те минават през _dropCapLetterInfo.
  const skipChars = {'(', '*', '/', '['};
  if (b.text.isEmpty) return false;
  final first = b.text.substring(0, 1);
  if (skipChars.contains(first)) return false;
  final info = _dropCapLetterInfo(b.text);
  return RegExp(r'[А-Яа-яA-Za-zЀ-ӿ]').hasMatch(info.cap);
}

/// Колко реда заема текстът при дадена ширина.
int _countLines(String text, double width, PdfFont font, double fontSize) {
  var lines = 1;
  var current = '';
  for (final w in text.split(' ')) {
    final candidate = current.isEmpty ? w : '$current $w';
    if (font.stringMetrics(candidate).width * fontSize <= width ||
        current.isEmpty) {
      current = candidate;
    } else {
      lines++;
      current = w;
    }
  }
  return lines;
}

/// Началото на четивото с водеща буква. pdf пакетът няма CSS float, затова
/// обтичането се прави като в четеца: буквата отляво, а вдясно от нея —
/// пет реда текст.
///
/// Тези пет реда се пълнят от КОЛКОТО АБЗАЦА ПОТРЯБВАТ, а не само от
/// първия. Иначе, ако първият абзац е кратък, вдясно от буквицата зейваше
/// празнина, а следващият абзац чакаше чак под нея. Абзаците след първия
/// получават обичайния си отстъп на първия ред и по-широко отстояние
/// отгоре — за да личи, че са нови абзаци, а не пренесени редове.
///
/// Връща и колко блока е поел, за да ги прескочи главният цикъл.
({List<pw.Widget> widgets, int consumed}) _dropCapWidgets(
  List<_Block> blocks,
  int start,
  double pageWidth,
  PdfFont measureFont, {
  required PdfColor strongColor,
}) {
  const capLines = 5;
  final lineHeightPt = _bodySize * _lineHeight;
  // Отстъпът между блока с буквицата и остатъка от абзаца — там абзацът се
  // пречупва на два widget-а и шевът личи, ако не се премери.
  //
  // Шевът е descender + blockGap + ascender, тъй че зависи от шрифта:
  //     Cambria   4.44 + 9 + 19.00 = 32.4  → незабележим
  //     Charis SIL 8.79 + 9 + 23.93 = 41.7  → зее насред абзаца
  // Charis има с 4.9 пункта по-висок ascender и с 4.4 по-дълбок descender и
  // те се събират точно тук. Затова тръгваме от същата поправка както при
  // междуредието и добавяме малкото, което Cambria на практика имаше (~4),
  // за да не се слепят двата блока.
  final blockGap = _lineSpacing(measureFont, _bodySize) + 4;

  // Размерът е ЗАДАДЕН ПРЯКО (както в четеца), а не мащабиран през
  // FittedBox: там глифът се вписваше заедно с празните полета около себе
  // си и изглеждаше дребен и изместен надясно. Единичен знак няма как да
  // се пренесе на нов ред, така че широчината на кутията не го застрашава.
  final capFontSize = lineHeightPt * capLines * 0.85;
  final capWidth = capFontSize * 0.45;
  // Буквицата трябва да НАДВИШАВА горния ръб на първия ред (както в
  // четеца). Постига се с отстъп отгоре на съседния текст: самата буква
  // започва най-горе в блока, а текстът тръгва по-надолу. Bukvica има
  // голямо празно поле над същинския глиф, затова отстъпът е по-щедър от
  // "на око" очакваното.
  final capRise = _bodySize * 0.9;
  // Освен отстъпа на съседния текст, самата буква се ИЗМЕСТВА нагоре.
  // Само с отстъпа не става: глифът се рисува на фиксирано място спрямо
  // кутията си, затова над определена точка увеличаването му не личеше.
  final capShift = _bodySize * 1.8;

  final narrowWidth = pageWidth - capWidth - 8;
  const paraGap = 20.0; // същото отстояние като между абзаците по-долу
  final indentWidth = _bodySize * 1.6;

  final style = pw.TextStyle(
      font: _body, fontSize: _bodySize,
      lineSpacing: _lineSpacing(measureFont, _bodySize), color: _ink);

  // Буквата на буквицата и евентуалната кавичка пред нея — смятаме го
  // ВЕДНЪЖ тук, защото трябва навсякъде долу: колко знака да отпаднат от
  // текста (skip) И самите знаци за рисуване накрая.
  final dropInfo = _dropCapLetterInfo(blocks[start].text);

  final beside = <pw.Widget>[]; // фрагментите вдясно от буквицата
  final tail = <pw.Widget>[]; // онова, което продължава под нея
  var consumed = 0;
  var budget = capLines.toDouble(); // остатък в редове
  final gapLines = paraGap / lineHeightPt;

  var idx = start;
  var isFirst = true;
  while (idx < blocks.length && budget >= 1) {
    final b = blocks[idx];
    if (!isFirst) {
      // Вдясно от буквицата влизат само обикновени абзаци: заглавие или
      // курсивен акцент там би изглеждал притиснат.
      if (b.isHeading || b.isItalic || !_onlyLinkTags(b.inner)) break;
      if (budget - gapLines < 1) break;
      budget -= gapLines;
    }

    var spans = _inlineSpans(b.inner.isEmpty ? b.text : b.inner, style,
        strongColor: strongColor);
    // Първият знак (или кавичка + знак) вече е нарисуван като буквица.
    if (isFirst) spans = _spansAfter(spans, dropInfo.skip);
    // Само текстовите парчета — котвите нямат ширина и не влизат в
    // мярката на редовете.
    final plain =
        spans.whereType<pw.TextSpan>().map((x) => x.text ?? '').join();
    if (plain.isEmpty) break;

    final maxLines = budget.floor();
    final indent = isFirst
        ? null
        : pw.WidgetSpan(child: pw.SizedBox(width: indentWidth));
    final needed = _countLines(plain, narrowWidth, measureFont, _bodySize);

    if (beside.isNotEmpty) beside.add(pw.SizedBox(height: paraGap));

    if (needed <= maxLines) {
      // Целият абзац се събира вдясно от буквицата. Последният му ред е
      // истински край на абзац — затова НЕ се разпъва, точно както трябва.
      beside.add(pw.RichText(
        textAlign: pw.TextAlign.justify,
        text: pw.TextSpan(
            style: style,
            children: [if (indent != null) indent, ...spans]),
      ));
      budget -= needed;
      consumed++;
      idx++;
      isFirst = false;
      continue;
    }

    // Абзацът се пресича: вдясно остават maxLines реда, останалото минава
    // под буквицата. Подава се ЦЕЛИЯТ абзац с maxLines — така последният
    // от тези редове не е "последен за widget-а" и се разпъва наравно с
    // другите (виж бележката при абзаците в sharePdf).
    final split = _splitLines(
        plain, narrowWidth, measureFont, _bodySize, maxLines,
        firstIndent: indent != null ? indentWidth : 0);
    beside.add(pw.RichText(
      textAlign: pw.TextAlign.justify,
      maxLines: maxLines,
      text: pw.TextSpan(
          style: style, children: [if (indent != null) indent, ...spans]),
    ));
    tail
      ..add(pw.SizedBox(height: blockGap))
      ..add(pw.RichText(
        textAlign: pw.TextAlign.justify,
        // Без overflow.span текстът НЕ се пренася между страници (виж
        // RichText.canSpan в pdf пакета).
        overflow: pw.TextOverflow.span,
        text: pw.TextSpan(
            style: style,
            children: _spansAfter(spans, split.head.length)),
      ));
    consumed++;
    budget = 0;
    break;
  }

  return (
    consumed: consumed == 0 ? 1 : consumed,
    widgets: [
      // Два ОТДЕЛНИ widget-а, не общ Column: Column в pdf пакета не се дели
      // между страници. Редът с буквицата НЕ е с фиксирана височина — ако
      // съседният текст поеме ред повече от очакваното, редът просто
      // пораства, вместо съдържанието да се застъпи.
      pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.SizedBox(
          // Височината е ИЗРИЧНА (точно колкото са редовете до буквицата).
          // Bukvica има високи горни/долни израстъци и без това ограничение
          // редът се раздуваше повече от текста, оставяйки празен ред след
          // блока. Глифът просто "виси" извън кутията — точно каквото искаме.
          width: capWidth,
          height: capLines * lineHeightPt,
          // Stack, не просто Transform: кавичката (ако има) виси ОТВЪН тази
          // кутия, вляво — `pw.Positioned` с отрицателен `left`.
          //
          // ⚠ pw.Stack по подразбиране изрязва децата си на границите си
          // (overflow: Overflow.clip) — точно обратното на нужното тук.
          // Без изричното overflow: Overflow.visible кавичката просто
          // изчезва, също като квадратчето за непознат символ по-рано.
          child: pw.Stack(
            overflow: pw.Overflow.visible,
            children: [
              pw.Transform.translate(
                // Положителна стойност = НАГОРЕ (проверено емпирично:
                // отрицателната свали буквата върху следващия ред).
                offset: PdfPoint(0, capShift),
                child: pw.Text(dropInfo.cap,
                    style: pw.TextStyle(
                        font: _dropCapFont,
                        fontSize: capFontSize,
                        color: _wine)),
              ),
              if (dropInfo.quote.isNotEmpty)
                pw.Positioned(
                  // ⚠ "На око", за разлика от Transform по-горе тук
                  // top/left са в обичайната посока (надолу/наляво),
                  // както навсякъде другаде в pdf пакета (напр.
                  // EdgeInsets.only(top:...)) — Positioned е layout
                  // widget, не суров canvas transform. Буквицата има
                  // голямо празно поле над истинския си глиф, затова
                  // визуално стърчи над реда въпреки capShift — кавичката
                  // трябва да излезе на височината на ПЪРВИЯ РЕД от
                  // съседния текст (там, където той тръгва след
                  // EdgeInsets.only(top: capRise) вдясно), не на върха на
                  // буквата. Провери визуално и подкарай тези константи.
                  top: capRise * 0.15,
                  left: -_bodySize * 0.25, //0.95,
                  child: pw.Text(dropInfo.quote,
                      style: pw.TextStyle(
                          font: _body,
                          fontSize: _bodySize * 1.35,
                          color: _wine)), //_ink)),
                ),
            ],
          ),
        ),
        pw.SizedBox(width: 8),
        pw.Expanded(
          child: pw.Padding(
            padding: pw.EdgeInsets.only(top: capRise),
            child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: beside),
          ),
        ),
      ]),
      ...tail,
    ],
  );
}

/// Сглобява PDF-а и отваря стандартния диалог за споделяне.
Future<void> sharePdf({
  required String title,
  required String bodyHtml,
  required String fileName,
  bool withDropCap = true,
  /// В службата <strong> носи богослужебните указания и по традиция е в
  /// червено; в житието същият таг е обикновено ударение (виж четеца).
  bool strongIsWine = false,
  /// Тропари/кондаци/служба: там заглавието се отделя по-осезаемо от
  /// текста. Житията и сказанията остават с досегашния отстъп.
  bool prayerLike = false,
}) async {
  await _ensureFonts();
  final blocks = _parseBlocks(bodyHtml);
  const margin = 40.0;
  final contentWidth = PdfPageFormat.a4.width - margin * 2;

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // БЪГФИКС #1: ИМЕ НА PDF ФАЙЛА
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // Извличаме заглавието (h1) и подзаглавието (memorydate) от вече
  // парсираните blocks, за да формираме смислено име на файла.
  // Предишният код разчиташе само на подадения параметър `fileName`,
  // който идваше отвън и съдържаше само подзаглавието.
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  String mainTitle = '';
  String subTitle = '';
  for (final block in blocks) {
    if (block.isHeading && mainTitle.isEmpty) {
      mainTitle = block.text;
    } else if (block.cls.contains('memorydate') && subTitle.isEmpty) {
      subTitle = block.text;
    }
  }
  // Ако няма заглавие, ползваме подаденото title
  if (mainTitle.isEmpty) mainTitle = title;
  // Формираме името: "Подзаглавие - Заглавие.pdf"
  // Ако няма подзаглавие или то е същото като заглавието, ползваме само заглавието
  final pdfBaseName = subTitle.isNotEmpty && mainTitle != subTitle
      ? '$subTitle - $mainTitle'
      : mainTitle;
  // Дребните жития обикновено имат прилични заглавия, но да не разчитаме
  // на late late — знаци, забранени във файлови имена (Android/Windows/
  // iOS: / \ : * ? " < > |), се махат, иначе записът на диска може да
  // откаже точно заради тях.
  final pdfFileName =
      '${pdfBaseName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '').trim()}.pdf';

  final doc = pw.Document();
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(margin),
      // pdf пакетът спира по подразбиране на 20 страници (предпазна мярка
      // срещу безкраен цикъл). При едър шрифт дългите жития лесно я минават
      // и генерирането гърмеше — вдигаме тавана.
      maxPages: 2000,
      // Истински номера на страници — заради тях изоставихме HTML пътя.
      footer: (context) => pw.Container(
        alignment: pw.Alignment.center,
        margin: const pw.EdgeInsets.only(top: 12),
        child: pw.Text('${context.pageNumber} / ${context.pagesCount}',
            // Изрично и през fontNormal: pdf пакетът избира шрифта по
            // fontWeight/fontStyle от отделните полета, а само `font`
            // минава през сливането с темата на документа.
            style: pw.TextStyle(
                font: _body,
                fontNormal: _body,
                fontSize: _bodySize - 2,
                color: _dim)),
      ),
      build: (context) {
        // Ако самото четиво започва със заглавие (<h1>..<h6>), нашето име
        // отгоре е излишно — иначе излизат две заглавия едно под друго.
        // Същата проверка като hasOwnTitle в четеца.
        final hasOwnTitle = blocks.isNotEmpty && blocks.first.isHeading;
        final widgets = <pw.Widget>[
          if (!hasOwnTitle) ...[
            pw.Center(
              child: pw.Text(title,
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(font: _title, fontSize: 34, color: _ink)),
            ),
            pw.SizedBox(height: prayerLike ? 56 : 22),
          ],
        ];
        var dropCapUsed = false;
        var mainHeadingUsed = false;
        var scanned = 0;
        String? pendingRest;
        double? mainHeadingGap;
        for (var i = 0; i < blocks.length; i++) {
          final b = blocks[i];
          mainHeadingGap = null;
          // Разпознава се по КЛАСА, който слагаме ние, а не по думата
          // "Източник": 49 жития завършват със собствен ред за източник,
          // част от самия текст. По думата спирахме на него и оставяхме
          // навън и тропарите, и нашата атрибуция.
          if (b.cls.contains('source') && widgets.isNotEmpty) {
            widgets.add(pw.SizedBox(height: 18));
          }
          // Началото на тропарите под житието — иска въздух над себе си,
          // за да не изглежда като продължение на последния абзац.
          // Заглавие тук няма нарочно: разделя ги отстоянието.
          if (b.cls.contains('pdfgap') && widgets.isNotEmpty) {
            widgets.add(pw.SizedBox(height: 40));
          }
          // Този абзац вече е започнат заедно със заглавието си — тук
          // остава да се изпише само остатъкът му.
          String blockText = b.text;
          if (pendingRest != null && !b.isHeading) {
            if (pendingRest!.isEmpty) {
              pendingRest = null;
              continue; // целият абзац се е побрал при заглавието
            }
            blockText = pendingRest!;
            pendingRest = null;
          }
          // Буквица само в началото (първите три абзаца), както в четеца.
          if (!b.isHeading) scanned++;
          final useDropCap = withDropCap &&
              !dropCapUsed &&
              scanned <= 3 &&
              _eligibleForDropCap(b);
          if (useDropCap) {
            dropCapUsed = true;
            final dc = _dropCapWidgets(
                blocks, i, contentWidth, _body!.getFont(context),
                strongColor: strongIsWine ? _wine : _ink);
            widgets.addAll(dc.widgets);
            // Буквицата може да е погълнала няколко абзаца — цикълът
            // прескача точно тях.
            i += dc.consumed - 1;
          } else {
            // Кой е следващият блок и ще носи ли той буквица — от това
            // зависи дали може да бъде "залепен" за заглавието над него.
            // Абзацът с буквицата се рендва ЦЯЛ от собствения си код и
            // затова НЕ бива да се групира (иначе първите му редове
            // излизаха два пъти).
            final next = i + 1 < blocks.length ? blocks[i + 1] : null;
            final nextTakesDropCap = withDropCap &&
                !dropCapUsed &&
                next != null &&
                _eligibleForDropCap(next);
            final canKeepWithNext = next != null &&
                !next.isHeading &&
                !next.isItalic &&
                !nextTakesDropCap &&
                !next.inner.contains('<');

            if (b.isHeading) {
              // Заглавието на самото четиво (<h1> в HTML-а) трябва да
              // изглежда като нашето: Tamburin, центрирано, едро. Първото
              // е главното; следващите (напр. в молитвите) са по-дребни.
              final isMain = !mainHeadingUsed;
              mainHeadingUsed = true;
              // Главното заглавие в службата идва от самия текст (<h3>), а
              // при тропарите е нашето. За да изглеждат еднакво, тук му
              // даваме същия по-голям отстъп до текста.
              if (isMain && prayerLike) mainHeadingGap = 56;
              final headingWidget = pw.Center(
                child: pw.Text(
                  b.text,
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(
                      font: _title,
                      fontSize: isMain ? 34 : _bodySize + 6,
                      color: _ink),
                ),
              );
              // Заглавието не бива да остава само в дъното на страницата —
              // групира се (Inseparable) с първите два реда след себе си.
              if (canKeepWithNext) {
                final split = _splitLines(next.text, contentWidth,
                    _body!.getFont(context), _bodySize, 2);
                pendingRest = split.rest;
                widgets.add(pw.Inseparable(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                    children: [
                      headingWidget,
                      pw.SizedBox(height: mainHeadingGap ?? (prayerLike ? 34 : 24)),
                      // Целият абзац с maxLines: 2 — виж бележката при
                      // абзаците долу защо не подаваме само двата реда.
                      pw.RichText(
                          textAlign: pw.TextAlign.justify,
                          maxLines: 2,
                          text: pw.TextSpan(
                              text: next.text,
                              style: pw.TextStyle(
                                font: _body,
                                fontSize: _bodySize,
                                lineSpacing: _lineSpacing(
                                    _body!.getFont(context), _bodySize),
                                color: _ink,
                              ))),
                    ],
                  ),
                ));
              } else {
                widgets.add(headingWidget);
              }
            } else {
              // Стиловете следват четеца (виж _htmlStyles там):
              //   .prayerhead — получер, винен, малко по-едър
              //   .csl        — църковнославянският текст, +0.5
              //   .trans      — преводът: курсив, приглушен, −1
              //   .source     — източникът: курсив, приглушен, дребен
              final isPrayerHead = b.cls.contains('prayerhead');
              final isCsl = b.cls.contains('csl');
              final isTrans = b.cls.contains('trans');
              final isSourceLine = b.cls.contains('source');
              //   .memorydate — редът с паметта („Памет на 9 август"):
              //     курсив, приглушен, центриран, −1. Той е указание кога
              //     се чете житието, не част от разказа — виж стила му в
              //     reader_styles.dart, който тук се повтаря едно към едно.
              final isMemoryDate = b.cls.contains('memorydate');
              // Изнесен в променлива, защото междуредието се смята СПРЯМО
              // него — иначе преводът (с по-дребен шрифт) и славянският
              // текст (с по-едър) щяха да получат реда на основния размер.
              final blockFontSize = isPrayerHead
                  ? _bodySize + 1
                  : isCsl
                      ? _bodySize + 0.5
                      : (isTrans || isMemoryDate)
                          ? _bodySize - 1
                          : isSourceLine
                              ? _bodySize - 3
                              : _bodySize;
              final style = pw.TextStyle(
                font: isPrayerHead
                    ? _bodyBold
                    : ((b.isItalic || isMemoryDate) ? _bodyItalic : _body),
                fontNormal: isPrayerHead
                    ? _bodyBold
                    : ((b.isItalic || isMemoryDate) ? _bodyItalic : _body),
                fontBold: _bodyBold,
                fontWeight:
                    isPrayerHead ? pw.FontWeight.bold : pw.FontWeight.normal,
                fontSize: blockFontSize,
                lineSpacing:
                    _lineSpacing(_body!.getFont(context), blockFontSize),
                // Източникът остава курсивен, но в мастилено: сивото се
                // губеше до синьото на самия адрес до него.
                color: isPrayerHead
                    ? _wine
                    : ((b.isItalic && !isSourceLine) || isMemoryDate
                        ? _dim
                        : _ink),
              );
              // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
              // 🔥 НОВ КОД ЗА MEMORYDATE: центриран с pw.Center + pw.Text
              // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
              if (isMemoryDate) {
                // Центриран текст - без RichText
                widgets.add(pw.Center(
                  child: pw.Text(
                    blockText,
                    style: style,
                    textAlign: pw.TextAlign.center,
                  ),
                ));
                // След memorydate добавяме стандартно отстояние
                widgets.add(pw.SizedBox(height: 20));
                continue;  // ← ПРОПУСКАМЕ ОСТАНАЛАТА ЛОГИКА за този блок
              }
              // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
              
              // Отстъп на ПЪРВИЯ ред (като tab). pdf пакетът няма
              // "text-indent", затова слагаме невидима кутия като първи
              // inline елемент — тя засяга само първия ред, не пренесените.
              // Абзацът с буквицата и източникът се пропускат, както и
              // остатъкът от абзац, започнат при заглавието си отгоре —
              // той е продължение, а не ново начало.
              
              final isContinuation = blockText != b.text;
              final indent = (!dropCapUsed ||
                      isContinuation ||
                      b.isItalic ||
                      isPrayerHead ||
                      isCsl ||
                      isTrans ||
                      isMemoryDate)
                  ? null
                  : pw.WidgetSpan(child: pw.SizedBox(width: _bodySize * 1.6));
              final bodySpans = _inlineSpans(
                  blockText != b.text
                      ? blockText
                      : (b.inner.isEmpty ? b.text : b.inner),
                  style,
                  strongColor: strongIsWine ? _wine : _ink,
                  baseBold: isPrayerHead,
                  // ⚠ И memorydate: без него _inlineSpans строи спановете
                  // с прав шрифт и презаписва курсива, зададен в `style`
                  // по-горе — стилът на блока се губи мълчаливо.
                  baseItalic: b.isItalic || isMemoryDate);
              final paragraph = pw.RichText(
                // Редът с паметта е ЦЕНТРИРАН, както в четеца; разлятото
                // подравняване е за същинския текст.
                
                textAlign:
                    isMemoryDate ? pw.TextAlign.center : pw.TextAlign.justify,
                // Без това дългите абзаци не могат да се разделят на страници.
                
                overflow: pw.TextOverflow.span,
                text: pw.TextSpan(
                  style: style,
                  children: [
                    if (indent != null) indent,
                    ...bodySpans,
                  ],
                ),
              );

              final fontSize = style.fontSize ?? _bodySize;
              if (isPrayerHead && canKeepWithNext) {
                // "Тропар"/"Кондак" не са <h1>, а абзаци с клас prayerhead —
                // но също не бива да остават сами най-долу на страницата.
                final split = _splitLines(next.text, contentWidth,
                    _body!.getFont(context), _bodySize + 0.5, 2);
                pendingRest = split.rest;
                widgets.add(pw.Inseparable(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                    children: [
                      paragraph,
                      pw.SizedBox(height: 12),
                      pw.RichText(
                          textAlign: pw.TextAlign.justify,
                          maxLines: 2,
                          text: pw.TextSpan(
                              text: next.text,
                              style: pw.TextStyle(
                                font: _body,
                                fontSize: _bodySize + 0.5,
                                lineSpacing: _lineSpacing(
                                    _body!.getFont(context), _bodySize + 0.5),
                                color: _ink,
                              ))),
                    ],
                  ),
                ));
              } else if (_onlyLinkTags(b.inner) &&
                  !isSourceLine &&
                  blockText.isNotEmpty) {
                // Самотен пръв ред в дъното на страницата не е добър вид:
                // първите ДВА реда на абзаца се държат заедно (Inseparable),
                // а остатъкът тече свободно и може да се пренася.
                //
                // Мери се СГЛОБЕНИЯТ от парчетата текст, не b.text: така
                // отрязването и изписването броят едни и същи знаци.
                // Връзките не сменят шрифта (само цвета), затова мярката с
                // _body важи и за тях; абзаци с курсив или получер текст
                // остават извън правилото — там сметката би се разминала.
                final plain = bodySpans
                    .whereType<pw.TextSpan>()
                    .map((x) => x.text ?? '')
                    .join();
                final split = _splitLines(
                    plain, contentWidth, _body!.getFont(context), fontSize, 2,
                    firstIndent: indent != null ? _bodySize * 1.6 : 0);
                if (split.rest.isEmpty) {
                  // Абзац до два реда — няма какво да се дели, но пък може
                  // да се разполови на границата на страницата и пак да
                  // остави самотен ред. Затова цял отива на следващата.
                  widgets.add(pw.Inseparable(child: paragraph));
                } else {
                  // Подава се ЦЕЛИЯТ абзац с maxLines: 2, а не отрязаните
                  // два реда. Причината е в pdf пакета: последният ред на
                  // текст НЕ се разпъва между полетата (така се пише всеки
                  // край на абзац). Ако тук подадем само двата реда, вторият
                  // им е "последен" и остава скъсен — а това си личеше на
                  // всеки абзац в документа. При maxLines изходът от
                  // подредбата става веднага след добавения ред, който вече
                  // е записан като разпънат.
                  widgets.add(pw.Inseparable(
                    child: pw.RichText(
                      textAlign: pw.TextAlign.justify,
                      maxLines: 2,
                      text: pw.TextSpan(style: style, children: [
                        if (indent != null) indent,
                        ...bodySpans,
                      ]),
                    ),
                  ));
                  widgets.add(pw.SizedBox(height: fontSize * 0.45));
                  widgets.add(pw.RichText(
                      textAlign: pw.TextAlign.justify,
                      overflow: pw.TextOverflow.span,
                      text: pw.TextSpan(
                        style: style,
                        children: _spansAfter(bodySpans, split.head.length),
                      )));
                }
              } else {
                widgets.add(paragraph);
              }
            }
          }
          // Източникът стои по-встрани от текста — той е бележка, не част
          // от повествованието.
          final isSource = b.cls.contains('source');
          // След източника НЕ добавяме нищо — нито отстъп, нито следващи
          // блокове. Празният отстъп накрая понякога не се побираше на
          // страницата и отваряше цял празен лист в края на документа.
          if (isSource) break;
          widgets.add(pw.SizedBox(
              height: b.isHeading
                  ? (mainHeadingGap ?? (prayerLike ? 34 : 24))
                  : b.cls.contains('prayerhead')
                      ? 12 // заглавен ред → текста под него
                      : 20));
        }
        // Бележките — СЛЕД целия текст, като списък.
        //
        // ⚠ Не „под линия" на всяка страница, и то по причина, не по
        // мързел: MultiPage сам разпределя съдържанието и не се знае
        // предварително кой абзац на коя страница пада. За истински
        // footnotes трябва двупроходно строене — строиш, гледаш къде са
        // паднали, строиш пак, — което е крехко. Тук са в края, както е
        // обичайно за такива издания (медиана 4 бележки на житие).
        final notes = _collectNotes(bodyHtml);
        // ВРЕМЕННО за диагностика — да се махне.
        // ignore: avoid_print
        final supAt = bodyHtml.indexOf('<sup');
        print('ДИАГНОСТИКА notes.length=${notes.length} supAt=$supAt');
        if (supAt >= 0) {
          final a = (supAt - 120).clamp(0, bodyHtml.length);
          final b = (supAt + 60).clamp(0, bodyHtml.length);
          print('ДИАГНОСТИКА около <sup>: ${bodyHtml.substring(a, b)}');
        }
        if (notes.isNotEmpty) {
          widgets.add(pw.SizedBox(height: 26));
          widgets.add(pw.Container(
            width: contentWidth * 0.34,
            height: 0.7,
            color: _dim,
          ));
          widgets.add(pw.SizedBox(height: 14));
          const noteSize = _bodySize - 5;
          for (final n in notes) {
            widgets.add(pw.Anchor(
              // Целта, към която сочи номерът горе в текста.
              name: _noteAnchor(n.number),
              child: pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 7),
              child: pw.RichText(
                textAlign: pw.TextAlign.left,
                overflow: pw.TextOverflow.span,
                text: pw.TextSpan(children: [
                  pw.TextSpan(
                    text: '${n.number}  ',
                    // Обратният път: от бележката към мястото, откъдето е
                    // повикана. Така четенето не се губи — човек скача
                    // долу, прочита и се връща с едно натискане.
                    annotation: pw.AnnotationLink(_refAnchor(n.number)),
                    style: pw.TextStyle(
                      font: _body,
                      fontSize: noteSize,
                      color: _linkBlue,
                      lineSpacing:
                          _lineSpacing(_body!.getFont(context), noteSize),
                    ),
                  ),
                  pw.TextSpan(
                    text: n.text,
                    style: pw.TextStyle(
                      // Курсив — бележката е друг глас, не продължение на
                      // разказа. Номерът пред нея остава ПРАВ: той е
                      // указател, а не текст за четене.
                      font: _bodyItalic,
                      fontNormal: _bodyItalic,
                      fontSize: noteSize,
                      fontStyle: pw.FontStyle.italic,
                      color: _dim,
                      lineSpacing:
                          _lineSpacing(_body!.getFont(context), noteSize),
                    ),
                  ),
                ]),
              ),
              ),
            ));
          }
        }
        // Източникът НЕ се добавя тук: _buildHtmlFor вече го е сложил в
        // самия HTML (иначе излизаше два пъти).
        return widgets;
      },
    ),
  );

  final bytes = await doc.save();
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // БЪГФИКС #1: ИЗПОЛЗВАНЕ НА НОВОТО ИМЕ НА ФАЙЛА
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // Вместо подадения `fileName` (който идва отвън и съдържа
  // само подзаглавието), използваме `pdfFileName`, който
  // включва и двете заглавия.
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  await Printing.sharePdf(bytes: bytes, filename: pdfFileName);
}

/// Същото като [sharePdf], но с готова обработка на неуспеха.
///
/// ⚠ Изнесено, защото беше преписано в двата четеца — а всяко преписване
/// рано или късно се разминава. Тук стои единственото място, което решава
/// какво вижда човек, ако PDF-ът не се получи.
///
/// Връща `true` при успех. Не хвърля: тръгне ли нещо на зле, показва
/// съобщение и връща `false` — извикващият няма какво повече да направи.
Future<bool> shareReaderPdf(
  BuildContext context, {
  required String title,
  required String bodyHtml,
  required String fileName,
  bool withDropCap = true,
  bool strongIsWine = false,
  bool prayerLike = false,
}) async {
  // Взима се ПРЕДИ await-а: след него екранът може вече да е напуснат и
  // `context` да не е годен за търсене на ScaffoldMessenger.
  final messenger = ScaffoldMessenger.of(context);
  try {
    await sharePdf(
      title: title,
      bodyHtml: bodyHtml,
      fileName: fileName,
      withDropCap: withDropCap,
      strongIsWine: strongIsWine,
      prayerLike: prayerLike,
    );
    return true;
  } catch (e) {
    messenger.showSnackBar(
      SnackBar(content: Text('Неуспешно създаване на PDF: $e')),
    );
    return false;
  }
}