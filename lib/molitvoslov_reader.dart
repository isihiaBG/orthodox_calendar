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

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import 'app_theme.dart';
import 'bible_reader.dart' show kLanguageFontFamilies;
import 'bookmarks.dart';
import 'bookmarks_all.dart';
import 'external_link.dart';
import 'molitvoslov_book.dart';
import 'molitvoslov_db.dart';
import 'molitvoslov_settings.dart';
import 'quotes_list.dart';
import 'reader_match_ticks.dart';
import 'reader_more_menu.dart';
import 'reader_theme.dart';
import 'reader_toolbar.dart';
import 'round_icon_button.dart';
import 'saint_expandable_tile.dart' show lookupBySlug;
import 'search_match.dart' show searchTerms;
import 'quote_link.dart';
import 'quote_menu.dart';
import 'quotes.dart';

/// Основното междуредие — като в библейския четец.
const double _kLineHeight = 1.35;

class MolitvoslovReader extends StatefulWidget {
  final MolSection section;

  /// Цитат, до който да се отвори (от любимите или от споделен линк).
  final ParsedQuoteLink? openAtQuote;

  /// Режим „водене на служба": отворено през плаващото копче. Тогава и в
  /// Псалтира има копче и се връща точното място. Отворен от съдържанието,
  /// Псалтирът е за самостоятелно четене — там копчето само пречи
  /// (указание на потребителя). Богослужебните книги са винаги в този режим.
  final bool serviceMode;

  /// ВГРАДЕН в панела за препратка (виж [showRefSheet]): същото оформление,
  /// но без плаващото копче и без да записва мястото и последно четеното —
  /// човекът само надниква и се връща в службата си.
  final bool embedded;

  /// Отваря се превъртян на този абзац (молитва, абзац на цс).
  final (int, int)? startAt;
  const MolitvoslovReader(
      {super.key,
      required this.section,
      this.openAtQuote,
      this.serviceMode = false,
      this.embedded = false,
      this.startAt});

  bool get inService => !embedded && (section.book != null || serviceMode);

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

  /// Височината на изгледа на четеца (не на устройството) — мярката, над
  /// която празнината получава подсказка.
  double _viewportH = 600;

  /// Ключ на всяка молитва — за скока до началото на текста и за връщането
  /// на мястото при завъртане.
  List<GlobalKey> _unitKeys = const [];

  /// Измерените височини на съдържанието: страна ('L'/'R') → молитва → px.
  final Map<String, Map<int, double>> _cellH = {'L': {}, 'R': {}};

  /// Подсказките за празнините: страна → молитва-домакин → подсказка.
  Map<String, Map<int, _GapHint>> _hints = {'L': {}, 'R': {}};
  bool _hintsQueued = false;

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

  /// Мястото на всяко намерено като ДЯЛ от цялата височина на текста.
  ///
  /// ⚠ Смята се при РИСУВАНЕ (след оформлението), не се пази отпреди: зависи
  /// от височините, а те се менят с шрифта и при завъртане (виж CLAUDE.md,
  /// „Съотношенията се смятат при рисуване"). Съотношението е просто
  /// `място / цялата дължина` — палецът представя целия екран.
  List<double> _tickRatios = const [];
  bool _ticksQueued = false;

  void _queueTicks() {
    if (_ticksQueued) return;
    _ticksQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ticksQueued = false;
      if (!mounted || !_scroll.hasClients) return;
      final total = _scroll.position.maxScrollExtent + _scroll.position.viewportDimension;
      if (total <= 0) return;
      final out = <double>[];
      final units = _units ?? const <MolUnit>[];
      for (final h in _hits) {
        final box = _unitKeys[h.unit].currentContext?.findRenderObject() as RenderBox?;
        if (box == null || !box.hasSize) continue;
        final vp = RenderAbstractViewport.of(box) as RenderBox;
        final top = box.localToGlobal(Offset.zero, ancestor: vp).dy + _scroll.offset;
        // Вътре в молитвата — по реда на абзаца: достатъчно точно за
        // чертичка, а молитвите рядко са по-високи от няколко екрана.
        final n = units[h.unit].of(h.lang).length;
        final frac = (h.block + 1.5) / (n + 2);
        out.add(((top + frac * box.size.height) / total).clamp(0.0, 1.0));
      }
      final same = out.length == _tickRatios.length &&
          [for (var i = 0; i < out.length; i++) (out[i] - _tickRatios[i]).abs() < 0.001]
              .every((x) => x);
      if (!same) setState(() => _tickRatios = out);
    });
  }

  @override
  void initState() {
    super.initState();
    // Запомня се и оттук (линк, любим цитат), не само от съдържанието.
    final b = widget.embedded ? null : bookKeyOf(widget.section);
    if (b != null) {
      MolitvoslovBookLast.loadOnce().then((_) => MolitvoslovBookLast.set(b, widget.section.id));
    }
    _load();
  }

  Future<void> _load() async {
    try {
      await Future.wait([
        ReaderTheme.loadOnce(),
        MolitvoslovFontSize.loadOnce(),
        MolitvoslovLanguages.loadOnce(),
        MolitvoslovPlaces.loadOnce(),
      ]);
      final langs = await MolitvoslovDb.languages();
      final units = await MolitvoslovDb.units(widget.section.id);
      if (!mounted) return;
      _slide.value = MolitvoslovLanguages.active.value.toDouble();
      setState(() {
        _langs = langs;
        _units = units;
        _unitKeys = [for (var i = 0; i < units.length; i++) GlobalKey()];
      });
      // Цитатът се търси СЛЕД първото оформление — тогава и ключовете, и
      // езиците по страни са налице.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        // В богослужебна книга човекът се връща ТОЧНО там, където е спрял
        // (освен ако не идва по цитат — тогава печели цитатът).
        final place = MolitvoslovPlaces.value[widget.section.id];
        if (widget.openAtQuote == null && widget.inService &&
            place != null && place.$1 < units.length) {
          _lastAnchor = place;
          _restoreSettled(place);
        }
        _goToQuote();
        if (widget.startAt != null) _revealQuote(0);
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

  /// Левият език: българският, ако го има; иначе цс с граждански шрифт.
  String get _left => _has('bg') ? 'bg' : (_has('csr') ? 'csr' : 'csl');

  /// Десният език на ЕДНА молитва — цс шрифт, ако го има, иначе граждански.
  ///
  /// ⚠ Решава се ЗА ВСЯКА МОЛИТВА, не за целия раздел: при акатистите цс
  /// шрифтът покрива само кондаците, икосите и молитвите, а канонът го има
  /// само с граждански шрифт — там дясната колона пада на него, вместо да
  /// зее празна. `null` — молитвата няма втори език.
  String? _rightOf(MolUnit u) {
    for (final l in const ['csl', 'csr']) {
      if (l != _left && u.of(l).isNotEmpty) return l;
    }
    return null;
  }

  /// Надписът на копчето за езика. ⚠ Двата цс вида се различават — при
  /// акатиста към Иисус Христос те са ЛЯВО и ДЯСНО и иначе копчето би
  /// казвало „цс" и за двете страни.
  String _langLabel(String code) => switch (code) {
        'bg' => 'бг',
        'csr' => 'цс гр.',
        _ => 'цс',
      };

  /// Десният език на раздела изобщо — за заглавието, търсенето и копчето.
  String get _second =>
      (_left != 'csl' && _has('csl')) ? 'csl' : (_left != 'csr' && _has('csr') ? 'csr' : 'csl');

  /// ⚠ Раздел само с ЕДИН език — той се показва на цялата ширина, без
  /// плъзгане (указание на потребителя). Кой е — идва от данните: у
  /// акатистите без цс извор това е българският.
  String? get _only {
    final units = _units ?? const <MolUnit>[];
    return units.any((u) => _rightOf(u) != null) ? null : _left;
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
    // ⚠ И вътрешни препратки `<a href="mol:…">` (виж [showRefSheet]) —
    // парчето помни адреса си и се рисува подчертано.
    final re = RegExp(r'<span class="rubric">(.*?)</span>|<a href="(mol:[^"]+)">(.*?)</a>',
        dotAll: true);
    var at = 0;
    for (final m in re.allMatches(html)) {
      if (m.start > at) out.add(_Run(_plain(html.substring(at, m.start)), false));
      if (m.group(2) != null) {
        out.add(_Run(_plain(m.group(3)!), false, href: _plain(m.group(2)!)));
      } else {
        out.add(_Run(_plain(m.group(1)!), true));
      }
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
      List<_Hit> hits, int? current, [List<_Hit> quote = const []]) {
    final out = <InlineSpan>[];
    var pos = 0;
    for (final r in runs) {
      final end = pos + r.text.length;
      final cuts = <int>{pos, end};
      for (final h in [...hits, ...quote]) {
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
        // ⚠ Търсенето ПОБЕЖДАВА цитата (жълтото над синьото) — както в
        // другите четци.
        if (bg == null) {
          for (final h in quote) {
            if (h.start <= a && h.end >= b) {
              bg = p.quote;
              break;
            }
          }
        }
        final href = r.href;
        out.add(TextSpan(
          text: r.text.substring(a - pos, b - pos),
          recognizer: href == null
              ? null
              : (TapGestureRecognizer()..onTap = () => showRefSheet(context, href)),
          style: (r.wine || bg != null || href != null)
              ? TextStyle(
                  color: r.wine ? p.wine : null,
                  backgroundColor: bg,
                  // В светла тема жълтото е светло — текстът върху него
                  // остава мастилен (виж [ReaderPalette.hit]).
                  decoration: href != null ? TextDecoration.underline : null,
                  decorationStyle: TextDecorationStyle.dotted,
                )
              : null,
        ));
      }
      pos = end;
    }
    return out;
  }

  // ⚠ <br> е нов ред (стихотворният Велик канон се чете ред по ред).
  static String _plain(String s) => s
      .replaceAll(RegExp(r'<br\s*/?>'), '\n')
      .replaceAll(RegExp(r'<[^>]+>'), '')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&amp;', '&');

  bool _redFirst(String lang, MolBlock b) =>
      !b.isRubric &&
      !b.isRefrain &&
      !b.isHint &&
      !b.isVerse &&
      (_lang(lang)?.rubricate ?? false);

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
    List<_Hit> quoteIn(int bi) => [
          for (final h in _quoteMarks)
            if (h.unit == ui && h.lang == lang && h.block == bi) h
        ];
    final q0 = _quoteMarks.isEmpty ? null : _quoteMarks.first;
    Key? keyFor(int bi) {
      if (cur != null && cur.unit == ui && cur.lang == lang && cur.block == bi) {
        return _hitKey;
      }
      // Началото на отворения цитат — за плъзгането до него.
      if (q0 != null && q0.unit == ui && q0.lang == lang && q0.block == bi) {
        return _quoteKey;
      }
      // Панел за препратка — мястото, на което се отваря.
      final st = widget.startAt;
      if (q0 == null && st != null && st.$1 == ui && st.$2 == bi && lang != 'bg') {
        return _quoteKey;
      }
      return null;
    }

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
                  _currentHit, quoteIn(-1))),
          textAlign: TextAlign.center,
        ),
      ));
    }
    for (var bi = 0; bi < blocks.length; bi++) {
      final b = blocks[bi];
      final style = b.isRubric
          ? base.copyWith(color: p.wine, fontSize: base.fontSize! - 2)
          : b.isIrmos
              // 4 пункта — при 2 разликата с тропарите не личеше (потребителят).
              ? base.copyWith(fontSize: base.fontSize! - 4)
          : b.isRefrain
              // Текстът на припева е посивен, за да се отделя от тропарите;
              // етикетът „Припев:" е червено парче и остава винен.
              ? base.copyWith(color: p.dim, fontSize: base.fontSize! - 2)
              : b.isHint
                  ? base.copyWith(
                      color: p.dim,
                      fontStyle: FontStyle.italic,
                      fontSize: base.fontSize! - 1)
                  : base;
      children.add(Padding(
        key: keyFor(bi),
        padding: const EdgeInsets.only(bottom: 8),
        child: Text.rich(
          TextSpan(
              style: style,
              children: _spansOf(_runs(b.html, redFirst: _redFirst(lang, b)),
                  p, hitsIn(bi), _currentHit, quoteIn(bi))),
          textAlign: TextAlign.justify,
        ),
      ));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
  }


  // ───────────────────────── празнините ─────────────────────────
  //
  // ⚠ Двата езика вървят молитва до молитва, тъй че където единият има
  // текст, а другият — не, видимата страна зее празна. Човек, който не се
  // сеща, че вдясно има друг език, вижда празен екран и не знае какво става.
  // (Указание на потребителя, 28.09.2026.) Подсказка има САМО където
  // празнината надхвърля ЕДИН ЕКРАН НА ЧЕТЕЦА — по-малките са естествени.

  /// Клетка на една страна: измереното съдържание и, ако тук започва голяма
  /// празнина, подсказката под него.
  ///
  /// ⚠ Мери се САМО съдържанието, без подсказката — инак появата ѝ мени
  /// мерките и сметката се гони сама.
  Widget _sideCell(ReaderPalette p, MolUnit u, String lang, int ui, String side) {
    final hint = (_landscape || _only != null) ? null : _hints[side]?[ui];
    final cell = _SizeReport(
      onSize: (h) => _report(side, ui, h),
      child: _unitCell(p, u, lang, ui),
    );
    if (hint == null) return cell;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [cell, _gapHintWidget(p, hint, side)],
    );
  }

  void _report(String side, int ui, double h) {
    final old = _cellH[side]![ui];
    if (old != null && (old - h).abs() < 0.5) return;
    _cellH[side]![ui] = h;
    if (_hintsQueued) return;
    _hintsQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _hintsQueued = false;
      if (mounted) _recomputeHints();
    });
  }

  void _recomputeHints() {
    final units = _units ?? const <MolUnit>[];
    final next = <String, Map<int, _GapHint>>{'L': {}, 'R': {}};
    for (final side in const ['L', 'R']) {
      final other = side == 'L' ? 'R' : 'L';
      int? host;
      var gap = 0.0;
      for (var ui = 0; ui < units.length; ui++) {
        final mine = _cellH[side]![ui] ?? 0;
        final theirs = _cellH[other]![ui] ?? 0;
        final unitH = mine > theirs ? mine : theirs;
        // ⚠ Дребните остатъци (празно заглавие, отстъп) не са „текст".
        if (mine > 24) {
          if (host != null && gap > _viewportH) {
            next[side]![host] = _GapHint(target: ui);
          }
          host = ui;
          gap = unitH - mine;
        } else {
          host ??= ui;
          gap += unitH;
        }
      }
      if (host != null && gap > _viewportH) {
        next[side]![host] = const _GapHint(target: null);
      }
    }
    String sig(Map<String, Map<int, _GapHint>> m) =>
        [for (final s in m.keys) '$s:${m[s]!.entries.map((e) => '${e.key}>${e.value.target}').join(',')}'].join('|');
    if (sig(next) != sig(_hints)) setState(() => _hints = next);
  }

  /// Името на езика в изречение: „българския текст" и т.н.
  String _langPhrase(String code) => switch (code) {
        'bg' => 'българския текст',
        'csr' => 'църковнославянския текст с граждански шрифт',
        _ => 'църковнославянския текст',
      };

  Widget _gapHintWidget(ReaderPalette p, _GapHint hint, String side) {
    final otherLang = side == 'L' ? _second : _left;
    final where = side == 'L' ? 'вдясно' : 'вляво';
    final String text;
    final IconData icon;
    final VoidCallback onTap;
    if (hint.target != null) {
      text = 'Плъзни надолу до началото на текста или виж $where '
          '${_langPhrase(otherLang)}';
      icon = Icons.arrow_downward;
      onTap = () {
        final ctx = _unitKeys[hint.target!].currentContext;
        if (ctx != null) {
          Scrollable.ensureVisible(ctx,
              alignment: 0.02,
              duration: const Duration(milliseconds: 450),
              curve: Curves.easeInOutCubic);
        }
      };
    } else {
      text = 'Виж допълнението в ${_langPhrase(otherLang)}';
      icon = side == 'L' ? Icons.arrow_forward : Icons.arrow_back;
      onTap = _toggleLanguage;
    }
    return SelectionContainer.disabled(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 12),
        child: Column(children: [
          Text(text,
              textAlign: TextAlign.center,
              style: TextStyle(color: p.dim, fontSize: 15, height: 1.35)),
          const SizedBox(height: 14),
          Material(
            color: Colors.transparent,
            shape: CircleBorder(side: BorderSide(color: p.dim, width: 1.5)),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Icon(icon, size: 34, color: p.dim),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  // ───────────────────────── завъртането ─────────────────────────
  //
  // ⚠ Четивата са дълги, а изправено и легнало са ДВЕ РАЗЛИЧНИ подредби
  // (плъзгане срещу две колони), тъй че същият пиксел сочи съвсем друго
  // място. Затова се пази МОЛИТВАТА горе и докъде в нея, а не пикселът.
  // (Указание на потребителя: „това е много важно".)

  /// Последното запомнено място — обновява се при всяко СПИРАНЕ на скрола.
  ///
  /// ⚠ Не се улавя в мига на завъртането (`didChangeMetrics`): пробвано и
  /// не сработи — дотогава подредбата вече е сменена и скролът е на нулата.
  /// Мястото, където човек е СПРЯЛ, е и точно онова, което трябва да се върне.
  (int, double)? _lastAnchor;
  bool? _prevLandscape;

  /// Докато тече връщането, собствените ни скокове не пренаписват мястото.
  bool _restoring = false;

  /// ⚠ Android завърта на НЯКОЛКО стъпки (прозорецът и лентите се
  /// преоразмеряват поотделно), тъй че подредбата се сменя повече от веднъж.
  /// Върнато само веднъж, мястото пада в междинна подредба и после се
  /// разминава — на устройството скочи с четири молитви напред. Затова
  /// връщането се повтаря, докато оформлението се успокои.
  void _restoreSettled((int, double) a) {
    _restoring = true;
    _restoreAnchor(a, 0);
    for (final ms in const [250, 600, 1000]) {
      Future.delayed(Duration(milliseconds: ms), () {
        if (mounted) _restoreAnchor(a, 0);
      });
    }
    Future.delayed(const Duration(milliseconds: 1200), () => _restoring = false);
  }

  /// Мястото в богослужебна книга се пази — виж [MolitvoslovPlaces].
  void _savePlace() {
    final a = _lastAnchor;
    if (!widget.embedded && bookKeyOf(widget.section) != null && a != null) {
      MolitvoslovPlaces.set(widget.section.id, a);
    }
  }

  (int, double)? _topAnchor() {
    final off = _scroll.offset;
    for (var ui = 0; ui < _unitKeys.length; ui++) {
      final box = _unitKeys[ui].currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) continue;
      final top = RenderAbstractViewport.of(box).getOffsetToReveal(box, 0).offset;
      final h = box.size.height;
      if (top + h > off) {
        return (ui, h <= 0 ? 0 : ((off - top) / h).clamp(0.0, 1.0));
      }
    }
    return null;
  }

  /// ⚠ Изчаква новото оформление (два кадъра: смяна на подредбата, после
  /// мерките), а непостроена молитва се пробва пак — голото `return` е
  /// тихият отказ, платен вече няколко пъти в проекта.
  void _restoreAnchor((int, double) a, int tries) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scroll.hasClients) return;
        final box = _unitKeys[a.$1].currentContext?.findRenderObject() as RenderBox?;
        if (box == null || !box.hasSize) {
          if (tries < 6) _restoreAnchor(a, tries + 1);
          return;
        }
        final top = RenderAbstractViewport.of(box).getOffsetToReveal(box, 0).offset;
        final pos = (top + a.$2 * box.size.height)
            .clamp(0.0, _scroll.position.maxScrollExtent);
        _scroll.jumpTo(pos);
      });
    });
  }

  // ───────────────────────────── търсенето ─────────────────────────────

  /// Езикът, в който се търси в ДАДЕНА молитва — онзи, който се вижда. В
  /// легнало — левият. ⚠ По молитва, защото десният език е по молитва.
  String _searchLangOf(MolUnit u) => _only ??
      (_landscape || _slide.value < 0.5 ? _left : (_rightOf(u) ?? _left));

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
    final terms = searchTerms(foldPrayerText(q).text);
    final hits = <_Hit>[];
    if (terms.isNotEmpty) {
      final units = _units ?? const <MolUnit>[];
      for (var ui = 0; ui < units.length; ui++) {
        final u = units[ui];
        final lang = _searchLangOf(u);
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
    final right = _rightOf(u);
    // Молитва без втори език стои неподвижна — при плъзгане няма към какво.
    // ⚠ Мери се и за двете страни: тя Е текст и за двете.
    if (right == null) {
      return _SizeReport(
        onSize: (h) {
          _report('L', ui, h);
          _report('R', ui, h);
        },
        child: _unitCell(p, u, _left, ui),
      );
    }
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
                    child: _selectable(t < 0.5, _sideCell(p, u, _left, ui, 'L'))),
              ),
              Transform.translate(
                offset: Offset((1 - t) * w, 0),
                child: SizedBox(
                    width: w,
                    child: _selectable(t >= 0.5, _sideCell(p, u, right, ui, 'R'))),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Легнало: двата езика успоредно, с черта по средата.
  Widget _parallel(ReaderPalette p, MolUnit u, int ui) {
    final right = _rightOf(u);
    if (right == null) return _unitCell(p, u, _left, ui);
    return IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: _unitCell(p, u, _left, ui)),
            Container(
              width: 1,
              margin: const EdgeInsets.symmetric(horizontal: 14),
              color: p.dim.withValues(alpha: 0.35),
            ),
            // ⚠ В легнало се маркира ЛЯВАТА колона — както в Библията:
            // селекция през двете колони би редувала езиците ред по ред.
            Expanded(child: _selectable(false, _unitCell(p, u, right, ui))),
          ],
        ),
      );
  }

  Widget _header(ReaderPalette p, String? only) {
    final s = widget.section;
    TextStyle st(String lang) => _style(p, lang, delta: 6).copyWith(
        fontFamily: lang == 'bg' ? kTitleFamily : null,
        fontFamilyFallback: lang == 'bg' ? kTitleFallback : null,
        // ⚠ Цветът на ТЕКСТА, не синьото на заглавията в другите четци:
        // в богослужебните книги такова оцветяване няма, а синьото не
        // пасва на мастиленото и виненото (указание на потребителя).
        color: p.ink,
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
    return _slidingPairWidgets(t(_left), t(_second));
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
    // ⚠ Източникът може да е и КНИГА без адрес (бг Псалтирът) — изписва се
    // като текст, не като връзка.
    final plainBg = <String>[];
    for (final u in urls) {
      final uri = Uri.tryParse(u);
      if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
        plainBg.add(u);
        continue;
      }
      final h = uri.host.replaceFirst('www.', '');
      if (!hosts.contains(h)) {
        hosts.add(h);
        firstUrl[h] = u;
      }
    }
    // ⚠ Адресът е от самата книга (`dc:source` в .epub-а, след пренасочването), не е гаден.
    // ⚠ Източникът на цс може да е и КНИГА без адрес (Канонникът в PDF) —
    // тогава се изписва като обикновен текст.
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
            // Цяло изречение („Текстът на български е…") — без етикет отпред.
            for (final t in plainBg)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(t),
              ),
            if (_has('csl') && widget.section.sourceCsl != null)
              _sourceAny(p, 'на църковнославянски: ', widget.section.sourceCsl!),
            if (_has('csr') && widget.section.sourceCsr != null)
              _sourceAny(p, 'на църковнославянски (граждански шрифт): ',
                  widget.section.sourceCsr!),
          ],
        ),
      ),
    );
  }

  /// Адрес → връзка с името на сайта; друго → текст както е.
  Widget _sourceAny(ReaderPalette p, String label, String value) {
    final uri = Uri.tryParse(value);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text('$label$value'),
      );
    }
    final h = uri.host.replaceFirst('www.', '');
    return _sourceLine(p, label, [h], {h: value});
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
                    child: Text(_langLabel(_slide.value >= 0.5 ? _second : _left),
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
      // ⚠ Поле за скролбара с чертичките (~12) ПЛЮС празнина поне колкото
      // между двете копчета (14) и малко отгоре — инак палецът, насочен към
      // дясното копче, хваща скролбара (бележка на потребителя, два пъти).
      // В Библията накрая стои ⚙, затова там този проблем го няма.
      const SizedBox(width: 32),
    ]);
  }

  /// ⚠ НЕВИДИМИЯТ ЕЗИК НЕ СЕ МАРКИРА. Двата езика стоят построени един до
  /// друг (само отместени), а `SelectionArea` хваща ВСЕКИ текст под себе си —
  /// без това маркиране през два абзаца би вмъкнало и скрития превод
  /// (същият капан като в библейския четец, виж `_quotableOnly` там).
  static Widget _selectable(bool on, Widget child) =>
      on ? child : SelectionContainer.disabled(child: child);

  String? _selected;

  /// Маркиране и контекстно меню — ЕДНО И СЪЩО с другите четци, заедно
  /// със „Запази цитат" и споделянето с линк ([QuotableSelectionArea]).
  ///
  /// ⚠ АДРЕСЪТ Е „раздел|страна": блоковете се броят в езика, който се
  /// вижда (невидимият е изключен от селекцията), а десният език е по
  /// молитва — затова страната, а не кодът на езика.
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
      child: QuotableSelectionArea(
        source: QuoteSource.molitvoslov,
        locator: () => '${widget.section.id}|${_quoteSide()}',
        title: () => widget.section.titleBg,
        blocks: () => _quoteBlocks(_quoteSide()).$1,
        // Ориентирът е ДО МОЛИТВАТА: блоковете вътре в нея нямат свои
        // ключове, а търсенето уточнява мястото по текста.
        blockKey: (i) {
          final map = _quoteBlocks(_quoteSide()).$2;
          return i >= 0 && i < map.length ? _unitKeys[map[i].$1] : null;
        },
        child: child,
      ),
    );
  }

  /// Коя страна се вижда — в легнало се маркира лявата.
  String _quoteSide() => (_landscape || _slide.value < 0.5) ? 'L' : 'R';

  /// Езикът на дадена страна в дадена молитва — същото правило като при
  /// рисуването.
  String _langOn(String side, MolUnit u) =>
      side == 'L' ? _left : (_rightOf(u) ?? _left);

  /// Текстът по блокове, в реда на четене, за една страна — заедно с
  /// (молитва, абзац) на всеки блок (абзац −1 = заглавието).
  ///
  /// ⚠ СЪЩИЯТ текст като рисувания: заглавието се брои само ако се показва,
  /// а абзацът — през `_runs`, както го вижда и търсенето.
  (List<String>, List<(int, int)>) _quoteBlocks(String side) {
    final texts = <String>[];
    final map = <(int, int)>[];
    final units = _units ?? const <MolUnit>[];
    for (var ui = 0; ui < units.length; ui++) {
      final u = units[ui];
      final lang = _langOn(side, u);
      final blocks = u.of(lang);
      final title = u.titleFor(lang);
      if (title != null && title.isNotEmpty && (blocks.isNotEmpty || lang != 'bg')) {
        texts.add(_plain(title));
        map.add((ui, -1));
      }
      for (var bi = 0; bi < blocks.length; bi++) {
        texts.add(_runs(blocks[bi].html, redFirst: _redFirst(lang, blocks[bi]))
            .map((r) => r.text)
            .join());
        map.add((ui, bi));
      }
    }
    return (texts, map);
  }

  /// Маркираното от отворения цитат — синьото `palette.quote`.
  List<_Hit> _quoteMarks = const [];
  final GlobalKey _quoteKey = GlobalKey();

  /// Отваря се на цитата: страната от адреса, намиране по текста, синьо
  /// маркиране и плъзгане до него.
  void _goToQuote() {
    final q = widget.openAtQuote;
    if (q == null || _units == null) return;
    final side = q.anchor.locator.split('|').elementAtOrNull(1) == 'R' ? 'R' : 'L';
    if (!_landscape) {
      _slide.value = side == 'R' ? 1 : 0;
    }
    final (texts, map) = _quoteBlocks(side);
    if (texts.isEmpty) return;
    final hit = locateParsedQuote(texts, q);
    final startB = hit.block.clamp(0, texts.length - 1);
    final endB = (startB + (q.anchor.blockEnd - q.anchor.block)).clamp(startB, texts.length - 1);
    final marks = <_Hit>[];
    for (var b = startB; b <= endB; b++) {
      final (ui, bi) = map[b];
      final lang = _langOn(side, _units![ui]);
      final len = texts[b].length;
      final from = b == startB ? hit.start.clamp(0, len) : 0;
      final to = b == endB
          ? (b == startB ? (hit.start + hit.length) : q.anchor.charEnd).clamp(from, len)
          : len;
      if (to > from) marks.add(_Hit(ui, lang, bi, from, to));
    }
    setState(() => _quoteMarks = marks);
    _revealQuote(0);
  }

  void _revealQuote(int tries) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ctx = _quoteKey.currentContext;
      if (ctx == null) {
        if (tries < 8) _revealQuote(tries + 1);
        return;
      }
      Scrollable.ensureVisible(ctx,
          alignment: 0.25,
          duration: const Duration(milliseconds: 450),
          curve: Curves.easeInOutCubic);
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = ReaderTheme.palette;
    final landscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    _landscape = landscape;
    if (_prevLandscape != null && _prevLandscape != landscape && _lastAnchor != null) {
      _restoreSettled(_lastAnchor!);
    }
    _prevLandscape = landscape;
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
        _viewportH = c.maxHeight - kReaderToolbarHeight;
        final units = _units!;
        // ⚠ Не мързелив списък: обхождането на намереното и подсказките в
        // празнините искат всяка молитва построена и измерена. Разделите са
        // по няколко десетки молитви — строят се наведнъж.
        //
        // ⚠ ЛЕНТАТА Е ВЪТРЕ В СКРОЛА и се скрива при плъзгане — както в
        // библейския четец. При търсене е ЗАКОВАНА: тя носи полето и
        // стрелките, а обхождането само мести скрола.
        return _selectionArea(p, NotificationListener<ScrollEndNotification>(
          onNotification: (_) {
            if (!_restoring) {
              _lastAnchor = _topAnchor() ?? _lastAnchor;
              _savePlace();
            }
            return false;
          },
          // ⚠ Показалецът е като в другите четци: хваща се с пръст и се влачи,
          // а докато се търси, стои постоянно видим (човек скача между
          // намереното и палецът трябва да е под пръста).
          child: ScrollbarTheme(
          data: readerScrollbarTheme(p),
          child: Scrollbar(
          controller: _scroll,
          interactive: true,
          // Постоянно видим само докато се търси и има намерено — тогава
          // чертичките стоят върху лентата и палецът е отправната точка.
          thumbVisibility: _searchOpen && _hits.isNotEmpty,
          child: CustomScrollView(
          controller: _scroll,
          slivers: [
            SliverAppBar(
              floating: !_searchOpen,
              snap: !_searchOpen,
              pinned: _searchOpen,
              toolbarHeight: kReaderToolbarHeight,
              automaticallyImplyLeading: false,
              automaticallyImplyActions: false,
              titleSpacing: 0,
              backgroundColor: AppColors.toolbar,
              surfaceTintColor: Colors.transparent,
              scrolledUnderElevation: 0,
              elevation: 0,
              title: SelectionContainer.disabled(
                  child: _toolbar(p, single, landscape)),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(pad, 12, pad, 0),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _header(p, only ?? (landscape ? _left : null)),
                    for (var ui = 0; ui < units.length; ui++)
                      KeyedSubtree(
                        key: _unitKeys[ui],
                        child: single
                            ? _unitCell(p, units[ui], only, ui)
                            : landscape
                                ? _parallel(p, units[ui], ui)
                                : _slidingPair(p, units[ui], ui),
                      ),
                    _sources(p),
                  ],
                ),
              ),
            ),
          ],
        )))));
      });
      // Чертичките за намереното — върху скролбара, по неговата геометрия
      // (crossAxisMargin 2, mainAxisMargin 4, дебелина kReaderScrollThumb).
      if (_searchOpen && _hits.isNotEmpty && _tickRatios.isNotEmpty) {
        body = Stack(children: [
          body,
          Positioned(
            right: 2,
            top: 4,
            bottom: 4,
            width: kReaderScrollThumb,
            child: IgnorePointer(
              child: CustomPaint(
                painter: MatchTicksPainter(
                  ratios: _tickRatios,
                  currentIndex: _currentHit,
                  hitColor: p.tickHit,
                  currentColor: p.tickCurrent,
                ),
              ),
            ),
          ),
        ]);
      }
      if (_searchOpen && _hits.isNotEmpty) _queueTicks();
      // ⚠ Обвивката стои ВИНАГИ (в легнало — без действия), за да е едно и
      // също дървото в двете положения: иначе скролът се пресъздава при
      // завъртане и тръгва от нулата.
      final slides = !single && !landscape;
      body = GestureDetector(
        onHorizontalDragUpdate: slides
            ? (d) {
                final dx = d.primaryDelta ?? 0;
                _slide.value = (_slide.value - dx / _textWidth).clamp(0.0, 1.0);
              }
            : null,
        onHorizontalDragEnd: slides ? (d) => _settleSlide(d.primaryVelocity ?? 0) : null,
        onHorizontalDragCancel: slides ? () => _settleSlide(0) : null,
        child: body,
      );
    }

    // ⚠ Скелетът е с цвета на лентата, а фонът на страницата е ВЪТРЕ в
    // SafeArea — инак ивицата на системната лента светва кремава в светла
    // тема (виж „Ивицата на системната лента" в CLAUDE.md).
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: AppColors.toolbar,
        // ⚠ Плаващото копче — само в богослужебните книги: списък с книгите
        // за скок между тях, докато се кара службата (указание на
        // потребителя). Отместено от десния ръб, за да не се пипа скролбарът.
        floatingActionButton: !widget.inService || widget.embedded
            ? null
            : Padding(
                padding: const EdgeInsets.only(right: 14, bottom: 8),
                child: FloatingActionButton.small(
                  heroTag: null,
                  tooltip: 'Богослужебни книги',
                  // ⚠ Цветовете на изскачащите прозорчета (`palette.sheet`,
                  // както подканата за връщане при отметките): сиво и в двете
                  // теми. Закованото тъмно се сливаше с тъмната страница.
                  backgroundColor: p.sheet,
                  foregroundColor: p.ink,
                  onPressed: () {
                    // ⚠ Мястото се взима СЕГА — скролът може още да не е
                    // спирал, а раздела ще го смени друг.
                    if (!_restoring) _lastAnchor = _topAnchor() ?? _lastAnchor;
                    _savePlace();
                    showBookSwitcher(context, widget.section);
                  },
                  child: const Icon(Icons.auto_stories),
                ),
              ),
        // ⚠ `Stack` — за етикета с книгата В ИЗРЕЗА, извън `SafeArea`
        // (виж [_bookSpine]).
        body: Stack(children: [
        SafeArea(
          // Докато няма текст, лентата стои отгоре неподвижно; с текст тя е
          // вътре в скрола (виж по-горе).
          child: _units == null || _units!.isEmpty || _error != null
              ? Column(children: [
                  _toolbar(p, single, landscape),
                  Expanded(child: Container(color: p.bg, child: body)),
                ])
              : Container(color: p.bg, child: body),
        ),
        _bookSpine(),
        ]),
      ),
    );
  }

  /// Коя книга е отворена — за всеки таб: в богослужебните се сменя книга
  /// след книга и ориентирът е най-нужен, но и в останалите помага.
  String? get _bookLabel {
    final s = widget.section;
    switch (s.tab) {
      case 'psaltir':
        return kPsalterBook;
      case 'molitvi':
        return 'Молитвеник';
      case 'kanonnik':
        return 'Канонник';
      case 'akatisti':
        return 'Акатисти';
    }
    final b = s.book;
    if (b == null) return null;
    final g = s.grp;
    if (b == 'Минеи' && g != null) return g;              // „Миней за август"
    if (b == 'Октоих' && g != null && g.startsWith('Глас')) {
      return 'Октоих, ${g.toLowerCase()}';                // „Октоих, глас 5"
    }
    return b;
  }

  /// Етикетът с книгата — В САМИЯ ИЗРЕЗ, преписан от `_chapterSpine` в
  /// bible_reader.dart (там са и всички доводи): лентата се крие при скрол,
  /// а изрезът е извън него, тъй че „в коя книга съм" стои винаги. Без фон,
  /// дребен и приглушен; в изправено — отгоре, от ръба на текста до 44% от
  /// ширината (в средата е обективът); в легнало — отвесен, от долния ръб на
  /// лентата до средата. Няма ли изрез — няма и етикет.
  Widget _bookSpine() {
    final label = _bookLabel;
    if (label == null) return const SizedBox.shrink();
    final mq = MediaQuery.of(context);
    final pad = mq.padding;
    final size = mq.size;
    final text = Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        color: AppColors.textSecondary,
        fontSize: 14,
        letterSpacing: 0.4,
        height: 1.0,
      ),
    );
    const minStrip = 20.0;
    if (pad.top >= minStrip) {
      const left = 18.0; // полето на текста (`pad` в тялото)
      return Positioned(
        top: 0,
        left: left,
        height: pad.top,
        width: size.width * 0.44 - left,
        child: Align(alignment: Alignment.centerLeft, child: text),
      );
    }
    final toCutout = size.height / 2 - kReaderToolbarHeight - 12;
    if (pad.left >= minStrip) {
      return Positioned(
        left: 0,
        top: kReaderToolbarHeight,
        width: pad.left,
        height: toCutout,
        child: RotatedBox(
          quarterTurns: 3,
          child: Align(alignment: Alignment.centerRight, child: text),
        ),
      );
    }
    if (pad.right >= minStrip) {
      return Positioned(
        right: 0,
        top: kReaderToolbarHeight,
        width: pad.right,
        height: toCutout,
        child: RotatedBox(
          quarterTurns: 1,
          child: Align(alignment: Alignment.centerLeft, child: text),
        ),
      );
    }
    return const SizedBox.shrink();
  }
}

/// Парче текст от абзац — винено (указание, червена буква) или обикновено.
/// Вътрешна препратка в богослужебна книга → ПАНЕЛ ОТДОЛУ със същия четец.
///
/// ⚠ Панел, а не нов екран (идея на потребителя): човекът не напуска
/// службата, прочита колкото му трябва и затваря с плъзгане или „назад" —
/// няма връщане от връзка, което да се управлява.
///
/// Адресът: `mol:<книга>/<заглавие на раздела>[#<начало на абзац>]` —
/// по ИМЕ и по ТЕКСТ, не по номер: номерата на разделите се разместват при
/// пресглобяване на базата (виж `pruneBookLast`).
Future<void> showRefSheet(BuildContext context, String href) async {
  final m = RegExp(r'^mol:([^/]+)/([^#]+)(?:#(.+))?$').firstMatch(href);
  if (m == null) return;
  final all = await MolitvoslovDb.sections();
  final sec = all.where((s) => s.book == m.group(1) && s.titleBg == m.group(2)).firstOrNull;
  if (sec == null || !context.mounted) return;
  (int, int)? start;
  final anchor = m.group(3);
  if (anchor != null) {
    String fold(String t) => t
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll(RegExp(r'[\u0300-\u036f\u0483-\u0489\u2de0-\u2dff\ua66f-\ua67f\s.,:;]'), '')
        .toLowerCase();
    final want = fold(anchor);
    final units = await MolitvoslovDb.units(sec.id);
    for (var ui = 0; ui < units.length && start == null; ui++) {
      final bl = units[ui].of('csl');
      for (var bi = 0; bi < bl.length; bi++) {
        if (fold(bl[bi].html).startsWith(want)) {
          start = (ui, bi);
          break;
        }
      }
    }
  }
  if (!context.mounted) return;
  final h = MediaQuery.of(context).size.height;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => SizedBox(
      height: h * 0.9,
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        child: MolitvoslovReader(section: sec, embedded: true, startAt: start),
      ),
    ),
  );
}

class _Run {
  final String text;
  final bool wine;
  final String? href;
  const _Run(this.text, this.wine, {this.href});
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

/// Подсказка в празнината: `target` — молитвата, където текстът започва
/// отново; `null` — нататък до края текст няма.
class _GapHint {
  final int? target;
  const _GapHint({required this.target});
}

/// Отчита височината на детето си след всяко оформление.
class _SizeReport extends SingleChildRenderObjectWidget {
  final ValueChanged<double> onSize;
  const _SizeReport({required this.onSize, required super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderSizeReport(onSize);

  @override
  void updateRenderObject(BuildContext context, _RenderSizeReport ro) {
    ro.onSize = onSize;
  }
}

class _RenderSizeReport extends RenderProxyBox {
  ValueChanged<double> onSize;
  _RenderSizeReport(this.onSize);

  @override
  void performLayout() {
    super.performLayout();
    onSize(size.height);
  }
}

/// Отваря цитат от молитвослова — от любимите или от споделен линк.
///
/// ⚠ `replaceStack` само при ВЪНШЕН линк — същият довод като при житията
/// (quote_incoming.dart): „назад" трябва да върне в приложението, откъдето
/// е дошъл човекът.
Future<void> openMolitvoslovQuote(NavigatorState nav, ParsedQuoteLink q,
    {bool replaceStack = false}) async {
  final id = int.tryParse(q.anchor.locator.split('|').first);
  final sections = await MolitvoslovDb.sections();
  final section = sections.where((s) => s.id == id).firstOrNull;
  if (section == null) {
    final ctx = nav.context;
    if (ctx.mounted) {
      ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
          content: Text('Този раздел го няма в молитвослова.')));
    }
    return;
  }
  final route = MaterialPageRoute<void>(
      builder: (_) => MolitvoslovReader(section: section, openAtQuote: q));
  if (replaceStack) {
    nav.pushAndRemoveUntil(route, (_) => false);
  } else {
    nav.push(route);
  }
}
