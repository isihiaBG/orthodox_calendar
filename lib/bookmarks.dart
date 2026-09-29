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

import 'dart:async';

import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'nudge_shake.dart';

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
/// Всеки ред: заглавие (натискане → отваря четивото) + вид отдолу + кошче
/// вдясно. Задържане включва режим „избиране" за трупно изтриване.
/// „Изтрий всички" — иконката в лентата отгоре.
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

  /// Подаде ли се, списъкът минава на РЕЖИМ НА РЕДАКТИРАНЕ по образеца на
  /// плаващото копче в богослужебните книги (`molitvoslov_book.dart`):
  ///
  ///   преглед    ред → стрелка „отвори"; моливче горе вдясно
  ///   редакция   плъзгач вляво, ✕ вдясно, „изтрий всички" горе
  ///
  /// ⚠ Кошчето на всеки ред изчезва от прегледа нарочно — там то стоеше до
  /// пръста и се натискаше неволно. ✕ в редакцията трие БЕЗ питане (човекът
  /// вече е влязъл нарочно, за да махне нещо); пита се САМО при „изтрий
  /// всички" (решение на потребителя, 29.09.2026).
  ///
  /// Получава id-тата в новия ред. Днес го ползват само ЛЮБИМИТЕ ЦИТАТИ:
  /// отметките са групирани по томове и разместване там няма смисъл.
  final Future<void> Function(List<String> ids)? onReorder;

  const BookmarksListScreen({
    super.key,
    required this.load,
    this.screenTitle = 'Списък с отметки',
    this.emptyText = 'Няма запазени отметки',
    this.onReorder,
  });

  @override
  State<BookmarksListScreen> createState() => _BookmarksListScreenState();
}

class _BookmarksListScreenState extends State<BookmarksListScreen>
    with SingleTickerProviderStateMixin {
  List<BookmarkEntry>? _items;

  /// Избраните редове. Режимът „избиране" се пази с ОТДЕЛЕН флаг, а не се
  /// познава по това дали има избрани: докосването върху маркиран ред го
  /// размаркира, та човек лесно стига до нула избрани насред работата си —
  /// а тогава изхвърлянето от режима значи ново задържане на пръста.
  /// Излиза се само нарочно: с ✕, с „назад" или след изтриване.
  final _selected = <String>{};
  bool _selectionMode = false;

  /// Режимът на редактиране — само при [BookmarksListScreen.onReorder].
  bool _editing = false;
  bool get _editable => widget.onReorder != null;

  /// ⚠ Промените в редакцията се ЗАПИСВАТ ЧАК ПРИ ИЗЛИЗАНЕ от нея — само така
  /// „отмени" може да върне и изтрит запис ([BookmarkEntry] знае как се трие,
  /// но не и как се връща). [_editStart] е списъкът при влизането, а
  /// [_history] — състоянията преди всяка стъпка.
  List<BookmarkEntry> _editStart = const [];
  final _history = <List<BookmarkEntry>>[];

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
    if (_history.isNotEmpty) widget.onReorder!([for (final e in now) e.id]);
    _history.clear();
    _editStart = const [];
  }

  void _undo() {
    if (_history.isEmpty) return;
    setState(() => _items = _history.removeLast());
  }

  /// Копчето горе не сменя иконката си, когато влезем в режим „избиране" —
  /// вместо това тя леко се разтърсва и наедрява. Подсещането се повтаря,
  /// ако човек се позамисли и не предприеме нищо: таймерът се вдига наново
  /// при всяко докосване, така че разтърсването идва само след затишие.
  late final AnimationController _nudge = AnimationController(
    vsync: this,
    duration: kNudgeBump,
  );
  Timer? _nudgeTimer;
  static const _nudgePause = Duration(seconds: 4);

  void _toggle(String id) {
    setState(() {
      _selectionMode = true;
      if (!_selected.remove(id)) _selected.add(id);
    });
    _restartNudge();
  }

  void _clearSelection() {
    setState(() {
      _selected.clear();
      _selectionMode = false;
    });
    _restartNudge(); // спира таймера — вече няма какво да подсеща
  }

  void _restartNudge() {
    _nudgeTimer?.cancel();
    // Няма какво да подсеща, докато не е избрано поне едно.
    if (!_selectionMode || _selected.isEmpty) {
      _nudge.stop();
      return;
    }
    _nudge.forward(from: 0);
    _nudgeTimer = Timer.periodic(_nudgePause, (_) {
      if (!mounted || !_selectionMode || _selected.isEmpty) return;
      _nudge.forward(from: 0);
    });
  }

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _commitEdits(); // излизане със системния „назад" насред редакцията
    _nudgeTimer?.cancel();
    _nudge.dispose();
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

  Future<bool> _confirm(String title, String content) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title, style: const TextStyle(fontSize: 20)),
        content: Text(content, style: const TextStyle(fontSize: 16)),
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
    return result ?? false;
  }

  Future<void> _deleteOne(BookmarkEntry e) async {
    final confirmed = await _confirm(
      'Изтриване на отметката',
      'Наистина ли искате да изтриете тази отметка?',
    );
    if (!confirmed) return;
    await e.delete();
    _reload();
  }

  Future<void> _deleteAll() async {
    final confirmed = await _confirm(
      _editable ? 'Изтриване на всички цитати' : 'Изтриване на всички отметки',
      _editable
          ? 'Наистина ли искате да изтриете ВСИЧКИ запазени цитати?'
          : 'Наистина ли искате да изтриете ВСИЧКИ запазени отметки?',
    );
    if (!confirmed) return;
    for (final e in _items ?? const <BookmarkEntry>[]) {
      await e.delete();
    }
    _reload();
  }

  Future<void> _deleteSelected() async {
    final confirmed = await _confirm(
      'Изтриване на избраните отметки',
      'Наистина ли искате да изтриете избраните отметки?',
    );
    if (!confirmed) return;
    for (final e in _items ?? const <BookmarkEntry>[]) {
      if (_selected.contains(e.id)) await e.delete();
    }
    if (!mounted) return;
    _clearSelection();
    _reload();
  }

  Future<void> _open(BookmarkEntry e) => e.open(context);

  /// ✕ в редакцията — без питане; връща се с „отмени".
  void _removeNow(BookmarkEntry e) {
    setState(() {
      _history.add([...?_items]);
      _items = [...?_items]..removeWhere((x) => x.id == e.id);
    });
  }

  /// „Изтрий всички" — единственото, което пита, и затова е ОКОНЧАТЕЛНО:
  /// не минава през „отмени".
  Future<void> _deleteAllEditing() async {
    final confirmed = await _confirm(
      'Изтриване на всички цитати',
      'Наистина ли искате да изтриете ВСИЧКИ запазени цитати?',
    );
    if (!confirmed) return;
    for (final e in _editStart) {
      await e.delete();
    }
    _history.clear();
    _editStart = const [];
    if (!mounted) return;
    setState(() {
      _items = const [];
      _editing = false;
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

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return PopScope(
      // Докато има избрани редове, „назад" излиза от режима, а не от
      // екрана — иначе човек губи списъка вместо избора си.
      canPop: !_selectionMode && !_editing,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_editing) {
          _finishEditing();
        } else {
          _clearSelection();
        }
      },
      child: _editable ? _buildEditableScaffold(items) : _buildScaffold(items),
    );
  }

  Widget _buildScaffold(List<BookmarkEntry>? items) {
    return Scaffold(
      backgroundColor: AppColors.toolbar,
      appBar: AppBar(
        backgroundColor: AppColors.toolbar,
        // В режим „избиране" на мястото на стрелката „назад" стои изричен
        // „Отказ" — думата се чете еднозначно, докато ✕ оставя съмнение
        // дали ще затвори екрана, или само ще изчисти избора.
        leading: _selectionMode ? const SizedBox.shrink() : null,
        leadingWidth: _selectionMode ? 0 : null,
        title: _selectionMode
            ? Row(
                children: [
                  TextButton.icon(
                    onPressed: _clearSelection,
                    icon: const Icon(Icons.close, size: 20),
                    label: const Text('Отказ', style: TextStyle(fontSize: 16)),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.textPrimary,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                    ),
                  ),
                  const SizedBox(width: 4),
                  // Броячът отстъпва пръв, ако мястото не стигне — по-важно
                  // е изходът от режима да се вижда изцяло.
                  Flexible(
                    child: Text(
                      'Избрани: ${_selected.length}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              )
            : Text(widget.screenTitle),
        // actionsPadding: нула, за да МАХНЕМ вградения отстъп на AppBar-а и
        // сами да контролираме десния отстъп (виж contentPadding на
        // ListTile-овете долу) — за да легнат кошчетата едно точно под
        // друго, и двете разстояния трябва да идват от НАС, не от
        // framework подразбирания, които може да са различни едно от друго.
        actionsPadding: EdgeInsets.zero,
        actions: [
          if (items != null && items.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Tooltip(
                message: _selectionMode ? 'Изтрий избраните' : 'Изтрий всички',
                child: IconButton(
                  // Едно и също копче с две задачи. Иконката не се сменя —
                  // че режимът е друг, се вижда от заглавието и от лекото
                  // разтърсване, което се повтаря през няколко секунди.
                  icon: NudgeShake(
                    animation: _nudge,
                    child: const Icon(Icons.delete_sweep_outlined),
                  ),
                  // Без избрани копчето е угасено — така се вижда, че
                  // чака избор, вместо да изтрие всичко по погрешка.
                  onPressed: _selectionMode
                      ? (_selected.isEmpty ? null : _deleteSelected)
                      : _deleteAll,
                ),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: Container(
          color: AppColors.background,
          child: items == null
              ? const Center(child: CircularProgressIndicator())
              : items.isEmpty
                  ? Center(
                      child: Text(
                        widget.emptyText,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 16,
                        ),
                      ),
                    )
                  : _list(_rows(items)),
        ),
      ),
    );
  }

  // ─── списъкът с редакция (любимите цитати) ───

  Widget _buildEditableScaffold(List<BookmarkEntry>? items) {
    final has = items != null && items.isNotEmpty;
    return Scaffold(
      backgroundColor: AppColors.toolbar,
      appBar: AppBar(
        backgroundColor: AppColors.toolbar,
        // В редакцията вляво стои ✕ „Готово" — същото като в плаващото копче.
        leading: _editing
            ? IconButton(
                tooltip: 'Готово',
                icon: const Icon(Icons.close),
                onPressed: _finishEditing,
              )
            : null,
        title: Text(_editing ? 'Подредба' : widget.screenTitle),
        actionsPadding: EdgeInsets.zero,
        actions: [
          if (_editing)
            IconButton(
              tooltip: 'Отмени',
              icon: const Icon(Icons.undo),
              onPressed: _history.isEmpty ? null : _undo,
            ),
          if (has || _editing)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _editing
                  ? IconButton(
                      tooltip: 'Изтрий всички',
                      icon: const Icon(Icons.delete_sweep_outlined),
                      onPressed: _editStart.isEmpty ? null : _deleteAllEditing,
                    )
                  : IconButton(
                      tooltip: 'Подреди',
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: _startEditing,
                    ),
            ),
        ],
      ),
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
                  : (_editing ? _editList(items) : _viewList(items)),
        ),
      ),
    );
  }

  Widget _entryText(BookmarkEntry e) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            e.title,
            // ⚠ Таван на редовете — цитатът може да е цял абзац (виж _list).
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

  Widget _viewList(List<BookmarkEntry> items) {
    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: (_, _) =>
          const Divider(height: 1, thickness: 0, color: AppColors.sectionDivider),
      itemBuilder: (context, i) {
        final e = items[i];
        return InkWell(
          onTap: () => _open(e),
          // Задържането е другият вход в редакцията, освен моливчето.
          onLongPress: _startEditing,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
            child: Row(children: [
              Expanded(child: _entryText(e)),
              IconButton(
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

  Widget _editList(List<BookmarkEntry> items) {
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

  Widget _list(List<(String?, BookmarkEntry?)> rows) {
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
        if (header != null) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
            child: Text(
              header,
              style: const TextStyle(
                color: AppColors.sectionTitle,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          );
        }
        final e = entry!;
        final picked = _selected.contains(e.id);
        // Фонът се рисува от НАС, а не през ListTile. selectedTileColor
        // минава през Ink и в този вложен списък не се появяваше изобщо.
        return AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          color: picked ? AppColors.rowSelected : Colors.transparent,
          child: ListTile(
            // Десен отстъп = точно колкото добавихме на „Изтрий всички" в
            // лентата отгоре (виж AppBar.actionsPadding) — за да легне
            // кошчето точно под него.
            contentPadding: const EdgeInsets.only(left: 16, right: 16),
            // Задържане отваря режима за избиране; след това обикновеното
            // докосване вече не отваря четивото, а добавя/маха реда.
            onLongPress: () => _toggle(e.id),
            onTap: () => _selectionMode ? _toggle(e.id) : _open(e),
            title: Text(
              e.title,
              // ⚠ Таван на редовете заради ЦИТАТИТЕ: заглавието на житие е
              // къс ред, но маркиран откъс може да е цял абзац и без това
              // един запис би изял целия екран. Списъкът е за ориентиране,
              // не за четене — същото правило като при резултатите от
              // търсенето (виж CLAUDE.md).
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 16,
              ),
            ),
            subtitle: Text(
              e.typeLabel,
              style: const TextStyle(
                color: AppColors.sectionTitle,
                fontSize: 13,
              ),
            ),
            // В режим „избиране" кошчето на реда отстъпва мястото си на
            // отметка за избора — изтриването минава през копчето горе.
            trailing: _selectionMode
                ? Icon(
                    picked ? Icons.check_circle : Icons.circle_outlined,
                    color:
                        picked ? AppColors.textPrimary : AppColors.textMuted,
                  )
                : IconButton(
                    icon: const Icon(
                      Icons.delete_outline,
                      color: AppColors.textSecondary,
                    ),
                    onPressed: () => _deleteOne(e),
                  ),
          ),
        );
      },
    );
  }
}
