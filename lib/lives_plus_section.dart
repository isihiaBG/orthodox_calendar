// lives_plus_section.dart
//
// Тялото на секцията „СЛОВА ЗА ДЕНЯ" в дневния изглед.
//
// ⚠⚠ СЕКЦИЯТА Е ИЗКЛЮЧИТЕЛНА — показва се САМО в дните, които имат поне едно
// слово. Затова списъкът се чете в `_loadDay` (евтина заявка по индексиран
// адрес, без телата) и се подава готов оттам; ако е празен, `day_screen`
// изобщо не строи секцията. Инак човек би виждал всеки ден надпис, под който
// в 3 от 4 дни няма нищо.

import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'lives_plus.dart';
import 'slovo_open.dart';

class LivesPlusSection extends StatelessWidget {
  /// Словата на свт. Димитрий Ростовски.
  final List<Slovo> slova;

  /// Поясненията за деня от прот. Григорий Дебольски.
  final List<Slovo> dni;

  const LivesPlusSection({super.key, required this.slova, this.dni = const []});

  // ⚠⚠ РАЗДЕЛЕНИЕТО Е ПО АВТОР (решение на потребителя, 25.09.2026). Двата
  // вида четиво са в ЕДНА секция, за да не се множат секциите, но не бива да
  // се представят като едно и също: словата са проповеди, поясненията — не.
  static const _kSlovaHeading = 'Слова от свт. Димитрий Ростовски';
  static const _kDniHeading = 'Пояснения за деня от прот. Григорий Дебольски';

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (slova.isNotEmpty) ..._group(context, _kSlovaHeading, slova, 'Слово'),
        if (slova.isNotEmpty && dni.isNotEmpty) const SizedBox(height: 10),
        if (dni.isNotEmpty)
          ..._group(context, _kDniHeading, dni, 'Пояснение за деня'),
      ],
    );
  }

  List<Widget> _group(
      BuildContext context, String heading, List<Slovo> items, String type) {
    return [
      Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 2),
        child: Text(
          heading,
          style: const TextStyle(
            color: AppColors.sectionTitle,
            fontSize: 14,
            fontWeight: FontWeight.w600,
            height: 1.4,
          ),
        ),
      ),
      for (final s in items)
        InkWell(
          onTap: () => openSlovo(context, s, typeLabel: type),
          child: Padding(
            // ⚠ Отстъпът групира четивата ПОД автора си.
            padding: const EdgeInsets.only(left: 12, top: 6, bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 3, right: 8),
                  child: Icon(Icons.menu_book_outlined,
                      size: 16, color: AppColors.sectionTitle),
                ),
                Expanded(
                  child: Text(
                    s.title,
                    style: const TextStyle(
                      color: AppColors.sectionTitle,
                      fontSize: 15,
                      height: 1.5,
                      decoration: TextDecoration.underline,
                      decorationStyle: TextDecorationStyle.dotted,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
    ];
  }
}
