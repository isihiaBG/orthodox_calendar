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
import 'molitvoslov_lang_chip.dart';
import 'molitvoslov_reader.dart';
import 'molitvoslov_settings.dart';

/// Плъзга ВИДИМО до реда с [key] — както съдържанието на Библията
/// (`_revealAnchor` там): списъкът е мързелив, тъй че далечен ред още не е
/// построен и `ensureVisible` няма за какво да се хване. Затова първо се
/// плъзга по ОЦЕНКА [estimate] (което го построява), после се донамества.
/// ⚠ Голото `return` при непостроен ред е тихият отказ, платен вече
/// няколко пъти в проекта.
Future<void> glideToRow(ScrollController ctrl, GlobalKey key, double estimate,
    bool Function() alive, [int attempt = 0]) async {
  if (!alive()) return;
  final ctx = key.currentContext;
  if (ctx != null) {
    await Scrollable.ensureVisible(ctx,
        alignment: 0.3,
        duration: Duration(milliseconds: attempt == 0 ? 450 : 220),
        curve: Curves.easeOutCubic);
    return;
  }
  if (attempt >= 8) return;
  if (!ctrl.hasClients) {
    WidgetsBinding.instance.addPostFrameCallback(
        (_) => glideToRow(ctrl, key, estimate, alive, attempt + 1));
    return;
  }
  final max = ctrl.position.maxScrollExtent;
  final want = (estimate - ctrl.position.viewportDimension * 0.3).clamp(0.0, max);
  // ⚠ Стигнато е до оценката, а редът още не е построен: оценката е по
  // НОМИНАЛНИ височини, а дългите заглавия (Минеите) се пренасят на два-три
  // реда — тоест реалното място е ПО-НАДОЛУ. Дотук тук стоеше голо `return`
  // и в Минеята списъкът спираше далеч преди днешната дата. Сега се върви
  // по още почти един екран надолу, докато редът се построи.
  if (attempt > 0 && (ctrl.offset - want).abs() < 1) {
    if (want >= max) return;
    await glideToRow(ctrl, key,
        estimate + ctrl.position.viewportDimension * 0.8, alive, attempt + 1);
    return;
  }
  final ms = (260 + (ctrl.offset - want).abs() * 0.38).clamp(260, 900).round();
  await ctrl.animateTo(want,
      duration: Duration(milliseconds: ms), curve: Curves.easeInOutCubic);
  await glideToRow(ctrl, key, estimate, alive, attempt + 1);
}

/// Псалтирът е свой таб, но за плаващото копче е КНИГА като останалите —
/// с него се кара Часословът (катизмите).
const String kPsalterBook = 'Псалтир';

/// Книгата, към която принадлежи разделът (null — не е богослужебна).
String? bookKeyOf(MolSection s) =>
    s.book ?? (s.tab == 'psaltir' ? kPsalterBook : null);

/// Заглавието на раздел в съдържание. В Псалтира диапазонът в скобите
/// („Катизма първа (псалми 1–8)") минава на СВОЙ ред: иначе в изправено
/// половината заглавия се пречупват насред скобите. Редовете са сбити
/// (height 1.15), за да стои скобата по-близо до своето заглавие, отколкото
/// до следващия ред в списъка (указание на потребителя).
Widget sectionTitleText(MolSection s, TextStyle style) {
  final m = s.tab == 'psaltir'
      ? RegExp(r'^(.*?)\s+(\([^()]*\))$').firstMatch(s.titleBg)
      : null;
  if (m == null) return Text(s.titleBg, style: style);
  final tight = style.copyWith(height: 1.15);
  return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(m.group(1)!, style: tight),
    // Диапазонът — посивен, за да не изпъква наравно с името (потребителят).
    Text(m.group(2)!, style: tight.copyWith(color: AppColors.textSecondary)),
  ]);
}

/// Чисти остарелите записи в [MolitvoslovBookLast] срещу ТЕКУЩАТА база.
void pruneBookLast(List<MolSection> all) {
  final byId = {for (final s in all) s.id: s};
  MolitvoslovBookLast.prune((id) {
    final s = byId[id];
    return s == null ? null : bookKeyOf(s);
  });
}

/// Книгите в реда на таба „Богослужебни".
List<String> bookOrder(List<MolSection> all) {
  final out = <String>[];
  for (final s in all) {
    final b = s.book;
    if (b != null && !out.contains(b)) out.add(b);
  }
  return out;
}

/// Всички книги, годни за копчето: Псалтирът — веднага след Часослова.
List<String> switcherCandidates(List<MolSection> all) {
  final out = bookOrder(all);
  if (all.any((s) => s.tab == 'psaltir')) {
    out.insert(out.isEmpty ? 0 : 1, kPsalterBook);
  }
  return out;
}

/// Отваря раздел от богослужебна книга и го запомня — общо място за
/// съдържанието на книгата и за плаващото копче.
void openBookSection(NavigatorState nav, MolSection s,
    {bool replace = false, bool service = false}) {
  MolitvoslovLastSection.set(s.id);
  final b = bookKeyOf(s);
  if (b != null) MolitvoslovBookLast.set(b, s.id);
  final route = MaterialPageRoute(
      builder: (_) => MolitvoslovReader(section: s, serviceMode: service));
  if (replace) {
    nav.pushReplacement(route);
  } else {
    nav.push(route);
  }
}

class MolitvoslovBook extends StatefulWidget {
  final String book;
  final List<MolSection> sections;

  /// Дошло през плаващото копче — разделите се отварят в режим „служба"
  /// (важи за Псалтира; виж [MolitvoslovReader.serviceMode]).
  final bool service;
  const MolitvoslovBook(
      {super.key, required this.book, required this.sections, this.service = false});

  @override
  State<MolitvoslovBook> createState() => _MolitvoslovBookState();
}

class _MolitvoslovBookState extends State<MolitvoslovBook> {
  final Set<String> _open = {};
  final GlobalKey _lastKey = GlobalKey();
  final ScrollController _scroll = ScrollController();

  // Номиналните височини — само за оценката; точното място дава ensureVisible.
  static const double _kHeaderH = 50, _kRowH = 48;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  List<MolSection> get _mine =>
      widget.sections.where((s) => bookKeyOf(s) == widget.book).toList();

  @override
  void initState() {
    super.initState();
    final last = MolitvoslovBookLast.value[widget.book];
    for (final s in _mine) {
      if (s.id == last && s.grp != null) _open.add(s.grp!);
    }
    _reveal(0);
  }

  /// Плъзга до последно четения раздел — виж [glideToRow].
  void _reveal(int attempt) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final last = MolitvoslovBookLast.value[widget.book];
      // ⚠ Запомненото id може да НЕ е от тази книга: базата се пресглобява и
      // номерата на разделите се разместват, а записът на телефона остава
      // стар. Тогава цикълът долу не спира и оценката излиза колкото целия
      // списък — екранът тръгваше надолу без нищо маркирано.
      if (last == null || !_mine.any((s) => s.id == last)) return;
      // Оценка: заглавията на групите и видимите редове преди последния.
      var y = 8.0;
      String? g;
      for (final s in _mine) {
        if (s.grp != g) {
          g = s.grp;
          if (g != null) y += _kHeaderH;
        }
        if (s.id == last) break;
        if (s.grp == null || _open.contains(s.grp)) y += _kRowH;
      }
      glideToRow(_scroll, _lastKey, y, () => mounted);
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
      // ⚠ Отстъп отстрани от изреза (в легнало камерата е на единия ръб и
      // текстът се пъхаше под нея). Горе/долу се пазят от лентата и системата.
      body: SafeArea(
        top: false,
        bottom: false,
        child: ListView(
          controller: _scroll,
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: rows,
        ),
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
          openBookSection(Navigator.of(context), s, service: widget.service);
          setState(() {});
        },
        child: Container(
          decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.sectionDivider, width: 0.5))),
          padding: EdgeInsets.fromLTRB(s.grp == null ? 16 : 28, 13, 16, 13),
          child: Row(children: [
            Expanded(
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: sectionTitleText(
                      s, const TextStyle(color: AppColors.textPrimary, fontSize: 16)),
                ),
                const SizedBox(width: 10),
                Transform.translate(offset: const Offset(0, -2), child: LangChip(s.langs)),
              ]),
            ),
            const SizedBox(width: 2),
            const Icon(Icons.chevron_right, color: AppColors.textMuted),
          ]),
        ),
      ),
    );
  }
}

/// Плаващото копче в четеца: списък с книгите, всяка с последно четения си
/// раздел. Тап върху реда отваря този раздел на мястото на текущия; копчето
/// вдясно — съдържанието на книгата. Моливчето горе — режим на редактиране
/// (разместване, махане, добавяне), запомня се в [MolitvoslovSwitcherBooks].
Future<void> showBookSwitcher(BuildContext context, MolSection current) async {
  final nav = Navigator.of(context);
  await Future.wait([MolitvoslovBookLast.loadOnce(), MolitvoslovSwitcherBooks.loadOnce()]);
  final all = await MolitvoslovDb.sections();
  pruneBookLast(all);
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.backgroundCard,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
    builder: (_) => _BookSwitcher(nav: nav, all: all, current: bookKeyOf(current)),
  );
}

class _BookSwitcher extends StatefulWidget {
  final NavigatorState nav;
  final List<MolSection> all;
  final String? current;
  const _BookSwitcher({required this.nav, required this.all, required this.current});

  @override
  State<_BookSwitcher> createState() => _BookSwitcherState();
}

class _BookSwitcherState extends State<_BookSwitcher> {
  late final List<String> _candidates = switcherCandidates(widget.all);
  late final List<String> _books = [
    for (final b in MolitvoslovSwitcherBooks.value ?? _candidates)
      if (_candidates.contains(b)) b,
  ];
  bool _editing = false;

  late final Map<int, MolSection> _byId = {for (final s in widget.all) s.id: s};

  List<String> get _missing => [for (final b in _candidates) if (!_books.contains(b)) b];

  void _save() => MolitvoslovSwitcherBooks.set(_books);

  void _contents(String book) {
    Navigator.of(context).pop();
    widget.nav.push(MaterialPageRoute(
        builder: (_) => MolitvoslovBook(book: book, sections: widget.all, service: true)));
  }

  void _open(String book) {
    final last = _byId[MolitvoslovBookLast.value[book]];
    if (last == null) return _contents(book);
    Navigator.of(context).pop();
    openBookSection(widget.nav, last, replace: true, service: true);
  }

  Future<void> _add() async {
    final miss = _missing;
    if (miss.isEmpty) return;
    final pick = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.backgroundCard,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const _SheetHandle(),
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 4, 24, 10),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('ДОБАВИ КНИГА', style: _kHeadStyle),
            ),
          ),
          for (final b in miss)
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 24),
              leading: const Icon(Icons.add_circle_outline, color: AppColors.sectionTitle),
              title: Text(b, style: const TextStyle(color: AppColors.textPrimary, fontSize: 17)),
              onTap: () => Navigator.of(ctx).pop(b),
            ),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (pick == null || !mounted) return;
    setState(() => _books.add(pick));
    _save();
  }

  @override
  Widget build(BuildContext context) {
    final maxH = MediaQuery.of(context).size.height * 0.8;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxH),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const _SheetHandle(),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: _editing ? _editHeader() : _viewHeader(),
          ),
          const Divider(height: 1, color: AppColors.sectionDivider),
          Flexible(child: _editing ? _editList() : _viewList()),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  // ─── горната лента ───

  Widget _viewHeader() => SizedBox(
        key: const ValueKey('view'),
        height: 52,
        child: Row(children: [
          const SizedBox(width: 24),
          const Expanded(child: Text('БОГОСЛУЖЕБНИ КНИГИ', style: _kHeadStyle)),
          IconButton(
            tooltip: 'Подреди списъка',
            icon: const Icon(Icons.edit_document, color: AppColors.textSecondary, size: 22),
            onPressed: () => setState(() => _editing = true),
          ),
          const SizedBox(width: 8),
        ]),
      );

  Widget _editHeader() {
    final canAdd = _missing.isNotEmpty;
    return SizedBox(
      key: const ValueKey('edit'),
      height: 52,
      child: Row(children: [
        const SizedBox(width: 8),
        IconButton(
          tooltip: 'Готово',
          icon: const Icon(Icons.close, color: AppColors.textPrimary),
          onPressed: () => setState(() => _editing = false),
        ),
        const Expanded(
          child: Text('Подредба на книгите',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textPrimary, fontSize: 16,
                  fontWeight: FontWeight.w600)),
        ),
        IconButton(
          tooltip: 'Добави книга',
          icon: Icon(Icons.add,
              color: canAdd ? AppColors.sectionTitle : AppColors.textMuted),
          onPressed: canAdd ? _add : null,
        ),
        const SizedBox(width: 8),
      ]),
    );
  }

  // ─── списъците ───

  Widget _viewList() {
    if (_books.isEmpty) return _empty();
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(vertical: 4),
      children: [for (final b in _books) _viewRow(b)],
    );
  }

  Widget _viewRow(String book) {
    final last = _byId[MolitvoslovBookLast.value[book]];
    final isCurrent = book == widget.current;
    return Material(
      color: isCurrent ? AppColors.rowSelected : Colors.transparent,
      child: InkWell(
        onTap: () => _open(book),
        child: Container(
          // Текущата книга — тънка синя черта вляво (като маркер в книга).
          decoration: BoxDecoration(
            border: Border(
                left: BorderSide(
                    color: isCurrent ? AppColors.sectionTitle : Colors.transparent,
                    width: 3)),
          ),
          padding: const EdgeInsets.fromLTRB(21, 10, 8, 10),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(book,
                    style: const TextStyle(color: AppColors.textPrimary, fontSize: 17)),
                const SizedBox(height: 2),
                Text(last?.titleBg ?? 'още не е отваряна',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: last == null ? AppColors.textMuted : AppColors.textSecondary,
                        fontSize: 13,
                        fontStyle: last == null ? FontStyle.italic : FontStyle.normal)),
              ]),
            ),
            IconButton(
              tooltip: 'Съдържание',
              icon: const Icon(Icons.format_list_bulleted, color: AppColors.textSecondary),
              onPressed: () => _contents(book),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _editList() {
    if (_books.isEmpty) return _empty();
    return ReorderableListView(
      shrinkWrap: true,
      buildDefaultDragHandles: false,
      padding: const EdgeInsets.symmetric(vertical: 4),
      // Влаченият ред се повдига като карта над останалите.
      proxyDecorator: (child, _, anim) => AnimatedBuilder(
        animation: anim,
        builder: (_, c) => Material(
          elevation: 6 * anim.value,
          color: AppColors.backgroundCard,
          borderRadius: BorderRadius.circular(10),
          child: c,
        ),
        child: child,
      ),
      // onReorderItem вече е поправил индекса за премахнатия ред.
      onReorderItem: (a, b) {
        setState(() => _books.insert(b, _books.removeAt(a)));
        _save();
      },
      children: [
        for (var i = 0; i < _books.length; i++)
          Container(
            key: ValueKey(_books[i]),
            height: 56,
            decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: AppColors.sectionDivider, width: 0.5))),
            child: Row(children: [
              ReorderableDragStartListener(
                index: i,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Icon(Icons.drag_indicator, color: AppColors.textMuted),
                ),
              ),
              Expanded(
                child: Text(_books[i],
                    style: const TextStyle(color: AppColors.textPrimary, fontSize: 17)),
              ),
              IconButton(
                tooltip: 'Махни от списъка',
                icon: const Icon(Icons.close, color: AppColors.textSecondary, size: 20),
                onPressed: () {
                  setState(() => _books.removeAt(i));
                  _save();
                },
              ),
              const SizedBox(width: 8),
            ]),
          ),
      ],
    );
  }

  Widget _empty() => const Padding(
        padding: EdgeInsets.fromLTRB(24, 28, 24, 28),
        child: Text('Списъкът е празен — добави книги с ＋ в режима на подредба.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary, fontSize: 14)),
      );
}

const TextStyle _kHeadStyle = TextStyle(
    color: AppColors.sectionTitle, fontSize: 13, fontWeight: FontWeight.w700,
    letterSpacing: 1.0);

class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 10, bottom: 6),
        child: Container(
          width: 36,
          height: 4,
          decoration: BoxDecoration(
              color: AppColors.textMuted, borderRadius: BorderRadius.circular(2)),
        ),
      );
}
