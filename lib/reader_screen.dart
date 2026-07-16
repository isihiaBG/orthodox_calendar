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
    '&ndash;': '\u2013',   // –
    '&mdash;': '\u2014',   // —
    '&nbsp;': '\u00A0',
    '&laquo;': '\u00AB',   // «
    '&raquo;': '\u00BB',   // »
    '&bdquo;': '\u201E',   // „
    '&ldquo;': '\u201C',   // “
    '&rdquo;': '\u201D',   // ”
    '&lsquo;': '\u2018',
    '&rsquo;': '\u2019',
    '&hellip;': '\u2026',  // …
    '&middot;': '\u00B7',
    '&deg;': '\u00B0',
    '&amp;': '&',
    '&lt;': '<',
    '&gt;': '>',
    '&quot;': '"',
    '&apos;': "'",
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

enum _ReaderMode { life, prayers, sluzhba }

class ReaderScreen extends StatefulWidget {
  final SaintTexts texts;
  final SaintLookup lookup;
  final _ReaderMode _mode;

  const ReaderScreen.life({
    super.key,
    required this.texts,
    required this.lookup,
  }) : _mode = _ReaderMode.life;

  const ReaderScreen.prayers({
    super.key,
    required this.texts,
    required this.lookup,
  }) : _mode = _ReaderMode.prayers;

  const ReaderScreen.sluzhba({
    super.key,
    required this.texts,
    required this.lookup,
  }) : _mode = _ReaderMode.sluzhba;

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  // Размерът е static: пази се за цялата сесия, общ за всички екрани
  // на четеца. 17 е базата; стъпка 1.5; разумни граници.
  // Тема на четеца — НЕЗАВИСИМА от темата на приложението.
  // static: пази се за сесията, обща за всички екрани на четеца.
  static bool _darkMode = true;   // по подразбиране тъмна

  static double _fontSize = 22.0; //Първоначален размер на шрифта по подразбиране
  static const double _step = 1.5;
  static const double _btnSize = 22.0;   // еднакъв размер и за трите бутона
  static const double _min = 13.0;
  static const double _max = 30.0;
  static const double _lineHeight = 1.25;

  void _bump(double d) {
    setState(() {
      _fontSize = (_fontSize + d).clamp(_min, _max);
    });
  }

  // ---------------------------------------------------------------
  // Съставяне на HTML
  // ---------------------------------------------------------------

  /// Отделя: (HTML преди първия <p> — напр. <h3> заглавие; първата буква;
  /// текстът на първия <p> без буквата; останалият HTML след първия <p>).
  /// Буквата се вади от първия <p>, а заглавието остава на пълна ширина.
  (String, String, String, String) _splitDropCap(String html) {
    final pm = RegExp(r'<p>(.*?)</p>', dotAll: true).firstMatch(html);
    if (pm == null) return (html, '', '', '');
    final before = html.substring(0, pm.start);
    final pInner = pm.group(1)!;
    final after = html.substring(pm.end);

    final cm = RegExp(r'^\s*(\S)').firstMatch(pInner);
    if (cm == null || !RegExp(r'[А-Яа-яA-Za-z]').hasMatch(cm.group(1)!)) {
      // Няма буква за инициал — всичко тече нормално.
      return (html, '', '', '');
    }
    final ch = cm.group(1)!;
    final pRest = pInner.substring(cm.end);
    return (before, ch, pRest, after);
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

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(url)));
  }

  // ---------------------------------------------------------------

  // Палитрата на четеца — независима от темата на приложението.
  Color get _bg   => _darkMode ? const Color(0xFF121212) : const Color(0xFFFAF7F0);
  Color get _ink  => _darkMode ? const Color(0xFFE6E1D8) : const Color(0xFF1A1A1A);
  Color get _dim  => _darkMode ? const Color(0xFF9A948A) : const Color(0xFF6B675F);
  Color get _wine => _darkMode ? const Color(0xFFA84444) : const Color(0xFF7A1F1F);

  @override
  Widget build(BuildContext context) {
    final title = widget._mode == _ReaderMode.life
        ? 'Житие'
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

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        title: Text(title),
        actions: [
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
          const SizedBox(width: 24), // Разстояние между Тогъл и (-)
          _RoundIconButton(
            icon: Icons.remove,
            tooltip: 'По-дребен шрифт',
            enabled: _fontSize > _min,
            onTap: () => _bump(-_step),
            size: _btnSize,
          ),
          const SizedBox(width: 24), // Разстояние между (-) и (+)
          _RoundIconButton(
            icon: Icons.add,
            tooltip: 'По-едър шрифт',
            enabled: _fontSize < _max,
            onTap: () => _bump(_step),
            size: _btnSize,
          ),
          const SizedBox(width: 30), // Разстояние до десния край
        ],
      ),
      body: SafeArea(
        child: ScrollbarTheme(
          // Палецът следва темата на ЧЕТЕЦА, не на приложението.
          data: ScrollbarThemeData(
            thumbColor: WidgetStatePropertyAll(_dim.withOpacity(0.55)),
            radius: const Radius.circular(3),
            thickness: const WidgetStatePropertyAll(4),
          ),
          child: Scrollbar(
            // Появява се при скрол и плавно избледнява след бездействие.
            //timeToFade: const Duration(milliseconds: 800),
            //fadeDuration: const Duration(milliseconds: 400),
            child: SelectionArea(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 60),
                children: [
            // Името на светията — само ако житието няма собствено заглавие
            if (!hasOwnTitle)
              Padding(
                padding: const EdgeInsets.only(top: 10, bottom: 6),
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
              ),

            // Заглавието на житието (напр. <h3>) — на пълна ширина
            if (dropCap.isNotEmpty && beforeHtml.trim().isNotEmpty)
              Html(
                data: beforeHtml,
                onLinkTap: (url, attributes, element) => _onLinkTap(url),
                style: _htmlStyles(context),
              ),

            // Водеща буква с ИСТИНСКО обтичане: първите редове с отстъп,
            // останалият текст — на пълна ширина под буквата
            if (dropCap.isNotEmpty)
              _DropCapParagraph(
                dropCap: dropCap,
                dropCapSize: dropCapSize,
                lineHeight: lineHeightPx,
                lineFactor: _lineHeight,
                firstParagraph: firstP,
                afterHtml: afterHtml,
                fontSize: _fontSize,
                capColor: _wine,
                inkColor: _ink,
                onLinkTap: _onLinkTap,
                styles: _htmlStyles(context),
              )
            else
              Html(
                data: beforeHtml,
                onLinkTap: (url, attributes, element) => _onLinkTap(url),
                style: _htmlStyles(context),
              ),
          ],
              ),
            ),
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
        margin: Margins.only(top: 18, bottom: 40),
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
      // Линковете: синьото на секциите от дневния изглед, не лилаво.
      'a': Style(
        color: AppColors.sectionTitle,
        textDecoration: TextDecoration.none,
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
  final String afterHtml;      // всичко след първия </p>
  final double fontSize;
  final Color capColor;
  final Color inkColor;
  final Future<void> Function(String?) onLinkTap;
  final Map<String, Style> styles;

  const _DropCapParagraph({
    required this.dropCap,
    required this.dropCapSize,
    required this.lineHeight,
    required this.lineFactor,
    required this.firstParagraph,
    required this.afterHtml,
    required this.fontSize,
    required this.capColor,
    required this.inkColor,
    required this.onLinkTap,
    required this.styles,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final capWidth = dropCapSize * 0.40; // приблизителна ширина на глифа
      const gap = 4.0;
      final narrowWidth = constraints.maxWidth - capWidth - gap;
      final capLines = (dropCapSize / lineHeight).ceil();

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
                child: Text(
                  wrapText,
                  textAlign: TextAlign.justify,
                  style: TextStyle(
                    fontFamily: _bodyFamily,
                    fontSize: fontSize,
                    height: lineFactor,
                    color: inkColor,
                  ),
                ),
              ),
            ],
          ),
          if (restText.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                restText,
                textAlign: TextAlign.justify,
                style: TextStyle(
                  fontFamily: _bodyFamily,
                  fontSize: fontSize,
                  height: lineFactor,
                  color: inkColor,
                ),
              ),
            ),
          if (afterHtml.trim().isNotEmpty)
            Html(
              data: afterHtml,
              onLinkTap: (url, attributes, element) => onLinkTap(url),
              style: styles,
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
          child: Icon(icon, size: size * 0.58, color: color),
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
