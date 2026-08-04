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
// ползваните знаци (виж TtfWriter.withChars), затова Cambria не надува
// файла и основният текст е със същия шрифт като в четеца.

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

// Кеш на шрифтовете — зареждат се веднъж за целия живот на приложението.
pw.Font? _body, _bodyItalic, _bodyBold, _title, _dropCapFont;

Future<void> _ensureFonts() async {
  if (_body != null) return;
  _body = pw.Font.ttf(await rootBundle.load('assets/fonts/cambria.ttf'));
  _bodyItalic = pw.Font.ttf(await rootBundle.load('assets/fonts/cambriai.ttf'));
  _bodyBold = pw.Font.ttf(await rootBundle.load('assets/fonts/cambriab.ttf'));
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
    blocks.add(_Block(
      text,
      isHeading: tag != 'p',
      isItalic: attrs.contains('italic-center') ||
          attrs.contains('trans') ||
          attrs.contains('source'),
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
/// Удебеляването е с ИСТИНСКИ получер шрифт (cambriab.ttf). Опитът да се
/// симулира с PdfTextRenderingMode.fillAndStroke се провали: pdf пакетът
/// изписва режима, но никога не го връща обратно (graphics.dart:538 —
/// пише само когато режимът е различен от "запълване"), затова
/// удебеляването изтичаше върху целия текст след него.
List<pw.TextSpan> _inlineSpans(
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
  final spans = <pw.TextSpan>[];
  // strong = истинско <strong>/<b> (носи и цвят), label = етикетът
  // "Превод:" (получер и ПРАВ, но с цвета на абзаца, не на <strong>).
  var strong = 0;
  var label = 0;
  var italic = 0;
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
    spans.add(pw.TextSpan(
      text: text,
      // Само това парче става кликаемо — не целият абзац.
      annotation: link > 0 ? pw.AnnotationUrl(href) : null,
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

/// Вярно, ако единствените тагове в абзаца са връзки (<a>). Тогава
/// шрифтът е един и същ по цялата дължина и мярката на редовете излиза
/// точна — а без това правилото за самотните редове не може да се приложи
/// безопасно.
bool _onlyLinkTags(String inner) =>
    !RegExp(r'<(?!/?a\b)[^>]*>', caseSensitive: false).hasMatch(inner);

/// Същите парчета, но без първите [skip] знака — с непокътнати цветове и
/// връзки. Така остатъкът от абзаца не се сглобява наново от HTML-а.
List<pw.TextSpan> _spansAfter(List<pw.TextSpan> spans, int skip) {
  final out = <pw.TextSpan>[];
  var left = skip;
  for (final s in spans) {
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

/// Кой абзац заслужава буквица — същите правила като в четеца
/// (_splitDropCap): пропускат се редакторски бележки в скоби, цитати,
/// курсивни акценти и всичко, което не започва с истинска буква. Търси се
/// само в началото на текста, не насред него.
bool _eligibleForDropCap(_Block b) {
  if (b.isHeading || b.isItalic || b.startsItalic) return false;
  const skipChars = {'(', "'", '*', '/', '«', '"', '['};
  final first = b.text.isEmpty ? '' : b.text.substring(0, 1);
  if (first.isEmpty || skipChars.contains(first)) return false;
  return RegExp(r'[А-Яа-яA-Za-zЀ-ӿ]').hasMatch(first);
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
  final lineSpacing = _bodySize * 0.45;

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
      font: _body, fontSize: _bodySize, lineSpacing: lineSpacing, color: _ink);

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
    // Първата буква вече е нарисувана като буквица.
    if (isFirst) spans = _spansAfter(spans, 1);
    final plain = spans.map((x) => x.text ?? '').join();
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
      ..add(pw.SizedBox(height: lineSpacing))
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

  final letter = blocks[start].text;
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
          child: pw.Transform.translate(
            // Положителна стойност = НАГОРЕ (проверено емпирично:
            // отрицателната свали буквата върху следващия ред).
            offset: PdfPoint(0, capShift),
            child: pw.Text(letter.isEmpty ? '' : letter.substring(0, 1),
                style: pw.TextStyle(
                    font: _dropCapFont, fontSize: capFontSize, color: _wine)),
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
                                lineSpacing: _bodySize * 0.45,
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
              final style = pw.TextStyle(
                font: isPrayerHead
                    ? _bodyBold
                    : (b.isItalic ? _bodyItalic : _body),
                fontNormal: isPrayerHead
                    ? _bodyBold
                    : (b.isItalic ? _bodyItalic : _body),
                fontBold: _bodyBold,
                fontWeight:
                    isPrayerHead ? pw.FontWeight.bold : pw.FontWeight.normal,
                fontSize: isPrayerHead
                    ? _bodySize + 1
                    : isCsl
                        ? _bodySize + 0.5
                        : isTrans
                            ? _bodySize - 1
                            : isSourceLine
                                ? _bodySize - 3
                                : _bodySize,
                lineSpacing: _bodySize * 0.45,
                // Източникът остава курсивен, но в мастилено: сивото се
                // губеше до синьото на самия адрес до него.
                color: isPrayerHead
                    ? _wine
                    : (b.isItalic && !isSourceLine ? _dim : _ink),
              );
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
                      isTrans)
                  ? null
                  : pw.WidgetSpan(child: pw.SizedBox(width: _bodySize * 1.6));
              final bodySpans = _inlineSpans(
                  blockText != b.text
                      ? blockText
                      : (b.inner.isEmpty ? b.text : b.inner),
                  style,
                  strongColor: strongIsWine ? _wine : _ink,
                  baseBold: isPrayerHead,
                  baseItalic: b.isItalic);
              final paragraph = pw.RichText(
                textAlign: pw.TextAlign.justify,
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
                                lineSpacing: _bodySize * 0.45,
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
                final plain = bodySpans.map((x) => x.text ?? '').join();
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
        // Източникът НЕ се добавя тук: _buildHtmlFor вече го е сложил в
        // самия HTML (иначе излизаше два пъти).
        return widgets;
      },
    ),
  );

  final bytes = await doc.save();
  await Printing.sharePdf(bytes: bytes, filename: fileName);
}
