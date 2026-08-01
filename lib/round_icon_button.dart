// round_icon_button.dart
//
// Кръглото бутонче с контур (− / +) от лентата на четеца. Изнесено тук,
// за да е ЕДНО И СЪЩО навсякъде (четец, "Празници"…) — копие на същия код
// в няколко файла рано или късно се разминава при първата корекция.

import 'package:flutter/material.dart';

class RoundIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool enabled;
  final VoidCallback onTap;
  final double size;

  const RoundIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.enabled,
    required this.onTap,
    this.size = 26,
  });

  @override
  Widget build(BuildContext context) {
    final color = enabled
        ? (AppBarTheme.of(context).foregroundColor ?? Colors.white)
        : Colors.white38;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: enabled ? onTap : null,
        customBorder: const CircleBorder(),
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: color, width: 1.3),
          ),
          child: Icon(icon, size: size * 0.72, color: color),
        ),
      ),
    );
  }
}
