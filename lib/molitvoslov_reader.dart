// molitvoslov_reader.dart
//
// Четецът на „Молитвослов" — един раздел (утринни молитви, вечерни…) на
// български и църковнославянски.
//
// ⚠ СВОЙ четец, нарочно, а не обобщен библейски (решение на потребителя,
// 28.09.2026). Библейският е вързан за книги, глави и номерирани стихове;
// молитвата е заглавие → указания → абзаци. Отвън двата изглеждат еднакво:
// същата лента, същото плъзгане между езиците в изправено, двете колони в
// легнало, същите шрифтове и червената първа буква.
//
// ⚠ Нищо тук не чете и не пише настройките на Библията — езикът, размерът на
// шрифта и мястото са свои (molitvoslov_settings.dart).
//
// ⚠ РАЗДЕЛ БЕЗ БЪЛГАРСКИ показва само цс колоната, на цялата ширина, без
// плъзгане („когато цял раздел няма даден език, тази част от екрана се
// скрива" — указание на потребителя).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_theme.dart';
import 'bible_reader.dart' show kLanguageFontFamilies;
import 'bookmarks.dart';
import 'bookmarks_all.dart';
import 'external_link.dart';
import 'molitvoslov_db.dart';
import 'molitvoslov_settings.dart';
import 'quotes_list.dart';
import 'reader_more_menu.dart';
import 'reader_theme.dart';
import 'reader_toolbar.dart';
import 'round_icon_button.dart';
import 'saint_expandable_tile.dart' show lookupBySlug;
import 'search_match.dart' show searchTerms;
import 'selection_toolbar.dart';
import 'package:share_plus/share_plus.dart';

/// Основното междуредие — като в библейския четец.
const double _kLineHeight = 1.35;

class MolitvoslovReader extends StatefulWidget {
  final MolSection section;
  const MolitvoslovReader({super.key, required this.section});

  @override
  State<MolitvoslovReader> createState() => _MolitvoslovReaderState();
}

class _MolitvoslovReaderState extends State<MolitvoslovReader>
    with SingleTickerProviderStateMixin {
  List<MolUnit>? _units;
  List<MolLanguage> _langs = const [];
  Object? _error;

  /// 0 = българският се вижда, 1 = църковнославянският. Следва пръста.
  late final AnimationController _slide =
      AnimationController(vsync: this, value: MolitvoslovLanguages.active.value.toDouble());

  double _textWidth = 300;
  bool _landscape = false;

  // ───────────────────────────── търсенето ─────────────────────────────
  //
  // ⚠ Устроено като търсенето „в главата" на библейския четец: лентата се
  // ПРЕВРЪЩА в поле (не излиза втора), броячът е в полето, ‹ › обхождат.
  // Търси се САМО в езика, който се вижда — какво свети, това се и брои.

  bool _searchOpen = false;
  final TextEditingController _searchCtrl = TextEditingController();
  final ScrollController _scroll = ScrollController();
  String _query = '';
  List<_Hit> _hits = const [];
  int _currentHit = 0;
  final GlobalKey _hitKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      await Future.wait([
        ReaderTheme.loadOnce(),
        MolitvoslovFontSize.loadOnce(),
        MolitvoslovLanguages.loadOnce(),
      ]);
      final langs = await MolitvoslovDb.languages();
      final units = await MolitvoslovDb.units(widget.section.id);
      if (!mounted) return;
      _slide.value = MolitvoslovLanguages.active.value.toDouble();
      setState(() {
        _langs = langs;
        _units = units;
      });
    } catch (e) {
      // ⚠ Грешката се ПОКАЗВА — не бива да изглежда като „още се зарежда"
      // (правилото „зареждане / грешка / празно", виж MiniReader).
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  void dispose() {
    _slide.dispose();
    _searchCtrl.dispose();
    _scroll.dispose();
    ReaderTheme.flush();
    MolitvoslovFontSize.flush();
    super.dispose();
  }

  bool _has(String lang) =>
      (_units ?? const []).any((u) => u.of(lang).isNotEmpty);

  /// Вторият (цс) език на раздела: `csl` — истински цс шрифт, или `csr` —
  /// цс с граждански шрифт („Канонник"). Който има текст.
  String get _second => _has('csl') ? 'csl' : 'csr';

  /// ⚠ Раздел само с ЕДИН език — той се показва на цялата ширина, без
  /// плъзгане (указание на потребителя). Кой е — идва от данните: у
  /// акатистите без цс извор това е българският.
  String? get _only {
    final bg = _has('bg'), cs = _has(_second);
    if (bg && cs) return null;
    return bg ? 'bg' : _second;
  }

  MolLanguage? _lang(String code) {
    for (final l in _langs) {
      if (l.code == code) return l;
    }
    return null;
  }

  // ───────────────────────────── плъзгането ─────────────────────────────

  void _settleSlide(double velocity) {
    final target = velocity.abs() > 320
        ? (velocity < 0 ? 1.0 : 0.0)
        : (_slide.value >= 0.5 ? 1.0 : 0.0);
    _slide
        .animateTo(target,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic)
        .whenComplete(() {
      if (!mounted) return;
      // ⚠ Записът е НАКРАЯ, не на всеки кадър от жеста.
      final changed = MolitvoslovLanguages.active.value != (target == 1.0 ? 1 : 0);
      MolitvoslovLanguages.set(target == 1.0 ? 1 : 0);
      // ⚠ Преизчислява се САМО при истинска смяна на езика — жестът се
      // отказва (cancel) и при всеки тап по екрана, а безусловно
      // преизчисляване би връщало обхождането на първото съвпадение
      // (платено в библейския четец, виж „Три правила" в CLAUDE.md).
      if (changed && _query.isNotEmpty) _runSearch(_query);
    });
  }

  void _toggleLanguage() => _settleSlide(_slide.value >= 0.5 ? 600 : -600);

  // ───────────────────────────── рисуването ─────────────────────────────

  TextStyle _style(ReaderPalette p, String lang, {double delta = 0}) {
    final l = _lang(lang);
    final chain = kLanguageFontFamilies[l?.font ?? ''];
    return TextStyle(
      color: p.ink,
      fontSize: MolitvoslovFontSize.value + (l?.sizeDelta ?? 0) + delta,
      height: _kLineHeight + (l?.lineDelta ?? 0),
      fontFamily: (chain == null || chain.isEmpty) ? null : chain.first,
      fontFamilyFallback:
          (chain == null || chain.length < 2) ? null : chain.sublist(1),
    );
  }

  /// HTML на един абзац → парчета текст, всяко с цвят или без.
  ///
  /// В цс книгата указанията насред текста са `<span class="rubric">` —
  /// те стават винени НА МЯСТО, без да се губи редът на думите.
  ///
  /// ⚠ ЕДНА функция и за рисуването, и за търсенето: отместванията на
  /// намереното се броят в сбора от тези парчета, тъй че разминат ли се
  /// двете, маркирането пада на съседни думи.
  List<_Run> _runs(String html, {required bool redFirst}) {
    final out = <_Run>[];
    final re = RegExp(r'<span class="rubric">(.*?)</span>', dotAll: true);
    var at = 0;
    for (final m in re.allMatches(html)) {
      if (m.start > at) out.add(_Run(_plain(html.substring(at, m.start)), false));
      out.add(_Run(_plain(m.group(1)!), true));
      at = m.end;
    }
    if (at < html.length) out.add(_Run(_plain(html.substring(at)), false));

    // ⚠ Червената ПЪРВА БУКВА на всеки абзац (указание на потребителя) —
    // рубрикацията на славянските богослужебни книги. Само ако парчето е
    // обикновен текст и буквата е главна.
    if (redFirst && out.isNotEmpty && !out.first.wine) {
      final t = out.first.text;
      final trimmed = t.trimLeft();
      if (trimmed.isNotEmpty) {
        final lead = t.substring(0, t.length - trimmed.length);
        final ch = trimmed.characters.first;
        final isCap = ch.toUpperCase() == ch && ch.toLowerCase() != ch;
        if (isCap) {
          out.replaceRange(0, 1, [
            if (lead.isNotEmpty) _Run(lead, false),
            _Run(ch, true),
            _Run(trimmed.characters.skip(1).toString(), false),
          ]);
        }
      }
    }
    return out;
  }

  /// Парчетата → спанове, с фона на намереното.
  ///
  /// ⚠ Реже се по ОБЕДИНЕНИТЕ граници — на парчетата И на намереното, —
  /// тъй че съвпадение, пресичащо червената буква, пак свети цяло.
  List<InlineSpan> _spansOf(List<_Run> runs, ReaderPalette p,
      List<_Hit> hits, int? current) {
    final out = <InlineSpan>[];
    var pos = 0;
    for (final r in runs) {
      final end = pos + r.text.length;
      final cuts = <int>{pos, end};
      for (final h in hits) {
        if (h.start > pos && h.start < end) cuts.add(h.start);
        if (h.end > pos && h.end < end) cuts.add(h.end);
      }
      final list = cuts.toList()..sort();
      for (var i = 0; i + 1 < list.length; i++) {
        final a = list[i], b = list[i + 1];
        Color? bg;
        for (var k = 0; k < hits.length; k++) {
          final h = hits[k];
          if (h.start <= a && h.end >= b) {
            bg = identical(h, current == null ? null : _hits[current])
                ? p.hitCurrent
                : p.hit;
            break;
          }
        }
        out.add(TextSpan(
          text: r.text.substring(a - pos, b - pos),
          style: (r.wine || bg != null)
              ? TextStyle(
                  color: r.wine ? p.wine : null,
                  backgroundColor: bg,
                  // В светла тема жълтото е светло — текстът върху него
                  // остава мастилен (виж [ReaderPalette.hit]).
                )
              : null,
        ));
      }
      pos = end;
    }
    return out;
  }

  static String _plain(String s) => s
      .replaceAll(RegExp(r'<[^>]+>'), '')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&amp;', '&');

  bool _redFirst(String lang, MolBlock b) =>
      !b.isRubric && !b.isRefrain && (_lang(lang)?.rubricate ?? false);

  /// Една молитва на един език: заглавие, после абзаците.
  ///
  /// [ui] е поредният номер на молитвата — по него се познава намереното.
  Widget _unitCell(ReaderPalette p, MolUnit u, String lang, int ui) {
    final blocks = u.of(lang);
    final title = u.titleFor(lang);
    final base = _style(p, lang);
    final cur = _hits.isEmpty ? null : _hits[_currentHit];
    List<_Hit> hitsIn(int bi) => [
          for (final h in _hits)
            if (h.unit == ui && h.lang == lang && h.block == bi) h
        ];
    Key? keyFor(int bi) => (cur != null &&
            cur.unit == ui &&
            cur.lang == lang &&
            cur.block == bi)
        ? _hitKey
        : null;

    final children = <Widget>[];
    if (title != null && title.isNotEmpty && (blocks.isNotEmpty || lang != 'bg')) {
      children.add(Padding(
        key: keyFor(-1),
        padding: const EdgeInsets.only(top: 14, bottom: 6),
        child: Text.rich(
          TextSpan(
              style: base.copyWith(
                  color: p.wine, fontWeight: FontWeight.w600, height: 1.25),
              children: _spansOf([_Run(_plain(title), false)], p, hitsIn(-1),
                  _currentHit)),
          textAlign: TextAlign.center,
        ),
      ));
    }
    for (var bi = 0; bi < blocks.length; bi++) {
      final b = blocks[bi];
      final style = b.isRubric
          ? base.copyWith(color: p.wine, fontSize: base.fontSize! - 2)
          : b.isRefrain
              ? base.copyWith(fontSize: base.fontSize! - 2)
              : base;
      children.add(Padding(
        key: keyFor(bi),
        padding: const EdgeInsets.only(bottom: 8),
        child: Text.rich(
          TextSpan(
              style: style,
              children: _spansOf(_runs(b.html, redFirst: _redFirst(lang, b)),
                  p, hitsIn(bi), _currentHit)),
          textAlign: TextAlign.justify,
        ),
      ));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
  }

  // ───────────────────────────── търсенето ─────────────────────────────

  /// Езикът, в който се търси — онзи, който се вижда. В легнало — левият.
  String get _searchLang =>
      _only ?? (_landscape ? 'bg' : (_slide.value >= 0.5 ? _second : 'bg'));

  void _toggleSearch() {
    setState(() {
      _searchOpen = !_searchOpen;
      if (!_searchOpen) {
        _searchCtrl.clear();
        _query = '';
        _hits = const [];
        _currentHit = 0;
      }
    });
  }

  void _clearSearch() {
    _searchCtrl.clear();
    _runSearch('');
  }

  void _runSearch(String q) {
    final lang = _searchLang;
    final terms = searchTerms(foldPrayerText(q).text);
    final hits = <_Hit>[];
    if (terms.isNotEmpty) {
      final units = _units ?? const <MolUnit>[];
      for (var ui = 0; ui < units.length; ui++) {
        final u = units[ui];
        final blocks = u.of(lang);
        final title = u.titleFor(lang);
        if (title != null && title.isNotEmpty && (blocks.isNotEmpty || lang != 'bg')) {
          hits.addAll(_find(_plain(title), terms, ui, lang, -1));
        }
        for (var bi = 0; bi < blocks.length; bi++) {
          final text = _runs(blocks[bi].html, redFirst: _redFirst(lang, blocks[bi]))
              .map((r) => r.text)
              .join();
          hits.addAll(_find(text, terms, ui, lang, bi));
        }
      }
    }
    setState(() {
      _query = q;
      _hits = hits;
      _currentHit = 0;
    });
    if (hits.isNotEmpty) _revealCurrent();
  }

  static List<_Hit> _find(
      String text, List<String> terms, int ui, String lang, int bi) {
    final f = foldPrayerText(text);
    final found = <List<int>>[];
    for (final t in terms) {
      var from = 0;
      while (true) {
        final at = f.text.indexOf(t, from);
        if (at < 0) break;
        found.add([f.starts[at], f.ends[at + t.length - 1]]);
        from = at + 1;
      }
    }
    if (found.isEmpty) return const [];
    found.sort((a, b) => a[0].compareTo(b[0]));
    final merged = <List<int>>[found.first];
    for (final r in found.skip(1)) {
      if (r[0] <= merged.last[1]) {
        if (r[1] > merged.last[1]) merged.last[1] = r[1];
      } else {
        merged.add(r);
      }
    }
    return [for (final r in merged) _Hit(ui, lang, bi, r[0], r[1])];
  }

  void _stepHit(int d) {
    if (_hits.isEmpty) return;
    setState(() => _currentHit = (_currentHit + d) % _hits.length);
    _revealCurrent();
  }

  /// ⚠ Изчаква КАДЪР: ключът се мести със `setState`, а потърсен веднага,
  /// още виси на предишния абзац. И опитва пак, ако абзацът още не е
  /// построен — голото `return` е тихият отказ, платен вече три пъти.
  void _revealCurrent([int tries = 0]) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ctx = _hitKey.currentContext;
      if (ctx == null) {
        if (tries < 6) _revealCurrent(tries + 1);
        return;
      }
      Scrollable.ensureVisible(ctx,
          alignment: 0.25,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic);
    });
  }

  // ───────────────────────────── менюто ─────────────────────────────

  /// ⚠ Посивени, а не махнати (установеното правило): менюто е едно и също
  /// в четирите четеца. Настройките и споделянето чакат свой вид адрес за
  /// молитвослова; отметките и любимите цитати са ОБЩИ списъци и работят.
  static final Set<String> _disabledItems = {
    kReaderSettingsMenuItem.value,
    kShareReadingMenuItem.value,
    kSharePdfValue,
  };

  Future<void> _showMoreMenu() async {
    final choice = await showReaderMoreMenu(context,
        items: kReaderMenuItems, disabled: _disabledItems);
    if (!mounted || choice == null) return;
    if (choice == kBookmarksMenuItem.value) {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => BookmarksListScreen(
          load: () => allBookmarkEntries(lookupBySlug),
        ),
      ));
    } else if (choice == kQuotesMenuItem.value) {
      openQuotesList(context, lookupBySlug);
    }
  }

  /// Изправено: двата езика на ЕДНА молитва, наслоени и отместени по X.
  ///
  /// ⚠ Устройството е като `_slidingPair` в библейския четец и по същата
  /// причина: `Stack` взима размера на по-голямото дете, тъй че началата на
  /// молитвите съвпадат в двата езика и нищо не подскача при плъзгане, а
  /// `Transform.translate` не мени подредбата.
  Widget _slidingPair(ReaderPalette p, MolUnit u, int ui) {
    final w = _textWidth;
    return ClipRect(
      child: AnimatedBuilder(
        animation: _slide,
        builder: (context, _) {
          final t = _slide.value;
          return Stack(
            alignment: AlignmentDirectional.topStart,
            children: [
              Transform.translate(
                offset: Offset(-t * w, 0),
                child: SizedBox(
                    width: w,
                    child: _selectable(t < 0.5, _unitCell(p, u, 'bg', ui))),
              ),
              Transform.translate(
                offset: Offset((1 - t) * w, 0),
                child: SizedBox(
                    width: w,
                    child: _selectable(t >= 0.5, _unitCell(p, u, _second, ui))),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Легнало: двата езика успоредно, с черта по средата.
  Widget _parallel(ReaderPalette p, MolUnit u, int ui) => IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: _unitCell(p, u, 'bg', ui)),
            Container(
              width: 1,
              margin: const EdgeInsets.symmetric(horizontal: 14),
              color: p.dim.withValues(alpha: 0.35),
            ),
            // ⚠ В легнало се маркира ЛЯВАТА колона — както в Библията:
            // селекция през двете колони би редувала езиците ред по ред.
            Expanded(child: _selectable(false, _unitCell(p, u, _second, ui))),
          ],
        ),
      );

  Widget _header(ReaderPalette p, String? only) {
    final s = widget.section;
    TextStyle st(String lang) => _style(p, lang, delta: 6).copyWith(
        fontFamily: lang == 'bg' ? kTitleFamily : null,
        fontFamilyFallback: lang == 'bg' ? kTitleFallback : null,
        color: p.heading,
        height: 1.2);
    Widget t(String lang) => Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 10),
          child: Text(
            lang == 'bg' ? s.titleBg : (s.titleCsl ?? s.titleBg),
            textAlign: TextAlign.center,
            style: st(lang),
          ),
        );
    if (only != null) return t(only);
    return _slidingPairWidgets(t('bg'), t(_second));
  }

  Widget _slidingPairWidgets(Widget a, Widget b) {
    final w = _textWidth;
    return ClipRect(
      child: AnimatedBuilder(
        animation: _slide,
        builder: (context, _) {
          final t = _slide.value;
          return Stack(children: [
            Transform.translate(offset: Offset(-t * w, 0), child: SizedBox(width: w, child: _selectable(t < 0.5, a))),
            Transform.translate(offset: Offset((1 - t) * w, 0), child: SizedBox(width: w, child: _selectable(t >= 0.5, b))),
          ]);
        },
      ),
    );
  }

  /// Източниците на българския текст — накрая, като при житията.
  Widget _sources(ReaderPalette p) {
    final urls = <String>[];
    for (final u in _units ?? const <MolUnit>[]) {
      for (final url in (u.sourceBg ?? '').split('\n')) {
        if (url.isNotEmpty && !urls.contains(url)) urls.add(url);
      }
    }
    final hosts = <String>[];
    final firstUrl = <String, String>{};
    for (final u in urls) {
      final h = Uri.tryParse(u)?.host.replaceFirst('www.', '') ?? u;
      if (!hosts.contains(h)) {
        hosts.add(h);
        firstUrl[h] = u;
      }
    }
    // ⚠ Адресът е от самата книга (`dc:source` в .epub-а, след пренасочването), не е гаден.
    const csl = 'azbyka.ru';
    return Padding(
      padding: const EdgeInsets.only(top: 28, bottom: 36),
      child: DefaultTextStyle(
        style: TextStyle(color: p.dim, fontSize: 13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Източници:'),
            if (hosts.isNotEmpty)
              _sourceLine(p, 'на български: ', hosts, firstUrl),
            if (_has(_second) && widget.section.sourceCsl != null)
              _sourceLine(p, 'на църковнославянски: ', [csl],
                  {csl: widget.section.sourceCsl!}),
          ],
        ),
      ),
    );
  }

  Widget _sourceLine(ReaderPalette p, String label, List<String> hosts,
      Map<String, String> urls) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(children: [
        Text(label),
        for (var i = 0; i < hosts.length; i++) ...[
          if (i > 0) const Text(', '),
          GestureDetector(
            onTap: () => openExternal(context, urls[hosts[i]]!),
            child: Text(hosts[i],
                style: TextStyle(color: p.link, decoration: TextDecoration.underline)),
          ),
        ],
      ]),
    );
  }

  /// ⚠ Подредбата е ТОЧНО като в библейския четец (искане на потребителя):
  /// назад, заглавие, език, после общите бутони — лупа, тема, − +, ⋮.
  Widget _toolbar(ReaderPalette p, bool single, bool landscape) {
    final fg = AppBarTheme.of(context).foregroundColor ?? Colors.white;
    return Container(
      height: kReaderToolbarHeight,
      color: AppColors.toolbar,
      child: _searchOpen
          ? _searchBar(fg)
          : Row(children: [
              readerBackButton(context),
              Expanded(
                child: Text(
                  widget.section.titleBg,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: fg, fontSize: 16),
                ),
              ),
              // Копчето за езика — само в изправено и само ако има какво да
              // се сменя; то казва кой език се вижда и при тап плъзга към
              // другия.
              if (!single && !landscape)
                AnimatedBuilder(
                  animation: _slide,
                  builder: (_, _) => TextButton(
                    onPressed: _toggleLanguage,
                    child: Text(_slide.value >= 0.5 ? 'цс' : 'бг',
                        style: TextStyle(color: fg, fontSize: 16)),
                  ),
                ),
              const SizedBox(width: 4),
              ...readerToolbarActions(
                context: context,
                onSearch: _toggleSearch,
                searchOpen: _searchOpen,
                onThemeToggle: () {
                  // ⚠ Менюто живее в Overlay и не се преизгражда при смяна
                  // на темата — прибира се, както в Библията.
                  ContextMenuController.removeAny();
                  setState(() => ReaderTheme.dark = !ReaderTheme.dark);
                },
                onFontSmaller: () => setState(
                    () => MolitvoslovFontSize.nudge(-MolitvoslovFontSize.step)),
                onFontBigger: () => setState(
                    () => MolitvoslovFontSize.nudge(MolitvoslovFontSize.step)),
                fontValue: MolitvoslovFontSize.value,
                fontMin: MolitvoslovFontSize.min,
                fontMax: MolitvoslovFontSize.max,
                onMore: _showMoreMenu,
              ),
            ]),
    );
  }

  /// Лентата при търсене — същият вид като в библейския четец.
  Widget _searchBar(Color fg) {
    final stepping = _hits.length > 1;
    return Row(children: [
      IconButton(
        icon: Icon(Icons.close, color: fg),
        tooltip: 'Затвори търсенето',
        onPressed: _toggleSearch,
      ),
      Expanded(
        child: SizedBox(
          height: 38,
          child: TextField(
            controller: _searchCtrl,
            autofocus: true,
            style: TextStyle(color: fg, fontSize: 15),
            textInputAction: TextInputAction.search,
            onChanged: _runSearch,
            decoration: InputDecoration(
              isDense: true,
              hintText: 'търси в раздела',
              hintStyle:
                  TextStyle(color: fg.withValues(alpha: 0.45), fontSize: 13),
              contentPadding:
                  const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
              filled: true,
              fillColor: Colors.black.withValues(alpha: 0.15),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
              suffixIcon: _query.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.only(right: 10, left: 6),
                      child: Icon(Icons.search,
                          size: 18, color: fg.withValues(alpha: 0.45)),
                    )
                  : Padding(
                      padding: const EdgeInsets.only(right: 8, left: 6),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Text(
                          _hits.isEmpty
                              ? '0/0'
                              : '${_currentHit + 1}/${_hits.length}',
                          style: TextStyle(
                              color: fg.withValues(alpha: 0.7), fontSize: 12),
                        ),
                        const SizedBox(width: 8),
                        InkWell(
                          onTap: _clearSearch,
                          customBorder: const CircleBorder(),
                          child: Icon(Icons.close,
                              size: 18, color: fg.withValues(alpha: 0.75)),
                        ),
                      ]),
                    ),
              suffixIconConstraints:
                  const BoxConstraints(minWidth: 0, minHeight: 0),
            ),
          ),
        ),
      ),
      const SizedBox(width: 10),
      RoundIconButton(
        icon: Icons.chevron_left,
        tooltip: 'Предишно съвпадение',
        enabled: stepping,
        size: kReaderBtnSize,
        onTap: () => _stepHit(-1),
      ),
      const SizedBox(width: 14),
      RoundIconButton(
        icon: Icons.chevron_right,
        tooltip: 'Следващо съвпадение',
        enabled: stepping,
        size: kReaderBtnSize,
        onTap: () => _stepHit(1),
      ),
      const SizedBox(width: 10),
    ]);
  }

  /// ⚠ НЕВИДИМИЯТ ЕЗИК НЕ СЕ МАРКИРА. Двата езика стоят построени един до
  /// друг (само отместени), а `SelectionArea` хваща ВСЕКИ текст под себе си —
  /// без това маркиране през два абзаца би вмъкнало и скрития превод
  /// (същият капан като в библейския четец, виж `_quotableOnly` там).
  static Widget _selectable(bool on, Widget child) =>
      on ? child : SelectionContainer.disabled(child: child);

  String? _selected;

  /// Маркиране и контекстно меню — ЕДНО И СЪЩО с другите четци
  /// ([IconSelectionToolbar], същите цветове на селекцията и на менюто).
  ///
  /// ⚠ БЕЗ „Запази цитат": любимите цитати се отварят наново по адрес, а
  /// молитвословът още няма свой вид адрес. Сърчице, което запазва нещо
  /// неотворимо, би било по-лошо от липсата му. „Сподели" праща текста с
  /// надпис откъде е.
  Widget _selectionArea(ReaderPalette p, Widget child) {
    return Theme(
      data: Theme.of(context).copyWith(
        textSelectionTheme: TextSelectionThemeData(
          selectionColor: AppColors.sectionTitle.withValues(alpha: 0.35),
          selectionHandleColor: AppColors.sectionTitle,
          cursorColor: AppColors.sectionTitle,
        ),
        colorScheme: Theme.of(context).colorScheme.copyWith(
              surface: p.sheet,
              onSurface: p.ink,
            ),
      ),
      child: SelectionArea(
        onSelectionChanged: (c) => _selected = c?.plainText,
        contextMenuBuilder: (context, region) => IconSelectionToolbar(
          anchors: region.contextMenuAnchors,
          items: region.contextMenuButtonItems,
          onShareQuote: () {
            final text = _selected?.trim() ?? '';
            region.hideToolbar();
            if (text.isEmpty) return;
            Share.share('$text\n\n— из „${widget.section.titleBg}“, Молитвослов');
          },
        ),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = ReaderTheme.palette;
    final landscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    _landscape = landscape;
    final only = _only;
    final single = only != null;

    Widget body;
    if (_error != null) {
      body = Center(
          child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text('Грешка при четене на молитвослова:\n$_error',
            style: TextStyle(color: p.dim)),
      ));
    } else if (_units == null) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_units!.isEmpty) {
      body = Center(
          child: Text('В този раздел още няма текст.',
              style: TextStyle(color: p.dim)));
    } else {
      body = LayoutBuilder(builder: (context, c) {
        const pad = 18.0;
        _textWidth = c.maxWidth - 2 * pad;
        final units = _units!;
        // ⚠ Не `ListView.builder`: обхождането на намереното иска абзацът
        // да е построен, а мързеливият списък не строи невидимото.
        // Разделите са по няколко десетки молитви — строят се наведнъж.
        return _selectionArea(p, SingleChildScrollView(
          controller: _scroll,
          padding: const EdgeInsets.fromLTRB(pad, 12, pad, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(p, only ?? (landscape ? 'bg' : null)),
              for (var ui = 0; ui < units.length; ui++)
                single
                    ? _unitCell(p, units[ui], only, ui)
                    : landscape
                        ? _parallel(p, units[ui], ui)
                        : _slidingPair(p, units[ui], ui),
              _sources(p),
            ],
          ),
        ));
      });
      if (!single && !landscape) {
        body = GestureDetector(
          onHorizontalDragUpdate: (d) {
            final dx = d.primaryDelta ?? 0;
            _slide.value = (_slide.value - dx / _textWidth).clamp(0.0, 1.0);
          },
          onHorizontalDragEnd: (d) => _settleSlide(d.primaryVelocity ?? 0),
          onHorizontalDragCancel: () => _settleSlide(0),
          child: body,
        );
      }
    }

    // ⚠ Скелетът е с цвета на лентата, а фонът на страницата е ВЪТРЕ в
    // SafeArea — инак ивицата на системната лента светва кремава в светла
    // тема (виж „Ивицата на системната лента" в CLAUDE.md).
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: AppColors.toolbar,
        body: SafeArea(
          child: Column(children: [
            _toolbar(p, single, landscape),
            Expanded(child: Container(color: p.bg, child: body)),
          ]),
        ),
      ),
    );
  }
}

/// Парче текст от абзац — винено (указание, червена буква) или обикновено.
class _Run {
  final String text;
  final bool wine;
  const _Run(this.text, this.wine);
}

/// Едно намерено място: молитва, език, абзац (−1 = заглавието) и знаците.
class _Hit {
  final int unit;
  final String lang;
  final int block;
  final int start;
  final int end;
  const _Hit(this.unit, this.lang, this.block, this.start, this.end);
}

/// Сгънат текст и къде в изходния стои всеки негов знак.
class FoldedText {
  final String text;
  final List<int> starts;
  final List<int> ends;
  const FoldedText(this.text, this.starts, this.ends);
}

/// Буквите от цс азбука → гражданските, с които човек пише на клавиатура.
const Map<String, String> _kCslLetters = {
  'ѡ': 'о', 'ѻ': 'о', 'ѽ': 'о', 'ꙍ': 'о', 'ѿ': 'от',
  'ꙋ': 'у', 'ѹ': 'у', 'і': 'и', 'ї': 'и', 'ѵ': 'и', 'ѷ': 'и',
  'ѧ': 'я', 'ꙗ': 'я', 'ѣ': 'е', 'є': 'е', 'ѥ': 'е',
  'ѯ': 'кс', 'ѱ': 'пс', 'ѳ': 'ф', 'ѕ': 'з', 'ꙁ': 'з', 'ꙃ': 'з',
  'ꙑ': 'ы', 'ѫ': 'у',
};

bool _isMark(int c) =>
    (c >= 0x0300 && c <= 0x036F) ||
    (c >= 0x0483 && c <= 0x0489) ||
    (c >= 0x2DE0 && c <= 0x2DFF) ||
    (c >= 0xA66F && c <= 0xA67F) ||
    c == 0x0482;

/// Сгъва текст за търсене: малки букви, без ударения и надредни знаци, с
/// цс буквите сведени до гражданските („ѡ" → „о", „оу" → „у").
///
/// ⚠ Пази за всеки сгънат знак мястото му в ИЗХОДНИЯ текст — маркирането
/// става там, а сгъването мени дължината (махнати знаци, „ѿ" → „от").
/// Краят на всеки знак поглъща и надредните след него, за да свети цялата
/// буква, а не само основата ѝ.
FoldedText foldPrayerText(String src) {
  final lower = src.toLowerCase();
  final buf = StringBuffer();
  final starts = <int>[], ends = <int>[];
  final cu = lower.codeUnits;
  var i = 0;
  while (i < cu.length) {
    final c = cu[i];
    if (_isMark(c)) {
      i++;
      continue;
    }
    // Краят на буквата — след надредните знаци подир нея.
    var j = i + 1;
    while (j < cu.length && _isMark(cu[j])) {
      j++;
    }
    final ch = String.fromCharCode(c);
    // „оу" (диграф за у) → „у", ако следващата буква е „у"/„ꙋ".
    if (ch == 'о' && j < cu.length) {
      final nx = String.fromCharCode(cu[j]);
      if (nx == 'у' || nx == 'ꙋ') {
        var k = j + 1;
        while (k < cu.length && _isMark(cu[k])) {
          k++;
        }
        buf.write('у');
        starts.add(i);
        ends.add(k);
        i = k;
        continue;
      }
    }
    final out = _kCslLetters[ch] ?? ch;
    for (var n = 0; n < out.length; n++) {
      buf.write(out[n]);
      starts.add(i);
      ends.add(j);
    }
    i = j;
  }
  return FoldedText(buf.toString(), starts, ends);
}
