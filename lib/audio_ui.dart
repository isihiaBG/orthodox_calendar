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

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'audiobook.dart';
import 'phone_voice.dart';
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

/// Няма български глас на устройството — едно докосване до екрана на
/// Google за сваляне, без обяснения къде е в настройките (автора, 28.10.2026).
Future<void> askPhoneVoiceInstall(BuildContext context) async {
  final palette = ReaderTheme.palette;
  final messenger = ScaffoldMessenger.of(context);
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: palette.sheet,
      title: Text('Четене на глас', style: TextStyle(color: palette.ink, fontSize: 19)),
      content: Text(
        'На устройството няма български глас.\n'
        'Google го дава безплатно — сваля се веднъж.',
        style: TextStyle(color: palette.ink, fontSize: 16, height: 1.35),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Назад')),
        FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Свали гласа')),
      ],
    ),
  );
  if (ok != true) return;
  if (!await PhoneVoice.install()) {
    messenger.showSnackBar(
        const SnackBar(content: Text('Екранът за сваляне на гласа не се отвори.')));
  }
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

/// Обновяване на една глава с по-нова версия — с размера.
Future<void> askAudioUpdate(BuildContext context, AudioBook book, String part,
    {required String title}) async {
  final palette = ReaderTheme.palette;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: palette.sheet,
      title: Text('Нова версия на звука', style: TextStyle(color: palette.ink, fontSize: 19)),
      content: Text(
        '„$title“\n\nИма поправен запис. Да го сваля ли (${audioSizeLabel(book.sizeOf(part))})? '
        'Старият се заменя, щом новият е свален.',
        style: TextStyle(color: palette.ink, fontSize: 16, height: 1.35),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Назад')),
        FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Обнови')),
      ],
    ),
  );
  if (ok != true) return;
  final messenger = ScaffoldMessenger.maybeOf(context);
  final err = await book.download(part);
  messenger?.showSnackBar(SnackBar(content: Text(err ?? 'Звукът е обновен.')));
}

/// „Обнови всички" за една книга — първо регистъра, после остарелите глави.
Future<void> askAudioUpdateAll(BuildContext context, AudioBook book) async {
  final todo = book.outdatedParts();
  if (todo.isEmpty) return;
  final palette = ReaderTheme.palette;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: palette.sheet,
      title: Text('Нови версии на звука', style: TextStyle(color: palette.ink, fontSize: 19)),
      content: Text(
        'Има поправени записи на ${todo.length} '
        '${todo.length == 1 ? 'глава' : 'глави'} — общо ${audioSizeLabel(book.bytesOf(todo))}. '
        'Да ги сваля ли? Старите се заменят, щом новите са свалени.',
        style: TextStyle(color: palette.ink, fontSize: 16, height: 1.35),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Назад')),
        FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Обнови')),
      ],
    ),
  );
  if (ok != true) return;
  final messenger = ScaffoldMessenger.maybeOf(context);
  final err = await book.updateAll();
  messenger?.showSnackBar(SnackBar(content: Text(err ?? 'Звукът е обновен.')));
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

/// Слушалките на СВАЛЕН запис — с малко „HQ" горе вдясно, ако е свален във
/// високо качество (18.10.2026, автора). Икономичното е нормата и знак няма:
/// маркира се изключението — по-тежкият запис.
class AudioHeadphones extends StatelessWidget {
  final bool high;
  final double size;
  final Color color;
  const AudioHeadphones(
      {super.key, required this.high, this.size = 15, this.color = AppColors.sectionTitle});

  @override
  Widget build(BuildContext context) {
    final icon = Icon(Icons.headphones, size: size, color: color);
    if (!high) return icon;
    // Като горен индекс: подравнено по ГОРНИЯ ръб на иконата, тъй че
    // стои по-високо от средата ѝ — суфикс на слушалките.
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        icon,
        Container(
          margin: const EdgeInsets.only(left: 1),
          padding: const EdgeInsets.symmetric(horizontal: 2.5, vertical: 0.5),
          decoration: BoxDecoration(
            color: AppColors.textMuted.withValues(alpha: 0.22),
            borderRadius: BorderRadius.circular(2.5),
          ),
          child: Text('HQ',
              style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: size * 0.42,
                  fontWeight: FontWeight.w700,
                  height: 1.1,
                  letterSpacing: 0.2)),
        ),
      ],
    );
  }
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

  /// Заглавието на главата — за прозореца при обновяване.
  final String title;
  const AudioChip(
      {super.key,
      required this.book,
      required this.part,
      required this.onTap,
      this.onLongPress,
      this.ink,
      this.title = 'Главата'});

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
        } else if (done && book.isOutdated(part)) {
          // Нова версия: слушалките пускат старата, ⟳ сваля новата.
          inner = Row(mainAxisSize: MainAxisSize.min, children: [
            AudioHeadphones(high: book.isHigh(part)),
            const SizedBox(width: 4),
            InkWell(
              onTap: () => askAudioUpdate(context, book, part, title: title),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.update, size: 15, color: AppColors.sectionTitle),
                const SizedBox(width: 2),
                Text(audioSizeLabel(book.sizeOf(part)), style: muted),
              ]),
            ),
          ]);
        } else if (done) {
          inner = AudioHeadphones(high: book.isHigh(part));
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

/// Печатът „екстра" — записът (ElevenLabs/Azure) на четивото, по-хубав от
/// гласа на телефона (замисъл на автора, 28.10.2026). Назъбено кръгче в
/// старо злато; вътре ⤓ (има запис, не е свален) или 🔈 (свален).
///
/// ⚠ ЦВЕТОВЕТЕ СА МЕРЕНИ, не на око (правило на автора: тъмното не е чисто
/// черно, светлото не е чисто бяло):
///   тъмна тема — печат #CDA757 върху копче #4D4943: 3.9x; знакът #34290F
///                върху печата 6.3:1;
///   светла     — печат #8F6420 (по-плътно злато: светлото се сливаше с
///                бежовото копче #C8B995, 2.0x) — 2.7x; знакът #FBEFD3 4.6:1.
/// Обиколката е в цвета на СТРАНИЦАТА — изрязва печата от копчето, без
/// да се вижда върху страницата.
class ExtraSeal extends StatelessWidget {
  /// true — свален (високоговорител), false — за сваляне (⤓).
  final bool downloaded;

  /// 0..1 докато се сваля.
  final double? progress;
  final bool dark;
  final Color cut;
  final double size;
  const ExtraSeal(
      {super.key,
      required this.downloaded,
      required this.dark,
      required this.cut,
      this.progress,
      this.size = 20});

  @override
  Widget build(BuildContext context) {
    final fill = dark ? const Color(0xFFCDA757) : const Color(0xFF8F6420);
    final mark = dark ? const Color(0xFF34290F) : const Color(0xFFFBEFD3);
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _SealPainter(fill: fill, cut: cut, progress: progress),
        child: Center(
          child: Icon(
            downloaded ? Icons.volume_up_rounded : Icons.download_rounded,
            size: size * 0.6,
            color: progress != null ? mark.withValues(alpha: 0.55) : mark,
          ),
        ),
      ),
    );
  }
}

class _SealPainter extends CustomPainter {
  final Color fill, cut;
  final double? progress;
  _SealPainter({required this.fill, required this.cut, this.progress});

  static const _teeth = 12;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    // Мек печат: зъбците са плитки (вътрешният радиус 0.86) и заоблени —
    // остри изглеждаха като звезда, не като печат.
    final path = Path();
    const n = _teeth * 2;
    for (var i = 0; i <= n; i++) {
      final a = -math.pi / 2 + i * math.pi / _teeth;
      final rr = i.isEven ? r : r * 0.86;
      final p = c + Offset(math.cos(a), math.sin(a)) * rr;
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    path.close();
    canvas.drawPath(
        path,
        Paint()
          ..color = cut
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4
          ..strokeJoin = StrokeJoin.round);
    canvas.drawPath(
        path,
        Paint()
          ..color = fill
          ..style = PaintingStyle.fill);
    canvas.drawPath(
        path,
        Paint()
          ..color = fill
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8
          ..strokeJoin = StrokeJoin.round);
    final p = progress;
    if (p != null) {
      // Напредъкът — тънка дъга в цвета на изрязването, по ръба.
      canvas.drawArc(
          Rect.fromCircle(center: c, radius: r * 0.7),
          -math.pi / 2,
          2 * math.pi * p.clamp(0.02, 1.0),
          false,
          Paint()
            ..color = cut
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.6
            ..strokeCap = StrokeCap.round);
    }
  }

  @override
  bool shouldRepaint(_SealPainter old) =>
      old.fill != fill || old.cut != cut || old.progress != progress;
}

/// Плаващото копче долу вдясно — при всяко четиво (гласът на телефона), а
/// при четиво със запис — с печата „екстра" в горния десен ъгъл, който
/// излиза леко извън копчето.
///
/// ⚠⚠ НЕ В ЛЕНТАТА (решено с автора, 11.10.2026). На изправен телефон лентата
/// на четеца е пълна — стрелка и съдържание отляво, шест копчета отдясно —
/// и седмото се блъскаше в съдържанието. Плаващото копче е като това в
/// молитвослова (същият `palette.fab`), а щом звукът тръгне, на мястото му
/// идва мини плейърът.
///
/// Копчето винаги ЧЕТЕ веднага (записа, ако е свален, иначе гласа на
/// телефона). Печатът е отделно докосване — сваля записа.
class AudioFab extends StatelessWidget {
  final AudioBook? book;
  final String? part;
  final VoidCallback onTap;
  final VoidCallback? onSeal;
  const AudioFab({super.key, this.book, this.part, required this.onTap, this.onSeal});

  @override
  Widget build(BuildContext context) {
    final b = book;
    if (b == null) return _build(null);
    return ValueListenableBuilder<int>(
      valueListenable: b.revision,
      builder: (context, _, _) => _build(b),
    );
  }

  Widget _build(AudioBook? b) {
    final p = ReaderTheme.palette;
    final hasRec = b != null && part != null && b.has(part);
    final done = hasRec && b.isDownloaded(part);
    final busy = hasRec && b.isDownloading(part);
    final fab = FloatingActionButton.small(
      heroTag: null,
      tooltip: done ? 'Слушай записа' : 'Слушай',
      backgroundColor: p.fab,
      foregroundColor: p.ink,
      onPressed: onTap,
      child: const Icon(Icons.headphones),
    );
    if (!hasRec) {
      return Padding(padding: const EdgeInsets.only(right: 14, bottom: 8), child: fab);
    }
    // ⚠ Копчето е отместено с 11 px навътре, за да е и печатът ВЪТРЕ в
    // стека — докосване извън стека не стига до него. Копчето стои на
    // същото място (14 − 11 отдясно). Мястото на печата — избрано от автора
    // по рисунки (28.10.2026): 4 px по-вдясно и по-нагоре от първото, за да
    // не застъпва дъгата на слушалките.
    return Padding(
      padding: const EdgeInsets.only(right: 3, bottom: 8),
      child: Stack(clipBehavior: Clip.none, children: [
              Padding(padding: const EdgeInsets.only(top: 11, right: 11), child: fab),
              Positioned(
                right: 3,
                top: 3,
                child: Tooltip(
                  message: done
                      ? 'Записът е свален'
                      : 'Свали записа · ${audioSizeLabel(b.sizeOf(part!))}',
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: done || busy ? null : onSeal,
                    // Зоната за допир е по-голяма от рисунката (32 px).
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: ExtraSeal(
                        downloaded: done,
                        dark: p.dark,
                        cut: p.bg,
                        progress: busy ? (b.progress[part] ?? 0) : null,
                      ),
                    ),
                  ),
                ),
              ),
            ]),
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
    final msg = err ?? await audioSummary();
    if (!mounted) return;
    setState(() => _checking = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
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
        final missing = book.missingParts(), outdated = book.outdatedParts();
        final Widget inner;
        VoidCallback? tap;
        if (total != null) {
          // Напредъкът в MB — като под кориците (автора, 13.10.2026).
          final (done, all) = book.bulkBytes;
          inner = Text('${(book.bulkFraction * 100).floor()}% · '
              '${(done / 1048576).toStringAsFixed(1)} / ${audioSizeLabel(all)}', style: muted);
        } else if (missing.isNotEmpty) {
          inner = Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.download, size: 14, color: fg),
            const SizedBox(width: 3),
            Text('всички · ${audioSizeLabel(book.bytesOf(missing))}', style: muted),
          ]);
          tap = () => _ask(context);
        } else if (outdated.isNotEmpty) {
          inner = Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.update, size: 14, color: AppColors.sectionTitle),
            const SizedBox(width: 3),
            Text('обнови · ${audioSizeLabel(book.bytesOf(outdated))}', style: muted),
          ]);
          tap = () => askAudioUpdateAll(context, book);
        } else {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: const EdgeInsets.only(left: 8),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: tap,
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

/// „Запис · 14 MB" в плейъра отдолу, докато чете гласът на телефона — тих
/// надпис с печата „екстра"; докосване — сваля записа, после плейърът минава
/// към него от същото изречение.
class AudioRecordingChip extends StatelessWidget {
  final AudioBook book;
  final String part;
  final VoidCallback onTap;
  const AudioRecordingChip(
      {super.key, required this.book, required this.part, required this.onTap});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
        valueListenable: book.revision,
        builder: (context, _, _) {
          final busy = book.isDownloading(part);
          final pr = book.progress[part] ?? 0;
          final label = busy
              ? 'запис · ${(pr * 100).round()}%'
              : 'запис · ${audioSizeLabel(book.sizeOf(part))}';
          return Tooltip(
            message: 'Свали записа — по-хубав глас',
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: busy ? null : onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  ExtraSeal(
                    downloaded: false,
                    dark: true,
                    cut: AppColors.toolbar,
                    progress: busy ? pr : null,
                    size: 18,
                  ),
                  const SizedBox(width: 7),
                  Flexible(
                    child: Text(label,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Color(0xFFCDA757),
                            fontSize: 15,
                            fontFeatures: [FontFeature.tabularFigures()])),
                  ),
                ]),
              ),
            ),
          );
        },
      );
}

/// Зъбното колело в плейъра: „следващото четиво след края" и скоростта
/// (само при гласа на телефона — при запис е сива). Тук ще влизат и
/// бъдещите настройки на слушането.
class _PlayerSettings extends StatelessWidget {
  final bool phone;
  const _PlayerSettings({required this.phone});

  @override
  Widget build(BuildContext context) => MenuAnchor(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(AppColors.backgroundCard),
          shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(vertical: 6)),
          elevation: const WidgetStatePropertyAll(4),
        ),
        // Десният ръб на менюто — под десния ръб на колелото (не опрян в
        // ръба на екрана).
        alignmentOffset: const Offset(48 - _PlayerSettingsPanel.width, 0),
        menuChildren: [_PlayerSettingsPanel(phone: phone)],
        builder: (_, menu, _) => IconButton(
          tooltip: 'Настройки на слушането',
          onPressed: () => menu.isOpen ? menu.close() : menu.open(),
          iconSize: 26,
          icon: const Icon(Icons.settings_outlined, color: Colors.white70),
        ),
      );
}

class _PlayerSettingsPanel extends StatefulWidget {
  final bool phone;
  const _PlayerSettingsPanel({required this.phone});
  static const width = 280.0;

  @override
  State<_PlayerSettingsPanel> createState() => _PlayerSettingsPanelState();
}

class _PlayerSettingsPanelState extends State<_PlayerSettingsPanel> {
  // Докато се влачи — само тук; гласът получава скоростта при пускане
  // (иначе би почвал изречението наново на всяка стъпка).
  late double _speed = AudioSpeed.value;

  @override
  Widget build(BuildContext context) {
    const ink = Color(0xDEFFFFFF);
    const dim = Color(0x8AFFFFFF);
    const off = Color(0x4DFFFFFF);
    final on = widget.phone;
    return SizedBox(
      width: _PlayerSettingsPanel.width,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ValueListenableBuilder<bool>(
          valueListenable: AudioAutoNext.notifier,
          builder: (_, next, _) => SwitchListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            title: const Text('Следващото четиво след края',
                style: TextStyle(color: ink, fontSize: 15)),
            value: next,
            activeThumbColor: AppColors.toolbar,
            activeTrackColor: AppColors.sectionTitle,
            inactiveThumbColor: dim,
            inactiveTrackColor: AppColors.drawerDivider,
            trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
            onChanged: (_) => AudioAutoNext.toggle(),
          ),
        ),
        const Divider(height: 10, color: AppColors.drawerDivider),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
          child: Row(children: [
            Text('Скорост', style: TextStyle(color: on ? ink : off, fontSize: 15)),
            const Spacer(),
            // Докосване по стойността — обратно на обичайната.
            GestureDetector(
              onTap: on && _speed != 1.0
                  ? () {
                      setState(() => _speed = 1.0);
                      AudioSpeed.set(1.0);
                    }
                  : null,
              child: Text(AudioSpeed.label(_speed),
                  style: TextStyle(
                      color: on ? ink : off,
                      fontSize: 15,
                      fontFeatures: const [FontFeature.tabularFigures()])),
            ),
          ]),
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: AppColors.sectionTitle,
            inactiveTrackColor: AppColors.drawerDivider,
            thumbColor: AppColors.sectionTitle,
            disabledActiveTrackColor: off,
            disabledInactiveTrackColor: AppColors.drawerDivider,
            disabledThumbColor: const Color(0xFF5A5A5A),
            activeTickMarkColor: Colors.transparent,
            inactiveTickMarkColor: Colors.transparent,
            disabledActiveTickMarkColor: Colors.transparent,
            disabledInactiveTickMarkColor: Colors.transparent,
            overlayColor: AppColors.sectionTitle.withValues(alpha: 0.16),
            trackHeight: 3,
          ),
          child: Slider(
            value: _speed,
            min: AudioSpeed.min,
            max: AudioSpeed.max,
            divisions: 8,
            onChanged: on ? (v) => setState(() => _speed = v) : null,
            onChangeEnd: on ? AudioSpeed.set : null,
          ),
        ),
        if (!on)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text('Само за гласа на телефона — записът е в своето темпо.',
                style: TextStyle(color: dim, fontSize: 12.5, height: 1.3)),
          ),
      ]),
    );
  }
}

/// Лентата на плейъра отдолу.
class AudioMiniPlayer extends StatelessWidget {
  final ReadAloud playback;
  final VoidCallback onClose;

  /// Само при гласа на телефона и четиво със запис — [AudioRecordingChip]
  /// на мястото на часовника.
  final Widget? recording;
  const AudioMiniPlayer(
      {super.key, required this.playback, required this.onClose, this.recording});

  @override
  Widget build(BuildContext context) {
    const fg = Colors.white;
    final total = playback.chapter.duration;
    final phone = playback.isPhoneVoice;
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
                tooltip: phone ? 'Предишното изречение' : 'Назад 5 секунди',
                onPressed: () => playback.skip(-5),
                iconSize: 30,
                icon: Icon(phone ? Icons.skip_previous_rounded : Icons.replay_5, color: fg),
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
                tooltip: phone ? 'Следващото изречение' : 'Напред 5 секунди',
                onPressed: () => playback.skip(5),
                iconSize: 30,
                icon: Icon(phone ? Icons.skip_next_rounded : Icons.forward_5, color: fg),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: recording != null && phone
                    ? Align(alignment: Alignment.centerLeft, child: recording)
                    : ValueListenableBuilder<double>(
                  valueListenable: playback.position,
                  // Гласът на телефона — времето е приблизително (по броя
                  // на знаците), затова с „≈".
                  builder: (_, t, _) => Text('${phone ? '≈ ' : ''}${_clock(t)} / ${_clock(total)}',
                      style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 16,
                          fontFeatures: [FontFeature.tabularFigures()])),
                ),
              ),
              _PlayerSettings(phone: phone),
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
