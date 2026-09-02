// Контекстното меню при маркиран текст — с ИКОНКИ вместо надписи.
//
// ⚠ Защо изобщо свое, вместо `AdaptiveTextSelectionToolbar`: тя рисува
// надписи („Копиране", „Споделяне", „Избиране на всичко"), а с добавената
// точка „Запази цитат" редът става четири думи и се пренася на два реда над
// текста. Иконките ги събират в един ред и се четат по-бързо — човек ги
// познава от всяко друго приложение. (Искане на потребителя, 02.09.2026.)
//
// ⚠ РАЗДЕЛЕНИЕТО Е ПО ПРОИЗХОД, не по брой. Flutter казва вида на всеки
// бутон ([ContextMenuButtonType]); нашите четири получават иконки и стоят
// отпред, а всичко, което платформата добави от себе си — „Търси в
// интернет", „Преведи", каквото Android реши — отива зад трите точки. Така
// редът не расте от нещо, което не контролираме.

import 'package:flutter/material.dart';

import 'package:flutter_svg/flutter_svg.dart';

import 'app_theme.dart';
import 'reader_theme.dart';

/// Размерът на иконките в лентата.
///
/// ⚠ Едро НАРОЧНО. Първият опит беше 22 и потребителят го отхвърли като
/// „прекалено ситно" (02.09.2026): лентата изскача над текста, натиска се с
/// палец в движение и се чете за части от секундата — там дребната иконка е
/// по-лоша от надпис.
const double _kIconSize = 26;

/// Обичайната иконка за всеки познат вид бутон, или `null` за непознат.
///
/// ⚠ ПЛЪТНИТЕ варианти, не контурните (`*_outlined`). Тези иконки се четат
/// на един поглед и трябва да имат тежест; контурните се губят на дребно и
/// изглеждат недовършени до плътното сърце. Сверено срещу еталоните,
/// подадени от потребителя (02.09.2026).
IconData? _iconFor(ContextMenuButtonType? type) => switch (type) {
      ContextMenuButtonType.copy => Icons.content_copy,
      ContextMenuButtonType.cut => Icons.content_cut,
      ContextMenuButtonType.paste => Icons.content_paste,
      ContextMenuButtonType.selectAll => Icons.select_all,
      ContextMenuButtonType.share => Icons.share,
      _ => null,
    };

/// Лента с иконки над маркирания текст.
///
/// ⚠ ЦВЕТОВЕТЕ ИДВАТ ОТ ПАЛИТРАТА НА ЧЕТЕЦА, не от `AppColors`. Менюто
/// изскача върху страницата, а тя е кремава в светла тема и почти черна в
/// тъмна — закован цвят тук би бил нечетим в едната от двете. Точно този
/// капан вече е плащан веднъж: подканата за връщане имаше закован тъмен фон
/// и надписи от палитрата, тоест тъмно върху тъмно в светла тема (виж
/// CLAUDE.md, „Фонът на изскачащите прозорчета — palette.sheet").
///
/// `sheet` е сиво в двете теми — по-светло от почти черната страница и
/// по-тъмно от кремавата. Прозорчето се чете по РАЗЛИКАТА със страницата, не
/// по конкретния цвят.
class IconSelectionToolbar extends StatelessWidget {
  final TextSelectionToolbarAnchors anchors;
  final List<ContextMenuButtonItem> items;

  /// Точката „Запази цитат" — подава се отделно, за да получи своята иконка
  /// и да застане ПОСЛЕДНА сред нашите.
  final VoidCallback? onSaveQuote;

  /// Ако е подадено, ЗАМЕСТВА системното „Сподели".
  ///
  /// ⚠ Системното праща гол текст; това праща цитата с източник и линк, който
  /// отваря приложението на мястото му. Иконката остава същата — за човека
  /// действието е същото, само резултатът е по-полезен.
  final VoidCallback? onShareQuote;

  const IconSelectionToolbar({
    super.key,
    required this.anchors,
    required this.items,
    this.onSaveQuote,
    this.onShareQuote,
  });

  @override
  Widget build(BuildContext context) {
    final palette = ReaderTheme.palette;
    final ink = palette.ink;
    final sheet = palette.sheet;

    final known = <(IconData, VoidCallback?, String)>[];
    final rest = <ContextMenuButtonItem>[];
    for (final it in items) {
      final icon = _iconFor(it.type);
      if (icon != null) {
        final replaced = it.type == ContextMenuButtonType.share &&
                onShareQuote != null
            ? onShareQuote
            : it.onPressed;
        known.add((icon, replaced, _labelFor(it.type)));
      } else {
        // ⚠ Платформено — оставя се както си е, зад трите точки. Не му се
        // измисля иконка: не знаем какво е и надписът е единственото
        // сигурно.
        rest.add(it);
      }
    }

    return TextSelectionToolbar(
      anchorAbove: anchors.primaryAnchor,
      anchorBelow: anchors.secondaryAnchor ?? anchors.primaryAnchor,
      toolbarBuilder: (context, child) => Material(
        color: sheet,
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.antiAlias,
        child: child,
      ),
      children: [
        for (final (icon, onTap, tip) in known)
          IconButton(
            icon: Icon(icon, size: _kIconSize, color: ink),
            tooltip: tip,
            onPressed: onTap,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            constraints: const BoxConstraints(),
          ),
        if (onSaveQuote != null)
          IconButton(
            // ⚠ SVG, а не съставена от две Material иконки: първият опит
            // (сърце + плюс в Stack) излезе ситен и неравен до останалите.
            // Тази е рисувана нарочно и се оцветява при изписване, тъй че
            // следва темата — както знаците на Типикона.
            icon: SvgPicture.asset(
              AppIcons.addToFavorites,
              width: _kIconSize,
              height: _kIconSize,
              colorFilter: ColorFilter.mode(ink, BlendMode.srcIn),
            ),
            tooltip: 'Запази цитат',
            onPressed: onSaveQuote,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            constraints: const BoxConstraints(),
          ),
        if (rest.isNotEmpty)
          PopupMenuButton<int>(
            icon: Icon(Icons.more_vert, size: _kIconSize, color: ink),
            tooltip: 'Още',
            color: sheet,
            itemBuilder: (_) => [
              for (var i = 0; i < rest.length; i++)
                PopupMenuItem(
                  value: i,
                  child: Text(
                    rest[i].label ?? '',
                    style: TextStyle(color: ink),
                  ),
                ),
            ],
            onSelected: (i) => rest[i].onPressed?.call(),
          ),
      ],
    );
  }

  /// Надписът остава като подсказка при задържане — иконката се чете
  /// веднага, но при съмнение думата е налице.
  String _labelFor(ContextMenuButtonType? type) => switch (type) {
        ContextMenuButtonType.copy => 'Копиране',
        ContextMenuButtonType.cut => 'Изрязване',
        ContextMenuButtonType.paste => 'Поставяне',
        ContextMenuButtonType.selectAll => 'Избиране на всичко',
        ContextMenuButtonType.share => 'Споделяне',
        _ => '',
      };
}
