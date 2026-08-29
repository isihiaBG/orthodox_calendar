// bible_contents.dart
//
// Съдържанието на секцията „Библия" — входът към четеца.
//
// ⚠ ЗАЩО МАТРИЦА, А НЕ СПИСЪК. Заглавията на главите в Писанието са просто
// НОМЕРА. Изсипани в отвесен списък, 151-те псалма заемат петнайсет екрана,
// на всеки ред стои една цифра и останалите девет десети от ширината зеят.
// Търсенето на глава 97 се превръща в дълго превъртане.
//
// Затова главите се подреждат в решетка — редове и колони, четени отляво
// надясно и отгоре надолу, както човек чете. Цялата книга се събира на един
// екран и окото стига до всяка глава наведнъж, вместо да я гони.
//
// Книгите ОСТАВАТ списък: имената им са думи с различна дължина и в решетка
// биха се резали.
//
// Табовете (Нов завет / Стар завет / Псалтир) са отделени, защото това са
// три съвсем различни навика на четене. Псалтирът е свой таб не защото е
// отделна книга — той е част от Стария завет — а защото се отваря по няколко
// пъти на ден и не бива да се търси всеки път надолу в списъка.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_drawer.dart';
import 'app_theme.dart';
import 'bible_db.dart';
import 'bible_language_pair.dart';
import 'bible_reader.dart';
import 'bible_book_groups.dart';
import 'bible_ref.dart';
import 'bible_search_panel.dart';
import 'bible_search_settings.dart';
import 'bible_settings.dart';
import 'kathisma.dart';
import 'reader_font_size.dart';
import 'reader_more_menu.dart';
import 'reader_toolbar.dart';
import 'settings_screen.dart';
import 'round_icon_button.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Едно съвпадение в указателя.
///
/// ⚠ Пази ТЕКСТА, с който редът да се покаже, а не само къде е — при
/// съвпадение в пълното име редът показва него вместо късата форма (виж
/// [_BibleContentsState._runSearch]).
class _TocHit {
  /// Код на книга („Mt") или ключ на катизма („k5") — по него редът се
  /// разпознава при рисуване.
  final String key;
  final String text;

  const _TocHit({required this.key, required this.text});
}

/// Най-малката страна на клетка в решетката. Клетките се разтеглят, за да
/// напълнят ширината, но не слизат под това — под ~44 не се уцелват с палец.
const double _kCellMin = 46.0;
const double _kCellGap = 6.0;

/// Височината на реда с книга в списъка.
///
/// ⚠ ЗАДАВА СЕ КАТО ПОД, а не като отстъп отгоре и отдолу. Отстъпът се
/// пресмята наум и се разминава щом заглавието се пренесе на два реда
/// („Премъдрост Соломонова"); подът важи и в двата случая — къс ред застава
/// точно на 44, дълъг пораства колкото трябва.
///
/// 44 не е избрано на око: това е размерът, който проектът вече е приел за
/// „уцелва се с палец" — бутоните в опашката на четеца
/// (reader_footer.dart) и височината на лентата с инструменти
/// (kReaderToolbarHeight). По-ниско тук значи, че списък от 50 книги става
/// по-къс за скролване, но по-труден за натискане; това е подът.
const double _kBookRowMinHeight = 40.0;

/// Въздухът около разделителната линия пред нов дял.
///
/// ⚠ ЧЕРТАТА ПРИНАДЛЕЖИ НА ЗАГЛАВИЕТО ПОД НЕЯ, не на дяла над нея. Двете
/// заедно казват „тук започва нов дял"; черта, увиснала по средата между два
/// дяла, не казва нищо и само шуми.
///
/// Оттам и посоката на числата: НАД чертата въздухът е голям (там наистина
/// свършва предишният дял), ПОД нея — малък. Стълбицата е низходяща и всяка
/// следваща връзка е по-тясна от предишната:
///
///     [последна книга]  ──20──  ═══ черта ═══  ──10──  ЗАГЛАВИЕ  ──6──  [първа книга]
///
/// Дотук беше обратното (10 над, 22 под) и заглавието изглеждаше откъснато
/// от собствената си черта, а тя — залепена за предишния дял.
///
/// ⚠ Мери се и с ОПТИЧНИЯ въздух: редът с книга е с под 40, а текстът в него
/// е центриран, тъй че под него остават още към 9 празни. Затова 20 отгоре
/// изглеждат като 29, а 10 отдолу — като 13.
const double _kAirAboveRule = 20.0;
const double _kRuleToHeading = 10.0;


/// Дял от указателя: заглавие и книгите под него.
// ⚠ Дяловете живеят в bible_book_groups.dart — общи са с екрана за
// избор на обхват на търсенето (bible_scope_screen.dart).
class BibleContents extends StatefulWidget {
  /// С кой таб да се отвори — 0 Нов завет, 1 Стар завет, 2 Псалтир.
  ///
  /// Подава го въвеждащият екран с трите корици
  /// (bible_welcome_screen.dart). Влезе ли се без него — изключен е от
  /// настройките — остава Новият завет, най-четеният.
  final int initialTab;

  /// Да НЕ пали системната лента при излизане.
  ///
  /// ⚠ Точно като [BookReader.keepImmersiveOnExit] и по същата причина: щом
  /// оттук се излиза към екран, който сам стои без лента (въвеждащите корици),
  /// паленето тук е само едно премигване — следващият я гаси веднага.
  /// Подава се `true` САМО когато сме дошли от кориците.
  final bool keepImmersiveOnExit;

  const BibleContents({
    super.key,
    this.initialTab = 0,
    this.keepImmersiveOnExit = false,
  });

  @override
  State<BibleContents> createState() => _BibleContentsState();
}

class _BibleContentsState extends State<BibleContents>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs =
      TabController(length: 3, vsync: this, initialIndex: widget.initialTab);

  List<BibleBook> _books = const [];
  bool _loading = true;
  String? _error;

  /// Разгърнатата в момента книга — под нея се показва решетката с главите.
  /// Само една наведнъж: две отворени решетки объркват коя чия е.
  String? _openBook;

  /// Кои глави РЕАЛНО ги има за показвания превод. Клетка без текст зад себе
  /// си стои приглушена и не се натиска — по-добре, отколкото да отвори
  /// празен екран.
  /// Наличните псалми. ⚠ ОТДЕЛНО поле, а не общото [_available].
  ///
  /// Табът „Псалтир" показва решетката си винаги, без да минава през списък,
  /// тъй че отначало я отваряше сам чрез addPostFrameCallback в build().
  /// Това беше грешка от учебникарски вид — СТРАНИЧЕН ЕФЕКТ В ПОСТРОЯВАНЕТО:
  /// `TabBarView` строи и съседния таб, тъй че при всеки кадър псалтирът
  /// пренаписваше `_openBook` обратно на „Ps" и отменяше избора на
  /// потребителя в другия таб. Отвън изглеждаше, че тапът върху книга ПРОСТО
  /// НЕ РАБОТИ — без грешка, без изключение, без следа в лога.
  Set<int> _psalms = const {};

  /// Коя катизма е разгъната в таба „Псалтир". Отделно от [_openBook] —
  /// двата таба се разгъват независимо и не бива да се засичат.
  String? _openKathisma;

  /// Последно отваряното четиво ЗА ВСЕКИ ТАБ поотделно — „Mt:5", „Gen:1",
  /// „Ps:50".
  ///
  /// ⚠ По таб, а не общо. Трите таба обслужват три различни навика: в Новия
  /// завет човек чете подред, в Стария търси книга, а в Псалтира се връща
  /// към позната катизма. Едно общо място щеше да размества и трите при
  /// всяко отваряне на което и да е.
  final Map<int, String> _lastRead = {};

  static const List<String> _lastReadKeys = [
    'bible_toc_last_nt',
    'bible_toc_last_ot',
    'bible_toc_last_ps',
  ];

  /// Ключ на реда, до който да се плъзне след отваряне на таба.
  /// ⚠ Нужен е, за да отваря менюто зад трите точки `endDrawer`-а с
  /// настройките — същият похват като в трите четеца. Панелът стои НАД
  /// указателя и не го затваря, тъй че промяна в него трябва да стигне
  /// дотук през слушател, а не през ново построяване.
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  final Map<int, GlobalKey> _anchorKeys = {};

  /// Скролът на всеки таб поотделно.
  ///
  /// ⚠ СВОЙ контролер за всеки, а не общият `PrimaryScrollController`: трите
  /// списъка живеят наведнъж в `TabBarView` и един контролер, закачен за
  /// няколко скрола, гърми („multiple ScrollPositions").
  ///
  /// Нужни са, за да може [_revealAnchor] да СКОЧИ по оценка и да принуди
  /// мързеливия списък да построи далечния ред — виж бележката там.
  final Map<int, ScrollController> _scrollers = {};

  /// Плоският списък от редове на всеки таб, какъвто е построен последно.
  /// Пази се, за да може оценката в [_estimatedAnchorOffset] да преброи
  /// редовете преди запомнения, без да ги сглобява наново.
  final Map<int, List<Object>> _rowsForTab = {};

  bool _restored = false;

  // ── Търсене в указателя ────────────────────────────────────────────────
  //
  // ⚠ ТЪРСИ СЕ САМО В ТЕКУЩИЯ ТАБ, и съвпаденията се смятат наново при
  // всяко превключване. Трите таба са три различни навика на четене (виж
  // бележката най-горе), тъй че общ списък с резултати през всичките би
  // изкарал човека от дяла, в който търси. Затова и броячът „3/8" се
  // отнася за таба пред очите му, а не за цялото Писание.

  /// Отворено ли е полето за търсене. Докато е `true`, лентата е в другия
  /// си режим: заглавието отстъпва мястото си на полето, хамбургерът става
  /// ✕, а „−/+" стават „‹/›".
  bool _searchOpen = false;

  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';
  List<_TocHit> _hits = const [];
  int _currentHit = 0;

  /// Върви ли в момента заявка към базата (пълнотекстовото търсене).
  bool _searching = false;

  /// Закача се за реда с ТЕКУЩОТО съвпадение — единственият, до който се
  /// плъзга. Същият похват като котвата на последно четеното: един ключ,
  /// местен по списъка, вместо ключ на всеки ред.
  final GlobalKey _hitKey = GlobalKey();

  /// Кой ред носи `_hitKey` в момента — код на книга или ключ на катизма.
  String? get _currentHitKey =>
      _hits.isEmpty ? null : _hits[_currentHit.clamp(0, _hits.length - 1)].key;

  ScrollController _scrollerFor(int tab) =>
      _scrollers.putIfAbsent(tab, ScrollController.new);

  @override
  void initState() {
    super.initState();
    // ⚠ Системната лента се гаси ТУК, при влизане в секцията, и се пали
    // обратно в dispose(). Четецът също я гаси, но НЕ я пали при излизане —
    // връща се насам, където тя пак трябва да е скрита. Палене и гасене
    // между два съседни екрана се вижда като премигване (CLAUDE.md).
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    // ⚠ Всеки таб пази СВОЕ място, тъй че връщането се задейства при всяко
    // превключване, не само веднъж при отваряне.
    _tabs.addListener(() {
      if (_tabs.indexIsChanging) return;
      // ⚠ При активно търсене резултатите СЕ ПРЕСМЯТАТ, а не се пазят: те са
      // на текущия таб (виж бележката при [_searchOpen]). Връщането към
      // последно четеното се пропуска — човек, който търси, не иска да го
      // отнесат при друг ред точно докато гледа намереното.
      if (_searchOpen) {
        _runSearch(_query);
        return;
      }
      _restored = false;
      _restoreLastRead();
    });
    _load();
  }

  @override
  void dispose() {
    if (!widget.keepImmersiveOnExit) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    for (final c in _scrollers.values) {
      c.dispose();
    }
    _tabs.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final langs = await BibleDb.languages();
      await BibleLanguages.loadOnce([for (final l in langs) l.code]);
      final books = await BibleDb.books();
      await BibleTocFontSize.loadOnce();
      // Настройките на секцията се прочитат ТУК, на входа ѝ — четецът се
      // отваря само оттук и заварва стойността готова.
      await BibleZachala.loadOnce();
      await BibleSearchSettings.loadOnce();
      final prefs = await SharedPreferences.getInstance();
      for (var t = 0; t < _lastReadKeys.length; t++) {
        final v = prefs.getString(_lastReadKeys[t]);
        if (v != null) _lastRead[t] = v;
      }
      // Псалтирът се отваря веднага при влизане в своя таб, тъй че наличните
      // му глави се четат наред с указателите, а не при построяване.
      final psalms = await BibleDb.availableChapters(
          'Ps', BibleLanguages.value.activeCode);
      if (!mounted) return;
      setState(() {
        _books = books;
        _psalms = psalms;
        _loading = false;
      });
      _restoreLastRead();
    } catch (e) {
      if (!mounted) return;
      // Грешката се различава от празното — виж бележката в bible_reader.
      setState(() {
        _loading = false;
        _error = 'Не мога да отворя Писанието: $e';
      });
    }
  }

  /// Кой таб отговаря на дадена книга.
  int _tabFor(String bookCode) {
    if (bookCode == 'Ps' && _tabs.index == 2) return 2;
    for (final b in _books) {
      if (b.code == bookCode) return b.isOldTestament ? 1 : 0;
    }
    return 0;
  }

  bool _isLastRead(String bookCode, int chapter) =>
      _lastRead[_tabFor(bookCode)] == '$bookCode:$chapter';

  void _rememberLastRead(String bookCode, int chapter) {
    final tab = _tabFor(bookCode);
    final value = '$bookCode:$chapter';
    setState(() => _lastRead[tab] = value);
    SharedPreferences.getInstance()
        .then((p) => p.setString(_lastReadKeys[tab], value));
  }

  /// Разгъва запомненото и плъзга до него.
  ///
  /// ⚠ Плъзгането става СЛЕД кадър и през `ensureVisible` по ключа на реда,
  /// а не с пресметнат офсет: редовете са с различна височина (заглавия на
  /// дялове, двуредови имена, разгъната решетка) и всяка сметка наум се
  /// разминава при първата промяна в оформлението.
  void _restoreLastRead() {
    if (_restored) return;
    _restored = true;
    final tab = _tabs.index;
    final last = _lastRead[tab];
    if (last == null) return;
    final book = last.split(':').first;

    setState(() {
      if (tab == 2) {
        final psalm = int.tryParse(last.split(':').last) ?? 1;
        final k = KathismaTable.forPsalm(psalm);
        _openKathisma = k == null ? 'extra' : 'k${k.number}';
      } else {
        _openBook = book;
      }
    });

    // ⚠ Дотук тук се питаше кои глави ги има за активния превод, за да се
    // сивеят останалите. Клетките вече са ВИНАГИ живи (виж `_chapterGrid`),
    // тъй че заявката отпадна заедно със сивото — пътьом спестява по едно
    // четене при всяко отваряне на книга.

    WidgetsBinding.instance
        .addPostFrameCallback((_) => unawaited(_revealAnchor(tab, 0)));
  }

  /// Плъзга до запомнения ред — ДОРИ КОГАТО ТОЙ ОЩЕ НЕ Е ПОСТРОЕН.
  ///
  /// ⚠ ТИХИЯТ ОТКАЗ. Дотук тук стоеше голо
  ///
  ///     if (ctx == null) return;   // ← нищо не се случва
  ///
  /// и заради него връщането работеше САМО за книги в горната част на
  /// списъка. `ListView.builder` е МЪРЗЕЛИВ: строи единствено видимото плюс
  /// малко около него, тъй че `GlobalKey.currentContext` на ред, който стои
  /// двайсет книги по-надолу, е `null` в мига на връщането. Списъкът
  /// оставаше в началото, без грешка и без следа в лога — отвън изглеждаше,
  /// че запомнянето просто не работи за далечните книги.
  ///
  /// Същият клас бъг като при четеца на жития (виж CLAUDE.md, „Тихият отказ
  /// при връщане на позицията"), и лекът е същият, двуфазен:
  ///
  ///   1. няма ли го реда — плъзга се по ОЦЕНКА, което пътьом го построява;
  ///   2. после се опитва пак, и построи ли се, минава точната сметка на
  ///      `ensureVisible`, тъй че оценката става без значение.
  ///
  /// ⚠ ПЛЪЗГА СЕ ВИДИМО, не се скача. Дотук първата фаза беше `jumpTo` —
  /// мигновен, защото целта му беше само да принуди построяването. Отвън
  /// обаче това изглежда като телепортиране: списъкът се появява отгоре и в
  /// същия миг е някъде другаде, без човек да е видял накъде е тръгнал и
  /// колко далеч е стигнал. Загубва се и усетът къде се намира в книгата.
  ///
  /// Същото правило вече важи за съдържанието на „Месецослов" (CLAUDE.md:
  /// „списъкът се ПЛЪЗГА до него ВИДИМО … самото движение е подсещането").
  /// Тук печели двойно: `animateTo` минава през междинните позиции, тъй че
  /// мързеливият списък строи редовете по пътя — тоест видимото движение и
  /// принуждаването на построяването са едно и също нещо.
  ///
  /// Таван от осем опита, за да не се върти безкрайно, ако редът изобщо го
  /// няма (изтрита книга в запомнения ключ).
  Future<void> _revealAnchor(int tab, int attempt) async {
    // Смени ли човек таба, докато опитваме — този опит вече не е желан.
    if (!mounted || _tabs.index != tab) return;

    final ctx = _anchorKeys[tab]?.currentContext;
    if (ctx != null) {
      await Scrollable.ensureVisible(
        ctx,
        alignment: 0.15,
        // ⚠ След плъзгане остатъкът е няколко точки, тъй че тук движението
        // е ДОНАМЕСТВАНЕ, не пътуване — иначе се вижда като второ, излишно
        // потегляне веднага след първото.
        duration: Duration(milliseconds: attempt == 0 ? 420 : 200),
        curve: Curves.easeOutCubic,
      );
      return;
    }
    if (attempt >= 8) return;

    final target = _estimatedAnchorOffset(tab);
    if (target == null) return; // няма какво да търсим — истински край

    final ctrl = _scrollers[tab];
    // ⚠ ОЩЕ ЕДИН ТИХ ОТКАЗ, ако тук стоеше `return`. При смяна на таб
    // `TabBarView` строи новата страница чак на следващия кадър, тъй че
    // контролерът ѝ още няма закачена позиция. Това е „не сега", а не
    // „никога" — затова се опитва пак, вместо да се отказва.
    if (ctrl == null || !ctrl.hasClients) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _revealAnchor(tab, attempt + 1));
      return;
    }

    final max = ctrl.position.maxScrollExtent;
    final want = target.clamp(0.0, max);
    // Стигнали сме дъното, а редът пак го няма — няма накъде повече.
    if (attempt > 0 && (ctrl.offset - want).abs() < 1 && want >= max) return;

    await ctrl.animateTo(
      want,
      duration: _glideDuration((ctrl.offset - want).abs()),
      curve: Curves.easeInOutCubic,
    );
    if (!mounted || _tabs.index != tab) return;
    await _revealAnchor(tab, attempt + 1);
  }

  /// Колко да трае плъзгането според изминатото разстояние.
  ///
  /// ⚠ НЕ Е постоянна стойност. Един и същ брой милисекунди прави късото
  /// разстояние мудно, а дългото — размазано бързо. Скоростта е горе-долу
  /// постоянна (около 2,6 екрана в секунда), с под и таван: под 260 ms окото
  /// не успява да проследи посоката, а над 900 ms чакането почва да дразни
  /// човек, който просто е сменил таб.
  Duration _glideDuration(double distance) {
    final ms = 260 + distance * 0.38;
    return Duration(milliseconds: ms.clamp(260, 900).round());
  }

  /// Груба оценка къде стои запомненият ред — САМО за да се построи.
  ///
  /// ⚠ Не е нужно да е точна: щом редът се построи, `ensureVisible` го
  /// намества по истинската му геометрия. Затова тук не се мери текст, а
  /// просто се броят редовете преди него по номинална височина.
  ///
  /// Оценката НЕ включва разгънатата решетка, и това е нарочно: разгънат е
  /// точно запомненият ред, а неговата решетка стои ПОД него и не мести
  /// началото му.
  double? _estimatedAnchorOffset(int tab) {
    // Височина на ред с книга/катизма — подът, който и оформлението ползва.
    const rowH = _kBookRowMinHeight;
    // Заглавие на дял — вече е закован хедър с фиксирана височина, тъй че
    // сметката е точно неговата (виж [_StickyGroupHeader]).
    final headerH = BibleTocFontSize.value * 1.35 + 22;

    final last = _lastRead[tab];
    if (last == null) return null;

    if (tab == 2) {
      final psalm = int.tryParse(last.split(':').last) ?? 1;
      final k = KathismaTable.forPsalm(psalm);
      final index = k == null ? kKathismata.length : k.number - 1;
      return index * rowH;
    }

    final rows = _rowsForTab[tab];
    if (rows == null) return null;
    final code = last.split(':').first;
    var y = 0.0;
    for (final row in rows) {
      if (row is BibleBook) {
        if (row.code == code) return y;
        y += rowH;
      } else {
        y += headerH;
      }
    }
    return null;
  }

  Future<void> _openChapters(BibleBook book) async {
    if (_openBook == book.code) {
      setState(() => _openBook = null);
      return;
    }
    if (!mounted) return;
    setState(() => _openBook = book.code);
  }

  /// Кой панел да се построи в `endDrawer`-а.
  ///
  /// ⚠ `Scaffold` има ЕДИН `endDrawer`, а тук панелите са два: общите
  /// настройки на Библията (от менюто зад трите точки) и настройките на
  /// търсенето (от зъбното колело). Затова се сменя СЪДЪРЖАНИЕТО му, а не се
  /// търси втори слот — Flutter няма такъв, а bottom sheet за едното би
  /// значел два различни жеста за две еднакви по вид настройки.
  bool _searchSettingsInDrawer = false;

  void _openSearchSettings() {
    setState(() => _searchSettingsInDrawer = true);
    _scaffoldKey.currentState?.openEndDrawer();
  }

  /// Има ли какво да се обхожда — от това зависи какво вършат двете кръгчета
  /// вдясно в лентата.
  bool get _stepping => _searchOpen && _hits.isNotEmpty;

  /// Полето за търсене, застанало на мястото на заглавието.
  Widget _searchField() {
    const fg = Colors.white;
    return SizedBox(
      height: 38,
      child: TextField(
        controller: _searchCtrl,
        // Полето се отваря готово за писане: човек е натиснал лупата тъкмо
        // за да пише, а вадене на клавиатурата с втори тап е излишна стъпка.
        autofocus: true,
        style: const TextStyle(color: fg, fontSize: 15),
        textInputAction: TextInputAction.search,
        onChanged: _runSearch,
        // ⚠ Пълнотекстовото се пуска при ПОТВЪРЖДЕНИЕ, не при всяка буква.
        // Търсенето в имената пресява седемдесет реда в паметта и може да
        // върви с писането; търсенето в текста чете осем мегабайта и това е
        // около половин секунда на всяко натискане — тоест забито поле.
        onSubmitted: (_) {
          if (BibleSearchSettings.where == BibleSearchWhere.text) {
            unawaited(_runTextSearch());
          }
        },
        decoration: InputDecoration(
          isDense: true,
          hintText: _inText ? 'в цялото Писание — Enter' : 'търси книга',
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
          suffixIcon: _fieldSuffix(fg),
          suffixIconConstraints:
              const BoxConstraints(minWidth: 0, minHeight: 0),
        ),
      ),
    );
  }

  /// Каквото стои в десния край НА САМОТО поле: сивата лупа, докато е
  /// празно, и броячът с ✕, щом се пише.
  ///
  /// ⚠ ДВЕТЕ ✕ ВЪРШАТ РАЗЛИЧНИ НЕЩА и затова изглеждат различно: голямото
  /// вляво в лентата ЗАТВАРЯ търсенето, а това малкото, вътре в полето, само
  /// ИЗЧИСТВА написаното и оставя полето отворено. Виждат се едновременно
  /// единствено когато има какво да се чисти.
  ///
  /// Лупата е знак какво е това поле, не копче — затова отстъпва мястото си,
  /// щом полето заработи. Взето едно към едно от съдържанието на
  /// „Месецослов" (`_TocSheetState._fieldSuffix`).
  Widget _fieldSuffix(Color fg) {
    // ⚠ Докато върви заявката, на мястото на лупата стои кръгче. Пълният
    // прочит на текста трае към половин секунда — достатъчно, за да изглежда
    // приложението забито, ако нищо не се промени след Enter.
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
    if (_query.isEmpty || _inText) {
      return Padding(
        padding: const EdgeInsets.only(right: 10, left: 6),
        child: Icon(Icons.search, size: 18, color: fg.withValues(alpha: 0.45)),
      );
    }
    // ⚠ В режим „в текста" се стига дотук само с празно поле — броячът няма
    // какво да брои, защото намереното живее на друг екран. Тогава остава
    // лупата (виж условието по-горе), а не „0/0", което би значело
    // „търсих и не намерих".
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

  /// Надписът на един ред в указателя, с маркирано намереното.
  ///
  /// ⚠ ЦВЕТОВЕТЕ СА ОБЩИ С ЧЕТЦИТЕ (`AppColors.hit*`). Смяна се прави там,
  /// инак намереното свети различно в указателя и в отвореното от него
  /// четиво — същото правило като при търсенето в календара.
  ///
  /// Указателят стои винаги на тъмен фон, тъй че тук се ползва само тъмната
  /// половина от двойките.
  Widget _rowLabel(String rowKey, String fallback, TextStyle style) {
    final hit = _searchOpen && _query.isNotEmpty
        ? _hits.where((h) => h.key == rowKey).firstOrNull
        : null;
    if (hit == null) return Text(fallback, style: style);

    final current = _currentHitKey == rowKey;
    final text = hit.text;
    final lower = text.toLowerCase();
    final q = _query.toLowerCase();

    final spans = <InlineSpan>[];
    var from = 0;
    while (true) {
      final at = lower.indexOf(q, from);
      if (at < 0 || q.isEmpty) break;
      if (at > from) spans.add(TextSpan(text: text.substring(from, at)));
      spans.add(TextSpan(
        text: text.substring(at, at + q.length),
        style: TextStyle(
          backgroundColor:
              current ? AppColors.hitCurrentDark : AppColors.hitDark,
        ),
      ));
      from = at + q.length;
    }
    if (from < text.length) spans.add(TextSpan(text: text.substring(from)));

    return Text.rich(TextSpan(style: style, children: spans));
  }

  // ── Търсене в указателя: намиране, обхождане, плъзгане ─────────────────

  /// Отваря или затваря режима на търсене.
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

  /// Пресмята съвпаденията в ТЕКУЩИЯ таб.
  ///
  /// ⚠ ТЪРСИ СЕ И В ДВЕТЕ ИМЕНА НА КНИГАТА, а показваното се нагажда.
  /// Списъкът рисува късата форма („Матей"), но човек, който напише
  /// „евангелие", очаква да намери четирите евангелия — а в късата форма
  /// такава дума няма. Затова редът със съвпадение САМО в пълното име
  /// („Евангелие от Матей") временно показва ПЪЛНОТО: инак се маркира ред,
  /// в който не се вижда нищо маркирано, и находката изглежда като грешка.
  ///
  /// ⚠ Сравнява се по `toLowerCase()` от двете страни — човек пише „йоан", а
  /// в указателя стои „Йоан" (същото правило като в търсенето на календара).
  void _runSearch(String raw) {
    final q = raw.trim().toLowerCase();
    final tab = _tabs.index;
    final hits = <_TocHit>[];

    // ⚠ В режим „в текста" списъкът НЕ се пресява. Намереното там не живее
    // в този екран — то отваря свой — тъй че маркиране по имената на
    // книгите би било трети, несвързан отговор на същата заявка.
    if (q.isNotEmpty && !_inText) {
      if (tab == 2) {
        // Псалтирът е списък от катизми — съвпадението е в заглавието им.
        for (final k in kKathismata) {
          final title = 'Катизма ${k.number}';
          if (title.toLowerCase().contains(q)) {
            hits.add(_TocHit(key: 'k${k.number}', text: title));
          }
        }
      } else {
        for (final row in _rowsForTab[tab] ?? const <Object>[]) {
          if (row is! BibleBook) continue;
          if (row.short.toLowerCase().contains(q)) {
            hits.add(_TocHit(key: row.code, text: row.short));
          } else if (row.title.toLowerCase().contains(q)) {
            hits.add(_TocHit(key: row.code, text: row.title));
          }
        }
      }
    }

    setState(() {
      _query = raw.trim();
      _hits = hits;
      _currentHit = 0;
    });
    if (hits.isNotEmpty) unawaited(_revealHit(0));
  }

  /// Търси ли се в текста на Писанието (а не в имената на книгите).
  bool get _inText => BibleSearchSettings.where == BibleSearchWhere.text;

  /// Кои книги влизат в обхвата според настройката и отворения таб.
  ///
  /// Празен списък значи „цялото Писание" — така го разбира и
  /// [BibleDb.searchText].
  List<String> _scopeBooks() {
    switch (BibleSearchSettings.range) {
      case BibleSearchRange.all:
        return const [];
      case BibleSearchRange.picked:
        return BibleSearchSettings.pick.books.toList();
      case BibleSearchRange.tab:
        switch (_tabs.index) {
          case 0:
            return [for (final b in _books) if (!b.isOldTestament) b.code];
          case 1:
            return [for (final b in _books) if (b.isOldTestament) b.code];
          default:
            return const ['Ps'];
        }
    }
  }

  /// Отделните глави в обхвата — днес само катизмите на Псалтира.
  Map<String, Set<int>> _scopeChapters() => scopeChaptersFor(
      BibleSearchSettings.range, BibleSearchSettings.pick);

  /// Пълнотекстовото търсене: заявка към базата и екран с намереното.
  Future<void> _runTextSearch() async {
    final q = _searchCtrl.text.trim();
    if (q.isEmpty) return;

    // ⚠ Търси се в АКТИВНИЯ превод — онзи, в чиято колона стои човекът, а не
    // в двата. Иначе една и съща дума дава по два реда, щом я има и в двата
    // текста, а списъкът се удвоява без да каже нищо ново.
    final pair = BibleLanguages.value;
    final lang = pair.active == 0 ? pair.first : pair.second;

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

  /// Следващото/предишното съвпадение, в кръг.
  void _stepHit(int delta) {
    if (_hits.isEmpty) return;
    setState(() {
      _currentHit = (_currentHit + delta) % _hits.length;
      if (_currentHit < 0) _currentHit += _hits.length;
    });
    unawaited(_revealHit(0));
  }

  void _clearSearch() {
    _searchCtrl.clear();
    setState(() {
      _query = '';
      _hits = const [];
      _currentHit = 0;
    });
  }

  /// Плъзга до текущото съвпадение — ДОРИ КОГАТО РЕДЪТ ОЩЕ НЕ Е ПОСТРОЕН.
  ///
  /// ⚠ Устроен е точно като [_revealAnchor] и по същата причина: списъкът е
  /// мързелив, тъй че `GlobalKey.currentContext` на съвпадение двайсет реда
  /// по-надолу е `null` в мига на скока. Голо `return` тук би било третият
  /// тих отказ в този проект — виж бележката при [_revealAnchor].
  ///
  /// ⚠ Подравняването е 0.35, не 0.15 като при котвата: намереното трябва да
  /// се види ЗАЕДНО със съседите си, за да личи в кой дял е попаднало, а не
  /// да застава залепено под лентата.
  Future<void> _revealHit(int attempt) async {
    if (!mounted || !_searchOpen || _hits.isEmpty) return;

    // ⚠ ИЗЧАКВА СЕ КАДЪР, ИНАЧЕ СЕ ПЛЪЗГА ДО ПРЕДИШНОТО СЪВПАДЕНИЕ.
    // `_hitKey` се МЕСТИ по списъка (един ключ, не по един на ред), а
    // `setState` само насрочва построяване. Потърси ли се `currentContext`
    // веднага след него, ключът още виси на СТАРИЯ ред и `ensureVisible`
    // услужливо го намества — с което броячът казва „3/5", а на екрана стои
    // второто. Симптомът лъже: изглежда като изгубено едно натискане, а
    // всъщност всяко натискане закъснява с едно.
    if (attempt == 0) await WidgetsBinding.instance.endOfFrame;
    if (!mounted || !_searchOpen || _hits.isEmpty) return;

    final tab = _tabs.index;

    // ⚠ `ctx.mounted`, а не само `mounted` на State-а: контекстът идва от
    // GlobalKey и може да е на ред, който междувременно е излязъл от
    // построеното (списъкът е мързелив). State-ът може да е жив, а точно
    // този елемент — не.
    final ctx = _hitKey.currentContext;
    if (ctx != null && ctx.mounted) {
      await Scrollable.ensureVisible(
        ctx,
        alignment: 0.35,
        duration: Duration(milliseconds: attempt == 0 ? 380 : 200),
        curve: Curves.easeOutCubic,
      );
      return;
    }
    if (attempt >= 8) return;

    final target = _estimatedHitOffset(tab);
    if (target == null) return;

    final ctrl = _scrollers[tab];
    if (ctrl == null || !ctrl.hasClients) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _revealHit(attempt + 1));
      return;
    }

    final max = ctrl.position.maxScrollExtent;
    final want = target.clamp(0.0, max);
    if (attempt > 0 && (ctrl.offset - want).abs() < 1 && want >= max) return;

    await ctrl.animateTo(
      want,
      duration: _glideDuration((ctrl.offset - want).abs()),
      curve: Curves.easeInOutCubic,
    );
    if (!mounted || _tabs.index != tab) return;
    await _revealHit(attempt + 1);
  }

  /// Груба оценка къде стои редът със съвпадението — САМО за да се построи.
  /// Същата сметка като [_estimatedAnchorOffset], но по ключа на находката.
  double? _estimatedHitOffset(int tab) {
    final key = _currentHitKey;
    if (key == null) return null;
    const rowH = _kBookRowMinHeight;
    final headerH = BibleTocFontSize.value * 1.35 + 22;

    if (tab == 2) {
      final n = int.tryParse(key.replaceFirst('k', ''));
      final index = n == null ? kKathismata.length : n - 1;
      return index * rowH;
    }

    final rows = _rowsForTab[tab];
    if (rows == null) return null;
    var y = 0.0;
    for (final row in rows) {
      if (row is BibleBook) {
        if (row.code == key) return y;
        y += rowH;
      } else {
        y += headerH;
      }
    }
    return null;
  }

  /// Менюто зад трите точки — СЪЩОТО като в трите четеца.
  ///
  /// ⚠ Точките са ДВЕ, не пълните `kReaderMenuItems`: „Сподели като PDF" тук
  /// няма смисъл. Указателят не е четиво — той е списък с имена на книги и
  /// решетка от номера, тъй че изнасянето му на хартия не носи нищо.
  ///
  /// Списъкът с отметки още го няма и точката казва това вместо да мълчи —
  /// същият довод като при бутона за търсене в четеца: ред, който не прави
  /// нищо и не обяснява защо, се приема за счупен.
  Future<void> _showMoreMenu() async {
    final choice = await showReaderMoreMenu(
      context,
      items: const [kReaderSettingsMenuItem, kBookmarksMenuItem],
    );
    if (!mounted || choice == null) return;

    if (choice == kReaderSettingsMenuItem.value) {
      setState(() => _searchSettingsInDrawer = false);
      _scaffoldKey.currentState?.openEndDrawer();
    } else if (choice == kBookmarksMenuItem.value) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Списъкът с отметки е в процес на разработка.'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: AppColors.background,
      // ⚠ ХАМБУРГЕР ВМЕСТО СТРЕЛКА „НАЗАД". Указателят на Библията е раздел
      // от приложението, равен на „Празници" и „Месецослов", а не екран
      // навътре в нещо — и във всички останали раздели горе вляво стои
      // менюто. Стрелката тук значеше „обратно там, откъдето влезе", което
      // при разходка между разделите е ту менюто, ту календарът.
      //
      // ⚠ Достатъчно е `drawer` да е зададен: `AppBar` предпочита копчето за
      // менюто пред стрелката, когато скелетът има drawer
      // (`hasDrawer` в app_bar.dart), тъй че `leading` не се пипа.
      // Излизането назад остава на хардуерния бутон, както в другите
      // раздели.
      drawer: const AppDrawer(),
      // ⚠ Настройките се отварят като панел ОТДЯСНО, не като нов екран —
      // както във всички четци. Категорията е само `bible`: указателят не
      // зависи нито от стила на календара, нито от буквицата в житията.
      //
      // ⚠ Копчето за този панел НЕ се появява само в лентата, защото
      // `actions` е непразен (`AppBar` предпочита подадените бутони пред
      // `EndDrawerButton` — виж app_bar.dart). Отваря се единствено през
      // менюто зад трите точки.
      endDrawer: _searchSettingsInDrawer
          ? BibleSearchSettingsPanel(
              onChanged: () => _runSearch(_searchCtrl.text))
          : const SettingsDrawer(sections: {SettingsSection.bible}),
      appBar: AppBar(
        backgroundColor: AppColors.toolbar,
        foregroundColor: Colors.white,
        // ⚠ СИСТЕМНИЯТ шрифт, не TamburinModern — същият довод като при
        // заглавието на главата в четеца (bible_reader._toolbar): лентата е
        // УПРАВЛЕНИЕ, не четиво, а Tamburin е за заглавия ВЪТРЕ в текста.
        // Калиграфският надпис тук спореше и с табовете под него, и с
        // указателя отдолу, които са изцяло със системния.
        // ⚠ ПОЛЕТО ЗАСТАВА ВЪРХУ ЗАГЛАВИЕТО, а не под лентата на свой ред.
        // Лентата и без това носи всичко нужно за търсенето (изход вляво,
        // обхождане вдясно), тъй че втори ред би повторил рамката ѝ и би
        // отнел от указателя — а в легнало положение той е малкото, което
        // остава. Същият похват като в дневния изглед, където лупата отваря
        // поле на мястото на надписа.
        title: _searchOpen ? _searchField() : const Text('Библия'),
        // ⚠ ✕ ВМЕСТО ХАМБУРГЕРА, докато се търси. Менюто и изходът от
        // търсенето искат едно и също място — горе вляво, под палеца — а
        // докато полето е отворено, по-нужното е излизането. Менюто се
        // връща само, щом търсенето се затвори.
        leading: _searchOpen
            ? IconButton(
                icon: const Icon(Icons.close),
                tooltip: 'Затвори търсенето',
                onPressed: _toggleSearch,
              )
            : null,
        // ⚠ РАЗСТОЯНИЯТА СА ТЕЗИ ОТ ЧЕТЦИТЕ, не свои. Общият
        // `readerToolbarActions` (reader_toolbar.dart) дели бутоните с 18 и
        // завършва със `SizedBox(width: 2)` до десния ръб. Тук двете кръгчета
        // стояха ЗАЛЕПЕНИ едно за друго и се четяха като едно тежко петно,
        // вместо като два отделни бутона — а секцията трябва да изглежда като
        // същия четец, не като роднина.
        actions: [
          // ⚠ Лупата е ПЪРВА отляво сред копчетата — както в трите четеца
          // (`readerToolbarActions`). Редът им е навик, не подредба по
          // важност: ръката вече знае къде да иде.
          if (!_searchOpen) ...[
            // ⚠ ОБЩОТО копче, не `RoundIconButton`. Лупата в трите четеца е
            // без кръгче и с иконка 24; кръгчетата са запазени за „−/+".
            readerSearchButton(context: context, onTap: _toggleSearch),
            const SizedBox(width: 10),
          ],
          // ⚠ ДВОЙКАТА СМЕНЯ ЗАНЯТИЕТО СИ, НЕ ВИДА СИ — точно както в
          // съдържанието на „Месецослов": щом има какво да се обхожда,
          // „− +" стават „‹ ›" на същото място и със същия размер. Никой не
          // нагласява шрифт, докато търси, тъй че двете употреби могат да
          // делят едно място, без да си пречат.
          RoundIconButton(
            icon: _stepping ? Icons.chevron_left : Icons.remove,
            tooltip: _stepping ? 'Предишно съвпадение' : 'По-дребен текст',
            // ⚠ Извън обхождането двойката пак върши старата си работа —
            // дори при отворено поле. Човек може да е отворил търсенето и
            // още да не е написал нищо; посивени бутони тогава изглеждат
            // като счупени. Един към едно с „Месецослов".
            enabled: _stepping || BibleTocFontSize.value > BibleTocFontSize.min,
            size: kReaderBtnSize,
            onTap: () => _stepping
                ? _stepHit(-1)
                : setState(() =>
                    BibleTocFontSize.nudge(-BibleTocFontSize.step)),
          ),
          const SizedBox(width: 18),
          RoundIconButton(
            icon: _stepping ? Icons.chevron_right : Icons.add,
            tooltip: _stepping ? 'Следващо съвпадение' : 'По-едър текст',
            enabled: _stepping || BibleTocFontSize.value < BibleTocFontSize.max,
            size: kReaderBtnSize,
            onTap: () => _stepping
                ? _stepHit(1)
                : setState(() =>
                    BibleTocFontSize.nudge(BibleTocFontSize.step)),
          ),
          // ⚠ 10 — „менюто е приятел на съседа си". Числото е преписано от
          // общия `readerToolbarActions`, където до трите точки стои същото
          // по-тясно разстояние: то ги свързва с двойката преди тях, вместо
          // да ги остави да плуват сами.
          //
          // ⚠ Дотук тук стоеше `SizedBox(width: 12)` с обяснение, че 2 е
          // малко, защото последно е кръгчето „+" (то няма вътрешен отстъп и
          // се долепяше до ръба). Сега последен е бутонът с трите точки —
          // иконка 24 в кутия с по 6 отстъп, — тъй че важи оригиналното 2 и
          // центърът пак пада на ~23 от ръба, както във всички ленти.
          const SizedBox(width: 10),
          // ⚠ ТРИТЕ ТОЧКИ СТАВАТ ЗЪБНО КОЛЕЛО, докато се търси — по същото
          // правило като двойката вляво от тях: лентата има два режима и
          // всяко копче в нея служи на този, който е в сила. В режим на
          // търсене менюто („Настройки", „Списък с отметки") не върши работа
          // на човека, а настройките НА ТЪРСЕНЕТО — да, и трябва да са на
          // един тап от полето.
          Tooltip(
            message: _searchOpen ? 'Настройки на търсенето' : 'Още',
            child: InkWell(
              onTap: _searchOpen ? _openSearchSettings : _showMoreMenu,
              customBorder: const CircleBorder(),
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Icon(
                    _searchOpen ? Icons.tune : Icons.more_vert,
                    size: 24,
                    color: Colors.white),
              ),
            ),
          ),
          const SizedBox(width: 2),
        ],
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          // ⚠ ЧЕРТАТА ПОД ЦЕЛИЯ РЕД ТАБОВЕ — не индикаторът, а тя.
          //
          // Material 3 я рисува сама, с `colorScheme.outlineVariant`, и в
          // тъмната схема тя излиза почти бяла: това беше НАЙ-ЯРКОТО нещо на
          // екрана — по-ярко от имената на книгите под нея. Тоест обзавеждане
          // крещеше по-силно от съдържанието.
          //
          // Тук е свалена до сивото, с което приложението и без това дели
          // дялове. Индикаторът остава бял: той бележи избора и трябва да е
          // ярък — чертата само отделя лентата от списъка.
          dividerColor: AppColors.sectionDivider,
          // ⚠ Тесен отстъп, за да се РАЗПЪНАТ табовете по ширина. По
          // подразбиране Flutter слага по 16 отстрани на всеки и трите
          // надписа се скупчват в средата, а между тях зее празно.
          labelPadding: const EdgeInsets.symmetric(horizontal: 4),
          // Колкото имената на книгите под тях, но БЕЗ получер: пробвахме го
          // и утежнява лентата — чертата отдолу и без това казва кой таб е
          // избран.
          //
          // ⚠ `height: 1.05` е за случая, в който надписът СЕ ПРЕГЪНЕ на два
          // реда (при по-едър шрифт, зададен с +). При обичайното нормално
          // междуредие двата реда разпъват лентата двойно; тук трябва да
          // стоят плътно един под друг.
          labelStyle: TextStyle(
              fontSize: BibleTocFontSize.value,
              fontWeight: FontWeight.normal,
              height: 1.05),
          unselectedLabelStyle: TextStyle(
              fontSize: BibleTocFontSize.value,
              fontWeight: FontWeight.normal,
              height: 1.05),
          tabs: [
            for (final t in const ['Нов завет', 'Стар завет', 'Псалтир'])
              Tab(
                // ⚠ Височина за ЕДИН ред, не за два.
                //
                // Дотук се пазеше място за прегънат надпис — но трите имена
                // („Нов завет", „Стар завет", „Псалтир") се събират на един
                // ред при всеки размер на шрифта, тъй че вторият стоеше празен
                // ВИНАГИ. В легнало положение това е чист разкош: лентата яде
                // от малкото височина, останала за самия текст.
                //
                // Вместо да се пази запас „за всеки случай", надписът е
                // едноредов и се свива, ако някога не се побере — виж
                // FittedBox по-долу. Така лентата е точно толкова висока,
                // колкото ѝ трябва, и нищо не може да се реже.
                height: BibleTocFontSize.value * 1.35 + 12,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(t, maxLines: 1, softWrap: false),
                ),
              ),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_error!, textAlign: TextAlign.center),
                  ),
                )
              : TabBarView(
                  controller: _tabs,
                  children: [
                    _bookList([for (final b in _books) if (!b.isOldTestament) b],
                        kNtGroups, 0),
                    // ⚠ Псалтирът НЕ се вади оттук, макар да има свой таб.
                    // Той е книга от Стария завет и мястото му в реда между
                    // Иов и Притчи е част от подредбата на Писанието;
                    // третият таб е ПРЯК ПЪТ, не преместване. Извади ли се,
                    // човек, който върви по списъка, го намира липсващ точно
                    // там, където го търси.
                    _bookList([for (final b in _books) if (b.isOldTestament) b],
                        kOtGroups, 1),
                    _psalter(),
                  ],
                ),
    );
  }

  /// Един дял, готов за рисуване: заглавие и книгите под него.
  ///
  /// ⚠ Празно заглавие значи „без закован надпис" — виж [kNtGroups], където
  /// „Деяния" стои нарочно без име на дял. При закованите заглавия това дори
  /// има ПОЛЗА: щом дялът без име влезе в изгледа, `SliverMainAxisGroup`
  /// изтласква надписа на предишния и отгоре не остава нищо. Инак „ЕВАНГЕЛИЯ"
  /// щеше да виси над Деяния и да лъже къде се намираш.
  List<({String title, List<BibleBook> books})> _groupsFor(
      List<BibleBook> books, List<BibleBookGroup> groups) {
    final byCode = {for (final b in books) b.code: b};
    final used = <String>{};
    final out = <({String title, List<BibleBook> books})>[];

    for (final g in groups) {
      final inGroup = [
        for (final code in g.codes)
          if (byCode[code] != null) byCode[code]!,
      ];
      if (inGroup.isEmpty) continue;
      out.add((title: g.title, books: inGroup));
      used.addAll(inGroup.map((b) => b.code));
    }

    // Некатегоризираното — накрая, БЕЗ заглавие. Виж бележката при
    // kNtGroups: така никоя книга не изчезва, забрави ли се в списъка.
    final rest = [for (final b in books) if (!used.contains(b.code)) b];
    if (rest.isNotEmpty) out.add((title: '', books: rest));
    return out;
  }

  /// Списъкът с книги — със ЗАКОВАНИ заглавия на дяловете.
  ///
  /// ⚠ ЗАЩО НЕ ОБИКНОВЕН `ListView`. Дотук заглавието на дяла отплаваше
  /// нагоре заедно с книгите и по средата на „Пророчески книги" (19 книги)
  /// човек нямаше как да разбере в кой дял чете, без да превърти обратно.
  /// Сега надписът се закача под табовете и стои там, докато дялът му е на
  /// екрана.
  ///
  /// ⚠ КЛЮЧОВОТО Е `SliverMainAxisGroup`, а не просто `pinned: true`.
  /// Закован хедър БЕЗ група остава горе до края на целия списък — всичките
  /// пет заглавия биха се натрупали едно върху друго. Групата ограничава
  /// закования надпис до СВОЯ дял, тъй че следващият го изтласква нагоре и
  /// заема мястото му. Точно това е исканото поведение.
  Widget _bookList(List<BibleBook> books, List<BibleBookGroup> groups, int tab) {
    final grouped = _groupsFor(books, groups);
    // Оценката на позицията в [_estimatedAnchorOffset] брои същите редове —
    // пази се сплеснат, за да не се сглобява наново.
    _rowsForTab[tab] = [
      for (final g in grouped) ...[
        if (g.title.isNotEmpty) g.title,
        ...g.books,
      ],
    ];

    return CustomScrollView(
      controller: _scrollerFor(tab),
      slivers: [
        for (final g in grouped)
          SliverMainAxisGroup(
            slivers: [
              if (g.title.isNotEmpty)
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _StickyGroupHeader(g.title),
                ),
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, i) => _bookRow(g.books[i], tab),
                  childCount: g.books.length,
                ),
              ),
            ],
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 32)),
      ],
    );
  }

  /// Един ред с книга и разгъващата се под него решетка.
  Widget _bookRow(BibleBook book, int tab) {
    final open = _openBook == book.code;
    // Котвата за връщането — само на реда, който сме запомнили за ТОЗИ таб.
    // Без нея ensureVisible няма за какво да се хване.
    final isAnchor = _lastRead[tab]?.split(':').first == book.code;
    // ⚠ Намереното ИЗПРЕВАРВА котвата, когато двете паднат на един ред: два
    // GlobalKey-а на един widget не могат да стоят, а при активно търсене
    // плъзгането се води от находката — връщането към последно четеното е
    // спряно точно тогава (виж слушателя на табовете).
    final isHit = _searchOpen && _currentHitKey == book.code;
    return Column(
      key: isHit
          ? _hitKey
          : (isAnchor ? _anchorKeys.putIfAbsent(tab, GlobalKey.new) : null),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => _openChapters(book),
          child: Container(
            constraints: const BoxConstraints(minHeight: _kBookRowMinHeight),
            padding: const EdgeInsets.fromLTRB(16, 4, 12, 4),
            alignment: Alignment.centerLeft,
            child: Row(
              children: [
                Expanded(
                  // ⚠ Късата форма („Матей"), не пълната. Списъкът се чете
                  // на един поглед и „Евангелие от" пред четири поредни реда
                  // само отмества същественото надясно.
                  child: _rowLabel(
                      book.code,
                      book.short,
                      TextStyle(
                          fontSize: BibleTocFontSize.value,
                          // ⚠ Свито междуредие: текстът расте, редът НЕ.
                          // Виж бележката при _kBookRowMinHeight.
                          height: 1.15)),
                ),
                _trailingCount('${book.chapters}'),
              ],
            ),
          ),
        ),
        // ⚠ Същите 300 ms като разгъващите се секции в дневния изглед
        // (saint_expandable_tile.dart) — за човека това е едно и също
        // движение и не бива да е с различна бързина според екрана.
        AnimatedSize(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          alignment: Alignment.topCenter,
          child: open ? _chapterGrid(book) : const SizedBox.shrink(),
        ),
      ],
    );
  }

  /// Сведението в десния край на реда — броят глави, или обхватът на
  /// катизмата („Пс. 1–8").
  ///
  /// ⚠ СТРЕЛКАТА ДО НЕГО Е МАХНАТА. Всеки ред носеше два знака наведнъж —
  /// число и шеврон — и двата казващи едно и също: „тук има още". При
  /// петнайсет реда на екран това са петнайсет повторени стрелки, които не
  /// добавят нищо: решетката, която изскача при тап, е сама по себе си
  /// достатъчна и много по-ясна индикация. Числото остава, защото ТО носи
  /// истинско сведение — колко дълга е книгата.
  ///
  /// ⚠ Цветът е [AppColors.textSecondary], а не [AppColors.textMuted].
  /// Измерено: muted върху фона на приложението дава 3,51:1 — под нормата
  /// 4,5:1 на WCAG AA. Точно с него бяха изписани обхватите на катизмите,
  /// тоест най-полезното при избор на катизма беше и най-трудното за
  /// разчитане. `textSecondary` дава 4,9:1 и минава.
  Widget _trailingCount(String text) {
    return Padding(
      // Малко въздух до десния ръб, за да не опира числото в него.
      padding: const EdgeInsets.only(left: 12, right: 4),
      child: Text(
        text,
        style: TextStyle(
          color: AppColors.textSecondary,
          fontSize: BibleTocFontSize.value - 4,
        ),
      ),
    );
  }

  /// Табът „Псалтир" — по КАТИЗМИ, не на куп.
  ///
  /// ⚠ Делението е САМО тук. Книгата „Псалтир" в таба „Стар завет" остава с
  /// плоска решетка от 1 до 151, и това е нарочно: там Псалтирът е книга от
  /// Писанието, а катизмите са богослужебна подредба ВЪРХУ него — виж
  /// kathisma.dart. Двата изгледа обслужват две различни четения.
  ///
  /// ⚠ Тук НЯМА нито setState, нито addPostFrameCallback. Построяването само
  /// рисува наличното; наличността е прочетена още в [_load]. Виж бележката
  /// при [_psalms] защо това е важно.
  Widget _psalter() {
    BibleBook? ps;
    for (final b in _books) {
      if (b.code == 'Ps') ps = b;
    }
    if (ps == null) {
      return const Center(child: Text('Псалтирът не е зареден.'));
    }
    final book = ps;
    final extra = KathismaTable.extraFor(book.chapters);

    return ListView(
      controller: _scrollerFor(2),
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        for (final k in kKathismata)
          _kathismaSection(
            book,
            key: 'k${k.number}',
            title: 'Катизма ${k.number}',
            trailing: k.range,
            numbers: k.psalms,
          ),
        // Псалмите извън катизмите. Показва се само ако ги има — при 150
        // глави секцията просто отпада, без празен ред.
        if (extra.isNotEmpty)
          _kathismaSection(
            book,
            key: 'extra',
            // ⚠ ЕДИНСТВЕНО ЧИСЛО, защото псалмът е един. Катизмите покриват
            // 1–150, а Псалтирът има 151 — тъй че извън тях остава ТОЧНО
            // един, и това не е случайност, а устройство на книгата.
            //
            // Числото пак се съгласува само (както и `trailing` до него):
            // подадат ли се утре 150 псалма, секцията изобщо отпада, а при
            // друго деление надписът остава верен, без да се пипа тук.
            title: extra.length == 1 ? 'Допълнителен' : 'Допълнителни',
            trailing: extra.length == 1 ? 'Пс. ${extra.first}' : '${extra.length}',
            numbers: extra,
            // ⚠ ЕДИНСТВЕНАТА линия в този таб. Двайсетте катизми са един
            // непрекъснат ред и черта помежду им не казва нищо; „Допълнителен"
            // обаче е ДРУГО нещо — псалмите извън богослужебната подредба — и
            // границата дотам е истинска. Същото правило като при дяловете в
            // другите два таба (виж [_groupHeader]).
            dividerAbove: true,
          ),
      ],
    );
  }

  /// Коя катизма съдържа последно четения псалм — котвата на таб „Псалтир".
  ///
  /// ⚠ Смята се от ЗАПОМНЕНОТО, не от разгънатото. Двете обикновено съвпадат
  /// (връщането разгъва точно нея), но котвата трябва да е неподвижна дори
  /// когато човек разгъне друга — виж бележката при `isAnchor` по-долу.
  String? get _lastReadKathismaKey {
    final last = _lastRead[2];
    if (last == null) return null;
    final psalm = int.tryParse(last.split(':').last) ?? 1;
    final k = KathismaTable.forPsalm(psalm);
    return k == null ? 'extra' : 'k${k.number}';
  }

  /// Един разгъващ се дял в таба „Псалтир".
  Widget _kathismaSection(
    BibleBook book, {
    required String key,
    required String title,
    required String trailing,
    required List<int> numbers,
    bool dividerAbove = false,
  }) {
    final open = _openKathisma == key;
    // ⚠ КЛЮЧЪТ НЕ БИВА ДА ЗАВИСИ ОТ `open` — иначе разгъването не се
    // анимира.
    //
    // Дотук стоеше `open && _lastRead[2] != null`, тоест `GlobalKey`-ът се
    // появяваше ТОЧНО в мига на разгъването. Смяна на ключ обаче значи друг
    // widget за Flutter (`Widget.canUpdate` сравнява тип И ключ): старият
    // Element се изхвърля и се построява нов. А нов `AnimatedSize` няма
    // предишен размер, тъй че ляга направо на крайния — без анимация.
    // Отвън изглеждаше, че катизмите просто „изскачат", докато книгите в
    // другите два таба се разгъват плавно; разликата беше само тази, защото
    // там котвата се смята от ЗАПОМНЕНАТА книга, не от разгънатата.
    final isAnchor = key == _lastReadKathismaKey;
    final isHit = _searchOpen && _currentHitKey == key;
    return Column(
      key: isHit
          ? _hitKey
          : (isAnchor ? _anchorKeys.putIfAbsent(2, GlobalKey.new) : null),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Същата стълбица като при дяловете (виж [_kAirAboveRule]): голям
        // въздух над чертата, малък под нея. Тук под чертата стои направо
        // редът „Допълнителен" — той сам е заглавието на своя дял.
        if (dividerAbove) ...[
          const SizedBox(height: _kAirAboveRule),
          const Divider(
              height: 1, thickness: 1, color: AppColors.sectionDivider),
          const SizedBox(height: _kRuleToHeading - 4),
        ],
        InkWell(
          onTap: () => setState(() => _openKathisma = open ? null : key),
          child: Container(
            constraints: const BoxConstraints(minHeight: _kBookRowMinHeight),
            padding: const EdgeInsets.fromLTRB(16, 4, 12, 4),
            alignment: Alignment.centerLeft,
            child: Row(
              children: [
                Expanded(
                  child: _rowLabel(
                      key,
                      title,
                      TextStyle(
                          fontSize: BibleTocFontSize.value, height: 1.15)),
                ),
                _trailingCount(trailing),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          alignment: Alignment.topCenter,
          child: open
              ? _chapterGrid(book,
                  available: _psalms, known: true, numbers: numbers)
              : const SizedBox.shrink(),
        ),
        // ⚠ Няма линия под реда — виж [_groupHeader]. Единствената в този
        // таб стои НАД „Допълнителни" (`dividerAbove`).
      ],
    );
  }

  /// Решетката с номерата на главите.
  ///
  /// ⚠ Броят колони се смята от ШИРИНАТА, не е закован. Легнало положение и
  /// таблет дават повече колони сами; закован брой би оставил половин екран
  /// празен в легнало и би смачкал клетките на тесен телефон.
  /// Решетката с номерата на главите.
  ///
  /// ⚠ ШИРИНАТА СЕ ЧЕТЕ ОТ MediaQuery, а НЕ от `LayoutBuilder`. Изглежда
  /// като дребна разлика, но заради нея разгъването се отваряше РЯЗКО (а се
  /// затваряше плавно): решетката стои вътре в `AnimatedSize`, който мери
  /// детето си, за да знае докъде да расте. `LayoutBuilder` вътре в него се
  /// преизгражда спрямо МЕЖДИННИТЕ ограничения на анимацията и още на първия
  /// кадър връща крайния размер — тъй че нямаше какво да се анимира. При
  /// затваряне не личеше, защото там размерът вече е известен.
  ///
  /// Броят колони пак не е закован — смята се от ширината на екрана, тъй че
  /// легнало положение и таблет дават повече колони сами.
  Widget _chapterGrid(BibleBook book,
      {Set<int>? available, bool? known, List<int>? numbers}) {
    final cells = numbers ?? [for (var c = 1; c <= book.chapters; c++) c];

    // ⚠ Отстъпът е СЪЩИЯТ като на реда с книгата (16), не 12, и сметката
    // ползва точно него.
    //
    // Дотук двете бяха различни: отстъпът беше 12, а от ширината се вадеха
    // 24 + 24. Двете последици се виждаха на екрана — решетката тръгваше с
    // 4 точки ПО-НАЛЯВО от името на книгата над нея (тоест не се подравняваше
    // с нищо), а отдясно оставаше близо 30 точки неизползвана ширина, тъй че
    // редът клетки свършваше на ръбест, случаен ръб. Сега лявата колона
    // клетки застава точно под първата буква на името, а последната — точно
    // под броя глави в десния край.
    const pad = 16.0;
    final width = MediaQuery.of(context).size.width - 2 * pad;
    final columns = (width / (_kCellMin + _kCellGap)).floor().clamp(4, 12);
    final side = (width - (columns - 1) * _kCellGap) / columns;

    return Padding(
      padding: const EdgeInsets.fromLTRB(pad, 2, pad, 14),
      child: Wrap(
        spacing: _kCellGap,
        runSpacing: _kCellGap,
        children: [
          for (final ch in cells)
            // ⚠ ВСИЧКИ клетки са живи, независимо какво носи избраният превод.
            //
            // Дотук главите извън обхвата му се сивееха и не се отваряха. Това
            // е грешно на две нива. Първо, сивото не КАЗВА нищо: човек го чете
            // като „повредено" или „несвалено", а истината е друга — този
            // превод просто не включва тази книга (ивритът няма Нов завет,
            // гръцкият Нов завет няма Стар и т.н.).
            //
            // Второ и по-важно: показваните преводи са ДВА. При двойка
            // „български + иврит" и отворен Нов завет българският го ИМА —
            // забраната пречеше да се стигне до текст, който е налице.
            //
            // Сега главата се отваря винаги, а липсата се обяснява ТАМ, в
            // колоната на превода, който я няма (виж `_coverageNote` в
            // bible_reader.dart).
            _chapterCell(book, ch, side, enabled: true),
        ],
      ),
    );
  }

  Widget _chapterCell(BibleBook book, int chapter, double side,
      {required bool enabled}) {
    return SizedBox(
      width: side,
      height: _kCellMin,
      child: Material(
        // ⚠ Синьото е `AppColors.rowSelected` — същото, с което приложението
        // вече бележи избран ред другаде. Не е ново, за да не се учи второ
        // значение на втори цвят.
        color: _isLastRead(book.code, chapter)
            ? AppColors.rowSelected
            : enabled
                ? AppColors.backgroundCard
                : AppColors.backgroundCard.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: enabled
              ? () {
                  _rememberLastRead(book.code, chapter);
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) =>
                        BibleReader(bookCode: book.code, chapter: chapter),
                  ));
                }
              : null,
          child: Center(
            child: Text(
              '$chapter',
              style: TextStyle(
                fontSize: BibleTocFontSize.value - 2,
                color: enabled
                    ? AppColors.textPrimary
                    : AppColors.textMuted.withValues(alpha: 0.5),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Закованото заглавие на дял в указателя.
///
/// ⚠ ФИКСИРАНА ВИСОЧИНА (`minExtent == maxExtent`). Закован хедър, който се
/// свива при скрол, „диша" под пръста и прави списъка неспокоен; тук
/// надписът е указател, не сгъваема лента, тъй че стои цял или го няма.
///
/// ⚠ ВИСОЧИНАТА СЕ СМЯТА ОТ РАЗМЕРА НА ШРИФТА, не е закована. Указателят има
/// свои +/- (`BibleTocFontSize`), тъй че закована стойност би отрязала
/// надписа при по-едър шрифт. Оттам и [shouldRebuild] — сравнява и размера,
/// не само заглавието.
///
/// ⚠ ПЛЪТЕН ФОН — задължителен. Закованият надпис стои ВЪРХУ движещия се
/// списък; без фон книгите минават през буквите му.
class _StickyGroupHeader extends SliverPersistentHeaderDelegate {
  final String title;
  final double fontSize;

  _StickyGroupHeader(this.title) : fontSize = BibleTocFontSize.value;

  /// Въздух над и под надписа. Отгоре е повече, защото при закован хедър
  /// горният ръб опира в табовете, а долният — в първата книга.
  static const double _padTop = 14.0;
  static const double _padBottom = 8.0;

  double get _height => fontSize * 1.35 + _padTop + _padBottom;

  @override
  double get minExtent => _height;
  @override
  double get maxExtent => _height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) {
    return Container(
      color: AppColors.background,
      padding: const EdgeInsets.fromLTRB(16, _padTop, 16, _padBottom),
      alignment: Alignment.centerLeft,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                title.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                // ⚠ СИНЬОТО НА СЕКЦИИТЕ ОТ ДНЕВНИЯ ИЗГЛЕД
                // ([AppColors.sectionTitle]) — точно цветът на „ЕВАНГЕЛИЕ И
                // АПОСТОЛ" там. Дяловете дълго бяха най-бледото нещо на
                // екрана, макар да са степен НАД книгите под тях; размерът
                // не може да ги вдигне (`groupBonus = 0` — получерът и
                // главните вършат работата), тъй че сигналът е цветът.
                style: TextStyle(
                  color: AppColors.sectionTitle,
                  fontSize: fontSize,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _StickyGroupHeader old) =>
      old.title != title || old.fontSize != fontSize;
}
