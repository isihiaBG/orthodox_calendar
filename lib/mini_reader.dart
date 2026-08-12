// mini_reader.dart
//
// Мини четец за разгъващите се секции на дневния изглед.
//
// Рисува готово HTML тяло НА МЯСТО, вътре в секцията — без да отваря нов
// екран, без лента и без заглавие. Това е разликата спрямо ReaderScreen:
// там всяко четиво е цял екран с навигация, търсене и буквица; тук текстът
// е кратък и стои под заглавието на секцията, докъдето е разгъната.
//
// Направен е ОБЩ нарочно: първият му ползвател е „Мисли от Теофан
// Затворник", вторият ще бъде „От оптинските старци". Затова не знае нищо
// за съдържанието — получава зареждач и съобщение за празен ден.
//
// Заявката тръгва при ПЪРВОТО показване, не при построяването на дневния
// изглед: ExpandableSection монтира съдържанието си чак при разгъване, тъй
// че initState тук се изпълнява точно тогава. Веднъж заредено, остава в
// паметта на състоянието и повторното разгъване не удря базата.

import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_theme.dart';
import 'reader_screen.dart';
import 'reference_text.dart';
import 'saint_expandable_tile.dart' show lookupBySlug;

/// Схемата, с която 03_build_db.py бележи препратките към бележки под линия
/// в мислите на свт. Теофан. Държи се тук, до мястото, което я разпознава.
const String kTeofanNoteScheme = 'teofan-note://';

class MiniReader extends StatefulWidget {
  /// Връща готовото HTML тяло или null, ако за деня няма запис.
  final Future<String?> Function() load;

  /// Какво да пише, когато зареждачът върне null. За книга, писана за една
  /// църковна година, това е нормален отговор, не грешка — виж коментара
  /// при DatabaseHelper.teofanThought.
  final String emptyMessage;

  /// Мини четецът НЕ наследява размера на ReaderScreen — той е за цял екран
  /// и потребителят си го върти отделно. Тръгва от размера на останалите
  /// текстове в дневния изглед (15), за да не изглежда като чуждо тяло между
  /// секциите, и е с една степен по-голям (стъпката на четеца е 1.5), защото
  /// тук се чете свързан текст, а не отделни редове.
  final double fontSize;
  final double lineHeight;

  const MiniReader({
    super.key,
    required this.load,
    required this.emptyMessage,
    this.fontSize = 16.5,
    this.lineHeight = 1.6,
  });

  @override
  State<MiniReader> createState() => _MiniReaderState();
}

class _MiniReaderState extends State<MiniReader> {
  late final Future<String?> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.load();
  }

  Future<void> _onLinkTap(String? url) async {
    if (url == null) return;

    // Бележките под линия НЕ водят навън — отварят се в четеца, както
    // четивата на „Справочник". Библейските препратки нарочно си остават
    // външни (azbyka.ru), докато си направим своя секция „Библия".
    if (url.startsWith(kTeofanNoteScheme)) {
      final key = Uri.decodeComponent(url.substring(kTeofanNoteScheme.length));
      final texts = await loadTeofanNote('$kTeofanNoteSlugPrefix$key');
      if (!mounted) return;
      if (texts == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Бележката не беше намерена.')),
        );
        return;
      }
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ReaderScreen.sluzhba(
          texts: texts,
          lookup: lookupBySlug,
          lifeTitle: texts.name,
          // Режимът рисува без буквица, но четивото не е служба.
          typeLabel: 'Бележка',
        ),
      ));
      return;
    }

    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        // Грешката трябва да се ВИЖДА. Ако тя падне в същия клон като
        // „няма запис за деня", всеки счупен път — липсваща база, грешна
        // заявка, изключение — изглежда като нормален празен ден и се
        // издирва часове.
        if (snapshot.hasError) {
          debugPrint('MiniReader: ${snapshot.error}\n${snapshot.stackTrace}');
          return Text(
            'Грешка при зареждане: ${snapshot.error}',
            style: const TextStyle(
                color: AppColors.textSecondary, fontSize: 13, height: 1.5),
          );
        }
        final body = snapshot.data;
        if (body == null || body.isEmpty) {
          return Text(
            widget.emptyMessage,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 15,
              height: 1.6,
              fontStyle: FontStyle.italic,
            ),
          );
        }
        return Html(
          data: body,
          style: _styles(),
          onLinkTap: (url, attributes, element) => _onLinkTap(url),
        );
      },
    );
  }

  Map<String, Style> _styles() => {
        // flutter_html обвива съдържанието в имплицитни <html> и <body> с
        // браузърни отстъпи — нулираме ги, за да ляга текстът точно на
        // ширината на секцията.
        'html': Style(margin: Margins.zero, padding: HtmlPaddings.zero),
        'body': Style(margin: Margins.zero, padding: HtmlPaddings.zero),
        'p': Style(
          fontSize: FontSize(widget.fontSize),
          lineHeight: LineHeight(widget.lineHeight),
          margin: Margins.only(top: 0, bottom: 10),
          textAlign: TextAlign.justify,
          // textPrimary, не textSecondary: свързаният текст се чете дълго и
          // иска малко повече контраст от кратките редове около него.
          color: AppColors.textPrimary,
        ),
        // Цитатите. Нарочно СДЪРЖАНО: в 353-те поучения има 496 такива
        // места и ярко открояване би направило страницата пъстра. Кавичките
        // «…» и без това вече казват на читателя, че това е цитат — курсивът
        // само помага на окото да го отдели.
        '.cite': Style(fontStyle: FontStyle.italic),
        // Същият цвят като връзките в четеца — да не въвеждаме втори вид
        // връзка в приложението.
        'a': Style(
          color: AppColors.sectionTitle,
          textDecoration: TextDecoration.none,
        ),
        // Препратките към бележки под линия — отварят се в четеца
        // (виж _onLinkTap). Цветът им идва от правилото за <a> отгоре.
        'sup': Style(fontSize: FontSize(widget.fontSize * 0.7)),
      };
}
