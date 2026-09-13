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
import 'reader_screen.dart';
import 'saint_expandable_tile.dart';

class LivesPlusSection extends StatelessWidget {
  final List<Slovo> slova;

  const LivesPlusSection({super.key, required this.slova});

  Future<void> _open(BuildContext context, Slovo s) async {
    final texts = await LivesPlusDb.load(s.slug);
    if (texts == null || !context.mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
      // ⚠ Режимът е `life`, не `sluzhba`: словата са свързан разказ и
      // получават буквица, както житията.
      builder: (_) => ReaderScreen.life(
        texts: texts,
        lookup: lookupBySlug,
        lifeTitle: s.title,
        typeLabel: 'Слово',
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final s in slova)
          InkWell(
            onTap: () => _open(context, s),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
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
        const Padding(
          padding: EdgeInsets.only(top: 6),
          child: Text(
            'По свт. Димитрий Ростовски',
            style: TextStyle(
                color: AppColors.textSecondary, fontSize: 13, height: 1.4),
          ),
        ),
      ],
    );
  }
}
