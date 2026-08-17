// reader_toolbar.dart
//
// Лентата с инструменти при четене — ОБЩА за четеца на жития
// (reader_screen.dart) и за четеца на книги (book_reader.dart).
//
// За потребителя двата екрана трябва да са ЕДИН И СЪЩИ четец: същите
// бутони, същите разстояния, същият вид. Затова редът им се строи на едно
// място, а всеки екран подава само това, което може да прави — каквото не
// подаде, просто не се показва.
//
// „Съдържание" го има само при книгите: житието от календара е едно
// четиво и няма какво да съдържа.

import 'package:flutter/material.dart';

import 'nudge_shake.dart';
import 'reader_font_size.dart';
import 'round_icon_button.dart';

/// Размерът на бутоните — еднакъв за всички в лентата.
const double kReaderBtnSize = 22.0;

/// Знак "първа четвъртина на луната": кръг с контур, вертикално разделен —
/// едната половина плътна (бяла), другата празна.
class HalfMoonPainter extends CustomPainter {
  final Color outline;
  const HalfMoonPainter({required this.outline});

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2 - 1;

    // Дясната половина — плътна
    final fill = Paint()
      ..color = outline
      ..style = PaintingStyle.fill;
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r),
      -1.5707963, // -90° (горе)
      3.1415926,  // 180° по часовниковата → дясната половина
      true,
      fill,
    );

    // Контурът на целия кръг
    final stroke = Paint()
      ..color = outline
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    canvas.drawCircle(c, r, stroke);
  }

  @override
  bool shouldRepaint(covariant HalfMoonPainter old) => old.outline != outline;
}

/// Плосък кръгъл бутон с „хлътнало" състояние (лупата, отметката).
Widget _flatCircle({
  required BuildContext context,
  required IconData icon,
  required String tooltip,
  required VoidCallback onTap,
  bool active = false,
  bool enabled = true,
  Animation<double>? nudge,
}) {
  final fgFull = AppBarTheme.of(context).foregroundColor ?? Colors.white;
  // Посивено, когато действието няма смисъл тук — виж отметката на
  // заглавната страница в book_reader.
  final fg = enabled ? fgFull : fgFull.withValues(alpha: 0.30);
  Widget glyph = Icon(icon, size: 24, color: fg);
  if (nudge != null) glyph = NudgeShake(animation: nudge, child: glyph);
  return Tooltip(
    message: tooltip,
    child: InkWell(
      onTap: enabled ? onTap : null,
      customBorder: const CircleBorder(),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: kReaderBtnSize + 8,
        height: kReaderBtnSize + 8,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: active ? fg.withValues(alpha: 0.28) : Colors.transparent,
        ),
        child: glyph,
      ),
    ),
  );
}

/// Копчето „Съдържание" — САМО за четеца на книги и САМО отляво.
///
/// Стои отделно от [readerToolbarActions], защото мястото му е друго: веднага
/// след стрелката „назад", а не сред копчетата вдясно. Причината е навик —
/// в четците съдържанието се вика отляво, а на широк екран разликата е
/// осезаема. Изглежда точно като останалите кръгли копчета.
Widget readerContentsButton({
  required BuildContext context,
  required VoidCallback onTap,
  Animation<double>? nudge,
}) {
  return _flatCircle(
    context: context,
    icon: Icons.format_list_bulleted,
    tooltip: 'Съдържание',
    onTap: onTap,
    nudge: nudge,
  );
}

/// Бутоните вдясно в лентата на четеца.
///
/// Всеки е незадължителен: подаде ли се null, бутонът просто липсва. Така
/// четецът на книги показва „Съдържание", а четецът на жития — не, без
/// нито един флаг и без разклонения вътре.
List<Widget> readerToolbarActions({
  required BuildContext context,
  required VoidCallback onThemeToggle,
  required VoidCallback onFontSmaller,
  required VoidCallback onFontBigger,
  VoidCallback? onSearch,
  bool searchOpen = false,
  VoidCallback? onBookmark,
  bool bookmarked = false,

  /// Може ли изобщо да се отбелязва тук. false посивява бутона — ползва
  /// се на заглавната страница на том, която не е четиво.
  bool canBookmark = true,
  VoidCallback? onMore,
}) {
  final fg = AppBarTheme.of(context).foregroundColor ?? Colors.white;
  final out = <Widget>[];

  if (onSearch != null) {
    out
      ..add(_flatCircle(
        context: context,
        icon: Icons.search,
        tooltip: 'Търсене в текста',
        onTap: onSearch,
        active: searchOpen,
      ))
      ..add(const SizedBox(width: 16));
  }

  // Тогъл на темата: кръг, разделен вертикално (първа четвъртина).
  out
    ..add(Tooltip(
      message: 'Светла/тъмна тема',
      child: InkWell(
        onTap: onThemeToggle,
        customBorder: const CircleBorder(),
        child: Container(
          width: kReaderBtnSize,
          height: kReaderBtnSize,
          alignment: Alignment.center,
          child: CustomPaint(
            size: const Size(kReaderBtnSize, kReaderBtnSize),
            painter: HalfMoonPainter(outline: fg),
          ),
        ),
      ),
    ))
    ..add(const SizedBox(width: 18))
    ..add(RoundIconButton(
      icon: Icons.remove,
      tooltip: 'По-дребен шрифт',
      enabled: ReaderFontSize.value > ReaderFontSize.min,
      onTap: onFontSmaller,
      size: kReaderBtnSize,
    ))
    ..add(const SizedBox(width: 18))
    ..add(RoundIconButton(
      icon: Icons.add,
      tooltip: 'По-едър шрифт',
      enabled: ReaderFontSize.value < ReaderFontSize.max,
      onTap: onFontBigger,
      size: kReaderBtnSize,
    ));

  if (onBookmark != null) {
    out
      ..add(const SizedBox(width: 18))
      ..add(_flatCircle(
        context: context,
        icon: bookmarked ? Icons.bookmark : Icons.bookmark_border,
        tooltip: canBookmark
            ? (bookmarked ? 'Премахни отметката' : 'Отметни тук')
            : 'Тук няма какво да се отмята',
        onTap: onBookmark,
        active: bookmarked,
        enabled: canBookmark,
      ));
  }

  if (onMore != null) {
    out
      // По-тясно — менюто е „приятел" на отметката.
      ..add(const SizedBox(width: 10))
      ..add(Tooltip(
        message: 'Още',
        child: InkWell(
          onTap: onMore,
          customBorder: const CircleBorder(),
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Icon(Icons.more_vert, size: 24, color: fg),
          ),
        ),
      ));
  }

  out.add(const SizedBox(width: 2)); // разстояние до десния край
  return out;
}
