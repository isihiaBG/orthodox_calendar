// „Звук" — всички записи за слушане на едно място (13.10.2026, искане на
// автора): книга → глави; житията по свт. Димитрий Ростовски — по месеци.
// Оттук се сваля и трие; моливчето отваря редакция като в списъка с
// отметки — отметки, „Изтрий звука", „Отмени" и „Избери всички", а
// файловете се трият чак при излизане от редакцията.
//
// ⚠ Мрежа само по воля на човека: регистърът се чете от телефона (и от
// копието в пакета); „Провери за звук" (↻) и свалянето теглят.
// ⚠ Заглавията идват от съдържанието на САМАТА книга — нова озвучена книга
// влиза тук сама, без промяна в кода.

import 'dart:async';

import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'audio_ui.dart';
import 'audiobook.dart';
import 'book_reader.dart';
import 'chitalnya_books.dart';
import 'edit_icon.dart';
import 'epub_source.dart';

const _months = ['Януари', 'Февруари', 'Март', 'Април', 'Май', 'Юни', 'Юли', 'Август',
  'Септември', 'Октомври', 'Ноември', 'Декември'];

/// Една книга със звук: пътят, видимото име и главите (част → заглавие).
class _AudioBookInfo {
  final String asset;
  final String name;
  final int? month; // житията по месеци — номерът на тома
  final List<(String, String)> parts;
  _AudioBookInfo(this.asset, this.name, this.month, this.parts);
  AudioBook get book => AudioBook.forAsset(asset)!;
}

Future<List<_AudioBookInfo>> _loadBooks() async {
  await AudioRegistry.load();
  final out = <_AudioBookInfo>[];
  for (final asset in AudioRegistry.books) {
    final parts = AudioRegistry.entry(asset)!.$2.keys.where((k) => !k.startsWith('note')).toList();
    final titles = <String, String>{};
    String name = asset.split('/').last;
    int? month;
    try {
      final epub = await EpubBook.open(asset);
      name = epub.title;
      // Листът печели пред деня, който дели файла с него (томовете).
      for (final top in epub.toc) {
        for (final e in top.flattened()) {
          final p = AudioBook.partOf(e.href);
          if (p != null && (e.children.isEmpty || !titles.containsKey(p))) titles[p] = e.title;
        }
      }
    } catch (_) {}
    final ch = kChitalnyaBooks.where((b) => b.epub == asset);
    if (ch.isNotEmpty) name = ch.first.short;
    final m = RegExp(r' - (\d\d)\(').firstMatch(asset);
    if (asset.startsWith('assets/books/') && m != null) month = int.parse(m.group(1)!);
    parts.sort((a, b) => a == 'title' ? -1 : b == 'title' ? 1 : a.compareTo(b));
    out.add(_AudioBookInfo(asset, name, month, [
      for (final p in parts) (p, p == 'title' ? 'Начало' : (titles[p] ?? p)),
    ]));
  }
  out.sort((a, b) => (a.month ?? 0).compareTo(b.month ?? 0));
  return out;
}

/// Отваря главата в четеца на книгата ѝ и пуска звука (тап в списъка).
Future<void> _openAndPlay(BuildContext context, String asset, String part) async {
  final nav = Navigator.of(context);
  final book = await EpubBook.open(asset);
  EpubTocEntry? hit;
  for (final e in book.toc.expand((e) => e.flattened())) {
    if (e.href.isEmpty || AudioBook.partOf(e.href) != part) continue;
    // Денят дели файла с житието си — печели листът (самото четиво).
    if (hit == null || e.children.isEmpty) hit = e;
    if (e.children.isEmpty) break;
  }
  if (hit == null) return;
  await nav.push(MaterialPageRoute(
      builder: (_) => BookReader(book: book, start: hit, playOnOpen: true)));
}

class AudioManageScreen extends StatefulWidget {
  const AudioManageScreen({super.key});

  @override
  State<AudioManageScreen> createState() => _AudioManageScreenState();
}

class _AudioManageScreenState extends State<AudioManageScreen> {
  List<_AudioBookInfo>? _books;
  bool _edit = false;
  final Set<(String, String)> _selected = {};
  final List<Set<(String, String)>> _undo = [];
  final Set<(String, String)> _pending = {}; // изтрити видимо, още на диска
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    AudioRegistry.revision.addListener(_reload);
    _reload();
  }

  @override
  void dispose() {
    AudioRegistry.revision.removeListener(_reload);
    unawaited(_commit());
    super.dispose();
  }

  Future<void> _reload() async {
    final b = await _loadBooks();
    if (mounted) setState(() => _books = b);
  }

  Future<void> _commit() async {
    if (_pending.isEmpty) return;
    final by = <String, List<String>>{};
    for (final (a, p) in _pending) {
      by.putIfAbsent(a, () => []).add(p);
    }
    _pending.clear();
    _undo.clear();
    for (final e in by.entries) {
      await AudioBook.forAsset(e.key)?.removeMany(e.value);
    }
  }

  Future<void> _check() async {
    setState(() => _checking = true);
    final err = await AudioRegistry.check();
    if (!mounted) return;
    setState(() => _checking = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(err ?? 'Списъкът със звука е обновен.')));
  }

  bool _isGot(_AudioBookInfo b, String p) =>
      b.book.isDownloaded(p) && !_pending.contains((b.asset, p));

  List<(String, String)> get _allGot => [
        for (final b in _books ?? <_AudioBookInfo>[])
          for (final (p, _) in b.parts)
            if (_isGot(b, p)) (b.asset, p)
      ];

  void _deleteSelected() {
    if (_selected.isEmpty) return;
    setState(() {
      _undo.add({..._selected});
      _pending.addAll(_selected);
      _selected.clear();
    });
  }

  void _undoLast() {
    if (_undo.isEmpty) return;
    setState(() => _pending.removeAll(_undo.removeLast()));
  }

  Future<void> _closeEdit() async {
    setState(() {
      _edit = false;
      _selected.clear();
    });
    await _commit();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final books = _books;
    final got = _allGot;
    final selBytes = _selected.fold<int>(
        0, (a, x) => a + (AudioBook.forAsset(x.$1)?.sizeOf(x.$2) ?? 0));
    return PopScope(
      canPop: !_edit,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _edit) _closeEdit();
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.toolbar,
          foregroundColor: Colors.white,
          leading: _edit
              ? IconButton(tooltip: 'Готово', icon: const Icon(Icons.close), onPressed: _closeEdit)
              : null,
          title: Text(
              _edit
                  ? (_selected.isEmpty
                      ? 'Избери за изтриване'
                      : 'Избрани: ${_selected.length} · ${audioSizeLabel(selBytes)}')
                  : 'Звук',
              style: const TextStyle(fontSize: 19)),
          actions: _edit
              ? [
                  IconButton(
                      tooltip: 'Отмени',
                      onPressed: _undo.isEmpty ? null : _undoLast,
                      icon: Icon(Icons.undo,
                          color: _undo.isEmpty ? Colors.white38 : Colors.white)),
                  IconButton(
                    tooltip: _selected.length == got.length ? 'Махни избора' : 'Избери всички',
                    onPressed: got.isEmpty
                        ? null
                        : () => setState(() {
                              if (_selected.length == got.length) {
                                _selected.clear();
                              } else {
                                _selected
                                  ..clear()
                                  ..addAll(got);
                              }
                            }),
                    icon: Icon(_selected.length == got.length && got.isNotEmpty
                        ? Icons.deselect
                        : Icons.select_all),
                  ),
                  TextButton.icon(
                    onPressed: _selected.isEmpty ? null : _deleteSelected,
                    icon: Icon(Icons.headset_off,
                        color: _selected.isEmpty ? Colors.white38 : Colors.white),
                    label: Text('Изтрий звука',
                        style: TextStyle(
                            color: _selected.isEmpty ? Colors.white38 : Colors.white)),
                  ),
                ]
              : [
                  IconButton(
                    tooltip: 'Провери за звук',
                    onPressed: _checking ? null : _check,
                    icon: _checking
                        ? const SizedBox(
                            width: 20, height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.refresh),
                  ),
                  IconButton(
                    tooltip: 'Редакция',
                    onPressed: got.isEmpty ? null : () => setState(() => _edit = true),
                    icon: EditIcon(size: 29, color: got.isEmpty ? Colors.white38 : null),
                  ),
                ],
        ),
        body: books == null
            ? const Center(child: CircularProgressIndicator())
            : books.isEmpty
                ? _empty()
                : ListView(
                    padding: const EdgeInsets.only(bottom: 72),
                    children: _sections(books),
                  ),
      ),
    );
  }

  Widget _empty() => Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'Още няма списък със звука. Натиснете ↻ („Провери за звук“) горе вдясно — '
          'приложението ще погледне какво може да се свали.',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 16, height: 1.4),
        ),
      );

  List<Widget> _sections(List<_AudioBookInfo> books) {
    final lives = books.where((b) => b.month != null).toList();
    final other = books.where((b) => b.month == null).toList();
    return [
      for (final b in other)
        _group(b.name, [for (final (p, t) in b.parts) _row(b, p, t)], b),
      if (lives.isNotEmpty)
        _group('Жития по свт. Димитрий Ростовски', [
          for (final b in lives)
            _group(_months[b.month! - 1], [for (final (p, t) in b.parts) _row(b, p, t)], b,
                nested: true),
        ], null),
    ];
  }

  Widget _group(String title, List<Widget> children, _AudioBookInfo? b, {bool nested = false}) {
    // ⚠ Заглавието на групата СЛЕДИ свалянето и триенето (book.revision) —
    // иначе иконата „свали останалите" и броят оставаха стари до следващото
    // отваряне на екрана (автор, 13.10.2026).
    Widget? sub(_AudioBookInfo b) {
      final n = b.parts.where((x) => _isGot(b, x.$1)).length;
      final total = b.book.bytesOf([for (final x in b.parts) x.$1]);
      return Text('свалени $n от ${b.parts.length} · общо ${audioSizeLabel(total)}',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13));
    }

    Widget? trailing(_AudioBookInfo b) {
      if (_edit) return null;
      final book = b.book;
      if (book.bulkTotal != null) {
        // „Свали всички" тече — общият напредък на мястото на иконата.
        return SizedBox(
            width: 24, height: 24,
            child: CircularProgressIndicator(
                strokeWidth: 2.5, value: book.bulkFraction, color: AppColors.sectionTitle));
      }
      if (book.missingParts().isEmpty) return null;
      return IconButton(
        tooltip: 'Свали останалите',
        icon: const Icon(Icons.download, color: AppColors.textSecondary),
        onPressed: () => askAudioDownloadAll(context, book),
      );
    }

    Widget tile(Widget? subtitle, Widget? trail) => Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            key: PageStorageKey('audio-group-$title'),
            tilePadding: EdgeInsets.only(left: nested ? 28 : 16, right: 12),
            childrenPadding: EdgeInsets.only(left: nested ? 12 : 0),
            iconColor: AppColors.sectionTitle,
            collapsedIconColor: AppColors.textSecondary,
            initiallyExpanded: !nested,
            title: Text(title,
                style: TextStyle(
                    color: AppColors.sectionTitle,
                    fontSize: nested ? 16 : 17,
                    fontWeight: FontWeight.w600)),
            subtitle: subtitle,
            trailing: trail,
            children: children,
          ),
        );

    if (b == null) return tile(null, null);
    return ValueListenableBuilder<int>(
      valueListenable: b.book.revision,
      builder: (context, _, _) => tile(sub(b), trailing(b)),
    );
  }

  Widget _row(_AudioBookInfo b, String part, String title) {
    final book = b.book;
    final key = (b.asset, part);
    return ValueListenableBuilder<int>(
      valueListenable: book.revision,
      builder: (context, _, _) {
        final got = _isGot(b, part);
        final busy = book.isDownloading(part);
        Widget trailing;
        if (_edit) {
          trailing = got
              ? Checkbox(
                  value: _selected.contains(key),
                  activeColor: AppColors.sectionTitle,
                  onChanged: (v) => setState(() => v == true ? _selected.add(key) : _selected.remove(key)),
                )
              : const SizedBox(width: 48);
        } else if (busy) {
          trailing = SizedBox(
              width: 22, height: 22,
              child: CircularProgressIndicator(
                  strokeWidth: 2, value: book.progress[part], color: AppColors.sectionTitle));
        } else if (got) {
          trailing = IconButton(
            tooltip: 'Слушай',
            icon: const Icon(Icons.headphones, color: AppColors.sectionTitle, size: 22),
            onPressed: () => _openAndPlay(context, b.asset, part),
          );
        } else {
          trailing = IconButton(
            tooltip: 'Свали',
            icon: const Icon(Icons.download, color: AppColors.textSecondary),
            onPressed: () => downloadAudioWithPrompt(context, book, part, title: title),
          );
        }
        return ListTile(
          dense: true,
          contentPadding: const EdgeInsets.only(left: 32, right: 12),
          title: Text(title, style: const TextStyle(color: AppColors.textPrimary, fontSize: 15)),
          subtitle: Text(audioSizeLabel(book.sizeOf(part)),
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          trailing: trailing,
          // Тап по реда — отваря четивото и пуска звука (несвалено — първо
          // пита за сваляне); в редакцията — отметка.
          onTap: _edit
              ? (got
                  ? () => setState(() => _selected.contains(key) ? _selected.remove(key) : _selected.add(key))
                  : null)
              : () => _openAndPlay(context, b.asset, part),
        );
      },
    );
  }
}
