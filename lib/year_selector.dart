// year_selector.dart
//
// Избор на година — общ за "Празници" и "Пости". Стандартният Material
// DropdownMenu, но с включено писане: освен да избере от списъка,
// потребителят може да НАПИШЕ година (включително извън предложения
// обхват) и да натисне Enter.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_theme.dart';

/// Разумни граници на въведената година. Пасхалията се смята за всяка
/// година, но извън този период сметките губят практически смисъл.
const int kMinYear = 1583;
const int kMaxYear = 2400;

class YearSelector extends StatefulWidget {
  final int value;
  final List<int> years;
  final ValueChanged<int> onChanged;
  final double fontSize;
  final String fontFamily;
  final Color color;

  const YearSelector({
    super.key,
    required this.value,
    required this.years,
    required this.onChanged,
    required this.fontSize,
    required this.fontFamily,
    required this.color,
  });

  @override
  State<YearSelector> createState() => _YearSelectorState();
}

class _YearSelectorState extends State<YearSelector> {
  late final TextEditingController _controller =
      TextEditingController(text: '${widget.value}');

  @override
  void didUpdateWidget(YearSelector old) {
    super.didUpdateWidget(old);
    // Размерът на шрифта/годината може да се смени отвън (бутоните −/+,
    // смяна на година) — държим полето в синхрон.
    if (widget.value != old.value && _controller.text != '${widget.value}') {
      _controller.text = '${widget.value}';
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Приема написаното на ръка. Ако е безсмислено, връща полето към
  /// текущата година, вместо да остави потребителя с невалиден текст.
  void _submitTyped(String raw) {
    final parsed = int.tryParse(raw.trim());
    if (parsed != null && parsed >= kMinYear && parsed <= kMaxYear) {
      widget.onChanged(parsed);
    } else {
      _controller.text = '${widget.value}';
    }
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontFamily: widget.fontFamily,
      fontSize: widget.fontSize,
      color: widget.color,
    );
    // DropdownMenu няма onSubmitted/onEditingComplete. Затова прихващаме
    // загубата на фокус (натиснат Enter, тап другаде) и чак тогава
    // приемаме написаната на ръка година.
    return Focus(
      onFocusChange: (hasFocus) {
        if (!hasFocus) _submitTyped(_controller.text);
      },
      child: DropdownMenu<int>(
        controller: _controller,
        initialSelection: widget.value,
        // Двете заедно позволяват писане и филтриране на списъка.
        requestFocusOnTap: true,
        enableFilter: true,
        width: widget.fontSize * 6.5,
        textStyle: style,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        onSelected: (y) {
          if (y != null) widget.onChanged(y);
        },
        // DropdownMenu няма onSubmitted — прихващаме Enter от вътрешното поле.
        inputDecorationTheme: const InputDecorationTheme(
          border: InputBorder.none,
          isDense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: 4),
        ),
        menuStyle: const MenuStyle(
          backgroundColor: WidgetStatePropertyAll(AppColors.toolbar),
        ),
        dropdownMenuEntries: [
          for (final y in widget.years)
            DropdownMenuEntry(
              value: y,
              label: '$y',
              style: MenuItemButton.styleFrom(
                foregroundColor: AppColors.textPrimary,
                textStyle: style.copyWith(fontSize: widget.fontSize * 0.6),
              ),
            ),
        ],
      ),
    );
  }
}
