// book_reader.dart
//
// Четецът на книги от „Читанка". Чете глава по глава направо от .epub-а
// (виж epub_source.dart) — книгите НЕ се превръщат в бази.
//
// Отделен екран от reader_screen.dart, защото навигацията е наистина
// различна: там едно четиво, тук книга със съдържание, предишна и следваща
// глава. Всичко останало обаче е ОБЩО и се внася:
//
//   drop_cap.dart          буквицата и разделянето за нея
//   reader_styles.dart     стиловете за flutter_html
//   reader_theme.dart      палитрата и нощният режим
//   reader_font_size.dart  размерът на шрифта
//
// Тоест смяна на цвят или на стил се отразява и тук, и в четеца на жития —
// а нощният режим и размерът на шрифта се пренасят между двата, защото са
// сесийни: човек си нагласява четенето веднъж.
//
// БУКВИЦАТА се явява в началото на ВСЯКА глава — тя е знакът на
// приложението, а всяка глава тук е отделно житие.

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_html/flutter_html.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_theme.dart';
import 'drop_cap.dart';
import 'epub_source.dart';
import 'reader_font_size.dart';
import 'reader_styles.dart';
import 'reader_sup_extension.dart';
import 'reader_theme.dart';
import 'reader_toolbar.dart';

class BookReader extends StatefulWidget {
  final EpubBook book;

  /// Откъде да започне. Ако е null — от началото на книгата.
  final EpubTocEntry? start;

  const BookReader({super.key, required this.book, this.start});

  @override
  State<BookReader> createState() => _BookReaderState();
}

class _BookReaderState extends State<BookReader> {
  /// Долната лента със стрелките и брояча „4 / 129".
  ///
  /// Изключена засега по решение на потребителя (12.08.2026): тя яде ред от
  /// текста, а прелистването между глави и без това е достъпно през
  /// съдържанието. Кодът ѝ (_navBar) НЕ е махнат — ще потрябва, когато
  /// решим как да изглежда преходът между главите.
  static const bool _showNavBar = false;

  /// Главите — само тези, които са в СЪДЪРЖАНИЕТО, не целият spine.
  ///
  /// Spine-ът носи и стотиците файлове с бележки под линия (в септемврийския
  /// том 892 файла срещу 148 записа в съдържанието). Прелистването „нататък"
  /// трябва да върви по главите, не да пропада в бележките.
  late final List<EpubTocEntry> _chapters;

  int _index = 0;
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _chapters = widget.book.toc
        .expand((e) => e.flattened())
        .where((e) => e.href.isNotEmpty)
        .toList();
    final start = widget.start;
    if (start != null) {
      final at = _chapters.indexWhere(
          (e) => e.href == start.href && e.anchor == start.anchor);
      if (at >= 0) _index = at;
    }
    ReaderFontSize.loadOnce().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    ReaderFontSize.flush();
    _scroll.dispose();
    super.dispose();
  }

  EpubTocEntry get _current => _chapters[_index];

  void _goTo(int i) {
    if (i < 0 || i >= _chapters.length) return;
    setState(() => _index = i);
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  Future<void> _onLinkTap(String? url) async {
    if (url == null) return;

    // Външните препратки (библейските към azbyka.ru) водят навън.
    if (url.startsWith('http')) {
      final uri = Uri.tryParse(url);
      if (uri != null) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
      return;
    }

    // Вътрешните сочат файл в самия .epub — най-често бележка под линия
    // („../Text/note1690.xhtml#note1690"). Пътят е ОТНОСИТЕЛЕН спрямо
    // текущата глава, затова се разрешава спрямо нейната папка.
    final path = url.split('#').first;
    if (path.isEmpty) return;
    final full = p.normalize(p.join(p.dirname(_current.href), path));
    final raw = widget.book.readFile(full);
    if (raw == null) {
      debugPrint('epub: няма $full');
      return;
    }
    if (!mounted) return;

    // Бележката се показва в изскачащ панел, а не на цял екран: те са
    // стотици в том и четенето не бива да се прекъсва с нова страница за
    // всяка. Заглавието на файла е самият номер — излишно е, текстът
    // говори сам.
    final body = _normalize(raw)
        .replaceAll(RegExp(r'<h3\b[^>]*>.*?</h3>', dotAll: true), '')
        .trim();
    final palette = ReaderTheme.palette;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: palette.bg,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _NoteSheet(html: body, palette: palette),
    );
  }

  Future<void> _showMoreMenu() async {
    // TODO: същинско меню (отметки, преход към календара, споделяне).
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Менюто предстои.')),
    );
  }

  // ── Съдържанието ────────────────────────────────────────────────────────

  Future<void> _showToc() async {
    final palette = ReaderTheme.palette;
    final chosen = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: palette.bg,
      builder: (_) => _TocSheet(
        toc: widget.book.toc,
        chapters: _chapters,
        current: _index,
        palette: palette,
      ),
    );
    if (chosen != null) _goTo(chosen);
  }

  @override
  Widget build(BuildContext context) {
    final palette = ReaderTheme.palette;
    final raw = widget.book.readFile(_current.href);

    return Scaffold(
      backgroundColor: palette.bg,
      body: SafeArea(
        bottom: false,
        // Лентата се ПРИБИРА при плъзгане надолу и се връща при плъзгане
        // нагоре — същото поведение като в четеца на жития (SliverAppBar с
        // floating+snap, без pinned). При четене на дълъг текст всеки
        // изгубен ред се усеща.
        child: ScrollbarTheme(
          data: readerScrollbarTheme(palette),
          child: Scrollbar(
            controller: _scroll,
            // Разрешава ВЛАЧЕНЕ на палеца с пръст; без него скролбарът е
            // само показалец. Флагът разширява и зоната за докосване отвъд
            // видимата ширина на палеца.
            interactive: true,
            child: CustomScrollView(
              controller: _scroll,
              slivers: [
                SliverAppBar(
                  primary: false,
                  floating: true,
                  snap: true,
                  pinned: false,
                  backgroundColor: AppColors.toolbar,
                  toolbarHeight: 44,
                  title: Text(
                    _current.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 15),
                  ),
                  // Същата лента като при четеца на жития — за потребителя
                  // това е един и същи четец. Разликата е само
                  // „Съдържание": то има смисъл при книга, не при житие.
                  actions: readerToolbarActions(
                    context: context,
                    onShowContents: _showToc,
                    onThemeToggle: () =>
                        setState(() => ReaderTheme.dark = !ReaderTheme.dark),
                    onFontSmaller: () => setState(
                        () => ReaderFontSize.nudge(-ReaderFontSize.step)),
                    onFontBigger: () => setState(
                        () => ReaderFontSize.nudge(ReaderFontSize.step)),
                    // Търсенето и отметките предстоят; менюто вече стои,
                    // защото и тук ще получи аналогични инструменти.
                    onMore: _showMoreMenu,
                  ),
                ),
                SliverToBoxAdapter(
                  child: raw == null
                      ? Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text('Няма ${_current.href}',
                              style: TextStyle(color: palette.dim)))
                      : _chapterBody(raw, palette),
                ),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: _showNavBar ? _navBar(palette) : null,
    );
  }

  Widget _chapterBody(String raw, ReaderPalette palette) {
    final body = _normalize(raw);
    final (beforeHtml, dropCap, firstP, afterHtml) = splitDropCap(body);
    final styles = readerStyles(
      fontSize: ReaderFontSize.value,
      palette: palette,
    );

    final fontSize = ReaderFontSize.value;
    final lineHeightPx = fontSize * kReaderLineHeight;

    // Без долната лента текстът стига до края на екрана; отдолу се оставя
    // само толкова, колкото заема системната лента за жестове.
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 24 + bottomInset),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (beforeHtml.trim().isNotEmpty)
            Html(
                data: beforeHtml,
                style: styles,
                extensions: const [ReaderSupExtension()],
                onLinkTap: (u, _, __) => _onLinkTap(u)),
          if (dropCap.isNotEmpty)
            DropCapParagraph(
              dropCap: dropCap,
              // Същата сметка като в четеца на жития: 5,5 реда височина, с
              // корекция за ascender-а на Bukvica.
              dropCapSize: lineHeightPx * 5.5 * 0.82,
              lineHeight: lineHeightPx,
              lineFactor: kReaderLineHeight,
              firstParagraph: firstP,
              secondParagraph: '',
              fontSize: fontSize,
              capColor: palette.wine,
              inkColor: palette.ink,
              linkColor: palette.link,
              onLinkTap: _onLinkTap,
            ),
          if (afterHtml.trim().isNotEmpty)
            Html(
                data: afterHtml,
                style: styles,
                extensions: const [ReaderSupExtension()],
                onLinkTap: (u, _, __) => _onLinkTap(u)),
        ],
      ),
    );
  }

  /// Привежда разметката на книгата към тази на останалите четива.
  ///
  /// Томовете идват от calibre и пишат абзаците като `<div
  /// class="paragraph">`, а заглавията като `<h1 class="calibre9">` —
  /// проверено: 4372 `<div>` срещу нито един `<p>`. Стиловете ни (и
  /// splitDropCap, който търси абзаци) очакват `<p>` и `<h3>`, тъй че без
  /// това преобразуване книгата излиза със системния шрифт и без буквица.
  ///
  /// Преобразува се ТУК, при показването, а не в самите .epub-и: те са
  /// самостоятелни книги и трябва да се четат и извън приложението.
  ///
  /// Стиловете и шрифтовете на книгата се ИГНОРИРАТ — взима се само
  /// `<body>`. Иначе томът ще изглежда като чуждо тяло вътре в
  /// приложението: той си носи собствен CSS и вградени шрифтове.
  static String _normalize(String raw) {
    var body = RegExp(r'<body[^>]*>(.*)</body>', dotAll: true)
            .firstMatch(raw)
            ?.group(1) ??
        raw;

    // Редът с паметта („Памет на 1 септември") — ПЪРВО, преди общото
    // правило за абзаците. Белегът му е устойчив: цялото съдържание на
    // абзаца е един <span>, без нищо друго. Проверено — 236 от 236 глави.
    //
    // Получава собствен клас по две причини: изписва се в курсив (той е
    // указание, не част от разказа) и — понеже splitDropCap търси ГОЛ
    // `<p>` — буквицата сама прескача до следващия абзац, където ѝ е
    // мястото.
    body = body.replaceAllMapped(
      RegExp(r'<div\s+class="paragraph"[^>]*>\s*<span>(.*?)</span>\s*</div>',
          dotAll: true),
      (m) => '<p class="memorydate">${m.group(1)}</p>',
    );
    // Останалите абзаци. Вложени <div> в „paragraph" няма — проверено.
    body = body.replaceAllMapped(
      RegExp(r'<div\s+class="paragraph"[^>]*>(.*?)</div>', dotAll: true),
      (m) => '<p>${m.group(1)}</p>',
    );
    // Заглавието на главата. h3 е стилът за заглавие в reader_styles.dart.
    //
    // Завършващият <br/> вътре в заглавието се маха: calibre го оставя в
    // края на всеки <h1> и той добавя цял празен ред между заглавието и
    // реда с паметта под него.
    body = body.replaceAllMapped(
      RegExp(r'<h1\b[^>]*>(.*?)</h1>', dotAll: true),
      (m) => '<h3>${m.group(1)!.replaceAll(RegExp(r'(<br\b[^>]*/?>\s*)+$'), '').trim()}</h3>',
    );
    // Празните котви на calibre (<a id="TOC_…"></a>) само шумят.
    body = body.replaceAll(
        RegExp(r'<a\s+(?![^>]*href)[^>]*>\s*</a>', dotAll: true), '');

    // Препратките към бележки идват като <a …><sup>1690</sup></a>. Обръщаме
    // вложеността на <sup><a …>1690</a></sup>, защото flutter_html рисува
    // връзката като ЕДИН отрязък и не прилага повдигане на вложеното в нея —
    // номерът излизаше наравно с текста и се четеше като част от думата
    // („Траян1679"). Отвън ли е <sup>, правилото за него се хваща.
    body = body.replaceAllMapped(
      RegExp(r'<a\b([^>]*)>\s*<sup\b[^>]*>(.*?)</sup>\s*</a>', dotAll: true),
      (m) => '<sup><a${m.group(1)}>${m.group(2)}</a></sup>',
    );
    return body;
  }

  Widget _navBar(ReaderPalette palette) {
    return Container(
      color: AppColors.toolbar,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left),
              color: AppColors.textPrimary,
              onPressed: _index > 0 ? () => _goTo(_index - 1) : null,
            ),
            Expanded(
              child: Text(
                '${_index + 1} / ${_chapters.length}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 12),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              color: AppColors.textPrimary,
              onPressed: _index < _chapters.length - 1
                  ? () => _goTo(_index + 1)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

/// Съдържанието като плъзгащ се панел. Пази вложеността: дните са заглавия,
/// житията под тях са с отстъп.
class _TocSheet extends StatelessWidget {
  final List<EpubTocEntry> toc;
  final List<EpubTocEntry> chapters;
  final int current;
  final ReaderPalette palette;

  const _TocSheet({
    required this.toc,
    required this.chapters,
    required this.current,
    required this.palette,
  });

  @override
  Widget build(BuildContext context) {
    final rows = <(EpubTocEntry, int)>[];
    void walk(List<EpubTocEntry> list, int depth) {
      for (final e in list) {
        rows.add((e, depth));
        walk(e.children, depth + 1);
      }
    }

    walk(toc, 0);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          margin: const EdgeInsets.symmetric(vertical: 10),
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: palette.dim,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        Flexible(
          child: ListView.builder(
            itemCount: rows.length,
            itemBuilder: (context, i) {
              final (entry, depth) = rows[i];
              final at = chapters.indexWhere((c) =>
                  c.href == entry.href && c.anchor == entry.anchor);
              final isCurrent = at == current;
              return InkWell(
                onTap: at < 0 ? null : () => Navigator.of(context).pop(at),
                child: Container(
                  color: isCurrent
                      ? palette.hit.withValues(alpha: 0.25)
                      : null,
                  padding:
                      EdgeInsets.fromLTRB(16.0 + depth * 18, 11, 16, 11),
                  child: Text(
                    entry.title,
                    style: TextStyle(
                      color: depth == 0 ? AppColors.sectionTitle : palette.ink,
                      fontSize: depth == 0 ? 15 : 14,
                      fontWeight:
                          depth == 0 ? FontWeight.w600 : FontWeight.normal,
                      fontFamily: kBodyFamily,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Бележка под линия — изскачащ панел, не цял екран.
///
/// В един том има стотици бележки; ако всяка отваряше страница, четенето
/// щеше да се накъсва. Панелът се плъзга обратно с един жест и оставя
/// читателя точно там, където е бил.
class _NoteSheet extends StatelessWidget {
  final String html;
  final ReaderPalette palette;

  const _NoteSheet({required this.html, required this.palette});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          margin: const EdgeInsets.symmetric(vertical: 10),
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: palette.dim,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
            child: Html(
              data: html,
              extensions: const [ReaderSupExtension()],
              // Бележката е пояснение, не част от разказа: една степен
              // по-дребна и в курсив, за да се различава от текста, от
              // който току-що е дошъл читателят.
              style: () {
                final size = ReaderFontSize.value - ReaderFontSize.step;
                final s = readerStyles(fontSize: size, palette: palette);
                s['p'] = s['p']!.copyWith(fontStyle: FontStyle.italic);
                return s;
              }(),
            ),
          ),
        ),
      ],
    );
  }
}
