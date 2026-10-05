// molitvoslov_contents.dart
//
// Съдържанието на „Молитвослов" — четири таба: Молитви, Канонник, Акатисти,
// Богослужебни. Устроено по образеца на съдържанието на „Библия".
//
// ⚠ Раздел, който още няма текст, не изчезва от лентата: табът стои и казва
// „предстои". Празен таб без обяснение изглежда като счупен.

import 'package:flutter/material.dart';

import 'app_drawer.dart';
import 'app_theme.dart';
import 'molitvoslov_book.dart';
import 'molitvoslov_db.dart';
import 'molitvoslov_lang_chip.dart';
import 'molitvoslov_reader.dart';
import 'molitvoslov_settings.dart';

class MolitvoslovContents extends StatefulWidget {
  final int initialTab;
  const MolitvoslovContents({super.key, this.initialTab = 0});

  @override
  State<MolitvoslovContents> createState() => _MolitvoslovContentsState();
}

class _MolitvoslovContentsState extends State<MolitvoslovContents>
    with TickerProviderStateMixin {
  List<MolTab>? _tabs;
  TabController? _ctrl;
  List<MolSection> _sections = const [];
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      await MolitvoslovLastSection.loadOnce();
      await MolitvoslovBookLast.loadOnce();
      final tabs = await MolitvoslovDb.tabs();
      final sections = await MolitvoslovDb.sections();
      pruneBookLast(sections);
      if (!mounted) return;
      // ⚠ Контролерът се прави ВЕДНЪЖ, след като броят табове е известен —
      // слушател, окачен в build, би се добавял при всяко построяване.
      _ctrl = TabController(
          length: tabs.length,
          vsync: this,
          initialIndex: widget.initialTab.clamp(0, tabs.length - 1))
        // ⚠ Табът НЕ се записва тук: помни се само ИЗБРАНАТА КОРИЦА
        // (указание на потребителя) — разходката между табовете не бива да я
        // пренаписва. Слушателят само плъзга до последно отворения раздел.
        ..addListener(() {
          if (!_ctrl!.indexIsChanging) _revealLast(_ctrl!.index, 0);
        });
      setState(() {
        _tabs = tabs;
        _sections = sections;
      });
      _revealLast(_ctrl!.index, 0);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  /// Ключ на реда с последно отворения раздел — за плъзгането до него.
  final GlobalKey _lastKey = GlobalKey();

  /// Плъзга ВИДИМО до последно отворения раздел, ако е в този таб — както
  /// съдържанието на Библията („самото движение е подсещането"). Виж
  /// [glideToRow] — далечният ред се построява по пътя.
  void _revealLast(int tabIndex, int attempt) {
    final last = MolitvoslovLastSection.value;
    final tabs = _tabs;
    if (last == null || tabs == null) return;
    final code = tabs[tabIndex].code;
    final list = _sections.where((s) => s.tab == code).toList();
    final i = list.indexWhere((s) => s.id == last);
    if (i < 0) return;
    // В „Богослужебни" редът е КНИГАТА на последния раздел (два реда текст).
    final double y;
    if (list.any((s) => s.book != null)) {
      final bi = bookOrder(list).indexOf(list[i].book ?? '');
      if (bi < 0) return;
      y = 8 + bi * 67.0;
    } else {
      y = 8 + i * 51.0;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      glideToRow(_scrollerFor(code), _lastKey, y,
          () => mounted && _ctrl?.index == tabIndex);
    });
  }

  /// Всеки таб — свой контролер: списъците живеят наведнъж в `TabBarView`,
  /// а един контролер за няколко скрола гърми (виж Библията).
  final Map<String, ScrollController> _scrollers = {};
  ScrollController _scrollerFor(String code) =>
      _scrollers.putIfAbsent(code, ScrollController.new);

  // ⚠ Маршрутът се пази в поле: в dispose контекстът вече не бива да се пита.
  Route<dynamic>? _myRoute;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _myRoute = ModalRoute.of(context);
    molitvoslovTabsRoute = _myRoute;
  }

  @override
  void dispose() {
    if (molitvoslovTabsRoute == _myRoute) molitvoslovTabsRoute = null;
    _ctrl?.dispose();
    for (final c in _scrollers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null || _tabs == null) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(title: const Text('Молитвослов')),
        drawer: const AppDrawer(),
        body: Center(
          child: _error != null
              ? Text('Грешка при четене на молитвослова:\n$_error',
                  style: const TextStyle(color: AppColors.textSecondary))
              : const CircularProgressIndicator(),
        ),
      );
    }
    final tabs = _tabs!;
    return Scaffold(
      backgroundColor: AppColors.background,
      drawer: const AppDrawer(),
      appBar: AppBar(
        title: const Text('Молитвослов'),
        bottom: TabBar(
          controller: _ctrl,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          dividerColor: AppColors.sectionDivider,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: AppColors.textSecondary,
          tabs: [for (final t in tabs) Tab(text: t.title)],
        ),
      ),
      // ⚠ Отстъп отстрани от изреза (в легнало камерата е на единия ръб и
      // текстът се пъхаше под нея). Горе/долу се пазят от лентата и системата.
      body: SafeArea(
        top: false,
        bottom: false,
        child: TabBarView(controller: _ctrl, children: [
          for (final t in tabs) _tabBody(t),
        ]),
      ),
    );
  }

  Widget _tabBody(MolTab tab) {
    final list = _sections.where((s) => s.tab == tab.code).toList();
    if (list.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Този раздел предстои.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 16)),
        ),
      );
    }
    if (list.any((s) => s.book != null)) return _booksBody(list, tab.code);
    return ListView.separated(
      controller: _scrollerFor(tab.code),
      // Въздух под последния ред — да не е забит в долния ръб (потребителят).
      padding: const EdgeInsets.only(top: 8, bottom: 72),
      itemCount: list.length,
      separatorBuilder: (_, _) =>
          const Divider(height: 1, color: AppColors.sectionDivider),
      itemBuilder: (context, i) {
        final s = list[i];
        final isLast = s.id == MolitvoslovLastSection.value;
        // ⚠ Синьото е `AppColors.rowSelected` — същото, с което Библията
        // бележи последно четената глава. Не е нов цвят с ново значение.
        return Material(
          key: isLast ? _lastKey : null,
          color: isLast ? AppColors.rowSelected : Colors.transparent,
          child: InkWell(
          onTap: () {
            // ⚠ Не `setState(() => …set(...))`: `set` връща Future, а
            // setState гърми, ако обратното извикване върне Future.
            MolitvoslovLastSection.set(s.id);
            setState(() {});
            Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => MolitvoslovReader(section: s)));
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(children: [
              Expanded(
                // Етикетът с езиците — горе вдясно, до ПЪРВИЯ ред на
                // заглавието (многоредовото заглавие не го влачи надолу).
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                    child: sectionTitleText(
                        s,
                        const TextStyle(
                            color: AppColors.textPrimary, fontSize: 17)),
                  ),
                  const SizedBox(width: 10),
                  Transform.translate(
                      offset: const Offset(0, -2), child: LangChip(s.langs)),
                ]),
              ),
              const SizedBox(width: 2),
              const Icon(Icons.chevron_right, color: AppColors.textMuted),
            ]),
          ),
          ),
        );
      },
    );
  }

  /// „Богослужебни": първото ниво са КНИГИТЕ; тап отваря съдържанието на
  /// книгата. Под името — последно четеното в нея (синьо, ако е и
  /// последно отвореното изобщо).
  Widget _booksBody(List<MolSection> tabList, String code) {
    // Псалтирът — и като ред тук, веднага след Часослова, както в плаващото
    // копче ([switcherCandidates]) — указание на потребителя, 05.10.2026. Същите раздели като в таба „Псалтир", не
    // копие; отворен оттук — с плаващото копче (`service`).
    final list = [...tabList, ..._sections.where((s) => s.tab == 'psaltir')];
    final byId = {for (final s in list) s.id: s};
    final books = bookOrder(tabList);
    if (list.length > tabList.length) {
      final at = books.indexOf('Часослов');
      books.insert(at < 0 ? 0 : at + 1, kPsalterBook);
    }
    return ListView.separated(
      controller: _scrollerFor(code),
      // Въздух под последния ред — да не е забит в долния ръб (потребителят).
      padding: const EdgeInsets.only(top: 8, bottom: 72),
      itemCount: books.length,
      separatorBuilder: (_, _) =>
          const Divider(height: 1, color: AppColors.sectionDivider),
      itemBuilder: (context, i) {
        final b = books[i];
        final last = byId[MolitvoslovBookLast.value[b]];
        final isLast = last != null && last.id == MolitvoslovLastSection.value;
        return Material(
          key: isLast ? _lastKey : null,
          color: isLast ? AppColors.rowSelected : Colors.transparent,
          child: InkWell(
            onTap: () async {
              await Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => MolitvoslovBook(
                      book: b, sections: list, service: b == kPsalterBook)));
              if (mounted) setState(() {});
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(children: [
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Expanded(
                            child: Text(b,
                                style: const TextStyle(
                                    color: AppColors.textPrimary, fontSize: 17)),
                          ),
                          LangChip(_bookLangs(list, b)),
                        ]),
                        if (last != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: Text(last.titleBg,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 13)),
                          ),
                      ]),
                ),
                const Icon(Icons.chevron_right, color: AppColors.textMuted),
              ]),
            ),
          ),
        );
      },
    );
  }

  /// Езиците на книгата — сборът от езиците на разделите ѝ.
  static List<String> _bookLangs(List<MolSection> list, String book) {
    final all = {for (final s in list) if (bookKeyOf(s) == book) ...s.langs};
    return [for (final l in const ['bg', 'csl', 'csr']) if (all.contains(l)) l];
  }
}
