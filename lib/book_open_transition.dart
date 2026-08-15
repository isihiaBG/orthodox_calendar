// book_open_transition.dart
//
// Отварянето на том от библиотеката — ЕДНО движение, а не премигване.
//
// Тапнатата корица първо хлътва, сякаш е натисната, после политва към
// човека и се стапя; тъмнината поглъща екрана; от нея излиза светлата
// заглавна страница, идваща отдалеч и прояснявайки се. Двете половини са
// нарочно отделени:
//
//   • [CoverLaunch] — излитането. Рисува се НАД всичко през Overlay-а, за
//     да може корицата да мине и върху лентата, и върху долния панел.
//   • [bookOpenRoute] — посрещането. Страницата идва с мъничко по-едър
//     мащаб и се уталожва до своя, изпод черна пелена, която избледнява.
//
// Мярката за успех е една: човек не бива да усети смяна на екрана, а
// продължение на собствения си жест. Затова и двете части са бързи —
// заедно под секунда — и никъде няма линейно движение.

import 'package:flutter/material.dart';

/// Колко трае излитането на корицата.
const Duration kCoverLaunchDuration = Duration(milliseconds: 440);

/// Колко трае проявяването на страницата изпод пелената.
///
/// Близо два пъти по-дълго от излитането нарочно: излитането е жест на
/// човека и трябва да отговаря пъргаво, а проявяването е пристигане — то се
/// поема бавно. Тъкмо в тази разлика е кинематографското усещане; изравнят
/// ли се двете, преходът става механичен.
const Duration kPageArriveDuration = Duration(milliseconds: 1000);

/// Излитащата корица — слой над целия екран.
///
/// Не е екран и не е част от библиотеката: подава се на Overlay-а, живее
/// колкото трае движението и се маха. Всичко в него е изведено от една
/// стойност `t` (0…1), за да не се разминат съставките му.
class CoverLaunch extends StatelessWidget {
  /// Откъде тръгва — мястото на корицата на екрана.
  final Rect from;

  final ImageProvider cover;

  /// Ходът на излитането, 0…1.
  final Animation<double> animation;

  /// Ходът на РАЗБУЛВАНЕТО, 0…1 — пелената избледнява и открива четеца.
  ///
  /// Отделна от [animation] нарочно: между двете стои отварянето на самия
  /// четец. Пелената почернява, четецът се построява НЕВИДИМ под нея и чак
  /// след това тя се вдига. Така смяната на екрана не се вижда никъде —
  /// има само едно потъмняване и едно просветляване.
  final Animation<double> reveal;

  const CoverLaunch({
    super.key,
    required this.from,
    required this.cover,
    required this.animation,
    required this.reveal,
  });

  /// Докъде трае хлътването. Кратко — то е потвърждение за докосването, не
  /// самостоятелно движение.
  static const double _sinkUntil = 0.18;

  /// Колко хлътва.
  static const double _sinkBy = 0.06;

  /// Докъде порасва, преди да се стопи.
  static const double _riseTo = 0.85;

  /// Кога започва стапянето. По-късно от излитането нарочно: корица, която
  /// избледнява от самото начало, изглежда като изчезваща, а не като
  /// приближаваща се.
  static const double _fadeFrom = 0.42;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: Listenable.merge([animation, reveal]),
        builder: (context, _) {
          final t = animation.value;

          // Хлътване, после излитане. Излитането е с ускорение (easeIn):
          // тръгва кротко изпод пръста и набира ход — обратното изглежда
          // като изстрелване.
          final sink =
              Curves.easeOut.transform((t / _sinkUntil).clamp(0.0, 1.0));
          final rise = Curves.easeInCubic
              .transform(((t - _sinkUntil) / (1 - _sinkUntil)).clamp(0.0, 1.0));
          final scale = (1 - _sinkBy * sink) * (1 + _riseTo * rise);

          final fade = Curves.easeIn
              .transform(((t - _fadeFrom) / (1 - _fadeFrom)).clamp(0.0, 1.0));

          // Пелената тръгва малко след хлътването и застила екрана, докато
          // корицата се стапя — така преходът свършва в чисто тъмно, от
          // което после изгрява страницата. После се вдига с `reveal`.
          final closing =
              Curves.easeIn.transform(((t - 0.12) / 0.88).clamp(0.0, 1.0));
          // ⚠ НЕ easeOut. Той сваля пелената най-бързо в самото начало и
          // страницата „изскача" от тъмното, колкото и дълъг да е ходът.
          // Кривата трябва да е полегата в ДВАТА края: тъмнината се отпуска
          // бавно, светлината идва бавно.
          final opening = Curves.easeInOutCubic.transform(reveal.value);
          final veil = closing * (1 - opening);

          return Stack(
            children: [
              Positioned.fill(
                child: ColoredBox(
                  color: Colors.black.withValues(alpha: veil),
                ),
              ),
              Positioned.fromRect(
                rect: from,
                child: Opacity(
                  opacity: (1 - fade).clamp(0.0, 1.0),
                  child: Transform.scale(
                    scale: scale,
                    child: Image(image: cover, fit: BoxFit.fill),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Пътят към четивото: страницата идва отдалеч и се уталожва.
///
/// ⚠ ТУК НЯМА ПОТЪМНЯВАНЕ. Тъмнината е една за целия преход и се държи от
/// пелената на [CoverLaunch], която стои над всички маршрути: тя почернява,
/// докато корицата отлита, четецът се построява невидим под нея и чак после
/// тя се вдига. Собствена пелена и тук би значела две почернявания едно
/// подир друго — точно накъсването, което гоним да няма.
///
/// Остава само мащабът: страницата тръгва мъничко по-едра и се свива до
/// своята, огледално на излитането на корицата.
Route<T> bookOpenRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    transitionDuration: kPageArriveDuration,
    reverseTransitionDuration: const Duration(milliseconds: 260),
    pageBuilder: (_, __, ___) => page,
    transitionsBuilder: (context, animation, secondary, child) {
      final t = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
      return ScaleTransition(
        scale: Tween<double>(begin: 1.06, end: 1.0).animate(t),
        child: child,
      );
    },
  );
}
