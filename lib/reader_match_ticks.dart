// reader_match_ticks.dart
//
// Чертичките по скролбара — по една за всяко намерено съвпадение при
// търсене. ОБЩО за двата четеца.
//
// Показват КЪДЕ из цялото четиво са попаденията, без да се превърта:
// текущото е в по-наситен цвят, останалите — в по-блед. Заедно с палеца на
// скролбара дават усещане за разпределението им.

import 'package:flutter/material.dart';

import 'reader_theme.dart';

/// Чертички за позициите на съвпаденията върху лентата (виж
/// _buildMatchTicksOverlay). ratios са стойности 0..1 — дял от цялата
/// (оценена) дължина на текста.
class MatchTicksPainter extends CustomPainter {
  final List<double> ratios;
  final int currentIndex;
  final Color hitColor;
  final Color currentColor;

  const MatchTicksPainter({
    required this.ratios,
    required this.currentIndex,
    required this.hitColor,
    required this.currentColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final hitPaint = Paint()
      ..color = hitColor
      ..strokeWidth = 2;
    // Първо всички жълти чертички...
    for (int i = 0; i < ratios.length; i++) {
      final y = (ratios[i].clamp(0.0, 1.0) * size.height).clamp(
        0.0,
        size.height,
      );
      canvas.drawLine(Offset(0, y), Offset(size.width, y), hitPaint);
    }
    // ...после ОТДЕЛНО оранжевата, рисувана НАПОСЛЕДЪК — гарантирано най-
    // отгоре в z-реда, дори когато няколко жълти са плътно една до друга и
    // иначе биха я скрили.
    if (currentIndex >= 0 && currentIndex < ratios.length) {
      final currentPaint = Paint()
        ..color = currentColor
        ..strokeWidth = 3;
      final y = (ratios[currentIndex].clamp(0.0, 1.0) * size.height).clamp(
        0.0,
        size.height,
      );
      canvas.drawLine(Offset(0, y), Offset(size.width, y), currentPaint);
    }
  }

  @override
  bool shouldRepaint(covariant MatchTicksPainter old) =>
      old.ratios != ratios || old.currentIndex != currentIndex;
}

/// Лентата с чертичките — по една за всяко намерено съвпадение, върху
/// скролбара.
///
/// [ratios] са позициите им в дела от цялата височина (0..1). Кой ги смята
/// е РАЗЛИЧНО в двата четеца: при житието — по оценени височини на
/// регионите, при книгата — по позицията в един непрекъснат текст. Затова
/// сметката остава в екраните, а тук е само рисуването.
///
/// Геометрията съвпада с тази на скролбара (crossAxisMargin: 2,
/// mainAxisMargin: 4, дебелина kReaderScrollThumb), за да легнат
/// чертичките точно върху палеца, а не встрани от него.
Widget matchTicksOverlay({
  required List<double> ratios,
  required int currentIndex,
  required ReaderPalette palette,
  required double top,
}) {
  if (ratios.isEmpty) return const SizedBox.shrink();
  return Positioned(
    right: 2,
    top: top,
    bottom: 4,
    width: kReaderScrollThumb,
    child: IgnorePointer(
      child: CustomPaint(
        painter: MatchTicksPainter(
          ratios: ratios,
          currentIndex: currentIndex,
          hitColor: palette.tickHit,
          currentColor: palette.tickCurrent,
        ),
      ),
    ),
  );
}
