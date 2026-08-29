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
const String _bodyFamily = 'CharisSIL';
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

// ─── Използваните източници ──────────────────────────────────────────────
//
// ⚠ ДЪЛЖИМО ЦИТИРАНЕ, не украса. Почти цялото съдържание на приложението е
// чужд труд: Писанието, житията, песнопенията и двете разгъващи се секции в
// дневния изглед идват от azbyka.ru, а четивата в „Справочник" — от руското
// приложение на Oleksandr Kotyuk, откъдето е взаимствано и устройството на
// дневния изглед с разгъващите се секции.
//
// ⚠ Името на ХРАНИЛИЩЕТО в GitHub се разминава с името на автора
// (`AlexandrKozlovskiy/OrthodoxCalendar`, пакетът е
// `oleksandr.kotyuk.orthodoxcalendarfree`) — същият проект е. Не го
// „поправяй" на нещо, което изглежда по-логично: адресът е верен така.
const String _pravoslavietoUrl = 'https://www.pravoslavieto.com/bible/';
const String _azbykaUrl = 'https://azbyka.ru';
const String _kotyukUrl =
    'https://github.com/AlexandrKozlovskiy/OrthodoxCalendar';

const String _sourcesTitle = 'Използвани източници';

const String _sourcesIntro =
    'Съдържанието на приложението е плод преди всичко на чужд труд, за '
    'който дължим и признание, и благодарност.';

const String _sourcesPravoslavieto =
    ' — оттам e взето Свещеното Писание на български език';

const String _sourcesAzbyka =
    ' — оттам са Свещеното Писание на църковнославянски и чужди езици, '
    'житията на светиите по свт. Димитрий Ростовски, '
    'тропарите, кондаците, молитвите и величанията, мислите на '
    'свт. Теофан Затворник и сентенциите на Оптинските старци. Под всяко '
    'библейско четиво стои и пряка връзка към същата глава в сайта.';

const String _sourcesKotyuk =
    ' — руското приложение „Православный календарь" от Олександр Котюк с '
    'отворен код. Оттам са взаимствани четивата в раздел „Справочник", а също и '
    'устройството на дневния изглед с разгъващите се секции.';

const String _sourcesTranslation =
    'Руските текстове са преведени машинно и след това редактирани. '
    'Шрифтовете за основния текст и за църковнославянската графика — '
    'Charis SIL, Triodion и Monomakh — са със свободен лиценз (SIL OFL).';

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
  late final TapGestureRecognizer _pravoslavietoTap;
  late final TapGestureRecognizer _azbykaTap;
  late final TapGestureRecognizer _kotyukTap;

  @override
  void initState() {
    super.initState();
    _emailTap = TapGestureRecognizer()..onTap = _openEmail;
    _githubTap = TapGestureRecognizer()..onTap = _openGithub;
    _pravoslavietoTap = TapGestureRecognizer()..onTap = () => _openUrl(_pravoslavietoUrl);
    _azbykaTap = TapGestureRecognizer()..onTap = () => _openUrl(_azbykaUrl);
    _kotyukTap = TapGestureRecognizer()..onTap = () => _openUrl(_kotyukUrl);
  }

  @override
  void dispose() {
    _emailTap.dispose();
    _githubTap.dispose();
    _pravoslavietoTap.dispose();
    _azbykaTap.dispose();
    _kotyukTap.dispose();
    super.dispose();
  }

  Future<void> _openEmail() async {
    final uri = Uri(scheme: 'mailto', path: _feedbackEmail);
    await launchUrl(uri);
  }

  Future<void> _openGithub() async => _openUrl(_githubUrl);

  Future<void> _openUrl(String url) async {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
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

  /// Дялът „Използвани източници" — най-отдолу на екрана.
  ///
  /// ⚠ Заглавието е ЕДИНСТВЕНОТО тук с шрифта на заглавията; самите редове
  /// вървят с курсива на страничните бележки, същия като на реда с адреса
  /// на хранилището малко по-горе. Дялът трябва да се чете като продължение
  /// на разговора, а не като втори екран, залепен за първия.
  ///
  /// ⚠ Имената на източниците са ВРЪЗКИ (те са и самото цитиране), а
  /// обяснението подире им — обикновен текст. Затова всеки ред е един
  /// [RichText] с два спана, а не отделен ред с адрес отдолу: така окото
  /// вижда веднага кой източник за какво е.
  Widget _sources(TextStyle style) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const SizedBox(height: 40),
      const Text(
        _sourcesTitle,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontFamily: _titleFamily,
          // ⚠ ПО-ЕДРО от тялото, инак не е заглавие.
          //
          // Дотук стоеше голото `_fontSize` — тоест буква по буква същият
          // кегел като текста под него. Единственото, което го отделяше, беше
          // шрифтът, а той е декоративен и в двете роли; окото го четеше като
          // ред от текста, не като начало на дял.
          //
          // Стълбицата на екрана е 22 (тяло) → 36 (името на приложението);
          // 28 пада по средата ѝ, тъй че дялът личи, без да спори с главното
          // заглавие.
          fontSize: _fontSize + 6,
          height: 1.25,
          color: _ink,
        ),
      ),
      const SizedBox(height: 20),
      Text.rich(
        TextSpan(
          style: style,
          children: const [
            _firstLineIndent,
            TextSpan(text: _sourcesIntro),
          ],
        ),
        textAlign: TextAlign.justify,
      ),
      const SizedBox(height: 20),
      RichText(
        textAlign: TextAlign.justify,
        text: TextSpan(
          style: style,
          children: [
            _firstLineIndent,
            _linkSpan('pravoslavieto.com/bible', _pravoslavietoTap),
            const TextSpan(text: _sourcesPravoslavieto),
          ],
        ),
      ),
      const SizedBox(height: 20),
      RichText(
        textAlign: TextAlign.justify,
        text: TextSpan(
          style: style,
          children: [
            _firstLineIndent,
            _linkSpan('azbyka.ru', _azbykaTap),
            const TextSpan(text: _sourcesAzbyka),
          ],
        ),
      ),
      const SizedBox(height: 20),
      RichText(
        textAlign: TextAlign.justify,
        text: TextSpan(
          style: style,
          children: [
            _firstLineIndent,
            _linkSpan(
              'github.com/AlexandrKozlovskiy/OrthodoxCalendar',
              _kotyukTap,
            ),
            const TextSpan(text: _sourcesKotyuk),
          ],
        ),
      ),
      const SizedBox(height: 20),
      Text.rich(
        TextSpan(
          style: style,
          children: const [
            _firstLineIndent,
            TextSpan(text: _sourcesTranslation),
          ],
        ),
        textAlign: TextAlign.justify,
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final logoSize = (MediaQuery.of(context).size.width * 0.55).clamp(
      160.0,
      260.0,
    );
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
                    children: [
                      _firstLineIndent,
                      TextSpan(text: _authorParagraph),
                    ],
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
                        text:
                            'Молим за прошка, ако се натъкнете тук на неточност '
                            'или неудобство. С благодарност бихме приели '
                            'забележки и препоръки за подобряване '
                            'на приложението: \n',
                      ),
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
                        text:
                            'Можете свободно да разгледате изходния код '
                            'на приложението на следния адрес: \n',
                      ),
                      _linkSpan(
                        'github.com/isihiaBG/orthodox_calendar',
                        _githubTap,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                Text.rich(
                  TextSpan(
                    style: smallItalicStyle,
                    children: [
                      _firstLineIndent,
                      TextSpan(text: _closingParagraph),
                    ],
                  ),
                  textAlign: TextAlign.justify,
                ),
                _sources(smallItalicStyle),
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final lineHeightPx = fontSize * lineHeight;
        final dropCapSize = lineHeightPx * 5.5 * 0.82;
        final capWidth = dropCapSize * 0.40;
        const gap = 4.0;
        final narrowWidth = constraints.maxWidth - capWidth - gap;
        const capLines = 5;

        final tp = TextPainter(
          text: TextSpan(
            text: firstParagraph,
            style: TextStyle(
              fontFamily: _bodyFamily,
              fontSize: fontSize,
              height: lineHeight,
            ),
          ),
          textDirection: TextDirection.ltr,
          maxLines: capLines,
        )..layout(maxWidth: narrowWidth);
        int cut = tp.didExceedMaxLines
            ? tp
                  .getPositionForOffset(
                    Offset(narrowWidth, capLines * lineHeightPx - 1),
                  )
                  .offset
            : firstParagraph.length;
        if (cut < firstParagraph.length) {
          final sp = firstParagraph.lastIndexOf(' ', cut);
          if (sp > 0) cut = sp;
        }

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
                  // ⚠ ЦЕЛИЯТ firstParagraph, отрязан визуално с maxLines — не
                  // предварително отрязан низ (както преди). Подаде ли се
                  // готово отрязан текст, Flutter го третира като ЦЕЛИЯ абзац
                  // и никога не разпъва последния му ред (типографско
                  // правило: последният ред на абзац не се justify-ва). С
                  // maxLines пакетът знае, че текстът продължава отвъд, и
                  // разпъва последния ВИДИМ ред нормално — същият похват като
                  // в четеца, viж drop_cap.dart около "maxLines реже точно
                  // там".
                  child: Text(
                    firstParagraph,
                    maxLines: capLines,
                    textAlign: TextAlign.justify,
                    style: baseStyle,
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
                  style: baseStyle,
                ),
              ),
          ],
        );
      },
    );
  }
}
