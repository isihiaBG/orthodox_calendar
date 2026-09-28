// molitvoslov_book.dart
//
// „Богослужебни" е ДВУСТЕПЕНЕН (указание на потребителя): табът изрежда
// книгите (Часослов, Октоих, Минеи…), а тук е съдържанието на ЕДНА книга.
// Където книгата има подгрупи (месеците на Минеята, гласовете на Октоиха),
// те са разгъващи се заглавия — отворена е тази с последно четения раздел.
//
// Плюс [showBookSwitcher] — списъкът с книгите за плаващото копче в четеца:
// човек, който кара службата за деня, прескача между книгите и всяка го
// връща там, където е спрял в нея (MolitvoslovBookLast).

import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'molitvoslov_db.dart';
import 'molitvoslov_reader.dart';
import 'molitvoslov_settings.dart';

/// Книгите в реда на таба (и на плаващото копче).
List<String> bookOrder(List<MolSection> all) {
  final out = <String>[];
  for (final s in all) {
    final b = s.book;
    if (b != null && !out.contains(b)) out.add(b);
  }
  return out;
}

/// Отваря раздел от богослужебна книга и го запомня — общо място за
/// съдържанието на книгата и за плаващото копче.
void openBookSection(NavigatorState nav, MolSection s, {bool replace = false}) {
  MolitvoslovLastSection.set(s.id);
  if (s.book != null) MolitvoslovBookLast.set(s.book!, s.id);
  final route = MaterialPageRoute(builder: (_) => MolitvoslovReader(section: s));
  if (replace) {
    nav.pushReplacement(route);
  } else {
    nav.push(route);
  }
}

class MolitvoslovBook extends StatefulWidget {
  final String book;
  final List<MolSection> sections;
  const MolitvoslovBook({super.key, required this.book, required this.sections});

  @override
  State<MolitvoslovBook> createState() => _MolitvoslovBookState();
}

class _MolitvoslovBookState extends State<MolitvoslovBook> {
  final Set<String> _open = {};
  final GlobalKey _lastKey = GlobalKey();

  List<MolSection> get _mine =>
      widget.sections.where((s) => s.book == widget.book).toList();

  @override
  void initState() {
    super.initState();
    final last = MolitvoslovBookLast.value[widget.book];
    for (final s in _mine) {
      if (s.id == last && s.grp != null) _open.add(s.grp!);
    }
    _reveal(0);
  }

  /// Плъзга до последно четения раздел (виж съдържанието на молитвослова).
  void _reveal(int attempt) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ctx = _lastKey.currentContext;
      if (ctx == null) {
        if (attempt < 8) _reveal(attempt + 1);
        return;
      }
      Scrollable.ensureVisible(ctx,
          alignment: 0.3,
          duration: const Duration(milliseconds: 450),
          curve: Curves.easeInOutCubic);
    });
  }

  @override
  Widget build(BuildContext context) {
    final mine = _mine;
    final groups = <String?>[];
    for (final s in mine) {
      if (!groups.contains(s.grp)) groups.add(s.grp);
    }
    final rows = <Widget>[];
    for (final g in groups) {
      final items = mine.where((s) => s.grp == g).toList();
      if (g == null) {
        rows.addAll(items.map(_row));
        continue;
      }
      final open = _open.contains(g);
      rows.add(_groupHeader(g, open));
      if (open) rows.addAll(items.map(_row));
    }
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text(widget.book)),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: rows,
      ),
    );
  }

  Widget _groupHeader(String g, bool open) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => setState(() => open ? _open.remove(g) : _open.add(g)),
        child: Container(
          decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.sectionDivider))),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Row(children: [
            Expanded(
              child: Text(g.toUpperCase(),
                  style: const TextStyle(
                      color: AppColors.sectionTitle,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8)),
            ),
            AnimatedRotation(
              turns: open ? 0.5 : 0,
              duration: const Duration(milliseconds: 200),
              child: const Icon(Icons.expand_more, color: AppColors.sectionTitle),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _row(MolSection s) {
    final isLast = s.id == MolitvoslovBookLast.value[widget.book];
    return Material(
      key: isLast ? _lastKey : null,
      color: isLast ? AppColors.rowSelected : Colors.transparent,
      child: InkWell(
        onTap: () {
          openBookSection(Navigator.of(context), s);
          setState(() {});
        },
        child: Container(
          decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.sectionDivider, width: 0.5))),
          padding: EdgeInsets.fromLTRB(s.grp == null ? 16 : 28, 13, 16, 13),
          child: Row(children: [
            Expanded(
              child: Text(s.titleBg,
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 16)),
            ),
            const Icon(Icons.chevron_right, color: AppColors.textMuted),
          ]),
        ),
      ),
    );
  }
}

/// Плаващото копче в четеца на богослужебна книга: списък с книгите, всяка
/// с последно четения си раздел. Тап върху реда отваря този раздел на мястото
/// на текущия; копчето вдясно — съдържанието на книгата.
Future<void> showBookSwitcher(BuildContext context, MolSection current) async {
  final nav = Navigator.of(context);
  await MolitvoslovBookLast.loadOnce();
  final all = await MolitvoslovDb.sections();
  if (!context.mounted) return;
  final byId = {for (final s in all) s.id: s};
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.backgroundCard,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text('Богослужебни книги',
                style: TextStyle(color: AppColors.sectionTitle, fontSize: 15,
                    fontWeight: FontWeight.w700)),
          ),
          for (final b in bookOrder(all))
            _switcherRow(ctx, nav, b, byId[MolitvoslovBookLast.value[b]], all,
                current.book == b),
        ],
      ),
    ),
  );
}

Widget _switcherRow(BuildContext ctx, NavigatorState nav, String book,
    MolSection? last, List<MolSection> all, bool isCurrent) {
  void contents() {
    Navigator.of(ctx).pop();
    nav.push(MaterialPageRoute(
        builder: (_) => MolitvoslovBook(book: book, sections: all)));
  }

  return Material(
    color: isCurrent ? AppColors.rowSelected : Colors.transparent,
    child: InkWell(
      onTap: () {
        if (last == null) return contents();
        Navigator.of(ctx).pop();
        openBookSection(nav, last, replace: true);
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 8, 10),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(book,
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 17)),
              if (last != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(last.titleBg,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                ),
            ]),
          ),
          IconButton(
            tooltip: 'Съдържание',
            icon: const Icon(Icons.list, color: AppColors.textSecondary),
            onPressed: contents,
          ),
        ]),
      ),
    ),
  );
}
