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
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_theme.dart';
import 'bookmarks.dart';
import 'bookmarks_all.dart';
import 'pdf_export.dart';
import 'round_icon_button.dart';
import 'drop_cap.dart';
import 'drop_cap_scale.dart';
import 'settings_screen.dart';
import 'external_link.dart';
import 'text_line_locator.dart';
import 'reader_font_size.dart';
import 'reader_match_ticks.dart';
import 'reader_more_menu.dart';
import 'reader_resume_prompt.dart';
import 'reader_regions.dart';
import 'reader_search.dart';
import 'reader_styles.dart';
import 'reader_sup_extension.dart';
import 'reader_text_utils.dart';
import 'reader_theme.dart';
import 'reader_toolbar.dart';
import 'saint_expandable_tile.dart'
    show SaintTexts, SaintLookup, prayersTitleFor;

// Шрифтовете (family имената от pubspec.yaml):
const String kTitleFamily = 'TamburinModern'; // заглавието на житието
const String kDropCapFamily = 'Bukvica';      // орнаментираният инициал
const String kBodyFamily = 'CharisSIL';       // основният текст и молитвите


// ---------------------------------------------------------------
// Търсене: диакритик- и регистър-неутрално сравнение
// ---------------------------------------------------------------



int _countMatchesPlain(String text, String foldedQuery) {
  if (foldedQuery.isEmpty) return 0;
  final f = fold(text).text;
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




/// Чист текст без тагове — същата формула, ползвана и в _DropCapParagraph.
String _plainTextOf(String innerHtml) {
  return decodeEntities(
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
  // Грубо средна широчина на знак спрямо fontSize за серифния шрифт Charis SIL.
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

int _countInRegion(ReaderRegion r, String foldedQuery) {
  if (r.isHtml) return _countMatchesHtml(r.content, foldedQuery);
  var total = _countMatchesPlain(_plainTextOf(r.content), foldedQuery);
  for (final p in r.rest) {
    total += _countMatchesPlain(_plainTextOf(p), foldedQuery);
  }
  return total;
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
  // Заглавието, църковнославянският текст и преводът с курсив отдолу —
  // редът е един и същ за тропар, кондак, молитва и величание. Броят им
  // вече е неограничен: идват от lives.hymns, а не от четири колони.
  for (final h in texts.hymns) {
    // Молитвите и величанията нямат превод; осемте стари сирака нямат
    // църковнославянски оригинал. Ред без нито едно от двете няма какво
    // да покаже.
    if (h.csl.isEmpty && h.bg.isEmpty) continue;
    if (h.heading.isNotEmpty) {
      b.write('<p class="prayerhead">${h.heading}</p>');
    }
    if (h.csl.isNotEmpty) b.write('<p class="csl">${h.csl}</p>');
    if (h.bg.isNotEmpty) {
      b.write(
        '<p class="trans"><span class="translabel">Превод:</span> ${h.bg}</p>',
      );
    }
  }

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
  final List<ReaderRegion> regions;
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
  final (beforeHtml, _, dropCap, firstP, afterHtml) = isLife
      ? splitDropCap(html)
      : (html, '', '', '', '');

  // Житието има ли собствено заглавие (<h1>..<h6> преди първия абзац)? Ако
  // да — нашето име отгоре е излишно и се пропуска, за да няма два почти
  // еднакви заглавни реда един под друг. isLife: в режима с молитвите
  // beforeHtml съдържа целия HTML (вкл. заглавията на тропарите), затова
  // проверката важи само за житието.
  var hasOwnTitle =
      (isLife || args.mode == _ReaderMode.sluzhba) &&
      RegExp(r'<h[1-6]\b').hasMatch(beforeHtml);

  // Няма ли четивото свое заглавие, ВЛИВАМЕ името в самия текст.
  //
  // Дотук то се рисуваше като отделен надпис НАД съдържанието и затова
  // оставаше извън търсенето: търсачката черпи от регионите, а те се правят
  // от HTML-а. За читателя обаче заглавието си е текст на екрана и е редно
  // да се намира. Влято тук, то става обикновен регион и всичко останало
  // (броене, маркиране, чертички, мерене на височини) го поема без
  // изключения — а отделният надпис отпада, защото hasOwnTitle става true.
  var before = beforeHtml;
  final name = args.texts.name.trim();
  if (!hasOwnTitle && name.isNotEmpty) {
    final escaped = name.replaceAll('&', '&amp;').replaceAll('<', '&lt;');
    before = '<h3>$escaped</h3>$beforeHtml';
    hasOwnTitle = true;
  }

  final regions = computeRegions(before, dropCap, firstP, afterHtml);
  final hasGap = dropCap.isNotEmpty && before.trim().isNotEmpty;

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

  /// Индекс на ЗНАКА вътре в региона — първата буква на най-горния видим
  /// ред в мига на записа.
  ///
  /// Защо знак, а не ред и не пиксел: и двете се менят със размера на
  /// шрифта, тъй че записани днес, утре сочат другаде. Знакът е
  /// единственото инвариантно; редът и пикселът се смятат наново при всяко
  /// отваряне (виж text_line_locator.dart).
  ///
  /// 0 значи „началото на региона" — така се четат и всички стари записи,
  /// правени преди тази колона да съществува, тоест никой не си губи
  /// отметките.
  final int charInRegion;

  final String name;
  final String typeLabel;
  final int savedAtMs; // за сортиране по скорошност в списъка с отметки

  const _BookmarkRecord({
    required this.regionIndex,
    this.charInRegion = 0,
    required this.name,
    required this.typeLabel,
    required this.savedAtMs,
  });

  Map<String, dynamic> toJson() => {
        'regionIndex': regionIndex,
        'charInRegion': charInRegion,
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
      charInRegion: m['charInRegion'] is int ? m['charInRegion'] as int : 0,
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

  /// Какъв вид четиво е това — надписът над заглавието, който влиза и в
  /// отметката.
  ///
  /// Режимът `sluzhba` отдавна не носи само служби: с него се отварят и
  /// четивата на „Справочник", и бележките на свт. Теофан. Той решава как
  /// се РИСУВА текстът (без буквица), не какво Е той, затова надписът се
  /// подава отвън. Празно значи старото поведение — „Служба".
  final String? typeLabel;

  const ReaderScreen.life({
    super.key,
    required this.texts,
    required this.lookup,
    this.lifeTitle,
    this.typeLabel,
  }) : _mode = _ReaderMode.life;

  const ReaderScreen.prayers({
    super.key,
    required this.texts,
    required this.lookup,
    this.lifeTitle,
    this.typeLabel,
  }) : _mode = _ReaderMode.prayers;

  const ReaderScreen.sluzhba({
    super.key,
    required this.texts,
    required this.lookup,
    this.lifeTitle,
    this.typeLabel,
  }) : _mode = _ReaderMode.sluzhba;

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  // Размерът е static: пази се за цялата сесия, общ за всички екрани
  // на четеца. 17 е базата; стъпка 1.5; разумни граници.
  // Тема на четеца — НЕЗАВИСИМА от темата на приложението.
  // static: пази се за сесията, обща за всички екрани на четеца.


  // Персистиране на размера в потребителските настройки (SharedPreferences),
  // за да оцелее и след рестарт на приложението (ReaderFontSize.value сам по себе си е
  // само сесиен). Зареждаме от диска ЕДНОКРАТНО на сесия (виж
  // _loadPersistedFontSizeOnce) — следващите ReaderScreen инстанции вече
  // виждат правилната стойност направо в статичното поле, без нов прочит.
  // Последно ЗАПИСАНАТА на диска стойност, пазена в паметта — сравняваме
  // с нея вместо да четем от диска всеки път, за да пропускаме излишни
  // записи (напр. потребителят увеличава и после пак намалява до същото).
  static const double _btnSize = 22.0;   // еднакъв размер и за трите бутона
  static const double _searchBtnSize =
      _btnSize + 6; // старт/</>  в search лентата
  static const double _titleGap =
      30.0; // константно разстояние заглавие → текст

  // Резултатът от еднократната тежка текстова подготовка (виж
  // _prepareReaderContent по-горе) — null докато фоновият isolate работи.
  // build() показва лек spinner дотогава, за да не блокира push-а на
  // екрана (виж коментара в initState).
  _PreparedContent? _prepared;




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
    WidgetsBinding.instance.addObserver(this);
    _scrollController.addListener(_onScrollForBookmark);
    _scrollController.addListener(_onScrollDirectionForToolbarPin);
    // Темата и размерът се четат заедно — за човека това е един
    // четец и настройките му са общи (виж ReaderTheme.loadOnce).
    ReaderTheme.loadOnce().then((_) {
      if (mounted) setState(() {});
    });
    ReaderFontSize.loadOnce().then((_) {
      if (mounted) setState(() {});
    });
    ReaderDropCapScale.loadOnce().then((_) {
      if (mounted) setState(() {});
    });
    // Настройката се сменя от drawer, който стои НАД четеца (не го
    // затваря) — без слушател ефектът се виждаше едва при следващо
    // отваряне на четивото.
    ReaderDropCapScale.notifier.addListener(_onDropCapScaleChanged);

    // ПЪЛЕН ЕКРАН ЗА ЦЯЛОТО ЧЕТЕНЕ — същото както в четеца на книги (виж
    // book_reader.dart). Включва се веднъж тук, изключва се веднъж в
    // dispose, и между тях режимът НЕ се пипа.
    //
    // Урокът дойде оттам: смяната на системния режим преоразмерява
    // прозореца ВЕДНЪЖ. Като състояние всеки режим е спокоен — неспокойни
    // са преходите. Затова режимът се сменя при влизане и излизане от
    // екран, никога при плъзгане.
    //
    // immersiveSticky: при жест отгоре лентата наднича и сама се скрива
    // пак, без да ни връща в друг режим.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
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
      // resume-подканата (виж ResumePrompt) вместо да скачаме безшумно.
      final slug = widget.texts.slug;
      if (slug.isEmpty) return;
      final saved = await _BookmarkStore.load(slug, widget._mode);
      if (!mounted || saved == null) return;
      setState(() {
        _isBookmarked = true;
        _bookmarkedRegionIndex = saved.regionIndex;
        _bookmarkedChar = saved.charInRegion;
        _showResumePrompt = true;
        _awaitingBookmarkDecision = true;
      });
    });
  }

  void _bump(double d) {
    // ⚠ Улавяме най-горния видим ред ПРЕДИ смяна на шрифта — старата
    // геометрия е още достъпна тук (layout-ът с новия размер минава чак
    // на следващия кадър, същият похват като при завъртане на екрана —
    // виж _restoreAfterRotation). Извън търсене досега тук нищо не пазеше
    // позицията: докладвано 22.08.2026 — смяна на шрифта по средата на
    // дълго житие изгубваше читателя.
    final at = _totalMatches > 0 ? null : _topmostLine();
    setState(() {
      // Заковава лентата (виж _toolbarPinned) — иначе jumpTo-то по-долу
      // изглежда за floating+snap като скрол надолу и лентата се скрива
      // точно докато пръстът е още на +/-. Освобождава се пак САМО при
      // истинско влачене надолу (_onScrollDirectionForToolbarPin), не и
      // от самата корекция тук.
      _toolbarPinned = true;
      ReaderFontSize.nudge(d);
      // Реалните измерени височини важат само за СТАРИЯ размер на шрифта —
      // със SliverVariedExtentList старите стойности биха ПРИНУДИЛИ новия
      // (различно висок) текст в грешна кутия (препълване, изрязване).
      // Нулираме, за да прескочим обратно на хюристиката и да предизвикаме
      // ново фоново измерване за актуалния размер.
      _realCumulativeHeights = null;
      _realItemExtents = null;
      _measuring = false;
    });

    // Смяната на шрифта преформатира целия текст (различни височини на
    // абзаците) — ако има активно търсене, текущото съвпадение би могло
    // да "избяга" от изгледа; пренасочваме скрола към него отново.
    if (_totalMatches > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Future.delayed(const Duration(milliseconds: 80), () {
          if (mounted) _scrollToCurrent();
        });
      });
    } else if (at != null) {
      // Извън търсене — връщаме най-горния ред на мястото му, вместо да
      // оставим скрола на СТАРИЯ пиксел офсет (който при новия размер на
      // шрифта вече сочи съвсем друго място в текста).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Future.delayed(const Duration(milliseconds: 80), () {
          if (mounted) _jumpToLineInstant(at.$1, at.$2);
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
  int _bookmarkedChar = 0;     // и знакът в нея (виж _BookmarkRecord)
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

  /// Пореден номер на текущото искане за скрол — виж _scrollToCurrent.
  /// Пази от закъснели поправки, останали от предишна стъпка.
  int _scrollToken = 0;

  /// Кутията с буквицата — питаме я на кой пиксел стои даден знак от първия
  /// абзац. Тя единствена знае къде е пречупила обтичащата зона.
  final GlobalKey<DropCapParagraphState> _dropCapKey =
      GlobalKey<DropCapParagraphState>();
  /// За отварянето на настройките като endDrawer — виж _showMoreMenu().
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  /// Докато е true, лентата с инструменти НЕ се крие (SliverAppBar минава
  /// от floating+snap на pinned) — виж _bump() и _onScrollDirectionForPin.
  /// Нужно е, защото смяната на шрифта поправя скрол позицията с jumpTo
  /// (виж _bump), а floating+snap го чете като „скрол надолу" и скрива
  /// лентата точно докато пръстът е още върху +/- (докладвано 24.08.2026).
  bool _toolbarPinned = false;
  bool _measuring = false;
  List<GlobalKey> _measureKeys = [];
  final GlobalKey _titleMeasureKey = GlobalKey();
  double? _measuredForWidth; // ширината, за която важат реалните измервания

  List<double> get _effectiveCumulativeHeights =>
      _realCumulativeHeights ?? _cumulativeHeights;

  Color get _hitColor => _p.hit;
  Color get _hitCurrentColor => _p.hitCurrent;

  // Чертичките на скролбара имат СВОЙ цвят за светлата тема — светложълтото
  // на _hitColor (добро като фон зад маркиран текст) почти изчезва на тънка
  // линия върху кремавия фон (_bg = 0xFFF5E6C5), затова тук е по-тъмен,
  // по-наситен маслинено-кехлибарен нюанс само за тях.
  Color get _tickHitColor => _p.tickHit;
  Color get _tickCurrentColor => _p.tickCurrent;

  /// Пресъздава скрол-контролера със стартова позиция = текущата, за да
  /// прехвърли безшумно офсета към новото Scrollable (виж коментара на
  /// _scrollController).
  void _reanchorScrollController() {
    final offset = _scrollController.hasClients
        ? _scrollController.position.pixels
        : 0.0;
    _scrollController.dispose();
    _scrollController = ScrollController(initialScrollOffset: offset)
      ..addListener(_onScrollForBookmark)
      ..addListener(_onScrollDirectionForToolbarPin);
  }

  // ---------------------------------------------------------------
  // Завъртане на екрана — пази позицията (докладвано 21.08.2026)
  // ---------------------------------------------------------------

  /// Последно познатата ориентация — за да различим ИСТИНСКО завъртане от
  /// друга промяна на метриките (напр. клавиатурата, която сменя само
  /// височината, не съотношението). null значи "още нищо видяно": първото
  /// повикване само го запомня, не скролва никъде.
  bool? _wasLandscape;

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    final views = WidgetsBinding.instance.platformDispatcher.views;
    if (views.isEmpty) return;
    final size = views.first.physicalSize;
    if (size.isEmpty) return;
    final landscape = size.width > size.height;
    final was = _wasLandscape;
    _wasLandscape = landscape;
    if (was == null || was == landscape) return; // не е завъртане
    _restoreAfterRotation();
  }

  /// При завъртане съдържанието се прекомпонова на новата ширина, а
  /// пиксел-офсетът на скрола остава непроменен — вече сочи към СЪВСЕМ
  /// друг ред и четецът "скача" безсмислено (докладвано 21.08.2026).
  ///
  /// При търсене — просто скролваме ОТНОВО до текущото съвпадение
  /// (_currentMatch не се пипа никъде тук, тъй че "3/8" не се губи).
  /// Извън търсене — улавяме кой ред е бил най-отгоре ПРЕДИ
  /// прекомпоновката (геометрията в момента на didChangeMetrics е още
  /// СТАРАТА — layout-ът на новата ширина минава едва на следващия кадър,
  /// виж бележката при _viewportWidth в build()) и го връщаме най-отгоре
  /// пак, през същия механизъм, който вече върши това за отметките.
  void _restoreAfterRotation() {
    if (!mounted) return;
    if (_searchOpen) {
      if (_currentMatch < 0) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Future.delayed(const Duration(milliseconds: 80), () {
          if (mounted) _scrollToCurrent();
        });
      });
      return;
    }
    final at = _topmostLine();
    if (at == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 80), () {
        // jumpTo (_jumpToLineInstant), НЕ _jumpToBookmarkRegion (animateTo)
        // — виж бележката там защо: animateTo оставяше 350 ms прозорец, в
        // който следващо бързо завъртане засичаше скрола по средата на
        // предишната анимация и натрупваше отместване.
        if (mounted) _jumpToLineInstant(at.$1, at.$2);
      });
    });
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

  /// Освобождава закованата лента (виж _toolbarPinned) при ПЪРВОТО истинско
  /// движение на пръста надолу през текста — не при кое да е движение на
  /// скрола: `userScrollDirection` е Flutter-ово поле, което се движи само
  /// докато пръстът реално влачи (ScrollDirection.reverse = съдържанието се
  /// изтегля нагоре, тоест четивото „слиза"), а НЕ при programmatic jumpTo —
  /// точно затова е избрано пред грубо слушане по pixels/offset, което би
  /// хванало и собствената ни корекция след смяна на шрифта.
  void _onScrollDirectionForToolbarPin() {
    if (!_toolbarPinned || !_scrollController.hasClients) return;
    if (_scrollController.position.userScrollDirection ==
        ScrollDirection.reverse) {
      setState(() => _toolbarPinned = false);
    }
  }

  void _saveBookmarkIfStillIdle() {
    if (!mounted || !_isBookmarked || _awaitingBookmarkDecision) return;
    if (!_scrollController.hasClients) return;
    final slug = widget.texts.slug;
    if (slug.isEmpty) return;
    // Най-горният ВИДИМ РЕД, не просто най-горният абзац: така при връщане
    // екранът застава точно както е бил оставен.
    final at = _topmostLine();
    final idx = at?.$1 ??
        _topmostRegionIndex(_scrollController.position.pixels);
    final ch = at?.$2 ?? 0;
    // Сравняваме с последно ЗАПАЗЕНОТО (в паметта, не презачитаме от диска)
    // — ако нищо не се е променило (телефонът лежи неподвижен с часове или
    // дребно поклащане в рамките на същия ред), пропускаме записа на диска.
    if (idx == _bookmarkedRegionIndex && ch == _bookmarkedChar) return;
    _bookmarkedRegionIndex = idx;
    _bookmarkedChar = ch;
    _BookmarkStore.save(
      slug,
      widget._mode,
      _BookmarkRecord(
        regionIndex: idx,
        charInRegion: ch,
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
        _bookmarkedChar = 0;
        _showResumePrompt = false;
        _awaitingBookmarkDecision = false;
      });
    } else {
      final at = _scrollController.hasClients ? _topmostLine() : null;
      final idx = at?.$1 ??
          (_scrollController.hasClients
              ? _topmostRegionIndex(_scrollController.position.pixels)
              : 0);
      final ch = at?.$2 ?? 0;
      await _BookmarkStore.save(
        slug,
        widget._mode,
        _BookmarkRecord(
          regionIndex: idx,
          charInRegion: ch,
          name: widget.texts.name,
          typeLabel: _typeLabel,
          savedAtMs: DateTime.now().millisecondsSinceEpoch,
        ),
      );
      if (!mounted) return;
      setState(() {
        _isBookmarked = true;
        _bookmarkedRegionIndex = idx;
        _bookmarkedChar = ch;
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
  void _jumpToBookmarkRegion(int regionIndex, [int charInRegion = 0]) {
    if (regionIndex < 0 || regionIndex >= _regionKeys.length) return;
    final key = _regionKeys[regionIndex];

    void refine() {
      final ctx = key.currentContext;
      if (ctx == null) return;
      final box = ctx.findRenderObject() as RenderBox?;
      // Целим точния РЕД, на който е спрял читателят, и го поставяме най-
      // горе — така екранът изглежда както го е оставил. Знакът е записан,
      // редът се смята сега, при текущия размер на шрифта.
      final line = box == null
          ? null
          : _lineForChar(regionIndex, charInRegion, box.size.width);
      if (box != null && line != null && _scrollController.hasClients) {
        final target = RenderAbstractViewport.of(box)
            .getOffsetToReveal(
              box,
              0.0,
              rect: Rect.fromLTWH(0, line.$1, box.size.width, line.$2),
            )
            .offset;
        final position = _scrollController.position;
        _scrollController.animateTo(
          target.clamp(position.minScrollExtent, position.maxScrollExtent),
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeInOut,
        );
        return;
      }
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

  /// Вариант на [_jumpToBookmarkRegion] БЕЗ анимация — скача направо
  /// (jumpTo), не се плъзга (animateTo).
  ///
  /// ⚠ Съществува заради конкретен бъг (докладван 22.08.2026): при
  /// повторно завъртане на екрана, докато предишният animateTo (350 ms)
  /// още е бил в ход, следващото улавяне на "най-горния ред" засичаше
  /// СКРОЛА ПО СРЕДА НА АНИМАЦИЯТА — нито старата, нито новата позиция, а
  /// нещо междинно. Повторено при няколко завъртания едно след друго, това
  /// натрупваше видимо, все по-растящо отместване надолу. jumpTo е
  /// атомарен — няма прозорец от време, в който следващо събитие да
  /// завари скрола "по средата", тъй че грешката не може да се натрупва.
  /// Ползва се само за случаи, при които самата анимация не носи нищо
  /// (потребителят вече не гледа този момент) — завъртане на екрана и
  /// превключване на търсенето. Виж _restoreAfterRotation и _toggleSearch.
  ///
  /// [extraOffset] — ръчна корекция в пиксели, добавена към изчисленото
  /// подравняване. Нужна е при превключване на търсенето (виж
  /// _toggleSearch): подравняването към alignment 0.0 е пиксел-точно
  /// спрямо ГОРНИЯ РЪБ НА СКРОЛИРУЕМАТА ЗОНА, но самата тази зона расте с
  /// височината на двете ленти (лентата с инструменти + лентата за
  /// търсене, 44+58=102), които изчезват при затваряне. Без корекция
  /// редът застава пиксел-точно на новия връх, но окото го вижда
  /// изместен нагоре точно с толкова, колкото тежат изчезналите ленти
  /// (докладвано 22.08.2026: ~3.5 реда). Отрицателна стойност спира
  /// скрола по-рано (по-малко разстояние от началото).
  void _jumpToLineInstant(int regionIndex, int charInRegion,
      {double extraOffset = 0}) {
    if (!mounted || !_scrollController.hasClients) return;
    if (regionIndex < 0 || regionIndex >= _regionKeys.length) return;
    final ctx = _regionKeys[regionIndex].currentContext;
    final box = ctx?.findRenderObject() as RenderBox?;
    final line =
        box == null ? null : _lineForChar(regionIndex, charInRegion, box.size.width);
    if (box == null || line == null) return;
    final target = RenderAbstractViewport.of(box)
            .getOffsetToReveal(
              box,
              0.0,
              rect: Rect.fromLTWH(0, line.$1, box.size.width, line.$2),
            )
            .offset +
        extraOffset;
    final position = _scrollController.position;
    position.jumpTo(target.clamp(position.minScrollExtent, position.maxScrollExtent));
  }

  void _onResumePromptJump() {
    final idx = _bookmarkedRegionIndex;
    if (idx != null) _jumpToBookmarkRegion(idx, _bookmarkedChar);
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

  /// Лентата с инструменти + лентата за търсене — заедно изчезват при
  /// затваряне на търсенето (и заедно се появяват при отваряне). Виж
  /// корекцията в _toggleSearch по-долу. Смятана от СЪЩИТЕ кръстени
  /// константи, с които се строят самите ленти (reader_toolbar.dart) — не
  /// голи числа тук, за да не могат корекцията и реалната височина да се
  /// разминат при промяна.
  static const double _kSearchChromeHeight =
      kReaderToolbarHeight + kSearchBarHeight;

  void _toggleSearch() {
    // ⚠ Улавяме най-горния видим ред ПРЕДИ превключването — само
    // запазването на pixels (_reanchorScrollController) не стига.
    // Лентата за търсене (58) ту стои ИЗВЪН скрола (фиксирана над
    // Expanded-а), ту ВЪТРЕ като sliverHeader.bottom — двете подредби
    // броят различно колко от тази височина влиза в скрол-координатите,
    // тъй че еднакъв pixels сочи различно съдържание преди/след. Знакът
    // тук е точен и НЕ зависи от тази сметка за височините — същият
    // механизъм, който вече пази позицията при завъртане.
    //
    // ⚠ Самото подравняване към alignment 0.0 е пиксел-точно спрямо
    // ГОРНИЯ РЪБ НА СКРОЛИРУЕМАТА ЗОНА — но при затваряне тази зона
    // РАСТЕ точно с _kSearchChromeHeight (двете ленти изчезват), тъй че
    // редът каца пиксел-точно на новия връх, а окото го вижда изместен
    // нагоре точно с толкова (докладвано 22.08.2026: ~3.5 реда).
    // extraOffset компенсира — спира скрола толкова по-рано (при
    // затваряне) или го праща толкова по-нататък (при отваряне, огледално).
    //
    // ⚠ Не е пиксел-перфектно при всеки размер на шрифта (проверено
    // 22.08.2026: точно при най-малките два размера, един ред разлика на
    // третия) — вероятно защото _searchAnim (220 мс) още не е свършила,
    // когато следващия кадър вече прилага корекцията. Оставено нарочно
    // — потребителят прецени, че един ред разлика не си струва по-нататъшно
    // гонене на този пиксел.
    final wasOpen = _searchOpen;
    final at = _topmostLine();
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
    if (at != null) {
      final extraOffset = wasOpen ? -_kSearchChromeHeight : _kSearchChromeHeight;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _jumpToLineInstant(at.$1, at.$2, extraOffset: extraOffset);
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

    final foldedQuery = fold(query).text;
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

  /// Отместването на съвпадение №[ordinal] ВЪТРЕ в региона [regionIdx],
  /// мерено при текущия размер на шрифта и подадената ширина.
  ///
  /// Това е сърцевината на точното позициониране: дотук се целеше цял
  /// регион, а регион може да е дълъг колкото няколко екрана — тогава
  /// съвпадение в средата му оставаше невидимо. Виж text_line_locator.dart.
  ///
  /// null значи „не можах да го изчисля" — тогава извикващият се връща към
  /// стария начин (цял регион), вместо да скочи на грешно място.
  (double, double)? _matchLineInRegion(int regionIdx, double width) {
    final prepared = _prepared;
    if (prepared == null || width <= 0) return null;
    if (regionIdx < 0 || regionIdx >= prepared.regions.length) return null;
    if (_committedQuery.isEmpty) return null;
    final region = prepared.regions[regionIdx];

    // Кое поред съвпадение в ТОЗИ регион е текущото.
    var ordinal = _currentMatch;
    for (int i = 0; i < regionIdx && i < _regionMatchCounts.length; i++) {
      ordinal -= _regionMatchCounts[i];
    }
    if (ordinal < 0) return null;

    // Абзацът с буквицата. Текстът обтича инициала, тъй че прав TextPainter
    // не го мери вярно — питаме самата кутия (виж DropCapParagraphState).
    //
    // ⚠ Без този клон грубият скок отиваше на вярното място и веднага след
    // това точната стъпка го разваляше: връщаше null и се падаше на
    // „покажи целия регион", тоест на началото на абзаца.
    if (!region.isHtml) {
      final state = _dropCapKey.currentState;
      if (state == null) return null;
      final folded = fold(_committedQuery).text;
      final starts = matchStartsOf(_plainTextOf(region.content), folded);
      // Регионът на буквицата може да носи и следващите абзаци (изтеглят
      // се вдясно от инициала, докато остава място). Съвпаденията им
      // продължават номерацията на първия, по ред.
      double? dy;
      if (ordinal < starts.length) {
        dy = state.dyForChar(starts[ordinal]);
      } else {
        var remaining = ordinal - starts.length;
        for (var i = 0; i < region.rest.length; i++) {
          final startsI = matchStartsOf(_plainTextOf(region.rest[i]), folded);
          if (remaining < startsI.length) {
            dy = state.dyForCharInRest(i, startsI[remaining]);
            break;
          }
          remaining -= startsI.length;
        }
      }
      if (dy == null) return null;
      // Кутията с буквицата няма поле отгоре — започва направо от реда с
      // инициала.
      return (dy, ReaderFontSize.value * kReaderLineHeight);
    }

    final locator = LineLocator.forHtml(
      html: region.content,
      base: TextStyle(
        fontFamily: kBodyFamily,
        fontSize: ReaderFontSize.value,
        height: kReaderLineHeight,
      ),
      maxWidth: width,
    );
    try {
      final at = locator.charOfMatch(fold(_committedQuery).text, ordinal);
      if (at == null) return null;
      // Абзацът има поле отгоре (виж правилото за 'p' в reader_styles.dart);
      // текстът започва под него.
      return (_pTopMargin + locator.dyForChar(at), locator.lineHeightForChar(at));
    } finally {
      locator.dispose();
    }
  }

  /// Отместването и височината на реда, в който стои знак [charInRegion] от
  /// региона [regionIdx] — при ТЕКУЩИЯ шрифт и подадената ширина.
  ///
  /// Общо за търсенето и за отметките: и двете имат нужда от едно и също
  /// превръщане „знак → ред → пиксел".
  (double, double)? _lineForChar(int regionIdx, int charInRegion, double width) {
    final prepared = _prepared;
    if (prepared == null || width <= 0) return null;
    if (regionIdx < 0 || regionIdx >= prepared.regions.length) return null;
    final region = prepared.regions[regionIdx];
    final lineH = ReaderFontSize.value * kReaderLineHeight;

    if (!region.isHtml) {
      final dy = _dropCapKey.currentState?.dyForChar(charInRegion);
      return dy == null ? null : (dy, lineH);
    }
    final (base, topMargin) = _measureStyleFor(region.content);
    final locator =
        LineLocator.forHtml(html: region.content, base: base, maxWidth: width);
    try {
      return (
        topMargin + locator.dyForChar(charInRegion),
        locator.lineHeightForChar(charInRegion),
      );
    } finally {
      locator.dispose();
    }
  }

  /// Абсолютното отместване на един регион в скрола — от РЕАЛНАТА му
  /// геометрия, не от оценка. null, ако още не е построен (мързелив списък).
  double? _regionTopOffset(int regionIdx) {
    if (regionIdx < 0 || regionIdx >= _regionKeys.length) return null;
    final ctx = _regionKeys[regionIdx].currentContext;
    if (ctx == null) return null;
    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null) return null;
    return RenderAbstractViewport.of(box).getOffsetToReveal(box, 0.0).offset;
  }

  /// Кой знак стои на най-горния видим ред — (регион, знак в него).
  ///
  /// Това записва отметката. Върви по РЕАЛНАТА геометрия на построените
  /// региони: първият, чийто долен ръб е под горния ръб на екрана, е
  /// видимият най-отгоре. (Непостроените са далеч от екрана по построение.)
  (int, int)? _topmostLine() {
    if (!_scrollController.hasClients) return null;
    final pixels = _scrollController.position.pixels;
    for (int i = 0; i < _regionKeys.length; i++) {
      final ctx = _regionKeys[i].currentContext;
      if (ctx == null) continue;
      final box = ctx.findRenderObject() as RenderBox?;
      if (box == null) continue;
      final top =
          RenderAbstractViewport.of(box).getOffsetToReveal(box, 0.0).offset;
      if (top + box.size.height <= pixels) continue; // изцяло над екрана
      final dy = pixels - top;
      if (dy < 0) return (i, 0); // екранът е спрял преди този регион
      return (i, _charAtDyInRegion(i, dy, box.size.width) ?? 0);
    }
    return null;
  }

  int? _charAtDyInRegion(int regionIdx, double dy, double width) {
    final prepared = _prepared;
    if (prepared == null || width <= 0) return null;
    if (regionIdx < 0 || regionIdx >= prepared.regions.length) return null;
    final region = prepared.regions[regionIdx];
    if (!region.isHtml) return _dropCapKey.currentState?.charAtDy(dy);
    final (base, topMargin) = _measureStyleFor(region.content);
    final locator =
        LineLocator.forHtml(html: region.content, base: base, maxWidth: width);
    try {
      return locator.charAtDy(dy - topMargin);
    } finally {
      locator.dispose();
    }
  }

  /// Стилът и горното поле, с които се РИСУВА даден регион.
  ///
  /// Мерещият трябва да е огледален на рисуващия, инак редовете се чупят на
  /// друго място и отместването излиза грешно. Стойностите тук са същите
  /// като правилата в reader_styles.dart — сменят ли се там, сменят се и
  /// тук. (Заглавието е с друг шрифт и с 12 пункта по-едро; църковнославян-
  /// ският откъс е малко по-едър и по-нагъсто; преводът, редът с паметта и
  /// източникът са по-дребни и в курсив.)
  (TextStyle, double) _measureStyleFor(String html) {
    final size = ReaderFontSize.value;
    TextStyle body(double s, {FontStyle? italic, double? height}) => TextStyle(
          fontFamily: kBodyFamily,
          fontSize: s,
          height: height ?? kReaderLineHeight,
          fontStyle: italic,
        );
    final head = html.trimLeft();
    if (head.startsWith('<h3')) {
      return (
        TextStyle(
          fontFamily: kTitleFamily,
      fontFamilyFallback: kTitleFallback,
          fontSize: size + 12,
          height: 1.05,
        ),
        18.0,
      );
    }
    if (head.contains('class="csl"')) return (body(size + 0.5, height: 1.3), 8.0);
    if (head.contains('class="trans"')) {
      return (body(size - 1, italic: FontStyle.italic), 8.0);
    }
    if (head.contains('class="memorydate"')) {
      return (body(size - 1, italic: FontStyle.italic), 2.0);
    }
    if (head.contains('class="source"')) {
      return (body(size - 2, italic: FontStyle.italic), 24.0);
    }
    if (head.contains('class="prayerhead"')) {
      return (
        TextStyle(
          fontFamily: kBodyFamily,
          fontSize: size + 1,
          height: kReaderLineHeight,
          fontWeight: FontWeight.w600,
        ),
        18.0,
      );
    }
    return (body(size), _pTopMargin);
  }

  /// Горното поле на обикновен абзац — Margins.only(top: 8) в
  /// reader_styles.dart.
  static const double _pTopMargin = 8.0;

  /// Скролва до текущото съвпадение. SliverList строи децата си мързеливо
  /// (само близо до видимата зона) — ако регионът вече е построен, целим
  /// точния РЕД в него; иначе първо скачаме ПРИБЛИЗИТЕЛНО по пропорция, за
  /// да влезе в build-обхвата, после прецизираме.
  void _scrollToCurrent() {
    if (_currentMatch < 0 || _regionKeys.isEmpty) return;
    final regionIdx = _regionIndexForCurrentMatch();
    if (regionIdx >= _regionKeys.length) return;
    final key = _regionKeys[regionIdx];

    // Всяка нова стъпка обезсилва подредените поправки от предната. Без
    // това бързото натискане на „напред" оставя опашка от закъснели
    // поправки и всяка дърпа екрана към СВОЕТО съвпадение.
    final token = ++_scrollToken;

    void refine(String tag) {
      if (token != _scrollToken) return;
      final ctx = key.currentContext;
      if (ctx == null) return;
      final box = ctx.findRenderObject() as RenderBox?;
      final line =
          box == null ? null : _matchLineInRegion(regionIdx, box.size.width);
      if (box != null && line != null && _scrollController.hasClients) {
        // getOffsetToReveal с ВЪТРЕШЕН правоъгълник: искаме да се покаже
        // точно този ред от този абзац. Геометрията на слоевете (заглавие,
        // отстояния, sliver-и) се пресмята от самата viewport-а, тъй че тук
        // не се събират отмествания на ръка.
        final viewport = RenderAbstractViewport.of(box);
        final target = viewport
            .getOffsetToReveal(
              box,
              _matchAlignment,
              rect: Rect.fromLTWH(0, line.$1, box.size.width, line.$2),
            )
            .offset;
        final position = _scrollController.position;
        final clamped =
            target.clamp(position.minScrollExtent, position.maxScrollExtent);
        // Вече сме там — не мърдаме. Точно тази проверка липсваше и
        // втората (закъсняла) поправка местеше екрана за няколко пиксела, а
        // докато височините още се оценяват — го връщаше назад.
        if ((position.pixels - clamped).abs() < 8) return;
        _scrollController.animateTo(
          clamped,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeInOut,
        );
        return;
      }
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
      // Втора поправка САМО докато височините още се оценяват: тогава всеки
      // новопостроен елемент мести абсолютните отмествания и първият ход
      // може да е бил спрямо остаряла геометрия. Веднъж измерено точно,
      // повторението няма какво да добави — а има какво да развали.
      if (_realItemExtents == null) {
        Future.delayed(const Duration(milliseconds: 420), () {
          if (mounted) refine('refine-1');
        });
      }
      return;
    }
    // Не е построен — скок по НАШАТА оценка (не сляпа пропорция от
    // maxScrollExtent, който самият той е нестабилен), после прецизиране.
    // Целим самото съвпадение, а не началото на абзаца му: при дълъг абзац
    // това са няколко екрана разлика и вторият, точният ход тръгва отдалеч.
    //
    // ⚠ Оценката е ХЮРИСТИЧНА, докато _realItemExtents е null — точно
    // състоянието непосредствено СЛЕД смяна на шрифта (_bump() го нулира
    // нарочно, за да предизвика ново фоново премерване). Докладвано
    // 22.08.2026: обхождане на съвпадение точно тогава можеше да скочи
    // достатъчно далеч от целта, че регионът така и не влизаше в build-
    // обхвата на мързеливия списък — тогава ЕДНОКРАТНАТА поправка по-долу
    // мълчаливо се отказваше (ctx == null → return) и потребителят
    // оставаше на грешно място, без самокорекция. Затова опитът се
    // ПОВТАРЯ, докато регионът не се построи (или до разумен таван) —
    // всеки следващ опит пресмята оценката наново от
    // _effectiveCumulativeHeights, който междувременно се доуточнява от
    // фоновото премерване.
    void attemptJump(int attempt) {
      if (token != _scrollToken || !mounted) return;
      if (key.currentContext != null) {
        refine('retry-$attempt');
        return;
      }
      if (attempt >= 6) return; // ~600 мс общо — таван, не безкраен цикъл
      if (!_scrollController.hasClients) return;
      final position = _scrollController.position;
      _ensureMatchYs();
      final cumulative = _effectiveCumulativeHeights;
      final estimateRaw = _currentMatch < _matchYs.length
          ? _matchYs[_currentMatch] -
              position.viewportDimension * _matchAlignment
          : (regionIdx > 0 && regionIdx - 1 < cumulative.length
              ? cumulative[regionIdx - 1]
              : 0.0);
      final estimate = estimateRaw.clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      position.jumpTo(estimate);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Future.delayed(const Duration(milliseconds: 100), () {
          if (mounted) attemptJump(attempt + 1);
        });
      });
    }

    attemptJump(0);
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

  // ── Къде точно стои всяко съвпадение ──────────────────────────────────
  //
  // Отместването (в пиксели, при текущия шрифт и ширина) на ВСЯКО
  // съвпадение поотделно. Дотук се знаеше само в кой абзац е — тъй че
  // всички съвпадения в един абзац получаваха една и съща позиция: по
  // скролбара чертичките се струпваха на купчини, а обхождането ги
  // подминаваше, защото скачаше все на едно и също място.
  //
  // Смята се лениво и се пази, докато не се смени нещо, което го обезсилва
  // (заявка, размер на шрифта, ширина на екрана). Виж text_line_locator.dart.
  List<double> _matchYs = const [];
  String _matchYsQuery = '';
  double _matchYsFont = -1;
  double _matchYsWidth = -1;
  bool _matchYsFromRealHeights = false;

  void _ensureMatchYs() {
    final prepared = _prepared;
    if (prepared == null) return;
    // Меренето минава през две състояния: първо оценени височини, после
    // реални. Смени ли се това, позициите се смятат наново — иначе
    // чертичките остават по старата, приблизителна геометрия.
    final real = _realItemExtents != null;
    if (_matchYsQuery == _committedQuery &&
        _matchYsFont == ReaderFontSize.value &&
        _matchYsWidth == _viewportWidth &&
        _matchYsFromRealHeights == real) {
      return;
    }
    _matchYsQuery = _committedQuery;
    _matchYsFont = ReaderFontSize.value;
    _matchYsWidth = _viewportWidth;
    _matchYsFromRealHeights = real;

    if (_committedQuery.isEmpty || _totalMatches == 0) {
      _matchYs = const [];
      return;
    }
    final folded = fold(_committedQuery).text;
    final cumulative = _effectiveCumulativeHeights;
    final width = _viewportWidth - _horizontalPadding * 2;
    final ys = <double>[];
    for (int i = 0; i < prepared.regions.length; i++) {
      final count = i < _regionMatchCounts.length ? _regionMatchCounts[i] : 0;
      if (count == 0) continue;
      // Отместване до началото на региона В ПРОСТРАНСТВОТО НА СКРОЛА, а не
      // само спрямо другите региони: над тях стоят горният отстъп на
      // списъка, заглавието и (след първия регион) луфтът под него. Без
      // тези три събираеми чертичките излизаха систематично по-нагоре от
      // показалеца на скролбара, макар подредбата им да беше вярна.
      final top = _contentTop +
          (i >= 1 ? _gapBeforeRegions : 0.0) +
          (i > 0 && i - 1 < cumulative.length ? cumulative[i - 1] : 0.0);
      final region = prepared.regions[i];
      if (!region.isHtml) {
        final state = _dropCapKey.currentState;
        final starts = matchStartsOf(_plainTextOf(region.content), folded);
        final restStarts = [
          for (final p in region.rest) matchStartsOf(_plainTextOf(p), folded)
        ];
        for (int k = 0; k < count; k++) {
          double? dy;
          if (state != null) {
            if (k < starts.length) {
              dy = state.dyForChar(starts[k]);
            } else {
              var remaining = k - starts.length;
              for (var i = 0; i < restStarts.length; i++) {
                if (remaining < restStarts[i].length) {
                  dy = state.dyForCharInRest(i, restStarts[i][remaining]);
                  break;
                }
                remaining -= restStarts[i].length;
              }
            }
          }
          ys.add(dy == null ? top : top + dy);
        }
        continue;
      }
      if (width <= 0) {
        for (int k = 0; k < count; k++) {
          ys.add(top);
        }
        continue;
      }
      final (base, topMargin) = _measureStyleFor(region.content);
      final locator =
          LineLocator.forHtml(html: region.content, base: base, maxWidth: width);
      try {
        for (int k = 0; k < count; k++) {
          final at = locator.charOfMatch(folded, k);
          ys.add(at == null ? top : top + topMargin + locator.dyForChar(at));
        }
      } finally {
        locator.dispose();
      }
    }
    _matchYs = ys;
  }

  /// Горният отстъп на списъка плюс височината на заглавието — всичко, което
  /// стои НАД първия регион в скрола. Виж SliverPadding в build().
  double get _contentTop {
    const topPadding = 8.0;
    final extents = _realItemExtents;
    final prepared = _prepared;
    if (extents == null || extents.isEmpty || prepared == null) {
      return topPadding;
    }
    return topPadding + (prepared.hasOwnTitle ? 0.0 : extents.first);
  }

  /// Луфтът между заглавната част и буквицата — вмъква се СЛЕД първия
  /// регион, тъй че важи за всички следващи.
  double get _gapBeforeRegions {
    final prepared = _prepared;
    if (prepared == null || !prepared.hasGap) return 0.0;
    return _titleGap;
  }

  /// Цялата дължина на съдържанието в скрола — знаменателят за чертичките.
  /// Показалецът на скролбара се движи в ТОВА пространство.
  double get _totalContentHeight {
    const topPadding = 8.0;
    const bottomPadding = 60.0;
    final extents = _realItemExtents;
    if (extents != null && extents.isNotEmpty) {
      return topPadding +
          extents.fold<double>(0, (a, b) => a + b) +
          bottomPadding;
    }
    final cumulative = _effectiveCumulativeHeights;
    if (cumulative.isEmpty) return 0;
    return topPadding + cumulative.last + bottomPadding;
  }

  /// Отстоянието вляво/вдясно на текстовата колона — виж SliverPadding в
  /// build(). Мерещият трябва да ползва СЪЩАТА ширина като рисуващият.
  static const double _horizontalPadding = 16.0;

  /// Позицията (0..1) на всяко съвпадение спрямо цялата преценена дължина
  /// на текста. Ползва се за чертичките по скролбара.
  List<double> _allMatchRatios() {
    if (_totalMatches == 0) return const [];
    final total = _totalContentHeight;
    if (total <= 0) return const [];
    _ensureMatchYs();
    if (_matchYs.isEmpty) return const [];
    return [
      for (final y in _matchYs) (y / total).clamp(0.0, 1.0),
    ];
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
      // mainAxisMargin: 4, thickness: kReaderScrollThumb (10) — за да легнат
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
      width: kReaderScrollThumb,
      child: IgnorePointer(
        child: CustomPaint(
          painter: MatchTicksPainter(
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
              // Търси се НА ЖИВО, на всеки въведен знак — както в четеца
              // на книги. Сметката е евтина (броене по вече сгънатия
              // текст на четивото), а човек вижда отговора, докато пише.
              onChanged: (_) => _runSearch(),
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

  /// Преначертава при смяна на размера на буквицата от настройките — виж
  /// слушателя, закачен в initState.
  void _onDropCapScaleChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ReaderDropCapScale.notifier.removeListener(_onDropCapScaleChanged);
    // Прибираме евентуален висящ SnackBar веднага — иначе остава да виси и
    // след като този екран е затворен (ScaffoldMessenger е общ, не
    // локален за reader_screen). removeCurrentSnackBar (не hideCurrentSnackBar)
    // нарочно, за да изчезне мигновено, без анимация на излизане.
    _scaffoldMessenger?.removeCurrentSnackBar();
    _bookmarkIdleTimer?.cancel();
    // ЗАДЪЛЖИТЕЛНО: режимът важи за цялото приложение, не за екрана. Без
    // това дневният изглед остава без системна лента след затваряне на
    // четивото.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual,
        overlays: SystemUiOverlay.values);
    // Ако имаше чакащ (недовършил 3-те си секунди) запис на шрифта, го
    // пускаме веднага сега — иначе промяната би се изгубила при излизане.
    ReaderFontSize.flush();
    ReaderTheme.flush();
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

    // Външен линк (https://…) — с питане и с разкодиран адрес.
    // Виж external_link.dart: `&amp;` от XHTML стигаше до браузъра както си
    // е и azbyka.ru отваряше Писанието само на църковнославянски.
    if (mounted) await openExternal(context, url);
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
    // Точките живеят в reader_more_menu.dart — общи с четеца на книги.
    final selected = await showReaderMoreMenu(context, items: kReaderMenuItems);
    if (!mounted || selected == null) return;
    if (selected == kReaderSettingsMenuItem.value) {
      // Настройка на четеца — като локална, се появява като drawer, СЪЩИЯТ
      // принцип, който важи навсякъде другаде (виж SettingsDrawer в
      // календара); цял отделен екран е само за общите настройки от
      // главното меню.
      _scaffoldKey.currentState?.openEndDrawer();
    } else if (selected == kBookmarksMenuItem.value) {
      Navigator.of(context).push(
        MaterialPageRoute(
        builder: (_) => BookmarksListScreen(
          load: () => allBookmarkEntries(widget.lookup),
        ),
        ),
      );
    } else if (selected == kSharePdfMenuItem.value) {
      _shareAsPdf();
    }
  }


  /// Сглобява PDF (A4) от същия HTML, който се показва в четеца, и отваря
  /// стандартния диалог за споделяне. Виж pdf_export.dart за оформлението.
  Future<void> _shareAsPdf() async {
    // Заглавието идва от името на светията, а тялото — от вече готовия
    // HTML; така PDF-ът съдържа точно това, което потребителят чете.
    // Обработката на неуспеха е в shareReaderPdf — обща с четеца на книги.
    await shareReaderPdf(
      context,
      title: widget.texts.name,
      bodyHtml: _buildPdfHtmlFor(widget._mode, widget.texts),
      fileName: '${_typeLabel.toLowerCase()} - ${widget.texts.name}.pdf',
      // Буквица САМО за житието — точно както в четеца. Тропарите,
      // кондаците и службата започват без водеща заглавна буква.
      withDropCap: widget._mode == _ReaderMode.life,
      strongIsWine: widget._mode == _ReaderMode.sluzhba,
      prayerLike: widget._mode != _ReaderMode.life,
    );
  }

  String get _typeLabel =>
      widget.typeLabel ??
      (widget._mode == _ReaderMode.life
          ? (widget.lifeTitle ?? 'Житие')
          : widget._mode == _ReaderMode.sluzhba
              ? 'Служба'
              : prayersTitleFor(widget.texts));

  // Палитрата на четеца живее в reader_theme.dart — обща с четеца на
  // книги. Тукашните имена са запазени само за да не се пипат стотиците
  // им употреби из екрана.
  ReaderPalette get _p => ReaderTheme.palette;
  Color get _bg => _p.bg;
  Color get _ink => _p.ink;
  Color get _dim => _p.dim;
  Color get _wine => _p.wine;
  //Color get _wine => ReaderTheme.dark ? const Color(0xFFA84444) : const Color(0xFF7A1F1F);

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
                toolbarHeight: kReaderToolbarHeight,
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

    // Височина на водещата буква ≈ 5–6 реда основен текст (малка), 7–8
    // (средна) или 10–11 (голяма) — виж drop_cap_scale.dart.
    final lineHeightPx = ReaderFontSize.value * kReaderLineHeight; //1.5;
    final dropCapSize = lineHeightPx *
        ReaderDropCapScale.value.linesMultiplier *
        0.82; // корекция за ascender

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
        ReaderFontSize.value,
        kReaderLineHeight,
        _viewportWidth,
        linkCount: prepared.regionLinkCounts[i],
      );
      _cumulativeHeights[i] = running;
    }
    final foldedQuery = _committedQuery.isEmpty
        ? ''
        : fold(_committedQuery).text;

    int matchOffset = 0;
    final regionWidgets = <Widget>[];
    for (int i = 0; i < regions.length; i++) {
      final r = regions[i];
      final count = i < _regionMatchCounts.length ? _regionMatchCounts[i] : 0;
      final key = _regionKeys[i];
      if (r.isHtml) {
        final data = foldedQuery.isEmpty
            ? r.content
            : highlightHtml(
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
          child: DropCapParagraph(
            key: _dropCapKey,
            dropCap: dropCap,
            dropCapSize: dropCapSize,
            offsetScale: ReaderDropCapScale.value.offsetMultiplier,
            lineHeight: lineHeightPx,
            lineFactor: kReaderLineHeight,
            firstParagraph: r.content,
            restParagraphs: r.rest,
            fontSize: ReaderFontSize.value,
            capColor: _wine,
            inkColor: _ink,
            linkColor: _p.link,
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
                fontFamily: kTitleFamily,
      fontFamilyFallback: kTitleFallback,
                // Изравнено с четеца на книги (виж стила на h3 там): при
                // междуредие 1.25 по-дългите заглавия се разсипваха на
                // разредени редове вместо да стоят като един надпис.
                fontSize: ReaderFontSize.value + 12,
                height: 1.05,
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
            child: DropCapParagraph(
              dropCap: dropCap,
              dropCapSize: dropCapSize,
              offsetScale: ReaderDropCapScale.value.offsetMultiplier,
              lineHeight: lineHeightPx,
              lineFactor: kReaderLineHeight,
              firstParagraph: r.content,
              restParagraphs: r.rest,
              fontSize: ReaderFontSize.value,
              capColor: _wine,
              inkColor: _ink,
              linkColor: _p.link,
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
                onTap: () => setState(() => ReaderTheme.dark = !ReaderTheme.dark),
                customBorder: const CircleBorder(),
                child: Container(
                  width: _btnSize,
                  height: _btnSize,
                  alignment: Alignment.center,
                  child: CustomPaint(
                    size: const Size(_btnSize - 0, _btnSize - 0),
                    painter: HalfMoonPainter(
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
              enabled: ReaderFontSize.value > ReaderFontSize.min,
              onTap: () => _bump(-ReaderFontSize.step),
              size: _btnSize,
            ),
            const SizedBox(width: 18), // Разстояние между (-) и (+)
            RoundIconButton(
              icon: Icons.add,
              tooltip: 'По-едър шрифт',
              enabled: ReaderFontSize.value < ReaderFontSize.max,
              onTap: () => _bump(ReaderFontSize.step),
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
        preferredSize: Size.fromHeight(kSearchBarHeight * value),
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
        // Заковава се временно след +/- на шрифта — виж _toolbarPinned.
        floating: !_toolbarPinned,
        snap: !_toolbarPinned,
        pinned: _toolbarPinned,
        backgroundColor: AppColors.toolbar,
        toolbarHeight: kReaderToolbarHeight,
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
          toolbarHeight: kReaderToolbarHeight,
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
        // Темата е ОБЩА с четеца на книги — виж readerScrollbarTheme.
        data: readerScrollbarTheme(_p),
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
        key: _scaffoldKey,
        backgroundColor: AppColors.toolbar,
        endDrawer: const SettingsDrawer(sections: {SettingsSection.reader}),
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
                      child: ResumePrompt(
                        background: _p.sheet,   // ⚠ от палитрата, не закован цвят:
                                   // в светла тема тъмният фон правеше
                                   // прозорчето нечетимо (текстът също е
                                   // тъмен), а в тъмна се сливаше със
                                   // страницата.
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
  static const double _tipikonSignBox = kReaderLineHeight;

  /// Знаците на Типикона, вградени в текста като `<znak n="1">`…`<znak n="5">`.
  /// Ползват се в справочната статия "Знаците от Типикона": там оригиналът
  /// ги описваше с текстови заместители ((+), +), +, (:· …), а два от петте
  /// заместителя СЪВПАДАХА и се различаваха само по цвят — разликата се
  /// губеше напълно. Тук се рисуват същите SVG-та, които стоят и до
  /// светиите в календара (виж AppIcons.forRank), в цветовете на четеца.
  List<HtmlExtension> get _tipikonExtensions => [
        // Горният индекс — общ с четеца на книги, за да не подскача
        // номерът на бележка между двата начина на рисуване.
        const ReaderSupExtension(),
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
            // Двата размера са ВРЪЗАНИ за ReaderFontSize.value, за да растат и намаляват
            // заедно с текста от бутоните −/+ (виж _tipikonSignBox защо
            // кутията е по-малка от рисунката).
            final box = ReaderFontSize.value * _tipikonSignBox;
            final draw = ReaderFontSize.value * _tipikonSignScale;
            // Рисунката се излива извън кутията и НАСТРАНИ, не само нагоре и
            // надолу — затова изяждаше интервала преди тирето след себе си.
            // Отстъпът покрива преливането ((draw−box)/2) плюс нормалното
            // разстояние между знак и дума, и расте заедно с шрифта.
            final side = (draw - box) / 2 + ReaderFontSize.value * 0.34;
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

  /// Стиловете живеят в reader_styles.dart — общи с четеца на книги.
  /// Класовете (.csl, .trans, .prayerhead, .source, .dropcap…) идват от
  /// самите текстове, тъй че двата четеца трябва да ги рисуват еднакво.
  Map<String, Style> _htmlStyles(BuildContext context) => readerStyles(
        fontSize: ReaderFontSize.value,
        palette: _p,
        // В службата <strong> носи богослужебните указания и по традиция
        // се пише в червено; в житието същият таг е обикновено ударение.
        strongInWine: widget._mode == _ReaderMode.sluzhba,
      );
}







/// Отметките от житията/службите, преведени към общия вид на списъка.
///
/// Живее ТУК, защото само този файл вижда хранилището им и знае как се
/// отваря четиво. Самият списък ([BookmarksListScreen]) не знае нищо за
/// светии — виж bookmarks.dart.
Future<List<BookmarkEntry>> livesBookmarkEntries(SaintLookup lookup) async {
  final items = await _BookmarkStore.loadAll();
  return [
    for (final (id, record) in items)
      BookmarkEntry(
        id: 'life:${id.mode.name}:${id.slug}',
        title: record.name,
        typeLabel: record.typeLabel,
        group: '', // житията вървят без група
        savedAtMs: record.savedAtMs,
        delete: () => _BookmarkStore.clear(id.slug, id.mode),
        open: (context) async {
          final texts = await lookup(id.slug);
          if (!context.mounted) return;
          if (texts == null) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Няма запис за този светия.')),
            );
            return;
          }
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => switch (id.mode) {
                _ReaderMode.life =>
                  ReaderScreen.life(texts: texts, lookup: lookup),
                _ReaderMode.prayers =>
                  ReaderScreen.prayers(texts: texts, lookup: lookup),
                _ReaderMode.sluzhba =>
                  ReaderScreen.sluzhba(texts: texts, lookup: lookup),
              },
            ),
          );
        },
      ),
  ];
}
