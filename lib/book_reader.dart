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
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_html/flutter_html.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_theme.dart';
import 'drop_cap.dart';
import 'epub_source.dart';
import 'reader_font_size.dart';
import 'reader_match_ticks.dart';
import 'reader_search.dart';
import 'reader_styles.dart';
import 'reader_sup_extension.dart';
import 'reader_text_utils.dart';
import 'reader_theme.dart';
import 'round_icon_button.dart';
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

  // ── Търсене в главата ───────────────────────────────────────────────
  //
  // Търси се в ТЕКУЩАТА глава, не в целия том — точният аналог на четеца
  // на жития. Търсенето из цялата книга е друг род задача (резултатът е
  // списък с глави, а не движение в текста) и ще дойде отделно.
  bool _searchOpen = false;
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  /// Изгладеният низ за сравнение — без ударения и регистър (виж fold()).
  String _query = '';

  /// Делът от височината на текста, на който стои всяко съвпадение (0..1).
  /// По тях се рисуват чертичките по скролбара.
  List<double> _hitRatios = const [];

  int _total = 0;
  int _currentHit = -1;

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

    // ПЪЛЕН ЕКРАН ЗА ЦЯЛОТО ЧЕТЕНЕ — включва се веднъж тук и се изключва
    // веднъж при излизане. Между тях режимът НЕ се пипа.
    //
    // Това е същината. По-рано системната лента се скриваше и връщаше
    // според посоката на плъзгане, а всяка смяна на режима преоразмерява
    // прозореца веднъж — тоест текстът подскачаше по няколко пъти в
    // минута. Като състояние скритото беше спокойно; неспокойни бяха
    // ПРЕХОДИТЕ. Затова сега преходи има само два.
    //
    // immersiveSticky, а не immersive: при жест отгоре лентата наднича и
    // сама се скрива пак, без да ни връща в друг режим. Потребителят губи
    // само часовника, а печели цялата височина — особено в хоризонтално
    // положение, където тя отнема чувствителна част от екрана.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    ReaderFontSize.flush();
    _scroll.dispose();
    // ЗАДЪЛЖИТЕЛНО: режимът важи за цялото приложение, не за екрана. Без
    // това календарът остава без системна лента, след като човек затвори
    // книгата.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual,
        overlays: SystemUiOverlay.values);
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

  // ── Търсене ─────────────────────────────────────────────────────────

  void _toggleSearch() {
    setState(() {
      _searchOpen = !_searchOpen;
      if (!_searchOpen) {
        _searchCtrl.clear();
        _query = '';
        _hitRatios = const [];
        _total = 0;
        _currentHit = -1;
      }
    });
    if (_searchOpen) _searchFocus.requestFocus();
  }

  /// Преброява съвпаденията и смята дела им от височината на текста.
  ///
  /// Мярката е по ПОЗИЦИЯТА В ЧИСТИЯ ТЕКСТ, а не по действително измерена
  /// височина. Главата е един непрекъснат блок с еднакъв шрифт, тъй че
  /// знак от текста ≈ еднакъв дял от височината — за чертичките по
  /// скролбара това е достатъчно точно и не иска мерене на всеки абзац.
  /// (В четеца на жития е другояче: там четивото е разделено на региони с
  /// различни шрифтове и височините се оценяват поотделно.)
  void _runSearch(String raw) {
    final q = fold(raw.trim()).text;
    final plain =
        _plainOf(_normalize(widget.book.readFile(_current.href) ?? ''));
    final folded = fold(plain);
    final ratios = <double>[];
    if (q.isNotEmpty && folded.text.isNotEmpty) {
      var from = 0;
      while (true) {
        final at = folded.text.indexOf(q, from);
        if (at < 0) break;
        ratios.add(folded.origIndex[at] / plain.length);
        from = at + q.length;
      }
    }
    setState(() {
      _query = q;
      _hitRatios = ratios;
      _total = ratios.length;
      _currentHit = ratios.isEmpty ? -1 : 0;
    });
    if (ratios.isNotEmpty) _scrollToHit(0);
  }

  /// Колко пъти се среща заявката в даден откъс HTML.
  int _countHits(String html) {
    if (_query.isEmpty) return 0;
    final folded = fold(_plainOf(html));
    var n = 0, from = 0;
    while (true) {
      final at = folded.text.indexOf(_query, from);
      if (at < 0) break;
      n++;
      from = at + _query.length;
    }
    return n;
  }

  /// Чистият текст на главата — по него се броят и разполагат съвпаденията.
  static String _plainOf(String html) => html
      .replaceAll(RegExp(r'<[^>]+>'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  void _scrollToHit(int i) {
    if (i < 0 || i >= _hitRatios.length || !_scroll.hasClients) return;
    final max = _scroll.position.maxScrollExtent;
    // Съвпадението се вкарва малко под горния ръб, а не залепено за него —
    // така се вижда и редът преди него.
    final target = (_hitRatios[i] * max - 80).clamp(0.0, max);
    _scroll.animateTo(target,
        duration: const Duration(milliseconds: 280), curve: Curves.easeOut);
  }

  void _stepHit(int delta) {
    if (_total == 0) return;
    setState(() => _currentHit = (_currentHit + delta + _total) % _total);
    _scrollToHit(_currentHit);
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
      // Чертичките за намереното стоят НАД скрола, затова е Stack: те са
      // показалец, не част от текста.
      body: Stack(children: [
        SafeArea(
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
                  // При ТЪРСЕНЕ лентите остават заковани: иначе полето за
                  // въвеждане и броячът изчезват при първото плъзгане към
                  // намереното. Същото прави и четецът на жития.
                  floating: !_searchOpen,
                  snap: !_searchOpen,
                  pinned: _searchOpen,
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
          onSearch: _toggleSearch,
          searchOpen: _searchOpen,
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
                  bottom: _searchOpen ? _searchBar() : null,
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
        // Отстъпът отгоре съвпада с височината на лентата (44) плюс тази
        // за търсене (52) — за да легнат чертичките точно върху скролбара.
        if (_searchOpen && _total > 0)
          matchTicksOverlay(
            ratios: _hitRatios,
            currentIndex: _currentHit,
            palette: palette,
            top: 44 + 52 + 4,
          ),
      ]),
      bottomNavigationBar: _showNavBar ? _navBar(palette) : null,
    );
  }

  Widget _chapterBody(String raw, ReaderPalette palette) {
    var body = _normalize(raw);
    // Маркирането е ОБЩО с четеца на жития (виж reader_search.dart): то
    // обвива намереното в <span class="hit">, а стиловете го оцветяват.
    if (_query.isNotEmpty) {
      body = highlightHtml(body, _query, 0, _currentHit);
    }
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
              // Първите редове се рисуват РЪЧНО (Text.rich), не през
              // flutter_html — значи маркирането трябва да им се подаде
              // отделно. Без това намереното в началото на главата оставаше
              // неоцветено.
              searchQuery: _query,
              // Съвпаденията се броят ГЛОБАЛНО за цялата глава, а буквицата
              // започва след beforeHtml (заглавието и реда с паметта).
              // Затова ѝ се подава колко са намерени преди нея — иначе
              // „текущото" би се оцветило на грешно място.
              firstGlobalMatchIndex: _countHits(beforeHtml),
              currentGlobalMatch: _currentHit,
              hitColor: palette.hit,
              hitCurrentColor: palette.hitCurrent,
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

  /// Лентата за търсене — ЕДНАКВА с тази в четеца на жития: същата
  /// височина, същите отстояния, същото поле със заоблен тъмен фон и същите
  /// кръгли бутони. За потребителя двата екрана са един и същи четец.
  PreferredSizeWidget _searchBar() {
    final fg = AppBarTheme.of(context).foregroundColor ?? Colors.white;
    return PreferredSize(
      preferredSize: const Size.fromHeight(58),
      child: Container(
        height: 58,
        // Дясната страна е по-широка — броячът иначе се залепва за
        // чертичките по скролбара, които стоят точно в тази зона.
        padding: const EdgeInsets.fromLTRB(12, 6, 17, 6),
        color: AppColors.toolbar,
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _searchCtrl,
                focusNode: _searchFocus,
                style: TextStyle(color: fg, fontSize: 16),
                textInputAction: TextInputAction.search,
                onChanged: _runSearch,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Търсене в текста…',
                  hintStyle: TextStyle(color: fg.withValues(alpha: 0.5)),
                  contentPadding: const EdgeInsets.symmetric(
                      vertical: 8, horizontal: 10),
                  filled: true,
                  fillColor: Colors.black.withValues(alpha: 0.15),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            RoundIconButton(
              icon: Icons.chevron_left,
              tooltip: 'Предишно съвпадение',
              enabled: _total > 0,
              onTap: () => _stepHit(-1),
              size: kReaderBtnSize + 6,
            ),
            const SizedBox(width: 16),
            RoundIconButton(
              icon: Icons.chevron_right,
              tooltip: 'Следващо съвпадение',
              enabled: _total > 0,
              onTap: () => _stepHit(1),
              size: kReaderBtnSize + 6,
            ),
            const SizedBox(width: 12),
            Text(
              _total > 0 ? '${_currentHit + 1}/$_total' : '0/0',
              maxLines: 1,
              softWrap: false,
              style: TextStyle(color: fg, fontSize: 13),
            ),
          ],
        ),
      ),
    );
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
