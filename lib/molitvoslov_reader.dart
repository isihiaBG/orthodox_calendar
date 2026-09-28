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
import 'external_link.dart';
import 'molitvoslov_db.dart';
import 'molitvoslov_settings.dart';
import 'reader_theme.dart';
import 'reader_toolbar.dart';

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
      MolitvoslovLanguages.set(target == 1.0 ? 1 : 0);
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

  /// HTML на един абзац → парчета текст.
  ///
  /// В цс книгата указанията насред текста са `<span class="rubric">` —
  /// те стават винени НА МЯСТО, без да се губи редът на думите.
  List<InlineSpan> _spans(String html, ReaderPalette p, {required bool redFirst}) {
    final out = <TextSpan>[];
    final re = RegExp(r'<span class="rubric">(.*?)</span>', dotAll: true);
    var at = 0;
    for (final m in re.allMatches(html)) {
      if (m.start > at) out.add(TextSpan(text: _plain(html.substring(at, m.start))));
      out.add(TextSpan(text: _plain(m.group(1)!), style: TextStyle(color: p.wine)));
      at = m.end;
    }
    if (at < html.length) out.add(TextSpan(text: _plain(html.substring(at))));

    // ⚠ Червената ПЪРВА БУКВА на всеки абзац (указание на потребителя) —
    // рубрикацията на славянските богослужебни книги. Само ако парчето е
    // обикновен текст и буквата е главна.
    if (redFirst && out.isNotEmpty && out.first.style == null) {
      final t = out.first.text ?? '';
      final trimmed = t.trimLeft();
      if (trimmed.isNotEmpty) {
        final lead = t.substring(0, t.length - trimmed.length);
        final ch = trimmed.characters.first;
        final isCap = ch.toUpperCase() == ch && ch.toLowerCase() != ch;
        if (isCap) {
          out[0] = TextSpan(children: [
            TextSpan(text: lead),
            TextSpan(text: ch, style: TextStyle(color: p.wine)),
            TextSpan(text: trimmed.characters.skip(1).toString()),
          ]);
        }
      }
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

  /// Една молитва на един език: заглавие, после абзаците.
  Widget _unitCell(ReaderPalette p, MolUnit u, String lang) {
    final blocks = u.of(lang);
    final title = u.titleFor(lang);
    final base = _style(p, lang);
    final l = _lang(lang);
    final children = <Widget>[];
    if (title != null && title.isNotEmpty && (blocks.isNotEmpty || lang != 'bg')) {
      children.add(Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 6),
        child: Text(
          _plain(title),
          textAlign: TextAlign.center,
          style: base.copyWith(
              color: p.wine, fontWeight: FontWeight.w600, height: 1.25),
        ),
      ));
    }
    for (final b in blocks) {
      final style = b.isRubric
          ? base.copyWith(color: p.wine, fontSize: base.fontSize! - 2)
          : base;
      children.add(Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text.rich(
          TextSpan(
              style: style,
              children: _spans(b.html, p,
                  redFirst: !b.isRubric && (l?.rubricate ?? false))),
          textAlign: TextAlign.justify,
        ),
      ));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
  }

  /// Изправено: двата езика на ЕДНА молитва, наслоени и отместени по X.
  ///
  /// ⚠ Устройството е като `_slidingPair` в библейския четец и по същата
  /// причина: `Stack` взима размера на по-голямото дете, тъй че началата на
  /// молитвите съвпадат в двата езика и нищо не подскача при плъзгане, а
  /// `Transform.translate` не мени подредбата.
  Widget _slidingPair(ReaderPalette p, MolUnit u) {
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
                child: SizedBox(width: w, child: _unitCell(p, u, 'bg')),
              ),
              Transform.translate(
                offset: Offset((1 - t) * w, 0),
                child: SizedBox(width: w, child: _unitCell(p, u, _second)),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Легнало: двата езика успоредно, с черта по средата.
  Widget _parallel(ReaderPalette p, MolUnit u) => IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: _unitCell(p, u, 'bg')),
            Container(
              width: 1,
              margin: const EdgeInsets.symmetric(horizontal: 14),
              color: p.dim.withValues(alpha: 0.35),
            ),
            Expanded(child: _unitCell(p, u, _second)),
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
            Transform.translate(offset: Offset(-t * w, 0), child: SizedBox(width: w, child: a)),
            Transform.translate(offset: Offset((1 - t) * w, 0), child: SizedBox(width: w, child: b)),
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

  Widget _toolbar(ReaderPalette p, bool single, bool landscape) {
    final fg = AppBarTheme.of(context).foregroundColor ?? Colors.white;
    return Container(
      height: kReaderToolbarHeight,
      color: AppColors.toolbar,
      child: Row(children: [
        readerBackButton(context),
        Expanded(
          child: Text(
            widget.section.titleBg,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: fg, fontSize: 16),
          ),
        ),
        // Копчето за езика — само в изправено и само ако има какво да се
        // сменя; то казва кой език се вижда и при тап плъзга към другия.
        if (!single && !landscape)
          AnimatedBuilder(
            animation: _slide,
            builder: (_, _) => TextButton(
              onPressed: _toggleLanguage,
              child: Text(_slide.value >= 0.5 ? 'цс' : 'бг',
                  style: TextStyle(color: fg, fontSize: 16)),
            ),
          ),
        ...readerToolbarActions(
          context: context,
          onThemeToggle: () => setState(() => ReaderTheme.dark = !ReaderTheme.dark),
          onFontSmaller: () =>
              setState(() => MolitvoslovFontSize.nudge(-MolitvoslovFontSize.step)),
          onFontBigger: () =>
              setState(() => MolitvoslovFontSize.nudge(MolitvoslovFontSize.step)),
          fontValue: MolitvoslovFontSize.value,
          fontMin: MolitvoslovFontSize.min,
          fontMax: MolitvoslovFontSize.max,
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = ReaderTheme.palette;
    final landscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
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
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(pad, 12, pad, 0),
          itemCount: units.length + 2,
          itemBuilder: (context, i) {
            if (i == 0) {
              return _header(p, only ?? (landscape ? 'bg' : null));
            }
            if (i == units.length + 1) return _sources(p);
            final u = units[i - 1];
            if (single) return _unitCell(p, u, only);
            return landscape ? _parallel(p, u) : _slidingPair(p, u);
          },
        );
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
