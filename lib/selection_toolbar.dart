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

import 'reader_theme.dart';

/// Иконката за „Запази цитат" — сърце с плюс.
///
/// ⚠ Съставена, защото готова такава няма в Material. Плюсът стои в долния
/// десен ъгъл, върху кръгче в цвета на ЛЕНТАТА, за да не се слее с линията
/// на сърцето. [background] идва отвън по същата причина, по която и всичко
/// останало тук — виж бележката при [IconSelectionToolbar].
class _AddToFavouritesIcon extends StatelessWidget {
  final Color color;
  final Color background;
  const _AddToFavouritesIcon({required this.color, required this.background});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 24,
      height: 24,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Icon(Icons.favorite_border, size: 22, color: color),
          Positioned(
            right: -1,
            bottom: 0,
            child: Container(
              decoration: BoxDecoration(
                color: background,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(Icons.add, size: 12, color: color),
            ),
          ),
        ],
      ),
    );
  }
}

/// Обичайната иконка за всеки познат вид бутон, или `null` за непознат.
IconData? _iconFor(ContextMenuButtonType? type) => switch (type) {
      ContextMenuButtonType.copy => Icons.content_copy_outlined,
      ContextMenuButtonType.cut => Icons.content_cut,
      ContextMenuButtonType.paste => Icons.content_paste_outlined,
      ContextMenuButtonType.selectAll => Icons.select_all,
      ContextMenuButtonType.share => Icons.share_outlined,
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

  const IconSelectionToolbar({
    super.key,
    required this.anchors,
    required this.items,
    this.onSaveQuote,
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
        known.add((icon, it.onPressed, _labelFor(it.type)));
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
            icon: Icon(icon, size: 22, color: ink),
            tooltip: tip,
            onPressed: onTap,
            visualDensity: VisualDensity.compact,
          ),
        if (onSaveQuote != null)
          IconButton(
            icon: _AddToFavouritesIcon(color: ink, background: sheet),
            tooltip: 'Запази цитат',
            onPressed: onSaveQuote,
            visualDensity: VisualDensity.compact,
          ),
        if (rest.isNotEmpty)
          PopupMenuButton<int>(
            icon: Icon(Icons.more_vert, size: 22, color: ink),
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
