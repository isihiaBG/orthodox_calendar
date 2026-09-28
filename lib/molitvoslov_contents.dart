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
  /// съдържанието на Библията („самото движение е подсещането").
  /// ⚠ Непостроен ред се пробва пак на следващия кадър — голото `return` е
  /// тихият отказ, платен вече няколко пъти в проекта.
  void _revealLast(int tabIndex, int attempt) {
    final last = MolitvoslovLastSection.value;
    final tabs = _tabs;
    if (last == null || tabs == null) return;
    final inTab = _sections.any((s) => s.id == last && s.tab == tabs[tabIndex].code);
    if (!inTab) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ctx = _lastKey.currentContext;
      if (ctx == null) {
        if (attempt < 8) _revealLast(tabIndex, attempt + 1);
        return;
      }
      Scrollable.ensureVisible(ctx,
          alignment: 0.3,
          duration: const Duration(milliseconds: 450),
          curve: Curves.easeInOutCubic);
    });
  }

  @override
  void dispose() {
    _ctrl?.dispose();
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
      body: TabBarView(controller: _ctrl, children: [
        for (final t in tabs) _tabBody(t),
      ]),
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
    if (list.any((s) => s.book != null)) return _booksBody(list);
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
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
                child: Text(s.titleBg,
                    style: const TextStyle(
                        color: AppColors.textPrimary, fontSize: 17)),
              ),
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
  Widget _booksBody(List<MolSection> list) {
    final byId = {for (final s in list) s.id: s};
    final books = bookOrder(list);
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: books.length,
      separatorBuilder: (_, _) =>
          const Divider(height: 1, color: AppColors.sectionDivider),
      itemBuilder: (context, i) {
        final b = books[i];
        final last = byId[MolitvoslovBookLast.value[b]];
        final isLast = last != null && last.id == MolitvoslovLastSection.value;
        return Material(
          color: isLast ? AppColors.rowSelected : Colors.transparent,
          child: InkWell(
            onTap: () async {
              await Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => MolitvoslovBook(book: b, sections: list)));
              if (mounted) setState(() {});
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(children: [
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(b,
                            style: const TextStyle(
                                color: AppColors.textPrimary, fontSize: 17)),
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
}
