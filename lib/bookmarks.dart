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
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'app_theme.dart';

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

  const BookmarksListScreen({super.key, required this.load});

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

  /// Копчето горе не сменя иконката си, когато влезем в режим „избиране" —
  /// вместо това тя леко се разтърсва и наедрява. Подсещането се повтаря,
  /// ако човек се позамисли и не предприеме нищо: таймерът се вдига наново
  /// при всяко докосване, така че разтърсването идва само след затишие.
  late final AnimationController _nudge = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
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
    _nudgeTimer?.cancel();
    _nudge.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final items = await widget.load();
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
      'Изтриване на всички отметки',
      'Наистина ли искате да изтриете ВСИЧКИ запазени отметки?',
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
      canPop: !_selectionMode,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _clearSelection();
      },
      child: _buildScaffold(items),
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
            : const Text('Списък с отметки'),
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
                  icon: AnimatedBuilder(
                    animation: _nudge,
                    builder: (context, child) {
                      final t = _nudge.value;
                      if (t == 0) return child!;
                      // Затихващо махало: люлее се все по-слабо, а
                      // наедряването върви и обратно, за да не „подскочи"
                      // иконката в края.
                      final angle = math.sin(t * math.pi * 6) * 0.28 * (1 - t);
                      final scale = 1 + math.sin(t * math.pi) * 0.22;
                      return Transform.rotate(
                        angle: angle,
                        child: Transform.scale(scale: scale, child: child),
                      );
                    },
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
                  ? const Center(
                      child: Text(
                        'Няма запазени отметки.',
                        style: TextStyle(
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
