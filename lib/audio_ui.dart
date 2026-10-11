// audio_ui.dart
//
// Видимите части на четенето на глас (11.10.2026, по указание на автора):
//
//   AudioChip        етикетът в съдържанието — ТИХ, като този с езиците в
//                    молитвослова: несвалено (слушалки + ↓ + размер), сваля
//                    се (процент), свалено (слушалки)
//   AudioToolbarButton  същото в лентата на четеца — съдържанието е затворено,
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

/// Етикетът в съдържанието.
class AudioChip extends StatelessWidget {
  final AudioBook book;
  final String part;
  final VoidCallback onTap;
  const AudioChip({super.key, required this.book, required this.part, required this.onTap});

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
            const SizedBox(width: 3),
            const Icon(Icons.arrow_downward, size: 12, color: AppColors.textSecondary),
            const SizedBox(width: 2),
            Text(audioSizeLabel(book.sizeOf(part)), style: muted),
          ]);
        }
        return InkWell(
          onTap: busy ? null : onTap,
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

/// Копчето в лентата на четеца — видно само при беседа със звук.
class AudioToolbarButton extends StatelessWidget {
  final AudioBook book;
  final String part;
  final VoidCallback onTap;
  const AudioToolbarButton({super.key, required this.book, required this.part, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: book.revision,
      builder: (context, _, _) {
        if (!book.has(part)) return const SizedBox.shrink();
        final color = AppBarTheme.of(context).foregroundColor ?? Colors.white;
        final busy = book.isDownloading(part);
        return IconButton(
          tooltip: book.isDownloaded(part) ? 'Слушай беседата' : 'Свали звука на беседата',
          onPressed: busy ? null : onTap,
          icon: busy
              ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, value: book.progress[part], color: color))
              : Stack(clipBehavior: Clip.none, children: [
                  Icon(book.isDownloaded(part) ? Icons.headphones : Icons.headphones_outlined,
                      color: color),
                  if (!book.isDownloaded(part))
                    Positioned(
                        right: -4,
                        bottom: -3,
                        child: Icon(Icons.arrow_downward, size: 13, color: color)),
                ]),
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
