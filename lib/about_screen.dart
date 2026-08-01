// about_screen.dart
//
// Секцията "За приложението" от главното меню. Буквицата-с-обтичане тук е
// самостоятелна, по-проста версия на техниката от reader_screen.dart —
// нарочно НЕ е извлечена оттам, за да не пипаме работещия код на четеца
// (там версията носи и логика за маркиране при търсене, която тук не ни
// трябва). Визуалният резултат е същият.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_drawer.dart';
import 'app_theme.dart';

const String _titleFamily = 'TamburinModern';
const String _dropCapFamily = 'Bukvica';
const String _bodyFamily = 'Cambria';
const Color _ink = AppColors.textPrimary;
const Color _wine = Color(0xFFA0555B);

const double _fontSize = 22.0;
const double _lineHeight = 1.25;

const String _firstParagraph =
    'риложение за църковен календар на български език, което показва '
    'паметта на светиите, жития, тропари и кондаци за всеки ден, както по '
    'стар (юлиански), така и по нов (григориански) стил. Приложението е с '
    'отворен код и се разработва с некомерсиална, просветителска цел.';

const String _authorParagraph =
    'Създател е иером. Калиник (Василев). Негов старец е архим. Евгений '
    '(Райков), под чието духовно ръководство се наставлява от 1994 год. и до днес.';

const String _closingParagraph =
    'Приятно и спасително прекарване на времето с вдъхновяващите разкази '
    'от житията и възпоменанията за нашите хубави православни празници!';

const String _feedbackEmail = 'isihiaBG.orthodox.calendar@gmail.com';
const String _githubUrl = 'https://github.com/isihiaBG/orthodox_calendar';

/// Лек отстъп само на ПЪРВИЯ ред на абзац (като Tab) — Flutter няма вграден
/// "text-indent"; трикът е WidgetSpan с невидима кутия като първи inline
/// елемент — засяга само първия ред, не пренесените.
const WidgetSpan _firstLineIndent = WidgetSpan(child: SizedBox(width: 28));

class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  late final TapGestureRecognizer _emailTap;
  late final TapGestureRecognizer _githubTap;

  @override
  void initState() {
    super.initState();
    _emailTap = TapGestureRecognizer()..onTap = _openEmail;
    _githubTap = TapGestureRecognizer()..onTap = _openGithub;
  }

  @override
  void dispose() {
    _emailTap.dispose();
    _githubTap.dispose();
    super.dispose();
  }

  Future<void> _openEmail() async {
    final uri = Uri(scheme: 'mailto', path: _feedbackEmail);
    await launchUrl(uri);
  }

  Future<void> _openGithub() async {
    await launchUrl(Uri.parse(_githubUrl), mode: LaunchMode.externalApplication);
  }

  TextSpan _linkSpan(String text, TapGestureRecognizer recognizer) {
    return TextSpan(
      text: text,
      recognizer: recognizer,
      style: const TextStyle(
        color: AppColors.sectionTitle,
        decoration: TextDecoration.none,
        fontSize: _fontSize - 4,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final logoSize = (MediaQuery.of(context).size.width * 0.55).clamp(160.0, 260.0);
    const bodyStyle = TextStyle(
      fontFamily: _bodyFamily,
      fontSize: _fontSize,
      height: _lineHeight,
      color: _ink,
    );
    const smallItalicStyle = TextStyle(
      fontFamily: _bodyFamily,
      fontSize: _fontSize - 2,
      fontStyle: FontStyle.italic,
      height: _lineHeight,
      color: _ink,
    );

    return Scaffold(
      backgroundColor: AppColors.toolbar,
      // Меню вместо стрелка "назад" — от всеки екран потребителят може да
      // скочи направо в друг раздел, без да минава обратно през календара.
      drawer: const AppDrawer(),
      appBar: AppBar(
        backgroundColor: AppColors.toolbar,
        title: const Text('За приложението'),
      ),
      body: SafeArea(
        child: Container(
          color: AppColors.background,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Image.asset(
                    'assets/icon_trans.png',
                    width: logoSize,
                    height: logoSize,
                  ),
                ),
                const SizedBox(height: 28),
                const Text(
                  'Православен календар',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: _titleFamily,
                    fontSize: _fontSize + 14,
                    height: 1.25,
                    color: _ink,
                  ),
                ),
                const SizedBox(height: 32),
                _AboutDropCapParagraph(
                  dropCap: 'П',
                  firstParagraph: _firstParagraph,
                  fontSize: _fontSize,
                  lineHeight: _lineHeight,
                  capColor: _wine,
                  inkColor: _ink,
                ),
                const SizedBox(height: 24),
                Text.rich(
                  TextSpan(
                    style: bodyStyle,
                    children: [_firstLineIndent, TextSpan(text: _authorParagraph)],
                  ),
                  textAlign: TextAlign.justify,
                ),
                const SizedBox(height: 24),
                RichText(
                  textAlign: TextAlign.justify,
                  text: TextSpan(
                    style: smallItalicStyle,
                    children: [
                      _firstLineIndent,
                      const TextSpan(
                          text: 'Моля за прошка, ако се натъкнете тук на неточност '
                              'или неудобство. С благодарност бих приел '
                              'забележки и препоръки за подобряване '
                              'на приложението на адрес: \n'),
                      _linkSpan(_feedbackEmail, _emailTap),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                RichText(
                  textAlign: TextAlign.justify,
                  text: TextSpan(
                    style: smallItalicStyle,
                    children: [
                      _firstLineIndent,
                      const TextSpan(
                          text: 'Можете свободно да разгледате изходния код '
                          'на приложението на адрес: \n'),
                      _linkSpan('github.com/isihiaBG/orthodox_calendar', _githubTap),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                Text.rich(
                  TextSpan(
                    style: smallItalicStyle,
                    children: [_firstLineIndent, TextSpan(text: _closingParagraph)],
                  ),
                  textAlign: TextAlign.justify,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Опростена буквица-с-обтичане — само за първия абзац на "За приложението".
/// Без логика за търсене/маркиране (за разлика от reader_screen._DropCapParagraph),
/// защото тук не ни трябва.
class _AboutDropCapParagraph extends StatelessWidget {
  final String dropCap;
  final String firstParagraph; // чист текст, БЕЗ водещата буква
  final double fontSize;
  final double lineHeight; // коефициент (напр. 1.25)
  final Color capColor;
  final Color inkColor;

  const _AboutDropCapParagraph({
    required this.dropCap,
    required this.firstParagraph,
    required this.fontSize,
    required this.lineHeight,
    required this.capColor,
    required this.inkColor,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final lineHeightPx = fontSize * lineHeight;
      final dropCapSize = lineHeightPx * 5.5 * 0.82;
      final capWidth = dropCapSize * 0.40;
      const gap = 4.0;
      final narrowWidth = constraints.maxWidth - capWidth - gap;
      const capLines = 5;

      final tp = TextPainter(
        text: TextSpan(
          text: firstParagraph,
          style: TextStyle(fontFamily: _bodyFamily, fontSize: fontSize, height: lineHeight),
        ),
        textDirection: TextDirection.ltr,
        maxLines: capLines,
      )..layout(maxWidth: narrowWidth);
      int cut = tp.didExceedMaxLines
          ? tp.getPositionForOffset(Offset(narrowWidth, capLines * lineHeightPx - 1)).offset
          : firstParagraph.length;
      if (cut < firstParagraph.length) {
        final sp = firstParagraph.lastIndexOf(' ', cut);
        if (sp > 0) cut = sp;
      }

      final wrapText = firstParagraph.substring(0, cut).trim();
      final restText = firstParagraph.substring(cut).trim();
      final baseStyle = TextStyle(
        fontFamily: _bodyFamily,
        fontSize: fontSize,
        height: lineHeight,
        color: inkColor,
      );

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
                child: Text(wrapText, textAlign: TextAlign.justify, style: baseStyle),
              ),
            ],
          ),
          if (restText.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(restText, textAlign: TextAlign.justify, style: baseStyle),
            ),
        ],
      );
    });
  }
}
