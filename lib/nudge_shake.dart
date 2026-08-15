// nudge_shake.dart
//
// Подсещащото поклащане на иконка — ОБЩО за списъка с отметки
// (bookmarks.dart, кошчето при избиране) и за четеца на книги
// (book_reader.dart, съдържанието при отваряне на том).
//
// Танцът е един и същ навсякъде нарочно: щом човек го е видял веднъж, вече
// знае, че значи „оттук нататък". Затова тук стои САМО движението, а КОГА
// се пуска решава всеки екран за себе си — поводите са различни (там
// затишие насред избиране, тук първото стъпване в книгата).

import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Колко трае ЕДИН бъмп. Управляващият контролер трябва да е с тази
/// продължителност, за да изглежда поклащането еднакво навсякъде.
const Duration kNudgeBump = Duration(milliseconds: 700);

/// Обвивка, която разтърсва и наедрява детето си според [animation] (0…1).
///
/// При 0 не пипа нищо — тогава детето минава непокътнато, без нито едно
/// излишно преизчисляване.
class NudgeShake extends StatelessWidget {
  final Animation<double> animation;
  final Widget child;

  const NudgeShake({super.key, required this.animation, required this.child});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, ch) {
        final t = animation.value;
        if (t == 0) return ch!;
        // Затихващо махало: люлее се все по-слабо, а наедряването върви и
        // обратно, за да не „подскочи" иконката в края.
        final angle = math.sin(t * math.pi * 6) * 0.28 * (1 - t);
        final scale = 1 + math.sin(t * math.pi) * 0.22;
        return Transform.rotate(
          angle: angle,
          child: Transform.scale(scale: scale, child: ch),
        );
      },
      child: child,
    );
  }
}
