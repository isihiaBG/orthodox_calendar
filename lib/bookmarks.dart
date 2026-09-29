// bookmarks.dart
//
// Списъкът с отметки — ЕДИН за цялото приложение.
//
// Тук няма нищо за жития, служби, книги или бази. Екранът получава готови
// записи и всеки от тях сам знае как се отваря и как се трие. Затова
// четците могат да добавят свой вид отметки, без този файл да се променя —
// и обратното: подобрение по списъка (избиране с задържане, разтърсването
// на кошчето, потвържденията) идва наведнъж за всички.
//
// Групите: житията вървят непосредствено, а отметките в книгите се събират
// под заглавието на своя том. Причината е практическа — един том носи
// стотици четива и изписването на заглавието му на всеки ред би заело
// повече място от самите отметки.

import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'edit_icon.dart';

/// Един запис в списъка.
class BookmarkEntry {
  /// Уникален ключ. Ползва се за сравнение при избора, тъй че трябва да е
  /// стойностно сравним и стабилен между две зареждания на списъка.
  final String id;

  /// Какво пише на реда.
  final String title;

  /// Втори ред — вид на четивото („Житие", „Служба", „Тропар и кондак") или
  /// глава от книга.
  final String typeLabel;

  /// Заглавие на групата. Празно = записът върви без група (житията).
  final String group;

  final int savedAtMs;

  /// Изтрива САМО този запис.
  final Future<void> Function() delete;

  /// Отваря четивото. Получава контекста на списъка, за да може да
  /// навигира и да покаже съобщение при грешка.
  final Future<void> Function(BuildContext) open;

  const BookmarkEntry({
    required this.id,
    required this.title,
    required this.typeLabel,
    required this.group,
    required this.savedAtMs,
    required this.delete,
    required this.open,
  });
}

/// Списък с всички запазени отметки.
///
/// Всеки ред: заглавие (натискане → отваря четивото) + вид отдолу + стрелка
/// вдясно. Моливчето горе (или задържане на ред) води в РЕДАКЦИЯ — ✕ на
/// всеки ред, „отмени" и „изтрий всички" горе. Устройството е преписано от
/// плаващото копче в богослужебните книги (`molitvoslov_book.dart`), за да
/// се учи веднъж. (Решение на потребителя, 29.09.2026.)
class BookmarksListScreen extends StatefulWidget {
  /// Откъде идват записите. Подава се отвън, за да не знае този файл нищо
  /// за четците (иначе се получава кръгов внос).
  final Future<List<BookmarkEntry>> Function() load;

  /// Заглавие на екрана.
  ///
  /// ⚠ Параметър, защото същият екран показва и ЛЮБИМИТЕ ЦИТАТИ. Двата
  /// списъка са различни по смисъл — отметката е „докъде съм стигнал",
  /// цитатът е „това ми хареса" — но се държат еднакво: подреждане по
  /// време, задържане за избиране, изтриване на много наведнъж. Един екран,
  /// две заглавия.
  final String screenTitle;

  /// Какво се пише, когато няма нищо.
  final String emptyText;

  /// Подаде ли се, в редакцията всеки ред получава ПЛЪЗГАЧ вляво.
  /// Получава id-тата в новия ред.
  ///
  /// Днес го ползват само ЛЮБИМИТЕ ЦИТАТИ: отметките са групирани по томове
  /// и разместване там няма смисъл.
  final Future<void> Function(List<String> ids)? onReorder;

  /// Множественото число за потвърждението („Изтриване на всички …").
  final String pluralNoun;

  const BookmarksListScreen({
    super.key,
    required this.load,
    this.screenTitle = 'Списък с отметки',
    this.emptyText = 'Няма запазени отметки',
    this.onReorder,
    this.pluralNoun = 'отметки',
  });

  @override
  State<BookmarksListScreen> createState() => _BookmarksListScreenState();
}

class _BookmarksListScreenState extends State<BookmarksListScreen> {
  List<BookmarkEntry>? _items;

  bool _editing = false;
  bool get _reorderable => widget.onReorder != null;

  /// ⚠ Промените в редакцията се ЗАПИСВАТ ЧАК ПРИ ИЗЛИЗАНЕ от нея — само така
  /// „отмени" може да върне и изтрит запис ([BookmarkEntry] знае как се трие,
  /// но не и как се връща). [_editStart] е списъкът при влизането, а
  /// [_history] — състоянията преди всяка стъпка.
  ///
  /// ⚠ ✕ трие БЕЗ питане — човекът е влязъл нарочно, а грешката се връща с
  /// „отмени". Пита се САМО при „изтрий всички", но и то е обикновена
  /// стъпка: списъкът остава в редакцията и „отмени" го връща; окончателно
  /// става чак при излизане. (Решение на потребителя, 29.09.2026.)
  List<BookmarkEntry> _editStart = const [];
  final _history = <List<BookmarkEntry>>[];

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _commitEdits(); // излизане насред редакцията
    super.dispose();
  }

  Future<void> _reload() async {
    // ⚠⚠ ГРЕШКАТА НЕ БИВА ДА ИЗГЛЕЖДА КАТО „ОЩЕ СЕ ЗАРЕЖДА".
    //
    // `_items == null` значи спинер. Хвърли ли `load()`, грешката се губи
    // като необработена асинхронна, полето остава `null` и екранът върти
    // безкрайно — точно това се случи с празния списък от цитати
    // (06.09.2026, виж [QuotesStore.load]).
    //
    // Същото правило вече е записано за `MiniReader`: всеки изглед, който
    // зарежда асинхронно, е длъжен да РАЗЛИЧАВА трите състояния —
    // зареждане / грешка / празно.
    List<BookmarkEntry> items;
    try {
      items = await widget.load();
    } catch (e, st) {
      debugPrint('Списъкът не се зареди: $e\n$st');
      items = const [];
    }
    if (!mounted) return;
    setState(() => _items = items);
  }

  // ─── редакцията ───

  void _startEditing() {
    if (_editing) return;
    setState(() {
      _editing = true;
      _editStart = [...?_items];
      _history.clear();
    });
  }

  void _finishEditing() {
    _commitEdits();
    if (mounted) setState(() => _editing = false);
  }

  /// Нанася промените: трие махнатите и записва реда. Вика се и от
  /// [dispose], тъй че не пипа състоянието на екрана.
  void _commitEdits() {
    if (!_editing) return;
    final now = [...?_items];
    final keep = {for (final e in now) e.id};
    for (final e in _editStart) {
      if (!keep.contains(e.id)) e.delete();
    }
    if (_reorderable && _history.isNotEmpty) {
      widget.onReorder!([for (final e in now) e.id]);
    }
    _history.clear();
    _editStart = const [];
  }

  void _undo() {
    if (_history.isEmpty) return;
    setState(() => _items = _history.removeLast());
  }

  void _removeNow(BookmarkEntry e) {
    setState(() {
      _history.add([...?_items]);
      _items = [...?_items]..removeWhere((x) => x.id == e.id);
    });
  }

  void _reorder(int a, int b) {
    final items = [...?_items];
    items.insert(b, items.removeAt(a));
    setState(() {
      _history.add([...?_items]);
      _items = items;
    });
  }

  Future<void> _deleteAll() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Изтриване на всички ${widget.pluralNoun}',
            style: const TextStyle(fontSize: 20)),
        content: Text(
            'Наистина ли искате да изтриете ВСИЧКИ запазени ${widget.pluralNoun}?',
            style: const TextStyle(fontSize: 16)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Не', style: TextStyle(fontSize: 20)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Да', style: TextStyle(fontSize: 20)),
          ),
        ],
      ),
    );
    if (result != true || !mounted) return;
    setState(() {
      _history.add([...?_items]);
      _items = <BookmarkEntry>[];
    });
  }

  Future<void> _open(BookmarkEntry e) => e.open(context);

  /// Редовете за рисуване: заглавие на група или запис.
  List<(String?, BookmarkEntry?)> _rows(List<BookmarkEntry> items) {
    final rows = <(String?, BookmarkEntry?)>[];
    String? current;
    for (final e in items) {
      final g = e.group;
      if (g.isNotEmpty && g != current) {
        rows.add((g, null));
        current = g;
      } else if (g.isEmpty) {
        current = null;
      }
      rows.add((null, e));
    }
    return rows;
  }

  // ─── рисуването ───

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return PopScope(
      // В редакцията „назад" излиза от нея, а не от екрана.
      canPop: !_editing,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _finishEditing();
      },
      child: Scaffold(
        backgroundColor: AppColors.toolbar,
        appBar: _appBar(items),
        body: SafeArea(
          child: Container(
            color: AppColors.background,
            child: items == null
                ? const Center(child: CircularProgressIndicator())
                : items.isEmpty && !_editing
                    ? Center(
                        child: Text(
                          widget.emptyText,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 16,
                          ),
                        ),
                      )
                    : (_editing && _reorderable
                        ? _reorderList(items)
                        : _groupedList(items)),
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _appBar(List<BookmarkEntry>? items) {
    final has = items != null && items.isNotEmpty;
    return AppBar(
      backgroundColor: AppColors.toolbar,
      // В редакцията вляво стои ✕ „Готово" — същото като в плаващото копче.
      leading: _editing
          ? IconButton(
              tooltip: 'Готово',
              icon: const Icon(Icons.close),
              onPressed: _finishEditing,
            )
          : null,
      title: Text(_editing
          ? (_reorderable ? 'Подредба' : 'Редакция')
          : widget.screenTitle),
      actionsPadding: EdgeInsets.zero,
      actions: [
        if (_editing) ...[
          IconButton(
            tooltip: 'Отмени',
            // ⚠ Цветът е ИЗРИЧЕН: в лентата AppBar налага своя преден цвят
            // и угасеното копче изглеждаше като живо. Сиво е, докато няма
            // стъпка за връщане — при влизане и след като „отмени" е
            // върнало всичко до началото.
            icon: Icon(Icons.undo,
                color: _history.isEmpty ? AppColors.textMuted : null),
            onPressed: _history.isEmpty ? null : _undo,
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: IconButton(
              tooltip: 'Изтрий всички',
              icon: Icon(Icons.delete_sweep_outlined,
                  color: has ? null : AppColors.textMuted),
              onPressed: has ? _deleteAll : null,
            ),
          ),
        ] else if (has)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: IconButton(
              tooltip: 'Редактирай',
              // Моливче върху лист — по-ясно „редактирай списъка" от голото
              // моливче (избор на потребителя, 29.09.2026).
              icon: const EditIcon(size: 26),
              onPressed: _startEditing,
            ),
          ),
      ],
    );
  }

  Widget _entryText(BookmarkEntry e) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            e.title,
            // ⚠ Таван на редовете заради ЦИТАТИТЕ: заглавието на житие е къс
            // ред, но маркиран откъс може да е цял абзац и без това един
            // запис би изял целия екран. Списъкът е за ориентиране, не за
            // четене — същото правило като при резултатите от търсенето.
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 16),
          ),
          const SizedBox(height: 3),
          Text(
            e.typeLabel,
            style: const TextStyle(color: AppColors.sectionTitle, fontSize: 13),
          ),
        ],
      );

  Widget _groupHeader(String title) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
        child: Text(
          title,
          style: const TextStyle(
            color: AppColors.sectionTitle,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      );

  /// Прегледът — и редакцията, когато няма разместване (отметките).
  Widget _groupedList(List<BookmarkEntry> items) {
    final rows = _rows(items);
    return ListView.separated(
      itemCount: rows.length,
      separatorBuilder: (_, i) {
        // Пред заглавие на група чертата е по-плътна — тя дели книгите
        // една от друга, а не редовете вътре в тях.
        final nextIsHeader = i + 1 < rows.length && rows[i + 1].$1 != null;
        return Divider(
          height: nextIsHeader ? 12 : 1,
          thickness: nextIsHeader ? 1 : 0,
          color: AppColors.sectionDivider,
        );
      },
      itemBuilder: (context, i) {
        final (header, entry) = rows[i];
        if (header != null) return _groupHeader(header);
        final e = entry!;
        return InkWell(
          onTap: _editing ? null : () => _open(e),
          // Задържането е другият вход в редакцията, освен моливчето.
          onLongPress: _editing ? null : _startEditing,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
            child: Row(children: [
              Expanded(child: _entryText(e)),
              _editing
                  ? IconButton(
                      tooltip: 'Махни',
                      icon: const Icon(Icons.close,
                          color: AppColors.textSecondary, size: 20),
                      onPressed: () => _removeNow(e),
                    )
                  : IconButton(
                      tooltip: 'Отвори',
                      icon: const Icon(Icons.chevron_right,
                          color: AppColors.textSecondary),
                      onPressed: () => _open(e),
                    ),
            ]),
          ),
        );
      },
    );
  }

  /// Редакцията с разместване (любимите цитати — без групи).
  Widget _reorderList(List<BookmarkEntry> items) {
    return ReorderableListView(
      buildDefaultDragHandles: false,
      // Влаченият ред се повдига като карта — същото като в плаващото копче.
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
      onReorderItem: _reorder,
      children: [
        for (var i = 0; i < items.length; i++)
          Container(
            key: ValueKey(items[i].id),
            decoration: const BoxDecoration(
                border: Border(
                    bottom: BorderSide(
                        color: AppColors.sectionDivider, width: 0.5))),
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(children: [
              ReorderableDragStartListener(
                index: i,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  child:
                      Icon(Icons.drag_indicator, color: AppColors.textMuted),
                ),
              ),
              Expanded(child: _entryText(items[i])),
              IconButton(
                tooltip: 'Махни',
                icon: const Icon(Icons.close,
                    color: AppColors.textSecondary, size: 20),
                onPressed: () => _removeNow(items[i]),
              ),
              const SizedBox(width: 8),
            ]),
          ),
      ],
    );
  }
}
