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
/// Отваря настройките, скопирани до категорията на този екран — коя точно,
/// решава всеки четец сам (виж `SettingsDrawer(sections: …)`).
///
/// Първи ред в менюто нарочно (23.08.2026, по молба на потребителя).
///
/// ⚠ НАДПИСЪТ Е „Настройки", не името на категорията. Дотук пишеше „За
/// четивата" и до зъбното колело това създаваше съвсем друга асоциация —
/// звучи като раздел С ЧЕТИВА, а не като настройки за тях. Вътре в екрана
/// „Настройки" същите кратки имена са уместни и стоят като заглавия на
/// категории: там човекът вече знае къде е.
const ReaderMenuItem kReaderSettingsMenuItem = ReaderMenuItem(
  icon: Icons.settings_outlined,
  label: 'Настройки',
  value: 'reader_settings',
);

const ReaderMenuItem kBookmarksMenuItem = ReaderMenuItem(
  icon: Icons.bookmarks_outlined,
  label: 'Списък с отметки',
  value: 'bookmarks',
);

/// ⚠ Стои ДО отметките, не вместо тях. Двата списъка са различни по смисъл:
/// отметката е „докъде съм стигнал" (една на четиво, мести се), цитатът е
/// „това ми хареса" (много на четиво, стои завинаги).
const ReaderMenuItem kQuotesMenuItem = ReaderMenuItem(
  icon: Icons.format_quote_outlined,
  label: 'Любими цитати',
  value: 'quotes',
);

/// „Сподели четивото" — линк към САМОТО четиво, без маркиране.
///
/// ⚠ Иконката е СЪЩАТА, с която се споделя цитат (`Icons.share` в
/// selection_toolbar.dart): за човека това е едно и също действие, само
/// обхватът е друг.
const ReaderMenuItem kShareReadingMenuItem = ReaderMenuItem(
  icon: Icons.share,
  label: 'Сподели четивото',
  value: 'share_reading',
);

/// ⚠ Стойността е ИЗНЕСЕНА в константа, защото се ползва и за посивяване
/// (виж `_disabledItems` в bible_reader.dart). Написана втори път като литерал,
/// щеше да се размине мълчаливо при преименуване.
const String kSharePdfValue = 'share_pdf';

const ReaderMenuItem kSharePdfMenuItem = ReaderMenuItem(
  icon: Icons.picture_as_pdf_outlined,
  label: 'Сподели като PDF',
  value: kSharePdfValue,
);

/// Пълното меню на четеца. Ползва се и от двата.
const List<ReaderMenuItem> kReaderMenuItems = [
  kReaderSettingsMenuItem,
  kBookmarksMenuItem,
  kQuotesMenuItem,
  // ⚠ Двете споделяния стоят ЕДНО ДО ДРУГО, а „четивото" е преди „PDF"
  // (изрично подредено от потребителя, 06.09.2026): линкът е по-лекият и
  // по-често търсен изход, PDF-ът — по-тежкият.
  kShareReadingMenuItem,
  kSharePdfMenuItem,
];

/// Показва менюто и връща избраното (или null при затваряне).
/// [disabled] — стойностите на точките, които се виждат, но НЕ се натискат.
///
/// ⚠⚠ ПОСИВЕНО, А НЕ МАХНАТО. Правилото важи в целия проект (виж лупата в
/// „Чети в контекст"): посивеното казва „има такова нещо, но не сега", а
/// липсващото прави менюто различно на два съседни екрана и човек се чуди
/// дали не е сбъркал къде е. Оттам и разликата с ТИХИЯ отказ — точка, която
/// изглежда жива и не прави нищо, е най-лошият от трите изхода.
Future<String?> showReaderMoreMenu(
  BuildContext context, {
  required List<ReaderMenuItem> items,
  Set<String> disabled = const {},
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
                        for (final item in items)
                          // ⚠ Посивяването е с ПРОЗРАЧНОСТ, а не с друг цвят
                          // — така мъртвото се чете като „същото, но не
                          // сега". Същият похват като при трите копчета в
                          // „Избери книги" (bible_scope_screen.dart).
                          Opacity(
                            opacity: disabled.contains(item.value) ? 0.38 : 1,
                            child: InkWell(
                              // ⚠ `null` вместо празна функция: така InkWell
                              // не рисува и вълничка при натискане, тоест
                              // редът не се преструва, че се е случило нещо.
                              onTap: disabled.contains(item.value)
                                  ? null
                                  : () => Navigator.of(ctx).pop(item.value),
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
