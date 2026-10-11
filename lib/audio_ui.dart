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

/// Етикетът в съдържанието.
class AudioChip extends StatelessWidget {
  final AudioBook book;
  final String part;
  final VoidCallback onTap;

  /// Задържане върху свален етикет — изтриване (с питане).
  final VoidCallback? onLongPress;
  const AudioChip(
      {super.key, required this.book, required this.part, required this.onTap, this.onLongPress});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: book.revision,
      builder: (context, _, _) {
        if (!book.has(part)) return const SizedBox.shrink();
        final done = book.isDownloaded(part);
        final busy = book.isDownloading(part);
        const muted = TextStyle(
            color: AppColors.textSecondary, fontSize: 11.5, fontWeight: FontWeight.w600, height: 1.1);
        final Widget inner;
        if (busy) {
          inner = Text('${((book.progress[part] ?? 0) * 100).round()}%', style: muted);
        } else if (done) {
          inner = const Icon(Icons.headphones, size: 15, color: AppColors.sectionTitle);
        } else {
          inner = Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.headphones_outlined, size: 14, color: AppColors.textSecondary),
            const SizedBox(width: 4),
            const Icon(Icons.file_download_outlined, size: 14, color: AppColors.textSecondary),
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
                color: AppColors.textPrimary.withValues(alpha: 0.07),
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
              minHeight: 2,
              backgroundColor: AppColors.sectionDivider,
              color: AppColors.sectionTitle,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(children: [
              IconButton(
                tooltip: 'Назад 5 секунди',
                onPressed: () => playback.skip(-5),
                icon: const Icon(Icons.replay_5, color: fg),
              ),
              ValueListenableBuilder<bool>(
                valueListenable: playback.playing,
                builder: (_, on, _) => IconButton(
                  tooltip: on ? 'Пауза' : 'Пусни',
                  iconSize: 34,
                  onPressed: playback.toggle,
                  icon: Icon(on ? Icons.pause_circle_filled : Icons.play_circle_filled, color: fg),
                ),
              ),
              IconButton(
                tooltip: 'Напред 5 секунди',
                onPressed: () => playback.skip(5),
                icon: const Icon(Icons.forward_5, color: fg),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ValueListenableBuilder<double>(
                  valueListenable: playback.position,
                  builder: (_, t, _) => Text('${_clock(t)} / ${_clock(total)}',
                      style: const TextStyle(
                          color: Colors.white70, fontFeatures: [FontFeature.tabularFigures()])),
                ),
              ),
              IconButton(
                tooltip: 'Затвори плейъра',
                onPressed: onClose,
                icon: const Icon(Icons.close, color: Colors.white70),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
