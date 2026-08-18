// book_reader.dart
//
// Четецът на книги от „Месецослов". Чете глава по глава направо от .epub-а
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

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_html/flutter_html.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_theme.dart';
import 'book_image.dart';
import 'book_last_read_store.dart';
import 'book_position_store.dart';
import 'book_title_extension.dart';
import 'bookmarks.dart';
import 'bookmarks_all.dart';
import 'drop_cap.dart';
import 'epub_source.dart';
import 'external_link.dart';
import 'lives_index.dart';
import 'saint_expandable_tile.dart' show lookupBySlug;
import 'nudge_shake.dart';
import 'reader_font_size.dart';
import 'reader_footer.dart';
import 'reader_match_ticks.dart';
import 'pdf_export.dart';
import 'reader_more_menu.dart';
import 'reader_resume_prompt.dart';
import 'reader_regions.dart';
import 'text_line_locator.dart';
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

  /// Да ОСТАВИ ли системната лента скрита при излизане.
  ///
  /// Режимът важи за цялото приложение, не за екрана, тъй че четецът по
  /// подразбиране връща лентата — иначе календарът остава без нея. Но
  /// библиотеката („Месецослов") сама стои без лента: върне ли я четецът,
  /// тя я гаси веднага след него и се вижда премигване. Оттам и този флаг —
  /// по-добре да не се пали, отколкото да се гаси наново.
  final bool keepImmersiveOnExit;

  /// Да подсети ли, че оттук нататък се върви през съдържанието.
  ///
  /// Вдига се САМО от екрана за избор на книга: там човек тъкмо е отворил
  /// тома и стои на заглавната му страница, без да знае как се стига до
  /// житията. По другите пътища (отметка, връщане към прекъснато четене) той
  /// вече е насред четиво и подсещането би било досадно.
  final bool hintContents;

  const BookReader({
    super.key,
    required this.book,
    this.start,
    this.hintContents = false,
    this.keepImmersiveOnExit = false,
  });

  @override
  State<BookReader> createState() => _BookReaderState();
}

class _BookReaderState extends State<BookReader>
    with TickerProviderStateMixin {
  /// Последно отваряното четиво в ТОЗИ том — за текста на опашката под
  /// заглавната страница и за маркирането в съдържанието. null = томът не
  /// е отварян (или е отваряна само заглавната му страница).
  LastRead? _lastRead;

  /// Изчезването на СТАРОТО четиво — първата фаза на прехода.
  ///
  /// ⚠ Не е черен слой отгоре, а избледняване на самото съдържание. Черна
  /// пелена работи само в тъмна тема; в светла тя е рязко премигване. А
  /// щом трябва да е с цвета на фона, отделен слой изобщо не е нужен:
  /// избледнее ли текстът, фонът прозира сам — и в двете теми.
  ///
  /// ⚠ Лентата с инструментите НЕ се засяга. Сменя се четивото, не
  /// екранът; лента, която мига заедно с текста, изглежда като
  /// презареждане на целия изглед.
  ///
  /// Двуфазно е, защото инак двете глави трябва да съществуват
  /// едновременно — две пълни жития в паметта и двойно оформление на
  /// всеки кадър.
  late final AnimationController _veil;

  /// Влизането на новото: плъзгане настрани плюс избледняване.
  late final AnimationController _enter;
  bool _enterFromRight = true;

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
  /// Абсолютното отместване в скрола на всяко съвпадение (виж
  /// _recomputeHitYs). Заменя предишните съотношения спрямо дължината.
  List<double> _hitYs = const [];

  int _total = 0;
  int _currentHit = -1;

  // ── Докъде е стигнал читателят ──────────────────────────────────────
  //
  // Позицията се пази при СПИРАНЕ на плъзгането, не при всяко движение —
  // иначе всеки ред би бил запис на диска.
  /// По един ключ на регион — оттам идва реалната геометрия за точното
  /// позициониране (виж reader_regions.dart и text_line_locator.dart).
  List<GlobalKey> _regionKeys = [];

  /// Кутията с ЦЯЛОТО съдържание на главата. Спрямо нея се смятат
  /// съотношенията за чертичките — не спрямо скрола, защото в неговото
  /// пространство влиза и лентата отгоре (при търсене тя е закована и не се
  /// превърта, тъй че чертичките излизаха изместени).
  final GlobalKey _contentKey = GlobalKey();

  /// Кутията с буквицата — питаме я на кой пиксел стои даден знак.
  final GlobalKey<DropCapParagraphState> _dropCapKey =
      GlobalKey<DropCapParagraphState>();

  /// Уловен в didChangeDependencies: в dispose() context вече не е сигурен
  /// за нови lookup-и, а SnackBar-ът трябва да се прибере точно тогава.
  ScaffoldMessengerState? _scaffoldMessenger;

  Timer? _positionTimer;
  BookPosition? _saved;
  bool _promptShown = false;

  /// Има ли отметка в тази книга.
  ///
  /// Моделът е като в четеца на жития: отметката не е точка, а СПЪТНИК —
  /// сложиш ли я веднъж, тя те следва, докато четеш, и следващия път ти
  /// предлага да се върнеш там. Без отметка нищо не се пази.
  bool _isBookmarked = false;

  /// Последно ЗАПАЗЕНАТА позиция, пазена в паметта. Сравняваме с нея, за да
  /// пропускаме излишни записи: телефон, който лежи неподвижен, или дребно
  /// поклащане в рамките на същия екран, не бива да удрят диска.
  int? _savedChapter;
  double? _savedOffset;
  int _savedRegion = -1;
  int _savedChar = 0;

  /// Докато подканата за връщане стои на екрана, НЕ пишем нищо: иначе
  /// плъзгането зад нея би презаписало точно позицията, която тя предлага.
  bool _awaitingDecision = false;

  // ── Подсещането за съдържанието ─────────────────────────────────────
  //
  // Отвори ли се том от библиотеката, човек стои на заглавната страница —
  // красива, но задънена: нататък се върви само през съдържанието. Затова
  // иконката му се поклаща (виж nudge_shake.dart) по ДВА бъмпа наведнъж,
  // три серии през 5 секунди, и толкова. Подсещане, което не спира само,
  // престава да е подсещане и става натрапване.
  late final AnimationController _nudge =
      AnimationController(vsync: this, duration: kNudgeBump)
        ..addStatusListener(_onNudgeBumpEnd);
  Timer? _nudgeTimer;

  /// Колко бъмпа още се дължат в текущата серия.
  int _nudgeLeft = 0;

  /// Колко серии са изиграни. При 3 подсещането е приключило завинаги.
  int _nudgeRounds = 0;

  static const int _nudgeRoundCount = 3;
  static const int _nudgeBumpsPerRound = 2;
  static const Duration _nudgeGap = Duration(seconds: 5);

  /// Колко се чака ПРЕДИ първата серия. Страницата тъкмо се е появила и окото
  /// още обхожда заглавието и орнамента — движение точно в този миг остава
  /// незабелязано. Две секунди по-късно погледът вече е свободен.
  static const Duration _nudgeDelay = Duration(seconds: 2);

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
    // Пелената пада бързо (240) и се вдига по-бавно (420) — както при
    // отварянето на том: тръгването е жест на човека и трябва да отговори
    // веднага, а пристигането е нарочно по-спокойно.
    _veil = AnimationController(
      duration: const Duration(milliseconds: 240),
      reverseDuration: const Duration(milliseconds: 420),
      vsync: this,
    );
    // Плъзгането върви заедно с вдигането на пелената.
    _enter = AnimationController(
      duration: const Duration(milliseconds: 460),
      vsync: this,
      value: 1, // първата глава е вече „влязла" — не се анимира отварянето
    );
    // Темата и размерът се четат заедно — за човека това е един
    // четец и настройките му са общи (виж ReaderTheme.loadOnce).
    ReaderTheme.loadOnce().then((_) {
      if (mounted) setState(() {});
    });
    ReaderFontSize.loadOnce().then((_) {
      if (mounted) setState(() {});
    });
    // Кое четиво е било последно в този том — решава какво пише опашката
    // под заглавната страница и кой ред е маркиран в съдържанието.
    BookLastReadStore.load(widget.book.assetPath).then((v) {
      if (mounted) setState(() => _lastRead = v);
    });
    // Влизането направо в житие (от отметка или от кръстосана препратка)
    // също е отваряне и трябва да се запомни.
    if (_index > 0) _rememberLastRead();

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
    _scroll.addListener(_rememberPosition);
    _loadSavedPosition();

    if (widget.hintContents) _startNudge();
  }

  /// Пуска трите серии — първата след кратко изчакване (виж [_nudgeDelay]),
  /// следващите през [_nudgeGap]. Двата таймера делят едно поле, тъй че
  /// спирането е едно и също, независимо докъде е стигнало подсещането.
  void _startNudge() {
    _nudgeTimer = Timer(_nudgeDelay, () {
      if (!mounted) return;
      _nudgeRound();
      _nudgeTimer = Timer.periodic(_nudgeGap, (t) {
        if (!mounted || _nudgeRounds >= _nudgeRoundCount) {
          t.cancel();
          return;
        }
        _nudgeRound();
      });
    });
  }

  void _nudgeRound() {
    _nudgeRounds++;
    _nudgeLeft = _nudgeBumpsPerRound;
    _nudge.forward(from: 0);
  }

  /// Вторият бъмп в серията се пуска чак когато първият е свършил — иначе
  /// двата се сливат в едно по-дълго поклащане вместо в две подсещания.
  void _onNudgeBumpEnd(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    if (--_nudgeLeft > 0) _nudge.forward(from: 0);
  }

  /// Спира подсещането завинаги. Вика се при всяко докосване по лентата с
  /// инструменти: пипне ли човек там, той вече е разбрал къде да гледа —
  /// няма значение кое точно копче е натиснал.
  void _stopNudge() {
    // Без подсещане няма и какво да се спира — а достъпът до _nudge тук би
    // създал контролер за нищо (полето е late).
    if (!widget.hintContents) return;
    if (_nudgeTimer == null && _nudgeRounds >= _nudgeRoundCount) return;
    _nudgeTimer?.cancel();
    _nudgeTimer = null;
    _nudgeRounds = _nudgeRoundCount;
    _nudgeLeft = 0;
    _nudge.stop();
    _nudge.value = 0;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scaffoldMessenger = ScaffoldMessenger.of(context);
  }

  @override
  void dispose() {
    ReaderFontSize.flush();
    ReaderTheme.flush();
    // Прибираме евентуален висящ SnackBar веднага — ScaffoldMessenger е ОБЩ
    // за приложението, не локален за екрана, тъй че иначе съобщението остава
    // да виси и върху екрана, към който се връщаме.
    _scaffoldMessenger?.removeCurrentSnackBar();
    _positionTimer?.cancel();
    _nudgeTimer?.cancel();
    _enter.dispose();
    _veil.dispose();
    if (widget.hintContents) _nudge.dispose();
    _tocSlide.dispose();
    // НЕ пишем позиция при излизане — нарочно, както в четеца на жития.
    // Ако човек отвори книгата, види подканата за връщане и веднага излезе,
    // записът тук би презаписал точно позицията, която подканата предлага.
    // Пази се единствено по пътя „3 секунди покой на скрола".
    _scroll.removeListener(_rememberPosition);
    _scroll.dispose();
    // ЗАДЪЛЖИТЕЛНО: режимът важи за цялото приложение, не за екрана. Без
    // това календарът остава без системна лента, след като човек затвори
    // книгата. Изключение — екраните, които сами стоят без лента (виж
    // keepImmersiveOnExit): там паленето би било само едно премигване,
    // защото те я гасят веднага след нас.
    if (!widget.keepImmersiveOnExit) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual,
          overlays: SystemUiOverlay.values);
    }
    super.dispose();
  }

  EpubTocEntry get _current => _chapters[_index];

  Future<void> _goTo(int i) async {
    if (i < 0 || i >= _chapters.length) return;
    // Посоката на влизане: напред — новото идва отдясно, назад — отляво.
    // Пелената сама по себе си не я носи (всяка смяна изглежда еднакво),
    // затова плъзгането върви заедно с нея.
    _enterFromRight = i > _index;

    // Фаза 1: пелената пада. Смяната става зад нея.
    await _veil.forward(from: 0);
    if (!mounted) return;

    _positionTimer?.cancel();
    // Излезем ли от заглавната страница, подсещането е излишно — човекът
    // вече е намерил пътя навътре в тома.
    _stopNudge();
    setState(() {
      _index = i;
      // Отметката е на ниво ЖИТИЕ. Новата глава е ново четиво: бутонът
      // изгасва, а състоянието се чете наново за нея. Без това нулиране
      // бутонът светеше и в жития, които човек не е отбелязвал, а първото
      // спиране на скрола записваше позиция в тях.
      _isBookmarked = false;
      _savedChapter = null;
      _savedOffset = null;
      _saved = null;
      _promptShown = false;
      _awaitingDecision = false;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
    _loadSavedPosition();
    _rememberLastRead();

    // Фаза 2: пелената се вдига, новото се плъзга навътре. Двете вървят
    // заедно — иначе се вижда първо гола смяна, после движение.
    _enter.forward(from: 0);
    _veil.reverse();

    // ⚠ Търсенето НЕ се затваря при смяна на четиво — нарочно: така човек
    // обхожда книгата по един и същ критерий, четиво по четиво. Но затова
    // трябва да се ПРЕСМЕТНЕ наново за новата глава. Дотогава оставаше с
    // числата на старата: броячът показваше стар брой, чертичките сочеха
    // никъде, а в новия текст нищо не светеше.
    //
    // `_runSearch` е точно това, което трябва — брои по регионите на
    // ТЕКУЩАТА глава и сам отлага геометрията за следващия кадър.
    if (_searchOpen && _searchCtrl.text.trim().isNotEmpty) {
      _runSearch(_searchCtrl.text);
    }
  }

  /// Запомня кое четиво е отворено — за опашката на заглавната страница и
  /// за маркирането в съдържанието.
  ///
  /// ⚠ НЕЗАВИСИМО от отметките: пише се при всяко отваряне на житие, дори
  /// човек да не е отбелязал нищо. Затова не минава през
  /// BookPositionStore, който записва само отбелязаните.
  /// Заглавната страница (индекс 0) се пропуска в самия store.
  void _rememberLastRead() {
    if (_index <= 0) return;
    final e = _chapters[_index];
    BookLastReadStore.save(
      widget.book.assetPath,
      LastRead(chapter: _index, href: e.href, title: e.title),
    );
    _lastRead = LastRead(chapter: _index, href: e.href, title: e.title);
  }

  /// Отваря житието с този номер. Връща false, ако го няма в указателя.
  ///
  /// Ако е в СЪЩИЯ том — просто смяна на глава. Ако е в друг (почти винаги
  /// така), се отваря нов четец върху него; „назад" връща тук, на същото
  /// място, защото текущият екран не се затваря.
  Future<bool> _openLife(String num) async {
    final index = await LivesIndex.load();
    final ref = index[num];
    if (ref == null) return false;

    if (widget.book.assetPath.endsWith(ref.book)) {
      final i = _chapters.indexWhere((e) => e.href == ref.href);
      if (i >= 0) {
        _goTo(i);
        return true;
      }
      return false;
    }

    final book = await EpubBook.open('assets/books/${ref.book}');
    final entry = book.toc
        .expand((e) => e.flattened())
        .where((e) => e.href == ref.href)
        .firstOrNull;
    if (entry == null || !mounted) return false;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => BookReader(book: book, start: entry),
    ));
    return true;
  }

  Future<void> _onLinkTap(String? url) async {
    if (url == null) return;

    // Външните препратки (библейските към azbyka.ru) водят навън — с питане
    // и с разкодиран адрес; виж external_link.dart защо и двете са нужни.
    if (url.startsWith('http')) {
      if (mounted) await openExternal(context, url);
      return;
    }

    // Кръстосана препратка към друго житие („../zhitija-svjatykh/1143").
    // Числото е номерът на статията в azbyka.ru и по него указателят
    // намира главата — почти винаги в ДРУГ том (виж lives_index.dart).
    final num = LivesIndex.numberOf(url.split('#').first);
    if (num != null) {
      if (await _openLife(num)) return;
      // Няма съответствие у нас — тогава навън, към сайта, вместо да
      // мълчим. (Днес такива няма нито една, но томовете се менят.)
      if (mounted) {
        await openExternal(context,
            'https://azbyka.ru/otechnik/Dmitrij_Rostovskij/'
            'zhitija-svjatykh/$num');
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
      builder: (_) => _NoteSheet(
          html: body, palette: palette, extensions: _htmlExtensions),
    );
  }

  // ── Докъде е стигнал читателят ──────────────────────────────────────

  /// Отлага записа: пише се едва след като плъзгането спре. Без това всеки
  /// ред би бил обръщение към диска.
  void _rememberPosition() {
    if (!_isBookmarked || _awaitingDecision) return;
    _positionTimer?.cancel();
    // Три секунди покой — както в четеца на жития. Пише се при СПИРАНЕ на
    // плъзгането, не по време на него.
    _positionTimer = Timer(const Duration(seconds: 3), _saveIfStillIdle);
  }

  void _saveIfStillIdle() {
    if (!mounted || !_isBookmarked || _awaitingDecision) return;
    if (!_scroll.hasClients) return;
    // Ако нищо не се е променило спрямо последно запазеното, пропускаме
    // записа. Сравнява се РЕДЪТ (абзац + знак), не пикселът: дребно
    // поклащане в рамките на същия ред не е нова позиция.
    final at = _topmostLine();
    if (_index == _savedChapter &&
        at != null &&
        at.$1 == _savedRegion &&
        at.$2 == _savedChar) {
      return;
    }
    _writePosition();
  }

  void _writePosition() {
    if (!_scroll.hasClients) return;
    _savedChapter = _index;
    _savedOffset = _scroll.offset;
    // Пази се ЗНАК, не пиксел: пикселът зависи от размера на шрифта и
    // записан днес, утре сочи другаде. Виж BookPosition.
    final at = _topmostLine();
    _savedRegion = at?.$1 ?? -1;
    _savedChar = at?.$2 ?? 0;
    BookPositionStore.save(
      widget.book.assetPath,
      _current.href,
      BookPosition(
        chapter: _index,
        offset: _scroll.offset,
        region: _savedRegion,
        charInRegion: _savedChar,
        chapterTitle: _current.title,
        parentTitle: _dayTitleOf(_current),
        savedAtMs: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  /// Чете запазената позиция за ТЕКУЩАТА глава и, ако има такава, предлага
  /// връщане към нея.
  Future<void> _loadSavedPosition() async {
    // Записът се търси за ГЛАВАТА, която е отворена в момента — отметките
    // са на ниво житие (виж BookPositionStore).
    final href = _current.href;
    final pos = await BookPositionStore.load(widget.book.assetPath, href);
    // Стария общокнижен запис го чистим пътьом, веднъж.
    BookPositionStore.clearLegacy(widget.book.assetPath);
    if (!mounted || pos == null) return;
    // Главата се е сменила, докато четяхме от диска.
    if (_current.href != href) return;
    setState(() {
      _saved = pos;
      _isBookmarked = true;
      _savedChapter = pos.chapter;
      _savedOffset = pos.offset;
      _savedRegion = pos.region;
      _savedChar = pos.charInRegion;
      // Докато подканата стои, плъзгането зад нея не бива да презаписва
      // позицията, която тя предлага.
      _awaitingDecision = true;
    });
  }

  Future<void> _toggleBookmark() async {
    if (_isBookmarked) {
      await BookPositionStore.clear(widget.book.assetPath, _current.href);
      _positionTimer?.cancel();
      if (!mounted) return;
      setState(() {
        _isBookmarked = false;
        _savedChapter = null;
        _savedOffset = null;
        _savedRegion = -1;
        _savedChar = 0;
        _saved = null;
        _promptShown = true;
        _awaitingDecision = false;
      });
    } else {
      if (!mounted) return;
      setState(() {
        _isBookmarked = true;
        _promptShown = true;
        _awaitingDecision = false;
      });
      _writePosition();
      _showBookmarkEnabledSnackbar();
    }
  }

  void _showBookmarkEnabledSnackbar() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Последната ви позиция в книгата ще се запазва регулярно, '
          'докато бутонът за отметка остава включен.',
          style: TextStyle(fontSize: 18),
        ),
        duration: Duration(seconds: 10),
      ),
    );
  }

  void _jumpToSaved() {
    final pos = _saved;
    if (pos == null) return;
    setState(() {
      // Главата НЕ се сменя: записът е намерен по нейния ключ, тъй че
      // подканата връща само на мястото в текущото четиво. (Полето
      // `chapter` в записа остава като справка, но не води.)
      _promptShown = true;
      _saved = null;
      _awaitingDecision = false;
    });
    // Скролът получава позицията чак след като главата се построи.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final position = _scroll.position;
      // Новите записи носят абзац и знак — редът се смята сега, при
      // текущия размер на шрифта, и застава най-горе. Старите носят само
      // пиксел и се ползват както преди.
      if (pos.region >= 0 && pos.region < _regionKeys.length) {
        final ctx = _regionKeys[pos.region].currentContext;
        final box = ctx?.findRenderObject() as RenderBox?;
        final line = box == null
            ? null
            : _lineForChar(
                _currentRegions(), pos.region, pos.charInRegion, box.size.width);
        if (box != null && line != null) {
          final target = RenderAbstractViewport.of(box)
              .getOffsetToReveal(
                box,
                0.0,
                rect: Rect.fromLTWH(0, line.$1, box.size.width, line.$2),
              )
              .offset;
          _scroll.jumpTo(
              target.clamp(position.minScrollExtent, position.maxScrollExtent));
          return;
        }
      }
      _scroll.jumpTo(pos.offset.clamp(0.0, position.maxScrollExtent));
    });
  }

  // ── Търсене ─────────────────────────────────────────────────────────

  void _toggleSearch() {
    // ⚠ На ЗАГЛАВНАТА страница лупата прави друго: отваря съдържанието с
    // готов за писане курсор. Търсене в текста там е безсмислено — тя е
    // орнамент, заглавие и месец, няма какво да се намери. А най-близкото
    // полезно е да се търси житие по заглавие.
    //
    // Двете копчета остават различни: съдържанието само отваря списъка,
    // лупата отваря същия списък и вика клавиатурата.
    if (_index == 0) {
      _showToc(focusSearch: true);
      return;
    }
    setState(() {
      _searchOpen = !_searchOpen;
      if (!_searchOpen) {
        _searchCtrl.clear();
        _query = '';
        _hitYs = const [];
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
    // Броим ПО РЕГИОНИ, със същата сметка, с която се и маркира (виж
    // _chapterBody). Дотук се броеше по слепения текст на цялата глава — а
    // там съвпадение можеше да „прескочи" границата между два абзаца и да
    // се появи номер, който маркирането не рисува никъде.
    final regions = _currentRegions();
    var total = 0;
    for (final r in regions) {
      total += _countIn(r.content, q) + _countIn(r.second, q);
    }
    setState(() {
      _query = q;
      _total = total;
      _currentHit = total == 0 ? -1 : 0;
      _hitYs = const [];
    });
    // Позициите искат построена геометрия — смятат се след кадъра.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _recomputeHitYs();
      if (_total > 0) _scrollToHit(0);
    });
  }

  /// Регионите на текущата глава — същото деление, което рисува build().
  List<ReaderRegion> _currentRegions() {
    final body = _normalize(widget.book.readFile(_current.href) ?? '');
    final (beforeHtml, dropCap, firstP, afterHtml) = splitDropCap(body);
    return computeRegions(beforeHtml, dropCap, firstP, afterHtml);
  }

  int _countIn(String html, String foldedQuery) {
    if (foldedQuery.isEmpty || html.isEmpty) return 0;
    final folded = fold(_plainOf(html));
    var n = 0, from = 0;
    while (true) {
      final at = folded.text.indexOf(foldedQuery, from);
      if (at < 0) break;
      n++;
      from = at + foldedQuery.length;
    }
    return n;
  }

  /// Абсолютното отместване (в скрола) на всяко съвпадение.
  ///
  /// По РЕАЛНАТА геометрия на построените региони плюс реда вътре в тях —
  /// същото, което прави четецът на жития. Дотук тук се смяташе
  /// „съотношение × maxScrollExtent", което приема, че всички редове са
  /// еднакво високи: заглавия, полета между абзаците и буквицата го
  /// разместваха.
  void _recomputeHitYs() {
    if (_query.isEmpty || !_scroll.hasClients) {
      _hitYs = const [];
      return;
    }
    final regions = _currentRegions();
    final ys = <double>[];
    for (int i = 0; i < regions.length && i < _regionKeys.length; i++) {
      final r = regions[i];
      final count = _countIn(r.content, _query) + _countIn(r.second, _query);
      if (count == 0) continue;
      final ctx = _regionKeys[i].currentContext;
      final box = ctx?.findRenderObject() as RenderBox?;
      if (box == null) {
        for (var k = 0; k < count; k++) {
          ys.add(0);
        }
        continue;
      }
      // Две различни неща от една мярка:
      //   • за СКРОЛА — абсолютно отместване (виж getOffsetToReveal);
      //   • за ЧЕРТИЧКИТЕ — къде е това вътре в съдържанието, 0..1.
      final top =
          RenderAbstractViewport.of(box).getOffsetToReveal(box, 0.0).offset;
      for (int k = 0; k < count; k++) {
        final line = _lineOfMatch(regions, i, k, box.size.width);
        final dy = line?.$1 ?? 0;
        final y = top + dy;
        ys.add(y);
      }
    }
    if (mounted) setState(() => _hitYs = ys);
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

  /// Отместването и височината на реда с k-тото съвпадение в региона [i].
  (double, double)? _lineOfMatch(
      List<ReaderRegion> regions, int i, int k, double width) {
    if (width <= 0 || i < 0 || i >= regions.length) return null;
    final r = regions[i];
    final lineH = ReaderFontSize.value * kReaderLineHeight;

    if (!r.isHtml) {
      final state = _dropCapKey.currentState;
      if (state == null) return null;
      final starts = matchStartsOf(_plainOf(r.content), _query);
      if (k < starts.length) {
        final dy = state.dyForChar(starts[k]);
        return dy == null ? null : (dy, lineH);
      }
      final starts2 = matchStartsOf(_plainOf(r.second), _query);
      final k2 = k - starts.length;
      if (k2 >= starts2.length) return null;
      final dy = state.dyForCharInSecond(starts2[k2]);
      return dy == null ? null : (dy, lineH);
    }

    final (base, topMargin) = _measureStyleFor(r.content);
    final locator =
        LineLocator.forHtml(html: r.content, base: base, maxWidth: width);
    try {
      final at = locator.charOfMatch(_query, k);
      if (at == null) return null;
      return (
        topMargin + locator.dyForChar(at),
        locator.lineHeightForChar(at),
      );
    } finally {
      locator.dispose();
    }
  }

  /// Отместването и височината на реда със знак [charInRegion] от региона
  /// [i]. Общо за отметките и (през _lineOfMatch) за търсенето.
  (double, double)? _lineForChar(
      List<ReaderRegion> regions, int i, int charInRegion, double width) {
    if (width <= 0 || i < 0 || i >= regions.length) return null;
    final r = regions[i];
    final lineH = ReaderFontSize.value * kReaderLineHeight;
    if (!r.isHtml) {
      final dy = _dropCapKey.currentState?.dyForChar(charInRegion);
      return dy == null ? null : (dy, lineH);
    }
    final (base, topMargin) = _measureStyleFor(r.content);
    final locator =
        LineLocator.forHtml(html: r.content, base: base, maxWidth: width);
    try {
      return (
        topMargin + locator.dyForChar(charInRegion),
        locator.lineHeightForChar(charInRegion),
      );
    } finally {
      locator.dispose();
    }
  }

  /// Кой знак стои на пиксел [dy] в региона [i] — обратното на [_lineForChar].
  int? _charAtDyInRegion(
      List<ReaderRegion> regions, int i, double dy, double width) {
    if (width <= 0 || i < 0 || i >= regions.length) return null;
    final r = regions[i];
    if (!r.isHtml) return _dropCapKey.currentState?.charAtDy(dy);
    final (base, topMargin) = _measureStyleFor(r.content);
    final locator =
        LineLocator.forHtml(html: r.content, base: base, maxWidth: width);
    try {
      return locator.charAtDy(dy - topMargin);
    } finally {
      locator.dispose();
    }
  }

  /// Денят, под който стои това четиво в съдържанието.
  ///
  /// Съдържанието на томовете е двуетажно: ден → жития в него. Записът
  /// пази и двете, защото само заглавието на житието не казва кога се чете,
  /// а само денят не казва кое от четивата му е било отворено.
  String _dayTitleOf(EpubTocEntry entry) {
    for (final day in widget.book.toc) {
      if (day.children.isEmpty) continue;
      if (day.title == entry.title) return '';  // самият ден е отворен
      for (final child in day.children) {
        if (child.href == entry.href && child.anchor == entry.anchor) {
          return day.title;
        }
      }
    }
    return '';
  }

  /// (абзац, знак) на най-горния видим ред — това записва отметката.
  (int, int)? _topmostLine() {
    if (!_scroll.hasClients) return null;
    final regions = _currentRegions();
    final pixels = _scroll.position.pixels;
    for (int i = 0; i < regions.length && i < _regionKeys.length; i++) {
      final ctx = _regionKeys[i].currentContext;
      final box = ctx?.findRenderObject() as RenderBox?;
      if (box == null) continue;
      final top =
          RenderAbstractViewport.of(box).getOffsetToReveal(box, 0.0).offset;
      if (top + box.size.height <= pixels) continue; // изцяло над екрана
      final dy = pixels - top;
      if (dy < 0) return (i, 0);
      return (i, _charAtDyInRegion(regions, i, dy, box.size.width) ?? 0);
    }
    return null;
  }

  /// Стилът и горното поле, с които се РИСВА даден регион — мерещият
  /// трябва да е огледален на рисуващия (виж същото в reader_screen).
  (TextStyle, double) _measureStyleFor(String html) {
    final size = ReaderFontSize.value;
    final head = html.trimLeft();
    if (head.startsWith('<h3')) {
      return (
        TextStyle(fontFamily: kTitleFamily,
      fontFamilyFallback: kTitleFallback, fontSize: size + 12, height: 1.05),
        18.0,
      );
    }
    if (head.contains('class="memorydate"')) {
      return (
        TextStyle(
          fontFamily: kBodyFamily,
          fontSize: size - 1,
          height: kReaderLineHeight,
          fontStyle: FontStyle.italic,
        ),
        2.0,
      );
    }
    return (
      TextStyle(
        fontFamily: kBodyFamily,
        fontSize: size,
        height: kReaderLineHeight,
      ),
      8.0,
    );
  }

  /// Къде да легне чертичката: „място в текста / цялата дължина" — същата
  /// сметка като в четеца на жития (_allMatchRatios там).
  ///
  /// Палецът представя ЦЕЛИЯ екран, тъй че мястото на чертичката ВЪТРЕ в
  /// него казва къде на екрана стои намереното — горе, по средата или долу.
  /// Това е показание на уред, не украса.
  ///
  /// И излиза от сметка, не от нагласяне. Искаме
  /// `tick(Y) = палецГоре(o) + ((Y − o) / екран) × палец`. Заместим ли
  /// `палецГоре(o) = (o / maxScroll) × (път − палец)` и
  /// `палец = път × екран / съдържание`, членовете с текущата позиция `o`
  /// се съкращават напълно и остава `Y / съдържание`.
  ///
  /// ⚠ Всяко „подобрение" тук (изваждане на подравняването, поправки с
  /// дължината на палеца) РАЗВАЛЯ: залепва чертичката за единия му край.
  /// Разминаването, което гонехме, идваше от друго — лентата с чертичките
  /// беше ИЗВЪН SafeArea, а скролът вътре в нея.
  double _tickRatioFor(double matchY) {
    final p = _scroll.position;
    final content = p.maxScrollExtent + p.viewportDimension;
    if (content <= 0) return 0;
    return (matchY / content).clamp(0.0, 1.0);
  }

  /// Отстъпът отгоре на лентата с чертичките: лентата с инструменти (44)
  /// плюс тази за търсене (58) плюс луфта на скролбара.
  static const double _ticksLaneTop = 44 + 58 + 4;

  /// Колко от височината на екрана да остане НАД намереното.
  static const double _hitAlignment = 0.30;

  void _scrollToHit(int i) {
    if (i < 0 || !_scroll.hasClients) return;
    if (i >= _hitYs.length) return;
    final position = _scroll.position;
    final target = (_hitYs[i] - position.viewportDimension * _hitAlignment)
        .clamp(position.minScrollExtent, position.maxScrollExtent);
    if ((position.pixels - target).abs() < 8) return;
    _scroll.animateTo(target,
        duration: const Duration(milliseconds: 280), curve: Curves.easeOut);
  }

  void _stepHit(int delta) {
    if (_total == 0) return;
    setState(() => _currentHit = (_currentHit + delta + _total) % _total);
    _scrollToHit(_currentHit);
  }

  Future<void> _showMoreMenu() async {
    // СЪЩОТО меню като в четеца на жития — точките живеят в
    // reader_more_menu.dart (kReaderMenuItems), за да не се разминат.
    final choice = await showReaderMoreMenu(context, items: kReaderMenuItems);
    if (!mounted || choice == null) return;
    if (choice == kBookmarksMenuItem.value) {
      // Един и същи списък: там са и отметките от житията, и тукашните.
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => BookmarksListScreen(
          load: () => allBookmarkEntries(lookupBySlug),
        ),
      ));
    } else if (choice == kSharePdfMenuItem.value) {
      _shareAsPdf();
    }
  }

  /// Изнася ТЕКУЩАТА глава като PDF и отваря диалога за споделяне.
  ///
  /// Оформлението е същото като при житията — един и същ `pdf_export.dart`
  /// върху един и същ HTML, тъй че изнесеният файл изглежда като четивото.
  ///
  /// ⚠ Заглавието НЕ се подава отделно. В книгите то е вътре в главата
  /// (`<h1>` → `<h3>` след _normalize), а `sharePdf` го разпознава по
  /// `hasOwnTitle` и пропуска своето — инак излизат две заглавия едно под
  /// друго. При житията е обратното: там името идва отвън.
  Future<void> _shareAsPdf() async {
    final raw = widget.book.readFile(_current.href);
    if (raw == null) return;
    await shareReaderPdf(
      context,
      title: _current.title,
      bodyHtml: _chapterHtml(raw),
      fileName: '${_fileSafe(_current.title)}.pdf',
      // Главите започват с буквица, както житията.
      withDropCap: true,
    );
  }

  /// Име за файл от заглавие на глава: без знаци, които някои файлови
  /// системи и приложения за споделяне не приемат.
  static String _fileSafe(String s) =>
      s.replaceAll(RegExp(r'[\\/:*?"<>|]'), ' ').trim();

  // ── Съдържанието ────────────────────────────────────────────────────────

  /// Плъзгането на панела със съдържанието.
  ///
  /// Собствен контролер, защото подразбиращият се на `showModalBottomSheet`
  /// е 250 ms навън и 200 ms навътре — при панел, висок колкото екрана, това
  /// е толкова бързо, че прибирането не се вижда като движение, а като
  /// премигване. Особено при прекъснат жест: дръпнеш ли надолу и пуснеш по
  /// средата, панелът просто изчезва.
  ///
  /// Кривите остават тези на BottomSheet — тук се разтяга само времето.
  late final AnimationController _tocSlide = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
    reverseDuration: const Duration(milliseconds: 360),
  );

  /// [focusSearch] отваря панела с курсор в полето за търсене (лупата на
  /// заглавната страница — виж [_toggleSearch]). Плъзгането до маркирания
  /// ред се прави и тогава: при първия въведен знак обхождането само ще
  /// отведе другаде, а дотогава няма причина списъкът да стои на началото.
  Future<void> _showToc({bool focusSearch = false}) async {
    final palette = ReaderTheme.palette;
    final chosen = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      transitionAnimationController: _tocSlide,
      backgroundColor: palette.bg,
      builder: (_) => _TocSheet(
        toc: widget.book.toc,
        chapters: _chapters,
        // ⚠ От ЗАГЛАВНАТА страница се маркира последно четеното житие, а
        // не самата тя. Дотогава маркиран стоеше най-горният ред — тоест
        // заглавната, — което не казваше нищо: човек и без това идва
        // оттам. Така съдържанието помни вместо него.
        current: _index == 0 ? (_lastRead?.chapter ?? 0) : _index,
        palette: palette,
        autofocusSearch: focusSearch,
      ),
    );
    if (chosen != null) _goTo(chosen);
  }

  @override
  Widget build(BuildContext context) {
    final palette = ReaderTheme.palette;
    final raw = widget.book.readFile(_current.href);

    return Scaffold(
      // Фонът на СКЕЛЕТА е цветът на инструментите, а не на четеца — под
      // него остава само ивицата на системната лента (виж SafeArea долу).
      // Така тя стои еднакво тъмна и в светла тема, вместо да светне
      // кремава заедно със страницата. Точно както в четеца на жития.
      backgroundColor: AppColors.toolbar,
      body: SafeArea(
        bottom: false,
        // Лентата се ПРИБИРА при плъзгане надолу и се връща при плъзгане
        // нагоре — същото поведение като в четеца на жития (SliverAppBar с
        // floating+snap, без pinned). При четене на дълъг текст всеки
        // изгубен ред се усеща.
        child: Container(
          // Фонът на СТРАНИЦАТА — вътре в SafeArea, за да не покрие ивицата
          // на системната лента (тя остава с цвета на инструментите).
          color: palette.bg,
          // ПРИ ТЪРСЕНЕ лентата излиза ИЗВЪН скролируемото и застава като
          // обикновен AppBar в Column — както в четеца на жития.
          //
          // Не е подредба заради подредбата: докато лентата е sliver вътре
          // в скрола, пътят на палеца започва от самия връх на екрана и
          // палецът навлиза зад полето за търсене. Изнесена, тя отрязва
          // изгледа и палецът тръгва изпод нея — оттам и чертичките лягат
          // точно срещу него.
          // Чертичките и подканата стоят НАД скрола, затова е Stack — и
          // ВЪТРЕ в SafeArea, за да мерят от същото начало като него.
          // Отвън координатите им се разминават с височината на системната
          // ивица и разминаването расте надолу.
          child: Stack(children: [
          _searchOpen
              ? Column(children: [
                  // AppBar като дете на Column не получава височина отвън —
                  // затова е в SizedBox (същото и в четеца на жития).
                  SizedBox(
                    height: 44 + 58,
                    child: AppBar(
                      primary: false,
                      backgroundColor: AppColors.toolbar,
                      toolbarHeight: 44,
                      leading: _toolbarLeading(),
                      leadingWidth: _leadingWidth,
                      titleSpacing: 8,
                      title: _toolbarTitle(),
                      actions: _toolbarActions(),
                      bottom: _searchBar(),
                    ),
                  ),
                  Expanded(
                      child: _scrollBody(palette, raw, withHeader: false)),
                ])
              : _scrollBody(palette, raw, withHeader: true),
        // „Продължи оттам, докъдето стигна" — изскача веднъж при отваряне
        // и изчезва само, ако не го докоснат. Прозорчето е ОБЩО с четеца
        // на жития (виж reader_resume_prompt.dart).
        if (_saved != null && !_promptShown)
          Positioned(
            left: 12,
            right: 12,
            bottom: 20,
            child: ResumePrompt(
              background: palette.sheet,   // ⚠ от палитрата, не закован цвят:
                                   // в светла тема тъмният фон правеше
                                   // прозорчето нечетимо (текстът също е
                                   // тъмен), а в тъмна се сливаше със
                                   // страницата.
              ink: palette.ink,
              dim: palette.dim,
              onJump: _jumpToSaved,
              onDeleted: () {
                BookPositionStore.clear(
                    widget.book.assetPath, _current.href);
                setState(() {
                  _saved = null;
                  _isBookmarked = false;
                  _savedChapter = null;
                  _savedOffset = null;
                  _awaitingDecision = false;
                });
              },
              // Затваряне без избор: отметката ОСТАВА и продължава да следи
              // — човекът просто чете оттам, докъдето е отворил.
              onClosed: () => setState(() {
                _promptShown = true;
                _awaitingDecision = false;
              }),
            ),
          ),
        // Отстъпът отгоре съвпада с височината на лентата (44) плюс тази
        // за търсене (52) — за да легнат чертичките точно върху скролбара.
        if (_searchOpen && _total > 0)
          matchTicksOverlay(
            // Съотношенията се смятат В МОМЕНТА НА РИСУВАНЕ, а не се пазят:
            // те зависят от височината на изгледа, а тя се мени (завъртане,
            // прибиране на лентата, промяна в SafeArea). Запазени веднъж,
            // остаряват тихо и чертичките се разминават с палеца.
            ratios: [for (final y in _hitYs) _tickRatioFor(y)],
            currentIndex: _currentHit,
            palette: palette,
            top: _ticksLaneTop,
          ),
          ]),
        ),
      ),
    );
  }

  /// Разширенията за flutter_html — ЕДНИ И СЪЩИ навсякъде в този четец.
  ///
  /// Не са `const`, защото картинките трябва да знаят от коя книга и от коя
  /// глава идват, за да разрешат относителния си път.
  List<HtmlExtension> get _htmlExtensions => [
        const ReaderSupExtension(),
        BookImageExtension(book: widget.book, chapterHref: _current.href),
        BookTitleExtension(
            palette: ReaderPalette(ReaderTheme.dark),
            fontSize: ReaderFontSize.value),
      ];

  /// Адресът на житието в azbyka.ru, или null.
  ///
  /// Номерът на статията е оцелял в самите томове като `id` на заглавието:
  /// `<h1 id="642" …>`. Той съвпада с номера в адреса на сайта, откъдето са
  /// свалени книгите — проверено за 1505 от 1533 записа в съдържанията
  /// (останалите 28 са заглавни страници и сборни дялове).
  ///
  /// ⚠ Чете се от СУРОВИЯ html, преди _normalize: там `<h1>` става `<h3>`
  /// и от него остава само текстът, тъй че `id`-то се губи.
  ///
  /// ⚠ Само за томовете по св. Димитрий Ростовски. Проверката е по името на
  /// файла, защото пътят в адреса (`Dmitrij_Rostovskij/zhitija-svjatykh`) е
  /// техен и на друга книга би сочил в празното.
  String? _sourceUrl(String raw) {
    if (!widget.book.assetPath.contains('Димитрий Ростовски')) return null;
    // ⚠ Приема се и „calibre_pb_N", не само голото число. При първите
    // единайсет жития на януари calibre е сложил свой знак за нова страница
    // и е презаписал оригиналния id — номерът обаче е СЪЩИЯ (сверено срещу
    // сайта за 1, 3, 7, 10, 11). Формата се среща само там и само в <h1>,
    // тъй че е безопасно да се брои за равностойна. Без нея точно първите
    // страници, които човек отваря, оставаха без източник.
    final m = RegExp(r'<h1\b[^>]*\bid="(?:calibre_pb_)?(\d+)"')
        .firstMatch(raw);
    if (m == null) return null;
    return 'https://azbyka.ru/otechnik/Dmitrij_Rostovskij/zhitija-svjatykh/'
        '${m.group(1)}';
  }

  /// HTML-ът на главата, готов за рисуване И за PDF.
  ///
  /// ⚠ ЕДНО място за двете. Дотогава сглобяването живееше вътре в
  /// [_chapterBody], тъй че PDF-ът трябваше да го повтори — и при първата
  /// поправка (нов клас, друг ред за източника) двете щяха да се разминат
  /// мълчаливо: на екрана едно, в изнесения файл друго.
  String _chapterHtml(String raw) {
    var body = _normalize(raw);
    // Редът с източника накрая — само в приложението; .epub-ите остават
    // каквито ги прави конвейерът. Класът `.source` вече се рисува от
    // reader_styles.dart (приглушен курсив с отстояние отгоре).
    final src = _sourceUrl(raw);
    if (src != null) {
      body += '<p class="source">Източник: <a href="$src">azbyka.ru</a></p>';
    }
    return body;
  }

  Widget _chapterBody(String raw, ReaderPalette palette) {
    final body = _chapterHtml(raw);
    // Главата се дели на РЕГИОНИ (по абзац), както в четеца на жития.
    //
    // Не е подредба заради подредбата: регионът е единицата, която има свой
    // ключ и оттам реална геометрия в скрола. Без него „на кой пиксел е
    // този ред" няма спрямо какво да се смята — а и буквицата няма откъде
    // да получи втория абзац, който да изтегли до себе си.
    //
    // Маркирането се нанася ПО РЕГИОНИ, с текущо отместване на броя, за да
    // остане номерацията на съвпаденията същата като преди.
    final (beforeHtml, dropCap, firstP, afterHtml) = splitDropCap(body);
    final regions = computeRegions(beforeHtml, dropCap, firstP, afterHtml);
    if (_regionKeys.length != regions.length) {
      _regionKeys = List.generate(regions.length, (_) => GlobalKey());
    }
    final styles = readerStyles(
      fontSize: ReaderFontSize.value,
      palette: palette,
    );
    // Заглавният блок на тома. Класът е на calibre и го има САМО в книгите,
    // затова стои тук, а не в общия reader_styles.dart. Стойностите не са
    // измислени — прочетени са от stylesheet.css вътре в .epub-а:
    // центрирано, с шрифта на заглавията. Без него подзаглавието увисва
    // ляво подравнено под центрираното заглавие.
    styles['.calibre9'] = Style(
      fontFamily: kTitleFamily,
      fontFamilyFallback: kTitleFallback,
      textAlign: TextAlign.center,
      color: palette.ink,
      // Стегнат ред. Заглавието е едро и с обичайното междуредие на четеца
      // двата му реда се разкъсват; в самия том стои 1.2, а инлайн — още
      // по-стегнато (46px при 68px шрифт). Онова инлайн междуредие се маха
      // по-горе, защото flutter_html го чете като множител, тъй че тук е
      // единственото място, където намерението може да се върне.
      lineHeight: const LineHeight(1.05),
      fontSize: FontSize(ReaderFontSize.value + 6),
    );
    // Заглавната страница на тома се разпознава по това, че НЯМА нито един
    // абзац — само заглавен блок. Белегът е структурен, а не „главата е
    // първа": в тома точно два файла са такива (тя и корицата), а всички
    // 550 заглавия делят един и същ клас, тъй че по клас не се различават.
    //
    // Там заглавието е едро и с обичайното междуредие на четеца двата му
    // реда се разкъсват на две отделни надписа.
    if (!body.contains('<p')) {
      styles['h3'] = styles['h3']!.copyWith(
        lineHeight: const LineHeight(0.9),
        // Стегнатият ред слепва и подзаглавието за заглавието — връщаме им
        // въздуха помежду, но само тук: в главите отстоянието заглавие →
        // текст се мери другаде (виж отстоянието под заглавието в четеца).
        margin: Margins.only(top: 18, bottom: 16),
      );
    }

    final fontSize = ReaderFontSize.value;
    final lineHeightPx = fontSize * kReaderLineHeight;

    final children = <Widget>[];
    var matchOffset = 0;
    for (int i = 0; i < regions.length; i++) {
      final r = regions[i];
      if (r.isHtml) {
        children.add(KeyedSubtree(
          key: _regionKeys[i],
          child: Html(
            data: _query.isEmpty
                ? r.content
                : highlightHtml(r.content, _query, matchOffset, _currentHit),
            style: styles,
            extensions: _htmlExtensions,
            onLinkTap: (u, _, __) => _onLinkTap(u),
          ),
        ));
        matchOffset += _countHits(r.content);
      } else {
        children.add(KeyedSubtree(
          key: _regionKeys[i],
          child: DropCapParagraph(
            key: _dropCapKey,
            dropCap: dropCap,
            // Същата сметка като в четеца на жития: 5,5 реда височина, с
            // корекция за ascender-а на Bukvica.
            dropCapSize: lineHeightPx * 5.5 * 0.82,
            lineHeight: lineHeightPx,
            lineFactor: kReaderLineHeight,
            firstParagraph: r.content,
            // Вече се подава: при къс първи абзац следващият се изтегля
            // вдясно от инициала, вместо там да зее празно.
            secondParagraph: r.second,
            fontSize: fontSize,
            capColor: palette.wine,
            inkColor: palette.ink,
            linkColor: palette.link,
            // Първите редове се рисуват РЪЧНО (Text.rich), не през
            // flutter_html — значи маркирането трябва да им се подаде
            // отделно. Без това намереното в началото оставаше неоцветено.
            searchQuery: _query,
            firstGlobalMatchIndex: matchOffset,
            currentGlobalMatch: _currentHit,
            hitColor: palette.hit,
            hitCurrentColor: palette.hitCurrent,
            onLinkTap: _onLinkTap,
          ),
        ));
        matchOffset += _countHits(r.content) + _countHits(r.second);
      }
    }

    return Padding(
      key: _contentKey,
      // Долният отстъп е само дъх след последния ред — мястото на
      // системната лента за жестове вече е отнето от SafeArea (виж build).
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
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
    // Тропарите и кондаците накрая на житието — ПРЕДИ общото правило, инак
    // те щяха да станат обикновени абзаци и да загубят оформлението си.
    //
    // 04_build_epub.py ги бележи с data-prayer="head|csl|trans" и трите
    // стойности се превеждат едно към едно в класовете, с които стария
    // четец рисува тропарите от дневния изглед (виж _prayersBlocksHtml в
    // reader_screen.dart). Така молитвата изглежда еднакво и на двете
    // места, макар да идва от два съвсем различни източника.
    //
    // Атрибут, а не клас: в .epub-а `class` трябва да си остане точно
    // „paragraph", защото проверките на билд скрипта броят абзаците по него
    // — на техния ред виси буквицата.
    const prayerClass = {
      'head': 'prayerhead',
      'csl': 'csl',
      'trans': 'trans',
    };
    body = body.replaceAllMapped(
      RegExp(
          r'<div\s+class="paragraph"\s+data-prayer="(head|csl|trans)"[^>]*>'
          r'(.*?)</div>',
          dotAll: true),
      (m) => '<p class="${prayerClass[m.group(1)]}">${m.group(2)}</p>',
    );
    // Останалите абзаци. Вложени <div> в „paragraph" няма — проверено.
    body = body.replaceAllMapped(
      RegExp(r'<div\s+class="paragraph"[^>]*>(.*?)</div>', dotAll: true),
      (m) => '<p>${m.group(1)}</p>',
    );
    // Заглавието на ЗАГЛАВНАТА СТРАНИЦА — разпознава се и получава свой клас.
    //
    // 04_build_epub.py го пише като <span style="font-size: NNpx;
    // line-height: N;"> с три реда, разделени с <br/>. Тези числа са
    // нагласени по ОБИКНОВЕН четец и там изглеждат точно; flutter_html
    // обаче мери другояче — при 0.62 „на" опира в „СВЕТИИТЕ".
    //
    // Затова инлайн стилът се сваля и се заменя с клас `.booktitle`, чиито
    // стойности живеят в reader_styles.dart. Така .epub-ът остава
    // непокътнат — той е верен за четците, които го отварят отвън — а
    // приложението си има свои числа за същото място.
    body = body.replaceAllMapped(
      // ⚠ Хваща се ЦЕЛИЯТ <h1>, а вътрешното е ЛАКОМО (.*), не пестеливо.
      // Заглавието носи ВЛОЖЕН <span> — онзи, с който .epub-ът повдига „на"
      // за обикновените четци. С пестеливо `.*?` съвпадението спираше на
      // неговия </span>, уловените редове излизаха два вместо три и цялата
      // обработка мълчаливо се пропускаше.
      RegExp(
          r'<h1\b[^>]*>\s*<span style="font-size:\s*\d+px;[^"]*">'
          r'(.*)</span>\s*(?:<br\s*/?>)?\s*</h1>',
          dotAll: true),
      (m) {
        final lines = m
            .group(1)!
            .split(RegExp(r'<br\s*/?>'))
            .map((s) => s.replaceAll(RegExp(r'<[^>]+>'), '').trim())
            .where((s) => s.isNotEmpty)
            .toList();
        // ⚠ САМО за житията. Проверката е по самото заглавие, за да не може
        // намесата да засегне книга, добавена утре: там заглавната страница
        // минава по общия път и остава каквато я е направил конвейерът.
        final whole = lines.join(' ').toLowerCase();
        if (lines.length == 3 && whole.startsWith('жития на светиите')) {
          // Оттук нататък заглавието се рисува от book_title_extension.dart
          // с Column и Text — единственият начин средният ред да се повдигне
          // (виж коментара там кои четири пътя през HTML се провалиха).
          // Остава ВЪТРЕ в <h1>: той се превръща в <h3> малко по-надолу, а
          // правилото за h3 носи `textAlign: center`. Върнеше ли се голият
          // <booktitle>, блокът увисваше вляво.
          return '<h1><booktitle>${lines.join('|')}</booktitle></h1>';
        }
        return m.group(0)!;
      },
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
    // Инлайн междуредието на calibre — маха се, но САМО когато е с мерна
    // единица.
    //
    // Не е разкрасяване, а поправка: flutter_html чете `line-height: 46px`
    // като МНОЖИТЕЛ (46 пъти размера на шрифта), не като дължина. Редът
    // става няколко хиляди пиксела висок и текстът пада далеч под екрана —
    // страницата изглежда напълно празна, без никаква грешка в лога.
    // Точно това правеше заглавната страница на всеки том невидима.
    //
    // ⚠ БЕЗРАЗМЕРНИТЕ стойности („line-height: 0.62") ОСТАВАТ. Те и по CSS
    // значат множител, тъй че flutter_html ги чете правилно — и точно с тях
    // 04_build_epub.py задава сгъстяването на заглавната страница. Триеше
    // ли се и то, същите числа даваха различен вид в приложението и в
    // обикновен четец, а те трябва да си приличат.
    body = body.replaceAll(
        RegExp(r'line-height\s*:\s*[\d.]+\s*(px|em|rem|pt|%)\s*;?'), '');
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

  /// Копчетата в лентата — едни и същи в двата ѝ вида (sliver и закована).
  ///
  /// Целият ред стои в един `Listener`, за да може подсещането за
  /// съдържанието да спре при докосване КЪДЕТО И ДА Е по лентата, а не само
  /// върху самото копче. Listener-ът не поглъща събитието — копчетата под
  /// него работят както преди.
  List<Widget> _toolbarActions() => [
        _stopsNudge(
          child: Row(mainAxisSize: MainAxisSize.min, children: _toolbarRow()),
        ),
      ];

  /// Обвивка, която спира подсещането при докосване. Ползва се и от двете
  /// страни на лентата — важното е човек да е пипнал ЛЕНТАТА, не точно
  /// копчето за съдържание.
  Widget _stopsNudge({required Widget child}) => Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => _stopNudge(),
        child: child,
      );

  /// Стрелката „назад" и до нея копчето за съдържание.
  ///
  /// Съдържанието стои ОТЛЯВО: така е в четците изобщо, а на широк екран
  /// разликата е осезаема. Затова и не минава през [readerToolbarActions] —
  /// то реди копчетата вдясно.
  ///
  /// ⚠ Копчето е в гнездото на СТРЕЛКАТА (с изрично `leadingWidth`), а не в
  /// това на заглавието. На телефон в изправено положение копчетата вдясно
  /// изяждат 244 от 360 dp и за средното поле остават около 40 — копчето
  /// плюс отстъпа му не се побират в тях и лентата прелива. В гнездото на
  /// стрелката мястото е сигурно, а заглавието получава каквото остане:
  /// легнало то е цялото, изправено се свива до многоточие.
  Widget _toolbarLeading() => _stopsNudge(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const BackButton(),
            const SizedBox(width: _contentsGap),
            readerContentsButton(
              context: context,
              onTap: _showToc,
              nudge: widget.hintContents ? _nudge : null,
            ),
          ],
        ),
      );

  /// Луфтът между стрелката и копчето за съдържание.
  ///
  /// Нагласян е по око: стрелката е по-широка от трите точки в другия край,
  /// тъй че при слепени копчета левият край изглежда по-нагъсто от десния.
  static const double _contentsGap = 8;

  /// Ширината на онова гнездо: стрелката (48), луфтът и кръглото копче (30).
  ///
  /// ⚠ Трябва да ги събира ВСИЧКИТЕ. Веднъж го свих, за да изтегля копчето
  /// наляво — и лентата преля с точно толкова, защото луфтът беше направен с
  /// `Transform.translate`, който мести само рисуването, но не и мястото,
  /// което редът иска при разполагането.
  static const double _leadingWidth = 48 + _contentsGap + 30;

  Widget _toolbarTitle() => Text(
        _current.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 15),
      );

  List<Widget> _toolbarRow() => readerToolbarActions(
        context: context,
        onSearch: _toggleSearch,
        searchOpen: _searchOpen,
        onBookmark: _toggleBookmark,
        bookmarked: _isBookmarked,
        // ⚠ Заглавната страница не е четиво — няма какво да се отмята в
        // нея. Посивяването маха и причината за изскачащата подкана при
        // връщане: няма отметка → няма запис → няма подкана. Така не
        // трябва отделно правило, което да я потиска само тук.
        canBookmark: _index > 0,
        onThemeToggle: () =>
            setState(() => ReaderTheme.dark = !ReaderTheme.dark),
        onFontSmaller: () =>
            setState(() => ReaderFontSize.nudge(-ReaderFontSize.step)),
        onFontBigger: () =>
            setState(() => ReaderFontSize.nudge(ReaderFontSize.step)),
        onMore: _showMoreMenu,
      );

  /// Скролируемото тяло. [withHeader] решава дали лентата да е вътре в него
  /// (обикновено четене, прибира се при плъзгане) или не (търсене — тогава
  /// тя е закована отвън; виж коментара в build).
  Widget _scrollBody(ReaderPalette palette, String? raw,
      {required bool withHeader}) {
    return ScrollbarTheme(
      data: readerScrollbarTheme(palette),
      child: Scrollbar(
        controller: _scroll,
        // Постоянно видим палец, докато ИМА чертички за гледане — от старта
        // на търсенето с поне едно намерено, до затварянето му. Иначе
        // чертичките стоят, а палецът (референтната точка спрямо тях)
        // избледнява и сравнението е безсмислено.
        thumbVisibility: _searchOpen && _total > 0,
        // Разрешава ВЛАЧЕНЕ на палеца с пръст; без него скролбарът е само
        // показалец. Флагът разширява и зоната за докосване.
        interactive: true,
        child: CustomScrollView(
          controller: _scroll,
          slivers: [
            if (withHeader)
              SliverAppBar(
                primary: false,
                floating: true,
                snap: true,
                backgroundColor: AppColors.toolbar,
                toolbarHeight: 44,
                leading: _toolbarLeading(),
                leadingWidth: _leadingWidth,
                titleSpacing: 8,
                title: _toolbarTitle(),
                actions: _toolbarActions(),
              ),
            SliverToBoxAdapter(
              child: _entering(
                raw == null
                    ? Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text('Няма ${_current.href}',
                            style: TextStyle(color: palette.dim)))
                    : _chapterBody(raw, palette),
              ),
            ),
            // ⚠ Празнина, която избутва опашката ПОД прегъвката, но само
            // на заглавната страница. Тя е къса — орнамент, заглавие и
            // месец — тъй че без това опашката се вижда още при
            // отварянето и заглавната никога не стои сама на екрана.
            // SliverFillRemaining допълва точно колкото не достига до
            // дъното на изгледа: при дълга страница добавя нула.
            if (_index == 0)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: SizedBox.shrink(),
              ),
            // Опашката с навигацията — вътре в скрола, не като постоянна
            // лента: докато се чете, тя не отнема нищо от екрана.
            SliverToBoxAdapter(child: _footer()),
          ],
        ),
      ),
    );
  }

  /// Обвива новото четиво в плъзгане отстрани плюс избледняване.
  ///
  /// ⚠ Отместването е малко (0,12 от ширината), не цял екран: това не е
  /// прелистване на страници, а смяна на четиво — жестът трябва да се
  /// усети, без да изглежда като че ли съдържанието „лети".
  Widget _entering(Widget child) {
    return AnimatedBuilder(
      animation: Listenable.merge([_enter, _veil]),
      builder: (context, inner) {
        final t = Curves.easeOutCubic.transform(_enter.value);
        // Двете фази се умножават: първо _veil свежда старото до нула,
        // после _enter връща новото нагоре. Едно число за двете, тъй че
        // няма как да останат разсинхронизирани.
        final opacity = (1 - _veil.value) * t;
        final dx = (1 - t) * 0.12 * (_enterFromRight ? 1 : -1);
        return Opacity(
          opacity: opacity.clamp(0.0, 1.0),
          child: FractionalTranslation(
            translation: Offset(dx, 0),
            child: inner,
          ),
        );
      },
      child: child,
    );
  }

  /// Опашката под четивото. Две подредби според това къде сме.
  Widget _footer() {
    // Заглавната страница: един изход навътре, с текст според това дали
    // томът е бил отварян.
    if (_index == 0) {
      final resume = _lastRead;
      final target = resume?.chapter ?? 1;
      if (target >= _chapters.length) return const SizedBox.shrink();
      void go() => _goTo(target);
      return ReaderFooter(
        color: ReaderTheme.palette.dim,
        centerLabel: resume == null
            ? 'към първото четиво'
            : 'продължете от последно отваряното четиво',
        onCenterTap: go,
        right: FooterAction(
          icon: Icons.chevron_right,
          label: '',
          onTap: go,
        ),
      );
    }

    // Житие: назад и напред. ⚠ „Предишно" от ПЪРВОТО житие води към
    // заглавната страница — щом тя е достъпна от съдържанието, няма
    // причина да е недостъпна от навигацията.
    return ReaderFooter(
      color: ReaderTheme.palette.dim,
      left: FooterAction(
        icon: Icons.chevron_left,
        label: 'предишно',
        onTap: () => _goTo(_index - 1),
      ),
      right: _index < _chapters.length - 1
          ? FooterAction(
              icon: Icons.chevron_right,
              label: 'следващо',
              onTap: () => _goTo(_index + 1),
            )
          : null,
    );
  }

}

/// Едно съвпадение при търсене в съдържанието: кой ред и кои знаци от
/// заглавието му обхваща (в ОРИГИНАЛНИЯ текст, с ударенията — виж fold).
class _TocHit {
  final int row;
  final int start;
  final int end;
  const _TocHit(this.row, this.start, this.end);
}

/// Съдържанието като плъзгащ се панел — малък самостоятелен екран.
///
/// Пази вложеността (дните са заглавия, житията под тях са с отстъп) и носи
/// собствена лента: поле за търсене по заглавие и двойка кръгчета, които са
/// „− / +" за размера, а щом търсенето намери нещо — стрелки за обхождане.
/// Двете употреби спокойно делят едно място: никой не нагласява шрифта,
/// докато търси.
class _TocSheet extends StatefulWidget {
  final List<EpubTocEntry> toc;
  final List<EpubTocEntry> chapters;
  final int current;
  final ReaderPalette palette;

  /// Курсорът застава в полето за търсене още при отварянето, тъй че
  /// клавиатурата излиза сама. Вдига се от лупата на заглавната страница.
  final bool autofocusSearch;

  const _TocSheet({
    required this.toc,
    required this.chapters,
    required this.current,
    required this.palette,
    this.autofocusSearch = false,
  });

  @override
  State<_TocSheet> createState() => _TocSheetState();
}

class _TocSheetState extends State<_TocSheet> {
  // Три различни разстояния, не едно. Заглавие на две-три строчки трябва да
  // се чете като ЕДИН блок (сбито междуредие), съседните жития — да се
  // отделят леко, а новият ден — осезаемо повече, защото той е разделителят
  // в списъка. Изравнят ли се трите, изгледът или се разлива, или се слепва.
  static const double _inside = 1.22; // междуредие ВЪТРЕ в едно заглавие
  static const double _gapLife = 4.0; // въздух над и под житие
  static const double _gapDay = 12.0; // въздух над ден
  static const double _padLeft = 16.0;
  static const double _padRight = 16.0;
  static const double _indent = 16.0;

  /// Съдържанието, разгънато в плосък списък: (запис, дълбочина).
  late final List<(EpubTocEntry, int)> _rows;

  final ScrollController _scroll = ScrollController();
  final TextEditingController _searchCtrl = TextEditingController();

  /// Изгладеният низ за сравнение — без ударения и регистър (виж fold()).
  String _query = '';
  List<_TocHit> _hits = const [];
  int _currentHit = -1;

  /// Горният ръб на всеки ред в пространството на списъка.
  ///
  /// Смята се наново при промяна на ширината или на размера на шрифта.
  /// Нужен е, защото `ListView.builder` не строи невидимите редове —
  /// `Scrollable.ensureVisible` няма за какво да се хване, когато
  /// намереното е на стотния ред.
  List<double> _tops = const [];
  double _measuredWidth = -1;
  double _measuredSize = -1;

  @override
  void initState() {
    super.initState();
    final rows = <(EpubTocEntry, int)>[];
    void walk(List<EpubTocEntry> list, int depth) {
      for (final e in list) {
        rows.add((e, depth));
        walk(e.children, depth + 1);
      }
    }

    walk(widget.toc, 0);
    _rows = rows;
    TocFontSize.loadOnce().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    // Последната промяна на размера иначе се губи, ако панелът се затвори
    // преди изтичането на трите секунди покой.
    TocFontSize.flush();
    _scroll.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  /// Стилът на един ред. ЕДНО място — по него и се рисува, и се мери.
  TextStyle _styleOf(bool isDay) => TextStyle(
        color: isDay ? AppColors.sectionTitle : widget.palette.ink,
        // Денят стои с една степен по-едро от житията под него — разликата в
        // ръста го прави разделител и без линия.
        fontSize: TocFontSize.value + (isDay ? TocFontSize.dayBonus : 0),
        height: _inside,
        fontWeight: isDay ? FontWeight.w600 : FontWeight.normal,
        // БЕЗ fontFamily — нарочно. Съдържанието е указател, не четиво: стои
        // със системния шрифт на телефона, както дневният и месечният
        // изглед. Charis SIL остава за самия текст на житията.
      );

  /// Пресмята горните ръбове на редовете със същия стил и същата ширина, с
  /// които се и рисуват. Мерещият трябва да е огледален на рисуващия —
  /// затова редовете се рисуват с `RichText`, а не с `Text`: `Text` слива
  /// стила по подразбиране от контекста, а мерещият не го вижда.
  void _measure(double width) {
    if (width == _measuredWidth && TocFontSize.value == _measuredSize) return;
    _measuredWidth = width;
    _measuredSize = TocFontSize.value;

    final tops = List<double>.filled(_rows.length + 1, 0);
    double y = 0;
    for (int i = 0; i < _rows.length; i++) {
      final (entry, depth) = _rows[i];
      final isDay = depth == 0;
      final painter = TextPainter(
        text: TextSpan(text: entry.title, style: _styleOf(isDay)),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: width - (_padLeft + depth * _indent) - _padRight);
      tops[i] = y;
      y += painter.height + (isDay && i > 0 ? _gapDay : _gapLife) + _gapLife;
      painter.dispose();
    }
    tops[_rows.length] = y;
    _tops = tops;

    // Първото измерване е и мигът, в който вече може да се скролне до
    // маркирания ред: дотогава няма позиции, по които да се цели.
    if (!_revealedCurrent) {
      _revealedCurrent = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _revealCurrent();
      });
    }
  }

  /// Скролването до маркираното става ВЕДНЪЖ, при отваряне. Инак всяко
  /// премерване (смяна на размера на шрифта, завъртане) би дърпало списъка
  /// обратно и човек не би могъл да го разгледа.
  bool _revealedCurrent = false;

  // ── Търсенето ───────────────────────────────────────────────────────
  //
  // Живо: от първия въведен знак, наново при всяка промяна. Списъкът НЕ се
  // филтрира — намереното се маркира и се обхожда, точно както в четеца.
  // Така човек вижда къде в тома попада заглавието, а не изваден от
  // подредбата откъслек.

  void _runSearch(String raw) {
    final q = fold(raw.trim()).text;
    final hits = <_TocHit>[];
    if (q.isNotEmpty) {
      for (int i = 0; i < _rows.length; i++) {
        final folded = fold(_rows[i].$1.title);
        int from = 0;
        while (true) {
          final at = folded.text.indexOf(q, from);
          if (at < 0) break;
          hits.add(_TocHit(
            i,
            folded.origIndex[at],
            folded.origIndex[at + q.length - 1] + 1,
          ));
          from = at + q.length;
        }
      }
    }
    setState(() {
      _query = q;
      _hits = hits;
      _currentHit = hits.isEmpty ? -1 : 0;
    });
    if (hits.isNotEmpty) {
      // Геометрията се строи с кадъра — скачаме след него.
      WidgetsBinding.instance.addPostFrameCallback((_) => _revealHit());
    }
  }

  void _stepHit(int delta) {
    if (_hits.isEmpty) return;
    setState(() {
      _currentHit = (_currentHit + delta) % _hits.length;
      if (_currentHit < 0) _currentHit += _hits.length;
    });
    _revealHit();
  }

  /// Придвижва списъка, за да застане текущото съвпадение в ГОРНАТА част на
  /// видимото.
  ///
  /// Две уговорки, всяка от които е струвала по един неверен изглед:
  ///
  /// • Клавиатурата НЕ смалява изгледа — тя ляга върху него. Мери ли се по
  ///   `viewportDimension`, „видимо" излиза и това, което стои зад нея, и
  ///   намереното редовно се озовава точно под клавиатурата.
  /// • Не всяко натискане мести списъка. Стои ли редът вече в горната
  ///   половина, нищо не мърда — съседните заглавия често са през два реда и
  ///   прескачането при всяко натискане прави обхождането накъсано.
  void _revealHit() {
    if (_currentHit < 0 || _tops.isEmpty || !_scroll.hasClients) return;
    final row = _hits[_currentHit].row;
    final pos = _scroll.position;
    final visible = pos.viewportDimension - MediaQuery.viewInsetsOf(context).bottom;
    if (visible <= 0) return;

    const margin = 28.0; // въздух, за да не опира редът в ръба
    final top = _tops[row];
    final bottom = _tops[row + 1];

    // Удобната зона: от горния ръб до средата на видимото.
    final inBand = top >= pos.pixels + margin &&
        bottom <= pos.pixels + visible * 0.5;
    if (inBand) return;

    // Иначе редът се изкарва на четвърт от височината — достатъчно високо,
    // за да се види и следващото под него, без да е залепен за лентата.
    final target = top - visible * 0.25;
    _scroll.animateTo(
      target.clamp(0.0, pos.maxScrollExtent),
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeInOutCubic,
    );
  }

  /// Изкарва МАРКИРАНИЯ ред (последно четеното житие) на видно място при
  /// отваряне на съдържанието.
  ///
  /// ⚠ Без това маркирането е безполезно в дълъг том: последното четено е
  /// някъде на осемдесетия ред, човек отваря съдържанието, вижда началото
  /// и не разбира, че изобщо има отбелязано място. Скролът го подсеща, а
  /// маркирането после задържа погледа му.
  ///
  /// Ако редът и без това се вижда, нищо не мърда — както при
  /// обхождането на намереното.
  void _revealCurrent() {
    final row = _rows.indexWhere((r) {
      final at = widget.chapters
          .indexWhere((c) => c.href == r.$1.href && c.anchor == r.$1.anchor);
      return at == widget.current;
    });
    if (row <= 0 || _tops.isEmpty || !_scroll.hasClients) return;
    if (row + 1 >= _tops.length) return;

    final pos = _scroll.position;
    final visible = pos.viewportDimension;
    if (visible <= 0) return;
    const margin = 28.0;
    final top = _tops[row];
    final bottom = _tops[row + 1];
    if (top >= pos.pixels + margin && bottom <= pos.pixels + visible * 0.8) {
      return; // вече се вижда
    }
    // ⚠ ВИДИМО плъзгане, не скок. Самото движение е подсещането: то казва
    // „списъкът се премести, защото има отбелязано място". Скочи ли
    // наготово, човек вижда просто едно съдържание, отворено някъде по
    // средата, и маркираният ред не се свързва с нищо.
    //
    // Изчаква панела да изплува (420 ms в _tocSlide) — инак двете
    // движения се засичат и нито едното не се чете.
    Future.delayed(const Duration(milliseconds: 460), () {
      if (!mounted || !_scroll.hasClients) return;
      // ⚠ Отменя се, ако човекът вече е започнал да търси. При лупата на
      // заглавната страница клавиатурата излиза веднага и първият знак
      // може да дойде преди тези 460 ms — тогава обхождането на
      // намереното дърпа списъка на едно място, а това плъзгане на друго.
      // Търсенето печели: то е по-новото желание.
      if (_query.isNotEmpty) return;
      _scroll.animateTo(
        (top - visible * 0.3).clamp(0.0, _scroll.position.maxScrollExtent),
        duration: const Duration(milliseconds: 620),
        curve: Curves.easeInOutCubic,
      );
    });
  }

  /// Изход от търсенето: полето се изчиства, клавиатурата се прибира и
  /// кръгчетата се връщат към размера на шрифта.
  void _clearSearch() {
    _searchCtrl.clear();
    FocusScope.of(context).unfocus();
    setState(() {
      _query = '';
      _hits = const [];
      _currentHit = -1;
    });
  }

  // ── Видът ───────────────────────────────────────────────────────────

  /// Каквото стои в десния край НА САМОТО поле: сивата лупа, докато полето е
  /// празно, и броячът с ✕, щом се пише. Лупата е знак какво е това поле, не
  /// копче — затова отстъпва мястото, щом полето заработи.
  Widget _fieldSuffix(Color fg) {
    if (_query.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(right: 10, left: 6),
        child: Icon(Icons.search, size: 18, color: fg.withValues(alpha: 0.45)),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(right: 8, left: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _hits.isEmpty ? '0/0' : '${_currentHit + 1}/${_hits.length}',
            style: TextStyle(color: fg.withValues(alpha: 0.7), fontSize: 12),
          ),
          const SizedBox(width: 8),
          InkWell(
            onTap: _clearSearch,
            customBorder: const CircleBorder(),
            child: Icon(Icons.close,
                size: 18, color: fg.withValues(alpha: 0.75)),
          ),
        ],
      ),
    );
  }

  Widget _bar(BuildContext context) {
    final fg = AppBarTheme.of(context).foregroundColor ?? Colors.white;
    // Двойката кръгчета сменя занятието си, а не вида си: щом има намерено,
    // „− +" стават „‹ ›" на същото място и със същия размер.
    final stepping = _hits.isNotEmpty;
    return Container(
      color: AppColors.toolbar,
      padding: const EdgeInsets.fromLTRB(12, 6, 14, 8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchCtrl,
              // Лупата на заглавната страница отваря панела готов за
              // писане — виж _BookReaderState._toggleSearch.
              autofocus: widget.autofocusSearch,
              style: TextStyle(color: fg, fontSize: 15),
              textInputAction: TextInputAction.search,
              onChanged: _runSearch,
              decoration: InputDecoration(
                isDense: true,
                hintText: 'търси заглавие',
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
                suffixIcon: _fieldSuffix(fg),
                suffixIconConstraints:
                    const BoxConstraints(minWidth: 0, minHeight: 0),
              ),
            ),
          ),
          const SizedBox(width: 16),
          RoundIconButton(
            icon: stepping ? Icons.chevron_left : Icons.remove,
            tooltip: stepping ? 'Предишно съвпадение' : 'По-дребен шрифт',
            enabled: stepping || TocFontSize.value > TocFontSize.min,
            onTap: () => stepping
                ? _stepHit(-1)
                : setState(() => TocFontSize.nudge(-TocFontSize.step)),
            size: kReaderBtnSize,
          ),
          const SizedBox(width: 18),
          RoundIconButton(
            icon: stepping ? Icons.chevron_right : Icons.add,
            tooltip: stepping ? 'Следващо съвпадение' : 'По-едър шрифт',
            enabled: stepping || TocFontSize.value < TocFontSize.max,
            onTap: () => stepping
                ? _stepHit(1)
                : setState(() => TocFontSize.nudge(TocFontSize.step)),
            size: kReaderBtnSize,
          ),
        ],
      ),
    );
  }

  /// Заглавието на реда, с маркирани съвпадения.
  InlineSpan _spanFor(int i) {
    final (entry, depth) = _rows[i];
    final base = _styleOf(depth == 0);
    if (_query.isEmpty) return TextSpan(text: entry.title, style: base);

    final parts = <InlineSpan>[];
    int at = 0;
    for (int h = 0; h < _hits.length; h++) {
      final hit = _hits[h];
      if (hit.row != i) continue;
      if (hit.start > at) {
        parts.add(TextSpan(text: entry.title.substring(at, hit.start)));
      }
      parts.add(TextSpan(
        text: entry.title.substring(hit.start, hit.end),
        style: TextStyle(
          backgroundColor: h == _currentHit
              ? widget.palette.hitCurrent
              : widget.palette.hit,
        ),
      ));
      at = hit.end;
    }
    if (at < entry.title.length) {
      parts.add(TextSpan(text: entry.title.substring(at)));
    }
    return TextSpan(children: parts, style: base);
  }

  Widget _row(int i) {
    final (entry, depth) = _rows[i];
    final at = widget.chapters.indexWhere(
        (c) => c.href == entry.href && c.anchor == entry.anchor);
    final isCurrent = at == widget.current;
    final isDay = depth == 0;
    return InkWell(
      onTap: at < 0 ? null : () => Navigator.of(context).pop(at),
      child: Container(
        color: isCurrent ? widget.palette.here : null,
        padding: EdgeInsets.fromLTRB(
          _padLeft + depth * _indent,
          // Първият ред няма какво да отделя от предходния.
          isDay && i > 0 ? _gapDay : _gapLife,
          _padRight,
          _gapLife,
        ),
        child: RichText(text: _spanFor(i)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Дръжката и лентата са ЕДИН блок в цвета на инструментите.
        //
        // Иначе при светла тема отгоре стои кремава ивица, под нея тъмна
        // лента, а после пак кремаво — изгледът се насича на пояси. Ъглите
        // повтарят тези на панела (28), инак в двата горни края наднича
        // кремавото под тях.
        Container(
          decoration: const BoxDecoration(
            color: AppColors.toolbar,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: const EdgeInsets.symmetric(vertical: 10),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  // Светла на тъмното — една и съща в двете теми, защото и
                  // подложката ѝ е една и съща.
                  color: Colors.white.withValues(alpha: 0.32),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              _bar(context),
            ],
          ),
        ),
        Flexible(
          child: LayoutBuilder(
            builder: (context, constraints) {
              _measure(constraints.maxWidth);
              final height =
                  constraints.maxHeight.isFinite ? constraints.maxHeight : 600.0;
              return ListView.builder(
                controller: _scroll,
                // Опашка празно място под последното заглавие. Тя не е
                // украса: без нея краят на списъка не може да се вдигне до
                // горната част на изгледа и последните няколко съвпадения
                // при обхождане увисват долу. Плюс мястото на клавиатурата,
                // която покрива последните редове тъкмо при търсене.
                padding: EdgeInsets.only(
                  bottom: MediaQuery.viewInsetsOf(context).bottom +
                      height * 0.55,
                ),
                itemCount: _rows.length,
                itemBuilder: (context, i) => _row(i),
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
  final List<HtmlExtension> extensions;

  const _NoteSheet(
      {required this.html,
      required this.palette,
      required this.extensions});

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
              extensions: extensions,
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
