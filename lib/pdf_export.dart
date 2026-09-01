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

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'drop_cap.dart'
    show dropCapOffsetX, DropCapWidthGroup, dropCapWidthGroupOf;
import 'drop_cap_scale.dart'
    show ReaderDropCapScale, DropCapScaleMetrics, DropCapScale;
import 'external_link.dart' show decodeHref;

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
///
/// ⚠ decodeHref() ЗАДЪЛЖИТЕЛНО — същата поправка като в четците
/// (external_link.dart): библейските препратки идват с `&amp;` (правилно
/// за XHTML атрибут), а PDF-ът пуска href-а директно в AnnotationUrl, без
/// browser/XML разбор по средата да го разкодира вместо нас. Останал
/// недекодиран, azbyka.ru вижда параметър `amp;bg~utfcs` вместо
/// `bg~utfcs` и препратката се отваря само на църковнославянски —
/// открито от потребителя 24.08.2026.
String _absoluteHref(String href) => decodeHref(href.startsWith('saint://')
    ? 'https://azbyka.ru/days/${href.substring('saint://'.length)}'
    : href);

const double _bodySize = 20.0;
const double _lineHeight = 1.45;

/// Корекции за буквицата, САМО в PDF-а — не в четците (там пропорциите са
/// наред). Причината е междуредието: тук `lineSpacing` е по-голямо, тъй че
/// грубото „redове × lineHeightPt" пресмятане на мястото за буквицата
/// (виж _dropCapWidgets) дава друга пропорция бяло петно, отколкото на
/// екрана, и разликата расте различно на всеки от трите размера.
///
/// Стойностите се определят ЕКСПЕРИМЕНТАЛНО (hot reload + преглед на
/// PDF-а), не по формула — виж CLAUDE.md.
///
/// Трите оси, всяка множител върху съществуващата формула:
///   - [_kPdfCapWidthFactor] — ЕДИН, общ за трите размера: коригира
///     широчината на бялото петно (capWidth), а с нея расте и самата
///     буква (capFontSize зависи от capWidth надолу по веригата — виж
///     употребата). Нарочно по-голям от 1.0 отгоре на самата корекция:
///     форматът А4 е по-широк от екрана, тъй че буквицата в PDF-а трябва
///     да излиза малко по-едра и там, където пропорцията вече е вярна.
///   - [_kPdfCapSizeFactor] — по ТРИ отделни, защото самият размер на
///     буквата спрямо петното не се разминава еднакво при малка/средна/
///     голяма.
///   - [_kPdfCapYShiftFactor] — по ТРИ отделни, върху `capShift`
///     (изместването на самия глиф нагоре) — колкото по-едра е буквата,
///     толкова по-различно пада спрямо горния ръб на реда.
const double _kPdfCapWidthFactor = 1.0;

const Map<DropCapScale, double> _kPdfCapSizeFactor = {
  DropCapScale.small:  1.2,
  DropCapScale.medium: 1.2,
  DropCapScale.large:  1.2,  //Size Up
};

const Map<DropCapScale, double> _kPdfCapYShiftFactor = {
  DropCapScale.small:  1.3,
  DropCapScale.medium: 2.0,
  DropCapScale.large:  3.0,  //Move Up
};

/// Множител върху ШИРИНАТА на бялото петно по ГРУПА (тясна/средна/широка
/// буква — виж DropCapWidthGroup в drop_cap.dart, споделената
/// класификация по реална ширина на глифа). ОТДЕЛЕН комплект от този на
/// четците (kDropCapWidthFactor там) — потвърдено от потребителя
/// 24.08.2026, че пропорциите тук се разминават достатъчно от екрана, за
/// да не свърши работа един общ комплект и на двете места. „Нормална" пак
/// е 1.0 — възпроизвежда сегашната ширина за тази група.
const Map<DropCapWidthGroup, double> _kPdfCapWidthGroupFactor = {
  DropCapWidthGroup.narrow: 0.6,
  DropCapWidthGroup.normal: 0.7,
  DropCapWidthGroup.wide: 1.0,
};

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

  /// Пътят до илюстрацията — САМО когато блокът е `<img>`. За всички
  /// останали е null и блокът е текстов.
  final String? imageAsset;

  /// Съотношението ширина/височина, взето от атрибутите на тага.
  ///
  /// ⚠ От АТРИБУТИТЕ, не от файла: мястото се смята преди изображението да
  /// е декодирано — същата причина, както в [LivesImageExtension].
  final double imageAspect;

  bool get isImage => imageAsset != null;
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
      this.inner = '',
      this.imageAsset,
      this.imageAspect = 0});
}

/// Премахва интервалите около таговете за бележки (<a> и <sup>),
/// за да няма разстояние между думата и номера на бележката.
/// 
/// Това е ключовата поправка за залепването на номерата на бележките
/// към предходната дума. Без нея интервалът от HTML-а остава и
/// номерът се отделя от думата, което води до пренасяне на номера
/// на нов ред при textAlign.justify.
String _cleanNoteSpacing(String html) {
  var cleaned = html;
  cleaned = cleaned.replaceAll(RegExp(r'\s+<sup'), '<sup');
  cleaned = cleaned.replaceAll(RegExp(r'</sup>\s+'), '</sup>');
  // ⚠ САМО ОКОЛО БЕЛЕЖКИТЕ, а не около всяка връзка.
  //
  // Дотук тук стоеше `\s+<a\b` → `<a`, което махаше интервала пред ВСЯКА
  // връзка. В житията те са 2773 и всяка слепваше предната дума за себе си:
  // „Кирил и <a>Методий</a>" излизаше „Кирил иМетодий". Личеше и в името на
  // файла, което се строи от същия текст (открито 31.08.2026).
  //
  // Бележката се разпознава по горния индекс вътре в самата връзка —
  // `<a href="…noteN…"><sup>N</sup></a>`; само там номерът трябва да е
  // долепен до думата, както в печатните книги.
  cleaned = cleaned.replaceAllMapped(
    RegExp(r'\s+(<a\b[^>]*>)(\s*<sup)', caseSensitive: false),
    (m) => '${m[1]}${m[2]}',
  );
  cleaned = cleaned.replaceAllMapped(
    RegExp(r'(</sup>\s*</a>)\s+', caseSensitive: false),
    (m) => m[1]!,
  );
  return cleaned;
}

/// Разделя HTML-а на абзаци/заглавия и маха таговете. Оформлението тук е
/// нарочно просто — PDF-ът е за четене и печат, не за пресъздаване на
/// всяка подробност от екрана.
List<_Block> _parseBlocks(String html) {
  final blocks = <_Block>[];
  // ⚠ И `<img>` — самозатварящ се таг, тъй че влиза в СЪЩИЯ израз като
  // отделно разклонение, а не като втори обход: редът на блоковете има
  // значение (надписът трябва да остане веднага след картинката си).
  final re = RegExp(
      r'<img\b([^>]*)>|<(p|h[1-6])\b([^>]*)>(.*?)</\2>',
      dotAll: true,
      caseSensitive: false);
  final srcRe = RegExp(r'src="([^"]+)"', caseSensitive: false);
  final wRe = RegExp(r'width="(\d+)"', caseSensitive: false);
  final hRe = RegExp(r'height="(\d+)"', caseSensitive: false);
  for (final m in re.allMatches(html)) {
    if (m.group(1) != null) {
      final tag = m.group(0)!;
      final src = srcRe.firstMatch(tag)?.group(1);
      // Чужд адрес (мрежов, остатък от източника) не се рисува — PDF-ът се
      // прави офлайн, както и четецът.
      if (src == null || !src.startsWith('assets/')) continue;
      final w = double.tryParse(wRe.firstMatch(tag)?.group(1) ?? '') ?? 0;
      final h = double.tryParse(hRe.firstMatch(tag)?.group(1) ?? '') ?? 0;
      blocks.add(_Block('',
          imageAsset: src, imageAspect: (w > 0 && h > 0) ? w / h : 0));
      continue;
    }
    final tag = m.group(2)!.toLowerCase();
    final attrs = m.group(3) ?? '';
    final inner = m.group(4)!;
    // Почистваме интервалите около таговете за бележки още преди парсването
    final cleanedInner = _cleanNoteSpacing(inner);
    final text = _decodeEntities(cleanedInner.replaceAll(RegExp(r'<[^>]+>'), ''))
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
      inner: cleanedInner, // <- използваме почистения inner
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

/// Текстът на един span — включително скрития във WidgetSpan.
///
/// ⚠ Дума+номер на бележка живеят във WidgetSpan (виж _inlineSpans), тъй
/// че `whereType<TextSpan>()` ги пропуска. Мерките за редове и за
/// разрязване трябва да ги броят, инак излизат по-къси от истинското.
/// Котвите нямат текст и добавят празен низ.
String _spanPlainText(pw.InlineSpan s) {
  if (s is pw.TextSpan) {
    final own = s.text ?? '';
    final kids = (s.children ?? const <pw.InlineSpan>[]).map(_spanPlainText);
    return own + kids.join();
  }
  if (s is pw.WidgetSpan) {
    final child = s.child;
    if (child is pw.RichText) return _spanPlainText(child.text);
  }
  return '';
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

// ═══════════════════════════════════════════════════════════════════
// МЕНИДЖЪР НА СТРАНИЦИТЕ — къде да падне всяка илюстрация
// ═══════════════════════════════════════════════════════════════════
//
// Задачата е една: страниците да се запълват, без картинка да се реже и без
// да се откъсва от надписа си.
//
// ⚠ КЛЮЧОВОТО НАБЛЮДЕНИЕ, от което следва целият алгоритъм: текстът се
// РАЗЦЕПВА между страници (`pw.TextOverflow.span`), тъй че сам по себе си не
// оставя празнина — той тече, докато свърши листът. Празнина се появява
// САМО когато неразделим блок не се побере в остатъка, а такива са тъкмо
// илюстрациите (картинка + надпис в един `Inseparable`).
//
// Затова не се налага да се пренарежда всичко — достатъчно е за всяка
// картинка да се избере МЯСТОТО, на което тя пада най-добре. Илюстрацията се
// мести с няколко абзаца напред или назад; редът на самия текст остава
// непокътнат.
//
// ⚠ Че картинката ще застане малко по-рано или по-късно от мястото си в
// източника, е приемливо — тя пътува заедно с надписа си и не се позовава на
// съседния абзац. Решение на потребителя (31.08.2026), с довода, че печалбата
// в оформлението е далеч по-голяма от загубата на точното място.

/// Безопасно име на файл от заглавието на четивото.
///
/// ⚠ ЛИМИТЪТ Е В БАЙТОВЕ, НЕ В ЗНАЦИ — и точно това го пропусна досегашният
/// код. Файловите системи на Android спират на 255 БАЙТА, а кирилицата е по
/// два байта на знак: 174-знаково име излиза 306 байта. Тогава записът гърми
/// с `ENAMETOOLONG`, споделянето се проваля и отвън изглежда, че копчето
/// „Сподели като PDF" просто не прави нищо. Точно това се случваше на
/// житието на св. Кирил Философ, чието заглавие и подзаглавие заедно са
/// 174 знака (докладвано 31.08.2026).
///
/// Съкращава се стъпаловидно: първо отпада подзаглавието (то е по-малко
/// важно от името), после самото заглавие се реже ПО ДУМА.
String _safeFileName({
  required String main,
  required String sub,
  required String fallback,
  String prefix = '',
}) {
  // Знаци, забранени във файлови имена (Android/Windows/iOS).
  String clean(String s) => s
      .replaceAll(RegExp(r'[\\/:*?"<>|]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  int bytes(String s) => utf8.encode(s).length;

  // ⚠ Запасът под 255 е нарочен: приложението за споделяне често добавя
  // свой префикс или наставка към името, преди да го запише.
  const maxBytes = 150;
  var head = clean(main);
  final tail = clean(sub);
  if (head.isEmpty) head = clean(fallback);
  if (head.isEmpty) head = 'Житие';

  // ⚠ ДВЕТЕ ЧАСТИ СЕ ПАЗЯТ ПООТДЕЛНО, а не се търси разделителят в готовия
  // низ. Самото подзаглавие може да съдържа тире („…и на 14 февруари -
  // Успение на…") и рязането по първото срещнато оставяше половин
  // подзаглавие пред цялото име.
  // ⚠ Представката („Памет на 14.фев.") се смята за ЗАДЪЛЖИТЕЛНА: тя е
  // указателят, по който човек подрежда свалените файлове, тъй че мястото ѝ
  // се вади от бюджета, вместо да отпада при съкращаване.
  final pre = prefix.isEmpty ? '' : '${clean(prefix)} ';
  final budget = maxBytes - bytes(pre);
  if (tail.isNotEmpty && bytes('$tail - $head') <= budget) {
    return '$pre$tail - $head.pdf';
  }
  if (bytes(head) <= budget) return '$pre$head.pdf';

  // Още е дълго — режем по дума, за да не свърши името насред сричка.
  final out = StringBuffer();
  for (final w in head.split(' ')) {
    final candidate = out.isEmpty ? w : '$out $w';
    if (bytes(candidate) > budget) break;
    out
      ..clear()
      ..write(candidate);
  }
  var trimmed = out.toString().trim();
  if (trimmed.isEmpty) {
    // Една-единствена свръхдълга дума: режем по ЗНАЦИ, докато байтовете
    // паднат — така никога не остава половин буква.
    trimmed = head;
    while (bytes(trimmed) > budget && trimmed.isNotEmpty) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }
    trimmed = trimmed.trim();
  }
  return '$pre$trimmed.pdf';
}

/// Докъде може да пътува илюстрация — в БЛОКОВЕ, не в пиксели.
///
/// ⚠ Има таван по две причини. Далеч преместена картинка се откъсва от
/// онова, за което разказва текстът наоколо; а и всяко местене отвъд една
/// страница само пренася празнината другаде, вместо да я премахне.
const int _kImageShiftLimit = 5;

/// Запас, с който картинката трябва да се побере, за да я сметнем за побрала
/// се.
///
/// ⚠ Не е предпазливост „за всеки случай". Симулацията се разминава с
/// `MultiPage` с няколко пункта на страница (отстъпи, които на границата не
/// се пренасят, последен ред, който не влиза) и в граничен случай казва
/// „побира се", а листът я отхвърля — при което зее цяла половин страница.
/// Обратната грешка струва много по-малко: картинката минава по-нататък,
/// където и без това щеше да иде.
const double _kFitMargin = 28;

/// Диагностика на разпределението — вдига се само при търсене на бъг.
bool _pdfDebug = false;
set pdfDebug(bool v) => _pdfDebug = v;

/// Един елемент от документа заедно с онова, което мениджърът трябва да знае
/// за него.
class _Item {
  final pw.Widget widget;
  final bool isImage;
  final bool isHeading;

  /// Може ли `MultiPage` да го разреже между две страници.
  ///
  /// ⚠ РЕШАВАЩО за сметката. Разцепваем елемент не оставя празнина — той
  /// тече, докато свърши листът. Всеки друг или се побира в остатъка, или
  /// цял отива на новата страница и зад него зее празно. Ако тук всичко се
  /// смята за течащо, симулацията излиза с една страница по-малко и
  /// „колко е останало" става грешно още в началото.
  ///
  /// Разцепваеми са само абзаците, построени с `pw.TextOverflow.span`.
  final bool splittable;

  /// От кой БЛОК е дошъл — по него пренареждането връща реда на блоковете,
  /// а не на готовите widget-и (вторият проход ги строи наново).
  int blockIndex = -1;

  /// Височината му в пунктове — ИЗМЕРЕНА, не оценена (виж [_reorderBlocks]).
  double height = 0;

  _Item(this.widget,
      {this.isImage = false,
      this.isHeading = false,
      this.splittable = false});
}

/// Решава къде да падне всяка илюстрация и връща НОВ ред на БЛОКОВЕТЕ.
///
/// ⚠ ВИСОЧИНИТЕ СЕ МЕРЯТ, НЕ СЕ ОЦЕНЯВАТ. Първата версия ги смяташе по брой
/// редове × междуредие и излизаше със 7% по-малко — при дълго житие това е
/// седем страници разлика, тъй че „колко е останало на листа" ставаше
/// произволно число още към десетата страница. Тук всеки елемент минава през
/// `layout()` — същата примитива, с която мери и самият `MultiPage`.
///
/// ⚠ Текстът се РАЗЦЕПВА между страници (`pw.TextOverflow.span`) и затова сам
/// не оставя празнина: тече, докато свърши листът. Празно остава само когато
/// НЕРАЗДЕЛИМ елемент не се побере — а такива са илюстрациите (картинка +
/// надпис в един `Inseparable`) и заглавията. Оттам цялата задача се свежда
/// до едно: за всяка картинка да се избере мястото, на което пада най-добре.
///
/// Връща САМИЯ подаден списък, ако нищо не се е разместило — тогава вторият
/// проход на строенето отпада.
List<_Block> _reorderBlocks(
  List<_Block> blocks,
  List<_Item> items,
  pw.Context context,
  double contentWidth,
  double pageHeight,
) {
  if (pageHeight <= 0 || !items.any((it) => it.isImage)) return blocks;

  // ── 1. Измерване ──────────────────────────────────────────────────
  final constraints = pw.BoxConstraints(maxWidth: contentWidth);
  for (final it in items) {
    try {
      it.widget.layout(context, constraints);
      it.height = it.widget.box?.height ?? 0;
    } catch (_) {
      it.height = 0; // не се е оформил — не участва в сметките
    }
  }

  // ── 2. Свиване до ЕДИНИЦИ по блок ─────────────────────────────────
  // Няколко widget-а могат да идват от един блок (текст + отстъп след него),
  // а картинката носи надписа си със себе си.
  final n = blocks.length;
  final h = List<double>.filled(n, 0);
  final splittable = List<bool>.filled(n, false);
  final isImg = List<bool>.filled(n, false);
  final isHead = List<bool>.filled(n, false);
  for (final it in items) {
    final b = it.blockIndex;
    if (b < 0 || b >= n) continue;
    h[b] += it.height;
    if (it.splittable) splittable[b] = true;
    if (it.isImage) isImg[b] = true;
    if (it.isHeading) isHead[b] = true;
  }

  // Надписът пътува с картинката си — двата блока се сливат в един.
  final unit = <List<int>>[];
  for (var i = 0; i < n; i++) {
    if (isImg[i] && i + 1 < n && blocks[i + 1].cls.contains('caption')) {
      unit.add([i, i + 1]);
      i++;
    } else {
      unit.add([i]);
    }
  }
  final uh = [for (final u in unit) u.fold<double>(0, (a, i) => a + h[i])];
  // Височината на един ред в единицата — по кегела на блока ѝ.
  final uLine = [
    for (final u in unit)
      _blockFontSizeOf(blocks[u.first], _bodySize) * _targetLineEm
  ];
  final uImg = [for (final u in unit) isImg[u.first]];
  final uHead = [for (final u in unit) isHead[u.first]];
  final uSplit = [
    for (final u in unit) u.every((i) => splittable[i] || h[i] == 0)
  ];

  // ── 3. Симулация + местене ────────────────────────────────────────
  //
  // За всяка илюстрация се оценяват три възможности:
  //   остави я тук      новата страница започва с нея
  //   отложи я с k      k единици минават пред нея и допълват листа
  //   издърпай я с j    застава пред последните j и завършва листа
  //
  // ⚠ Двете посоки не са симетрични и двете трябват. Отлагането се проваля
  // към КРАЯ на четивото (изтикана след последния абзац, картинката остава
  // сама на последна страница); издърпването — в НАЧАЛОТО, където няма зад
  // какво да се скрие.
  final order = List<int>.generate(unit.length, (i) => i);
  final yBefore = List<double>.filled(unit.length, 0);
  // ⚠ Всяка илюстрация се мести НАЙ-МНОГО ВЕДНЪЖ: симулацията се пуска
  // наново от новото ѝ място и без този пазач може да я върне обратно.
  final moved = <int>{};
  var y = 0.0;
  var changed = false;

  // ⚠ Текстът тече ПО ЦЕЛИ РЕДОВЕ, не като течност.
  //
  // Останат ли на листа 15 пункта, а редът е 19, редът не влиза — тези 15
  // се губят. Първата версия ги смяташе за запълнени и излизаше с 8%
  // по-малко страници (при дълго житие — шест). Тук се брои колко ЦЕЛИ реда
  // се побират, и остатъкът отива на новия лист.
  double advance(double from, double dh, double lineH) {
    if (lineH <= 0) {
      var t = from + dh;
      while (t > pageHeight) {
        t -= pageHeight;
      }
      return t;
    }
    var lines = (dh / lineH).round();
    var y = from;
    while (lines > 0) {
      final fits = ((pageHeight - y) / lineH).floor();
      if (fits >= lines) return y + lines * lineH;
      lines -= fits > 0 ? fits : 0;
      y = 0; // нов лист
      if (fits <= 0 && y == 0) {
        // редът не се побира дори на празен лист — предпазва от цикъл
        if (lineH > pageHeight) return pageHeight;
      }
    }
    return y;
  }

  for (var pos = 0; pos < order.length; pos++) {
    yBefore[pos] = y;
    final u = order[pos];
    final uHeight = uh[u];

    if (!uImg[u]) {
      if (uSplit[u]) {
        y = advance(y, uHeight, uLine[u]); // тече по цели редове
      } else if (uHeight <= pageHeight - y) {
        y += uHeight;
      } else {
        y = uHeight; // цял отива на нова страница
      }
      continue;
    }
    if (uHeight + _kFitMargin <= pageHeight - y) {
      y += uHeight;
      continue;
    }
    if (moved.contains(u)) {
      y = uHeight;
      continue;
    }

    var bestWaste = pageHeight - y;
    var bestShift = 0;

    var probe = y;
    for (var k = 1; k <= _kImageShiftLimit && pos + k < order.length; k++) {
      final nxt = order[pos + k];
      // ⚠ Друга картинка не се прескача — двете биха разменили реда си
      // спрямо разказа, а всяка носи свой надпис. Нито блокът с ИЗТОЧНИКА:
      // след него строенето спира и картинката просто би изчезнала.
      if (uImg[nxt] || blocks[unit[nxt].first].cls.contains('source')) break;
      probe = uSplit[nxt]
          ? advance(probe, uh[nxt], uLine[nxt])
          : (uh[nxt] <= pageHeight - probe ? probe + uh[nxt] : uh[nxt]);
      final waste = uHeight + _kFitMargin <= pageHeight - probe
          ? 0.0
          : pageHeight - probe;
      // ⚠ Отлагане до самия край НЕ Е печалба: картинката остава сама на
      // последна страница, каквото и да казва сметката.
      if (waste < bestWaste - 0.5 && pos + k < order.length - 1) {
        bestWaste = waste;
        bestShift = k;
      }
      if (waste == 0 && pos + k < order.length - 1) break;
    }

    for (var j = 1; j <= _kImageShiftLimit && pos - j >= 0; j++) {
      final prv = order[pos - j];
      // ⚠ Не се минава пред ЗАГЛАВИЕ: картинката би застанала преди реда,
      // който я въвежда.
      if (uImg[prv] || uHead[prv]) break;
      final yAt = yBefore[pos - j];
      final waste =
          uHeight + _kFitMargin <= pageHeight - yAt ? 0.0 : pageHeight - yAt;
      if (waste < bestWaste - 0.5) {
        bestWaste = waste;
        bestShift = -j;
      }
      if (waste == 0) break;
    }

    if (bestShift != 0) {
      moved.add(u);
      changed = true;
      order.removeAt(pos);
      order.insert(pos + bestShift, u);
      final restart = bestShift < 0 ? pos + bestShift : pos;
      y = yBefore[restart];
      pos = restart - 1;
      continue;
    }
    y = uHeight;
  }

  if (_pdfDebug) {
    var yy = 0.0, page = 1, gaps = 0;
    for (final i in order) {
      if (uSplit[i]) {
        final was = yy;
        yy = advance(yy, uh[i], uLine[i]);
        if (yy < was) page += 1 + ((was + uh[i] - yy) / pageHeight).floor();
      } else if (uh[i] > pageHeight - yy) {
        if (pageHeight - yy > 90) gaps++;
        page++;
        yy = uh[i];
      } else {
        yy += uh[i];
      }
    }
    // ignore: avoid_print
    print('  [сим] $page стр., празнини >90pt: $gaps, местени: ${moved.length}');
  }

  if (!changed) return blocks;
  return [for (final i in order) ...unit[i].map((b) => blocks[b])];
}

/// Мястото на илюстрацията в PDF-а: (ширина, височина) в пунктове.
///
/// ⚠ Височината е ОГРАНИЧЕНА, и то по-строго, отколкото на екрана. Там
/// таванът пази четенето от изображение, което заема целия екран; тук е и
/// въпрос на страница: висока картинка, тръгнала от средата, изтласква
/// целия текст под себе си и оставя половин лист празен.
const double _kPdfImageMaxHeightFactor = 0.52;

// ⚠ Таванът на разтягането е МАХНАТ и тук — по същото решение, с което
// отпадна и в четеца (01.09.2026): илюстрацията заема цялата ширина на
// колоната, каквато и да е тя в източника.

(double, double) _imageBox(double aspect, pw.MemoryImage img, double maxWidth) {
  final maxHeight =
      (PdfPageFormat.a4.height - 80) * _kPdfImageMaxHeightFactor;
  // ⚠ Съотношението от атрибутите е меродавно; към самото изображение се
  // пада само ако тагът не го е дал (в базата това не се среща, но чужд
  // текст утре може да го пропусне).
  final iw = (img.width ?? 0).toDouble();
  final ih = (img.height ?? 0).toDouble();
  final ratio = aspect > 0 ? aspect : (ih == 0 ? 1.0 : iw / ih);
  var w = maxWidth;
  var h = w / ratio;
  if (h > maxHeight) {
    h = maxHeight;
    w = h * ratio;
  }
  return (w, h);
}

/// Размерът на шрифта за един блок — ЕДНО място за таблицата.
///
/// ⚠ Изнесено, защото същите числа трябват и при ГРУПИРАНЕТО на абзац със
/// заглавието над него. Написани втори път там, те се разминаваха при
/// първата промяна — а разминаването се вижда като „остатъкът от абзаца
/// започва не оттам, откъдето свърши началото му".
double _blockFontSizeOf(_Block b, double bodySize) {
  if (b.cls.contains('prayerhead')) return bodySize + 1;
  if (b.cls.contains('csl')) return bodySize + 0.5;
  if (b.cls.contains('trans') ||
      b.cls.contains('memorydate') ||
      b.cls.contains('caption') ||
      b.cls.contains('centernote')) {
    return bodySize - 1;
  }
  if (b.cls.contains('source')) return bodySize - 3;
  return bodySize;
}

/// Стилът на един блок — огледален на четеца (виж readerStyles).
pw.TextStyle _blockStyleOf(_Block b, PdfFont measureFont, double bodySize) {
  final isPrayerHead = b.cls.contains('prayerhead');
  final isSourceLine = b.cls.contains('source');
  // ⚠ Курсивните по КЛАС: редът с паметта, надписът под илюстрация и
  // сведението в скоби. В четеца и трите са курсив, приглушени и с една
  // степен по-дребни (виж reader_styles.dart) — тук се повтаря същото.
  final isDimItalic = b.cls.contains('memorydate') ||
      b.cls.contains('caption') ||
      b.cls.contains('centernote');
  final size = _blockFontSizeOf(b, bodySize);
  return pw.TextStyle(
    font: isPrayerHead
        ? _bodyBold
        : ((b.isItalic || isDimItalic) ? _bodyItalic : _body),
    fontNormal: isPrayerHead
        ? _bodyBold
        : ((b.isItalic || isDimItalic) ? _bodyItalic : _body),
    fontBold: _bodyBold,
    fontWeight: isPrayerHead ? pw.FontWeight.bold : pw.FontWeight.normal,
    fontSize: size,
    lineSpacing: _lineSpacing(measureFont, size),
    color: isPrayerHead
        ? _wine
        : ((b.isItalic && !isSourceLine) || isDimItalic ? _dim : _ink),
  );
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
  /// Шрифтът, чиито вертикални мерки движат поправката на изместването
  /// при слятата двойка дума+номер на бележка — виж бележката до
  /// `mergeBaseline` по-долу и `_lineSpacing()` за същия похват.
  required PdfFont font,
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

    // Думата ПРЕД номера на бележка не бива да се разделя от него — нито с
    // прекъсване на реда (само числото да остане на нов ред), нито с
    // разтягане при justify (сякаш са отделни "думи"). И двете идват от
    // ЕДНО и също: буквален интервал в изходния HTML точно преди <sup> —
    // в едни бележки го има ("Лука <sup>1</sup>"), в други не
    // ("Мануил<sup>2</sup>"), в зависимост как си е бил написан
    // изходникът. Пренасянето и justify в pdf пакета работят по обичайния
    // начин — режат/разтягат само на интервали, не на границите между
    // span-овете сами по себе си. Без интервал между тях думата и номерът
    // стават ЕДНА непрекъсната последователност от непразни знаци —
    // недвижима и неразделима.
    // ⚠ Този интервал се маха ПРЕДИ сливането по-долу и е условие за
    // него: остане ли, „последната дума" пред номера излиза празна и
    // залепването се пропуска мълчаливо.
    if (isSup && spans.isNotEmpty && spans.last is pw.TextSpan) {
      final prev = spans.last as pw.TextSpan;
      final trimmed = (prev.text ?? '').replaceFirst(RegExp(r'\s+$'), '');
      if (trimmed != prev.text) {
        spans[spans.length - 1] = pw.TextSpan(
          text: trimmed,
          style: prev.style,
          annotation: prev.annotation,
        );
      }
    }

    // Истинско повдигане: НЕ местене на нормални цифри с baseline/
    // Transform (и двете опряха в тънки места на pdf пакета — baseline
    // мълчаливо не действаше в justify абзаци, а Transform.translate
    // буташе рисуването извън изрязващата рамка на WidgetSpan-а и
    // числото изчезваше). Вместо туй — истински Unicode superscript
    // знаци (¹ ² ³ …): те са малки и вдигнати по дизайн на шрифта,
    // изчертават се като обикновен текст, без нужда от каквато и да е
    // намеса в оразмеряването на реда.
    var renderText = text;
    if (isSup) renderText = _toSuperscriptDigits(renderText.trim());

    final spanStyle = base.copyWith(
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
      );
    final spanAnnotation = noteNum != null
        ? pw.AnnotationLink(_noteAnchor(noteNum))
        : (link > 0 ? pw.AnnotationUrl(href) : null);

    // ⚠ НОМЕРЪТ НА БЕЛЕЖКА СЕ ЗАЛЕПВА ЗА ДУМАТА ПРЕД СЕБЕ СИ.
    //
    // Причината е в самия pdf пакет: layout-ът обхожда спановете един по
    // един и реже по интервали ВЪТРЕ във всеки (`_layout` в
    // widgets/text.dart). Тоест ГРАНИЦАТА МЕЖДУ ДВА TextSpan-А Е САМА ПО
    // СЕБЕ СИ ГРАНИЦА МЕЖДУ ДУМИ — съседни спанове никога не се съшиват.
    // Затова „Ликия" и „²⁰" в два спана са две отделни думи: justify ги
    // разтяга, пренасянето ги разделя, и махането на интервала помежду им
    // НЕ помага.
    //
    // WidgetSpan обаче се мери НАВЕДНЪЖ и не се дели — затова двете
    // влизат в него, с вложен RichText, който пази двата различни цвята.
    if (noteNum != null && spans.isNotEmpty && spans.last is pw.TextSpan) {
      final prev = spans.last as pw.TextSpan;
      final prevText = prev.text ?? '';
      // Само ПОСЛЕДНАТА дума се откъсва — останалото си остава обикновен
      // текст, който се пренася и подравнява свободно.
      final cut = prevText.lastIndexOf(' ');
      final head = cut < 0 ? '' : prevText.substring(0, cut + 1);
      final word = cut < 0 ? prevText : prevText.substring(cut + 1);
      if (word.isNotEmpty) {
        spans.removeLast();
        if (head.isNotEmpty) {
          spans.add(pw.TextSpan(
              text: head, style: prev.style, annotation: prev.annotation));
        }
        spans.add(pw.WidgetSpan(
          annotation: spanAnnotation,
          // ⚠⚠ СТИЛЪТ Е ТОЗИ НА НОМЕРА (синия), а НЕ на думата — и това
          // НЕ е дреболия.
          //
          // `_RichTextState.paint` помни последния зададен цвят и
          // ПРОПУСКА `setFillColor`, когато новият съвпада с него.
          // Вложеният тук RichText рисува зад гърба на този отчет: щом
          // вътре смени цвета на синьо за номера, външният цикъл
          // продължава да смята, че текущият е черен — и следващият
          // (черен) TextSpan не задава нищо, тъй че НАСЛЕДЯВА синьото.
          // Така синьото изтичаше върху целия текст до следващата
          // бележка.
          //
          // Като обявим тук цвета, с който вложеното РЕАЛНО завършва,
          // отчетът на пакета съвпада с PDF потока и следващият span си
          // задава своя цвят както трябва.
          style: spanStyle,
          // ⚠⚠ ЦЯЛАТА ДУМА+НОМЕР ИЗПЛУВАШЕ НАД РЕДА — трети капан в pdf
          // пакета, отделен от предишните два.
          //
          // Стойността по-долу НЕ е изведена от кода на пакета — двата
          // опита с чиста теория (пълният обхват на шрифта, после
          // "истинските" per-glyph метрики на думата+числото) уцелиха
          // погрешно, единия път думата увисна над реда, другия — под
          // него. Намерена е ЕКСПЕРИМЕНТАЛНО: самостоятелен Dart скрипт
          // (без Flutter/adb — само `package:pdf`) построи един и същ
          // ред с WidgetSpan при десетки различни `baseline`, записа
          // резултата в PDF и той се прегледа директно. `font.descent`
          // (без ascent) уцели точно централата на широка "плоска зона"
          // (0.24–0.32 × естествения ред на шрифта се четат еднакво
          // добре) — тоест не е ръб на бръснач, а стабилна стойност.
          //
          // ⚠ `font.stringMetrics(word)` тук НЕ дава истински per-glyph
          // ascent/descent — пада на fallback по ЦЕЛИЯ шрифт (проверено:
          // за "Ликия" и "²⁰" излизат буквално еднакви числа с
          // `font.ascent`/`font.descent`). Затова формулата е константа
          // на шрифта, не мярка на конкретния текст — но пак се смята от
          // самия шрифт (`_lineSpacing()` също прави точно това), тъй че
          // смяна на шрифт пак не иска промяна тук.
          baseline: font.descent * (base.fontSize ?? _bodySize),
          child: pw.RichText(
            softWrap: false,
            text: pw.TextSpan(children: [
              pw.TextSpan(text: word, style: prev.style),
              pw.TextSpan(text: renderText, style: spanStyle),
            ]),
          ),
        ));
        // Котвата за обратния път — СЛЕД двойката, за да не дели нищо.
        spans.add(pw.WidgetSpan(
          child: pw.Anchor(name: _refAnchor(noteNum), child: pw.SizedBox()),
        ));
        continue;
      }
    }

    spans.add(pw.TextSpan(
      text: renderText,
      annotation: spanAnnotation,
      style: spanStyle,
    ));

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
      //
      // ⚠ КОТВАТА Е СЛЕД ЧИСЛОТО, НЕ ПРЕДИ: това е новото тук. Досега
      // седеше между думата и числото (дума → котва → число) — и въпреки
      // нулевата си ширина, изглежда pdf пакетът я третираше като валидна
      // точка за пренасяне на реда, също като истински интервал. Затова
      // числото понякога хвърчеше самò на нов ред. Като застава СЛЕД
      // числото, вече не разделя нищо: дума+число остават една непрекъсната
      // последователност без никакъв обект помежду им.
      spans.add(pw.WidgetSpan(
        child: pw.Anchor(name: _refAnchor(noteNum), child: pw.SizedBox()),
      ));
    }
  }
  return spans;
}

/// Превръща ASCII цифри в техните Unicode superscript форми (¹ ² ³ …).
/// Знаци извън 0–9 остават непипнати — по-добре да се изпише нормално,
/// отколкото да пропадне целият пасаж.
///
/// Charis SIL, като шрифт с научно/лингвистично предназначение, ги носи.
String _toSuperscriptDigits(String s) {
  const map = {
    '0': '\u2070', '1': '\u00B9', '2': '\u00B2', '3': '\u00B3',
    '4': '\u2074', '5': '\u2075', '6': '\u2076', '7': '\u2077',
    '8': '\u2078', '9': '\u2079',
  };
  final buf = StringBuffer();
  for (final ch in s.split('')) {
    buf.write(map[ch] ?? ch);
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
    caseSensitive: false,
    dotAll: true,
  );
  
  for (final m in re.allMatches(html)) {
    final title   = m.group(1) ?? m.group(3) ?? '';
    final numText = m.group(2) ?? m.group(4) ?? '';
    final num = _decodeEntities(numText.replaceAll(RegExp(r'<[^>]+>'), '').trim());

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
      // ⚠ Дума+номер на бележка живеят в WidgetSpan и НОСЯТ текст. Той
      // трябва да се брои в [skip], инак всичко след него се реже с
      // толкова знака встрани.
      final w = _spanPlainText(s);
      if (w.isNotEmpty) {
        if (left >= w.length) {
          left -= w.length;
          continue;
        }
        // Прекъсването пада ВЪТРЕ в неделимата двойка — тя отива цяла в
        // остатъка, за да не се разцепи точно това, което слепихме.
        left = 0;
        out.add(s);
        continue;
      }
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
  // Според избрания в настройките размер на буквицата — виж
  // drop_cap_scale.dart (общо с двата четеца). .ceil() както при тях
  // (там: (dropCapSize / lineHeight).ceil()).
  final scale = ReaderDropCapScale.value;
  final capLines = scale.linesMultiplier.ceil();
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
  final capFontSize =
      lineHeightPt * capLines * 0.85 * (_kPdfCapSizeFactor[scale] ?? 1.0);
  // Буквата на буквицата и евентуалната кавичка пред нея — смятаме го
  // ВЕДНЪЖ тук (по-рано, отколкото стоеше преди — capWidth вече има нужда
  // от нея за груповата корекция по-долу), защото трябва навсякъде долу:
  // колко знака да отпаднат от текста (skip) И самите знаци за рисуване
  // накрая.
  final dropInfo = _dropCapLetterInfo(blocks[start].text);
  final capWidth = capFontSize *
      0.45 *
      _kPdfCapWidthFactor *
      (_kPdfCapWidthGroupFactor[dropCapWidthGroupOf(dropInfo.cap)] ?? 1.0);
  // Буквицата трябва да НАДВИШАВА горния ръб на първия ред (както в
  // четеца). Постига се с отстъп отгоре на съседния текст: самата буква
  // започва най-горе в блока, а текстът тръгва по-надолу. Bukvica има
  // голямо празно поле над същинския глиф, затова отстъпът е по-щедър от
  // "на око" очакваното.
  final capRise = _bodySize * 0.9;
  // Освен отстъпа на съседния текст, самата буква се ИЗМЕСТВА нагоре.
  // Само с отстъпа не става: глифът се рисува на фиксирано място спрямо
  // кутията си, затова над определена точка увеличаването му не личеше.
  final capShift = _bodySize * 1.8 * (_kPdfCapYShiftFactor[scale] ?? 1.0);

  final narrowWidth = pageWidth - capWidth - 8;
  const paraGap = 20.0; // същото отстояние като между абзаците по-долу
  final indentWidth = _bodySize * 1.6;

  final style = pw.TextStyle(
      font: _body, fontSize: _bodySize,
      lineSpacing: _lineSpacing(measureFont, _bodySize), color: _ink);

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
        strongColor: strongColor, font: measureFont);
    // Първият знак (или кавичка + знак) вече е нарисуван като буквица.
    if (isFirst) spans = _spansAfter(spans, dropInfo.skip);
    // Само текстовите парчета — котвите нямат ширина и не влизат в
    // мярката на редовете.
    // ⚠ И текстът, скрит в WidgetSpan-овете (дума+номер на бележка), се
    // брои: инак редовете се мерят по-къси, отколкото са, и разрязването
    // на абзаца пада на грешно място.
    final plain = spans.map(_spanPlainText).join();
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
                // отрицателната свали буквата върху следващия ред). По X
                // посоката е обичайната (отрицателно = наляво) — виж
                // dropCapOffsetX в drop_cap.dart, споделена с четците.
                offset: PdfPoint(
                    dropCapOffsetX(dropInfo.cap, capFontSize,
                        scaleMultiplier:
                            ReaderDropCapScale.value.offsetMultiplier),
                    capShift),
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
/// Строи документа и връща байтовете му ЗАЕДНО с името на файла.
///
/// ⚠ Изнесено от [sharePdf] (31.08.2026), за да може оформлението да се
/// проверява БЕЗ устройство: `flutter test` вика тази функция, записва
/// изхода и той се преглежда веднага. Цикълът билд → пренос по мрежата →
/// инсталация отнема минути и харчи потребителски лимит, а тук е секунди —
/// същият довод, с който вертикалното подравняване на бележките беше
/// намерено експериментално (виж CLAUDE.md, „ДВА КАПАНА В pdf ПАКЕТА").
/// Църковната дата като „14.фев." — така, както застава в името на файла.
///
/// ⚠ Съкращенията са ТРИБУКВЕНИ и с точка, а месеците — в родителен вид,
/// какъвто се чете в „Памет на 14 февруари". Списъкът е зашит, защото
/// `intl` дава други форми („февр.", „фев") според локала, а името на файла
/// трябва да изглежда еднакво на всяко устройство.
const List<String> _monthShort = [
  '', 'ян.', 'фев.', 'март', 'апр.', 'май', 'юни',
  'юли', 'авг.', 'сеп.', 'окт.', 'ное.', 'дек.',
];

String memoryDatePrefix(DateTime churchDate) =>
    'Памет на ${churchDate.day.toString().padLeft(2, '0')}.'
    '${_monthShort[churchDate.month]}';

Future<({Uint8List bytes, String fileName})> buildPdfBytes({
  required String title,
  required String bodyHtml,
  required String fileName,
  bool withDropCap = true,
  bool strongIsWine = false,
  bool prayerLike = false,
  /// Църковната дата на паметта — застава пред заглавието в името на файла.
  DateTime? churchDate,
}) async {
  await _ensureFonts();
  final blocks = _parseBlocks(bodyHtml);
  const margin = 40.0;
  final contentWidth = PdfPageFormat.a4.width - margin * 2;

  // ⚠ Изображенията се зареждат ТУК, преди строенето: `MultiPage.build` е
  // СИНХРОНЕН, а четенето от пакета не е. Пропуснатото (липсващ файл,
  // повреден JPEG) просто не влиза в картата и блокът се подминава — една
  // липсваща илюстрация не бива да отнася целия документ, точно както в
  // четеца (виж LivesImageExtension).
  final images = <String, pw.MemoryImage>{};
  for (final b in blocks) {
    final asset = b.imageAsset;
    if (asset == null || images.containsKey(asset)) continue;
    try {
      final data = await rootBundle.load(asset);
      images[asset] = pw.MemoryImage(data.buffer.asUint8List());
    } catch (_) {
      // без картинка — блокът се пропуска при строенето
    }
  }

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // БЪГФИКС #1: ИМЕ НА PDF ФАЙЛА
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // Извличаме заглавието (h1) и подзаглавието (memorydate) от вече
  // парсираните blocks, за да формираме смислено име на файла.
  // Предишният код разчиташе само на подадения параметър `fileName`,
  // който идваше отвън и съдържаше само подзаглавието.
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // ⚠ ЗАГЛАВИЕТО СЕ ВЗИМА САМО ОТ НАЧАЛОТО на четивото, а не първото
  // срещнато. Дотук се търсеше „първият блок със заглавие, където и да е" —
  // а житията на българските светии носят „Допълнение" по средата (виж
  // 06_apply.py). Резултат: PDF-ът на Гавриил Лесновски се казваше
  // „Допълнение.pdf". Има ли четивото собствено заглавие, то е ПЪРВИЯТ блок;
  // няма ли — важи името, подадено отвън.
  String mainTitle = blocks.isNotEmpty && blocks.first.isHeading
      ? blocks.first.text
      : title;
  String subTitle = '';
  for (final block in blocks) {
    if (block.cls.contains('memorydate')) {
      subTitle = block.text;
      break;
    }
  }
  if (mainTitle.isEmpty) mainTitle = title;
  final pdfFileName = _safeFileName(
      main: mainTitle,
      sub: mainTitle == subTitle ? '' : subTitle,
      fallback: title,
      prefix: churchDate == null ? '' : memoryDatePrefix(churchDate));

  // Височината на листа, с която работи `MultiPage`: формат минус полетата
  // и минус опашката с номера (12 отстъп + един ред).
  final usableHeight =
      PdfPageFormat.a4.height - margin * 2 - (12 + (_bodySize - 2) * 1.4);
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
        // ⚠ ДВУПРОХОДНО СТРОЕНЕ (31.08.2026).
        //
        // Първият проход строи всичко и служи само за МЕРЕНЕ: оттам се
        // взимат истинските височини и се решава къде да падне всяка
        // илюстрация. Вторият строи наново, вече по пренаредените блокове.
        //
        // ⚠ Два прохода са НЕОБХОДИМИ, а не разточителство. Решението
        // „заглавието да се групира с абзаца под себе си" се взима ПО ВРЕМЕ
        // на строенето — а какво стои под заглавието зависи от
        // пренареждането. При един проход заглавие, следвано от картинка,
        // не намираше с какво да се групира и оставаше само в дъното на
        // листа, макар точно това правило да го пази от такъв край.
        List<_Item> buildItems(List<_Block> arranged) {
        // Ако самото четиво започва със заглавие (<h1>..<h6>), нашето име
        // отгоре е излишно — иначе излизат две заглавия едно под друго.
        // Същата проверка като hasOwnTitle в четеца.
        final hasOwnTitle = arranged.isNotEmpty && arranged.first.isHeading;
        // ⚠ Събират се _Item-и, а не голи widget-и: мениджърът на страниците
        // трябва да знае кои от тях са илюстрации и кои — заглавия.
        final items = <_Item>[
          if (!hasOwnTitle) ...[
            _Item(
              pw.Center(
                child: pw.Text(title,
                    textAlign: pw.TextAlign.center,
                    style:
                        pw.TextStyle(font: _title, fontSize: 34, color: _ink)),
              ),
              isHeading: true,
            ),
            _Item(pw.SizedBox(height: prayerLike ? 56 : 22)),
          ],
        ];
        // Кратка обвивка: досегашният код добавя widget-и на десетки места.
        var curBlock = -1; // кой блок се изписва в момента
        void add(pw.Widget w,
            {bool isImage = false,
            bool isHeading = false,
            bool splittable = false}) {
          items.add(_Item(w,
              isImage: isImage,
              isHeading: isHeading,
              splittable: splittable)
            ..blockIndex = curBlock);
        }
        var dropCapUsed = false;
        var mainHeadingUsed = false;
        var scanned = 0;
        // ⚠ КОЛКО ЗНАКА от следващия абзац вече са изписани заедно със
        // заглавието му, а НЕ самият остатък като текст.
        //
        // Дотук се пазеше готовият низ и се рендваше като гол текст — затова
        // групирането важеше само за абзаци БЕЗ нито един вътрешен таг
        // (`!next.inner.contains('<')`). А точно те са рядкост: курсив,
        // връзка или номер на бележка има почти навсякъде, тъй че правилото
        // мълчеше и заглавието оставаше само в дъното (докладвано с пример
        // 31.08.2026). С брой знаци остатъкът се реже със `_spansAfter` —
        // същата функция, с която работи и буквицата — и таговете оцеляват.
        int? pendingSkip;
        double? mainHeadingGap;
        for (var i = 0; i < arranged.length; i++) {
          final b = arranged[i];
          curBlock = i;
          mainHeadingGap = null;
          // Разпознава се по КЛАСА, който слагаме ние, а не по думата
          // "Източник": 49 жития завършват със собствен ред за източник,
          // част от самия текст. По думата спирахме на него и оставяхме
          // навън и тропарите, и нашата атрибуция.
          if (b.cls.contains('source') && items.isNotEmpty) {
            add(pw.SizedBox(height: 18));
          }
          // Началото на тропарите под житието — иска въздух над себе си,
          // за да не изглежда като продължение на последния абзац.
          // Заглавие тук няма нарочно: разделя ги отстоянието.
          if (b.cls.contains('pdfgap') && items.isNotEmpty) {
            add(pw.SizedBox(height: 40));
          }
          // Този абзац вече е започнат заедно със заглавието си — тук
          // остава да се изпише само остатъкът му.
          var skipInBlock = 0;
          if (pendingSkip != null && !b.isHeading) {
            final skip = pendingSkip;
            pendingSkip = null;
            if (skip < 0) {
              // ⚠ Целият абзац се е побрал при заглавието — но отстъпът СЛЕД
              // него още не е добавен, а `continue` прескача края на
              // итерацията. Без този ред следващото заглавие се залепваше за
              // текста отгоре.
              add(pw.SizedBox(height: 20));
              continue;
            }
            skipInBlock = skip;
          }
          // ── ИЛЮСТРАЦИЯ ────────────────────────────────────────────────
          if (b.isImage) {
            final img = images[b.imageAsset];
            if (img == null) continue; // липсващ файл — тихо, както в четеца
            final next = i + 1 < arranged.length ? arranged[i + 1] : null;
            final capBlock =
                (next != null && next.cls.contains('caption')) ? next : null;
            final size = _imageBox(b.imageAspect, img, contentWidth);
            final capStyle = capBlock == null
                ? null
                : _blockStyleOf(capBlock, _body!.getFont(context), _bodySize);
            // ⚠ КАРТИНКАТА И НАДПИСЪТ Ѝ СА ЕДНО ЦЯЛО (`Inseparable`): и
            // защото изображение, разрязано между две страници, е дефект, и
            // защото надпис, откъснат от своята картинка, спира да значи
            // каквото и да е.
            add(isImage: true, pw.Inseparable(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.SizedBox(height: 8),
                  pw.Image(img, width: size.$1, height: size.$2),
                  if (capBlock != null && capStyle != null) ...[
                    pw.SizedBox(height: 5),
                    // Надписът е ТОЧНО колкото картинката, не колкото
                    // колоната — той принадлежи на нея (както в четеца).
                    pw.SizedBox(
                      width: size.$1,
                      child: pw.RichText(
                        textAlign: pw.TextAlign.left,
                        text: pw.TextSpan(
                            style: capStyle,
                            children: _inlineSpans(
                                capBlock.inner.isEmpty
                                    ? capBlock.text
                                    : capBlock.inner,
                                capStyle,
                                strongColor: strongIsWine ? _wine : _ink,
                                font: _body!.getFont(context),
                                baseItalic: true)),
                      ),
                    ),
                  ],
                  pw.SizedBox(height: 14),
                ],
              ),
            ));
            if (capBlock != null) i++; // надписът е изписан заедно с нея
            continue;
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
                arranged, i, contentWidth, _body!.getFont(context),
                strongColor: strongIsWine ? _wine : _ink);
            for (final w in dc.widgets) { add(w); }
            // Буквицата може да е погълнала няколко абзаца — цикълът
            // прескача точно тях.
            i += dc.consumed - 1;
          } else {
            // Кой е следващият блок и ще носи ли той буквица — от това
            // зависи дали може да бъде "залепен" за заглавието над него.
            // Абзацът с буквицата се рендва ЦЯЛ от собствения си код и
            // затова НЕ бива да се групира (иначе първите му редове
            // излизаха два пъти).
            final next = i + 1 < arranged.length ? arranged[i + 1] : null;
            final nextTakesDropCap = withDropCap &&
                !dropCapUsed &&
                next != null &&
                _eligibleForDropCap(next);
            // ⚠ ДВЕ от досегашните условия отпаднаха (31.08.2026):
            // `!next.isItalic` и `!next.inner.contains('<')`. И двете бяха
            // там, защото групирането рендваше гол текст с прав шрифт; сега
            // то минава през същите стил и спанове като самия абзац, тъй че
            // курсив, връзка или номер на бележка не му пречат.
            //
            // ⚠ Остават две истински пречки: следващият да не е ЗАГЛАВИЕ
            // (две заглавия едно под друго не се групират — второто пак ще
            // остане само) и да не носи БУКВИЦА (тя се рендва от собствения
            // си код и залепена, излизаше два пъти).
            // ⚠ И не КАРТИНКА: групирането реже текст, а картинката няма
            // такъв — тя минаваше за „абзац, побрал се цял", маркираше се
            // като изписана и се пропускаше. Тоест заглавие, следвано от
            // илюстрация, я изяждаше мълчаливо (31.08.2026).
            final canKeepWithNext = next != null &&
                !next.isHeading &&
                !next.isImage &&
                !nextTakesDropCap;

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
                // ⚠ СЪЩИЯТ стил и СЪЩИТЕ спанове, с които абзацът ще се
                // изпише и сам. Дотук тук стоеше гол `next.text` с прав
                // шрифт и основен размер — затова курсивните абзаци и тези
                // с вътрешни тагове бяха изключени от правилото и
                // заглавието оставаше само.
                final nStyle =
                    _blockStyleOf(next, _body!.getFont(context), _bodySize);
                final nSize = _blockFontSizeOf(next, _bodySize);
                final nSpans = _inlineSpans(
                    next.inner.isEmpty ? next.text : next.inner, nStyle,
                    strongColor: strongIsWine ? _wine : _ink,
                    font: _body!.getFont(context),
                    baseBold: next.cls.contains('prayerhead'),
                    baseItalic: next.isItalic ||
                        next.cls.contains('memorydate') ||
                        next.cls.contains('caption') ||
                        next.cls.contains('centernote'));
                // Мери се СГЛОБЕНИЯТ от парчетата текст, не `next.text`:
                // така отрязването и изписването броят едни и същи знаци.
                final nPlain = nSpans.map(_spanPlainText).join();
                final split = _splitLines(nPlain, contentWidth,
                    _body!.getFont(context), nSize, 2);
                pendingSkip = split.rest.isEmpty ? -1 : split.head.length;
                final centered = next.cls.contains('memorydate');
                add(isHeading: true, pw.Inseparable(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                    children: [
                      headingWidget,
                      pw.SizedBox(height: mainHeadingGap ?? (prayerLike ? 34 : 24)),
                      // Целият абзац с maxLines: 2 — виж бележката при
                      // абзаците долу защо не подаваме само двата реда.
                      pw.RichText(
                          textAlign: centered
                              ? pw.TextAlign.center
                              : pw.TextAlign.justify,
                          maxLines: 2,
                          text: pw.TextSpan(style: nStyle, children: nSpans)),
                    ],
                  ),
                ));
              } else {
                add(headingWidget, isHeading: true);
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
              // ⚠ Стилът и размерът идват от ОБЩИТЕ функции — същите, с
              // които се строи и групирането на абзац със заглавието му.
              final style = _blockStyleOf(b, _body!.getFont(context), _bodySize);
              // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
              // 🔥 НОВ КОД ЗА MEMORYDATE: центриран с pw.Center + pw.Text
              // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
              if (isMemoryDate) {
                // Центриран текст - без RichText
                add(pw.Center(
                  child: pw.Text(
                    skipInBlock > 0 ? b.text.substring(skipInBlock).trim() : b.text,
                    style: style,
                    textAlign: pw.TextAlign.center,
                  ),
                ));
                // След memorydate добавяме стандартно отстояние
                add(pw.SizedBox(height: 20));
                continue;  // ← ПРОПУСКАМЕ ОСТАНАЛАТА ЛОГИКА за този блок
              }
              // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
              
              // Отстъп на ПЪРВИЯ ред (като tab). pdf пакетът няма
              // "text-indent", затова слагаме невидима кутия като първи
              // inline елемент — тя засяга само първия ред, не пренесените.
              // Абзацът с буквицата и източникът се пропускат, както и
              // остатъкът от абзац, започнат при заглавието си отгоре —
              // той е продължение, а не ново начало.
              
              final isContinuation = skipInBlock > 0;
              final indent = (!dropCapUsed ||
                      isContinuation ||
                      b.isItalic ||
                      isPrayerHead ||
                      isCsl ||
                      isTrans ||
                      isMemoryDate)
                  ? null
                  : pw.WidgetSpan(child: pw.SizedBox(width: _bodySize * 1.6));
              // ⚠ Спановете се строят ВИНАГИ от пълния блок, а остатъкът се
              // получава с `_spansAfter`. Дотук продължението се подаваше като
              // ГОЛ текст и всички тагове в него се губеха — оттам и тясното
              // условие, при което групирането изобщо се допускаше.
              final fullSpans = _inlineSpans(
                  b.inner.isEmpty ? b.text : b.inner,
                  style,
                  strongColor: strongIsWine ? _wine : _ink,
                  font: _body!.getFont(context),
                  baseBold: isPrayerHead,
                  // ⚠ И memorydate: без него _inlineSpans строи спановете
                  // с прав шрифт и презаписва курсива, зададен в `style`
                  // по-горе — стилът на блока се губи мълчаливо.
                  baseItalic: b.isItalic || isMemoryDate);
              final bodySpans =
                  skipInBlock > 0 ? _spansAfter(fullSpans, skipInBlock) : fullSpans;
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
                final nStyle =
                    _blockStyleOf(next, _body!.getFont(context), _bodySize);
                final nSize = _blockFontSizeOf(next, _bodySize);
                final nSpans = _inlineSpans(
                    next.inner.isEmpty ? next.text : next.inner, nStyle,
                    strongColor: strongIsWine ? _wine : _ink,
                    font: _body!.getFont(context),
                    baseItalic: next.isItalic);
                final nPlain = nSpans.map(_spanPlainText).join();
                final split = _splitLines(
                    nPlain, contentWidth, _body!.getFont(context), nSize, 2);
                pendingSkip = split.rest.isEmpty ? -1 : split.head.length;
                add(pw.Inseparable(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                    children: [
                      paragraph,
                      pw.SizedBox(height: 12),
                      pw.RichText(
                          textAlign: pw.TextAlign.justify,
                          maxLines: 2,
                          text: pw.TextSpan(style: nStyle, children: nSpans)),
                    ],
                  ),
                ));
              } else if (_onlyLinkTags(b.inner) &&
                  !isSourceLine &&
                  bodySpans.isNotEmpty) {
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
                  add(pw.Inseparable(child: paragraph));
                } else {
                  // Подава се ЦЕЛИЯТ абзац с maxLines: 2, а не отрязаните
                  // два реда. Причината е в pdf пакета: последният ред на
                  // текст НЕ се разпъва между полетата (така се пише всеки
                  // край на абзац). Ако тук подадем само двата реда, вторият
                  // им е "последен" и остава скъсен — а това си личеше на
                  // всеки абзац в документа. При maxLines изходът от
                  // подредбата става веднага след добавения ред, който вече
                  // е записан като разпънат.
                  add(pw.Inseparable(
                    child: pw.RichText(
                      textAlign: pw.TextAlign.justify,
                      maxLines: 2,
                      text: pw.TextSpan(style: style, children: [
                        if (indent != null) indent,
                        ...bodySpans,
                      ]),
                    ),
                  ));
                  add(pw.SizedBox(height: fontSize * 0.45));
                  add(splittable: true, pw.RichText(
                      textAlign: pw.TextAlign.justify,
                      overflow: pw.TextOverflow.span,
                      text: pw.TextSpan(
                        style: style,
                        children: _spansAfter(bodySpans, split.head.length),
                      )));
                }
              } else {
                add(paragraph, splittable: true);
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
          // ⚠ ГРУПИРАНОТО заглавие НЕ получава отстъп след себе си: той вече
          // стои ВЪТРЕ в кутията му, между надписа и първите два реда. Сложен
          // и тук, той падаше между тези два реда и остатъка на абзаца — тоест
          // насред изречение — и се четеше като нов абзац. (31.08.2026.)
          final grouped = pendingSkip != null;
          add(pw.SizedBox(
              height: grouped
                  ? 0
                  : b.isHeading
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
        if (notes.isNotEmpty) {
          add(pw.SizedBox(height: 26));
          add(pw.Container(
            width: contentWidth * 0.34,
            height: 0.7,
            color: _dim,
          ));
          add(pw.SizedBox(height: 14));
          const noteSize = _bodySize - 5;
          for (final n in notes) {
            add(pw.Anchor(
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
          return items;
        }

        // ⚠ ТОЧНО ДВА ПРОХОДА — първият само мери, вторият строи наред.
        //
        // Изкушението е да се повтаря, докато редът престане да се мени:
        // преместената картинка сменя онова, което стои под заглавието, а от
        // него зависи дали заглавието ще се групира с абзаца под себе си.
        // Мерено на живо обаче (31.08.2026), при най-дългото житие цената е
        // непосилна: всяко строене на 1200 елемента отнема ~2,5 s на
        // десктопа и към минута на телефона, а третата итерация вече само
        // разменяше една картинка напред-назад, без да намалява празнините.
        //
        // Затова: строим веднъж за мярка, пренареждаме веднъж, строим
        // наново. Остатъчната неточност е няколко пункта на страница —
        // покрита е от [_kFitMargin].
        final measured = buildItems(blocks);
        final reordered = _reorderBlocks(
            blocks, measured, context, contentWidth, usableHeight);
        if (identical(reordered, blocks)) {
          return [for (final it in measured) it.widget];
        }
        return [for (final it in buildItems(reordered)) it.widget];
      },
    ),
  );

  // ⚠ Името идва от САМИЯ текст (заглавие + ред с паметта), а не от
  // подадения `fileName` — той носи само подзаглавието.
  return (bytes: await doc.save(), fileName: pdfFileName);
}

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
  DateTime? churchDate,
}) async {
  final out = await buildPdfBytes(
    title: title,
    bodyHtml: bodyHtml,
    fileName: fileName,
    withDropCap: withDropCap,
    strongIsWine: strongIsWine,
    prayerLike: prayerLike,
    churchDate: churchDate,
  );
  await Printing.sharePdf(bytes: out.bytes, filename: out.fileName);
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
  DateTime? churchDate,
}) async {
  // Взима се ПРЕДИ await-а: след него екранът може вече да е напуснат и
  // `context` да не е годен за търсене на ScaffoldMessenger.
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context, rootNavigator: true);

  // ⚠ ПОКАЗАТЕЛ, ЧЕ СЕ РАБОТИ. Дълго житие с илюстрации се строи по няколко
  // секунди на десктопа и осезаемо повече на телефон — а строенето държи
  // нишката, тъй че екранът не отвръща на нищо. Без този прозорец човек
  // натиска „Сподели като PDF" и не се случва НИЩО видимо; естественото
  // заключение е, че копчето е счупено. (Докладвано 31.08.2026.)
  var dialogOpen = true;
  unawaited(showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.4),
            ),
            SizedBox(width: 18),
            Flexible(child: Text('Създава се PDF…')),
          ],
        ),
      ),
    ),
  ).then((_) => dialogOpen = false));

  void closeDialog() {
    if (!dialogOpen) return;
    dialogOpen = false;
    navigator.pop();
  }

  try {
    // ⚠ Един кадър, за да се появи прозорецът, ПРЕДИ да започне тежкото.
    // Строенето е синхронно и не пуска нишката — покажем ли го след него,
    // той ще мигне за миг и няма да свърши никаква работа.
    await Future<void>.delayed(const Duration(milliseconds: 16));
    await sharePdf(
      title: title,
      bodyHtml: bodyHtml,
      fileName: fileName,
      withDropCap: withDropCap,
      strongIsWine: strongIsWine,
      prayerLike: prayerLike,
      churchDate: churchDate,
    );
    closeDialog();
    return true;
  } catch (e) {
    closeDialog();
    messenger.showSnackBar(
      SnackBar(content: Text('Неуспешно създаване на PDF: $e')),
    );
    return false;
  }
}