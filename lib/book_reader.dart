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
import 'package:flutter_html/flutter_html.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_theme.dart';
import 'drop_cap.dart';
import 'epub_source.dart';
import 'reader_font_size.dart';
import 'reader_styles.dart';
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
    // Вътрешните препратки (бележки под линия, връзки между жития) сочат
    // файл в самия .epub. Външните — навън.
    if (url.startsWith('http')) {
      final uri = Uri.tryParse(url);
      if (uri != null) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
      return;
    }
    // TODO(бележките): вътрешните препратки още не се отварят — предстои.
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
      appBar: AppBar(
        backgroundColor: AppColors.toolbar,
        title: Text(
          _current.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 15),
        ),
        // Същата лента като при четеца на жития — за потребителя това е
        // един и същи четец. Разликата е само „Съдържание": то има смисъл
        // при книга, не при отделно житие.
        actions: readerToolbarActions(
          context: context,
          onShowContents: _showToc,
          onThemeToggle: () => setState(() => ReaderTheme.dark = !ReaderTheme.dark),
          onFontSmaller: () =>
              setState(() => ReaderFontSize.nudge(-ReaderFontSize.step)),
          onFontBigger: () =>
              setState(() => ReaderFontSize.nudge(ReaderFontSize.step)),
          // Търсенето и отметките в книга предстоят; менюто вече стои,
          // защото и тук ще получи аналогични инструменти.
          onMore: _showMoreMenu,
        ),
      ),
      body: raw == null
          ? Center(
              child: Text('Няма ${_current.href}',
                  style: TextStyle(color: palette.dim)))
          : _chapterBody(raw, palette),
      bottomNavigationBar: _navBar(palette),
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

    return SingleChildScrollView(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (beforeHtml.trim().isNotEmpty)
            Html(data: beforeHtml, style: styles, onLinkTap: (u, _, __) => _onLinkTap(u)),
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
              linkColor: AppColors.sectionTitle,
              onLinkTap: _onLinkTap,
            ),
          if (afterHtml.trim().isNotEmpty)
            Html(data: afterHtml, style: styles, onLinkTap: (u, _, __) => _onLinkTap(u)),
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
    body = body.replaceAllMapped(
      RegExp(r'<h1\b[^>]*>(.*?)</h1>', dotAll: true),
      (m) => '<h3>${m.group(1)}</h3>',
    );
    // Празните котви на calibre (<a id="TOC_…"></a>) само шумят.
    body = body.replaceAll(
        RegExp(r'<a\s+(?![^>]*href)[^>]*>\s*</a>', dotAll: true), '');
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
