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

import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_theme.dart';
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
    '&ndash;' : '\u2013',   // –
    '&mdash;' : '\u2014',   // —
    '&nbsp;'  : '\u00A0',
    '&laquo;' : '\u00AB',   // «
    '&raquo;' : '\u00BB',   // »
    '&bdquo;' : '\u201E',   // „
    '&ldquo;' : '\u201C',   // “
    '&rdquo;' : '\u201D',   // ”
    '&lsquo;' : '\u2018',
    '&rsquo;' : '\u2019',
    '&hellip;': '\u2026',  // …
    '&middot;': '\u00B7',
    '&deg;'   : '\u00B0',
    '&dagger;': '\u2020',  // † кръст
    '&amp;'   : '&',
    '&lt;'    : '<',
    '&gt;'    : '>',
    '&quot;'  : '"',
    '&apos;'  : "'",
  };
  var out = s;
  named.forEach((k, v) => out = out.replaceAll(k, v));
  // Числови: &#1234; и &#x04D1;
  out = out.replaceAllMapped(RegExp(r'&#(\d+);'),
      (m) => String.fromCharCode(int.parse(m.group(1)!)));
  out = out.replaceAllMapped(RegExp(r'&#[xX]([0-9a-fA-F]+);'),
      (m) => String.fromCharCode(int.parse(m.group(1)!, radix: 16)));
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

/// Маркира съвпаденията в чист текст (за буквицата) — връща TextSpan-ове.
List<InlineSpan> _highlightPlain(
  String text,
  String foldedQuery,
  int firstGlobalIndex,
  int currentGlobalIndex,
  TextStyle baseStyle,
  Color hitBg,
  Color hitCurrentBg,
) {
  if (foldedQuery.isEmpty) return [TextSpan(text: text, style: baseStyle)];
  final folded = _fold(text);
  final spans = <InlineSpan>[];
  int from = 0, lastEnd = 0, local = 0;
  while (true) {
    final at = folded.text.indexOf(foldedQuery, from);
    if (at < 0) break;
    final origStart = folded.origIndex[at];
    final endFoldedIdx = at + foldedQuery.length - 1;
    final origEnd = folded.origIndex[endFoldedIdx] + 1;
    if (origStart > lastEnd) {
      spans.add(
          TextSpan(text: text.substring(lastEnd, origStart), style: baseStyle));
    }
    final isCurrent = (firstGlobalIndex + local) == currentGlobalIndex;
    spans.add(TextSpan(
      text: text.substring(origStart, origEnd),
      style: baseStyle.copyWith(
        backgroundColor: isCurrent ? hitCurrentBg : hitBg,
      ),
    ));
    lastEnd = origEnd;
    local++;
    from = endFoldedIdx + 1;
  }
  if (lastEnd < text.length) {
    spans.add(TextSpan(text: text.substring(lastEnd), style: baseStyle));
  }
  return spans;
}

/// Маркира съвпаденията в HTML — обвива всяко в <span class="hit(-current)">.
String _highlightHtml(
  String html,
  String foldedQuery,
  int firstGlobalIndex,
  int currentGlobalIndex,
) {
  if (foldedQuery.isEmpty) return html;
  final buf = StringBuffer();
  int local = 0;
  for (final m in RegExp(r'<[^>]+>|[^<]+').allMatches(html)) {
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
  return buf.toString();
}

/// Дели HTML на блокове по абзаци/заглавия — всеки получава свой GlobalKey,
/// за да можем да скролваме прецизно до региона с текущото съвпадение.
List<String> _splitBlocks(String html) {
  final blocks = <String>[];
  final re =
      RegExp(r'<(p|h[1-6])\b[^>]*>.*?</\1>', dotAll: true, caseSensitive: false);
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
  return _decodeEntities(innerHtml.replaceAll(RegExp(r'<[^>]+>'), ''))
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
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
  const _Region.html(this.content) : isHtml = true;
  const _Region.dropcapPlain(this.content) : isHtml = false;
}

List<_Region> _computeRegions(
    String beforeHtml, String dropCap, String firstP, String afterHtml) {
  final regions = <_Region>[];
  if (dropCap.isNotEmpty) {
    if (beforeHtml.trim().isNotEmpty) regions.add(_Region.html(beforeHtml));
    regions.add(_Region.dropcapPlain(firstP));
    for (final block in _splitBlocks(afterHtml)) {
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
  return r.isHtml
      ? _countMatchesHtml(r.content, foldedQuery)
      : _countMatchesPlain(_plainTextOf(r.content), foldedQuery);
}

enum _ReaderMode { life, prayers, sluzhba }

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

  static double _fontSize = 22.0; //Първоначален размер на шрифта по подразбиране
  static const double _step = 1.5;
  static const double _btnSize = 22.0;   // еднакъв размер и за трите бутона
  static const double _searchBtnSize = _btnSize + 6; // старт/</>  в search лентата
  static const double _min = 13.0;
  static const double _max = 30.0;
  static const double _lineHeight = 1.25;
  static const double _titleGap = 30.0;  // константно разстояние заглавие → текст
  static const double _scrollThumb = 10.0;  // дебелина на палеца на скролбара

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
  bool _isBookmarked = false; // TODO: реално запазване/зареждане на отметки
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

  /// Пресъздава скрол-контролера със стартова позиция = текущата, за да
  /// прехвърли безшумно офсета към новото Scrollable (виж коментара на
  /// _scrollController).
  void _reanchorScrollController() {
    final offset =
        _scrollController.hasClients ? _scrollController.position.pixels : 0.0;
    _scrollController.dispose();
    _scrollController = ScrollController(initialScrollOffset: offset);
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
    final query = _searchCtrl.text.trim();
    final html = _buildHtml();
    final isLife = widget._mode == _ReaderMode.life;
    final (beforeHtml, dropCap, firstP, afterHtml) =
        isLife ? _splitDropCap(html) : (html, '', '', '');
    final regions = _computeRegions(beforeHtml, dropCap, firstP, afterHtml);

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
    final estimate =
        estimateRaw.clamp(position.minScrollExtent, position.maxScrollExtent);
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
            (_) => _finishMeasuring(regionCount, hasOwnTitle, hasGap));
        return;
      }
      titleHeight = (ctx.findRenderObject() as RenderBox).size.height;
    }
    final regionHeights = <double>[];
    for (int i = 0; i < regionCount; i++) {
      final ctx = _measureKeys[i].currentContext;
      if (ctx == null) {
        WidgetsBinding.instance.addPostFrameCallback(
            (_) => _finishMeasuring(regionCount, hasOwnTitle, hasGap));
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
            hitColor: _hitColor,
            currentColor: _hitCurrentColor,
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
                contentPadding:
                    const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
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
          _RoundIconButton(
            icon: Icons.search,
            tooltip: 'Старт на търсенето',
            enabled: true,
            onTap: _runSearch,
            size: _searchBtnSize,
          ),
          const SizedBox(width: 16),
          _RoundIconButton(
            icon: Icons.chevron_left,
            tooltip: 'Предишно съвпадение',
            enabled: _totalMatches > 0,
            onTap: () => _goToMatch(-1),
            size: _searchBtnSize,
          ),
          const SizedBox(width: 16),
          _RoundIconButton(
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
    _searchAnim.dispose();
    _searchCtrl.dispose();
    _searchFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------
  // Съставяне на HTML
  // ---------------------------------------------------------------

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
    final italicStart =
        RegExp(r'^\s*<(?:em|i)\b[^>]*>', caseSensitive: false);

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

  String _buildHtml() {
    if (widget._mode == _ReaderMode.sluzhba) {
      final src = widget.texts.source.isEmpty
          ? ''
          : '<p class="source">Източник: <a href="${widget.texts.source}">'
              '${widget.texts.source}</a></p>';
      return '${widget.texts.sluzhba}$src';
    }

    if (widget._mode == _ReaderMode.life) {
      final src = widget.texts.source.isEmpty
          ? ''
          : '<p class="source">Източник: <a href="${widget.texts.source}">'
              '${widget.texts.source}</a></p>';
      return '${widget.texts.lifeHtml}$src';
    }

    final b = StringBuffer();
    void block(String csl, String trans) {
      if (csl.isEmpty) return;
      final i = csl.indexOf(': ');
      if (i > 0 && i < 40) {
        //b.write('<h3>${csl.substring(0, i)}</h3>');
        b.write('<p class="prayerhead">${csl.substring(0, i)}</p>');
        b.write('<p class="csl">${csl.substring(i + 2)}</p>');
      } else {
        b.write('<p class="csl">$csl</p>');
      }
      if (trans.isNotEmpty) {
          b.write('<p class="trans"><span class="translabel">Превод:</span> $trans</p>');
      } 
    }

    block(widget.texts.tropar, widget.texts.troparTrans);
    block(widget.texts.tropar2, widget.texts.tropar2Trans);
    block(widget.texts.kondak, widget.texts.kondakTrans);
    block(widget.texts.kondak2, widget.texts.kondak2Trans);

    if (widget.texts.source.isNotEmpty) {
      b.write('<p class="source">Източник: '
          '<a href="${widget.texts.source}">${widget.texts.source}</a></p>');
    }
    return b.toString();
  }

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
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => target.hasLife
            ? ReaderScreen.life(texts: target, lookup: widget.lookup)
            : ReaderScreen.prayers(texts: target, lookup: widget.lookup),
      ));
      return;
    }

    // Външен линк (https://…) — отваряме в браузъра по подразбиране
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не може да се отвори: $url')),
      );
    }
    // ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(url)));
  }

  // ---------------------------------------------------------------

  // Палитрата на четеца — независима от темата на приложението.
  Color get _bg   => _darkMode ? const Color(0xFF121212) : const Color(0xFFF5E6C5);
  Color get _ink  => _darkMode ? const Color(0xFFE6E1D8) : const Color(0xFF1A1A1A);
  Color get _dim  => _darkMode ? const Color(0xFF9A948A) : const Color(0xFF6B675F);
  Color get _wine => _darkMode ? const Color(0xFFA0555B) : const Color(0xFFB83333);
  //Color get _wine => _darkMode ? const Color(0xFFA84444) : const Color(0xFF7A1F1F);

  @override
  Widget build(BuildContext context) {
    final title = widget._mode == _ReaderMode.life
        ? (widget.lifeTitle ?? 'Житие')
        : widget._mode == _ReaderMode.sluzhba
            ? 'Служба'
            : prayersTitleFor(widget.texts);
    final isLife = widget._mode == _ReaderMode.life;

    final html = _buildHtml();
    final (beforeHtml, dropCap, firstP, afterHtml) =
        isLife ? _splitDropCap(html) : (html, '', '', '');

    // Житието има ли собствено заглавие (<h1>..<h6> преди първия абзац)?
    // Ако да — нашето име отгоре е излишно и се пропуска, за да няма
    // два почти еднакви заглавни реда един под друг.
    // isLife: в режима с молитвите beforeHtml съдържа целия HTML (вкл.
    // заглавията на тропарите), затова проверката важи само за житието.
    final hasOwnTitle =
        (isLife || widget._mode == _ReaderMode.sluzhba) &&
            RegExp(r'<h[1-6]\b').hasMatch(beforeHtml);

    // Височина на водещата буква ≈ 5–6 реда основен текст.
    final lineHeightPx = _fontSize * _lineHeight; //1.5;
    final dropCapSize = lineHeightPx * 5.5 * 0.82; // корекция за ascender

    // Региони за търсене/скролиране — виж _computeRegions().
    final regions = _computeRegions(beforeHtml, dropCap, firstP, afterHtml);
    if (_regionKeys.length != regions.length) {
      _regionKeys = List.generate(regions.length, (_) => GlobalKey());
    }
    _viewportWidth = MediaQuery.sizeOf(context).width;
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
    // _EstimatingListDelegate по-долу.
    _cumulativeHeights = List.filled(regions.length, 0.0);
    double running = 0;
    for (int i = 0; i < regions.length; i++) {
      final plain = _plainTextOf(regions[i].content);
      final linkCount = 'href='.allMatches(regions[i].content).length;
      running += _estimateRegionHeight(plain, _fontSize, _lineHeight, _viewportWidth,
          linkCount: linkCount);
      _cumulativeHeights[i] = running;
    }
    final foldedQuery =
        _committedQuery.isEmpty ? '' : _fold(_committedQuery).text;

    int matchOffset = 0;
    final regionWidgets = <Widget>[];
    for (int i = 0; i < regions.length; i++) {
      final r = regions[i];
      final count =
          i < _regionMatchCounts.length ? _regionMatchCounts[i] : 0;
      final key = _regionKeys[i];
      if (r.isHtml) {
        final data = foldedQuery.isEmpty
            ? r.content
            : _highlightHtml(r.content, foldedQuery, matchOffset, _currentMatch);
        regionWidgets.add(KeyedSubtree(
          key: key,
          child: Html(
            data: data,
            onLinkTap: (url, attributes, element) => _onLinkTap(url),
            style: _htmlStyles(context),
          ),
        ));
      } else {
        regionWidgets.add(KeyedSubtree(
          key: key,
          child: _DropCapParagraph(
            dropCap: dropCap,
            dropCapSize: dropCapSize,
            lineHeight: lineHeightPx,
            lineFactor: _lineHeight,
            firstParagraph: r.content,
            fontSize: _fontSize,
            capColor: _wine,
            inkColor: _ink,
            searchQuery: foldedQuery,
            firstGlobalMatchIndex: matchOffset,
            currentGlobalMatch: _currentMatch,
            hitColor: _hitColor,
            hitCurrentColor: _hitCurrentColor,
          ),
        ));
      }
      matchOffset += count;
    }
    // Разстояние след заглавната част (преди буквицата), ако имаше before-блок.
    final hasGap = dropCap.isNotEmpty && beforeHtml.trim().isNotEmpty;
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
            (_) => _finishMeasuring(regions.length, hasOwnTitle, hasGap));
      }
      final measureChildren = <Widget>[
        if (titleWidget != null)
          KeyedSubtree(key: _titleMeasureKey, child: titleWidget),
      ];
      for (int i = 0; i < regions.length; i++) {
        final r = regions[i];
        if (r.isHtml) {
          measureChildren.add(KeyedSubtree(
            key: _measureKeys[i],
            child: Html(data: r.content, style: _htmlStyles(context)),
          ));
        } else {
          measureChildren.add(KeyedSubtree(
            key: _measureKeys[i],
            child: _DropCapParagraph(
              dropCap: dropCap,
              dropCapSize: dropCapSize,
              lineHeight: lineHeightPx,
              lineFactor: _lineHeight,
              firstParagraph: r.content,
              fontSize: _fontSize,
              capColor: _wine,
              inkColor: _ink,
            ),
          ));
        }
      }
      if (hasGap) {
        measureChildren.insert(
            titleWidget != null ? 2 : 1, const SizedBox(height: _titleGap));
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
                        ? (AppBarTheme.of(context).foregroundColor ??
                                Colors.white)
                            .withOpacity(0.28)
                        : Colors.transparent,
                  ),
                  child: Icon(
                    Icons.search,
                    size: 24,
                    color:
                        AppBarTheme.of(context).foregroundColor ?? Colors.white,
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
                      outline: AppBarTheme.of(context).foregroundColor ??
                          Colors.white,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 18), // Разстояние между Тогъл и (-)
            _RoundIconButton(
              icon: Icons.remove,
              tooltip: 'По-дребен шрифт',
              enabled: _fontSize > _min,
              onTap: () => _bump(-_step),
              size: _btnSize,
            ),
            const SizedBox(width: 18), // Разстояние между (-) и (+)
            _RoundIconButton(
              icon: Icons.add,
              tooltip: 'По-едър шрифт',
              enabled: _fontSize < _max,
              onTap: () => _bump(_step),
              size: _btnSize,
            ),
            const SizedBox(width: 18), // Разстояние между (+) и отметката
            // Отметка — плосък стил (като лупата). TODO: истинско
            // запазване/зареждане на позицията; засега само визуален toggle.
            Tooltip(
              message: _isBookmarked ? 'Премахни отметката' : 'Отметни тук',
              child: InkWell(
                onTap: () => setState(() => _isBookmarked = !_isBookmarked),
                customBorder: const CircleBorder(),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: _btnSize + 8,
                  height: _btnSize + 8,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _isBookmarked
                        ? (AppBarTheme.of(context).foregroundColor ??
                                Colors.white)
                            .withOpacity(0.28)
                        : Colors.transparent,
                  ),
                  child: Icon(
                    _isBookmarked ? Icons.bookmark : Icons.bookmark_border,
                    size: 24,
                    color:
                        AppBarTheme.of(context).foregroundColor ?? Colors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10), // По-тясно — менюто е "приятел" на отметката
            // Контекстно меню — най-вдясно. TODO: истинско съдържание
            // (списъци с отметки, преименуване и т.н.).
            PopupMenuButton<String>(
              tooltip: 'Още',
              icon: Icon(
                Icons.more_vert,
                size: 24,
                color: AppBarTheme.of(context).foregroundColor ?? Colors.white,
              ),
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: 'bookmarks',
                  child: Text('Списък с отметки'),
                ),
              ],
              onSelected: (value) {},
            ),
            const SizedBox(width: 12), // Разстояние до десния край
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

    return Scaffold(
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
            ],
          ),
        ),
      ),
    );
  }

  Map<String, Style> _htmlStyles(BuildContext context) {
    return {
      // flutter_html обвива съдържанието в имплицитни <html> и <body> с
      // браузърни подразбирания за margin/padding. Тях ги нулираме, за да
      // ляга HTML текстът точно на същата ширина като първия абзац (той се
      // рендва ръчно в _DropCapParagraph и няма такива отстъпи).
      'html': Style(
        margin: Margins.zero,
        padding: HtmlPaddings.zero,
      ),
      'body': Style(
        margin: Margins.zero,
        padding: HtmlPaddings.zero,
      ),
      'p': Style(
        fontFamily: _bodyFamily,
        fontSize: FontSize(_fontSize),
        lineHeight: const LineHeight(_lineHeight),
        margin: Margins.only(top: 8, bottom: 8),
        textAlign: TextAlign.justify,
        color: _ink,
      ),
      'h3': Style(
        fontFamily: _titleFamily , // _bodyFamily,
        fontSize: FontSize(_fontSize + 10),
        lineHeight: const LineHeight(_lineHeight),
        fontWeight: FontWeight.normal,
        textAlign: TextAlign.center,
        margin: Margins.only(top: 18, bottom: 0), // bottom се управлява от _titleGap
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
      '.italic-center': Style(
        textAlign: TextAlign.center,
      ),
      // Линковете: синьото на секциите от дневния изглед, не лилаво.
      'a': Style(
        color: AppColors.sectionTitle,
        textDecoration: TextDecoration.none,
      ),
      // Маркиране на съвпаденията от търсенето — виж _highlightHtml().
      '.hit': Style(
        backgroundColor: _hitColor,
      ),
      '.hit-current': Style(
        backgroundColor: _hitCurrentColor,
      ),
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
class _DropCapParagraph extends StatelessWidget {
  final String dropCap;
  final double dropCapSize;
  final double lineHeight;   // в ПИКСЕЛИ — за сметките (колко реда до буквата)
  final double lineFactor;   // коефициентът за TextStyle.height (напр. 1.25)
  final String firstParagraph; // HTML съдържанието на първия <p> (без буквата)
  final double fontSize;
  final Color capColor;
  final Color inkColor;
  // Търсене: празен searchQuery = няма активно търсене.
  final String searchQuery;
  final int firstGlobalMatchIndex;
  final int currentGlobalMatch;
  final Color hitColor;
  final Color hitCurrentColor;

  const _DropCapParagraph({
    required this.dropCap,
    required this.dropCapSize,
    required this.lineHeight,
    required this.lineFactor,
    required this.firstParagraph,
    required this.fontSize,
    required this.capColor,
    required this.inkColor,
    this.searchQuery = '',
    this.firstGlobalMatchIndex = 0,
    this.currentGlobalMatch = -1,
    this.hitColor = const Color(0x00000000),
    this.hitCurrentColor = const Color(0x00000000),
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final capWidth = dropCapSize * 0.40; // приблизителна ширина на глифа
      const gap = 4.0;
      final narrowWidth = constraints.maxWidth - capWidth - gap;

      // Букви с descender (опашка под базовата линия) заемат повече
      // височина от останалите — обтичащата зона им дава още един ред,
      // за да не застъпи глифът първия ред под буквицата.
      const descenderCaps = {'Ч', 'Д', 'Ц', 'Щ', 'У', 'Р'};
      final extraLine = descenderCaps.contains(dropCap) ? 1 : 0;
      final capLines = (dropCapSize / lineHeight).ceil() + extraLine;

      // Чист текст (без тагове) за измерването.
      // Махаме таговете, после разкодираме entity-тата (&ndash; и др.),
      // за да не се виждат като суров код в обтичащата зона.
      final plain = _decodeEntities(
              firstParagraph.replaceAll(RegExp(r'<[^>]+>'), ''))
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();

      // Колко знака се побират в capLines реда при narrowWidth?
      final tp = TextPainter(
        text: TextSpan(
          text: plain,
          style: TextStyle(
              fontFamily: _bodyFamily, fontSize: fontSize, height: lineFactor),
        ),
        textDirection: TextDirection.ltr,
        maxLines: capLines,
      )..layout(maxWidth: narrowWidth);
      int cut = tp.didExceedMaxLines
          ? tp.getPositionForOffset(
              Offset(narrowWidth, capLines * lineHeight - 1)).offset
          : plain.length;

      // Режем на граница на дума, за да не разполовим дума.
      if (cut < plain.length) {
        final sp = plain.lastIndexOf(' ', cut);
        if (sp > 0) cut = sp;
      }

      final wrapText = plain.substring(0, cut).trim();
      final restText = plain.substring(cut).trim();

      final baseStyle = TextStyle(
        fontFamily: _bodyFamily,
        fontSize: fontSize,
        height: lineFactor,
        color: inkColor,
      );
      final wrapCount =
          searchQuery.isEmpty ? 0 : _countMatchesPlain(wrapText, searchQuery);

      // Забележка: обтичащата зона и остатъкът се рендват като ЧИСТ ТЕКСТ
      // (Html таговете на първия абзац се губят при измерването; на практика
      // първият абзац на житията е почти винаги плоски изречения, а
      // линковете в него — рядкост; следващите абзаци са си пълен Html).
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
                    dropCap,
                    style: TextStyle(
                      fontFamily: _dropCapFamily,
                      fontSize: dropCapSize,
                      height: 1.0,
                      color: capColor,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: gap),
              Expanded(
                child: searchQuery.isEmpty
                    ? Text(wrapText, textAlign: TextAlign.justify, style: baseStyle)
                    : Text.rich(
                        TextSpan(
                          children: _highlightPlain(wrapText, searchQuery,
                              firstGlobalMatchIndex, currentGlobalMatch,
                              baseStyle, hitColor, hitCurrentColor),
                        ),
                        textAlign: TextAlign.justify,
                      ),
              ),
            ],
          ),
          if (restText.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: searchQuery.isEmpty
                  ? Text(restText, textAlign: TextAlign.justify, style: baseStyle)
                  : Text.rich(
                      TextSpan(
                        children: _highlightPlain(
                            restText,
                            searchQuery,
                            firstGlobalMatchIndex + wrapCount,
                            currentGlobalMatch,
                            baseStyle,
                            hitColor,
                            hitCurrentColor),
                      ),
                      textAlign: TextAlign.justify,
                    ),
            ),
        ],
      );
    });
  }
}

/// Кръгло бутонче с икона за лентата (+ / −).
class _RoundIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool enabled;
  final VoidCallback onTap;
  final double size;

  const _RoundIconButton({
    required this.icon,
    required this.tooltip,
    required this.enabled,
    required this.onTap,
    this.size = 26,
  });

  @override
  Widget build(BuildContext context) {
    final color = enabled
        ? (AppBarTheme.of(context).foregroundColor ?? Colors.white)
        : Colors.white38;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: enabled ? onTap : null,
        customBorder: const CircleBorder(),
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: color, width: 1.3),
          ),
          child: Icon(icon, size: size * 0.72, color: color),
        ),
      ),
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
  bool shouldRepaint(covariant _HalfMoonPainter old) =>
      old.outline != outline;
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
      final y = (ratios[i].clamp(0.0, 1.0) * size.height).clamp(0.0, size.height);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), hitPaint);
    }
    // ...после ОТДЕЛНО оранжевата, рисувана НАПОСЛЕДЪК — гарантирано най-
    // отгоре в z-реда, дори когато няколко жълти са плътно една до друга и
    // иначе биха я скрили.
    if (currentIndex >= 0 && currentIndex < ratios.length) {
      final currentPaint = Paint()
        ..color = currentColor
        ..strokeWidth = 3;
      final y = (ratios[currentIndex].clamp(0.0, 1.0) * size.height)
          .clamp(0.0, size.height);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), currentPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _MatchTicksPainter old) =>
      old.ratios != ratios || old.currentIndex != currentIndex;
}
