// year_selector.dart
//
// Избор на година — общ за "Празници" и "Пости".
//
// Самата година си стои като обикновен текст (както преди), а при
// докосване се отваря диалог със СТАНДАРТНАТА решетка с години на Flutter
// (YearPicker — същата, която се показва при тап върху годината в избора
// на дата в дневния изглед), плюс поле за ръчно въвеждане на година извън
// показания обхват.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_theme.dart';

/// Разумни граници на въведената година. Пасхалията се смята за всяка
/// година, но извън този период сметките губят практически смисъл.
const int kMinYear = 1583;
const int kMaxYear = 2400;

class YearSelector extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;
  final double fontSize;
  final String fontFamily;
  final Color color;

  const YearSelector({
    super.key,
    required this.value,
    required this.onChanged,
    required this.fontSize,
    required this.fontFamily,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        final picked = await showDialog<int>(
          context: context,
          builder: (_) => _YearPickerDialog(initialYear: value),
        );
        if (picked != null && picked != value) onChanged(picked);
      },
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$value',
              style: TextStyle(
                  fontFamily: fontFamily, fontSize: fontSize, color: color),
            ),
            const SizedBox(width: 4),
            Icon(Icons.arrow_drop_down, color: color, size: fontSize * 0.7),
          ],
        ),
      ),
    );
  }
}

class _YearPickerDialog extends StatefulWidget {
  final int initialYear;
  const _YearPickerDialog({required this.initialYear});

  @override
  State<_YearPickerDialog> createState() => _YearPickerDialogState();
}

class _YearPickerDialogState extends State<_YearPickerDialog> {
  late final TextEditingController _typed =
      TextEditingController(text: '${widget.initialYear}');
  late final DateTime _selected = DateTime.utc(widget.initialYear);
  String? _error;
  bool _manualOpen = false;

  @override
  void dispose() {
    _typed.dispose();
    super.dispose();
  }

  void _acceptTyped() {
    final parsed = int.tryParse(_typed.text.trim());
    if (parsed == null || parsed < kMinYear || parsed > kMaxYear) {
      setState(() => _error = 'Само между $kMinYear и $kMaxYear');
      return;
    }
    Navigator.of(context).pop(parsed);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.background,
      title: const Text('Изберете година', style: TextStyle(fontSize: 20)),
      contentPadding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      content: SizedBox(
        width: 320,
        height: 320,
        child: Column(
          children: [
            // Решетката с години — стандартният Flutter компонент, същият
            // като в избора на дата.
            Expanded(
              child: YearPicker(
                firstDate: DateTime.utc(kMinYear),
                lastDate: DateTime.utc(kMaxYear),
                selectedDate: _selected,
                onChanged: (d) => Navigator.of(context).pop(d.year),
              ),
            ),
            const Divider(color: AppColors.sectionDivider, height: 1),
            // Полето за ръчно въвеждане стои СКРИТО, докато потребителят
            // не го поиска — иначе заема място и отвлича вниманието от
            // решетката, която върши работа в почти всички случаи.
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: _manualOpen
                  ? Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _typed,
                            autofocus: true,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(4),
                            ],
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                                color: AppColors.textPrimary, fontSize: 18),
                            decoration: InputDecoration(
                              labelText: 'година',
                              labelStyle: const TextStyle(
                                  color: AppColors.textMuted, fontSize: 13),
                              errorText: _error,
                              isDense: true,
                            ),
                            onSubmitted: (_) => _acceptTyped(),
                            onChanged: (_) {
                              if (_error != null) setState(() => _error = null);
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        TextButton(
                            onPressed: _acceptTyped, child: const Text('Готово')),
                      ],
                    )
                  : Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => setState(() => _manualOpen = true),
                        icon: const Icon(Icons.keyboard, size: 18),
                        label: const Text('въведи ръчно'),
                      ),
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Отказ'),
        ),
      ],
    );
  }
}
