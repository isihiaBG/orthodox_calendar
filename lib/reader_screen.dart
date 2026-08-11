// reader_screen.dart
//
// Единният инструмент за четене: жития, тропари/кондаци (а после
// молитвослов, четива, указания).
//
// Възможности:
//  - Контроли (+) и (−) в лентата: увеличаване/намаляване на шрифта.
//    Изборът се пази за сесията (static) — следващото житие се отваря
//    със същия размер.
//  - Заглавието (името на светията) е в червеното на неделите.
//  - Житието започва с водеща главна буква: червена, артистичен шрифт,
//    с височина ~3 реда (drop cap).
//  - Линковете са сини (AppColors.sectionTitle) — никъде лилаво.
//  - saint:// линковете бутат нов ReaderScreen (Navigator.push — стекът
//    пази пътя назад: събор → апостол → назад → събора).
//  - Под текста стои източникът (атрибуция).
//
// Зависимости: flutter_html ^3.x; шрифт "DropCapFont" в pubspec:
//   fonts:
//     - family: DropCapFont
//       fonts:
//         - asset: assets/fonts/ТВОЯ_ФАЙЛ.ttf

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/gestures.dart' show TapGestureRecognizer;
import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_theme.dart';
import 'pdf_export.dart';
import 'round_icon_button.dart';
import 'saint_expandable_tile.dart'
    show SaintTexts, SaintLookup, prayersTitleFor;

// Шрифтовете (family имената от pubspec.yaml):
const String _titleFamily = 'TamburinModern'; // заглавието на житието
const String _dropCapFamily = 'Bukvica';      // орнаментираният инициал
const String _bodyFamily = 'Cambria';         // основният текст и молитвите

/// Разкодира HTML entity-тата (&ndash; &nbsp; &laquo; …) в истински символи.
/// Нужна е за обтичащата зона около буквицата, където текстът се рендва
/// като чист Text, а не през flutter_html (той си ги разкодира сам).
String _decodeEntities(String s) {
  const named = {
    '&ndash;': '\u2013', // –
    '&mdash;': '\u2014', // —
    '&nbsp;': '\u00A0',
    '&laquo;': '\u00AB', // «
    '&raquo;': '\u00BB', // »
    '&bdquo;': '\u201E', // „
    '&ldquo;': '\u201C', // “
    '&rdquo;': '\u201D', // ”
    '&lsquo;': '\u2018',
    '&rsquo;': '\u2019',
    '&hellip;': '\u2026',  // …
    '&middot;': '\u00B7',
    '&deg;': '\u00B0',
    // Гръцки букви — срещат се в цитирани оригинални имена.
    '&Alpha;': '\u0391', '&Epsilon;': '\u0395',
    '&zeta;': '\u03B6', '&eta;': '\u03B7',
    '&theta;': '\u03B8', '&iota;': '\u03B9',
    '&kappa;': '\u03BA', '&lambda;': '\u03BB',
    '&nu;': '\u03BD', '&xi;': '\u03BE',
    '&omicron;': '\u03BF', '&rho;': '\u03C1',
    '&sigma;': '\u03C3', '&sigmaf;': '\u03C2',
    '&tau;': '\u03C4', '&omega;': '\u03C9',
    '&egrave;': '\u00E8',
    '&dagger;': '\u2020',  // † кръст
    '&amp;': '&',
    '&lt;': '<',
    '&gt;': '>',
    '&quot;': '"',
    '&apos;': "'",
  };
  var out = s;
  named.forEach((k, v) => out = out.replaceAll(k, v));
  // Числови: &#1234; и &#x04D1;
  out = out.replaceAllMapped(
    RegExp(r'&#(\d+);'),
    (m) => String.fromCharCode(int.parse(m.group(1)!)),
  );
  out = out.replaceAllMapped(
    RegExp(r'&#[xX]([0-9a-fA-F]+);'),
    (m) => String.fromCharCode(int.parse(m.group(1)!, radix: 16)),
  );
  return out;
}

// ---------------------------------------------------------------
// Търсене: диакритик- и регистър-неутрално сравнение
// ---------------------------------------------------------------

/// "Изчистен" текст за търсене (малки букви, без ударения над буквите:
/// U+0300–U+036F — комбиниращи диакритични знаци) + карта на позициите,
/// за да можем да маркираме точно оригиналния (с ударения) откъс.
class _Folded {
  final String text;
  final List<int> origIndex;
  const _Folded(this.text, this.origIndex);
}

_Folded _fold(String s) {
  final buf = StringBuffer();
  final idx = <int>[];
  for (int i = 0; i < s.length; i++) {
    final code = s.codeUnitAt(i);
    if (code >= 0x0300 && code <= 0x036F) continue; // ударение/диакритика
    buf.write(s[i].toLowerCase());
    idx.add(i);
  }
  return _Folded(buf.toString(), idx);
}

int _countMatchesPlain(String text, String foldedQuery) {
  if (foldedQuery.isEmpty) return 0;
  final f = _fold(text).text;
  int count = 0, from = 0;
  while (true) {
    final at = f.indexOf(foldedQuery, from);
    if (at < 0) break;
    count++;
    from = at + foldedQuery.length;
  }
  return count;
}

/// Брои съвпаденията само в текстовите сегменти на HTML (не в таговете).
int _countMatchesHtml(String html, String foldedQuery) {
  if (foldedQuery.isEmpty) return 0;
  int count = 0;
  for (final m in RegExp(r'<[^>]+>|[^<]+').allMatches(html)) {
    final piece = m.group(0)!;
    if (piece.startsWith('<')) continue;
    count += _countMatchesPlain(piece, foldedQuery);
  }
  return count;
}

/// Маркира съвпаденията в HTML — обвива всяко в <span class="hit(-current)">.
///
/// <a href="...">...</a> се третира като ЦЯЛОСТЕН блок, обработван ОТДЕЛНО
/// от _highlightAnchorText — flutter_html принудително презаписва стила на
/// ВСЕКИ вложен span вътре в котва със собствения стил на котвата (виж
/// InteractiveElementBuiltIn._processInteractableChild в пакета), затова
/// <span class="hit"> вътре в <a> губи жълтия си фон и изчезва визуално.
/// Вместо да вмъкваме span, разделяме самата котва на съседни <a> тагове
/// със същия href — само фрагментът със съвпадението носи class="hit",
/// получавайки собствен смесен стил (синьо + жълт фон). Всичко останало
/// продължава по старата таг/текст логика, непроменена.
String _highlightHtml(
  String html,
  String foldedQuery,
  int firstGlobalIndex,
  int currentGlobalIndex,
) {
  if (foldedQuery.isEmpty) return html;
  final buf = StringBuffer();
  int local = 0;

  void highlightPlainSegment(String segment) {
    for (final m in RegExp(r'<[^>]+>|[^<]+').allMatches(segment)) {
      final piece = m.group(0)!;
      if (piece.startsWith('<')) {
        buf.write(piece);
        continue;
      }
      final folded = _fold(piece);
      int from = 0, lastEnd = 0;
      while (true) {
        final at = folded.text.indexOf(foldedQuery, from);
        if (at < 0) break;
        final origStart = folded.origIndex[at];
        final endFoldedIdx = at + foldedQuery.length - 1;
        final origEnd = folded.origIndex[endFoldedIdx] + 1;
        buf.write(piece.substring(lastEnd, origStart));
        final isCurrent = (firstGlobalIndex + local) == currentGlobalIndex;
        buf.write('<span class="${isCurrent ? 'hit-current' : 'hit'}">');
        buf.write(piece.substring(origStart, origEnd));
        buf.write('</span>');
        lastEnd = origEnd;
        local++;
        from = endFoldedIdx + 1;
      }
      buf.write(piece.substring(lastEnd));
    }
  }

  final anchorRe = RegExp(
    r'<a\b[^>]*?href="([^"]*)"[^>]*>(.*?)</a>',
    caseSensitive: false,
    dotAll: true,
  );
  int cursor = 0;
  for (final am in anchorRe.allMatches(html)) {
    if (am.start > cursor) {
      highlightPlainSegment(html.substring(cursor, am.start));
    }
    local = _highlightAnchorText(
      am.group(1)!,
      am.group(2)!,
      foldedQuery,
      firstGlobalIndex,
      local,
      currentGlobalIndex,
      buf,
    );
    cursor = am.end;
  }
  if (cursor < html.length) {
    highlightPlainSegment(html.substring(cursor));
  }
  return buf.toString();
}

/// Маркиране на съвпадение ВЪТРЕ в линк (виж коментара на _highlightHtml).
/// Приема, че вътрешността на <a> е чист текст (важи за всички линкове в
/// това приложение — saint:// и източник-атрибуцията, без вложено
/// форматиране). Връща новата стойност на local (брояча за "текущо"
/// съвпадение), за да продължи броенето непрекъснато след котвата.
int _highlightAnchorText(
  String href,
  String innerText,
  String foldedQuery,
  int firstGlobalIndex,
  int localStart,
  int currentGlobalIndex,
  StringBuffer buf,
) {
  final hrefAttr = 'href="$href"';
  final folded = _fold(innerText);
  int from = 0, lastEnd = 0, local = localStart;
  while (true) {
    final at = folded.text.indexOf(foldedQuery, from);
    if (at < 0) break;
    final origStart = folded.origIndex[at];
    final endFoldedIdx = at + foldedQuery.length - 1;
    final origEnd = folded.origIndex[endFoldedIdx] + 1;
    if (origStart > lastEnd) {
      buf.write('<a $hrefAttr>');
      buf.write(innerText.substring(lastEnd, origStart));
      buf.write('</a>');
    }
    final isCurrent = (firstGlobalIndex + local) == currentGlobalIndex;
    buf.write('<a $hrefAttr class="${isCurrent ? 'hit-current' : 'hit'}">');
    buf.write(innerText.substring(origStart, origEnd));
    buf.write('</a>');
    lastEnd = origEnd;
    local++;
    from = endFoldedIdx + 1;
  }
  if (lastEnd < innerText.length) {
    buf.write('<a $hrefAttr>');
    buf.write(innerText.substring(lastEnd));
    buf.write('</a>');
  } else if (lastEnd == 0) {
    // Няма съвпадение в тази котва — оставяме я непроменена (един таг).
    buf.write('<a $hrefAttr>');
    buf.write(innerText);
    buf.write('</a>');
  }
  return local;
}

/// Дели HTML на блокове по абзаци/заглавия — всеки получава свой GlobalKey,
/// за да можем да скролваме прецизно до региона с текущото съвпадение.
List<String> _splitBlocks(String html) {
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

/// Чист текст без тагове — същата формула, ползвана и в _DropCapParagraph.
String _plainTextOf(String innerHtml) {
  return _decodeEntities(
    innerHtml.replaceAll(RegExp(r'<[^>]+>'), ''),
  ).replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// Груба приблизителна оценка на височината (в пиксели) на един регион по
/// дължината на текста му. SliverList строи децата си мързеливо и когато
/// не ги е построил всичките, познава общата дължина на скрола по
/// СРЕДНОТО от вече построеното — при абзаци с много различна дължина
/// (кратка бележка vs. многоабзацен блок) тази преценка се преизчислява
/// драстично при всеки нов построен елемент, което кара показалеца на
/// скрола да "подскача" и прави приблизителния скок до далечно съвпадение
/// ненадежден. С тази оценка подаваме на SliverList знание за ЦЯЛата
/// дължина отнапред (виж _EstimatingListDelegate по-долу), вместо да гадае.
double _estimateRegionHeight(
  String plainText,
  double fontSize,
  double lineHeight,
  double viewportWidth, {
  int linkCount = 0,
}) {
  if (plainText.isEmpty) return 24.0;
  final availableWidth = (viewportWidth - 32).clamp(100.0, 2000.0);
  // Грубо средна широчина на знак спрямо fontSize за серифния шрифт Cambria.
  final avgCharWidth = fontSize * 0.52;
  final charsPerLine = (availableWidth / avgCharWidth).floor().clamp(10, 300);
  final lines = (plainText.length / charsPerLine).ceil().clamp(1, 2000);
  final base = lines * (fontSize * lineHeight) + 16; // + margin на <p>
  // Абзаци с няколко линка един до друг систематично подценяваха реалната
  // височина (наблюдение от чертичките на скролбара) — грубо компенсираме
  // на линк, докато не измерим точната причина в самия flutter_html рендер.
  return base + linkCount * (fontSize * 0.4);
}

/// SliverChildListDelegate с наша собствена преценка за общата дължина на
/// скрола (виж _estimateRegionHeight) — вместо вградената "средно от
/// построеното досега", която е нестабилна при силно различни по размер
/// деца.
class _EstimatingListDelegate extends SliverChildListDelegate {
  // Кумулативни оценени височини по РЕГИОН (не по child-индекс на sliver-а —
  // виж indexOffset). cumulativeHeights[i] = приблизителен край на региона i.
  final List<double> cumulativeHeights;
  // 1, ако преди regionWidgets има допълнителен елемент (заглавието на
  // светията), иначе 0 — за превод от sliver child-индекс към регион-индекс.
  final int indexOffset;

  _EstimatingListDelegate(
    super.children, {
    required this.cumulativeHeights,
    required this.indexOffset,
  });

  @override
  double? estimateMaxScrollOffset(
    int firstIndex,
    int lastIndex,
    double leadingScrollOffset,
    double trailingScrollOffset,
  ) {
    if (cumulativeHeights.isEmpty) return null;
    // Тази фаза е КРАТКА (само докато фоновото реално измерване приключи —
    // виж _finishMeasuring), затова тук държим нещата ПРОСТИ: фиксиран
    // резерв, не самокоригиращо се съотношение (то водеше до отделен скок
    // при всеки нов построен регион — разпръснато "подскачане" по пътя).
    return cumulativeHeights.last * 1.3;
  }
}

/// Delegate за РЕАЛНО измерения (точен) режим. КЛЮЧОВО: дори със
/// SliverVariedExtentList + itemExtentBuilder (точен размер на ВСЕКИ
/// елемент), Flutter пак пресмята maxScrollExtent по старата наивна формула
/// "средно от построеното досега × оставащ брой" (виж
/// _extrapolateMaxScrollOffset в sliver.dart) за всеки елемент, който още
/// не е построен — itemExtentBuilder изобщо не се пита за тази цел! Точно
/// това причиняваше "подскачането" дори в "точния" режим. Като върнем тук
/// готовата, точно известна обща сума, Flutter спира да гадае изцяло.
class _ExactListDelegate extends SliverChildListDelegate {
  final double totalExtent;
  _ExactListDelegate(super.children, {required this.totalExtent});

  @override
  double? estimateMaxScrollOffset(
    int firstIndex,
    int lastIndex,
    double leadingScrollOffset,
    double trailingScrollOffset,
  ) => totalExtent;
}

/// Един "регион" от документа — единица за търсене/скролиране.
/// isHtml=true  → рендва се през flutter_html (обикновен абзац/блок).
/// isHtml=false → буквицата (плосък текст, специален рендер).
class _Region {
  final bool isHtml;
  final String content;
  /// САМО за региона с буквицата: следващият абзац, който може да влезе
  /// вдясно от нея, ако първият не запълва петте реда. Той се маха от
  /// списъка с обикновени региони, за да не се изпише два пъти.
  final String second;
  const _Region.html(this.content)
      : isHtml = true,
        second = '';
  const _Region.dropcapPlain(this.content, {this.second = ''})
      : isHtml = false;
}

List<_Region> _computeRegions(
  String beforeHtml,
  String dropCap,
  String firstP,
  String afterHtml,
) {
  final regions = <_Region>[];
  if (dropCap.isNotEmpty) {
    if (beforeHtml.trim().isNotEmpty) regions.add(_Region.html(beforeHtml));
    final blocks = _splitBlocks(afterHtml);
    // Следващият блок отива при буквицата САМО ако е обикновен абзац:
    // заглавие или центриран курсив не бива да се притиска в тясната
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
    regions.add(_Region.dropcapPlain(firstP, second: second));
    for (final block in blocks) {
      regions.add(_Region.html(block));
    }
  } else {
    for (final block in _splitBlocks(beforeHtml)) {
      regions.add(_Region.html(block));
    }
  }
  return regions;
}

int _countInRegion(_Region r, String foldedQuery) {
  if (r.isHtml) return _countMatchesHtml(r.content, foldedQuery);
  return _countMatchesPlain(_plainTextOf(r.content), foldedQuery) +
      (r.second.isEmpty
          ? 0
          : _countMatchesPlain(_plainTextOf(r.second), foldedQuery));
}

enum _ReaderMode { life, prayers, sluzhba }

// ---------------------------------------------------------------
// Тежка текстова подготовка — изнесена в ТОП-НИВО чисти функции, за да могат
// да текат във фонов isolate (compute()), вместо синхронно в build(). За
// дълги жития (десетки региони) сглобяването на HTML + делението на
// абзаци/буквица + декодирането на entity-та във всеки регион отнемаше до
// секунда-две на устройството — точно толкова, колкото Navigator блокираше
// на push (той строи новия екран синхронно, за да го анимира), при което
// дори анимацията на присветването при тап "засичаше". Сега initState()
// стартира тази подготовка в отделен isolate; build() показва лек spinner
// докато чака и после ползва кешираните резултати (_prepared).
// ---------------------------------------------------------------

String _buildHtmlFor(_ReaderMode mode, SaintTexts texts) {
  if (mode == _ReaderMode.sluzhba) {
    final src = texts.source.isEmpty
        ? ''
        : '<p class="source">Източник: <a href="${texts.source}">'
            '${texts.source}</a></p>';
    return '${texts.sluzhba}$src';
  }

  if (mode == _ReaderMode.life) {
    final src = texts.source.isEmpty
        ? ''
        : '<p class="source">Източник: <a href="${texts.source}">'
            '${texts.source}</a></p>';
    return '${texts.lifeHtml}$src';
  }

  final prayers = _prayersBlocksHtml(texts);
  final src = texts.source.isEmpty
      ? ''
      : '<p class="source">Източник: '
          '<a href="${texts.source}">${texts.source}</a></p>';
  return '$prayers$src';
}

/// Тропарите и кондаците като HTML — БЕЗ източника отдолу.
///
/// Изнесено отделно, защото същите блокове се ползват на две места: в
/// екрана "Тропари и кондаци" и накрая на PDF-а с житието. Форматирането
/// (prayerhead / csl / trans) трябва да е едно и също и на двете места.
///
/// [firstClassExtra] лепва допълнителен клас на ПЪРВИЯ блок — така
/// pdf_export може да разпознае къде започват молитвите и да остави
/// по-голямо отстояние над тях.
String _prayersBlocksHtml(SaintTexts texts, {String firstClassExtra = ''}) {
  final b = StringBuffer();
  void block(String csl, String trans) {
    if (csl.isEmpty) return;
    final i = csl.indexOf(': ');
    if (i > 0 && i < 40) {
      b.write('<p class="prayerhead">${csl.substring(0, i)}</p>');
      b.write('<p class="csl">${csl.substring(i + 2)}</p>');
    } else {
      b.write('<p class="csl">$csl</p>');
    }
    if (trans.isNotEmpty) {
      b.write(
        '<p class="trans"><span class="translabel">Превод:</span> $trans</p>',
      );
    }
  }

  block(texts.tropar, texts.troparTrans);
  block(texts.tropar2, texts.tropar2Trans);
  block(texts.kondak, texts.kondakTrans);
  block(texts.kondak2, texts.kondak2Trans);

  var out = b.toString();
  if (out.isNotEmpty && firstClassExtra.isNotEmpty) {
    out = out.replaceFirst('class="', 'class="$firstClassExtra ');
  }
  return out;
}

/// HTML специално за PDF-а. Различава се от четеца само в едно: под
/// житието/сказанието се добавят и тропарите с кондаците (ако ги има),
/// и чак след тях идва източникът — веднъж, накрая, без нищо след себе си.
/// Службата остава сама, а екранът "Тропари и кондаци" — какъвто си е.
String _buildPdfHtmlFor(_ReaderMode mode, SaintTexts texts) {
  if (mode != _ReaderMode.life) return _buildHtmlFor(mode, texts);

  final prayers = _prayersBlocksHtml(texts, firstClassExtra: 'pdfgap');
  final src = texts.source.isEmpty
      ? ''
      : '<p class="source">Източник: <a href="${texts.source}">'
          '${texts.source}</a></p>';
  return '${texts.lifeHtml}$prayers$src';
}

/// Отделя: (HTML преди абзаца с буквицата; първата буква; текстът на
/// този абзац без буквата; останалият HTML).
///
/// Обхожда абзаците, докато намери такъв, който започва с истинска буква.
/// Така редакторски бележки в скоби ("(не путать с …)"), стоящи между
/// заглавието и житието, отиват в beforeHtml и се рендват нормално, а
/// буквицата пада върху първия същински абзац.
(String, String, String, String) _splitDropCap(String html) {
  // Абзац се ПРОПУСКА, ако същинският му текст започва с един от тези
  // знаци — редакторски бележки, цитати, бележки под линия и др. —
  // ИЛИ ако абзацът започва с курсивен таг (<em>/<i>): акцент/курсив
  // не бива да носи буквица. Курсивните абзаци допълнително се
  // центрират (клас .italic-center, виж _htmlStyles).
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
    var text = _decodeEntities(piece).replaceAll(RegExp(r'\s+'), ' ');
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
  final folded = _fold(text);
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

/// Аргументи за _prepareReaderContent — трябва да са "sendable" (само данни,
/// без closures), за да минат през границата на isolate-а с compute().
class _PrepareArgs {
  final _ReaderMode mode;
  final SaintTexts texts;
  const _PrepareArgs({required this.mode, required this.texts});
}

/// Резултатът от еднократната тежка подготовка — кешира се в State
/// (_prepared) и се преизползва при всеки следващ build() (тема, търсене,
/// смяна на шрифт), без да се преизчислява.
class _PreparedContent {
  final bool hasOwnTitle;
  final bool hasGap;
  final String dropCap;
  final List<_Region> regions;
  // Успоредни на regions — плоският текст (декодиран, без тагове) и броят
  // линкове на всеки регион, кеширани веднъж тук вместо преизвличани при
  // всеки build() само за да се пресметне хюристичната височина.
  final List<String> regionPlainTexts;
  final List<int> regionLinkCounts;

  const _PreparedContent({
    required this.hasOwnTitle,
    required this.hasGap,
    required this.dropCap,
    required this.regions,
    required this.regionPlainTexts,
    required this.regionLinkCounts,
  });
}

/// Върши ЦЯЛАТА тежка, чисто текстова подготовка (сглобяване на HTML,
/// делене на буквица/региони, декодиране на всеки регион) — стартира се
/// през compute() в отделен isolate, затова е ЧИСТА функция: никакви
/// референции към BuildContext/State/widget.
_PreparedContent _prepareReaderContent(_PrepareArgs args) {
  final html = _buildHtmlFor(args.mode, args.texts);
  final isLife = args.mode == _ReaderMode.life;
  final (beforeHtml, dropCap, firstP, afterHtml) = isLife
      ? _splitDropCap(html)
      : (html, '', '', '');

  // Житието има ли собствено заглавие (<h1>..<h6> преди първия абзац)? Ако
  // да — нашето име отгоре е излишно и се пропуска, за да няма два почти
  // еднакви заглавни реда един под друг. isLife: в режима с молитвите
  // beforeHtml съдържа целия HTML (вкл. заглавията на тропарите), затова
  // проверката важи само за житието.
  final hasOwnTitle =
      (isLife || args.mode == _ReaderMode.sluzhba) &&
      RegExp(r'<h[1-6]\b').hasMatch(beforeHtml);

  final regions = _computeRegions(beforeHtml, dropCap, firstP, afterHtml);
  final hasGap = dropCap.isNotEmpty && beforeHtml.trim().isNotEmpty;

  final plainTexts = <String>[];
  final linkCounts = <int>[];
  for (final r in regions) {
    plainTexts.add(_plainTextOf(r.content));
    linkCounts.add('href='.allMatches(r.content).length);
  }

  return _PreparedContent(
    hasOwnTitle: hasOwnTitle,
    hasGap: hasGap,
    dropCap: dropCap,
    regions: regions,
    regionPlainTexts: plainTexts,
    regionLinkCounts: linkCounts,
  );
}

// ---------------------------------------------------------------
// Отметка — пази се ЕДНА позиция (индекс на регион) на четиво (slug +
// режим). Наличието на запис = проследяването е включено; изтриване на
// записа = изключено — няма нужда от отделен bool флаг в storage-а.
// Освен индекса пазим и name/typeLabel — иначе списъкът с отметки (виж
// BookmarksListScreen) би трябвало да прави отделна DB заявка за всеки
// запис само за да покаже заглавие; вместо това ги кешираме тук, в
// момента на записа, когато вече ги имаме безплатно под ръка.
// ---------------------------------------------------------------
class _BookmarkRecord {
  final int regionIndex;
  final String name;
  final String typeLabel;
  final int savedAtMs; // за сортиране по скорошност в списъка с отметки

  const _BookmarkRecord({
    required this.regionIndex,
    required this.name,
    required this.typeLabel,
    required this.savedAtMs,
  });

  Map<String, dynamic> toJson() => {
        'regionIndex': regionIndex,
        'name': name,
        'typeLabel': typeLabel,
        'savedAtMs': savedAtMs,
      };

  static _BookmarkRecord? fromJson(Map<String, dynamic> m) {
    final regionIndex = m['regionIndex'];
    final name = m['name'];
    final typeLabel = m['typeLabel'];
    final savedAtMs = m['savedAtMs'];
    if (regionIndex is! int || name is! String || typeLabel is! String) {
      return null;
    }
    return _BookmarkRecord(
      regionIndex: regionIndex,
      name: name,
      typeLabel: typeLabel,
      savedAtMs: savedAtMs is int ? savedAtMs : 0,
    );
  }
}

/// Идентификатор на отметка — slug + режим (двете заедно сочат ЕДНО
/// конкретно четиво). Ползва се от списъка с отметки.
class _BookmarkId {
  final String slug;
  final _ReaderMode mode;
  const _BookmarkId(this.slug, this.mode);

  // Стойностно сравнение — списъкът с отметки държи избраните редове в Set
  // и след всяко презареждане получава НОВИ обекти за същите отметки.
  @override
  bool operator ==(Object other) =>
      other is _BookmarkId && other.slug == slug && other.mode == mode;

  @override
  int get hashCode => Object.hash(slug, mode);
}

class _BookmarkStore {
  static const String _prefix = 'bookmark_pos_';

  static String _key(String slug, _ReaderMode mode) =>
      '$_prefix${mode.name}_$slug';

  static Future<_BookmarkRecord?> load(String slug, _ReaderMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _key(slug, mode);
    try {
      // prefs.getString() САМО ТУК хвърля, ако под този ключ има стар
      // формат (чист int, от преди JSON записа) — затова целият прочит е
      // в try, не само декодирането.
      final raw = prefs.getString(key);
      if (raw == null) return null;
      return _BookmarkRecord.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      // Несъвместим/повреден стар запис — трием го, вместо да чупим четенето.
      await prefs.remove(key);
      return null;
    }
  }

  static Future<void> save(
    String slug,
    _ReaderMode mode,
    _BookmarkRecord record,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(slug, mode), jsonEncode(record.toJson()));
  }

  static Future<void> clear(String slug, _ReaderMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(slug, mode));
  }

  /// Всички запазени отметки в приложението — за BookmarksListScreen.
  static Future<List<(_BookmarkId, _BookmarkRecord)>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final result = <(_BookmarkId, _BookmarkRecord)>[];
    for (final key in prefs.getKeys()) {
      if (!key.startsWith(_prefix)) continue;
      _ReaderMode? mode;
      String? slug;
      for (final m in _ReaderMode.values) {
        final withMode = '$_prefix${m.name}_';
        if (key.startsWith(withMode)) {
          mode = m;
          slug = key.substring(withMode.length);
          break;
        }
      }
      if (mode == null || slug == null || slug.isEmpty) continue;
      try {
        final raw = prefs.getString(key);
        if (raw == null) continue;
        final record = _BookmarkRecord.fromJson(
          jsonDecode(raw) as Map<String, dynamic>,
        );
        if (record != null) result.add((_BookmarkId(slug, mode), record));
      } catch (_) {
        // Несъвместим/повреден стар запис — трием го при засичане.
        await prefs.remove(key);
      }
    }
    result.sort((a, b) => b.$2.savedAtMs.compareTo(a.$2.savedAtMs));
    return result;
  }

  static Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    for (final key in prefs.getKeys().toList()) {
      if (key.startsWith(_prefix)) await prefs.remove(key);
    }
  }
}

class ReaderScreen extends StatefulWidget {
  final SaintTexts texts;
  final SaintLookup lookup;
  final _ReaderMode _mode;

  /// "Житие" или "Сказание" — виж lifeLabelFor(). Ако е null, пада към
  /// "Житие" (напр. при saint:// вътрешен линк, където няма rank).
  final String? lifeTitle;

  const ReaderScreen.life({
    super.key,
    required this.texts,
    required this.lookup,
    this.lifeTitle,
  }) : _mode = _ReaderMode.life;

  const ReaderScreen.prayers({
    super.key,
    required this.texts,
    required this.lookup,
    this.lifeTitle,
  }) : _mode = _ReaderMode.prayers;

  const ReaderScreen.sluzhba({
    super.key,
    required this.texts,
    required this.lookup,
    this.lifeTitle,
  }) : _mode = _ReaderMode.sluzhba;

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen>
    with SingleTickerProviderStateMixin {
  // Размерът е static: пази се за цялата сесия, общ за всички екрани
  // на четеца. 17 е базата; стъпка 1.5; разумни граници.
  // Тема на четеца — НЕЗАВИСИМА от темата на приложението.
  // static: пази се за сесията, обща за всички екрани на четеца.
  static bool _darkMode = true;   // по подразбиране тъмна

  static double _fontSize =
      22.0; //Първоначален размер на шрифта по подразбиране
  // Персистиране на размера в потребителските настройки (SharedPreferences),
  // за да оцелее и след рестарт на приложението (_fontSize сам по себе си е
  // само сесиен). Зареждаме от диска ЕДНОКРАТНО на сесия (виж
  // _loadPersistedFontSizeOnce) — следващите ReaderScreen инстанции вече
  // виждат правилната стойност направо в статичното поле, без нов прочит.
  static bool _fontSizeLoadedFromDisk = false;
  // Последно ЗАПИСАНАТА на диска стойност, пазена в паметта — сравняваме
  // с нея вместо да четем от диска всеки път, за да пропускаме излишни
  // записи (напр. потребителят увеличава и после пак намалява до същото).
  static double? _lastSavedFontSize;
  static const String _fontSizeKey = 'reader_font_size';
  static const double _step = 1.5;
  static const double _btnSize = 22.0;   // еднакъв размер и за трите бутона
  static const double _searchBtnSize =
      _btnSize + 6; // старт/</>  в search лентата
  static const double _min = 13.0;
  static const double _max = 30.0;
  static const double _lineHeight = 1.25;
  static const double _titleGap =
      30.0; // константно разстояние заглавие → текст
  static const double _scrollThumb = 10.0;  // дебелина на палеца на скролбара

  // Резултатът от еднократната тежка текстова подготовка (виж
  // _prepareReaderContent по-горе) — null докато фоновият isolate работи.
  // build() показва лек spinner дотогава, за да не блокира push-а на
  // екрана (виж коментара в initState).
  _PreparedContent? _prepared;
  Timer? _fontSizeSaveTimer;

  /// Зарежда персистирания размер на шрифта от диска — САМО веднъж на
  /// сесия (виж _fontSizeLoadedFromDisk); следващи ReaderScreen инстанции
  /// вече го виждат директно в статичното поле _fontSize.
  static Future<void> _loadPersistedFontSizeOnce() async {
    if (_fontSizeLoadedFromDisk) return;
    _fontSizeLoadedFromDisk = true;
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getDouble(_fontSizeKey);
    if (saved != null) {
      _fontSize = saved.clamp(_min, _max);
      _lastSavedFontSize = _fontSize;
    }
  }

  /// Рестартира 3-секундния debounce за запис на шрифта (извиква се при
  /// всяко +/- натискане). Записваме едва когато измине покой от 3 сек —
  /// потребителите почти никога не уцелват желания размер от първия тап.
  void _scheduleFontSizeSave() {
    _fontSizeSaveTimer?.cancel();
    _fontSizeSaveTimer = Timer(const Duration(seconds: 3), _flushFontSizeSave);
  }

  /// Записва текущия _fontSize на диска — но само ако се различава от
  /// последно запазената стойност (пазена в паметта, без препрочитане).
  void _flushFontSizeSave() {
    _fontSizeSaveTimer = null;
    if (_lastSavedFontSize == _fontSize) return;
    _lastSavedFontSize = _fontSize;
    SharedPreferences.getInstance().then(
      (prefs) => prefs.setDouble(_fontSizeKey, _fontSize),
    );
  }

  // Captured в didChangeDependencies() (безопасно място за ScaffoldMessenger.of),
  // за да можем да скрием евентуален висящ SnackBar в dispose() — там
  // context вече не е сигурен за нови lookup-и. ScaffoldMessenger е ОБЩ за
  // цялото приложение (не локален за екрана), затова без това SnackBar-ът
  // (напр. "Последната ви позиция...") би останал да виси и върху
  // дневния изглед, след като reader_screen вече е затворен.
  ScaffoldMessengerState? _scaffoldMessenger;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scaffoldMessenger = ScaffoldMessenger.of(context);
  }

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScrollForBookmark);
    _loadPersistedFontSizeOnce().then((_) {
      if (mounted) setState(() {});
    });
    // Стартираме тежката подготовка ВЕДНАГА, но във фонов isolate — Navigator
    // все пак строи екрана синхронно веднъж при push (за анимацията), но
    // тъй като ТОЗИ (първият) build() е вече евтин (само spinner, виж
    // build() по-долу), push-ът вече не засича/блокира анимацията на тапа.
    compute(
      _prepareReaderContent,
      _PrepareArgs(mode: widget._mode, texts: widget.texts),
    ).then((result) async {
      if (!mounted) return;
      setState(() => _prepared = result);
      // Има ли вече запазена позиция за това четиво? Ако да — показваме
      // resume-подканата (виж _ResumePrompt) вместо да скачаме безшумно.
      final slug = widget.texts.slug;
      if (slug.isEmpty) return;
      final saved = await _BookmarkStore.load(slug, widget._mode);
      if (!mounted || saved == null) return;
      setState(() {
        _isBookmarked = true;
        _bookmarkedRegionIndex = saved.regionIndex;
        _showResumePrompt = true;
        _awaitingBookmarkDecision = true;
      });
    });
  }

  void _bump(double d) {
    setState(() {
      _fontSize = (_fontSize + d).clamp(_min, _max);
      // Реалните измерени височини важат само за СТАРИЯ размер на шрифта —
      // със SliverVariedExtentList старите стойности биха ПРИНУДИЛИ новия
      // (различно висок) текст в грешна кутия (препълване, изрязване).
      // Нулираме, за да прескочим обратно на хюристиката и да предизвикаме
      // ново фоново измерване за актуалния размер.
      _realCumulativeHeights = null;
      _realItemExtents = null;
      _measuring = false;
    });
    _scheduleFontSizeSave();
    // Смяната на шрифта преформатира целия текст (различни височини на
    // абзаците) — ако има активно търсене, текущото съвпадение би могло
    // да "избяга" от изгледа; пренасочваме скрола към него отново.
    if (_totalMatches > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Future.delayed(const Duration(milliseconds: 80), () {
          if (mounted) _scrollToCurrent();
        });
      });
    }
  }

  // ---------------------------------------------------------------
  // Търсене в текста
  // ---------------------------------------------------------------
  bool _searchOpen = false;
  // Отметка — виж _BookmarkStore по-горе и коментарите при методите долу.
  // _isBookmarked = проследяването е включено (има запис в storage-а).
  bool _isBookmarked = false;
  int? _bookmarkedRegionIndex; // последно известната запазена позиция
  bool _showResumePrompt = false; // показваме ли долния widget при отваряне
  // Докато resume-подканата виси на екрана (в което и да е от двете ѝ
  // състояния), автозаписът при скрол СПИРА — не бива да презаписваме
  // старата позиция, докато потребителят още не е решил какво иска.
  bool _awaitingBookmarkDecision = false;
  Timer? _bookmarkIdleTimer;
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  // Два РАЗЛИЧНИ дървовидни изгледа според _searchOpen (виж build()):
  // при четене — CustomScrollView с floating SliverAppBar; при търсене —
  // фиксирана (не-sliver) лента + отделен скролируем Expanded отдолу. При
  // всяко превключване контролерът се ПРЕСЪЗДАВА с initialScrollOffset =
  // текущата позиция (виж _toggleSearch) — новият Scrollable се ражда
  // директно на правилното място, без видим "скок" на първия кадър.
  ScrollController _scrollController = ScrollController();
  late final AnimationController _searchAnim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  );

  String _committedQuery = ''; // сурова заявка, преди fold
  int _totalMatches = 0;
  int _currentMatch = -1; // 0-based; -1 = няма
  List<int> _regionMatchCounts = [];
  List<GlobalKey> _regionKeys = [];
  // Кумулативни (нарастващи) оценени височини по региони — region i започва
  // приблизително на _cumulativeHeights[i-1] пиксела (0 за i=0). Ползва се
  // и от _EstimatingListDelegate (обща дължина), и от _scrollToCurrent
  // (по-точен "скок" до далечно съвпадение) и от маркерите на скролбара.
  List<double> _cumulativeHeights = [];
  double _viewportWidth = 400.0;

  // --- Фоново реално измерване на височините (заменя хюристиката) -----
  // Показваме житието веднага с хюристичната преценка (бързо), после в
  // невидим (Offstage) слой измерваме РЕАЛНИТЕ височини на всеки регион и
  // еднократно превключваме sliver-а към SliverVariedExtentList с точните
  // стойности — оттам нататък нативният скролбар (влачене, пропорционален
  // палец) е перфектно точен, без изкуствени прескачания.
  List<double>? _realCumulativeHeights; // по регион, кумулативно
  List<double>? _realItemExtents; // по sliver child-индекс (вкл. заглавие)
  bool _measuring = false;
  List<GlobalKey> _measureKeys = [];
  final GlobalKey _titleMeasureKey = GlobalKey();
  double? _measuredForWidth; // ширината, за която важат реалните измервания

  List<double> get _effectiveCumulativeHeights =>
      _realCumulativeHeights ?? _cumulativeHeights;

  Color get _hitColor =>
      _darkMode ? const Color(0xFF6B5B1E) : const Color(0xFFFFF176);
  Color get _hitCurrentColor =>
      _darkMode ? const Color(0xFFCC8A2E) : const Color(0xFFFFA726);

  // Чертичките на скролбара имат СВОЙ цвят за светлата тема — светложълтото
  // на _hitColor (добро като фон зад маркиран текст) почти изчезва на тънка
  // линия върху кремавия фон (_bg = 0xFFF5E6C5), затова тук е по-тъмен,
  // по-наситен маслинено-кехлибарен нюанс само за тях.
  Color get _tickHitColor => _darkMode ? _hitColor : const Color(0xFF9C7A1A);
  Color get _tickCurrentColor => _hitCurrentColor;

  /// Пресъздава скрол-контролера със стартова позиция = текущата, за да
  /// прехвърли безшумно офсета към новото Scrollable (виж коментара на
  /// _scrollController).
  void _reanchorScrollController() {
    final offset = _scrollController.hasClients
        ? _scrollController.position.pixels
        : 0.0;
    _scrollController.dispose();
    _scrollController = ScrollController(initialScrollOffset: offset)
      ..addListener(_onScrollForBookmark);
  }

  // ---------------------------------------------------------------
  // Отметка — проследяване на последна позиция (виж _BookmarkStore)
  // ---------------------------------------------------------------

  /// Регионът, който в момента е най-отгоре във видимата зона, по нашата
  /// кумулативна оценка (същата, ползвана за скрол до съвпадение).
  int _topmostRegionIndex(double pixels) {
    final cumulative = _effectiveCumulativeHeights;
    for (int i = 0; i < cumulative.length; i++) {
      if (cumulative[i] > pixels) return i;
    }
    return cumulative.isEmpty ? 0 : cumulative.length - 1;
  }

  /// Скрол-listener — НЕ пише при всяко движение (виж дискусията с
  /// потребителя): само рестартира 3-секунден таймер. Записваме едва
  /// когато скролът е бил напълно неподвижен за тези 3 секунди — така
  /// динамичното "докъде ми остава" разлистване не се брои за позиция на
  /// четене, и нищо не засича самия скрол (нула записи по време на движение).
  void _onScrollForBookmark() {
    if (!_isBookmarked || _awaitingBookmarkDecision) return;
    _bookmarkIdleTimer?.cancel();
    _bookmarkIdleTimer = Timer(
      const Duration(seconds: 3),
      _saveBookmarkIfStillIdle,
    );
  }

  void _saveBookmarkIfStillIdle() {
    if (!mounted || !_isBookmarked || _awaitingBookmarkDecision) return;
    if (!_scrollController.hasClients) return;
    final slug = widget.texts.slug;
    if (slug.isEmpty) return;
    final idx = _topmostRegionIndex(_scrollController.position.pixels);
    // Сравняваме с последно ЗАПАЗЕНАТА (в паметта, не презачитаме от диска)
    // стойност — ако позицията не се е променила (напр. телефонът лежи
    // неподвижен с часове, или дребно поклащане в рамките на същия регион),
    // пропускаме излишния запис на диска.
    if (idx == _bookmarkedRegionIndex) return;
    _bookmarkedRegionIndex = idx;
    _BookmarkStore.save(
      slug,
      widget._mode,
      _BookmarkRecord(
        regionIndex: idx,
        name: widget.texts.name,
        typeLabel: _typeLabel,
        savedAtMs: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  /// Включва/изключва проследяването. При включване записваме ТЕКУЩАТА
  /// позиция веднага (без да чакаме 3-те секунди покой — самият тап е
  /// достатъчно ясен сигнал). При изключване трием запазеното изцяло.
  Future<void> _toggleBookmark() async {
    final slug = widget.texts.slug;
    if (slug.isEmpty) return;
    if (_isBookmarked) {
      await _BookmarkStore.clear(slug, widget._mode);
      _bookmarkIdleTimer?.cancel();
      if (!mounted) return;
      setState(() {
        _isBookmarked = false;
        _bookmarkedRegionIndex = null;
        _showResumePrompt = false;
        _awaitingBookmarkDecision = false;
      });
    } else {
      final idx = _scrollController.hasClients
          ? _topmostRegionIndex(_scrollController.position.pixels)
          : 0;
      await _BookmarkStore.save(
        slug,
        widget._mode,
        _BookmarkRecord(
          regionIndex: idx,
          name: widget.texts.name,
          typeLabel: _typeLabel,
          savedAtMs: DateTime.now().millisecondsSinceEpoch,
        ),
      );
      if (!mounted) return;
      setState(() {
        _isBookmarked = true;
        _bookmarkedRegionIndex = idx;
      });
      _showBookmarkEnabledSnackbar();
    }
  }

  void _showBookmarkEnabledSnackbar() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Последната ви позиция в четивото ще се запазва регулярно, '
          'докато бутонът за отметка остава включен.',
          style: TextStyle(fontSize: 18),
        ),
        duration: Duration(seconds: 10),
      ),
    );
  }

  /// Скролира до региона на запазената отметка — първо пряко (ако вече е
  /// построен), иначе приблизителен скок по кумулативната оценка + прецизиране
  /// (същата двуфазна логика като _scrollToCurrent за търсенето).
  void _jumpToBookmarkRegion(int regionIndex) {
    if (regionIndex < 0 || regionIndex >= _regionKeys.length) return;
    final key = _regionKeys[regionIndex];

    void refine() {
      final ctx = key.currentContext;
      if (ctx == null) return;
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.05,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    }

    final ctx = key.currentContext;
    if (ctx != null) {
      refine();
      return;
    }
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    final cumulative = _effectiveCumulativeHeights;
    final estimateRaw = regionIndex > 0 && regionIndex - 1 < cumulative.length
        ? cumulative[regionIndex - 1]
        : 0.0;
    final estimate = estimateRaw.clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    position.jumpTo(estimate);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) refine();
      });
    });
  }

  void _onResumePromptJump() {
    final idx = _bookmarkedRegionIndex;
    if (idx != null) _jumpToBookmarkRegion(idx);
  }

  void _onResumePromptDeleted() {
    final slug = widget.texts.slug;
    if (slug.isNotEmpty) _BookmarkStore.clear(slug, widget._mode);
    if (!mounted) return;
    setState(() => _bookmarkedRegionIndex = null);
  }

  /// Извиква се, когато resume-подканата си отива — независимо дали чрез
  /// скок, изтриване или swipe-отказ. Възобновява нормалния автозапис.
  void _onResumePromptClosed() {
    if (!mounted) return;
    setState(() {
      _showResumePrompt = false;
      _awaitingBookmarkDecision = false;
    });
  }

  void _toggleSearch() {
    if (_searchOpen) {
      _searchAnim.reverse();
      setState(() {
        _searchOpen = false;
        _committedQuery = '';
        _totalMatches = 0;
        _currentMatch = -1;
        _regionMatchCounts = [];
        _reanchorScrollController();
      });
      _searchCtrl.clear();
    } else {
      setState(() {
        _searchOpen = true;
        _reanchorScrollController();
      });
      _searchAnim.forward();
      Future.delayed(const Duration(milliseconds: 120), () {
        if (mounted) _searchFocusNode.requestFocus();
      });
    }
  }

  void _runSearch() {
    final prepared = _prepared;
    if (prepared == null) return; // текстът още не е готов (spinner-фазата)
    final query = _searchCtrl.text.trim();
    final regions = prepared.regions;

    if (query.isEmpty) {
      setState(() {
        _committedQuery = '';
        _totalMatches = 0;
        _currentMatch = -1;
        _regionMatchCounts = [];
      });
      return;
    }

    final foldedQuery = _fold(query).text;
    final counts = regions.map((r) => _countInRegion(r, foldedQuery)).toList();
    final total = counts.fold<int>(0, (a, b) => a + b);
    setState(() {
      _committedQuery = query;
      _regionMatchCounts = counts;
      _totalMatches = total;
      _currentMatch = total > 0 ? 0 : -1;
      if (_regionKeys.length != regions.length) {
        _regionKeys = List.generate(regions.length, (_) => GlobalKey());
      }
    });
    if (total > 0) _scrollToCurrent();
  }

  void _goToMatch(int delta) {
    if (_totalMatches == 0) return;
    setState(() {
      _currentMatch = (_currentMatch + delta) % _totalMatches;
      if (_currentMatch < 0) _currentMatch += _totalMatches;
    });
    _scrollToCurrent();
  }

  int _regionIndexForCurrentMatch() {
    int remaining = _currentMatch;
    for (int i = 0; i < _regionMatchCounts.length; i++) {
      if (remaining < _regionMatchCounts[i]) return i;
      remaining -= _regionMatchCounts[i];
    }
    return 0;
  }

  /// Подравняване спрямо ГОРНАТА половина на видимата зона (не центъра) —
  /// по искане на потребителя: контекстът над фразата да се вижда, а
  /// клавиатурата долу да не я скрива. 0.22 ≈ среда на горната половина.
  static const double _matchAlignment = 0.22;

  /// Скролва до региона с текущото съвпадение. SliverList строи децата си
  /// мързеливо (само близо до видимата зона) — ако регионът вече е
  /// построен, ensureVisible е точен; иначе първо скачаме ПРИБЛИЗИТЕЛНО
  /// по пропорция, за да влезе в build-обхвата, после прецизираме.
  void _scrollToCurrent() {
    if (_currentMatch < 0 || _regionKeys.isEmpty) return;
    final regionIdx = _regionIndexForCurrentMatch();
    if (regionIdx >= _regionKeys.length) return;
    final key = _regionKeys[regionIdx];

    void refine(String tag) {
      final ctx = key.currentContext;
      if (ctx == null) return;
      Scrollable.ensureVisible(
        ctx,
        alignment: _matchAlignment,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    }

    final ctx = key.currentContext;
    if (ctx != null) {
      refine('direct');
      Future.delayed(const Duration(milliseconds: 420), () {
        if (mounted) refine('refine-1');
      });
      return;
    }
    // Не е построен — скок по НАШАТА кумулативна оценка (не сляпа пропорция
    // от maxScrollExtent, който самият той е нестабилен), после прецизиране.
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    final cumulative = _effectiveCumulativeHeights;
    final estimateRaw = regionIdx > 0 && regionIdx - 1 < cumulative.length
        ? cumulative[regionIdx - 1]
        : 0.0;
    final estimate = estimateRaw.clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    position.jumpTo(estimate);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) refine('after-jump');
      });
    });
  }

  /// Чете реалните построени (Offstage) височини и еднократно превключва
  /// на точен режим (SliverVariedExtentList). Ако някой елемент още не е
  /// построен, пробва пак на следващия кадър.
  void _finishMeasuring(int regionCount, bool hasOwnTitle, bool hasGap) {
    if (!mounted) return;
    double? titleHeight;
    if (!hasOwnTitle) {
      final ctx = _titleMeasureKey.currentContext;
      if (ctx == null) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _finishMeasuring(regionCount, hasOwnTitle, hasGap),
        );
        return;
      }
      titleHeight = (ctx.findRenderObject() as RenderBox).size.height;
    }
    final regionHeights = <double>[];
    for (int i = 0; i < regionCount; i++) {
      final ctx = _measureKeys[i].currentContext;
      if (ctx == null) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _finishMeasuring(regionCount, hasOwnTitle, hasGap),
        );
        return;
      }
      regionHeights.add((ctx.findRenderObject() as RenderBox).size.height);
    }

    final cumulative = List<double>.filled(regionCount, 0.0);
    double running = 0;
    for (int i = 0; i < regionCount; i++) {
      running += regionHeights[i];
      cumulative[i] = running;
    }

    final regionExtents = List<double>.from(regionHeights);
    if (hasGap) regionExtents.insert(1, _titleGap);
    final itemExtents = <double>[
      if (!hasOwnTitle) titleHeight!,
      ...regionExtents,
    ];

    setState(() {
      _realCumulativeHeights = cumulative;
      _realItemExtents = itemExtents;
      _measuredForWidth = _viewportWidth;
      _measuring = false;
    });
  }

  /// Позицията (0..1) на всяко съвпадение спрямо цялата преценена дължина
  /// на текста — по нашата кумулативна оценка (_cumulativeHeights), не по
  /// (нестабилния) реален maxScrollExtent. Ползва се за маркерите на
  /// скролбара — визуална проверка дали оценката е разумна.
  List<double> _allMatchRatios() {
    final cumulative = _effectiveCumulativeHeights;
    if (_totalMatches == 0 || cumulative.isEmpty) return const [];
    final total = cumulative.last;
    if (total <= 0) return const [];
    final ratios = <double>[];
    for (int i = 0; i < _regionMatchCounts.length; i++) {
      final startHeight = i > 0 ? cumulative[i - 1] : 0.0;
      final ratio = (startHeight / total).clamp(0.0, 1.0);
      for (int k = 0; k < _regionMatchCounts[i]; k++) {
        ratios.add(ratio);
      }
    }
    return ratios;
  }

  /// Тънка лента вдясно с чертички за всяко съвпадение (жълто) и текущото
  /// (оранжево) — визуализира нашите изчислени позиции върху скролбара,
  /// за проверка дали оценката на височините е стабилна/разумна.
  Widget _buildMatchTicksOverlay(BuildContext context) {
    if (!_searchOpen || _totalMatches == 0) return const SizedBox.shrink();
    final ratios = _allMatchRatios();
    if (ratios.isEmpty) return const SizedBox.shrink();
    return Positioned(
      // Съвпада с геометрията на Scrollbar-а: crossAxisMargin: 2,
      // mainAxisMargin: 4, thickness: _scrollThumb (10) — за да легнат
      // чертичките точно върху палеца/лентата, не встрани от нея.
      right: 2,
      // Тази лента се вижда САМО докато търсенето е отворено — тогава
      // NestedScrollView вече пази лентата с инструменти (44) + search
      // лентата (58) pinned отгоре, а тялото (и нативната му Scrollbar)
      // естествено започва под тях. Чертичките са отделен widget (не част
      // от тялото), затова трябва РЪЧНО да поемат същия отстъп, за да се
      // подравнят с реалната позиция на скролбара.
      top: 44 + 58 + 4,
      bottom: 4,
      width: _scrollThumb,
      child: IgnorePointer(
        child: CustomPaint(
          painter: _MatchTicksPainter(
            ratios: ratios,
            currentIndex: _currentMatch,
            hitColor: _tickHitColor,
            currentColor: _tickCurrentColor,
          ),
        ),
      ),
    );
  }

  Widget _buildSearchBar(BuildContext context) {
    final fg = AppBarTheme.of(context).foregroundColor ?? Colors.white;
    return Container(
      height: 58,
      // Дясната страна е малко по-широка — брояча (15/118) иначе се
      // "залепва" за чертичките на скролбара, разположени точно в тази зона.
      padding: const EdgeInsets.fromLTRB(12, 6, 17, 6),
      color: AppColors.toolbar,
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchCtrl,
              focusNode: _searchFocusNode,
              style: TextStyle(color: fg, fontSize: 16),
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _runSearch(),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Търсене в текста…',
                hintStyle: TextStyle(color: fg.withOpacity(0.5)),
                contentPadding: const EdgeInsets.symmetric(
                  vertical: 8,
                  horizontal: 10,
                ),
                filled: true,
                fillColor: Colors.black.withOpacity(0.15),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          RoundIconButton(
            icon: Icons.search,
            tooltip: 'Старт на търсенето',
            enabled: true,
            onTap: _runSearch,
            size: _searchBtnSize,
          ),
          const SizedBox(width: 16),
          RoundIconButton(
            icon: Icons.chevron_left,
            tooltip: 'Предишно съвпадение',
            enabled: _totalMatches > 0,
            onTap: () => _goToMatch(-1),
            size: _searchBtnSize,
          ),
          const SizedBox(width: 16),
          RoundIconButton(
            icon: Icons.chevron_right,
            tooltip: 'Следващо съвпадение',
            enabled: _totalMatches > 0,
            onTap: () => _goToMatch(1),
            size: _searchBtnSize,
          ),
          const SizedBox(width: 12),
          // Без фиксирана ширина — при повече цифри (напр. 1125/1130) текстът
          // просто заема колкото му трябва, вместо да се пренася на ред.
          Text(
            _totalMatches > 0 ? '${_currentMatch + 1}/$_totalMatches' : '0/0',
            maxLines: 1,
            softWrap: false,
            style: TextStyle(color: fg, fontSize: 13),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    // Прибираме евентуален висящ SnackBar веднага — иначе остава да виси и
    // след като този екран е затворен (ScaffoldMessenger е общ, не
    // локален за reader_screen). removeCurrentSnackBar (не hideCurrentSnackBar)
    // нарочно, за да изчезне мигновено, без анимация на излизане.
    _scaffoldMessenger?.removeCurrentSnackBar();
    _bookmarkIdleTimer?.cancel();
    // Ако имаше чакащ (недовършил 3-те си секунди) запис на шрифта, го
    // пускаме веднага сега — иначе промяната би се изгубила при излизане.
    if (_fontSizeSaveTimer != null) {
      _fontSizeSaveTimer!.cancel();
      _flushFontSizeSave();
    }
    _searchAnim.dispose();
    _searchCtrl.dispose();
    _searchFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // Съставянето на HTML, делението на буквица и региони, и декодирането на
  // всеки регион вече са ТОП-НИВО функции (виж _buildHtmlFor/_splitDropCap/
  // _prepareReaderContent по-горе) — изпълняват се ВЕДНЪЖ, във фонов isolate
  // (compute(), стартиран от initState), вместо да текат синхронно при
  // всеки build(). Виж коментара при полето _prepared по-долу.

  // ---------------------------------------------------------------
  // Линкове
  // ---------------------------------------------------------------

  Future<void> _onLinkTap(String? url) async {
    if (url == null) return;

    if (url.startsWith('saint://')) {
      final slug = url.substring('saint://'.length);
      final target = await widget.lookup(slug);
      if (!mounted) return;

      if (target == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Няма запис за този светия.')),
        );
        return;
      }
      Navigator.of(context).push(
        MaterialPageRoute(
        builder: (_) => target.hasLife
            ? ReaderScreen.life(texts: target, lookup: widget.lookup)
            : ReaderScreen.prayers(texts: target, lookup: widget.lookup),
        ),
      );
      return;
    }

    // Външен линк (https://…) — отваряме в браузъра по подразбиране
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Не може да се отвори: $url')));
    }
    // ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(url)));
  }

  // ---------------------------------------------------------------

  // Житие/Сказание/Служба/Тропар и кондак/… — ТУК е единственото място,
  // където се решава. Записва се в отметката такова, каквото е (виж
  // _BookmarkRecord.typeLabel), за да не се пресмята повторно в списъка
  // с отметки.
  /// Менюто "Още" — плъзва се отгоре надясно и се прибира по същия начин.
  /// Написано е ръчно (showGeneralDialog + SlideTransition), защото
  /// вграденият PopupMenuButton не позволява смяна на вида на анимацията.
  Future<void> _showMoreMenu() async {
    final topInset = MediaQuery.of(context).padding.top;
    final selected = await showGeneralDialog<String>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Затвори менюто',
      barrierColor: Colors.black26,
      transitionDuration: const Duration(milliseconds: 240),
      pageBuilder: (_, __, ___) => const SizedBox.shrink(),
      transitionBuilder: (ctx, anim, _, _) {
        final curved = CurvedAnimation(
          parent: anim,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return Stack(
          children: [
          Positioned(
            top: topInset + 44,
            right: 6,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, -0.35),
                end: Offset.zero,
              ).animate(curved),
              child: FadeTransition(
                opacity: curved,
                child: Material(
                  color: AppColors.backgroundCard,
                  elevation: 8,
                  borderRadius: BorderRadius.circular(14),
                  clipBehavior: Clip.antiAlias,
                  child: IntrinsicWidth(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Лента за затваряне най-отгоре — менюто се
                        // прибира и с тап встрани, но стрелката прави
                        // изхода очевиден.
                        Align(
                          alignment: Alignment.centerRight,
                          child: InkWell(
                            onTap: () => Navigator.of(ctx).pop(),
                            customBorder: const CircleBorder(),
                            child: const Padding(
                              padding: EdgeInsets.fromLTRB(14, 10, 14, 6),
                                child: Icon(
                                  Icons.arrow_forward,
                                  size: 22,
                                  color: AppColors.textSecondary,
                                ),
                            ),
                          ),
                        ),
                        const Divider(
                            height: 1,
                            color: AppColors.sectionDivider,
                          ),
                          _moreMenuItem(
                            ctx,
                            Icons.bookmarks_outlined,
                            'Списък с отметки',
                            'bookmarks',
                          ),
                          _moreMenuItem(
                            ctx,
                            Icons.picture_as_pdf_outlined,
                            'Сподели като PDF',
                            'share_pdf',
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          ],
        );
      },
    );
    if (!mounted || selected == null) return;
    if (selected == 'bookmarks') {
      Navigator.of(context).push(
        MaterialPageRoute(
        builder: (_) => BookmarksListScreen(lookup: widget.lookup),
        ),
      );
    } else if (selected == 'share_pdf') {
      _shareAsPdf();
    }
  }

  Widget _moreMenuItem(
    BuildContext ctx,
    IconData icon,
    String label,
    String value,
  ) {
    return InkWell(
      onTap: () => Navigator.of(ctx).pop(value),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            // Пропорция икона/текст като в главното меню (app_drawer.dart)
            // — това също е меню, не дребен списъчен ред.
            Icon(icon, size: 22, color: AppColors.textSecondary),
            const SizedBox(width: 12),
            Text(
              label,
                style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Сглобява PDF (A4) от същия HTML, който се показва в четеца, и отваря
  /// стандартния диалог за споделяне. Виж pdf_export.dart за оформлението.
  Future<void> _shareAsPdf() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      // Заглавието идва от името на светията, а тялото — от вече готовия
      // HTML; така PDF-ът съдържа точно това, което потребителят чете.
      await sharePdf(
        title: widget.texts.name,
        bodyHtml: _buildPdfHtmlFor(widget._mode, widget.texts),
        fileName: '${_typeLabel.toLowerCase()} - ${widget.texts.name}.pdf',
        // Буквица САМО за житието — точно както в четеца. Тропарите,
        // кондаците и службата започват без водеща заглавна буква.
        withDropCap: widget._mode == _ReaderMode.life,
        strongIsWine: widget._mode == _ReaderMode.sluzhba,
        prayerLike: widget._mode != _ReaderMode.life,
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Неуспешно създаване на PDF: $e')),
      );
    }
  }

  String get _typeLabel => widget._mode == _ReaderMode.life
      ? (widget.lifeTitle ?? 'Житие')
      : widget._mode == _ReaderMode.sluzhba
          ? 'Служба'
          : prayersTitleFor(widget.texts);

  // Палитрата на четеца — независима от темата на приложението.
  Color get _bg =>
      _darkMode ? const Color(0xFF121212) : const Color(0xFFF5E6C5);
  Color get _ink =>
      _darkMode ? const Color(0xFFE6E1D8) : const Color(0xFF1A1A1A);
  Color get _dim =>
      _darkMode ? const Color(0xFF9A948A) : const Color(0xFF6B675F);
  Color get _wine =>
      _darkMode ? const Color(0xFFA0555B) : const Color(0xFFB83333);
  //Color get _wine => _darkMode ? const Color(0xFFA84444) : const Color(0xFF7A1F1F);

  /// Показва се докато _prepared е null (isolate-ът още работи) — нарочно
  /// евтин build (само лента + spinner), за да не забавя push-а на екрана.
  Widget _buildLoadingScaffold(BuildContext context, String title) {
    return Scaffold(
      backgroundColor: AppColors.toolbar,
      body: SafeArea(
        top: true,
        child: Container(
          color: _bg,
          child: Column(
            children: [
              AppBar(
                primary: false,
                backgroundColor: AppColors.toolbar,
                toolbarHeight: 44,
                title: Text(title),
              ),
              Expanded(
                child: Center(child: CircularProgressIndicator(color: _dim)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = _typeLabel;

    // Тежката подготовка (HTML, буквица, региони — виж _prepareReaderContent)
    // още работи във фонов isolate — показваме лек spinner, вместо да
    // блокираме push-а на екрана и анимацията на тапа, докато чакаме.
    final prepared = _prepared;
    if (prepared == null) {
      return _buildLoadingScaffold(context, title);
    }
    final hasOwnTitle = prepared.hasOwnTitle;
    final dropCap = prepared.dropCap;
    final regions = prepared.regions;
    final hasGap = prepared.hasGap;

    // Височина на водещата буква ≈ 5–6 реда основен текст.
    final lineHeightPx = _fontSize * _lineHeight; //1.5;
    final dropCapSize = lineHeightPx * 5.5 * 0.82; // корекция за ascender

    if (_regionKeys.length != regions.length) {
      _regionKeys = List.generate(regions.length, (_) => GlobalKey());
    }
    // Ширината на СЪДЪРЖАНИЕТО, а не на екрана: текстът стои в SafeArea и
    // в хоризонтално положение изрезът на камерата отнема лента отстрани.
    // Без това измерването на височините ставаше на по-широко от реалното,
    // текстът поемаше ред повече и не се събираше в отредената си кутия
    // (жълтата лента "BOTTOM OVERFLOWED" при смяна на шрифта в landscape).
    _viewportWidth = MediaQuery.sizeOf(context).width -
        MediaQuery.paddingOf(context).horizontal;
    // Реалните измервания важат само за ширината, при която са направени
    // (напр. завъртане на устройството би променила пренасянето на реда).
    // Толеранс, не точно равенство — MediaQuery може да върне
    // микроскопично различна ширина между кадри (закръгляване, скролбар,
    // който се появява/изчезва), което иначе анулира измерването ПОСТОЯННО
    // и никога не му позволява да се задържи.
    if (_realItemExtents != null &&
        (_measuredForWidth == null ||
            (_measuredForWidth! - _viewportWidth).abs() > 2.0)) {
      _realCumulativeHeights = null;
      _realItemExtents = null;
      _measuring = false;
    }
    // Кумулативни оценени височини — виж _estimateRegionHeight() и
    // _EstimatingListDelegate по-долу. Плоският текст/броят линкове идват
    // вече кеширани от _prepared (изчислени веднъж, във фоновия isolate) —
    // тук остава само евтината аритметика, затова е безопасно да тече на
    // всеки build() (тема, търсене, смяна на шрифт).
    _cumulativeHeights = List.filled(regions.length, 0.0);
    double running = 0;
    for (int i = 0; i < regions.length; i++) {
      running += _estimateRegionHeight(
        prepared.regionPlainTexts[i],
        _fontSize,
        _lineHeight,
        _viewportWidth,
        linkCount: prepared.regionLinkCounts[i],
      );
      _cumulativeHeights[i] = running;
    }
    final foldedQuery = _committedQuery.isEmpty
        ? ''
        : _fold(_committedQuery).text;

    int matchOffset = 0;
    final regionWidgets = <Widget>[];
    for (int i = 0; i < regions.length; i++) {
      final r = regions[i];
      final count = i < _regionMatchCounts.length ? _regionMatchCounts[i] : 0;
      final key = _regionKeys[i];
      if (r.isHtml) {
        final data = foldedQuery.isEmpty
            ? r.content
            : _highlightHtml(
                r.content,
                foldedQuery,
                matchOffset,
                _currentMatch,
              );
        regionWidgets.add(
          KeyedSubtree(
          key: key,
          child: Html(
            data: data,
            onLinkTap: (url, attributes, element) => _onLinkTap(url),
            style: _htmlStyles(context),
            extensions: _tipikonExtensions,
          ),
          ),
        );
      } else {
        regionWidgets.add(
          KeyedSubtree(
          key: key,
          child: _DropCapParagraph(
            dropCap: dropCap,
            dropCapSize: dropCapSize,
            lineHeight: lineHeightPx,
            lineFactor: _lineHeight,
            firstParagraph: r.content,
            secondParagraph: r.second,
            fontSize: _fontSize,
            capColor: _wine,
            inkColor: _ink,
            linkColor: AppColors.sectionTitle,
            onLinkTap: _onLinkTap,
            searchQuery: foldedQuery,
            firstGlobalMatchIndex: matchOffset,
            currentGlobalMatch: _currentMatch,
            hitColor: _hitColor,
            hitCurrentColor: _hitCurrentColor,
          ),
          ),
        );
      }
      matchOffset += count;
    }
    // Разстояние след заглавната част (преди буквицата), ако имаше before-блок
    // (hasGap идва вече от _prepared — виж горе).
    if (hasGap) {
      regionWidgets.insert(1, const SizedBox(height: _titleGap));
    }

    final titleWidget = hasOwnTitle
        ? null
        : Padding(
            padding: const EdgeInsets.only(top: 10, bottom: _titleGap),
            child: Text(
              widget.texts.name,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: _titleFamily,
                fontSize: _fontSize + 9,
                height: 1.25,
                color: _ink,
              ),
            ),
          );
    final sliverChildren = <Widget>[
      if (titleWidget != null) titleWidget,
      ...regionWidgets,
    ];

    // --- Фоново реално измерване (виж коментара при полетата по-горе) —
    // построяваме СЪЩОТО съдържание веднъж в невидим (Offstage) слой, за
    // да прочетем реалните му височини и еднократно да превключим към
    // SliverVariedExtentList, вместо да разчитаме вечно на хюристиката.
    Widget? measurementTree;
    if (_realItemExtents == null) {
      if (_measureKeys.length != regions.length) {
        _measureKeys = List.generate(regions.length, (_) => GlobalKey());
      }
      if (!_measuring) {
        _measuring = true;
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _finishMeasuring(regions.length, hasOwnTitle, hasGap),
        );
      }
      final measureChildren = <Widget>[
        if (titleWidget != null)
          KeyedSubtree(key: _titleMeasureKey, child: titleWidget),
      ];
      for (int i = 0; i < regions.length; i++) {
        final r = regions[i];
        if (r.isHtml) {
          measureChildren.add(
            KeyedSubtree(
            key: _measureKeys[i],
            child: Html(
              data: r.content,
              style: _htmlStyles(context),
              extensions: _tipikonExtensions,
            ),
            ),
          );
        } else {
          measureChildren.add(
            KeyedSubtree(
            key: _measureKeys[i],
            child: _DropCapParagraph(
              dropCap: dropCap,
              dropCapSize: dropCapSize,
              lineHeight: lineHeightPx,
              lineFactor: _lineHeight,
              firstParagraph: r.content,
              secondParagraph: r.second,
              fontSize: _fontSize,
              capColor: _wine,
              inkColor: _ink,
              linkColor: AppColors.sectionTitle,
              onLinkTap: _onLinkTap,
            ),
            ),
          );
        }
      }
      if (hasGap) {
        measureChildren.insert(
          titleWidget != null ? 2 : 1,
          const SizedBox(height: _titleGap),
        );
      }
      measurementTree = Offstage(
        offstage: true,
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: (_viewportWidth - 32).clamp(100.0, 2000.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: measureChildren,
            ),
          ),
        ),
      );
    }

    final contentSliver = _realItemExtents != null
        ? SliverVariedExtentList(
            delegate: _ExactListDelegate(
              sliverChildren,
              totalExtent: _realItemExtents!.fold(0.0, (a, b) => a + b),
            ),
            itemExtentBuilder: (index, dimensions) {
              final extents = _realItemExtents!;
              return index < extents.length ? extents[index] : 100.0;
            },
          )
        : SliverList(
            delegate: _EstimatingListDelegate(
              sliverChildren,
              cumulativeHeights: _cumulativeHeights,
              indexOffset: hasOwnTitle ? 0 : 1,
            ),
          );

    // Действията в лентата — общи за ДВАТА режима (виж по-долу): при четене
    // се рендват вътре в плаващ SliverAppBar, при търсене — в обикновен,
    // фиксиран AppBar. Изчисляваме ги веднъж тук, за да не дублираме кода.
    final headerActions = <Widget>[
            // Търсене — плосък стил (като в search_screen/main.dart), не
            // outline-кръга на +/-. "Хлътнало" състояние = запълнен кръг
            // зад иконата, докато лентата за търсене е отворена.
            Tooltip(
              message: 'Търсене в текста',
              child: InkWell(
                onTap: _toggleSearch,
                customBorder: const CircleBorder(),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: _btnSize + 8,
                  height: _btnSize + 8,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _searchOpen
                  ? (AppBarTheme.of(context).foregroundColor ?? Colors.white)
                            .withOpacity(0.28)
                        : Colors.transparent,
                  ),
                  child: Icon(
                    Icons.search,
                    size: 24,
              color: AppBarTheme.of(context).foregroundColor ?? Colors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16), // Разстояние между лупата и Тогъл
            // Тогъл на темата: кръг, разделен вертикално (първа четвъртина)
            Tooltip(
              message: 'Светла/тъмна тема',
              child: InkWell(
                onTap: () => setState(() => _darkMode = !_darkMode),
                customBorder: const CircleBorder(),
                child: Container(
                  width: _btnSize,
                  height: _btnSize,
                  alignment: Alignment.center,
                  child: CustomPaint(
                    size: const Size(_btnSize - 0, _btnSize - 0),
                    painter: _HalfMoonPainter(
                outline:
                    AppBarTheme.of(context).foregroundColor ?? Colors.white,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 18), // Разстояние между Тогъл и (-)
            RoundIconButton(
              icon: Icons.remove,
              tooltip: 'По-дребен шрифт',
              enabled: _fontSize > _min,
              onTap: () => _bump(-_step),
              size: _btnSize,
            ),
            const SizedBox(width: 18), // Разстояние между (-) и (+)
            RoundIconButton(
              icon: Icons.add,
              tooltip: 'По-едър шрифт',
              enabled: _fontSize < _max,
              onTap: () => _bump(_step),
              size: _btnSize,
            ),
            const SizedBox(width: 18), // Разстояние между (+) и отметката
            // Отметка — плосък стил (като лупата). Виж _toggleBookmark и
            // _BookmarkStore по-горе.
            Tooltip(
              message: _isBookmarked ? 'Премахни отметката' : 'Отметни тук',
              child: InkWell(
                onTap: _toggleBookmark,
                customBorder: const CircleBorder(),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: _btnSize + 8,
                  height: _btnSize + 8,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _isBookmarked
                  ? (AppBarTheme.of(context).foregroundColor ?? Colors.white)
                            .withOpacity(0.28)
                        : Colors.transparent,
                  ),
                  child: Icon(
                    _isBookmarked ? Icons.bookmark : Icons.bookmark_border,
                    size: 24,
              color: AppBarTheme.of(context).foregroundColor ?? Colors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10), // По-тясно — менюто е "приятел" на отметката
            // Контекстно меню — най-вдясно. TODO: истинско съдържание
            // (списъци с отметки, преименуване и т.н.).
            // Собствено меню вместо PopupMenuButton: искахме то да се
            // ПЛЪЗГА (както drawer), а вграденият popup има само своята
            // анимация на разрастване, която не се сменя.
            Tooltip(
              message: 'Още',
              child: InkWell(
                onTap: _showMoreMenu,
                customBorder: const CircleBorder(),
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Icon(
                    Icons.more_vert,
                    size: 24,
              color: AppBarTheme.of(context).foregroundColor ?? Colors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 2), // Разстояние до десния край
          ];

    // Търсещата лента (плъзгаща се отгоре-надолу с анимация) — обща за двата
    // варианта на лентата (SliverAppBar/AppBar) по-долу, затова
    // параметризирана по текущата стойност на анимацията.
    PreferredSizeWidget? searchBarBottom(double value) {
      if (value == 0) return null;
      return PreferredSize(
        preferredSize: Size.fromHeight(58 * value),
        child: ClipRect(
          child: Align(
            alignment: Alignment.topCenter,
            heightFactor: value,
            child: _buildSearchBar(context),
          ),
        ),
      );
    }

    // РЕЖИМ НА ЧЕТЕНЕ: лентата е sliver вътре в CustomScrollView — floating
    // (скрива се при скрол надолу, връща се плавно при скрол нагоре).
    final sliverHeader = AnimatedBuilder(
      animation: _searchAnim,
      builder: (context, _) => SliverAppBar(
        primary: false,
        floating: true,
        snap: true,
        pinned: false,
        backgroundColor: AppColors.toolbar,
        toolbarHeight: 44,
        title: Text(title),
        actions: headerActions,
        bottom: searchBarBottom(_searchAnim.value),
      ),
    );

    // РЕЖИМ НА ТЪРСЕНЕ: обикновен (НЕ-sliver) AppBar, фиксиран най-отгоре в
    // Column — напълно извън всякаква Scrollable/sliver координация, затова
    // няма как да "потрепва" или да обръща посоката на палеца при скрол.
    final fixedHeader = AnimatedBuilder(
      animation: _searchAnim,
      // AppBar, ползван директно като дете на Column (извън слота
      // Scaffold.appBar), НЕ получава сам фиксирана височина отвън — тя
      // идва нормално от Scaffold. Без нея вътрешната му Column получава
      // неограничена височина и хвърля RenderFlex/unbounded assertion.
      // SizedBox тук изрично задава височината = preferredSize.
      builder: (context, _) => SizedBox(
        height: 44 + 58 * _searchAnim.value,
        child: AppBar(
          primary: false,
          backgroundColor: AppColors.toolbar,
          toolbarHeight: 44,
          title: Text(title),
          actions: headerActions,
          bottom: searchBarBottom(_searchAnim.value),
        ),
      ),
    );

    // Скролируемото тяло — самò по себе си, БЕЗ лентата с инструменти.
    // includeHeaderSliver=true (режим на четене) добавя sliverHeader като
    // ПЪРВИ sliver в СЪЩИЯ CustomScrollView, за да работи floating
    // поведението естествено (лентата е част от скрола, който контролира).
    // При търсене (includeHeaderSliver=false) тялото е самостоятелно, под
    // отделния fixedHeader — виж mainContent по-долу.
    Widget buildScrollableBody({required bool includeHeaderSliver}) {
      return ScrollbarTheme(
        // Палецът следва темата на ЧЕТЕЦА, не на приложението.
        data: ScrollbarThemeData(
          thumbColor: WidgetStatePropertyAll(_dim.withOpacity(0.44)),
          radius: const Radius.circular(5),
          thickness: const WidgetStatePropertyAll(_scrollThumb),
          // Палецът не бива да става твърде къс при дълго житие —
          // иначе е неуловим с пръст.
          minThumbLength: 48,
          crossAxisMargin: 2,
          mainAxisMargin: 4,
        ),
        child: Scrollbar(
          controller: _scrollController,
          // Постоянно видим палец, докато ИМА чертички за гледане —
          // от старта на търсенето с поне 1 намерен резултат, до
          // затварянето му. Иначе чертичките се виждат, а палецът
          // (референтната точка спрямо тях) избледнява — безсмислено.
          thumbVisibility: _searchOpen && _totalMatches > 0,
          // interactive: true разрешава ВЛАЧЕНЕ на палеца с пръст. Без него
          // скролбарът е само индикатор. Флагът разширява и зоната за
          // докосване отвъд видимата ширина на палеца.
          interactive: true,
          child: Theme(
            data: Theme.of(context).copyWith(
              textSelectionTheme: TextSelectionThemeData(
                selectionColor: AppColors.sectionTitle.withOpacity(0.35),
                selectionHandleColor: AppColors.sectionTitle,
                cursorColor: AppColors.sectionTitle,
              ),
            ),
            child: SelectionArea(
              child: CustomScrollView(
                controller: _scrollController,
                slivers: [
                  if (includeHeaderSliver) sliverHeader,
                  SliverPadding(
                    // Долен отстъп: докато режимът е хюристичен (преди
                    // реалното измерване), floating SliverAppBar може да
                    // "открадне" скрол-делта близо до края — луфтът пази
                    // от това. Веднъж измерено точно, вече не е нужен,
                    // но оставяме малък за спокойствие.
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 60),
                    sliver: contentSliver,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    // Двете СТРУКТУРНО различни подредби (виж коментара при _scrollController
    // по-горе за как офсетът се пренася безшумно между тях при превключване):
    //  - четене: единствен CustomScrollView, лентата е floating sliver в него;
    //  - търсене: фиксиран AppBar отгоре + отделен скролируем Expanded отдолу,
    //    напълно изолирани едно от друго — без sliver-координация между
    //    външна и вътрешна скрол зона, която причиняваше потрепването и
    //    грешната посока на палеца.
    final mainContent = _searchOpen
        ? Column(
            children: [
              fixedHeader,
              Expanded(child: buildScrollableBody(includeHeaderSliver: false)),
            ],
          )
        : buildScrollableBody(includeHeaderSliver: true);

    return PopScope(
      // Прихваща момента на самото натискане на "назад" — синхронно, преди
      // анимацията на прехода изобщо да е започнала. dispose() (виж по-горе)
      // също чисти SnackBar-а, но той се изпълнява едва СЛЕД анимацията;
      // тук го правим веднага, за да няма никакъв прозорец, в който
      // SnackBar-ът да увисне "осиротял" по време на прехода.
      onPopInvokedWithResult: (didPop, result) {
        _scaffoldMessenger?.removeCurrentSnackBar();
      },
      child: Scaffold(
        backgroundColor: AppColors.toolbar,
        body: SafeArea(
          // top: false — SliverAppBar/AppBar сам отчита статус лентата; ако
          // SafeArea я поеме и той, отстъпът горе се удвоява.
          top: true,
          child: Container(
            color: _bg,
            child: Stack(
              children: [
                mainContent,
                if (measurementTree != null) measurementTree,
                _buildMatchTicksOverlay(context),
                if (_showResumePrompt)
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 16,
                    child: SafeArea(
                      top: false,
                      child: _ResumePrompt(
                        background: AppColors.backgroundCard,
                        ink: _ink,
                        dim: _dim,
                        onJump: _onResumePromptJump,
                        onDeleted: _onResumePromptDeleted,
                        onClosed: _onResumePromptClosed,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Знакът на Типикона се РИСУВА толкова пъти по-едро от текста…
  static const double _tipikonSignScale = 1.4;

  /// …но ЗАЕМА само толкова — точно колкото е височината на реда.
  ///
  /// Двете нарочно се различават. Вграден в абзаца, знакът е inline елемент:
  /// ако кутията му е по-висока от реда, редът се разпъва и разстоянията
  /// между абзаците излизат неравни (само редовете СЪС знак стават
  /// по-високи). Затова кутията остава колкото реда, а рисунката се пуска да
  /// излезе извън нея през OverflowBox — подредбата не забелязва нищо, а
  /// знакът се вижда едър. Свободното място отгоре и отдолу го дават
  /// полетата между абзаците.
  static const double _tipikonSignBox = _lineHeight;

  /// Знаците на Типикона, вградени в текста като `<znak n="1">`…`<znak n="5">`.
  /// Ползват се в справочната статия "Знаците от Типикона": там оригиналът
  /// ги описваше с текстови заместители ((+), +), +, (:· …), а два от петте
  /// заместителя СЪВПАДАХА и се различаваха само по цвят — разликата се
  /// губеше напълно. Тук се рисуват същите SVG-та, които стоят и до
  /// светиите в календара (виж AppIcons.forRank), в цветовете на четеца.
  List<HtmlExtension> get _tipikonExtensions => [
        TagExtension(
          tagsToExtend: {'znak'},
          builder: (ctx) {
            final rank = int.tryParse(
                    ctx.attributes['n'] ?? '') ??
                6;
            final (path, _) = AppIcons.forRank(rank);
            if (path == null) return const SizedBox.shrink();
            // Ранг 5 (шестерична) е черният знак — останалите са червени.
            final color = rank == 5 ? _ink : _wine;
            // Двата размера са ВРЪЗАНИ за _fontSize, за да растат и намаляват
            // заедно с текста от бутоните −/+ (виж _tipikonSignBox защо
            // кутията е по-малка от рисунката).
            final box = _fontSize * _tipikonSignBox;
            final draw = _fontSize * _tipikonSignScale;
            // Рисунката се излива извън кутията и НАСТРАНИ, не само нагоре и
            // надолу — затова изяждаше интервала преди тирето след себе си.
            // Отстъпът покрива преливането ((draw−box)/2) плюс нормалното
            // разстояние между знак и дума, и расте заедно с шрифта.
            final side = (draw - box) / 2 + _fontSize * 0.34;
            return Padding(
              padding: EdgeInsets.symmetric(horizontal: side),
              child: SizedBox(
                width: box,
                height: box,
                child: OverflowBox(
                  maxWidth: draw,
                  maxHeight: draw,
                  child: SvgPicture.asset(
                    path,
                    width: draw,
                    height: draw,
                    colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
                  ),
                ),
              ),
            );
          },
        ),
      ];

  Map<String, Style> _htmlStyles(BuildContext context) {
    return {
      // flutter_html обвива съдържанието в имплицитни <html> и <body> с
      // браузърни подразбирания за margin/padding. Тях ги нулираме, за да
      // ляга HTML текстът точно на същата ширина като първия абзац (той се
      // рендва ръчно в _DropCapParagraph и няма такива отстъпи).
      'html': Style(margin: Margins.zero, padding: HtmlPaddings.zero),
      'body': Style(margin: Margins.zero, padding: HtmlPaddings.zero),
      'p': Style(
        fontFamily: _bodyFamily,
        fontSize: FontSize(_fontSize),
        lineHeight: const LineHeight(_lineHeight),
        margin: Margins.only(top: 8, bottom: 8),
        textAlign: TextAlign.justify,
        color: _ink,
      ),
      // Двете кутии около буквицата: като обикновен абзац, но без полета —
      // отстоянията там се мерят в редове и се задават отвън.
      '.dropcap': Style(
        fontFamily: _bodyFamily,
        fontSize: FontSize(_fontSize),
        lineHeight: const LineHeight(_lineHeight),
        margin: Margins.zero,
        padding: HtmlPaddings.zero,
        textAlign: TextAlign.justify,
        color: _ink,
      ),
      '.dropcap-rest': Style(
        fontFamily: _bodyFamily,
        fontSize: FontSize(_fontSize),
        lineHeight: const LineHeight(_lineHeight),
        margin: Margins.only(top: 2),
        padding: HtmlPaddings.zero,
        textAlign: TextAlign.justify,
        color: _ink,
      ),
      'h3': Style(
        fontFamily: _titleFamily, // _bodyFamily,
        fontSize: FontSize(_fontSize + 10),
        lineHeight: const LineHeight(_lineHeight),
        fontWeight: FontWeight.normal,
        textAlign: TextAlign.center,
        margin: Margins.only(
          top: 18,
          bottom: 0,
        ), // bottom се управлява от _titleGap
        color: _ink,
      ),
      // В службата <strong> носи богослужебните указания ("На велицей
      // вечерни", "стихиры, глас 2", "Подобен:") — по традиция в червено.
      // В житието същият таг е обикновено ударение → мастилен цвят.
      'strong': Style(
        color: widget._mode == _ReaderMode.sluzhba ? _wine : _ink,
      ),
      '.csl': Style(
        fontFamily: _bodyFamily,
        fontSize: FontSize(_fontSize + 0.5),
        lineHeight: const LineHeight(1.3),
        color: _ink,
      ),
      '.prayerhead': Style(
        fontFamily: _bodyFamily,
        fontSize: FontSize(_fontSize + 1),
        fontWeight: FontWeight.w600,
        margin: Margins.only(top: 18, bottom: 4),
        color: _wine,
      ),
      '.trans': Style(
        fontFamily: _bodyFamily,
        fontSize: FontSize(_fontSize - 1),
        fontStyle: FontStyle.italic,
        color: _dim,
        margin: Margins.only(bottom: 16),
      ),
      '.translabel': Style(
        fontWeight: FontWeight.w600,
        fontStyle: FontStyle.normal,
        color: _dim, //_ink,
      ),
      '.source': Style(
        fontFamily: _bodyFamily,
        fontSize: FontSize(_fontSize - 2),
        fontStyle: FontStyle.italic,
        color: _dim,
        margin: Margins.only(top: 24),
      ),
      // Курсивен абзац, пропуснат за буквица (виж _splitDropCap) — центриран.
      '.italic-center': Style(textAlign: TextAlign.center),
      // Линковете: синьото на секциите от дневния изглед, не лилаво.
      'a': Style(
        color: AppColors.sectionTitle,
        textDecoration: TextDecoration.none,
      ),
      // Маркиране на съвпаденията от търсенето — виж _highlightHtml().
      '.hit': Style(backgroundColor: _hitColor),
      '.hit-current': Style(backgroundColor: _hitCurrentColor),
    };
  }
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
class _DropCapParagraph extends StatefulWidget {
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

  const _DropCapParagraph({
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
  State<_DropCapParagraph> createState() => _DropCapParagraphState();
}

class _DropCapParagraphState extends State<_DropCapParagraph> {
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
          fontFamily: _bodyFamily,
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
                        fontFamily: _dropCapFamily,
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

/// Долна подкана "продължи от последната позиция" — показва се при отваряне
/// на четиво със запазена отметка. Две състояния:
///  - "пълно": обяснение + брояч 5→0 + бутон "иди" + бутон "пауза" (ако
///    броячът стигне 0 без реакция, автоматично скача на позицията);
///  - "slim" (на пауза): един ред, полупрозрачен, безсрочен, само бутоните.
/// Swipe на "пълно" пита за потвърждение преди да изтрие отметката; swipe
/// на "slim" просто се "събужда" обратно към пълно с пресен брояч.
class _ResumePrompt extends StatefulWidget {
  final Color background;
  final Color ink;
  final Color dim;
  final VoidCallback onJump;
  final VoidCallback onDeleted;
  final VoidCallback onClosed;

  const _ResumePrompt({
    required this.background,
    required this.ink,
    required this.dim,
    required this.onJump,
    required this.onDeleted,
    required this.onClosed,
  });

  @override
  State<_ResumePrompt> createState() => _ResumePromptState();
}

class _ResumePromptState extends State<_ResumePrompt> {
  static const int _countdownStart = 10;
  int _secondsLeft = _countdownStart;
  bool _paused = false;
  Timer? _timer;
  bool _closing = false; // пази от двойно извикване на onJump/onClosed

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), _tick);
  }

  void _tick(Timer t) {
    if (!mounted) {
      t.cancel();
      return;
    }
    if (_secondsLeft <= 0) {
      t.cancel();
      _jump();
      return;
    }
    setState(() => _secondsLeft--);
  }

  void _startCountdown() {
    _timer?.cancel();
    setState(() => _secondsLeft = _countdownStart);
    _timer = Timer.periodic(const Duration(seconds: 1), _tick);
  }

  void _togglePause() {
    setState(() => _paused = !_paused);
    if (_paused) {
      _timer?.cancel();
    } else {
      _startCountdown();
    }
  }

  void _jump() {
    if (_closing) return;
    _closing = true;
    _timer?.cancel();
    widget.onJump();
    widget.onClosed();
  }

  Future<bool> _confirmDelete() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'Заличаване на отметката',
          style: TextStyle(fontSize: 20),
        ),
        content: const Text(
            'Наистина ли искате да ЗАЛИЧИТЕ запазената отметка за това четиво?',
          style: TextStyle(fontSize: 16),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Не', style: TextStyle(fontSize: 20)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Да', style: TextStyle(fontSize: 20)),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Widget _circleButton({
    required IconData icon,
    required VoidCallback onTap,
    bool active = false,
  }) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 34,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: active ? widget.ink : Colors.transparent,
          border: Border.all(color: widget.ink, width: 1.3),
        ),
        child: Icon(
          icon,
          size: 18,
          color: active ? widget.background : widget.ink,
        ),
      ),
    );
  }

  Widget _buildFull() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Имате запазена позиция в това четиво.',
                style: TextStyle(color: widget.ink, fontSize: 18),
              ),
            ),
            const SizedBox(width: 8),
            _circleButton(icon: Icons.arrow_forward, onTap: _jump),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: Text(
                'Отваря се след $_secondsLeft…',
                style: TextStyle(color: widget.dim, fontSize: 13),
              ),
            ),
            Text('Изчакай', style: TextStyle(color: widget.dim, fontSize: 13)),
            const SizedBox(width: 6),
            _circleButton(icon: Icons.pause, onTap: _togglePause),
          ],
        ),
      ],
    );
  }

  Widget _buildSlim() {
    return Row(
      children: [
        _circleButton(icon: Icons.pause, onTap: _togglePause, active: true),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            'Отиди на отметката',
              textAlign: TextAlign.right,
            style: TextStyle(color: widget.ink, fontSize: 14),
          ),
        ),
        const SizedBox(width: 10),
        _circleButton(icon: Icons.arrow_forward, onTap: _jump),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final card = Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: widget.background,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(color: Colors.black45, blurRadius: 8, offset: Offset(0, 2)),
        ],
      ),
      child: _paused ? _buildSlim() : _buildFull(),
    );

    return Dismissible(
      key: ValueKey(_paused ? 'resume-slim' : 'resume-full'),
      direction: DismissDirection.horizontal,
      confirmDismiss: (_) async {
        if (_paused) {
          // Swipe на slim = "събуди се" — обратно към пълно с пресен брояч.
          _togglePause();
          return false;
        }
        // Спираме брояча веднага — иначе докато диалогът за потвърждение
        // виси, той продължава да тече във фонов режим и може да "скочи"
        // към отметката точно докато потребителят чете диалога.
        _timer?.cancel();
        final confirmed = await _confirmDelete();
        if (confirmed) {
          widget.onDeleted();
          widget.onClosed();
          return true;
        }
        _startCountdown(); // "Не" -> нулира брояча отначало
        return false;
      },
      child: card,
    );
  }
}

/// Знак "първа четвъртина на луната": кръг с контур, вертикално разделен —
/// едната половина плътна (бяла), другата празна.
class _HalfMoonPainter extends CustomPainter {
  final Color outline;
  const _HalfMoonPainter({required this.outline});

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2 - 1;

    // Дясната половина — плътна
    final fill = Paint()
      ..color = outline
      ..style = PaintingStyle.fill;
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r),
      -1.5707963, // -90° (горе)
      3.1415926,  // 180° по часовниковата → дясната половина
      true,
      fill,
    );

    // Контурът на целия кръг
    final stroke = Paint()
      ..color = outline
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    canvas.drawCircle(c, r, stroke);
  }

  @override
  bool shouldRepaint(covariant _HalfMoonPainter old) => old.outline != outline;
}

/// Чертички за позициите на съвпаденията върху лентата (виж
/// _buildMatchTicksOverlay). ratios са стойности 0..1 — дял от цялата
/// (оценена) дължина на текста.
class _MatchTicksPainter extends CustomPainter {
  final List<double> ratios;
  final int currentIndex;
  final Color hitColor;
  final Color currentColor;

  const _MatchTicksPainter({
    required this.ratios,
    required this.currentIndex,
    required this.hitColor,
    required this.currentColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final hitPaint = Paint()
      ..color = hitColor
      ..strokeWidth = 2;
    // Първо всички жълти чертички...
    for (int i = 0; i < ratios.length; i++) {
      final y = (ratios[i].clamp(0.0, 1.0) * size.height).clamp(
        0.0,
        size.height,
      );
      canvas.drawLine(Offset(0, y), Offset(size.width, y), hitPaint);
    }
    // ...после ОТДЕЛНО оранжевата, рисувана НАПОСЛЕДЪК — гарантирано най-
    // отгоре в z-реда, дори когато няколко жълти са плътно една до друга и
    // иначе биха я скрили.
    if (currentIndex >= 0 && currentIndex < ratios.length) {
      final currentPaint = Paint()
        ..color = currentColor
        ..strokeWidth = 3;
      final y = (ratios[currentIndex].clamp(0.0, 1.0) * size.height).clamp(
        0.0,
        size.height,
      );
      canvas.drawLine(Offset(0, y), Offset(size.width, y), currentPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _MatchTicksPainter old) =>
      old.ratios != ratios || old.currentIndex != currentIndex;
}

/// Списък с всички запазени отметки в приложението (виж _BookmarkStore) —
/// отваря се от менюто с трите точки в reader_screen. Всеки ред: заглавие
/// (натискане → отваря четивото; native InkWell "присветване" за feedback)
/// + тип (Житие/Сказание/Тропар и кондак/…, вече готов от _BookmarkRecord —
/// виж коментара там за защо не се пресмята повторно тук) + кошче вдясно
/// за единично изтриване. "Изтрий всички" — иконка в лентата отгоре.
class BookmarksListScreen extends StatefulWidget {
  final SaintLookup lookup;
  const BookmarksListScreen({super.key, required this.lookup});

  @override
  State<BookmarksListScreen> createState() => _BookmarksListScreenState();
}

class _BookmarksListScreenState extends State<BookmarksListScreen>
    with SingleTickerProviderStateMixin {
  List<(_BookmarkId, _BookmarkRecord)>? _items;

  /// Избраните редове. Режимът "избиране" се пази с ОТДЕЛЕН флаг, а не се
  /// познава по това дали има избрани: докосването върху маркиран ред го
  /// размаркира, та човек лесно стига до нула избрани насред работата си —
  /// а тогава изхвърлянето от режима значи ново задържане на пръста.
  /// Излиза се само нарочно: с ✕, с "назад" или след изтриване.
  final _selected = <_BookmarkId>{};
  bool _selectionMode = false;

  /// Копчето горе не сменя иконката си, когато влезем в режим "избиране" —
  /// вместо това тя леко се разтърсва и наедрява. Подсещането се повтаря,
  /// ако човек се позамисли и не предприеме нищо: таймерът се вдига наново
  /// при всяко докосване, така че разтърсването идва само след затишие.
  late final AnimationController _nudge = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );
  Timer? _nudgeTimer;
  static const _nudgePause = Duration(seconds: 4);

  void _toggle(_BookmarkId id) {
    setState(() {
      _selectionMode = true;
        if (!_selected.remove(id)) _selected.add(id);
      });
    _restartNudge();
  }

  void _clearSelection() {
    setState(() {
      _selected.clear();
      _selectionMode = false;
    });
    _restartNudge(); // спира таймера — вече няма какво да подсеща
  }

  void _restartNudge() {
    _nudgeTimer?.cancel();
    // Няма какво да подсеща, докато не е избрано поне едно.
    if (!_selectionMode || _selected.isEmpty) {
      _nudge.stop();
      return;
    }
    _nudge.forward(from: 0);
    _nudgeTimer = Timer.periodic(_nudgePause, (_) {
      if (!mounted || !_selectionMode || _selected.isEmpty) return;
      _nudge.forward(from: 0);
    });
  }

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _nudgeTimer?.cancel();
    _nudge.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final items = await _BookmarkStore.loadAll();
    if (!mounted) return;
    setState(() => _items = items);
  }

  Future<bool> _confirm(String title, String content) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title, style: const TextStyle(fontSize: 20)),
        content: Text(content, style: const TextStyle(fontSize: 16)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Не', style: TextStyle(fontSize: 20)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Да', style: TextStyle(fontSize: 20)),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _deleteOne(_BookmarkId id) async {
    final confirmed = await _confirm(
      'Изтриване на отметката',
      'Наистина ли искате да изтриете тази отметка?',
    );
    if (!confirmed) return;
    await _BookmarkStore.clear(id.slug, id.mode);
    _reload();
  }

  Future<void> _deleteAll() async {
    final confirmed = await _confirm(
      'Изтриване на всички отметки',
      'Наистина ли искате да изтриете ВСИЧКИ запазени отметки?',
    );
    if (!confirmed) return;
    await _BookmarkStore.clearAll();
    _reload();
  }

  Future<void> _deleteSelected() async {
    final confirmed = await _confirm(
      'Изтриване на избраните отметки',
      'Наистина ли искате да изтриете избраните отметки?',
    );
    if (!confirmed) return;
    for (final id in _selected) {
      await _BookmarkStore.clear(id.slug, id.mode);
    }
    if (!mounted) return;
    _clearSelection();
    _reload();
  }

  Future<void> _open(_BookmarkId id) async {
    final texts = await widget.lookup(id.slug);
    if (!mounted) return;
    if (texts == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Няма запис за този светия.')),
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
      builder: (_) => switch (id.mode) {
          _ReaderMode.life => ReaderScreen.life(
            texts: texts,
            lookup: widget.lookup,
          ),
          _ReaderMode.prayers => ReaderScreen.prayers(
            texts: texts,
            lookup: widget.lookup,
          ),
          _ReaderMode.sluzhba => ReaderScreen.sluzhba(
            texts: texts,
            lookup: widget.lookup,
          ),
      },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return PopScope(
      // Докато има избрани редове, "назад" излиза от режима, а не от
      // екрана — иначе човек губи списъка вместо избора си.
      canPop: !_selectionMode,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _clearSelection();
      },
      child: _buildScaffold(items),
    );
  }

  Widget _buildScaffold(List<(_BookmarkId, _BookmarkRecord)>? items) {
    return Scaffold(
      backgroundColor: AppColors.toolbar,
      appBar: AppBar(
        backgroundColor: AppColors.toolbar,
        // В режим "избиране" на мястото на стрелката "назад" стои изричен
        // "Отказ" — думата се чете еднозначно, докато ✕ оставя съмнение
        // дали ще затвори екрана, или само ще изчисти избора.
        leading: _selectionMode ? const SizedBox.shrink() : null,
        leadingWidth: _selectionMode ? 0 : null,
        title: _selectionMode
            ? Row(
                children: [
                  TextButton.icon(
                    onPressed: _clearSelection,
                    icon: const Icon(Icons.close, size: 20),
                    label: const Text('Отказ', style: TextStyle(fontSize: 16)),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.textPrimary,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                    ),
                  ),
                  const SizedBox(width: 4),
                  // Броячът отстъпва пръв, ако мястото не стигне — по-важно
                  // е изходът от режима да се вижда изцяло.
                  Flexible(
                    child: Text(
                      'Избрани: ${_selected.length}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              )
            : const Text('Списък с отметки'),
        // actionsPadding: нула, за да МАХНЕМ вградения отстъп на AppBar-а и
        // сами да контролираме десния отстъп (виж contentPadding на
        // ListTile-овете долу) — за да легнат кошчетата едно точно под
        // друго, и двете разстояния трябва да идват от НАС, не от
        // framework подразбирания, които може да са различни едно от друго.
        actionsPadding: EdgeInsets.zero,
        actions: [
          if (items != null && items.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Tooltip(
                message: _selectionMode ? 'Изтрий избраните' : 'Изтрий всички',
                child: IconButton(
                  // Едно и също копче с две задачи. Иконката не се сменя —
                  // че режимът е друг, се вижда от заглавието и от лекото
                  // разтърсване, което се повтаря през няколко секунди.
                  icon: AnimatedBuilder(
                    animation: _nudge,
                    builder: (context, child) {
                      final t = _nudge.value;
                      if (t == 0) return child!;
                      // Затихващо махало: люлее се все по-слабо, а
                      // наедряването върви и обратно, за да не "подскочи"
                      // иконката в края.
                      final angle = math.sin(t * math.pi * 6) * 0.28 * (1 - t);
                      final scale = 1 + math.sin(t * math.pi) * 0.22;
                      return Transform.rotate(
                        angle: angle,
                        child: Transform.scale(scale: scale, child: child),
                      );
                    },
                    child: const Icon(Icons.delete_sweep_outlined),
                    ),
                  // Без избрани копчето е угасено — така се вижда, че
                  // чака избор, вместо да изтрие всичко по погрешка.
                  onPressed: _selectionMode
                      ? (_selected.isEmpty ? null : _deleteSelected)
                      : _deleteAll,
                ),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: Container(
          color: AppColors.background,
          child: items == null
              ? const Center(child: CircularProgressIndicator())
              : items.isEmpty
                  ? const Center(
                      child: Text(
                        'Няма запазени отметки.',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 16,
                    ),
                      ),
                    )
                  : ListView.separated(
                      itemCount: items.length,
                  separatorBuilder: (_, _) =>
                      const Divider(height: 1, color: AppColors.sectionDivider),
                      itemBuilder: (context, i) {
                        final (id, record) = items[i];
                        final picked = _selected.contains(id);
                    // Фонът се рисува от НАС, а не през ListTile.
                    // selectedTileColor минава през Ink и в този вложен
                    // списък не се появяваше изобщо.
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      color: picked
                          ? AppColors.rowSelected
                          : Colors.transparent,
                      child: ListTile(
                          // Десен отстъп = точно колкото добавихме на
                          // "Изтрий всички" в лентата отгоре (виж
                          // AppBar.actionsPadding по-горе) — за да легне
                          // кошчето точно под него.
                        contentPadding: const EdgeInsets.only(
                          left: 16,
                          right: 16,
                        ),
                          // Задържане отваря режима за избиране; след това
                          // обикновеното докосване вече не отваря четивото,
                          // а добавя/маха реда от избора.
                          onLongPress: () => _toggle(id),
                        onTap: () => _selectionMode ? _toggle(id) : _open(id),
                          title: Text(
                            record.name,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 16,
                            ),
                          ),
                          subtitle: Text(
                            record.typeLabel,
                            style: const TextStyle(
                              color: AppColors.sectionTitle,
                              fontSize: 13,
                            ),
                          ),
                          // В режим "избиране" кошчето на реда отстъпва
                          // мястото си на отметка за избора — изтриването
                          // вече минава през копчето горе.
                          trailing: _selectionMode
                              ? Icon(
                                  picked
                                      ? Icons.check_circle
                                      : Icons.circle_outlined,
                                  color: picked
                                      ? AppColors.textPrimary
                                      : AppColors.textMuted,
                                )
                              : IconButton(
                                icon: const Icon(
                                  Icons.delete_outline,
                                  color: AppColors.textSecondary,
                                ),
                                  onPressed: () => _deleteOne(id),
                              ),
                                ),
                        );
                      },
                    ),
        ),
      ),
    );
  }
}
