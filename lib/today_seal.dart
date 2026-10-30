import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Знакът „днес" — златна 12-конечна звезда с контур, вълнообразна тъмна
/// ивица отвън и две разкрачени лентички отдолу (като старинен печат).
/// Височината е 1.3 × [size]; кръглата част е горните [size].
class TodaySeal extends StatelessWidget {
  /// Цветът под звездата — този на лентата, върху която стои.
  final Color fill;
  final double size;
  const TodaySeal({super.key, required this.fill, this.size = 44});

  static const gold = Color(0xFFCDA757);

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size * 1.3,
        child: CustomPaint(
          painter: _SealPainter(fill),
          child: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: size,
              height: size,
              child: Center(
                child: Text('днес',
                    style: TextStyle(
                        fontSize: size * 0.235,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.4,
                        height: 1,
                        color: gold)),
              ),
            ),
          ),
        ),
      );
}

class _SealPainter extends CustomPainter {
  final Color fill;
  _SealPainter(this.fill);

  static const _halo = Color(0x9E2E2E2E); // тъмносиво, леко прозрачно

  void _ribbon(Canvas canvas, Offset top, double angle, double w, double h, Color color) {
    canvas.save();
    canvas.translate(top.dx, top.dy);
    canvas.rotate(angle);
    canvas.drawPath(
        Path()
          ..moveTo(-w / 2, 0)
          ..lineTo(w / 2, 0)
          ..lineTo(w / 2, h)
          ..lineTo(0, h - w * 0.22) // плитка изрезка
          ..lineTo(-w / 2, h)
          ..close(),
        Paint()..color = color);
    canvas.restore();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2;
    final c = Offset(r, r);
    const gold = TodaySeal.gold;

    // Лентите тръгват от средата (скрити под звездата).
    final w = r * 0.60, h = r * 1.55;
    _ribbon(canvas, c + Offset(-r * 0.26, 0), 0.46, w, h, Color.lerp(gold, Colors.black, 0.30)!);
    _ribbon(canvas, c + Offset(r * 0.26, 0), -0.46, w, h, Color.lerp(gold, Colors.black, 0.16)!);

    // Ивицата: 12 гребена точно срещу върховете на зъбците.
    final halo = Path();
    for (var i = 0; i <= 240; i++) {
      final a = -math.pi / 2 + i * 2 * math.pi / 240;
      final rr = r * 0.94 + 3.5 + r * 0.065 * math.cos(12 * (a + math.pi / 2));
      final q = c + Offset(math.cos(a), math.sin(a)) * rr;
      i == 0 ? halo.moveTo(q.dx, q.dy) : halo.lineTo(q.dx, q.dy);
    }
    canvas.drawPath(halo..close(), Paint()..color = _halo);

    final star = Path();
    for (var i = 0; i <= 24; i++) {
      final a = -math.pi / 2 + i * math.pi / 12;
      final q = c + Offset(math.cos(a), math.sin(a)) * (i.isEven ? r : r * 0.88);
      i == 0 ? star.moveTo(q.dx, q.dy) : star.lineTo(q.dx, q.dy);
    }
    star.close();
    canvas.drawPath(star, Paint()..color = fill);
    canvas.drawPath(
        star,
        Paint()
          ..color = gold
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..strokeJoin = StrokeJoin.round);
  }

  @override
  bool shouldRepaint(_SealPainter old) => old.fill != fill;
}
