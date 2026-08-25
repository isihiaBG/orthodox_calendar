// bible_reader.dart
//
// Третият четец — за секцията „Библия" (после и за „Молитвослов").
//
// Изглежда като четеца на книги, но взима текста от база (bible.db), а не от
// .epub, и умее две неща, които другите два нямат: ПОДРАВНЕН ПАРАЛЕЛЕН
// ПРЕВОД и смяна на езика в движение.
//
//   изправено   един превод на цяла ширина; плъзгане наляво/надясно минава
//               на другия от двойката, БЕЗ да губи мястото;
//   легнало     двата успоредно, всеки в своя колона, с черта по средата;
//               редовете са подравнени по номер на стих.
//
// ⚠ ГЛАВНОТО ОПРОСТЕНИЕ СПРЯМО ДРУГИТЕ ДВА ЧЕТЕЦА: тук позицията се закача
// за СТИХ, а не за (регион, знак) или за пиксел.
//
// В житията и книгите текстът е свързана проза — там „къде съм" се пази като
// абзац плюс индекс на знак и се превежда в пиксел при всяко построяване
// (виж text_line_locator.dart и цялата поредица бележки в CLAUDE.md за
// „недоскролването"). Причината е, че прозата няма естествени спирки.
//
// Писанието ИМА. Стихът е готова, устойчива, ситна котва: не се мени с
// шрифта, не се мени с ширината, не се мени със завъртането — и е една и
// съща в двата превода. Затова целият механизъм тук се свежда до „запомни
// кой стих е най-горе, върни се на него" и НЕ бива да се усложнява по
// образеца на другите два. Оттам следва и че цялата глава се строи наведнъж
// (най-дългата е Пс. 118 със 176 стиха) — виртуализация не е нужна, а без
// нея позиционирането е точно, не приблизително.

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'app_theme.dart';
import 'bible_db.dart';
import 'bible_language_pair.dart';
import 'package:flutter/services.dart';

import 'reader_footer.dart';
import 'reader_more_menu.dart';
import 'reader_font_size.dart';
import 'reader_theme.dart';
import 'reader_toolbar.dart';
import 'settings_screen.dart';

/// Разстоянието между номера на стиха и текста му.
///
/// ⚠ Вдигнато, след като номерата станаха ДЯСНО подравнени: дотогава те се
/// центрираха в колонката си и сами си оставяха въздух отдясно. Подравнени,
/// всички опират в един и същ ръб и без този отстъп биха се залепили за
/// първата буква. Това е равнозначното на отстъпа в клетка от таблица —
/// разстоянието се задава веднъж тук и важи за двете подредби.
const double _kNumberGap = 11.0;

/// Ширината на колонката с номерата, като дял от размера на шрифта.
///
/// ⚠ ПРОИЗВОДНА, а не закована. Стоеше твърдо 30 и при подразбиращите се 16
/// пункта зееше — номерът заема към 22, а останалите 8 просто изяждаха
/// ширина от текста. Заковано число или зее при дребен шрифт, или реже при
/// едър: най-дългият номер е трицифрен (Пс. 118 стига до 176).
///
/// Сметката: номерът се рисува с 0.78 от основния размер, а цифрата в
/// системния шрифт е около 0.55 em — тоест три цифри искат
/// 3 × 0.55 × 0.78 ≈ 1.29 от основния. Закръглено нагоре за въздух.
///
/// Колонката остава ЕДНА ширина за цялата глава (не се свива при
/// едноцифрени стихове) — инак текстът вдясно щеше да подскача навън-навътре
/// от ред на ред.
const double _kNumberWidthFactor = 0.95;

/// ⚠ Номерът НЕ СЕ ПРЕНАСЯ и има право да излезе НАЛЯВО извън колонката си.
///
/// Колонката е свита нарочно — трицифрени номера има само в няколко книги
/// (Пс. 118 стига до 176) и заради тях цялата глава щеше да плаща отстъп,
/// който 99% от стиховете не ползват. Затова ширината е сметната за
/// двуцифрено, а рядкото трицифрено изпълзява наляво, в празното поле.
///
/// Надясно не може — там е дясното подравняване и текстът; наляво няма
/// какво да засегне.

/// Отстояние между два стиха.
const double _kVerseGap = 10.0;

/// Междуредието вътре в стиха.
///
/// По-сбито от четците за проза (там е 1.6): тук редът е по-къс, а до него
/// стои колонка с номер, тъй че текстът и без това има повече въздух около
/// себе си. ⚠ Ползва се и от номера на стиха — първият му ред трябва да
/// легне на същата основна линия като първия ред на стиха.
const double _kLineHeight = 1.35;

/// От условното име в базата (`languages.font`) към истинското семейство,
/// обявено в `pubspec.yaml`.
///
/// ⚠ Указателят е ИЗРИЧЕН нарочно. Дотогава името от базата се подаваше
/// направо на `TextStyle`, а Flutter подминава МЪЛЧАЛИВО всяко семейство,
/// което не е обявено в pubspec (записано е в CLAUDE.md). Тоест разликата
/// между „шрифтът го няма" и „сгрешено име в базата" беше невидима — и
/// двете даваха системния шрифт без нито дума. Сега неописаното тук пада до
/// системния СЪЗНАТЕЛНО, а сбърканото име личи веднага при добавяне.
///
/// Липсващите редове (`greek`, `hebrew`, `georgian`) не са пропуск: за тях
/// системният покрива данните напълно — измерено срещу базата, 0 липсващи
/// знака. Влезе ли някой ден свой шрифт, добавя се тук.
/// Първото име е основното, останалите са резерв — обхождат се ЗА ВСЕКИ
/// ОТДЕЛЕН ГЛИФ, преди да се падне до системния.
const Map<String, List<String>> _kFontFamilies = {
  // Triodion рисува църковнославянското; Monomakh е по-широк (815 знака
  // срещу 527 — добавя 132 латински, 56 кирилски и 43 надредни) и хваща
  // онова, което Triodion няма.
  //
  // ⚠ Петте гръцки знака в цсл текста (β, ά, τ, ο, ς — по едно срещане
  // всеки) ги няма в НИТО ЕДИН от двата, проверено. Тях поема системният,
  // до който веригата се пада сама.
  'cslavonic': ['Triodion', 'Monomakh'],
  'charis': [kBodyFamily],
};

class BibleReader extends StatefulWidget {
  final String bookCode;
  final int chapter;

  /// Стих, на който да се отвори (от търсене, от отметка, от дневно четиво).
  final String? initialVerse;

  const BibleReader({
    super.key,
    required this.bookCode,
    required this.chapter,
    this.initialVerse,
  });

  @override
  State<BibleReader> createState() => _BibleReaderState();
}

class _BibleReaderState extends State<BibleReader>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  final ScrollController _scroll = ScrollController();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  /// Докъде е плъзнат преводът: 0 = първият от двойката, 1 = вторият.
  ///
  /// ⚠ Дробна е ПО ВРЕМЕ НА ЖЕСТА — оттам идва усещането, че дърпаш съседна
  /// колона, а не че натискаш бутон. Пръстът я движи направо, а при пускане
  /// тя се доиграва до най-близкия цял.
  late final AnimationController _slide;

  /// Кои два превода са ЗАРЕДЕНИ в `_rows`.
  ///
  /// ⚠ Различава се от „кой се показва". Смяната на показвания превод НЕ
  /// пипа базата — `alignChapter` вече е донесъл и двата, тъй че плъзгането
  /// е чисто рисуване. Точно презареждането при всяко плъзгане правеше
  /// онова премигване; заявка се пуска само когато се смени самата ДВОЙКА.
  String? _loadedFirst;
  String? _loadedSecond;

  /// По един ключ на ред от главата — по тях се мери кой стих е най-горе и
  /// до кой да се скролва. Понеже цялата глава е построена, тези ключове
  /// ВИНАГИ имат геометрия; оттам идва точността.
  final Map<String, GlobalKey> _rowKeys = {};

  BibleBook? _book;
  List<BibleRow> _rows = const [];
  List<BibleLanguage> _langs = const [];
  List<BibleBook> _allBooks = const [];
  /// Подзаглавията, по превод и по стих: `_titles[lang][verse]`.
  ///
  /// ⚠ По ПРЕВОД, не само за показвания. Заглавието влиза ВЪТРЕ в плъзгащата
  /// се клетка, тъй че всеки превод носи своите; инак при плъзгане редовете
  /// щяха да се разместят точно там, където единият език има заглавие, а
  /// другият не.
  Map<String, Map<String, List<String>>> _titles = const {};

  /// Богослужебните зачала, по превод и по стих: `_zachala[lang][verse]`.
  ///
  /// Вадеха се от самото начало, но досега не се показваха никъде. Сега стоят
  /// в началото на своя стих, в червено — както в печатните богослужебни
  /// книги.
  Map<String, Map<String, List<String>>> _zachala = const {};

  bool _loading = true;
  String? _error;

  /// Стихът, на който да се върнем след прекомпоновка (завъртане, смяна на
  /// шрифта, смяна на превода). Пази се, докато не бъде употребен.
  String? _pendingAnchor;

  bool? _wasLandscape;

  /// Ширината на текстовата колона в пиксели — колкото трябва да измине едно
  /// пълно плъзгане. Мери се веднъж при построяване и се ползва от жеста, за
  /// да превърне изминатото от пръста в дял от прехода.
  double _textWidth = 1;



  /// Лентата да не се крие, докато трае наша собствена корекция на скрола.
  /// Виж бележката при SliverAppBar в [_body].
  bool _toolbarPinned = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _slide = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
      value: BibleLanguages.value.active.toDouble(),
    );
    // ⚠ immersiveSticky, не immersive — при жест отгоре лентата наднича и се
    // скрива сама, вместо да остане. Същото като в четеца на книги.
    //
    // ⚠ НЕ СЕ ВРЪЩА в dispose(): оттук се излиза към съдържанието на
    // „Библия", което също е без лента. Паленето и гасенето между двата
    // екрана се вижда като премигване — записано в CLAUDE.md.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    BibleLanguages.notifier.addListener(_onLanguageChanged);
    _scroll.addListener(_releaseToolbarOnDrag);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    BibleLanguages.notifier.removeListener(_onLanguageChanged);
    ReaderTheme.flush();
    ReaderFontSize.flush();
    BibleFontSize.flush();
    _slide.dispose();
    _scroll.removeListener(_releaseToolbarOnDrag);
    _scroll.dispose();
    super.dispose();
  }

  // ── Зареждане ────────────────────────────────────────────────────────

  Future<void> _load() async {
    try {
      await ReaderTheme.loadOnce();
      await ReaderFontSize.loadOnce();
      await BibleFontSize.loadOnce();

      final langs = await BibleDb.languages();
      await BibleLanguages.loadOnce([for (final l in langs) l.code]);

      final allBooks = await BibleDb.books();
      final book = await BibleDb.book(widget.bookCode);
      if (book == null) throw StateError('Няма книга „${widget.bookCode}"');

      final pair = BibleLanguages.value;
      final rows =
          await BibleDb.alignChapter(book.code, widget.chapter, pair.both);
      final titles = await _titlesForBoth(book.code, pair);
      final zachala = await _zachalaForBoth(book.code, pair);

      if (!mounted) return;
      setState(() {
        _book = book;
        _allBooks = allBooks;
        _langs = langs;
        _rows = rows;
        _titles = titles;
        _zachala = zachala;
        _loadedFirst = pair.first;
        _loadedSecond = pair.second;
        _slide.value = pair.active.toDouble();
        _loading = false;
        _error = rows.isEmpty ? 'Тази глава още не е свалена.' : null;
      });

      if (widget.initialVerse != null) {
        _pendingAnchor = widget.initialVerse;
        _restorePending();
      }
    } catch (e) {
      // ⚠ Грешката се РАЗЛИЧАВА от празния резултат. Изгледите тук минаха
      // веднъж през този капан: FutureBuilder без клон за hasError показваше
      // всяка грешка като „няма данни" и се търсеше с часове (виж бележката
      // за MiniReader в CLAUDE.md).
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Грешка при четене: $e';
      });
    }
  }

  /// Смяна на превода — презарежда, като пази мястото по СТИХ.
  ///
  /// Точно тук личи защо котвата е стих: българският стих 12 и
  /// църковнославянският стих 12 са едно и също място в Писанието, колкото и
  /// да се различават по дължина. При пиксел или ред връщането би било
  /// приблизително.
  Future<void> _onLanguageChanged() async {
    if (!mounted || _book == null) return;
    final pair = BibleLanguages.value;

    // ⚠ САМО СМЯНА НА ПОКАЗВАНИЯ — базата не се пипа.
    //
    // Двойката е същата, тоест `_rows` вече носи и двата превода: те са
    // донесени наведнъж от alignChapter(). Оставаше ли презареждането тук,
    // всяко плъзгане пускаше заявка и предизвикваше празен кадър — точно
    // премигването, от което трябва да се отървем. Освен това позицията
    // изобщо не се губи: нищо в подредбата не се мени.
    if (pair.first == _loadedFirst && pair.second == _loadedSecond) {
      final target = pair.active.toDouble();
      if ((_slide.value - target).abs() > 0.001) {
        _slide.animateTo(target,
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic);
      }
      return;
    }

    // Сменена е самата ДВОЙКА (от падащото меню) — това вече иска четене.
    _pendingAnchor ??= _topmostVerse();
    final rows =
        await BibleDb.alignChapter(_book!.code, widget.chapter, pair.both);
    final titles = await _titlesForBoth(_book!.code, pair);
    final zachala = await _zachalaForBoth(_book!.code, pair);
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _titles = titles;
      _zachala = zachala;
      _loadedFirst = pair.first;
      _loadedSecond = pair.second;
    });
    _slide.value = pair.active.toDouble();
    _restorePending();
  }

  /// Зачалата за ДВАТА превода наведнъж.
  Future<Map<String, Map<String, List<String>>>> _zachalaForBoth(
      String book, BibleLanguagePair pair) async {
    final out = <String, Map<String, List<String>>>{};
    for (final lang in pair.both) {
      out[lang] = await BibleDb.zachala(book, widget.chapter, lang);
    }
    return out;
  }

  /// Подзаглавията за ДВАТА превода наведнъж.
  Future<Map<String, Map<String, List<String>>>> _titlesForBoth(
      String book, BibleLanguagePair pair) async {
    final out = <String, Map<String, List<String>>>{};
    for (final lang in pair.both) {
      out[lang] = await BibleDb.titles(book, widget.chapter, lang);
    }
    return out;
  }

  // ── Позицията ────────────────────────────────────────────────────────

  /// Кой стих стои най-горе в изгледа в момента.
  ///
  /// Мери се по РЕАЛНАТА геометрия на построените редове, а не по оценка:
  /// цялата глава е в дървото, тъй че всеки ред има кутия.
  String? _topmostVerse() {
    if (!_scroll.hasClients) return null;
    final viewportBox = context.findRenderObject() as RenderBox?;
    if (viewportBox == null) return null;
    final top = viewportBox.localToGlobal(Offset.zero).dy;

    String? best;
    double bestDy = double.negativeInfinity;
    for (final row in _rows) {
      final ctx = _rowKeys[row.verse]?.currentContext;
      if (ctx == null) continue;
      final box = ctx.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) continue;
      final dy = box.localToGlobal(Offset.zero).dy - top;
      // Търси се последният ред, който още НЕ е излязъл над горния ръб —
      // тоест онзи, който човекът вижда пръв.
      if (dy <= 1 && dy > bestDy) {
        bestDy = dy;
        best = row.verse;
      }
      if (dy > 1) {
        best ??= row.verse;
        break;
      }
    }
    return best;
  }

  /// Връща изгледа на запомнения стих. Изчаква кадър, за да е построена
  /// новата подредба.
  void _restorePending() {
    final verse = _pendingAnchor;
    if (verse == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _jumpToVerse(verse, animate: false);
      _pendingAnchor = null;
    });
  }

  /// Скролва, докато стихът застане най-горе.
  ///
  /// ⚠ `jumpTo`, не `animateTo`, при връщане след прекомпоновка. Анимацията
  /// оставя прозорец, в който следващо събитие (второ завъртане, второ
  /// натискане на +) заварва скрола ПО СРЕДА и улавя нито старата, нито
  /// новата позиция — така грешката се натрупва. Същият урок е записан в
  /// CLAUDE.md за другите два четеца.
  void _jumpToVerse(String verse, {bool animate = true}) {
    final ctx = _rowKeys[verse]?.currentContext;
    if (ctx == null || !_scroll.hasClients) return;
    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null) return;

    final viewport = RenderAbstractViewport.of(box);
    final target = viewport
        .getOffsetToReveal(box, 0.0)
        .offset
        .clamp(_scroll.position.minScrollExtent,
            _scroll.position.maxScrollExtent);

    if (animate) {
      _scroll.animateTo(target,
          duration: const Duration(milliseconds: 260), curve: Curves.easeOut);
    } else {
      _scroll.jumpTo(target);
    }
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    final views = WidgetsBinding.instance.platformDispatcher.views;
    if (views.isEmpty) return;
    final size = views.first.physicalSize;
    if (size.isEmpty) return;
    final landscape = size.width > size.height;
    final was = _wasLandscape;
    _wasLandscape = landscape;
    // ⚠ Сравнява се СЪОТНОШЕНИЕТО, не височината: клавиатурата мени само
    // височината и не е завъртане.
    if (was == null || was == landscape) return;

    // Геометрията в мига на didChangeMetrics е още СТАРАТА — улавяме сега,
    // връщаме след прекомпоновката.
    _pendingAnchor ??= _topmostVerse();
    _restorePending();
  }

  /// +/- на шрифта. Пази мястото по същия път като завъртането.
  /// Освобождава лентата чак при ИСТИНСКО влачене с пръст.
  ///
  /// ⚠ `userScrollDirection` се мени единствено при реално докосване, НЕ при
  /// програмни `jumpTo`/`animateTo` — точно затова се следи то, а не голото
  /// `pixels`.
  void _releaseToolbarOnDrag() {
    if (!_toolbarPinned || !_scroll.hasClients) return;
    if (_scroll.position.userScrollDirection == ScrollDirection.reverse) {
      setState(() => _toolbarPinned = false);
    }
  }

  void _bumpFont(double delta) {
    _pendingAnchor ??= _topmostVerse();
    _toolbarPinned = true;
    setState(() => BibleFontSize.nudge(delta));
    _restorePending();
  }

  // ── Рисуване ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final palette = ReaderTheme.palette;
    final landscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    return Scaffold(
      key: _scaffoldKey,
      // ⚠ Цветът на СКЕЛЕТА е този на лентата, а фонът на страницата идва от
      // Container ВЪТРЕ в SafeArea. Сложи ли се фонът на четеца върху
      // скелета, ивицата на системната лента светва кремава заедно със
      // страницата — същият похват като в другите два четеца.
      backgroundColor: AppColors.toolbar,
      endDrawer: const SettingsDrawer(sections: {SettingsSection.reader}),
      body: SafeArea(
        child: Container(
          color: palette.bg,
          // ⚠ Лентата е ВЪТРЕ в скрола (виж _body), не над него — иначе не
          // може да се скрива. При зареждане и при грешка обаче тя трябва да
          // се вижда неподвижно, затова тогава се рисува отделно.
          child: (_loading || _error != null)
              ? Column(
                  children: [
                    _toolbar(palette, landscape),
                    Expanded(child: _body(palette, landscape)),
                  ],
                )
              : _body(palette, landscape),
        ),
      ),
    );
  }

  Widget _body(ReaderPalette palette, bool landscape) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!,
              textAlign: TextAlign.center,
              style: TextStyle(color: palette.dim, fontSize: 16)),
        ),
      );
    }

    final pair = BibleLanguages.value;
    final content = Theme(
      data: Theme.of(context)
          .copyWith(scrollbarTheme: readerScrollbarTheme(palette)),
      child: Scrollbar(
        controller: _scroll,
        child: CustomScrollView(
          controller: _scroll,
          slivers: [
            // ⚠ Лентата се СКРИВА при скрол надолу и се връща при скрол
            // нагоре — както в другите два четеца. `floating + snap` дава
            // точно това поведение.
            //
            // ⚠ `pinned: _toolbarPinned` е защитата срещу собствените ни
            // скокове: смяната на шрифта и завъртането местят скрола
            // програмно (`jumpTo`), а floating лентата чете ВСЯКО движение
            // като „скрол надолу" и се скрива точно докато пръстът е върху
            // +/-. Записано е в CLAUDE.md за другите четци — тук важи
            // дословно.
            SliverAppBar(
              floating: true,
              snap: !_toolbarPinned,
              pinned: _toolbarPinned,
              automaticallyImplyLeading: false,
              backgroundColor: AppColors.toolbar,
              elevation: 0,
              toolbarHeight: kReaderToolbarHeight,
              titleSpacing: 0,
              title: _toolbar(palette, landscape),
              // ⚠ ПРАЗЕН списък, а не липсващ. Оставен ли е null, Scaffold
              // сам добавя копче за `endDrawer` — хамбургер най-вдясно, който
              // не е наш и разваля реда. Менюто се отваря от трите точки.
              actions: const [],
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              sliver: SliverToBoxAdapter(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    // Ширината се мери ВЕДНЪЖ тук и се подава надолу, вместо
                    // всеки от 176-те реда да си слага свой LayoutBuilder.
                    final textWidth =
                        constraints.maxWidth - _numberWidth - _kNumberGap;
                    _textWidth = textWidth > 1 ? textWidth : 1;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        landscape
                            ? _parallelColumns(palette, pair)
                            : _slidingColumn(palette, pair, _textWidth),
                        _footer(palette),
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );

    if (landscape) return content;

    // ⚠ Плъзгането движи преводите НАПРАВО с пръста, без да чака пускане.
    // Смисълът е точно в междинните положения: човек дърпа наляво-надясно,
    // без да вдига пръст, и сравнява един и същ стих на двата езика.
    //
    // Затова тук НЯМА праг на скоростта и НЯМА „премести се, ако жестът е
    // достатъчно силен". Има само: пръстът дърпа, при пускане се доиграва до
    // по-близкия.
    //
    // Стои САМО в изправено положение: в легнало двата и без това се виждат,
    // а жестът би пречел на избора на текст.
    return GestureDetector(
      onHorizontalDragUpdate: (d) {
        final dx = d.primaryDelta ?? 0;
        _slide.value = (_slide.value - dx / _textWidth).clamp(0.0, 1.0);
      },
      onHorizontalDragEnd: (d) => _settleSlide(d.primaryVelocity ?? 0),
      onHorizontalDragCancel: () => _settleSlide(0),
      child: content,
    );
  }

  /// Доиграва плъзгането до цял превод и чак тогава записва избора.
  ///
  /// ⚠ Записът е НАКРАЯ, не по време на жеста. `BibleLanguages.set` пази на
  /// диска и известява слушателите; направено на всеки кадър, това би удряло
  /// SharedPreferences стотици пъти за едно дръпване.
  void _settleSlide(double velocity) {
    final pair = BibleLanguages.value;
    // Бърз замах решава посоката; бавно пускане — по това коя половина е
    // по-близо.
    final target = velocity.abs() > 320
        ? (velocity < 0 ? 1.0 : 0.0)
        : (_slide.value >= 0.5 ? 1.0 : 0.0);

    _slide
        .animateTo(target,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic)
        .whenComplete(() {
      if (!mounted) return;
      final wanted = target == 1.0 ? 1 : 0;
      if (BibleLanguages.value.active != wanted) {
        BibleLanguages.set(pair.copyWith(active: wanted));
      }
    });
  }

  /// Изправено: колонка с номерата, закована по X, и плъзгащи се преводи.
  ///
  /// ⚠ Номерът стои ИЗВЪН плъзгащото се. Той е един и същ за двата превода —
  /// стих 12 си е стих 12 — тъй че да се движи заедно с текста би било
  /// безсмислено трептене. По Y се движи свободно с реда, защото е част от
  /// същия отвесен скрол.
  Widget _slidingColumn(
      ReaderPalette palette, BibleLanguagePair pair, double textWidth) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final row in _rows)
          Container(
            key: _keyFor(row.verse),
            padding: const EdgeInsets.only(bottom: _kVerseGap),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: _numberWidth, child: _number(palette, row)),
                const SizedBox(width: _kNumberGap),
                SizedBox(
                  width: textWidth,
                  child: _slidingPair(palette, row, pair, textWidth),
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// Двата превода на ЕДИН стих, наслоени и отместени по X.
  ///
  /// ⚠ ТУК Е ПОДРАВНЯВАНЕТО, и то излиза само от `Stack`. Стекът приема
  /// размера на НАЙ-ГОЛЯМОТО си дете, тъй че редът е висок колкото
  /// по-дългата от двете клетки — независимо коя се вижда в момента.
  /// Следствията са три и всичките са поискани:
  ///
  ///   • началата на стиховете съвпадат по вертикала в двата превода;
  ///   • при по-къс стих остава празнина — тя Е разликата между езиците и
  ///     не бива да се „поправя";
  ///   • височината НЕ се мени при плъзгане, тъй че нищо не подскача под
  ///     пръста и колонката с номерата остава срещу своя стих.
  ///
  /// ⚠ `Transform.translate` НЕ влияе на подредбата — само на рисуването.
  /// Затова стекът си остава висок колкото трябва, докато двете клетки се
  /// разминават встрани. Ако това някога се смени на нещо, което мени
  /// размера, подравняването пада.
  ///
  /// ⚠ И двата текста са построени ВИНАГИ, не се строи този под пръста.
  /// Заявка към базата по време на жеста би значела празен кадър насред
  /// плъзгането — точно премигването, което трябва да го няма.
  Widget _slidingPair(ReaderPalette palette, BibleRow row,
      BibleLanguagePair pair, double w) {
    final first = SizedBox(width: w, child: _verseBody(palette, row, pair.first));
    final second =
        SizedBox(width: w, child: _verseBody(palette, row, pair.second));

    return ClipRect(
      child: AnimatedBuilder(
        animation: _slide,
        builder: (context, _) {
          final t = _slide.value;
          return Stack(
            alignment: AlignmentDirectional.topStart,
            children: [
              Transform.translate(
                  offset: Offset(-t * w, 0), child: first),
              Transform.translate(
                  offset: Offset((1 - t) * w, 0), child: second),
            ],
          );
        },
      ),
    );
  }

  /// Легнало: двата превода успоредно, с черта по средата.
  ///
  /// ⚠ Тук подравняването иска `IntrinsicHeight`, за да се разтегне и
  /// ЧЕРТАТА по цялата височина на реда. В изправено положение черта няма и
  /// стекът се справя сам — виж `_slidingPair`.
  Widget _parallelColumns(ReaderPalette palette, BibleLanguagePair pair) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final row in _rows)
          Container(
            key: _keyFor(row.verse),
            padding: const EdgeInsets.only(bottom: _kVerseGap),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(width: _numberWidth, child: _number(palette, row)),
                  const SizedBox(width: _kNumberGap),
                  Expanded(child: _verseBody(palette, row, pair.first)),
                  // Чертата по средата — тънка и приглушена: тя разделя, а не
                  // рисува таблица. Границите между РЕДОВЕТЕ нарочно ги няма.
                  Container(
                    width: 1,
                    margin: const EdgeInsets.symmetric(horizontal: 12),
                    color: palette.dim.withValues(alpha: 0.25),
                  ),
                  Expanded(child: _verseBody(palette, row, pair.second)),
                ],
              ),
            ),
          ),
      ],
    );
  }

  /// Номерът на стиха.
  ///
  /// Расте с текста, но остава по-дребен и приглушен: той е указател, не
  /// четиво. Със СИСТЕМНИЯ шрифт нарочно — цифрите трябва да изглеждат
  /// еднакво до всеки превод, а не да менят вида си според това кой език
  /// стои вдясно от тях.
  /// Стих с рубрикация: зачалото и главната буква в началото — в червено.
  ///
  /// ДВЕ ПРАВИЛА, и двете поискани изрично:
  ///
  /// 1. ⚠ Първата буква става червена САМО ако е ГЛАВНА. Много стихове
  ///    продължават изречение от предишния и започват с малка буква; там
  ///    рубрикацията би изглеждала произволна, защото не бележи начало на
  ///    нищо. Червеното трябва да значи „тук започва", а не „тук е ред 5".
  ///
  /// 2. Има ли зачало, то и главната буква след него са ЕДНО ЦЯЛО и се
  ///    оцветяват заедно — така стои и в печатните богослужебни книги.
  ///    Зачалото се оцветява дори когато буквата подире му е малка: то си е
  ///    указател и винаги се откроява.
  ///
  /// ⚠ „Първата буква" НЕ Е първият ЗНАК. Църковнославянският носи титли,
  /// ударения и придихания като ОТДЕЛНИ кодови точки след буквата: „А҆" е
  /// два знака, „Ѻ҆̀" — три. Отреже ли се по `text[0]`, буквата остава
  /// червена, а знакът ѝ — черен, залепен за следващата дума. Затова се реже
  /// по ГРАФЕМА (`characters`), която събира буквата с всичките ѝ надредни
  /// знаци. В цсл текст това не е педантизъм — почти всяка втора дума
  /// започва с такова съчетание.
  ///
  /// Червеното е `palette.wine` — същото, с което приложението вече пише
  /// подзаглавията, а не ново.
  /// Зачалата за този стих в този превод, ако има.
  /// Зачалата за този стих.
  ///
  /// ⚠ Ако ТОЗИ превод няма зачало на този стих, се взима от онзи, който
  /// има. Зачалото е свойство на МЯСТОТО в Писанието, не на превода —
  /// същото разсъждение като при надписанията. Източникът ги бележи само в
  /// руския (725), а те важат еднакво за църковнославянския и за българския.
  List<String>? _zachalaFor(String lang, BibleRow row) {
    final own = _zachala[lang]?[row.verse];
    if (own != null && own.isNotEmpty) return own;
    for (final entry in _zachala.entries) {
      final list = entry.value[row.verse];
      if (list != null && list.isNotEmpty) return list;
    }
    return null;
  }

  Widget _rubricated(
    String text,
    TextStyle style,
    ReaderPalette palette,
    List<String>? zachala,
  ) {
    final red = TextStyle(color: palette.wine);
    final spans = <TextSpan>[];

    if (zachala != null && zachala.isNotEmpty) {
      spans.add(TextSpan(text: '[${zachala.join(' ')}] ', style: red));
    }

    if (text.isEmpty) {
      return Text.rich(TextSpan(style: style, children: spans));
    }

    final first = text.characters.first;
    final rest = text.characters.skip(1).toString();

    // Главна ли е: буквата се мени при снижаване, но не и при повдигане.
    // Тази проверка минава и за знаци без регистър (цифри, кавички) — те
    // остават в основния цвят, което е и желаното.
    final isCapital = first.toUpperCase() == first &&
        first.toLowerCase() != first;

    if (isCapital) {
      spans.add(TextSpan(text: first, style: red));
      spans.add(TextSpan(text: rest));
    } else {
      spans.add(TextSpan(text: text));
    }

    return Text.rich(
      TextSpan(style: style, children: spans),
      textAlign: TextAlign.start,
    );
  }

  /// Ширината на колонката с номерата при текущия размер на шрифта.
  /// Ширината на колонката с номерата ЗА ТАЗИ ГЛАВА.
  ///
  /// ⚠ Смята се по най-дългия номер в главата, не по най-дългия в цялата
  /// Библия. Така Мт. 5 получава тясна колонка, а Пс. 118 (стих 176) —
  /// толкова, колкото ѝ трябва. Заковано „за всеки случай трицифрено" би
  /// карало всяка глава да плаща отстъп, който почти никоя не ползва.
  ///
  /// ⚠ ЕДНА ширина за цялата глава, а не за всеки ред поотделно: инак
  /// текстът вдясно щеше да подскача навън-навътре между стих 99 и стих 100.
  ///
  /// Дотук стоеше `OverflowBox`, за да може рядкото трицифрено число да
  /// изпълзи наляво извън тясна колонка. Отхвърлено — вътре в скрол той
  /// получава нулева височина и РЕДОВЕТЕ СЕ НАСЛАГВАТ един върху друг.
  double get _numberWidth {
    var digits = 2;
    for (final r in _rows) {
      if (r.verse.length > digits) digits = r.verse.length;
    }
    return BibleFontSize.value * _kNumberWidthFactor * (digits / 2);
  }

  Widget _number(ReaderPalette palette, BibleRow row) {
    final size = BibleFontSize.value;
    return Text(
      row.verse == '0' ? '' : row.verse,
      // ⚠ ДЯСНО подравняване, не центрирано. Номерата са едно-, дву- и
      // трицифрени; центрирани, единиците увисват навътре и колоната
      // изглежда разкривена. Подравнени вдясно, всички опират в текста на
      // еднакво разстояние — както е в печатните Библии.
      textAlign: TextAlign.right,
      maxLines: 1,
      softWrap: false,
      style: TextStyle(
        fontSize: size * 0.78,
        // Първият ред на номера трябва да легне на същата основна линия като
        // първия ред на стиха — оттам делението на същото междуредие.
        height: _kLineHeight / 0.78,
        color: palette.dim,
      ),
    );
  }

  /// Съдържанието на една клетка: подзаглавията на този превод (ако има) и
  /// текстът на стиха.
  ///
  /// ⚠ Подзаглавието влиза ВЪТРЕ в клетката, а не като свой ред над нея.
  /// Сръбският носи заглавия там, където другите преводи нямат; извадено
  /// навън, то би отместило само едната колона и подравняването щеше да се
  /// разпадне точно при плъзгане.
  Widget _verseBody(ReaderPalette palette, BibleRow row, String lang) {
    final titles = _titles[lang]?[row.verse];
    final text = _verseText(palette, row, lang);
    if (titles == null || titles.isEmpty) return text;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final t in titles)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              t,
              style: TextStyle(
                fontFamily: kTitleFamily,
                fontFamilyFallback: kTitleFallback,
                fontSize: BibleFontSize.value * 0.95,
                height: _kLineHeight,
                color: palette.wine,
              ),
            ),
          ),
        text,
      ],
    );
  }

  Widget _verseText(ReaderPalette palette, BibleRow row, String lang) {
    final verse = row[lang];
    final language = _languageOf(lang);
    final font = _fontFamiliesFor(language);
    final style = TextStyle(
      fontFamily: font.$1,
      fontFamilyFallback: font.$2,
      fontSize: BibleFontSize.value + (language?.sizeDelta ?? 0),
      // ⚠ Междуредието е ПО ПРЕВОД. Църковнославянските глифове носят свой
      // въздух и при общото 1.35 текстът се разрежда прекомерно — за кратък
      // надпис е хубаво, за цяло Писание не.
      height: _kLineHeight + (language?.lineDelta ?? 0),
      color: palette.ink,
    );

    // ⚠ НАДПИСАНИЕТО не е стих. Изписва се приглушено и в курсив, за да се
    // чете като заглавие — включително в преводите, чийто изворник изобщо не
    // го бележи (виж BibleRow.isHeading).
    final headingStyle = style.copyWith(
      color: palette.dim,
      fontStyle: FontStyle.italic,
    );

    final Widget body;
    if (row.isHeading && verse != null) {
      body = Text(verse.text, style: headingStyle, textAlign: TextAlign.start);
    } else if (verse == null) {
      // Празна клетка: този превод няма такъв стих. Редът пак се пази, за
      // да не се разместят съседните — виж alignChapter().
      body = Text('—',
          style: style.copyWith(color: palette.dim.withValues(alpha: .5)));
    } else if ((language?.rubricate ?? false) || _zachalaFor(lang, row) != null) {
      body = _rubricated(verse.text, style, palette, _zachalaFor(lang, row));
    } else {
      body = Text(verse.text, style: style, textAlign: TextAlign.start);
    }

    return language != null && language.isRtl
        ? Directionality(textDirection: TextDirection.rtl, child: body)
        : body;
  }

  /// Кой шрифт рисува даден превод: (семейство, резервен списък).
  ///
  /// Изборът е ДАННИ, не код — идва от `languages.font` в базата, тъй че нов
  /// превод не иска промяна тук.
  ///
  /// ⚠ ПРАЗНО поле значи СИСТЕМНИЯТ шрифт, и това е нарочен избор, не
  /// пропуск. Системният е по-компактен от Charis SIL, а стихът и без това
  /// губи ширина заради колонката с номера — на паралелен изглед двете
  /// колони са и без това тесни. Същото решение е взето и за дневния и
  /// месечния изглед (виж CLAUDE.md: „НЯМАТ зададен шрифт… нарочно е").
  /// Така стоят българският, руският, латинският, английският и сръбският.
  ///
  /// ⚠ РЕЗЕРВЪТ НЕ Е Charis SIL, а системният (тоест `null`). Това изглежда
  /// като пропуск, но е МЕРЕНО решение: срещу знаците в самата база Charis
  /// SIL се оказа ПО-БЕДЕН от системния за църковнославянски — няма нито
  /// `ꙋ` (34 717 срещания), нито `ѧ` (32 727), нито `ѡ` (27 826), нито
  /// титлата `҆` (103 876). Роботo ги има всичките.
  ///
  /// Сложи ли се Charis SIL за резерв, става по-лошо от липсата му: една и
  /// съща дума се рисува от ДВА шрифта наведнъж — основните букви от Charis,
  /// разширените от системния — и това се вижда с просто око.
  ///
  /// ⚠ Резервът работи САМО за шрифт, обявен в `pubspec.yaml` — иначе името
  /// се подминава МЪЛЧАЛИВО, без грешка (записано в CLAUDE.md). Затова
  /// `cslavonic`, `greek`, `hebrew` и `georgian` днес се свеждат до
  /// системния. Проверено на устройството: гръцкият, ивритът и грузинският
  /// излизат ПЪЛНИ така (0 липсващи знака срещу базата), а цс графиката —
  /// без един-единствен знак, `ᲂ` (U+1C82).
  (String?, List<String>?) _fontFamiliesFor(BibleLanguage? language) {
    final key = language?.font;
    if (key == null || key.isEmpty) return (null, null);
    final chain = _kFontFamilies[key];
    // Неописано условно име → системният шрифт, и то съзнателно, а не
    // защото Flutter е подминал нещо мълчаливо.
    if (chain == null || chain.isEmpty) return (null, null);
    return (chain.first, chain.length > 1 ? chain.sublist(1) : null);
  }

  GlobalKey _keyFor(String verse) =>
      _rowKeys.putIfAbsent(verse, () => GlobalKey());

  BibleLanguage? _languageOf(String code) {
    for (final l in _langs) {
      if (l.code == code) return l;
    }
    return null;
  }

  // ── Лентата ──────────────────────────────────────────────────────────

  /// Лентата с инструменти.
  ///
  /// ⚠ ВИЗУАЛНО ЕДНАКВА с другите два четеца, до подредбата и разстоянията.
  /// За човека това е ЕДИН четец; научи ли лентата веднъж, не бива всяка
  /// секция да го хвърля в непознати води. Оттам:
  ///   • стрелката „назад" е обикновен [BackButton] — БЕЗ кръгче, както е и
  ///     там (кръгчетата са запазени за действията вдясно);
  ///   • бутоните вдясно идват от общия `readerToolbarActions`, не се
  ///     нареждат тук наум;
  ///   • трите точки отварят СЪЩОТО меню (`kReaderMenuItems`), а не направо
  ///     настройките.
  ///
  /// Единствената разлика спрямо другите е изборът на превод — тя е заради
  /// функционалност, която само тази секция има.
  Widget _toolbar(ReaderPalette palette, bool landscape) {
    final book = _book;
    final pair = BibleLanguages.value;

    final actions = readerToolbarActions(
      context: context,
      onThemeToggle: () => setState(() => ReaderTheme.dark = !ReaderTheme.dark),
      onFontSmaller: () => _bumpFont(-BibleFontSize.step),
      onFontBigger: () => _bumpFont(BibleFontSize.step),
      fontValue: BibleFontSize.value,
      fontMin: BibleFontSize.min,
      fontMax: BibleFontSize.max,
      onMore: _showMoreMenu,
      // ⚠ Търсенето още го НЯМА — бутонът стои по изрична молба, за да е
      // лентата на мястото си от самото начало и да не се пренарежда, когато
      // функцията дойде. Дотогава показва къса бележка вместо да мълчи:
      // бутон, който не прави нищо и не казва нищо, се приема за счупен.
      onSearch: () => ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Търсенето в Писанието предстои.'),
          duration: Duration(seconds: 2),
        ),
      ),
    );

    // ⚠ В ЛЕГНАЛО двете менюта стоят В САМИЯ РЕД, всяко в своята половина —
    // а не в отделен слой върху лентата. Първият опит беше `Stack` с точната
    // геометрия на колоните отдолу; изглеждаше вярно на хартия, но слоят
    // ляга ВЪРХУ бутоните и надписите се застъпват с полумесеца и с минуса.
    // Точното подравняване с текста не си струва счупената лента.
    final bar = Row(
      children: [
        const BackButton(),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            book == null ? '' : '${book.abbr} ${widget.chapter}',
            // ⚠ СИСТЕМНИЯТ шрифт, не TamburinModern: лентата е управление,
            // не четиво, а Tamburin е за заглавия ВЪТРЕ в текста.
            style: const TextStyle(color: Colors.white, fontSize: 17),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (landscape) ...[
          // Всяко меню — към своята колона: лявото се долепя надясно в първата
          // половина, дясното започва отляво във втората.
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: _languageButton(pair, 0),
            ),
          ),
          const SizedBox(width: 25),
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: _languageButton(pair, 1),
            ),
          ),
        ] else ...[
          const SizedBox(width: 10),
          _languageButton(pair, null),
          const Spacer(),
        ],
        ...actions,
      ],
    );

    return SizedBox(height: kReaderToolbarHeight, child: bar);
  }

  /// Съседната глава — напред или назад, ПРЕЗ границите на книгите.
  ///
  /// ⚠ Прескача на съседната книга, вместо да спре в края: човек, който чете
  /// подред, не иска да се връща в съдържанието на всеки край на книга.
  /// Спира само в двата края на Завета. Книгите се обхождат по реда на
  /// самото Писание (`ord`), не по код или азбучно.
  (String, int)? _adjacentChapter(int direction) {
    final book = _book;
    if (book == null) return null;
    final target = widget.chapter + direction;
    if (target >= 1 && target <= book.chapters) return (book.code, target);

    final at = _allBooks.indexWhere((b) => b.code == book.code);
    if (at < 0) return null;
    final next = at + direction;
    if (next < 0 || next >= _allBooks.length) return null;
    final nb = _allBooks[next];
    return (nb.code, direction > 0 ? 1 : nb.chapters);
  }

  void _goToChapter((String, int) target) {
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => BibleReader(bookCode: target.$1, chapter: target.$2),
    ));
  }

  /// Опашката под четивото — ОБЩИЯТ [ReaderFooter], същият като в четеца на
  /// книги: същите бутони, същите надписи, същите разстояния.
  Widget _footer(ReaderPalette palette) {
    final prev = _adjacentChapter(-1);
    final next = _adjacentChapter(1);
    return ReaderFooter(
      color: palette.dim,
      left: prev == null
          ? null
          : FooterAction(
              icon: Icons.chevron_left,
              label: 'предишно',
              onTap: () => _goToChapter(prev),
            ),
      right: next == null
          ? null
          : FooterAction(
              icon: Icons.chevron_right,
              label: 'следващо',
              onTap: () => _goToChapter(next),
            ),
    );
  }

  /// СЪЩОТО меню като в другите два четеца — точките живеят в
  /// reader_more_menu.dart, за да не се разминат.
  Future<void> _showMoreMenu() async {
    final choice = await showReaderMoreMenu(context, items: kReaderMenuItems);
    if (!mounted || choice == null) return;
    if (choice == kReaderSettingsMenuItem.value) {
      _scaffoldKey.currentState?.openEndDrawer();
    }
  }

  /// Прилага избор от менюто върху превода, който е в полето.
  ///
  /// ⚠ Не ползва `BibleLanguages.setActiveCode`: то мени „активния", а тук
  /// целта може да е ДЯСНАТА колона в легнало положение, докато активният е
  /// левият. Затова се сменя изрично онази половина от двойката, която в
  /// момента е под фокус.
  ///
  /// ⚠ Избере ли се превод, който вече заема ДРУГАТА половина, двете се
  /// РАЗМЕНЯТ вместо да станат еднакви — инак плъзгането не води наникъде.
  void _pickLanguage(String code, String shown, BibleLanguagePair pair) {
    if (code == shown) return;
    final replacingFirst = shown == pair.first;
    if (code == (replacingFirst ? pair.second : pair.first)) {
      BibleLanguages.set(BibleLanguagePair(
        first: pair.second,
        second: pair.first,
        active: pair.active == 0 ? 1 : 0,
      ));
      return;
    }
    BibleLanguages.set(replacingFirst
        ? pair.copyWith(first: code)
        : pair.copyWith(second: code));
  }

  /// Кой превод стои в дадено меню.
  ///
  /// ⚠ В ИЗПРАВЕНО ([column] == null) следва ПЛЪЗГАНЕТО, а не запазения
  /// избор: докато пръстът дърпа, `_slide` е дробно и надписът трябва да се
  /// смени в мига, в който на екрана вече преобладава другият превод. Инак
  /// човек вижда „бг", а чете църковнославянски, докато не пусне.
  ///
  /// В ЛЕГНАЛО менютата са две и всяко си знае колоната.
  String _shownCode(BibleLanguagePair pair, int? column) {
    if (column != null) return column == 0 ? pair.first : pair.second;
    return _slide.value >= 0.5 ? pair.second : pair.first;
  }

  /// Падащото меню за превода — по искане на потребителя стои В ЛЕНТАТА, а
  /// не в настройките: смяната на езика е част от четенето, не нагласяване.
  ///
  /// Мени превода, който е в полето — виж [_shownCode].
  Widget _languageButton(BibleLanguagePair pair, int? column) {
    final shown = _shownCode(pair, column);
    final current = _languageOf(shown);
    return PopupMenuButton<String>(
      tooltip: 'Превод',
      color: AppColors.toolbar,
      onSelected: (code) => _pickLanguage(code, shown, pair),
      itemBuilder: (_) => [
        for (final l in _langs)
          PopupMenuItem<String>(
            value: l.code,
            child: Row(
              children: [
                Icon(
                  l.code == shown
                      ? Icons.radio_button_checked
                      : (l.code == pair.first || l.code == pair.second)
                          // Другата половина се вижда, че е заета — избере ли
                          // се, двата се разменят, вместо да станат еднакви.
                          ? Icons.swap_horiz
                          : Icons.radio_button_unchecked,
                  size: 18,
                  color: Colors.white70,
                ),
                const SizedBox(width: 10),
                // „бг · български" — съкращението води, защото след избора в
                // полето остава само то.
                SizedBox(
                  width: 30,
                  child: Text(l.abbr,
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 13)),
                ),
                Text(l.short, style: const TextStyle(color: Colors.white)),
              ],
            ),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ⚠ В полето остава САМО съкращението: пълното име изяжда
            // половината лента, а лентата трябва да побере и бутоните.
            Text(current?.abbr ?? '—',
                style: const TextStyle(color: Colors.white70, fontSize: 15)),
            const Icon(Icons.arrow_drop_down, color: Colors.white70, size: 18),
          ],
        ),
      ),
    );
  }
}
