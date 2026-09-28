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
      final tabs = await MolitvoslovDb.tabs();
      final sections = await MolitvoslovDb.sections();
      if (!mounted) return;
      // ⚠ Контролерът се прави ВЕДНЪЖ, след като броят табове е известен —
      // слушател, окачен в build, би се добавял при всяко построяване.
      _ctrl = TabController(
          length: tabs.length,
          vsync: this,
          initialIndex: widget.initialTab.clamp(0, tabs.length - 1))
        ..addListener(() {
          if (!_ctrl!.indexIsChanging) MolitvoslovLastTab.set(_ctrl!.index);
        });
      setState(() {
        _tabs = tabs;
        _sections = sections;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
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
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: list.length,
      separatorBuilder: (_, _) =>
          const Divider(height: 1, color: AppColors.sectionDivider),
      itemBuilder: (context, i) {
        final s = list[i];
        return InkWell(
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => MolitvoslovReader(section: s))),
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
        );
      },
    );
  }
}
