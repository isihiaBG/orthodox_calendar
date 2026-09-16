// expandable_section.dart
//
// Разгъващата се секция с chevron — „ЕВАНГЕЛИЕ И АПОСТОЛ", „СЛОВА ЗА ДЕНЯ",
// „МИСЛИ ОТ ТЕОФАН ЗАТВОРНИК" и останалите в дневния изглед.
//
// ⚠ Изнесена от `day_screen.dart` на 16.09.2026, защото същият вид потрябва
// и ВЪТРЕ в плочката на празника („Празници"). Преписана на две места, тя
// щеше да се размине при първата промяна в анимацията или в отстъпите — а
// това е точно нещото, което човек забелязва като „тук изглежда другояче".
//
// ⚠⚠ СЪДЪРЖАНИЕТО СЕ МОНТИРА ЧАК ПРИ РАЗГЪВАНЕ. На това разчитат Теофан,
// Оптинските старци и `MiniReader` — заявката им тръгва тогава, а не при
// построяване на деня.

import 'package:flutter/material.dart';

import 'app_theme.dart';

class ExpandableSection extends StatefulWidget {
  final String title;
  final Widget content;
  final bool initiallyExpanded;
  final bool isSunday;

  const ExpandableSection({
    super.key,
    required this.title,
    required this.content,
    this.initiallyExpanded = false,
    this.isSunday = false,
  });

  @override
  State<ExpandableSection> createState() => _ExpandableSectionState();
}

class _ExpandableSectionState extends State<ExpandableSection> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.isSunday
        ? AppColors.sectionTitleSunday
        : AppColors.sectionTitle;

    return Column(
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Container(
            // Ляво поле по-малко от дясното — иначе знакът (📖/🕯️/📜/⛪)
            // застава по-навътре от булетите на светиите и менюто горе,
            // и трите извън същата визуална колона.
            padding: const EdgeInsets.fromLTRB(0, 12, 4, 12),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: AppColors.sectionDivider, width: 0.5),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: RichText(
                    text: TextSpan(
                      children: [
                        TextSpan(
                          text: widget.title.substring(0, 2),
                          style: const TextStyle(fontSize: 20),
                        ),
                        TextSpan(
                          text: widget.title.substring(2),
                          style: TextStyle(color: color, fontSize: 14, letterSpacing: 0.5),
                        ),
                      ],
                    ),
                  ),
                ),
                Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  color: color,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          child: _expanded
              ? Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: widget.content,
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}
