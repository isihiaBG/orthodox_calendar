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

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'app_theme.dart';
import 'bible_bg_source.dart';
import 'bible_db.dart';
import 'bible_language_pair.dart';
import 'bible_ref.dart';
import 'bible_search_panel.dart';
import 'bible_search_settings.dart';
import 'bible_settings.dart';
import 'package:flutter/services.dart';

import 'external_link.dart';
import 'reader_footer.dart';
import 'reader_more_menu.dart';
import 'reader_font_size.dart';
import 'reader_theme.dart';
import 'reader_toolbar.dart';
import 'search_match.dart';
import 'round_icon_button.dart';
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

/// Един пасаж от препратка, с вече прочетените му стихове.
///
/// ⚠ Групата е по ГЛАВА, не по диапазон — „Мк.9:43,45" е една група с два
/// диапазона. Така „Чети в контекст" сочи еднозначно към една глава.
class _QuoteGroup {
  final BiblePassage passage;
  final BibleBook? book;

  /// Само поисканите редове, по реда им в главата.
  final List<BibleRow> rows;

  const _QuoteGroup({
    required this.passage,
    required this.book,
    required this.rows,
  });

  /// „Мат. 5:3-12" — съкратеното име на книгата плюс мястото.
  String get label =>
      '${book?.abbr ?? passage.book} ${passage.whereLabel}';
}

class BibleReader extends StatefulWidget {
  final String bookCode;
  final int chapter;

  /// Стих, на който да се отвори (от търсене, от отметка, от дневно четиво).
  final String? initialVerse;

  /// Местата в ТАЗИ глава, посочени от препратка — рисуват се с фон.
  ///
  /// Пълни се само при „Чети в контекст": главата се показва цяла, но
  /// поисканото личи. `null` е обикновено четене.
  final BiblePassage? highlight;

  /// Режим „цитати" — вместо главата се показват САМО поисканите стихове,
  /// групирани по пасаж, всеки със свой бутон „Чети в контекст".
  ///
  /// ⚠ Достъпен САМО през препратка от четиво, никога от съдържанието.
  /// Съдържанието води към ГЛАВА; цитатът е нещо друго — извадка, поискана
  /// от текст, който човек чете другаде.
  final BibleRef? quotes;

  /// Заглавие, което ЗАМЕСТВА името на главата в лентата.
  ///
  /// ⚠ Има го само заради търсенето. В режим „цитати" лентата обикновено
  /// изписва къде сочи препратката („Мат. 5:3-12") и това е вярно, докато
  /// пасажите идват от ЕДНО четиво. Резултатите от търсене обаче са от цяло
  /// Писание: първата книга в списъка не значи нищо и надписът по нея би
  /// лъгал, че гледаш нея. Затова тук стои какво Е това — „Резултати от
  /// търсенето".
  final String? resultsTitle;

  /// Един ред обяснение над резултатите — засега само че списъкът е отрязан.
  final String? resultsNote;

  /// Търсеното, за да СВЕТНЕ в показаните стихове.
  ///
  /// ⚠ Пътува през целия път на търсенето: списъкът с извадки го маркира, а
  /// „Чети в контекст" го подава нататък към главата — там стиховете и без
  /// това имат цветен фон, но фонът казва „това поиска", а не „ето заради
  /// коя дума". В глава от четиресет стиха второто е по-нужното.
  final String? searchQuery;

  /// Колко стиха са намерени ОБЩО — не колко се показват.
  final int? totalFound;

  const BibleReader({
    super.key,
    required this.bookCode,
    required this.chapter,
    this.initialVerse,
    this.highlight,
    this.quotes,
    this.resultsTitle,
    this.resultsNote,
    this.searchQuery,
    this.totalFound,
  });

  /// Отваря препратка от житие: списък с цитати, ако местата са няколко или
  /// частични; направо главата, ако е поискана цялата.
  ///
  /// ⚠ Цяла глава („Лк.15") НЕ минава през списъка — той би показал буквално
  /// същото, което и контекстът, и човек би тапвал бутон за нищо. Такива са
  /// 303 от 6369-те препратки в проекта.
  static Widget forRef(BibleRef ref) {
    final first = ref.passages.first;
    if (ref.isWholeChapterOnly) {
      return BibleReader(bookCode: first.book, chapter: first.chapter);
    }
    return BibleReader(
      bookCode: first.book,
      chapter: first.chapter,
      quotes: ref,
    );
  }

  @override
  State<BibleReader> createState() => _BibleReaderState();
}

class _BibleReaderState extends State<BibleReader>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  final ScrollController _scroll = ScrollController();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  // ── Търсене в четивото ─────────────────────────────────────────────────
  //
  // ⚠ ЛЕНТАТА СЕ ТРАНСФОРМИРА, а НЕ излиза втора под нея. Другите два четеца
  // (жития, книги) слагат отделна лента за търсене и това струва скъпо: две
  // подредби карат Flutter да построи НОВ `Scrollable`, тъй че скролът трябва
  // да се пресъздава и позицията да се компенсира с височината на лентите
  // (`kSearchBarHeight` — виж CLAUDE.md, „Затварянето на търсенето скачаше").
  // Тук лентата остава ЕДНА и същата височина, тъй че нищо от това не се
  // налага: подредбата не се мени, само какво стои в лентата.

  /// Кой панел стои в `endDrawer`-а — общите настройки или тези на
  /// търсенето. `Scaffold` има един слот, тъй че се сменя съдържанието му
  /// (същото решение като в указателя).
  bool _searchSettingsInDrawer = false;

  bool _searchOpen = false;
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';

  /// Намереното в показаното: (стих, кое поред е съвпадението в него).
  List<(String, int)> _hits = const [];
  int _currentHit = 0;

  (String, int)? get _currentHitVerse =>
      _hits.isEmpty ? null : _hits[_currentHit.clamp(0, _hits.length - 1)];

  bool get _stepping => _searchOpen && _hits.isNotEmpty;

  /// Какво да свети в стиховете.
  ///
  /// ⚠ Подаденото отвън ИЗПРЕВАРВА полето за търсене: на екрана с намереното
  /// (и в главата, отворена от него) свети думата, с която е търсено, а не
  /// каквото човек евентуално пише в лентата в момента.
  String get _markQuery {
    final outer = widget.searchQuery?.trim();
    if (outer != null) return outer;
    // ⚠ ПРИ РЕЖИМ „В ЦЕЛИЯ ТЕКСТ" В ГЛАВАТА НЕ СЕ МАРКИРА. Заявката се помни
    // и тогава (за да е готова, ако човек превключи режима), но съвпаденията
    // НЕ се броят — тъй че маркирането без това условие рисуваше осветени
    // думи до мъртви стрелки и празен брояч. Отвън изглеждаше като счупено
    // обхождане; всъщност нямаше какво да се обхожда.
    //
    // Правилото е общо: КАКВОТО СВЕТИ, ТОВА СЕ И ОБХОЖДА. Двете следват едно
    // условие, за да не могат да се разминат.
    if (BibleSearchSettings.where == BibleSearchWhere.text) return '';
    return _query;
  }

  /// Върви ли заявка към базата (пълнотекстовото търсене).
  bool _searching = false;

  /// Преводите от показваната двойка, които нямат НИТО ЕДИН стих тук.
  ///
  /// Смята се ВЕДНЪЖ при зареждане, не на всеки ред — обхожда всички редове.
  Set<String> _missingLangs = const {};

  /// Групите в режим „цитати". Празно в обикновено четене.
  List<_QuoteGroup> _groups = const [];

  /// Показва ли се нещо различно от избраното — за тихата бележка отгоре.
  bool _pairFellBack = false;

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

  /// Богослужебните зачала в главата: `стих → номер` („1", „125А").
  ///
  /// ⚠ ЕДНА карта за цялата глава, БЕЗ разбивка по превод. Зачалото е
  /// свойство на МЯСТОТО в Писанието, а не на езика, на който го четеш —
  /// затова и се рисува еднакво във всяка колона. Обединяването на
  /// източниците става в [BibleDb.zachala]; там е и описан бъгът, който
  /// доведе до тази промяна.
  Map<String, String> _zachala = const {};

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
    // ⚠ Слушател, а не еднократно четене: настройката се мени от панела,
    // който стои НАД четеца и НЕ го затваря, тъй че без него зачалата биха
    // се появили/скрили чак при следващо отваряне на глава. Само
    // прерисуване — текстът не се презарежда, защото зачалата вече не се
    // намесват в него (виж [BibleDb.chapter]).
    BibleZachala.notifier.addListener(_onZachalaChanged);
    // ⚠ Наборът от свалени преводи също се мени ИЗПОД четеца — панелът с
    // настройките стои над него и не го затваря. Виж
    // [BibleDb.languagesRevision].
    BibleDb.languagesRevision.addListener(_onInstalledLanguagesChanged);
    _scroll.addListener(_releaseToolbarOnDrag);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    BibleLanguages.notifier.removeListener(_onLanguageChanged);
    BibleZachala.notifier.removeListener(_onZachalaChanged);
    BibleDb.languagesRevision.removeListener(_onInstalledLanguagesChanged);
    ReaderTheme.flush();
    ReaderFontSize.flush();
    BibleFontSize.flush();
    _slide.dispose();
    _scroll.removeListener(_releaseToolbarOnDrag);
    _scroll.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onZachalaChanged() {
    if (mounted) setState(() {});
  }

  /// Свален или изтрит е езиков пакет, докато четецът стои отворен.
  ///
  /// ⚠ Списъкът се чете НАНОВО, а не се допълва: [BibleDb.languages] го
  /// сглобява от основната база плюс всеки свален пакет и го подрежда по
  /// `ord`, тъй че новият превод застава на своето място, а не най-отзад.
  void _onInstalledLanguagesChanged() {
    if (!mounted) return;
    () async {
      final langs = await BibleDb.languages();
      if (!mounted) return;
      setState(() => _langs = langs);
      // При ИЗТРИВАНЕ на превод, който в момента се чете, двойката се
      // подменя — а това пък задейства [_onLanguageChanged], който
      // презарежда самия текст. При обикновено сваляне тук няма какво да се
      // свери и нищо повече не се случва: показваното четиво не се пипа,
      // тъй че мястото в главата се запазва.
      BibleLanguages.reconcile([for (final l in langs) l.code]);
    }();
  }

  // ── Зареждане ────────────────────────────────────────────────────────

  /// Двойката, с която РЕАЛНО е зареден екранът.
  ///
  /// ⚠ Всичко, което рисува, минава оттук, а не направо през
  /// `BibleLanguages.value` — инак при падане към вградените преводи текстът
  /// идва от единия чифт, а лентата отгоре пише другия.
  ///
  /// ⚠ ИЗВЕЖДА СЕ от [_loadedFirst]/[_loadedSecond], а НЕ се пази като свое
  /// поле. Първата версия държеше отделно `_shownPair`, зададено само в
  /// `_load` — и това беше тих регрес: `_onLanguageChanged` презарежда
  /// редовете с новата двойка и обновява `_loadedFirst`/`_loadedSecond`, но
  /// не пипаше него. Тъй че след смяна на превод редовете вече носеха новия
  /// език, а рисуването още търсеше стария — и колоната излизаше ПРАЗНА.
  /// Изведено оттук, „кое се показва" не може да се разсинхронизира с „кое е
  /// заредено", защото е едно и също състояние.
  BibleLanguagePair get _pair {
    final f = _loadedFirst;
    final s = _loadedSecond;
    if (f == null || s == null) return BibleLanguages.value;
    return BibleLanguagePair(
      first: f,
      second: s,
      // Коя от двете половини се гледа е въпрос на РИСУВАНЕ, не на зареждане
      // — плъзгането го мени, без да пипа базата.
      active: BibleLanguages.value.active,
    );
  }

  /// Дошли ли сме тук по препратка от четиво, а не от съдържанието.
  bool get _fromLink => widget.quotes != null || widget.highlight != null;

  /// По колко СТИХА се отварят наведнъж в списъка с намереното.
  ///
  /// ⚠ Не е само за окото, а и за скоростта: всяка глава се чете с ОТДЕЛНА
  /// заявка, тъй че сто намерени стиха от сто различни глави биха значели сто
  /// заявки още при отваряне на екрана. С порции се плаща само за видяното.
  static const int _kQuotePage = 20;

  /// Докъде сме стигнали в `widget.quotes.passages` — оттам продължава
  /// следващата порция.
  int _quoteCursor = 0;

  /// Тече ли зареждане на следваща порция (за да не се пусне два пъти).
  bool _loadingMore = false;

  /// Има ли още непоказани пасажи.
  bool get _hasMoreQuotes =>
      widget.quotes != null && _quoteCursor < widget.quotes!.passages.length;

  /// Колко стиха остават непоказани — за надписа на копчето.
  int get _remainingQuoteVerses {
    final all = widget.quotes?.passages;
    if (all == null) return 0;
    var n = 0;
    for (var i = _quoteCursor; i < all.length; i++) {
      for (final r in all[i].ranges) {
        n += r.to - r.from + 1;
      }
    }
    return n;
  }

  /// Чете стиховете на следващата порция пасажи.
  ///
  /// ⚠ Всяка глава се чете ОТДЕЛНО и се пресява — няма как да се вземат
  /// „стиховете" накуп, защото пасажите може да са в различни глави и дори в
  /// различни книги.
  ///
  /// ⚠ Спира по БРОЙ СТИХОВЕ, не по брой групи. Групите са неравни: една
  /// глава може да даде един стих, друга — двайсет, тъй че „пет групи" е ту
  /// шепа редове, ту цял екран. Броят стихове е това, което човек вижда.
  Future<List<_QuoteGroup>> _loadQuoteGroups(BibleLanguagePair pair) async {
    final all = widget.quotes!.passages;
    final out = <_QuoteGroup>[];
    var added = 0;
    while (_quoteCursor < all.length && added < _kQuotePage) {
      final p = all[_quoteCursor];
      _quoteCursor++;
      final rows = await BibleDb.alignChapter(p.book, p.chapter, pair.both);
      final picked = p.isWholeChapter
          ? rows
          : rows.where((r) {
              final n = int.tryParse(r.verse);
              return n != null && p.marks(n);
            }).toList();
      out.add(_QuoteGroup(
        passage: p,
        book: await BibleDb.book(p.book),
        rows: picked,
      ));
      added += picked.length;
    }
    return out;
  }

  /// „Покажи още" — дочита следващата порция и я долепя към показаното.
  Future<void> _loadMoreQuotes() async {
    if (_loadingMore || !_hasMoreQuotes) return;
    setState(() => _loadingMore = true);
    try {
      final more = await _loadQuoteGroups(_pair);
      if (!mounted) return;
      setState(() => _groups = [..._groups, ...more]);
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _load() async {
    try {
      await ReaderTheme.loadOnce();
      await ReaderFontSize.loadOnce();
      await BibleFontSize.loadOnce();
      await BibleSearchSettings.loadOnce();

      final langs = await BibleDb.languages();
      await BibleLanguages.loadOnce([for (final l in langs) l.code]);

      final allBooks = await BibleDb.books();
      final book = await BibleDb.book(widget.bookCode);
      if (book == null) throw StateError('Няма книга „${widget.bookCode}"');

      var pair = BibleLanguages.value;
      var fellBack = false;

      // ⚠ Падането важи САМО когато сме дошли по ПРЕПРАТКА. Виж [_pair]:
      // при избор от съдържанието човек сам е избрал превода и празният
      // резултат е верният отговор, а тиха подмяна би го объркала.
      if (_fromLink) {
        final probe = await BibleDb.alignChapter(
            widget.bookCode, widget.chapter, pair.both);
        if (probe.isEmpty) {
          pair = const BibleLanguagePair(first: 'bg', second: 'utfcs');
          fellBack = true;
        }
      }

      final rows = widget.quotes != null
          ? const <BibleRow>[]
          : await BibleDb.alignChapter(book.code, widget.chapter, pair.both);
      final groups = widget.quotes == null
          ? const <_QuoteGroup>[]
          : await _loadQuoteGroups(pair);
      final titles = await _titlesForBoth(book.code, pair);
      final zachala = await BibleDb.zachala(book.code, widget.chapter);

      if (!mounted) return;
      setState(() {
        _book = book;
        _allBooks = allBooks;
        _langs = langs;
        _rows = rows;
        _groups = groups;
        _missingLangs = _missingFrom(
            groups.isNotEmpty ? [for (final g in groups) ...g.rows] : rows,
            pair);
        _pairFellBack = fellBack;
        _titles = titles;
        _zachala = zachala;
        _loadedFirst = pair.first;
        _loadedSecond = pair.second;
        _slide.value = pair.active.toDouble();
        _loading = false;
        _error = widget.quotes != null
            ? (groups.every((g) => g.rows.isEmpty)
                ? 'Тези стихове още не са свалени.'
                : null)
            : (rows.isEmpty ? 'Тази глава още не е свалена.' : null);
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
        _slide.animateTo(
          target,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
        );
      }
      return;
    }

    // Сменена е самата ДВОЙКА (от падащото меню) — това вече иска четене.
    _pendingAnchor ??= _topmostVerse();
    final rows = await BibleDb.alignChapter(
      _book!.code,
      widget.chapter,
      pair.both,
    );
    final titles = await _titlesForBoth(_book!.code, pair);
    final zachala = await BibleDb.zachala(_book!.code, widget.chapter);
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _titles = titles;
      _zachala = zachala;
      _loadedFirst = pair.first;
      _loadedSecond = pair.second;
      _missingLangs = _missingFrom(rows, pair);
    });
    _slide.value = pair.active.toDouble();
    _restorePending();
  }

  /// Подзаглавията за ДВАТА превода наведнъж.
  Future<Map<String, Map<String, List<String>>>> _titlesForBoth(
    String book,
    BibleLanguagePair pair,
  ) async {
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
  /// ⚠ Мери се в ПРОСТРАНСТВОТО НА СКРОЛА, а не в глобални пиксели.
  ///
  /// Дотук тук стоеше „вземи глобалното Y на реда минус глобалното Y на
  /// собствения widget". Вторият обаче е СКЕЛЕТЪТ, а скролируемата зона
  /// започва по-надолу — под `SafeArea`. Тоест нулата беше горният ръб на
  /// ЕКРАНА, не на изгледа, и всички разстояния излизаха с една лента на
  /// състоянието по-малки.
  ///
  /// Оттам и странната несиметричност, по която бъгът се разпозна: в
  /// ИЗПРАВЕНО горното поле е към 30 dp, тъй че се улавяше стихът с ЕДИН
  /// по-нагоре; в ЛЕГНАЛО (потопен режим, изрезът е отстрани) полето е
  /// почти нула и сметката излизаше вярна. Затова завъртането натам местеше
  /// с един стих, а обратното — не, и при многократно въртене изместването
  /// се трупаше.
  ///
  /// Сега величината е СЪЩАТА, с която [_jumpToVerse] връща позицията —
  /// `getOffsetToReveal(box, 0.0)`, тоест „при кой офсет този ред застава
  /// най-горе". Улавянето и връщането вече не могат да се разминат по
  /// определение: при непроменена геометрия двете са една и съща стойност.
  String? _topmostVerse() {
    if (!_scroll.hasClients) return null;
    final now = _scroll.offset;

    String? best;
    double bestReveal = double.negativeInfinity;
    for (final row in _rows) {
      final ctx = _keyFor(row.verse).currentContext;
      if (ctx == null) continue;
      final box = ctx.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) continue;
      final reveal = RenderAbstractViewport.of(
        box,
      ).getOffsetToReveal(box, 0.0).offset;
      // Търси се последният ред, който още НЕ е излязъл над горния ръб —
      // тоест онзи, който човекът вижда пръв.
      if (reveal <= now + 1) {
        if (reveal > bestReveal) {
          bestReveal = reveal;
          best = row.verse;
        }
      } else {
        best ??= row.verse;
        break;
      }
    }
    return best;
  }

  /// Връща изгледа на запомнения стих. Изчаква кадър, за да е построена
  /// новата подредба.
  ///
  /// ⚠ ЛЕНТАТА СЕ ЗАКОВАВА ТУК, а не при всеки повикващ поотделно.
  /// Защитата е нужна на всяко програмно връщане, тъй че мястото ѝ е при
  /// самото връщане; държана при повикващите, тя се пише на три места и
  /// рано или късно се забравя на четвъртото. Точно това се беше случило:
  /// `_bumpFont` я имаше, смяната на превода и завъртането — не.
  ///
  /// ⚠ ЗАЩО ЛИЧЕШЕ САМО В НАЧАЛОТО НА ГЛАВАТА. `getOffsetToReveal(box, 0.0)`
  /// подравнява реда с горния ръб на ИЗГЛЕДА, а лентата стои ВЪТРЕ в скрола,
  /// над първия стих. За да излезе стих 1 най-горе, трябва да се скролне
  /// надолу точно с нейната височина — а `floating` лента чете всяко
  /// движение надолу като „скрий се", включително програмното. По-надолу в
  /// текста лентата и без това вече е изпревъртяна, скокът е почти на място
  /// и нищо не помръдва — оттам и усещането, че бъгът е само отгоре.
  void _restorePending() {
    final verse = _pendingAnchor;
    if (verse == null) return;
    // Заковаването трябва да е в сила ПРЕДИ скока, тъй че минава през
    // построяване; самият скок се отлага с кадър и заварва лентата закована.
    if (!_toolbarPinned) setState(() => _toolbarPinned = true);
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
    final ctx = _keyFor(verse).currentContext;
    if (ctx == null || !_scroll.hasClients) return;
    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null) return;

    // ⚠ ПРИ ТЪРСЕНЕ СЕ СПИРА ПО-РАНО. Лентата е ВЪТРЕ в скрола и при
    // търсене стои закована (`pinned`), тъй че „на върха на изгледа" значи
    // „точно под нея" — тоест намереното застава ЗАД лентата и се вижда
    // празно място вместо съвпадение. Изваждат се височината ѝ и още малко
    // въздух, за да се чете и редът преди намереното: стих без съседа си
    // отгоре не казва къде е.
    const air = 56.0;
    final lift = _searchOpen ? kReaderToolbarHeight + air : 0.0;

    final viewport = RenderAbstractViewport.of(box);
    final target = (viewport.getOffsetToReveal(box, 0.0).offset - lift)
        .clamp(
          _scroll.position.minScrollExtent,
          _scroll.position.maxScrollExtent,
        );

    if (animate) {
      _scroll.animateTo(
        target,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
      );
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
    // ⚠ Заковаването на лентата вече НЕ Е тук — премести се в
    // [_restorePending], където важи за всяко програмно връщане.
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
      // ⚠ КАТЕГОРИЯТА Е „БИБЛИЯ", не „ЗА ЧЕТИВАТА". Втората носи размера на
      // буквицата — нещо, което в Писанието изобщо не се среща. Всеки екран
      // подава СВОЯТА категория; общото „всичко" се вижда само от пълния
      // екран с настройки в главното меню.
      endDrawer: _searchSettingsInDrawer
          ? BibleSearchSettingsPanel(
              onChanged: () => _runSearch(_searchCtrl.text))
          : const SettingsDrawer(sections: {SettingsSection.bible}),
      // ⚠ `Stack`, за да може етикетът с главата да се рисува ВЪТРЕ в изреза
      // — тоест ИЗВЪН `SafeArea`, върху ивицата, която тя иначе просто
      // оставя черна. Виж [_chapterSpine].
      body: Stack(
        children: [
          SafeArea(
            child: Container(
              color: palette.bg,
              // ⚠ Лентата е ВЪТРЕ в скрола (виж _body), не над него — иначе
              // не може да се скрива. При зареждане и при грешка обаче тя
              // трябва да се вижда неподвижно, затова тогава се рисува
              // отделно.
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
          _chapterSpine(),
        ],
      ),
    );
  }

  /// Името на главата — В САМИЯ ИЗРЕЗ, като етикет върху гръб на книга.
  ///
  /// ⚠ ЗАЩО НЕ В ЛЕНТАТА. Лентата е `floating` и се скрива при скрол надолу,
  /// тоест „в коя глава съм" го няма точно докато човек чете. Изрезът е
  /// ИЗВЪН скрола — там надписът стои винаги. Пътьом лентата се освобождава
  /// за още едно копче.
  ///
  /// ⚠ И НЕ СТРУВА МЯСТО ЗА ЧЕТЕНЕ. Ивицата на изреза и без това е черна:
  /// `SafeArea` я отделя, а никой не рисува в нея. Мерено на устройството —
  /// 36 dp, и в двете положения.
  ///
  /// ⚠ ИЗРЕЗЪТ НЕ ИЗЧЕЗВА ПРИ ЗАВЪРТАНЕ, А СЕ ПРЕМЕСТВА. Камерата е на един
  /// и същ физически ръб, тъй че в изправено ивицата е ОТГОРЕ, а в легнало —
  /// ОТСТРАНИ (отляво или отдясно според накъде е завъртян телефонът).
  /// Затова в легнало надписът е отвесен: това е единственото, което се
  /// побира на кант от 36 dp — и е точно видът на гръб на книга.
  ///
  /// ⚠ ЕТИКЕТЪТ ТРЪГВА ОТ НАЧАЛОТО НА ИВИЦАТА, НЕ ОТ СРЕДАТА. Самата дупка
  /// на камерата седи в средата ѝ — сверено с `dumpsys`:
  /// `boundingRect = Rect(0, 501 – 99, 579)` при 1080 px дължина, тоест
  /// точно централните 78 px. Центриран надпис би легнал върху обектива.
  /// Затова етикетът стои в началото и дължината му е ограничена до 40% от
  /// ивицата — изрезите са центрирани по устройство, тъй че първите 40% са
  /// свободни навсякъде, без да се пита за точната им геометрия (Flutter и
  /// без това не я дава — `MediaQuery` носи само отстъпите).
  Widget _chapterSpine() {
    final book = _book;
    if (book == null) return const SizedBox.shrink();
    // ⚠ Етикетът в изреза служи на ГЛАВАТА: той пази „къде съм", докато
    // лентата се крие при скрол. На екрана с резултати няма такова „къде" —
    // стиховете са от цяло Писание, — а дългият надпис се и отрязва в тясната
    // ивица. Отпадне ли тук, заглавието остава едно, и то в лентата
    // (виж [_hasSpine], който сам връща false в този случай).
    if (widget.resultsTitle != null) return const SizedBox.shrink();
    final label = _headerLabel(book);

    final mq = MediaQuery.of(context);
    final pad = mq.padding;
    final size = mq.size;

    // ⚠ Стил на ЕТИКЕТ, не на заглавие: дребен, приглушен, с разредка.
    // Той е указател, който стои постоянно пред очите — колкото по-тих,
    // толкова по-малко пречи на четивото до него.
    // ⚠ БЕЗ ФОН, нарочно. Плътна плочка тук би направила ДВЕ тъмни ленти
    // една върху друга — ивицата стои точно над лентата с инструменти — и
    // би превърнала тихия указател в значка. Освен това ивицата е до самия
    // обектив: запълни ли се, окото започва да гледа хардуера. Гол текст
    // оставя кантара да се чете като част от устройството, не като
    // интерфейс.
    //
    // ⚠ 14, не 12.5. Това е надпис, който стои постоянно пред очите и се
    // чете с бегъл поглед — по-дребното пести място, което тук и без това е
    // безплатно. Контраст 5,24:1 върху фона на ивицата.
    final text = Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: AppColors.textSecondary,
        fontSize: 14,
        // По-едрият кегел иска по-малко разредка — инак надписът се разсипва.
        letterSpacing: 0.4,
        height: 1.0,
      ),
    );

    const minStrip = 20.0; // под това ивицата е твърде тясна за надпис

    // ⚠ ПОДРАВНЯВАНЕ С МАРЖИНА НА СЪДЪРЖАНИЕТО (16), а не с първата буква на
    // стиха. Втората стои на ~48 dp, но това число НЕ Е устойчиво: то е
    // сборът от колонката с номерата, а тя се мени с размера на шрифта и с
    // най-дългия номер в главата (Пс. 118 стига до 176). Подравняване по
    // подвижна цел се разпада при първото натискане на „+".
    //
    // 16 е ръбът на самото съдържание (`SliverPadding` в _body) — там
    // започва блокът със стиховете, там пада и стрелката „назад" в лентата
    // (глифът ѝ е на 17,5). Тоест по този ръб се подреждат три неща наведнъж.
    const margin = 16.0;

    if (pad.top >= minStrip) {
      // ⚠ Подравнено с ТЕКСТА на стиховете, не с ръба на блока. Между двете
      // стои колонката с номерата; захване ли се надписът за ръба, той увисва
      // над числата и се чете като част от тях. По исканата подредба той е
      // етикет на самото четиво, тъй че тръгва оттам, откъдето тръгва и то.
      //
      // Целта е подвижна (колонката расте с шрифта и с най-дългия номер —
      // Пс. 118 стига до 176), затова се СМЯТА при всяко рисуване, вместо да
      // се закове число. Така подравняването следва текста, вместо да се
      // разпадне при първото „+".
      final textLeft = margin + _numberWidth + _kNumberGap;

      // ⚠ Краят пази разстояние от ОБЕКТИВА. Дупката на камерата е в средата
      // на ивицата (сверено с dumpsys: централните 78 px от 1080), тъй че
      // дясната граница стои на 44% от ширината — надписът се сбива с
      // многоточие, вместо да пропълзи под стъклото. Дотук границата идваше
      // от фиксирана ширина 40%; сега тя се мери от НАЧАЛОТО, което вече не
      // е нула, инак изместването надясно избутваше края точно в дупката.
      final right = size.width * 0.44;
      final w = right - textLeft;

      return Positioned(
        top: 0,
        left: textLeft,
        height: pad.top,
        // Съвсем тясна ивица (много едър шрифт, трицифрени номера) не бива да
        // дава отрицателна ширина — тогава надписът се връща на стария си ръб.
        width: w > 60 ? w : size.width * 0.40,
        child: Align(alignment: Alignment.centerLeft, child: text),
      );
    }

    // ⚠ В ЛЕГНАЛО НАДПИСЪТ ЗАПОЧВА ОТ ДОЛНИЯ РЪБ НА ЛЕНТАТА.
    //
    // Хоризонталната черта под лентата е най-силната линия на екрана; когато
    // краят на етикета легне точно на нея, двете се четат като едно
    // подравняване, а не като два случайни надписа. Оттам и
    // `kReaderToolbarHeight` — смени ли се утре височината на лентата,
    // етикетът се мести с нея.
    //
    // ⚠ `quarterTurns` следва СТРАНАТА: при ивица отляво надписът се чете
    // отдолу нагоре (както на гръб на книга, обърнат към лицето ѝ), при
    // ивица отдясно — отгоре надолу. Обратното кара текста да „бяга" от
    // страницата.
    //
    // ⚠ Дължината е ограничена ДО СРЕДАТА, защото там е обективът: сверено
    // с `dumpsys`, изрезът заема точно централните 78 px от 1080. Дванайсет
    // dp резерв, за да не опира.
    final toCutout = size.height / 2 - kReaderToolbarHeight - 12;

    if (pad.left >= minStrip) {
      return Positioned(
        left: 0,
        top: kReaderToolbarHeight,
        width: pad.left,
        height: toCutout,
        child: RotatedBox(
          quarterTurns: 3,
          // Преди завъртането „вдясно" е краят на надписа; след него той
          // сочи НАГОРЕ, тоест ляга на чертата под лентата.
          child: Align(alignment: Alignment.centerRight, child: text),
        ),
      );
    }
    if (pad.right >= minStrip) {
      return Positioned(
        right: 0,
        top: kReaderToolbarHeight,
        width: pad.right,
        height: toCutout,
        child: RotatedBox(
          quarterTurns: 1,
          child: Align(alignment: Alignment.centerLeft, child: text),
        ),
      );
    }
    // Устройство без изрез — етикет няма къде да стои; заглавието остава в
    // лентата (виж [_portraitBar]).
    return const SizedBox.shrink();
  }

  /// Има ли изрез, в който да застане етикетът с главата. Няма ли — името
  /// остава в лентата с инструменти, за да не изчезне съвсем.
  bool get _hasSpine {
    // ⚠ Резултатите от търсене НЕ отиват в изреза. Той побира къс надпис
    // („Мат. 5") — дълъг като „Резултати от търсенето" се отрязва точно
    // толкова, че да не значи нищо. Лентата е по-широка и на този екран е
    // свободна, защото там няма глава, чието име да пази.
    if (widget.resultsTitle != null) return false;
    final p = MediaQuery.of(context).padding;
    return p.top >= 20 || p.left >= 20 || p.right >= 20;
  }

  Widget _body(ReaderPalette palette, bool landscape) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _error!,
            textAlign: TextAlign.center,
            style: TextStyle(color: palette.dim, fontSize: 16),
          ),
        ),
      );
    }

    final pair = _pair;
    final content = Theme(
      data: Theme.of(context).copyWith(
        scrollbarTheme: readerScrollbarTheme(palette),
        // Маркиране/копиране на текст — ОБЩО с другите два четеца (виж
        // `book_reader` и `reader_screen.buildScrollableBody`). Цветовете са
        // същите, за да е един и същ жестът в цялото приложение.
        textSelectionTheme: TextSelectionThemeData(
          selectionColor: AppColors.sectionTitle.withValues(alpha: 0.35),
          selectionHandleColor: AppColors.sectionTitle,
          cursorColor: AppColors.sectionTitle,
        ),
        // ⚠ ФОНЪТ НА КОНТЕКСТНОТО МЕНЮ („Копиране / Споделяне") идва оттук.
        // Material го взима от `colorScheme.surface`, но САМО ако тя е
        // подменена: при подразбиращата се пада на свой закован цвят, който
        // върху почти черната страница на четеца се слива с нея и менюто
        // изглежда като надписи, увиснали във въздуха.
        //
        // ⚠ И ДВЕТЕ СЕ ЗАДАВАТ ЗАЕДНО. Смяна само на фона е документираният
        // капан „закован цвят + цвят от палитрата в едно и също нещо":
        // надписите идват от `onSurface` и в СВЕТЛА тема биха останали светли
        // върху светъл фон.
        //
        // `palette.sheet` е установеният цвят за изскачащо НАД четиво — сив в
        // двете теми, по-светъл от тъмната страница и по-тъмен от кремавата,
        // тъй че прозорчето се чете по разликата, не по конкретния цвят.
        colorScheme: Theme.of(context).colorScheme.copyWith(
              surface: palette.sheet,
              onSurface: palette.ink,
            ),
      ),
      // ⚠ SelectionArea обгръща СКРОЛА, не всеки стих: така маркирането
      // минава през няколко стиха наведнъж, а не спира на границата им.
      // Липсваше тук, макар стиховете да са обикновени `Text`/`Text.rich`,
      // тоест готови за селекция — както беше пропуснато и в четеца на книги
      // (докладвано 21.08.2026).
      child: SelectionArea(
        child: Scrollbar(
        controller: _scroll,
        // ⚠ Палецът се ХВАЩА С ПРЪСТ и се влачи — иначе скролбарът е само
        // показалец. Флагът разширява и зоната за докосване около него.
        // Същото е и в четеца на книги.
        interactive: true,
        // ⚠ Постоянно видим ДОКАТО СЕ ТЪРСИ: тогава човек скача между
        // намереното и дългата глава се обхожда напред-назад, тъй че палецът
        // трябва да е под пръста, а не да се появява чак след като скролът
        // вече е тръгнал. Извън търсенето се държи както навсякъде другаде —
        // явява се при движение и избледнява, за да не стои ивица до текста.
        thumbVisibility: _searchOpen,
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
            // ⚠ И ПРИ ТЪРСЕНЕ лентата се заковава. Тя носи полето, брояча и
            // стрелките за обхождане — скрие ли се при скрол, човек остава
            // без нито едно от тях точно докато обхожда намереното. А самото
            // обхождане мести скрола програмно, тоест лентата би се крила от
            // собствените ни скокове (същата причина като при +/-).
            SliverAppBar(
              floating: true,
              snap: !_toolbarPinned && !_searchOpen,
              pinned: _toolbarPinned || _searchOpen,
              automaticallyImplyLeading: false,
              backgroundColor: AppColors.toolbar,
              elevation: 0,
              toolbarHeight: kReaderToolbarHeight,
              titleSpacing: 0,
              title: _toolbar(palette, landscape),
              // ⚠ `automaticallyImplyActions: false` — ТОВА е ключът срещу
              // хамбургера, а НЕ празен списък в `actions`.
              //
              // Дотук стоеше `actions: const []` с обяснението, че така
              // копчето за `endDrawer` не се добавя. Не е вярно и се виждаше
              // на екрана: AppBar проверява `actions != null &&
              // actions!.isNotEmpty` (app_bar.dart), тъй че ПРАЗЕН списък
              // пропада точно към `else if (hasEndDrawer …)` и слага
              // `EndDrawerButton` — хамбургер най-вдясно.
              //
              // Освен че е излишно второ меню до трите точки, той изместваше
              // и целия ред навътре: общият `readerToolbarActions` завършва
              // със `SizedBox(width: 2)`, тъй че трите точки трябва да опират
              // в десния ръб. С хамбургера подире им между тях зееше дупка,
              // двойно по-широка от всички останали разстояния в лентата.
              //
              // Настройките на четеца се отварят от трите точки
              // (`kReaderSettingsMenuItem` → `_showMoreMenu`), както в другите
              // два четеца.
              automaticallyImplyActions: false,
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
                        if (_pairFellBack) _fallbackNote(palette),
                        ...(_groups.isNotEmpty
                            ? _quoteBodies(palette, pair, landscape)
                            : [
                                landscape
                                    ? _parallelColumns(palette, pair)
                                    : _slidingColumn(
                                        palette, pair, _textWidth),
                                _footer(palette),
                              ]),
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
        ),
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
    // Бърз замах решава посоката; бавно пускане — по това коя половина е
    // по-близо.
    final target = velocity.abs() > 320
        ? (velocity < 0 ? 1.0 : 0.0)
        : (_slide.value >= 0.5 ? 1.0 : 0.0);

    _slide
        .animateTo(
          target,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        )
        .whenComplete(() {
          if (!mounted) return;
          final wanted = target == 1.0 ? 1 : 0;
          // ⚠ Двойката се чете НАНОВО, а не се ползва уловената горе.
          //
          // Между потеглянето и доиграването минават 220 ms — предостатъчно
          // човек да отвори падащото меню и да смени превод. Записът с уловената
          // отпреди двойка връщаше стария избор върху новия и отвън изглеждаше
          // като „менюто не сработи". Тук ни трябва само `active`; кои са двата
          // превода в този миг решава единствено текущото състояние.
          final now = BibleLanguages.value;
          if (now.active == wanted) return;
          BibleLanguages.set(now.copyWith(active: wanted));

          // ⚠ Намереното се преброява НАНОВО САМО КОГАТО КОЛОНАТА НАИСТИНА СЕ
          // Е СМЕНИЛА — затова е след проверката, а не преди нея.
          //
          // Тук беше бъгът „обхождането не работи и скролът е закован":
          // лентата е ВЪТРЕ в скрола, тъй че всеки тап по нея и всяко
          // вертикално влачене минава през обгръщащия `GestureDetector`.
          // Той губи състезанието за жеста и получава
          // `onHorizontalDragCancel`, който вика тъкмо този метод. Викано
          // безусловно, преброяването нулираше `_currentHit` веднага след
          // всяко натискане на „‹ ›" (проверено в лог: `_stepHit` вдига
          // брояча на 1, а `_runSearch` го връща на 0 в същия кадър), а при
          // опит за скрол връщаше позицията на първото съвпадение — оттам
          // „не дава да мръднеш".
          //
          // ⚠ Тук, а не на всеки кадър от `_slide`: между двете крайни
          // положения няма „активен превод", а стойността се мени 60 пъти в
          // секунда.
          if (_searchOpen && _query.isNotEmpty) {
            _runSearch(_searchCtrl.text);
          }
        });
  }

  /// Тялото в режим „цитати": пасажите един под друг, всеки със заглавие и
  /// свой бутон за контекст.
  ///
  /// ⚠ Заглавие има САМО когато пасажите са повече от един. При единствен
  /// пасаж горе в лентата вече пише същото („Мат. 5:3-12") и повторението на
  /// един екран изглежда като недоглеждане.
  List<Widget> _quoteBodies(
      ReaderPalette palette, BibleLanguagePair pair, bool landscape) {
    final many = _groups.length > 1;
    final out = <Widget>[];

    // ⚠ Бележката стои НАД първия резултат, не под последния: тя казва, че
    // списъкът е отрязан, а това трябва да се знае, преди човек да е решил,
    // че намереното е всичко. Под списък от триста извадки никой не стига.
    final note = widget.resultsNote;
    if (note != null) {
      out.add(Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Text(note,
            style: TextStyle(
                color: palette.dim, fontSize: 13, height: 1.35)),
      ));
    }

    for (var gi = 0; gi < _groups.length; gi++) {
      final g = _groups[gi];
      if (many) out.add(_quoteHeading(palette, g));
      if (g.rows.isEmpty) {
        out.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text('Тези стихове още не са свалени.',
              style: TextStyle(color: palette.dim, fontSize: 15)),
        ));
      } else {
        out.add(landscape
            ? _parallelColumns(palette, pair,
                rows: g.rows,
                chapter: g.passage.chapter,
                book: g.passage.book)
            : _slidingColumn(palette, pair, _textWidth,
                rows: g.rows,
                chapter: g.passage.chapter,
                book: g.passage.book));
      }
      out.add(_contextButton(palette, g, last: gi == _groups.length - 1));
    }

    // ⚠ Копчето стои НАЙ-ОТДОЛУ, не като безкраен скрол. Списъкът с
    // намереното не се „разглежда", а се преглежда: човек стига до дъното,
    // вижда колко още има и решава. Автоматичното дозареждане би му отнело
    // точно това решение и би заличило усета докъде е стигнал.
    if (_hasMoreQuotes) out.add(_moreQuotesButton(palette));
    return out;
  }

  /// „Покажи още N" под списъка с намереното.
  ///
  /// ⚠ Числото е ИСТИНСКОТО останало, не кръгло „още 20": при седем останали
  /// копче с надпис „още 20" обещава повече, отколкото има, а следващият
  /// натиск свършва списъка и обещанието остава неудържано.
  Widget _moreQuotesButton(ReaderPalette palette) {
    final left = _remainingQuoteVerses;
    final next = left < _kQuotePage ? left : _kQuotePage;
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 28),
      child: Center(
        child: TextButton(
          onPressed: _loadingMore ? null : () => unawaited(_loadMoreQuotes()),
          style: TextButton.styleFrom(
            foregroundColor: palette.dim,
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
              side: BorderSide(color: palette.dim.withValues(alpha: 0.35)),
            ),
          ),
          child: _loadingMore
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: palette.dim),
                )
              : Text('Покажи още $next',
                  style: const TextStyle(fontSize: 15)),
        ),
      ),
    );
  }

  /// Каквото да пише горе — в лентата и в ивицата до камерата.
  ///
  /// ⚠ В режим „цитати" това НЕ е глава, а самата препратка. „Мат. 5" би
  /// било подвеждащо: на екрана не стои глава 5, а извадка от нея. При
  /// няколко пасажа се изброяват, докато се съберат, а останалите се сбиват
  /// в „+2" — заглавието е за ориентир, не за препис на препратката.
  String _headerLabel(BibleBook book) {
    // ⚠ Заглавието от търсенето изпреварва всичко: там пасажите са от цяло
    // Писание и изброяването им („Бит. 1:3, Мат. 5:9 +118") не ориентира, а
    // обърква.
    final override = widget.resultsTitle;
    if (override != null) {
      // ⚠ БРОЯТ Е НА НАМЕРЕНОТО, не на показаното. Списъкът се отваря на
      // части, но „Намерени: 37" трябва да казва колко има — инак числото
      // расте при всяко „Покажи още" и престава да значи каквото и да е.
      //
      // ⚠ Брои СТИХОВЕ, не съвпадения: в един стих думата може да стои и по
      // два пъти, а човек мери намереното с места в Писанието.
      final n = widget.totalFound;
      return n == null ? override : 'Намерени: $n';
    }
    if (_groups.isEmpty) return '${book.abbr} ${widget.chapter}';
    if (_groups.length == 1) {
      return '${book.abbr} ${_groups.first.passage.whereLabel}';
    }
    final shown = _groups.take(2).map((g) => g.passage.whereLabel).join(', ');
    final rest = _groups.length - 2;
    return '${book.abbr} $shown${rest > 0 ? ' +$rest' : ''}';
  }

  /// Преводите от показваната двойка, които нямат НИТО ЕДИН стих тук.
  ///
  /// ⚠ Пет от дванайсетте покриват само част от Писанието — ивритът и
  /// Септуагинтата нямат Нов завет, гръцкият Нов завет и древногрузинският
  /// нямат Стар, а KJV е без единайсетте второканонични книги. Отвореше ли се
  /// книга извън обхвата им, колоната им оставаше празна БЕЗ ДУМА обяснение и
  /// приличаше на несвалена или счупена.
  /// ⚠ Смята се от ПОДАДЕНИТЕ редове, не от `_rows` — вика се вътре в
  /// `setState`, преди полето да е присвоено.
  Set<String> _missingFrom(List<BibleRow> rows, BibleLanguagePair pair) {
    if (rows.isEmpty) return const {};
    final out = <String>{};
    for (final code in pair.both) {
      if (!rows.any((r) => r[code] != null)) out.add(code);
    }
    return out;
  }

  /// Защо този превод го няма ТУК — изведено от обхвата му И от книгата.
  ///
  /// ⚠ Двата случая са различни и смесването им ПОДВЕЖДА:
  ///
  ///   • книгата е от другия завет — „налични са само за Стария завет";
  ///   • книгата е от СЪЩИЯ завет, но преводът я няма — тогава горното е
  ///     направо невярно. Ивритът например обхваща Стария завет, но по
  ///     ЕВРЕЙСКИЯ канон: Товит е старозаветна книга и пак я няма. Кажеш ли
  ///     там „само за Стария завет", човек чете глупост, защото точно в
  ///     Стария завет се намира.
  String _whyMissing(BibleLanguage l) {
    final testament = _book?.testament;
    if (l.scope == 'ot' && testament == 'NT') {
      return 'Текстовете на ${l.short} са налични само за Стария завет.';
    }
    if (l.scope == 'nt' && testament == 'OT') {
      return 'Текстовете на ${l.short} са налични само за Новия завет.';
    }
    return 'Тази книга не е включена в превода „${l.short}".';
  }

  /// Бележката за непълно покритие — В КОЛОНАТА на липсващия превод.
  ///
  /// ⚠ Тук, а не над цялата глава: съседната колона си е наред и текстът ѝ се
  /// чете нормално. Обща бележка отгоре би обявила празнота, каквато има само
  /// от едната страна.
  Widget _coverageNote(ReaderPalette palette, String code) {
    final lang = _languageOf(code);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        lang == null ? 'Този превод няма тази книга.' : _whyMissing(lang),
        style: TextStyle(
          fontSize: 13,
          height: 1.35,
          color: palette.dim,
          fontStyle: FontStyle.italic,
        ),
      ),
    );
  }

  /// Тиха бележка, когато показваме друг превод от избрания.
  ///
  /// ⚠ Казва се ВЕДНЪЖ и приглушено. Човек е тапнал препратка в житие; той не
  /// е искал да смени езика и не бива да го гони съобщение — трябва само да
  /// разбере защо текстът пред него не е на онова, което четеше.
  Widget _fallbackNote(ReaderPalette palette) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Text(
          'Избраният превод няма това място. Показано на български и '
          'църковнославянски.',
          style: TextStyle(
            fontSize: 13,
            height: 1.35,
            color: palette.dim,
            fontStyle: FontStyle.italic,
          ),
        ),
      );

  /// Съкратеният запис над пасажа — „Мат. 5:3-12".
  ///
  /// ⚠ СЪС СИСТЕМНИЯ шрифт, не с [kTitleFamily]. Заглавието не е част от
  /// четивото, а указател към него — както дяловете в съдържанието и както
  /// самото съдържание на „Месецослов". Изписано с Tamburin, то се четеше
  /// като заглавие НА текста, а не като етикет над извадка.
  ///
  /// ⚠ Проперкейс, не главни. Дяловете в съдържанието са с главни, защото са
  /// имена на цели раздели; тук стои конкретно място („Мат. 5:3-12"), а
  /// главните биха превърнали указателя в надслов.
  Widget _quoteHeading(ReaderPalette palette, _QuoteGroup g) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          g.label,
          style: TextStyle(
            fontSize: BibleFontSize.value * 1.04,
            fontWeight: FontWeight.w700,
            color: palette.heading,
          ),
        ),
      );

  /// „Чети в контекст" — отваря ГЛАВАТА на този пасаж с маркирани места.
  ///
  /// ⚠ Бутонът е на всяка ГРУПА, не на екрана: „Йн.3:1-21, 7:50-52" са две
  /// различни глави и един общ бутон не би знаел коя да отвори.
  ///
  /// Връщането оттам води обратно ТУК, в списъка — човек може да обиколи
  /// пасажите един по един, без да се губи. За това не е нужно нищо особено:
  /// това е обикновен `push`, тъй че системният „назад" сам връща където
  /// трябва.
  Widget _contextButton(ReaderPalette palette, _QuoteGroup g,
          {required bool last}) =>
      Padding(
        padding: EdgeInsets.only(top: 6, bottom: last ? 8 : 28),
        child: Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            style: TextButton.styleFrom(
              foregroundColor: palette.dim,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              visualDensity: VisualDensity.compact,
            ),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => BibleReader(
                  bookCode: g.passage.book,
                  chapter: g.passage.chapter,
                  highlight: g.passage,
                  // ⚠ Търсеното пътува НАТАТЪК. Фонът под стиховете казва
                  // „това поиска", но не и защо: в глава от четиресет стиха
                  // окото пак трябва да търси думата на ръка. Подадена, тя
                  // свети и там — и трите нива на търсенето (списъкът с
                  // намереното, контекстът, четенето) маркират едно и също.
                  searchQuery: widget.searchQuery,
                  initialVerse: g.rows.isEmpty ? null : g.rows.first.verse,
                ),
              ),
            ),
            icon: const Icon(Icons.menu_book_outlined, size: 17),
            label: const Text('Чети в контекст', style: TextStyle(fontSize: 14)),
          ),
        ),
      );

  /// Изправено: колонка с номерата, закована по X, и плъзгащи се преводи.
  ///
  /// ⚠ Номерът стои ИЗВЪН плъзгащото се. Той е един и същ за двата превода —
  /// стих 12 си е стих 12 — тъй че да се движи заедно с текста би било
  /// безсмислено трептене. По Y се движи свободно с реда, защото е част от
  /// същия отвесен скрол.
  Widget _slidingColumn(
    ReaderPalette palette,
    BibleLanguagePair pair,
    double textWidth, {
    List<BibleRow>? rows,
    int? chapter,
    String? book,
  }) {
    final list = rows ?? _rows;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < list.length; i++)
          _rowShell(
            palette,
            i,
            list,
            chapter: chapter,
            book: book,
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                    width: _numberWidth, child: _number(palette, list[i])),
                const SizedBox(width: _kNumberGap),
                SizedBox(
                  width: textWidth,
                  child: _slidingPair(palette, list[i], pair, textWidth),
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
  Widget _slidingPair(
    ReaderPalette palette,
    BibleRow row,
    BibleLanguagePair pair,
    double w,
  ) {
    final first = SizedBox(
      width: w,
      child: _verseBody(palette, row, pair.first),
    );
    final second = SizedBox(
      width: w,
      child: _verseBody(palette, row, pair.second),
    );

    return ClipRect(
      child: AnimatedBuilder(
        animation: _slide,
        builder: (context, _) {
          final t = _slide.value;
          return Stack(
            alignment: AlignmentDirectional.topStart,
            children: [
              Transform.translate(offset: Offset(-t * w, 0), child: first),
              Transform.translate(
                offset: Offset((1 - t) * w, 0),
                child: second,
              ),
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
  Widget _parallelColumns(
    ReaderPalette palette,
    BibleLanguagePair pair, {
    List<BibleRow>? rows,
    int? chapter,
    String? book,
  }) {
    final list = rows ?? _rows;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < list.length; i++)
          _rowShell(
            palette,
            i,
            list,
            chapter: chapter,
            book: book,
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                      width: _numberWidth, child: _number(palette, list[i])),
                  const SizedBox(width: _kNumberGap),
                  Expanded(child: _verseBody(palette, list[i], pair.first)),
                  // Чертата по средата — тънка и приглушена: тя разделя, а не
                  // рисува таблица. Границите между РЕДОВЕТЕ нарочно ги няма.
                  Container(
                    width: 1,
                    margin: const EdgeInsets.symmetric(horizontal: 12),
                    color: palette.dim.withValues(alpha: 0.25),
                  ),
                  Expanded(child: _verseBody(palette, list[i], pair.second)),
                ],
              ),
            ),
          ),
      ],
    );
  }

  /// Маркиран ли е този стих от препратката, довела човека тук.
  ///
  /// ⚠ `row.verse` е ТЕКСТ, не число — при надписание на псалом е „0", а
  /// понякога носи буква. Затова се минава през `tryParse`, а не през
  /// `int.parse`: нечисловият ред просто не е маркиран, вместо да гръмне
  /// насред рисуването.
  bool _isQuoted(BibleRow row) {
    final p = widget.highlight;
    if (p == null || p.isWholeChapter) return false;
    final n = int.tryParse(row.verse);
    return n != null && p.marks(n);
  }

  /// Кутията около един ред — тя носи фона, когато редът е част от цитата.
  ///
  /// ⚠ Празнината под стиха влиза ВЪТРЕ във фона само когато СЛЕДВАЩИЯТ ред
  /// също е маркиран. Иначе диапазон от десет стиха би изглеждал като десет
  /// отделни плочки със светли процепи помежду им, вместо като един цитат.
  /// По същата причина ъглите се закръглят само на КРАИЩАТА на блока —
  /// закръглени навсякъде, те правят същата стълба.
  Widget _rowShell(
    ReaderPalette palette,
    int i,
    List<BibleRow> rows,
    Widget child, {
    int? chapter,
    String? book,
  }) {
    final row = rows[i];
    final key = _keyFor(row.verse, chapter, book);
    if (!_isQuoted(row)) {
      return Container(
        key: key,
        padding: const EdgeInsets.only(bottom: _kVerseGap),
        child: child,
      );
    }
    final prevMarked = i > 0 && _isQuoted(rows[i - 1]);
    final nextMarked = i + 1 < rows.length && _isQuoted(rows[i + 1]);
    return Container(
      key: key,
      padding: EdgeInsets.only(bottom: nextMarked ? _kVerseGap : 0),
      margin: EdgeInsets.only(bottom: nextMarked ? 0 : _kVerseGap),
      decoration: BoxDecoration(
        color: palette.quote,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(prevMarked ? 0 : 4),
          bottom: Radius.circular(nextMarked ? 0 : 4),
        ),
      ),
      child: child,
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
  /// ДВЕ ПРАВИЛА:
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

  /// Надписът на зачалото за този стих в този превод — или `null`.
  ///
  /// ⚠ ЕДИН И СЪЩ НОМЕР, РАЗЛИЧНО ИЗПИСВАНЕ. Зачалото е свойство на мястото,
  /// тъй че номерът идва от общата карта и не зависи от превода. Формата на
  /// съкращението обаче зависи от АЗБУКАТА: в църковнославянската графика
  /// установеното е „Заⷱ҇" (с надредно „ч"), а на гражданска азбука —
  /// „Зач.". Изписването е част от текста, не негов превод — затова всяка
  /// колона го носи по своему, както носи и самия текст.
  ///
  /// ⚠ Признакът е „ЦЪРКОВНОСЛАВЯНСКИ ЛИ Е", а НЕ `rubricate` и НЕ шрифтът.
  ///
  /// Дълго тук стоеше `rubricate` и работеше — но по СЪВПАДЕНИЕ: единственият
  /// рубрикиран превод беше и единственият в славянска графика. На
  /// 26.08.2026 рубрикацията се включи и за гражданската азбука (`cs`) и
  /// двете се разделиха. `rubricate` значи „червена главна буква" — свойство
  /// на богослужебната КНИГА; надредното „ч" в „Заⷱ҇" е свойство на самия
  /// ЕЗИК. Оставен по стария признак, флагът щеше да разнася съкращението
  /// навсякъде, където някой ден се включи рубрикация.
  ///
  /// ⚠ И двата църковнославянски превода получават „Заⷱ҇" — включително
  /// гражданският, комуто надредната буква строго погледнато е чужда.
  /// Изрично решение на потребителя (26.08.2026): текстът си е
  /// църковнославянски, само буквите са граждански, тъй че съкращението му
  /// подобава.
  String? _zachaloLabel(String lang, BibleRow row) {
    if (!BibleZachala.value) return null;
    final n = _zachala[row.verse];
    if (n == null) return null;
    final l = _languageOf(lang);
    final slavonic = l?.font == 'cslavonic' || l?.code == 'cs';
    return slavonic ? 'Заⷱ҇ $n' : 'Зач. $n';
  }

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
  /// ⚠ Интервалът след скобата влиза В ЧЕРВЕНОТО, за да не увисне черна
  /// шпация между зачалото и главната буква — двете трябва да се четат като
  /// един знак.
  ///
  /// ⚠ Текстът тук ВЕЧЕ Е ЧИСТ от вградено зачало — маха се на входа, в
  /// [BibleDb.chapter]. Дотук тази функция разпознаваше „[За…]" в самия низ
  /// и това ѝ беше най-заплетената част; сега зачалото има един-единствен
  /// път до екрана и правилото остава само едно.
  /// Парчетата на един рубрикиран стих.
  ///
  /// ⚠ Връща SPANS, а не готов `Text`, за да може маркирането на търсенето
  /// да мине ВЪРХУ тях ([_highlightSpans]). Инак двете рисуват едно и също
  /// място по два начина и второто трябва да преповтори първото — а
  /// рубрикацията е книжна конвенция с достатъчно правила, за да не се
  /// преписва.
  List<TextSpan> _rubricatedSpans(
    String text,
    ReaderPalette palette,
    String? zachalo,
  ) {
    final red = TextStyle(color: palette.wine);
    final spans = <TextSpan>[];

    if (zachalo != null) {
      spans.add(TextSpan(text: '[$zachalo] ', style: red));
    }

    if (text.isEmpty) return spans;

    final first = text.characters.first;
    final rest = text.characters.skip(1).toString();

    // Главна ли е: буквата се мени при снижаване, но не и при повдигане.
    // Тази проверка минава и за знаци без регистър (цифри, кавички) — те
    // остават в основния цвят, което е и желаното.
    final isCapital =
        first.toUpperCase() == first && first.toLowerCase() != first;

    if (isCapital) {
      spans.add(TextSpan(text: first, style: red));
      spans.add(TextSpan(text: rest));
    } else {
      spans.add(TextSpan(text: text));
    }

    return spans;
  }

  /// Разбива готови парчета по съвпаденията с търсеното.
  ///
  /// ⚠ Прилага се ВЪРХУ вече построените spans, а не вместо тях — тъй че
  /// червената главна буква и зачалото си остават червени, а намереното
  /// свети и в тях. Цената е, че съвпадение, ПРЕСИЧАЩО границата между две
  /// парчета (например първата буква и остатъка), не се улавя; в замяна
  /// нищо от книжния вид не се губи при търсене.
  ///
  /// ⚠ Цветовете са ОБЩИ с четците и с календара (`AppColors.hit*`) — виж
  /// бележката при [ReaderPalette]. Тук се избира по темата, защото
  /// Писанието се чете и в светла.
  List<InlineSpan> _highlightSpans(
    List<TextSpan> spans,
    String verse,
  ) {
    final terms = searchTerms(_markQuery);
    if (terms.isEmpty) return spans;

    // ⚠ СЪВПАДЕНИЯТА СЕ ТЪРСЯТ В СЛЕПЕНИЯ ТЕКСТ, не във всяко парче поотделно.
    //
    // Тук беше бъгът „намира го, брои го, но не го маркира": рубрикацията реже
    // стиха на ДВЕ парчета — червената главна буква и остатъка, — тъй че на
    // църковнославянски „Ї|и҃съ" пресича границата помежду им и търсено поотделно
    // във всяко, не се улавя никъде. А всеки цс стих започва точно така.
    //
    // ⚠ И ПО-ЛОШО ОТ НЕВИДИМОТО: [_runSearch] брои по ЦЕЛИЯ текст, тъй че
    // броячът показваше съвпадения, за които маркировка нямаше, и обхождането
    // спираше на празно място.
    final full = spans.map((s) => s.text ?? '').join();
    final ranges = matchRanges(full, terms);
    if (ranges.isEmpty) return spans;

    // Реже се по ОБЕДИНЕНИТЕ граници — на парчетата И на намереното. Така
    // едно съвпадение може да се раздели между две парчета, без да загуби нито
    // фона си, нито стила им: червената буква си остава червена, само че вече
    // и с фон под нея.
    final cuts = <int>{0, full.length};
    var at = 0;
    for (final s in spans) {
      at += (s.text ?? '').length;
      cuts.add(at);
    }
    for (final r in ranges) {
      cuts
        ..add(r.start)
        ..add(r.end);
    }
    final points = cuts.toList()..sort();

    final hitColor = ReaderTheme.dark ? AppColors.hitDark : AppColors.hitLight;
    final currentColor =
        ReaderTheme.dark ? AppColors.hitCurrentDark : AppColors.hitCurrentLight;
    final current = _currentHitVerse;

    /// Стилът на парчето, в което попада позицията.
    TextStyle? styleAt(int pos) {
      var start = 0;
      for (final s in spans) {
        final end = start + (s.text ?? '').length;
        if (pos < end) return s.style;
        start = end;
      }
      return spans.isEmpty ? null : spans.last.style;
    }

    /// Кое поред е съвпадението, покриващо позицията — или null.
    ///
    /// ⚠ Номерът е ГЛОБАЛЕН за стиха и брои същото, което брои [_runSearch] —
    /// затова „текущото" (оранжевото) винаги съвпада с брояча „3/20".
    int? hitAt(int pos) {
      for (var i = 0; i < ranges.length; i++) {
        if (pos >= ranges[i].start && pos < ranges[i].end) return i;
      }
      return null;
    }

    final out = <InlineSpan>[];
    for (var i = 0; i + 1 < points.length; i++) {
      final a = points[i], b = points[i + 1];
      if (a >= b) continue;
      final style = styleAt(a);
      final hit = hitAt(a);
      if (hit == null) {
        out.add(TextSpan(text: full.substring(a, b), style: style));
      } else {
        final isCurrent =
            current != null && current.$1 == verse && current.$2 == hit;
        out.add(TextSpan(
          text: full.substring(a, b),
          style: (style ?? const TextStyle())
              .copyWith(backgroundColor: isCurrent ? currentColor : hitColor),
        ));
      }
    }
    return out;
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
  /// ⚠ Броят се и редовете на ГРУПИТЕ. В режим „цитати" `_rows` е празен, тъй
  /// че само по него колонката оставаше широка колкото за две цифри — а
  /// цитат от Псалтира спокойно стига до три и номерът се отрязваше.
  double get _numberWidth {
    var digits = 2;
    for (final r in _rows) {
      if (r.verse.length > digits) digits = r.verse.length;
    }
    for (final g in _groups) {
      for (final r in g.rows) {
        if (r.verse.length > digits) digits = r.verse.length;
      }
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
    // ⚠ Липсва ли преводът за цялата глава, вместо низ от празни клетки стои
    // ЕДНА бележка — на мястото на първия стих, в неговата колона.
    if (_missingLangs.contains(lang)) {
      final rows =
          _groups.isNotEmpty ? [for (final g in _groups) ...g.rows] : _rows;
      final isFirst = rows.isNotEmpty && identical(rows.first, row);
      return isFirst
          ? _coverageNote(palette, lang)
          : const SizedBox.shrink();
    }
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

  /// ⚠ В КОЙ ПРЕВОД СЕ МАРКИРА. Търси се в АКТИВНИЯ (виж [_runSearch]) и
  /// броячът е негов, тъй че светенето трябва да е само там. Дотук светеха и
  /// двете колони, а числото беше на едната: на цс „са" дава 1065 съвпадения,
  /// на бг — 1775, и човек вижда осветени думи, които не са в сметката.
  ///
  /// ⚠ Изразът е СЪЩИЯТ като в [_runSearch] — нарочно, за да не могат
  /// броенето и маркирането да се разминат. Две различни сметки за „кой е
  /// активният" се разсинхронизират при първата промяна в едната.
  bool _marksLang(String lang) => lang == _shownCode(_pair, null);

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
      body = Text(
        '—',
        style: style.copyWith(color: palette.dim.withValues(alpha: .5)),
      );
    } else if ((language?.rubricate ?? false) ||
        _zachaloLabel(lang, row) != null ||
        (_markQuery.isNotEmpty && _marksLang(lang))) {
      // ⚠ Рубрикацията на ВСЕКИ стих (червена главна буква) си остава само
      // за църковнославянския — това е негова книжна конвенция, не украса.
      // Зачалото обаче се показва във всеки превод, тъй че стих СЪС зачало
      // минава оттук и на български: там червеното бележи не „начало на
      // стих", а „начало на богослужебно четиво", което важи еднакво.
      // ⚠ И БЕЗ рубрикация се минава оттук, щом се търси: пътят е един и
      // същ, само че при обикновен превод списъкът с парчета е едно-
      // единствено парче, върху което ляга маркирането.
      final rub = (language?.rubricate ?? false) ||
              _zachaloLabel(lang, row) != null
          ? _rubricatedSpans(verse.text, palette, _zachaloLabel(lang, row))
          : <TextSpan>[TextSpan(text: verse.text)];
      body = Text.rich(
        TextSpan(
            style: style,
            children: _marksLang(lang)
                ? _highlightSpans(rub, row.verse)
                : rub),
        textAlign: TextAlign.start,
      );
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

  /// ⚠ Ключът носи и КНИГАТА, и главата. В режим „цитати" на екрана стоят
  /// стихове от няколко места и номерата им се повтарят; само по номер два
  /// widget-а биха получили един и същ `GlobalKey`, а това е изключение по
  /// време на рисуване, не тиха грешка.
  ///
  /// ⚠ КНИГАТА беше добавена, когато режимът „цитати" пое и резултатите от
  /// търсене. Дотогава пасажите идваха от една препратка и почти винаги от
  /// една книга, тъй че „глава:стих" стигаше. Търсенето обаче връща „Мат.
  /// 5:9" и „Марк. 5:9" в един списък — и двата даваха ключ „5:9".
  /// Симптомът беше „Multiple widgets used the same GlobalKey" и отрязано
  /// дърво, тоест изчезнали резултати.
  GlobalKey _keyFor(String verse, [int? chapter, String? book]) =>
      _rowKeys.putIfAbsent(
          '${book ?? widget.bookCode}'
          ':${chapter ?? widget.chapter}:$verse',
          () => GlobalKey());

  BibleLanguage? _languageOf(String code) {
    for (final l in _langs) {
      if (l.code == code) return l;
    }
    return null;
  }

  // ── Търсене: логика ────────────────────────────────────────────────────

  void _toggleSearch() {
    setState(() {
      _searchOpen = !_searchOpen;
      if (!_searchOpen) {
        _searchCtrl.clear();
        _query = '';
        _hits = const [];
        _currentHit = 0;
      }
    });
  }

  /// Всички редове на екрана — в обикновено четене това е главата, в режим
  /// „цитати" са извадките, слети в един списък.
  List<BibleRow> get _visibleRows =>
      _groups.isNotEmpty ? [for (final g in _groups) ...g.rows] : _rows;

  /// Преброява намереното в показания текст.
  ///
  /// ⚠ Търси се в АКТИВНИЯ превод, не в двата — същото правило като при
  /// пълнотекстовото (виж `BibleSearchSettingsPanel`). В изправено положение
  /// на екрана и без това стои една колона.
  void _runSearch(String raw) {
    final q = raw.trim();
    final hits = <(String, int)>[];
    // ⚠ В режим „в текста" главата НЕ се пресява — намереното живее на друг
    // екран. Заявката все пак се помни, за да е готова, ако човек превключи
    // режима от панела: инак полето стои пълно, а нищо не свети.
    // Едно към едно с указателя ([BibleContents._runSearch]).
    final terms = searchTerms(q);
    if (terms.isNotEmpty &&
        BibleSearchSettings.where != BibleSearchWhere.text) {
      final lang = _shownCode(_pair, null);
      for (final row in _visibleRows) {
        final text = row[lang]?.text;
        if (text == null) continue;
        // ⚠ Броят СЪВПАДЕНИЯ, не стихове: обхождането води окото до всяко
        // място, а не само до всеки стих. Редът им е по позиция в текста —
        // [matchRanges] връща слятото и подредено, тъй че „‹ ›" вървят
        // отляво надясно, както се чете.
        for (var i = 0; i < matchRanges(text, terms).length; i++) {
          hits.add((row.verse, i));
        }
      }
    }
    setState(() {
      _query = q;
      _hits = hits;
      _currentHit = 0;
    });
    if (hits.isNotEmpty) _revealHit();
  }

  void _stepHit(int delta) {
    if (_hits.isEmpty) return;
    setState(() {
      _currentHit = (_currentHit + delta) % _hits.length;
      if (_currentHit < 0) _currentHit += _hits.length;
    });
    _revealHit();
  }

  /// Плъзга до текущото съвпадение.
  ///
  /// ⚠ Изчаква КАДЪР: маркирането се мести със `setState`, а скокът търси
  /// построения ред. Без изчакването се плъзга до предишното съвпадение —
  /// същият капан като в указателя ([BibleContents]).
  ///
  /// ⚠ И ПОВТАРЯ, вместо да се откаже. Проверено на устройството: първото
  /// намиране (докато клавиатурата още се вдига и лентата тъкмо е минала на
  /// `pinned`) не стигаше доникъде, а обхождането със стрелките после
  /// работеше безотказно — тоест редът е на мястото си, но точно в онзи миг
  /// геометрията още не е установена. Голо `return` тук е ТИХИЯТ ОТКАЗ,
  /// платен вече три пъти в този проект (виж CLAUDE.md).
  ///
  /// Спира при първото стигане: сравнява се позицията преди и след скока.
  Future<void> _revealHit([int attempt = 0]) async {
    final hit = _currentHitVerse;
    if (hit == null) return;
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || !_searchOpen) return;
    // Целта може да се е сменила, докато сме чакали (бързо натискане на ›).
    if (_currentHitVerse != hit) return;

    final before = _scroll.hasClients ? _scroll.offset : null;
    _jumpToVerse(hit.$1);

    if (attempt >= 5) return;
    // Стигнало ли е? `_jumpToVerse` мълчи, когато редът още го няма или
    // скролът няма позиция — затова се съди по резултата, не по връщането.
    await Future<void>.delayed(const Duration(milliseconds: 90));
    if (!mounted || !_searchOpen || _currentHitVerse != hit) return;
    final after = _scroll.hasClients ? _scroll.offset : null;
    if (before == null || after == null || before == after) {
      // ⚠ Равни позиции НЕ значат непременно провал — може вече да сме там.
      // Затова се пита геометрията: вижда ли се редът изобщо.
      final ctx = _keyFor(hit.$1).currentContext;
      final box = ctx?.findRenderObject() as RenderBox?;
      if (box != null && ctx!.mounted) {
        final dy = box.localToGlobal(Offset.zero).dy;
        final h = MediaQuery.of(context).size.height;
        if (dy >= 0 && dy < h) return; // вижда се — готово
      }
      unawaited(_revealHit(attempt + 1));
    }
  }

  void _clearSearch() {
    _searchCtrl.clear();
    setState(() {
      _query = '';
      _hits = const [];
      _currentHit = 0;
    });
  }

  void _openSearchSettings() {
    setState(() => _searchSettingsInDrawer = true);
    _scaffoldKey.currentState?.openEndDrawer();
  }

  /// Пълнотекстовото търсене — СЪЩОТО като в указателя, за да не се учи два
  /// пъти: настройката е обща, Enter го пуска, резултатите идват на свой
  /// екран.
  Future<void> _runTextSearch() async {
    final q = _searchCtrl.text.trim();
    if (q.isEmpty) return;
    final lang = _shownCode(_pair, null);

    // ⚠ ПРАЗЕН ПОИМЕНЕН ИЗБОР НЕ ЗНАЧИ „НАВСЯКЪДЕ". Празен списък книги е
    // уговорката за „цялото Писание" в [BibleDb.searchText] — тъй че при
    // обхват „в избрани книги" без нито една отметната търсенето би минало
    // през всичко, тоест точно обратното на поисканото. Спира се тук, с
    // обяснение накъде да се погледне.
    if (BibleSearchSettings.range == BibleSearchRange.picked &&
        BibleSearchSettings.pick.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Не са избрани книги за търсене.'),
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    setState(() => _searching = true);
    ({List<({String book, int chapter, String verse})> verses, int total}) found;
    try {
      found = await BibleDb.searchText(lang, q,
          books: _scopeBooks(), chapters: _scopeChapters());
    } finally {
      if (mounted) setState(() => _searching = false);
    }
    if (!mounted) return;

    if (found.verses.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Нищо не е намерено за „$q".'),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    final passages = groupFoundVerses(found.verses);
    final trimmed = found.total > found.verses.length;
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => BibleReader(
        bookCode: passages.first.book,
        chapter: passages.first.chapter,
        quotes: BibleRef(passages),
        // ⚠ „Намерени стихове", а не „Резултати от търсенето". Второто е
        // по-точно като смисъл, но при 21 знака се реже до „Резултати от
        // търсе…" между стрелката и трите копчета — мерено на устройството,
        // не на око. Тук пък застава броят, тъй че името и без това отстъпва
        // мястото си на него.
        resultsTitle: 'Намерени стихове',
        searchQuery: q,
        totalFound: found.total,
        resultsNote: trimmed
            ? 'От намерените ${found.total} стиха тук се отварят първите '
                '${found.verses.length}.'
            : null,
      ),
    ));
  }

  /// Обхватът по настройка. ⚠ В ЧЕТЕЦА „отвореният дял" се смята от КНИГАТА,
  /// която се чете, а не от таб — тук табове няма. Псалтирът е свой дял,
  /// защото и в указателя е свой.
  List<String> _scopeBooks() {
    switch (BibleSearchSettings.range) {
      case BibleSearchRange.all:
        return const [];
      case BibleSearchRange.picked:
        return BibleSearchSettings.pick.books.toList();
      case BibleSearchRange.tab:
        final book = _book;
        if (book == null) return const [];
        if (book.code == 'Ps') return const ['Ps'];
        return [
          for (final b in _allBooks)
            if (b.isOldTestament == book.isOldTestament) b.code
        ];
    }
  }

  Map<String, Set<int>> _scopeChapters() => scopeChaptersFor(
      BibleSearchSettings.range, BibleSearchSettings.pick);

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
    final pair = _pair;

    final actions = readerToolbarActions(
      context: context,
      onThemeToggle: () {
        // ⚠ Показаното контекстно меню („Копиране / Споделяне") се ПРИБИРА
        // при смяна на темата. То живее в Overlay и се строи ВЕДНЪЖ, при
        // показването си — тъй че `setState` тук не го докосва и то остава с
        // цветовете на старата тема, докато човек не маркира наново.
        //
        // По-честно е да си отиде: селекцията остава, менюто се вика пак с
        // един тап, а грешните цветове не се задържат на екрана.
        ContextMenuController.removeAny();
        setState(() => ReaderTheme.dark = !ReaderTheme.dark);
      },
      onFontSmaller: () => _bumpFont(-BibleFontSize.step),
      onFontBigger: () => _bumpFont(BibleFontSize.step),
      fontValue: BibleFontSize.value,
      fontMin: BibleFontSize.min,
      fontMax: BibleFontSize.max,
      onMore: _showMoreMenu,
      // ⚠ НА ЕКРАНА С РЕЗУЛТАТИ ЛУПАТА ОТПАДА. Там няма глава, в която да се
      // търси — стиховете са извадка от цяло Писание, — а мястото ѝ трябва
      // на заглавието: „Резултати от търсенето" не се побира между шест
      // копчета и се реже до „Резулт…".
      onSearch: widget.resultsTitle != null ? null : _toggleSearch,
      // ⚠ ПОСИВЕНА, а не махната, когато главата е отворена от намереното
      // („Чети в контекст"). Тук маркирането идва ОТВЪН и изпреварва полето
      // (виж [_markQuery]), тъй че ново търсене в същата глава просто не би
      // проработило. А и човек още не е излязъл от предишното търсене —
      // по-добре да не започва второ върху него.
      //
      // Посивена казва „има такова нещо, но не сега"; липсваща би оставила
      // лентата да изглежда различно на два съседни екрана.
      searchEnabled: widget.searchQuery == null,
    );

    // ⚠ ЗАГЛАВИЕТО ОБИКНОВЕНО НЕ Е ТУК. Мястото му е етикетът в изреза
    // ([_chapterSpine]) — там стои постоянно, докато лентата се скрива при
    // скрол. В лентата се връща САМО на устройство без изрез, където етикет
    // няма къде да се сложи; тогава по-добре отрязано име, отколкото
    // никакво.
    final title = _hasSpine
        ? const SizedBox.shrink()
        : Text(
            book == null ? '' : _headerLabel(book),
            // ⚠ СИСТЕМНИЯТ шрифт, не TamburinModern: лентата е управление,
            // не четиво, а Tamburin е за заглавия ВЪТРЕ в текста.
            style: const TextStyle(color: Colors.white, fontSize: 16),
            overflow: TextOverflow.ellipsis,
          );

    // ⚠ `LayoutBuilder`, за да се знае РЕАЛНАТА ширина на лентата. Тя не е
    // ширината на екрана: в легнало положение изрезът на камерата отнема
    // ляво поле през `SafeArea`, а лентата и текстът отдолу са ВЪТРЕ в
    // една и съща SafeArea, тъй че двете тръгват от една и съща нула.
    // Точно затова сметката по-долу може да сочи ръбовете на колоните.
    // ⚠ РЕЖИМЪТ НА ТЪРСЕНЕ ЗАМЕСТВА ЦЯЛАТА ЛЕНТА, в двете положения наведнъж.
    // Височината остава `kReaderToolbarHeight`, тъй че подредбата на екрана
    // не се мени — а точно от смяната на подредбата идваха компенсациите с
    // пиксели в другите два четеца.
    return SizedBox(
      height: kReaderToolbarHeight,
      child: _searchOpen
          ? _searchBar()
          : LayoutBuilder(
              builder: (context, c) => landscape
                  ? _landscapeBar(title, pair, actions, c.maxWidth)
                  : _portraitBar(title, pair, actions),
            ),
    );
  }

  /// Лентата в режим ТЪРСЕНЕ — на мястото на обикновената.
  ///
  /// ⚠ Всяко копче служи на режима, който е в сила: стрелката „назад" става
  /// ✕ (изход от търсенето, не от главата), „−/+" стават „‹/›", а трите
  /// точки — зъбно колело към настройките на търсенето. Изборът на превод и
  /// тогълът на темата отпадат: мястото им трябва на полето, а никой не
  /// сменя тема, докато търси дума.
  ///
  /// ⚠ Едно към едно с указателя ([BibleContents]). За човека това е ЕДНА
  /// търсачка, срещната на две места.
  Widget _searchBar() {
    const fg = Colors.white;
    final stepping = _stepping;
    final inText = BibleSearchSettings.where == BibleSearchWhere.text;

    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.close, color: fg),
          tooltip: 'Затвори търсенето',
          onPressed: _toggleSearch,
        ),
        Expanded(
          child: SizedBox(
            height: 38,
            child: TextField(
              controller: _searchCtrl,
              autofocus: true,
              style: const TextStyle(color: fg, fontSize: 15),
              textInputAction: TextInputAction.search,
              // ⚠ Търсенето В ГЛАВАТА върви с писането (то пресява шепа
              // стихове в паметта), а пълнотекстовото чака Enter — то чете
              // осем мегабайта и на всяка буква би заковало полето. Пътят е
              // един: [_runSearch] сам знае, че при „в текста" няма какво да
              // пресява, и само помни заявката.
              onChanged: _runSearch,
              onSubmitted: (_) {
                if (inText) unawaited(_runTextSearch());
              },
              decoration: InputDecoration(
                isDense: true,
                hintText:
                    inText ? 'в цялото Писание — Enter' : 'търси в главата',
                hintStyle: TextStyle(
                    color: fg.withValues(alpha: 0.45), fontSize: 13),
                contentPadding:
                    const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                filled: true,
                fillColor: Colors.black.withValues(alpha: 0.15),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                suffixIcon: _searchFieldSuffix(fg, inText),
                suffixIconConstraints:
                    const BoxConstraints(minWidth: 0, minHeight: 0),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        RoundIconButton(
          icon: Icons.chevron_left,
          tooltip: 'Предишно съвпадение',
          enabled: stepping,
          size: kReaderBtnSize,
          onTap: () => _stepHit(-1),
        ),
        const SizedBox(width: 14),
        RoundIconButton(
          icon: Icons.chevron_right,
          tooltip: 'Следващо съвпадение',
          enabled: stepping,
          size: kReaderBtnSize,
          onTap: () => _stepHit(1),
        ),
        const SizedBox(width: 8),
        Tooltip(
          message: 'Настройки на търсенето',
          child: InkWell(
            onTap: _openSearchSettings,
            customBorder: const CircleBorder(),
            child: const Padding(
              padding: EdgeInsets.all(6),
              child: Icon(Icons.tune, size: 24, color: fg),
            ),
          ),
        ),
        const SizedBox(width: 2),
      ],
    );
  }

  /// Десният край на полето: кръгче при чакане, лупа при празно, брояч с ✕
  /// при писане.
  Widget _searchFieldSuffix(Color fg, bool inText) {
    if (_searching) {
      return Padding(
        padding: const EdgeInsets.only(right: 12, left: 8),
        child: SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(
              strokeWidth: 2, color: fg.withValues(alpha: 0.6)),
        ),
      );
    }
    // ⚠ В режим „в текста" брояч няма какво да брои — намереното живее на
    // друг екран. Тогава остава лупата, а не „0/0", което би значело
    // „търсих и не намерих".
    if (_query.isEmpty || inText) {
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

  /// Лентата в ИЗПРАВЕНО положение.
  ///
  /// ⚠ Заглавието е `Expanded`, а НЕ `Flexible` до `Spacer()`. Дотогава
  /// двете деляха остатъка по равно и при пълен ред бутони на заглавието
  /// оставаха под 40 dp — толкова, че да не се изпише ИЗОБЩО. Отвън
  /// изглеждаше, че четецът просто няма заглавие: между стрелката и „бг"
  /// зееше празно и човек нямаше как да разбере коя глава чете.
  Widget _portraitBar(
    Widget title,
    BibleLanguagePair pair,
    List<Widget> actions,
  ) {
    return Row(
      children: [
        // ⚠ Цветът се взима ИЗРИЧНО от лентата, а НЕ от темата на четеца.
        // Фонът тук е закован тъмен (`AppColors.toolbar`) и не се мени със
        // светла/тъмна тема — а `BackButton` без цвят пита темата и в светла
        // ставаше тъмен върху тъмно, тоест изглеждаше изгаснал.
        //
        // Същият израз, с който `reader_toolbar.dart` оцветява останалите
        // иконки в лентата — така стрелката не може да се разсинхронизира с
        // тях при бъдеща промяна.
        BackButton(
          color: AppBarTheme.of(context).foregroundColor ?? Colors.white,
        ),
        // ⚠ БЕЗ отстъп след стрелката. `BackButton` е 48 широк, а иконката в
        // него е 24 и стои центрирана — тоест вдясно от глифа вече има 12
        // празни. Добавени още 8 отгоре, заглавието тръгваше на 62 dp, при
        // положение че текстът на стиха под него започва на 48. Разликата се
        // виждаше като разместена лява граница между лентата и четивото.
        Expanded(child: title),
        // ⚠ СЛУША `_slide`. Изборът тук е ЕДИН и трябва да сочи превода,
        // който в момента е на екрана — а в изправено положение това се мени
        // с плъзгането, не с натискане.
        //
        // `_shownCode` открай време чете `_slide` (виж бележката при него),
        // но лентата не се преизграждаше при движение: `_slide` е
        // `AnimationController`, а него го слушаше само плъзгащата се колона
        // (`_slidingColumn`). Тъй че текстът се сменяше, а надписът над него
        // оставаше стар — и по-лошо: изборът от менюто заменяше ДРУГАТА
        // половина от двойката, защото `_pickLanguage` получава същия
        // остарял `shown`.
        //
        // ⚠ Обвивката е САМО тук, в изправено. В легнало менютата са две и
        // всяко си знае колоната изрично (`column` 0/1) — там `_slide` няма
        // никакво значение и слушане би било грешка, защото плъзгане в
        // легнало изобщо няма.
        AnimatedBuilder(
          animation: _slide,
          // ⚠ НА ЕКРАНА С РЕЗУЛТАТИ изборът на превод отпада. Намереното е
          // намерено в ЕДИН превод — онзи, който човек е чел, — тъй че
          // смяната му тук би показала стихове на език, на който никой не е
          // търсил. А мястото трябва на заглавието: с бутона до себе си
          // „Резултати от търсенето" се режеше до „Резултати от…".
          builder: (context, _) => widget.resultsTitle != null
              ? const SizedBox.shrink()
              : _languageButton(pair, null),
        ),
        // ⚠ 4, а не 8 или 16 — и сметката НЕ е „колкото между бутоните".
        //
        // Изборът на превод носи СВОЙ вътрешен отстъп от 8, а стрелчицата му
        // (`arrow_drop_down`, 18) е триъгълник в кутия, тъй че вдясно от
        // самия глиф стоят още към 4 празни. Тоест 16 отгоре даваха ВИДИМА
        // дупка от близо 28 — двойно спрямо 16-те между иконките — и точно
        // затова контролът изглеждаше „изтеглен наляво" от групата. 4 + 8 + 4
        // изравнява оптически, а освободеното отива при заглавието.
        const SizedBox(width: 4),
        ...actions,
      ],
    );
  }

  /// Лентата в ЛЕГНАЛО положение — с двата избора на превод НАД колоните им.
  ///
  /// ⚠ Геометрията се ИЗВЕЖДА от същите числа, които редят и стиховете
  /// отдолу ([_numberWidth], [_kNumberGap], отстъпът на `SliverPadding`,
  /// полето около чертата), а не се нагажда на око. Смени ли се утре някое
  /// от тях, менютата се преместват заедно с колоните.
  ///
  /// ⚠ И НЕ Е `Stack` върху лентата. Такъв беше първият опит: слоят ляга
  /// ВЪРХУ бутоните и надписите се застъпват с полумесеца и с минуса.
  /// Вместо това лявата половина е кутия с ТОЧНА ширина — от края на
  /// стрелката до десния ръб на лявата колона — в която заглавието стои
  /// отляво, а изборът се долепя отдясно. Така подравняването е точно, без
  /// нищо да се качва върху нищо.
  Widget _landscapeBar(
    Widget title,
    BibleLanguagePair pair,
    List<Widget> actions,
    double barWidth,
  ) {
    // Огледало на подредбата в `_parallelColumns`.
    const pad = 16.0; // SliverPadding отляво/отдясно
    const dividerBox = 25.0; // чертата (1) + полето ѝ (12 + 12)
    final columnWidth =
        (barWidth - 2 * pad - _numberWidth - _kNumberGap - dividerBox) / 2;
    // Докъде стига текстът на ЛЯВАТА колона, мерено от левия ръб на лентата.
    final leftColumnRight = pad + _numberWidth + _kNumberGap + columnWidth;

    // Мястото, което стрелката „назад" вече е заела.
    const backWidth = kMinInteractiveDimension + 8;
    final headWidth = leftColumnRight - backWidth;

    // Не се ли събира (много едър шрифт, тесен екран), се пада към
    // изправената подредба, вместо да излезе отрицателна ширина.
    if (headWidth < 80 || columnWidth < 80) {
      return _portraitBar(title, pair, actions);
    }

    return Row(
      children: [
        // ⚠ Цветът се взима ИЗРИЧНО от лентата, а НЕ от темата на четеца.
        // Фонът тук е закован тъмен (`AppColors.toolbar`) и не се мени със
        // светла/тъмна тема — а `BackButton` без цвят пита темата и в светла
        // ставаше тъмен върху тъмно, тоест изглеждаше изгаснал.
        //
        // Същият израз, с който `reader_toolbar.dart` оцветява останалите
        // иконки в лентата — така стрелката не може да се разсинхронизира с
        // тях при бъдеща промяна.
        BackButton(
          color: AppBarTheme.of(context).foregroundColor ?? Colors.white,
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: headWidth,
          child: Row(
            children: [
              Expanded(child: title),
              _languageButton(pair, 0),
            ],
          ),
        ),
        const SizedBox(width: dividerBox),
        _languageButton(pair, 1),
        const Spacer(),
        ...actions,
      ],
    );
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
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => BibleReader(bookCode: target.$1, chapter: target.$2),
      ),
    );
  }

  /// Адресът на ТАЗИ глава в azbyka.ru — откъдето е свален целият текст.
  ///
  /// Строи се машинно, по същия шаблон, с който конвейерът е теглил
  /// главите (`BASE_URL` в `02_fetch_chapters.py`):
  ///
  ///     https://azbyka.ru/biblia/?{книга}.{глава}&{езици}
  ///
  /// ⚠ `books.code` В БАЗАТА Е ТОЧНО КЛЮЧЪТ НА AZBYKA („Mt", „Ps", „Gen") —
  /// така е замислена колоната, тъй че тук не трябва никакво преобразуване.
  ///
  /// ⚠ ДВАТА ПОКАЗАНИ ПРЕВОДА ОТИВАТ ЗАЕДНО, разделени с „~" — това е
  /// собственият език на сайта за успоредно четене (`?Ps.111:2&bg~utfcs`,
  /// същият вид адрес, който стои и в томовете по св. Димитрий Ростовски).
  /// Тъй че страницата отсреща показва същата двойка, която човек чете тук.
  String? _azbykaUrl() {
    final book = _book;
    if (book == null) return null;
    final langs = BibleLanguages.value.both.join('~');
    return 'https://azbyka.ru/biblia/?${book.code}.${widget.chapter}&$langs';
  }

  /// Адресът на ТАЗИ книга в pravoslavieto.com — откъдето е взет
  /// СЪВРЕМЕННИЯТ БЪЛГАРСКИ текст (виж `tools/bible_bg/`).
  ///
  /// ⚠ Към КНИГАТА, не към главата: там една книга стои в един файл, с
  /// всичките си глави наведнъж — обратно на azbyka.ru, където една
  /// страница е една глава.
  ///
  /// ⚠ Пътят идва от изброена карта ([kPravoslavietoBookPaths]), а не се
  /// сглобява по схема: имената на файловете там нямат закономерност
  /// (`2Car` е с главна буква, другите Царства — с малка).
  String? _pravoslavietoUrl() {
    final book = _book;
    if (book == null) return null;
    final path = kPravoslavietoBookPaths[book.code];
    if (path == null) return null;
    return 'https://www.pravoslavieto.com/bible/$path.htm';
  }

  /// Опашката под четивото — ОБЩИЯТ [ReaderFooter], същият като в четеца на
  /// книги: същите бутони, същите надписи, същите разстояния.
  Widget _footer(ReaderPalette palette) {
    final prev = _adjacentChapter(-1);
    final next = _adjacentChapter(1);
    final azbyka = _azbykaUrl();
    final pravoslavieto = _pravoslavietoUrl();

    // ⚠ ДВА ИЗТОЧНИКА, защото текстът наистина идва от две места:
    // съвременният български е сверен по pravoslavieto.com (виж
    // `tools/bible_bg/` — 5311 подменени стиха), а всички останали преводи
    // са от azbyka.ru.
    //
    // ⚠ azbyka.ru ОСТАВА винаги, дори когато на екрана е само българският:
    // той никога не стои сам — показват се по два превода наведнъж, а
    // отсрещният е оттам.
    final sources = <FooterSource>[
      if (pravoslavieto != null)
        FooterSource(
          prefix: 'за съвременния български:',
          name: 'pravoslavieto.com',
          onTap: () => openExternal(context, pravoslavieto),
        ),
      if (azbyka != null)
        FooterSource(
          prefix: 'за останалите текстове:',
          name: 'azbyka.ru',
          onTap: () => openExternal(context, azbyka),
        ),
    ];

    return ReaderFooter(
      color: palette.dim,
      sources: sources.isEmpty ? null : sources,
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
      setState(() => _searchSettingsInDrawer = false);
      _scaffoldKey.currentState?.openEndDrawer();
    }
  }

  /// Коя ПОЛОВИНА от двойката е под фокус: 0 = лявата, 1 = дясната.
  ///
  /// ⚠ В ИЗПРАВЕНО ИСТИНАТА Е `_slide`, НЕ `pair.active`. Двете обикновено
  /// съвпадат, но `active` се записва чак когато плъзгането се доиграе
  /// (`_settleSlide`), а дотогава — и след това, ако нищо не е предизвикало
  /// ново построяване — уловената в лентата двойка носи СТАРАТА стойност.
  /// Плъзгачът, обратно, винаги показва къде реално е човекът.
  int _focusedSlot(int? column) => column ?? (_slide.value >= 0.5 ? 1 : 0);

  /// Прилага избор от менюто върху превода, който е в полето.
  ///
  /// ⚠ ДВОЙКАТА СЕ ЧЕТЕ НАНОВО, а не се ползва подадената.
  ///
  /// Тук беше бъгът, който се държеше половин ден: в ЛЯВАТА колона всичко
  /// работеше, а в ДЯСНАТА всяка смяна на език те връщаше вляво и на екрана
  /// не се виждаше никаква промяна.
  ///
  /// Причината: `_toolbar` улавя `pair` при построяване. След плъзгане
  /// `_settleSlide` записва новото `active`, но `_onLanguageChanged` в клона
  /// „същата двойка" НЕ вика `setState` — само анимира плъзгача. Тъй че
  /// лентата продължаваше да носи двойка със старото `active: 0`, а
  /// `copyWith` го пренаписваше обратно върху новата. В лявата колона нулата
  /// съвпада с истината по случайност; в дясната — не.
  ///
  /// ⚠ И `active` СЕ ЗАДАВА ИЗРИЧНО, а не се наследява. Така изборът на език
  /// не просто не разваля позицията, а ПОПРАВЯ евентуално разминаване:
  /// каквото и да е било записано, след избора то сочи колоната, в която
  /// човек стои. Инак същият клас грешка може да се върне през друг път.
  ///
  /// ⚠ Избере ли се превод, който вече заема ДРУГАТА половина, двете се
  /// РАЗМЕНЯТ вместо да станат еднакви — инак плъзгането не води наникъде.
  /// Човекът пак остава в своята колона и вижда точно избраното.
  void _pickLanguage(String code, int? column) {
    final pair = BibleLanguages.value;
    final slot = _focusedSlot(column);
    final shown = slot == 0 ? pair.first : pair.second;
    final other = slot == 0 ? pair.second : pair.first;
    if (code == shown) return;

    if (code == other) {
      BibleLanguages.set(
        BibleLanguagePair(first: pair.second, second: pair.first, active: slot),
      );
      return;
    }
    BibleLanguages.set(
      slot == 0
          ? pair.copyWith(first: code, active: slot)
          : pair.copyWith(second: code, active: slot),
    );
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
      onSelected: (code) => _pickLanguage(code, column),
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
                  child: Text(
                    l.abbr,
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
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
            //
            // ⚠ ЧИСТО БЯЛО, колкото иконките до него. На `white70` то беше
            // единственото приглушено нещо в лента, в която всичко останало
            // е бяло — а приглушеното сред ярко се чете като ИЗКЛЮЧЕНО.
            // Стрелчицата остава по-тиха: тя е указател към менюто, не
            // самото сведение.
            Text(
              current?.abbr ?? '—',
              style: const TextStyle(color: Colors.white, fontSize: 15),
            ),
            const Icon(Icons.arrow_drop_down, color: Colors.white70, size: 18),
          ],
        ),
      ),
    );
  }
}
