// edit_icon.dart
//
// Иконката „редактирай" — моливче върху лист, нарисувана от потребителя
// (assets/icons/edit-icon.svg, 29.09.2026). Една за цялото приложение:
// списъците с отметки и цитати и плаващото копче в богослужебните книги.
//
// ⚠ SVG-то е ЧЕРНО и се оцветява тук (`ColorFilter` със `srcIn`). Цветът се
// взима от `IconTheme`, тъй че в лентата (AppBar) иконката е бяла като
// съседните, без да се подава изрично — точно както би се държал `Icon`.

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class EditIcon extends StatelessWidget {
  final Color? color;
  final double? size;
  const EditIcon({super.key, this.color, this.size});

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    // Рисунката запълва целия си квадрат, а глифовете на Material оставят
    // поле около себе си. Първо беше смалена с една пета и излизаше дребна
    // (бележка на потребителя, 30.09.2026) — сега е в пълния размер на
    // иконка, а в лентата и мъничко отгоре.
    final s = (size ?? theme.size ?? 24) * 1.0;
    return SizedBox(
      width: size ?? theme.size ?? 24,
      height: size ?? theme.size ?? 24,
      child: Center(
        child: SvgPicture.asset(
          'assets/icons/edit-icon.svg',
          width: s,
          height: s,
          colorFilter: ColorFilter.mode(
              color ?? theme.color ?? Colors.white, BlendMode.srcIn),
        ),
      ),
    );
  }
}
