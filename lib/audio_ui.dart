// audio_ui.dart
//
// Видимите части на четенето на глас (11.10.2026, по указание на автора):
//
//   AudioChip        етикетът в съдържанието — ТИХ, като този с езиците в
//                    молитвослова: несвалено (слушалки + ↓ + размер), сваля
//                    се (процент), свалено (слушалки)
//   AudioFab         плаващото копче долу вдясно — съдържанието е затворено,
//                    докато човек чете, а копчето е под ръка
//   askAudioDownload прозорчето „колко MB, безплатно" преди сваляне
//   AudioMiniPlayer  лентата отдолу: −5, пауза, +5, време, затваряне

import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'audiobook.dart';
import 'reader_theme.dart';

/// Пита, преди да свали. Връща `true` при „Свали".
Future<bool> askAudioDownload(BuildContext context, AudioBook book, String part,
    {required String title}) async {
  final palette = ReaderTheme.palette;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: palette.sheet,
      title: Text('Звукът на беседата', style: TextStyle(color: palette.ink, fontSize: 19)),
      content: Text(
        '„$title“\n\n'
        'Да сваля ли звука? ${audioSizeLabel(book.sizeOf(part))}, безплатно.\n'
        'След това се слуша и без интернет.',
        style: TextStyle(color: palette.ink, fontSize: 16, height: 1.35),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Назад')),
        FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Свали')),
      ],
    ),
  );
  return ok == true;
}

/// Сваля с прозорчето отпред; грешката се казва с човешки думи.
Future<bool> downloadAudioWithPrompt(BuildContext context, AudioBook book, String part,
    {required String title}) async {
  if (!await askAudioDownload(context, book, part, title: title)) return false;
  final err = await book.download(part);
  if (err != null && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
  }
  return err == null;
}

/// Пита и изтрива сваления звук — за освобождаване на място (искане на
/// автора, 11.10.2026: изслушана беседа човек може да не иска да пази).
Future<bool> askAudioDelete(BuildContext context, AudioBook book, String part,
    {required String title}) async {
  final palette = ReaderTheme.palette;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: palette.sheet,
      title: Text('Изтриване на звука', style: TextStyle(color: palette.ink, fontSize: 19)),
      content: Text(
        '„$title“\n\n'
        'Да изтрия ли звука от телефона? Освобождава ${audioSizeLabel(book.sizeOf(part))}. '
        'Може да се свали пак по всяко време.',
        style: TextStyle(color: palette.ink, fontSize: 16, height: 1.35),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Назад')),
        FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Изтрий')),
      ],
    ),
  );
  if (ok == true) await book.remove(part);
  return ok == true;
}

/// „Свали всички" — питане с общия размер, после сваляне поред. Общо за
/// етикета „↓ всички" и за менюто ⋮.
Future<void> askAudioDownloadAll(BuildContext context, AudioBook book) async {
  final todo = book.missingParts();
  if (todo.isEmpty) return;
  final bytes = todo.fold<int>(0, (a, p) => a + book.sizeOf(p));
  final palette = ReaderTheme.palette;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: palette.sheet,
      title: Text('Сваляне на звука', style: TextStyle(color: palette.ink, fontSize: 19)),
      content: Text(
        'Да сваля ли звука на всички ${todo.length} '
        '${todo.length == 1 ? 'глава' : 'глави'}, които още ги няма на телефона? '
        'Общо ${audioSizeLabel(bytes)}, безплатно. После се слушат и без интернет.',
        style: TextStyle(color: palette.ink, fontSize: 16, height: 1.35),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Назад')),
        FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Свали')),
      ],
    ),
  );
  if (ok != true) return;
  final messenger = ScaffoldMessenger.maybeOf(context);
  final err = await book.downloadAll();
  messenger?.showSnackBar(SnackBar(content: Text(err ?? 'Звукът е свален.')));
}

/// Пита и изтрива звука на няколко глави наведнъж (или на всички) — ЕДНО
/// питане с общия размер (искане на автора, 12.10.2026: едно по едно със
/// задържане беше бавно). [beforeRemove] спира плейъра, ако свири някоя от
/// тях. Връща `true`, ако е изтрито.
Future<bool> askAudioDeleteMany(BuildContext context, AudioBook book, List<String> parts,
    {Future<void> Function(Set<String>)? beforeRemove}) async {
  if (parts.isEmpty) return false;
  final palette = ReaderTheme.palette;
  final all = parts.length == book.downloadedParts().length;
  final n = parts.length;
  final glavi = '$n ${n == 1 ? 'глава' : 'глави'}';
  final what = all ? 'целия свален звук на книгата ($glavi)' : 'звука на $glavi';
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: palette.sheet,
      title: Text('Изтриване на звука', style: TextStyle(color: palette.ink, fontSize: 19)),
      content: Text(
        'Да изтрия ли $what от телефона? '
        'Освобождава ${audioSizeLabel(book.bytesOf(parts))}. '
        'Може да се свали пак по всяко време.',
        style: TextStyle(color: palette.ink, fontSize: 16, height: 1.35),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Назад')),
        FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Изтрий')),
      ],
    ),
  );
  if (ok != true) return false;
  await beforeRemove?.call(parts.toSet());
  await book.removeMany(parts);
  return true;
}

/// Етикетът в съдържанието.
class AudioChip extends StatelessWidget {
  final AudioBook book;
  final String part;
  final VoidCallback onTap;

  /// Задържане върху свален етикет — изтриване (с питане).
  final VoidCallback? onLongPress;

  /// Цветът на текста и иконките — в съдържанието той е мастилото на
  /// палитрата, за да личи и в СВЕТЛА тема (автора, 12.10.2026). Без него —
  /// приглушеното за тъмен фон.
  final Color? ink;
  const AudioChip(
      {super.key,
      required this.book,
      required this.part,
      required this.onTap,
      this.onLongPress,
      this.ink});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: book.revision,
      builder: (context, _, _) {
        if (!book.has(part)) return const SizedBox.shrink();
        final done = book.isDownloaded(part);
        final busy = book.isDownloading(part);
        final fg = ink ?? AppColors.textSecondary;
        final muted =
            TextStyle(color: fg, fontSize: 11.5, fontWeight: FontWeight.w600, height: 1.1);
        final Widget inner;
        if (busy) {
          inner = Text('${((book.progress[part] ?? 0) * 100).round()}%', style: muted);
        } else if (done) {
          inner = const Icon(Icons.headphones, size: 15, color: AppColors.sectionTitle);
        } else {
          inner = Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.headphones_outlined, size: 14, color: fg),
            const SizedBox(width: 4),
            Icon(Icons.file_download_outlined, size: 14, color: fg),
            const SizedBox(width: 1),
            Text(audioSizeLabel(book.sizeOf(part)), style: muted),
          ]);
        }
        return InkWell(
          onTap: busy ? null : onTap,
          onLongPress: done ? onLongPress : null,
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: (ink ?? AppColors.textPrimary).withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(5),
              ),
              child: inner,
            ),
          ),
        );
      },
    );
  }
}

/// Плаващото копче долу вдясно — видно само при глава със звук.
///
/// ⚠⚠ НЕ В ЛЕНТАТА (решено с автора, 11.10.2026). На изправен телефон лентата
/// на четеца е пълна — стрелка и съдържание отляво, шест копчета отдясно —
/// и седмото се блъскаше в съдържанието. Плаващото копче е като това в
/// молитвослова (същият `palette.fab`): самата му поява казва „тук има звук",
/// а щом звукът тръгне, на мястото му идва мини плейърът.
class AudioFab extends StatelessWidget {
  final AudioBook book;
  final String part;
  final VoidCallback onTap;
  const AudioFab({super.key, required this.book, required this.part, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: book.revision,
      builder: (context, _, _) {
        if (!book.has(part)) return const SizedBox.shrink();
        final p = ReaderTheme.palette;
        final done = book.isDownloaded(part);
        final busy = book.isDownloading(part);
        return Padding(
          padding: const EdgeInsets.only(right: 14, bottom: 8),
          child: FloatingActionButton.small(
            heroTag: null,
            tooltip: done ? 'Слушай беседата' : 'Свали звука на беседата',
            backgroundColor: p.fab,
            foregroundColor: p.ink,
            onPressed: busy ? null : onTap,
            child: busy
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, value: book.progress[part], color: p.ink))
                : done
                    ? const Icon(Icons.headphones)
                    // ⚠ Знакът „свали" е ДО слушалките, не върху тях
                    // (бележка на автора: стрелката ги застъпваше). Слушалките
                    // са по-малки и горе вляво, кръжецът — в долния десен
                    // ъгъл, а тънкият пръстен в цвета на копчето ги разделя.
                    : SizedBox(
                        width: 28,
                        height: 28,
                        child: Stack(children: [
                          const Positioned(
                              left: 0, top: 0, child: Icon(Icons.headphones_outlined, size: 20)),
                          Positioned(
                            right: 0,
                            bottom: 0,
                            child: Container(
                              width: 14,
                              height: 14,
                              decoration: BoxDecoration(
                                color: p.ink,
                                shape: BoxShape.circle,
                                border: Border.all(color: p.fab, width: 1.5),
                              ),
                              child: Icon(Icons.arrow_downward, size: 9, color: p.fab),
                            ),
                          ),
                        ]),
                      ),
          ),
        );
      },
    );
  }
}

/// Редът под кориците (Читалня, Месецослов): дали книгата има звук.
///
///   регистърът още не е свален  „🎧 Провери за звук" — копче, тегли го
///   книгата има звук            „🎧 Със звук: 3 глави · 1 свалена"
///   няма                        нищо (без излишни знаци — бележка на автора)
class CoverAudioLine extends StatefulWidget {
  final String assetPath;
  const CoverAudioLine(this.assetPath, {super.key});

  @override
  State<CoverAudioLine> createState() => _CoverAudioLineState();
}

class _CoverAudioLineState extends State<CoverAudioLine> {
  bool _checking = false;

  Future<void> _check() async {
    setState(() => _checking = true);
    final err = await AudioRegistry.check();
    if (!mounted) return;
    setState(() => _checking = false);
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final book = AudioBook.forAsset(widget.assetPath);
    if (book == null) return const SizedBox.shrink();
    return ValueListenableBuilder<int>(
      valueListenable: book.revision,
      builder: (context, _, _) {
        const style = TextStyle(color: AppColors.textSecondary, fontSize: 13.5);
        if (!AudioRegistry.known) {
          return TextButton.icon(
            onPressed: _checking ? null : _check,
            style: TextButton.styleFrom(
                foregroundColor: AppColors.textSecondary,
                visualDensity: VisualDensity.compact),
            icon: _checking
                ? const SizedBox(
                    width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.headphones_outlined, size: 17),
            label: const Text('Провери за звук', style: style),
          );
        }
        final (n, got) = book.counts();
        if (n == 0) return const SizedBox.shrink();
        final row = Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.headphones, size: 16, color: AppColors.sectionTitle),
            const SizedBox(width: 6),
            Text(
                'Със звук: $n ${n == 1 ? 'глава' : 'глави'}'
                '${got > 0 ? ' · $got ${got == 1 ? 'свалена' : 'свалени'}' : ''}',
                style: style),
            // Същото „всички" и ⋮ като на първия ред в съдържанието.
            AudioDownloadAllButton(book),
            AudioMoreButton(book),
          ]),
        );
        // Докато тече „Свали всички" — лента с общия напредък по байтове и
        // колко MB от колко: може да трае минути (искане на автора).
        if (book.bulkTotal != null) {
          final (done, all) = book.bulkBytes;
          return Column(mainAxisSize: MainAxisSize.min, children: [
            row,
            SizedBox(
              width: 260,
              child: LinearProgressIndicator(
                value: book.bulkFraction,
                minHeight: 4,
                backgroundColor: AppColors.sectionDivider,
                color: AppColors.sectionTitle,
              ),
            ),
            const SizedBox(height: 4),
            Text(
                'Глава ${book.bulkDone! + 1} от ${book.bulkTotal} · '
                '${audioSizeLabel(done)} от ${audioSizeLabel(all)}',
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5)),
          ]);
        }
        return row;
      },
    );
  }
}

/// „Свали всички" — на първия ред на съдържанието, до етикета със
/// слушалките (искане на автора, 12.10.2026). Показва се само ако има
/// несвалено.
class AudioDownloadAllButton extends StatelessWidget {
  final AudioBook book;

  /// Като [AudioChip.ink].
  final Color? ink;
  const AudioDownloadAllButton(this.book, {super.key, this.ink});

  Future<void> _ask(BuildContext context) => askAudioDownloadAll(context, book);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: book.revision,
      builder: (context, _, _) {
        final fg = ink ?? AppColors.textSecondary;
        final muted =
            TextStyle(color: fg, fontSize: 11.5, fontWeight: FontWeight.w600, height: 1.1);
        final total = book.bulkTotal;
        final Widget inner;
        if (total != null) {
          inner = Text('всички ${(book.bulkFraction * 100).floor()}%', style: muted);
        } else if (book.missingParts().isEmpty) {
          return const SizedBox.shrink();
        } else {
          inner = Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.download, size: 14, color: fg),
            const SizedBox(width: 3),
            Text('всички', style: muted),
          ]);
        }
        return Padding(
          padding: const EdgeInsets.only(left: 8),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: total != null ? null : () => _ask(context),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                border: Border.all(color: fg.withValues(alpha: 0.5)),
                borderRadius: BorderRadius.circular(10),
              ),
              child: inner,
            ),
          ),
        );
      },
    );
  }
}

/// ⋮ до „↓ всички" — сваляне на останалото, избор за изтриване и
/// изтриване на целия звук (искане на автора, 12.10.2026). Стои и на първия
/// ред на съдържанието, и под кориците. Видно е само ако поне една глава е
/// свалена — иначе работата му я върши „↓ всички".
///
/// Менюто е във вида на менюто зад трите точки в четеца
/// ([showReaderMoreMenu]): същият тъмен фон, ъгли, иконки 24 и текст 16.
class AudioMoreButton extends StatelessWidget {
  final AudioBook book;

  /// Като [AudioChip.ink].
  final Color? ink;

  /// Влиза в режима за избор в съдържанието. `null` — точката я няма (под
  /// кориците съдържание няма).
  final VoidCallback? onSelect;

  /// Спира плейъра, ако свири глава, която ще се изтрие.
  final Future<void> Function(Set<String>)? beforeRemove;

  const AudioMoreButton(this.book,
      {super.key, this.ink, this.onSelect, this.beforeRemove});

  Future<void> _open(BuildContext context) async {
    final box = context.findRenderObject() as RenderBox;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final at = box.localToGlobal(Offset(0, box.size.height), ancestor: overlay);
    final missing = book.missingParts(), got = book.downloadedParts();
    Widget row(IconData icon, String label) => Row(children: [
          Icon(icon, size: 24, color: AppColors.textSecondary),
          const SizedBox(width: 12),
          Text(label, style: const TextStyle(color: AppColors.textPrimary, fontSize: 16)),
        ]);
    const pad = EdgeInsets.symmetric(horizontal: 16);
    final v = await showMenu<String>(
      context: context,
      color: AppColors.backgroundCard,
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      position: RelativeRect.fromRect(at & const Size(1, 1), Offset.zero & overlay.size),
      items: [
        if (missing.isNotEmpty)
          PopupMenuItem(
              value: 'download',
              padding: pad,
              child: row(Icons.download,
                  'Свали останалите (${audioSizeLabel(book.bytesOf(missing))})')),
        if (onSelect != null)
          PopupMenuItem(
              value: 'select',
              padding: pad,
              child: row(Icons.checklist, 'Избери за изтриване')),
        PopupMenuItem(
            value: 'delete',
            padding: pad,
            child: row(Icons.headset_off,
                'Изтрий целия звук (${audioSizeLabel(book.bytesOf(got))})')),
      ],
    );
    if (!context.mounted) return;
    switch (v) {
      case 'download':
        await askAudioDownloadAll(context, book);
      case 'select':
        onSelect?.call();
      case 'delete':
        await askAudioDeleteMany(context, book, book.downloadedParts(),
            beforeRemove: beforeRemove);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: book.revision,
      builder: (context, _, _) {
        // Докато тече „всички" — нищо: менюто би предложило да се трие
        // онова, което в същия миг се сваля.
        if (book.bulkTotal != null || book.downloadedParts().isEmpty) {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: const EdgeInsets.only(left: 2),
          child: Tooltip(
            message: 'Звукът на книгата',
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => _open(context),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(Icons.more_vert, size: 18, color: ink ?? AppColors.textSecondary),
              ),
            ),
          ),
        );
      },
    );
  }
}

extension AudioDownloadAllExt on Widget {
  /// Слага „Свали всички" и ⋮ вдясно от етикета (само ако [book] не е `null`).
  Widget withDownloadAll(AudioBook? book,
          {Color? ink,
          VoidCallback? onSelect,
          Future<void> Function(Set<String>)? beforeRemove}) =>
      book == null
          ? this
          : Row(mainAxisSize: MainAxisSize.min, children: [
              this,
              AudioDownloadAllButton(book, ink: ink),
              AudioMoreButton(book,
                  ink: ink, onSelect: onSelect, beforeRemove: beforeRemove),
            ]);
}

String _clock(double s) {
  final t = s.isFinite ? s.round() : 0;
  return '${t ~/ 60}:${(t % 60).toString().padLeft(2, '0')}';
}

/// Лентата на плейъра отдолу.
class AudioMiniPlayer extends StatelessWidget {
  final AudioPlayback playback;
  final VoidCallback onClose;
  const AudioMiniPlayer({super.key, required this.playback, required this.onClose});

  @override
  Widget build(BuildContext context) {
    const fg = Colors.white;
    final total = playback.chapter.duration;
    return Material(
      color: AppColors.toolbar,
      child: SafeArea(
        top: false,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ValueListenableBuilder<double>(
            valueListenable: playback.position,
            builder: (_, t, _) => LinearProgressIndicator(
              value: total > 0 ? (t / total).clamp(0.0, 1.0) : 0,
              minHeight: 4,
              backgroundColor: AppColors.sectionDivider,
              color: AppColors.sectionTitle,
            ),
          ),
          Padding(
            // ⚠ По-едро (бележка на автора, 11.10.2026: „доста дребнички") —
            // копчетата се натискат с палец, докато човек слуша, без да гледа.
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(children: [
              IconButton(
                tooltip: 'Назад 5 секунди',
                onPressed: () => playback.skip(-5),
                iconSize: 30,
                icon: const Icon(Icons.replay_5, color: fg),
              ),
              ValueListenableBuilder<bool>(
                valueListenable: playback.playing,
                builder: (_, on, _) => IconButton(
                  tooltip: on ? 'Пауза' : 'Пусни',
                  iconSize: 48,
                  onPressed: playback.toggle,
                  icon: Icon(on ? Icons.pause_circle_filled : Icons.play_circle_filled, color: fg),
                ),
              ),
              IconButton(
                tooltip: 'Напред 5 секунди',
                onPressed: () => playback.skip(5),
                iconSize: 30,
                icon: const Icon(Icons.forward_5, color: fg),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ValueListenableBuilder<double>(
                  valueListenable: playback.position,
                  builder: (_, t, _) => Text('${_clock(t)} / ${_clock(total)}',
                      style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 16,
                          fontFeatures: [FontFeature.tabularFigures()])),
                ),
              ),
              // Продължи със следващата беседа (включено по подразбиране).
              ValueListenableBuilder<bool>(
                valueListenable: AudioAutoNext.notifier,
                builder: (_, on, _) => IconButton(
                  tooltip: on
                      ? 'След края — следващата беседа (вкл.)'
                      : 'След края — спри (следващата беседа е изкл.)',
                  onPressed: AudioAutoNext.toggle,
                  iconSize: 28,
                  icon: Icon(Icons.playlist_play,
                      color: on ? AppColors.sectionTitle : Colors.white38),
                ),
              ),
              IconButton(
                tooltip: 'Затвори плейъра',
                onPressed: onClose,
                iconSize: 28,
                icon: const Icon(Icons.close, color: Colors.white70),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
