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

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_theme.dart';
import 'bible_db.dart';
import 'bible_language_pair.dart';
import 'bible_reader.dart';
import 'kathisma.dart';
import 'reader_font_size.dart';
import 'reader_theme.dart';
import 'round_icon_button.dart';
import 'package:shared_preferences/shared_preferences.dart';

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


/// Дял от указателя: заглавие и книгите под него.
class _BookGroup {
  final String title;
  final List<String> codes;
  const _BookGroup(this.title, this.codes);
}

/// ⚠ ЗАЩО ДЯЛОВЕ, А НЕ ЕДИН СПИСЪК. 50 книги, излети наведнъж, се четат като
/// стена: окото няма за какво да се хване и всяко търсене минава през
/// изброяване отгоре надолу. Дяловете са и естествената подредба на
/// Писанието — не са измислени за приложението.
///
/// ⚠ Книга, която НЕ Е в нито един дял, пак се показва — накрая, без
/// заглавие (виж `_grouped`). Така никоя не може да изчезне мълчаливо,
/// забрави ли се тук. Днес такава е 3 Ездра: в славянската Библия тя стои
/// подир пророците, извън дяловете, и точно така я подрежда и източникът.
const List<_BookGroup> _kNtGroups = [
  _BookGroup('Евангелия', ['Mt', 'Mk', 'Lk', 'Jn']),
  // ⚠ „Деяния" стои БЕЗ заглавие на дял — то е една книга и заглавие над
  // единствен ред само би шумяло. Празният низ значи „без заглавие".
  _BookGroup('', ['Act']),
  _BookGroup('Съборни послания',
      ['Jac', '1Pet', '2Pet', '1Jn', '2Jn', '3Jn', 'Juda']),
  _BookGroup('Посланията на апостол Павел', [
    'Rom', '1Cor', '2Cor', 'Gal', 'Eph', 'Phil', 'Col',
    '1Thes', '2Thes', '1Tim', '2Tim', 'Tit', 'Phlm', 'Hebr',
  ]),
  _BookGroup('Пророческа книга', ['Apok']),
];

const List<_BookGroup> _kOtGroups = [
  _BookGroup('Петокнижие', ['Gen', 'Ex', 'Lev', 'Num', 'Deut']),
  _BookGroup('Исторически книги', [
    'Nav', 'Judg', 'Rth', '1Sam', '2Sam', '1King', '2King',
    '1Chron', '2Chron', 'Ezr', '2Ezr', 'Nehem', 'Tov', 'Judf', 'Est',
    '1Mac', '2Mac', '3Mac',
  ]),
  _BookGroup('Учителни книги',
      ['Job', 'Ps', 'Prov', 'Eccl', 'Song', 'Solom', 'Sir']),
  _BookGroup('Пророчески книги', [
    'Is', 'Jer', 'Lam', 'pJer', 'Bar', 'Ezek', 'Dan', 'Hos', 'Joel', 'Am',
    'Avd', 'Jona', 'Mic', 'Naum', 'Habak', 'Sofon', 'Hag', 'Zah', 'Mal',
  ]),
];

class BibleContents extends StatefulWidget {
  const BibleContents({super.key});

  @override
  State<BibleContents> createState() => _BibleContentsState();
}

class _BibleContentsState extends State<BibleContents>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);

  List<BibleBook> _books = const [];
  bool _loading = true;
  String? _error;

  /// Разгърнатата в момента книга — под нея се показва решетката с главите.
  /// Само една наведнъж: две отворени решетки объркват коя чия е.
  String? _openBook;

  /// Кои глави РЕАЛНО ги има за показвания превод. Клетка без текст зад себе
  /// си стои приглушена и не се натиска — по-добре, отколкото да отвори
  /// празен екран.
  Set<int> _available = const {};
  String? _availableFor;

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
  final Map<int, GlobalKey> _anchorKeys = {};

  bool _restored = false;

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
      _restored = false;
      _restoreLastRead();
    });
    _load();
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final langs = await BibleDb.languages();
      await BibleLanguages.loadOnce([for (final l in langs) l.code]);
      final books = await BibleDb.books();
      await BibleTocFontSize.loadOnce();
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

    if (tab != 2) {
      BibleDb.availableChapters(book, BibleLanguages.value.activeCode)
          .then((have) {
        if (!mounted) return;
        setState(() {
          _available = have;
          _availableFor = BibleLanguages.value.activeCode;
        });
      });
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _anchorKeys[tab]?.currentContext;
      if (ctx == null) return;
      Scrollable.ensureVisible(ctx,
          alignment: 0.15, duration: const Duration(milliseconds: 320));
    });
  }

  Future<void> _openChapters(BibleBook book) async {
    if (_openBook == book.code) {
      setState(() => _openBook = null);
      return;
    }
    final lang = BibleLanguages.value.activeCode;
    final have = await BibleDb.availableChapters(book.code, lang);
    if (!mounted) return;
    setState(() {
      _openBook = book.code;
      _available = have;
      _availableFor = lang;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.toolbar,
        foregroundColor: Colors.white,
        title: const Text('Библия',
            style: TextStyle(
                fontFamily: kTitleFamily, fontFamilyFallback: kTitleFallback)),
        actions: [
          RoundIconButton(
            icon: Icons.remove,
            tooltip: 'По-дребен текст',
            enabled: BibleTocFontSize.value > BibleTocFontSize.min,
            size: 22,
            onTap: () => setState(() =>
                BibleTocFontSize.nudge(-BibleTocFontSize.step)),
          ),
          RoundIconButton(
            icon: Icons.add,
            tooltip: 'По-едър текст',
            enabled: BibleTocFontSize.value < BibleTocFontSize.max,
            size: 22,
            onTap: () => setState(() =>
                BibleTocFontSize.nudge(BibleTocFontSize.step)),
          ),
          const SizedBox(width: 6),
        ],
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
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
                // Височина за два реда — иначе прегънатият надпис се реже.
                height: BibleTocFontSize.value * 2.1 + 16,
                child: Text(t,
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    softWrap: true),
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
                        _kNtGroups),
                    // ⚠ Псалтирът НЕ се вади оттук, макар да има свой таб.
                    // Той е книга от Стария завет и мястото му в реда между
                    // Иов и Притчи е част от подредбата на Писанието;
                    // третият таб е ПРЯК ПЪТ, не преместване. Извади ли се,
                    // човек, който върви по списъка, го намира липсващ точно
                    // там, където го търси.
                    _bookList([for (final b in _books) if (b.isOldTestament) b],
                        _kOtGroups),
                    _psalter(),
                  ],
                ),
    );
  }

  /// Плосък списък от редове: заглавие на дял или книга.
  ///
  /// Строи се предварително, за да остане `ListView.builder` — при 50 книги
  /// плюс дялове разликата е малка, но същият списък ще расте.
  List<Object> _grouped(List<BibleBook> books, List<_BookGroup> groups) {
    final byCode = {for (final b in books) b.code: b};
    final used = <String>{};
    final out = <Object>[];

    for (final g in groups) {
      final inGroup = [
        for (final code in g.codes)
          if (byCode[code] != null) byCode[code]!,
      ];
      if (inGroup.isEmpty) continue;
      if (g.title.isNotEmpty) out.add(g.title);
      out.addAll(inGroup);
      used.addAll(inGroup.map((b) => b.code));
    }

    // Некатегоризираното — накрая, БЕЗ заглавие. Виж бележката при
    // _kNtGroups: така никоя книга не изчезва, забрави ли се в списъка.
    for (final b in books) {
      if (!used.contains(b.code)) out.add(b);
    }
    return out;
  }

  Widget _bookList(List<BibleBook> books, List<_BookGroup> groups) {
    final rows = _grouped(books, groups);
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 32),
      itemCount: rows.length,
      itemBuilder: (context, i) {
        final row = rows[i];
        if (row is String) return _groupHeader(row, first: i == 0);
        final book = row as BibleBook;
        final open = _openBook == book.code;
        // Котвата за връщането — само на реда, който сме запомнили за
        // ТОЗИ таб. Без нея ensureVisible няма за какво да се хване.
        final tab = book.isOldTestament ? 1 : 0;
        final isAnchor = _lastRead[tab]?.split(':').first == book.code;
        return Column(
          key: isAnchor ? _anchorKeys.putIfAbsent(tab, GlobalKey.new) : null,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: () => _openChapters(book),
              child: Container(
                constraints:
                    const BoxConstraints(minHeight: _kBookRowMinHeight),
                padding: const EdgeInsets.fromLTRB(16, 4, 12, 4),
                alignment: Alignment.centerLeft,
                child: Row(
                  children: [
                    Expanded(
                      // ⚠ Късата форма („Матей"), не пълната. Списъкът се
                      // чете на един поглед и „Евангелие от" пред четири
                      // поредни реда само отмества същественото надясно.
                      child: Text(book.short,
                          style: TextStyle(
                              fontSize: BibleTocFontSize.value,
                              // ⚠ Свито междуредие: текстът расте, редът НЕ.
                              // Виж бележката при _kBookRowMinHeight.
                              height: 1.15)),
                    ),
                    Text('${book.chapters}',
                        style: TextStyle(
                            color: AppColors.textMuted,
                            fontSize: BibleTocFontSize.value - 4)),
                    Icon(open ? Icons.expand_less : Icons.expand_more,
                        color: AppColors.textMuted, size: 20),
                  ],
                ),
              ),
            ),
            // ⚠ Същите 180 ms като разгъващите се секции в дневния изглед
            // (saint_expandable_tile.dart) — за човека това е едно и също
            // движение и не бива да е с различна бързина според екрана.
            AnimatedSize(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              alignment: Alignment.topCenter,
              child: open ? _chapterGrid(book) : const SizedBox.shrink(),
            ),
            const Divider(height: 1, thickness: 1, color: AppColors.sectionDivider),
          ],
        );
      },
    );
  }

  /// Заглавие на дял.
  ///
  /// Със СЪЩИЯ вид като заглавията на дялове другаде в приложението
  /// (менюто, настройките): приглушено, дребно, с разредка. Нарочно не е
  /// копие на изгледа в източника — вътре в това приложение указателят
  /// трябва да изглежда като негова част, а не като чужда страница.
  Widget _groupHeader(String title, {required bool first}) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, first ? 14 : 22, 16, 6),
      child: Text(
        title.toUpperCase(),
        // ⚠ ПО-ЕДРО от имената на книгите, не по-дребно: дялът е степен
        // НАД тях в подредбата и трябва да се чете като такъв. Посивяването
        // го отдръпва назад, а размерът и получерът го издигат — двете
        // заедно дават йерархия без крещене.
        style: TextStyle(
          color: AppColors.textMuted,
          fontSize: BibleTocFontSize.value + BibleTocFontSize.groupBonus,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
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
            title: 'Допълнителни',
            trailing: extra.length == 1 ? 'Пс. ${extra.first}' : '${extra.length}',
            numbers: extra,
          ),
      ],
    );
  }

  /// Един разгъващ се дял в таба „Псалтир".
  Widget _kathismaSection(
    BibleBook book, {
    required String key,
    required String title,
    required String trailing,
    required List<int> numbers,
  }) {
    final open = _openKathisma == key;
    final isAnchor = open && _lastRead[2] != null;
    return Column(
      key: isAnchor ? _anchorKeys.putIfAbsent(2, GlobalKey.new) : null,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => setState(() => _openKathisma = open ? null : key),
          child: Container(
            constraints: const BoxConstraints(minHeight: _kBookRowMinHeight),
            padding: const EdgeInsets.fromLTRB(16, 4, 12, 4),
            alignment: Alignment.centerLeft,
            child: Row(
              children: [
                Expanded(
                  child: Text(title,
                      style: TextStyle(
                          fontSize: BibleTocFontSize.value, height: 1.15)),
                ),
                Text(trailing,
                    style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: BibleTocFontSize.value - 4)),
                Icon(open ? Icons.expand_less : Icons.expand_more,
                    color: AppColors.textMuted, size: 20),
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
        const Divider(height: 1, thickness: 1, color: AppColors.sectionDivider),
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
    final have = available ?? _available;
    final isKnown = known ?? (_availableFor == BibleLanguages.value.activeCode);
    final cells = numbers ?? [for (var c = 1; c <= book.chapters; c++) c];

    final width = MediaQuery.of(context).size.width - 24 - 24;
    final columns = (width / (_kCellMin + _kCellGap)).floor().clamp(4, 12);
    final side = (width - (columns - 1) * _kCellGap) / columns;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 2, 12, 14),
      child: Wrap(
        spacing: _kCellGap,
        runSpacing: _kCellGap,
        children: [
          for (final ch in cells)
            _chapterCell(book, ch, side,
                // Докато не знаем какво има за този превод, всички клетки са
                // живи — по-добре, отколкото всички да са сиви.
                enabled: !isKnown || have.contains(ch)),
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
