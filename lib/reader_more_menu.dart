// reader_more_menu.dart
//
// Менюто зад трите точки — ОБЩО за четеца на жития и за четеца на книги.
//
// Изнесено, за да е буквално едно и също, а не преписано: менюто има
// анимация (плъзва изпод лентата и избледнява), закачено е за горния десен
// ъгъл под самата лента и има стрелка за затваряне. Преписано на второ
// място, всяка бъдеща поправка би трябвало да се прави два пъти.
//
// Кои точки съдържа решава извикващият — оттам идва и разликата между
// двата четеца (в книгите още няма изнасяне към PDF).

import 'package:flutter/material.dart';

import 'app_theme.dart';

/// Една точка от менюто.
class ReaderMenuItem {
  final IconData icon;
  final String label;

  /// Какво връща менюто, ако човек избере тази точка.
  final String value;

  const ReaderMenuItem({
    required this.icon,
    required this.label,
    required this.value,
  });
}

/// Точките, ОБЩИ за двата четеца.
///
/// ⚠ Стоят тук, а не се описват на място във всеки четец. Дотогава бяха
/// два пъти преписани и вече се разминаваха: в книгите менюто носеше само
/// отметките, а споделянето като PDF го нямаше — не по решение, а защото
/// някой е добавил точката само на едното място. Нов елемент се слага
/// веднъж и се появява в двата.
const ReaderMenuItem kBookmarksMenuItem = ReaderMenuItem(
  icon: Icons.bookmarks_outlined,
  label: 'Списък с отметки',
  value: 'bookmarks',
);

const ReaderMenuItem kSharePdfMenuItem = ReaderMenuItem(
  icon: Icons.picture_as_pdf_outlined,
  label: 'Сподели като PDF',
  value: 'share_pdf',
);

/// Пълното меню на четеца. Ползва се и от двата.
const List<ReaderMenuItem> kReaderMenuItems = [
  kBookmarksMenuItem,
  kSharePdfMenuItem,
];

/// Показва менюто и връща избраното (или null при затваряне).
Future<String?> showReaderMoreMenu(
  BuildContext context, {
  required List<ReaderMenuItem> items,
}) {
  final topInset = MediaQuery.of(context).padding.top;
  return showGeneralDialog<String>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Затвори менюто',
    barrierColor: Colors.black26,
    transitionDuration: const Duration(milliseconds: 240),
    pageBuilder: (_, __, ___) => const SizedBox.shrink(),
    transitionBuilder: (ctx, anim, _, _) {
      final curved = CurvedAnimation(
        parent: anim,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return Stack(
        children: [
          Positioned(
            top: topInset + 44,
            right: 6,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, -0.35),
                end: Offset.zero,
              ).animate(curved),
              child: FadeTransition(
                opacity: curved,
                child: Material(
                  color: AppColors.backgroundCard,
                  elevation: 8,
                  borderRadius: BorderRadius.circular(14),
                  clipBehavior: Clip.antiAlias,
                  child: IntrinsicWidth(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Лента за затваряне най-отгоре — менюто се прибира
                        // и с тап встрани, но стрелката прави изхода
                        // очевиден.
                        Align(
                          alignment: Alignment.centerRight,
                          child: InkWell(
                            onTap: () => Navigator.of(ctx).pop(),
                            customBorder: const CircleBorder(),
                            child: const Padding(
                              padding: EdgeInsets.fromLTRB(14, 10, 14, 6),
                              child: Icon(
                                Icons.arrow_forward,
                                size: 22,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ),
                        ),
                        const Divider(
                          height: 1,
                          color: AppColors.sectionDivider,
                        ),
                        for (final item in items)
                          InkWell(
                            onTap: () => Navigator.of(ctx).pop(item.value),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 14),
                              child: Row(
                                children: [
                                  // Пропорция икона/текст като в главното
                                  // меню (app_drawer.dart) — това също е
                                  // меню, не дребен списъчен ред.
                                  Icon(item.icon,
                                      size: 22,
                                      color: AppColors.textSecondary),
                                  const SizedBox(width: 12),
                                  Text(
                                    item.label,
                                    style: const TextStyle(
                                      color: AppColors.textPrimary,
                                      fontSize: 16,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    },
  );
}
