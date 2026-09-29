// molitvoslov_lang_chip.dart
//
// Етикетът с наличните езици в съдържанието на молитвослова: „бг│цс│цс гр.".
//
// ⚠ ТИХ, нарочно (избор на потребителя измежду три вида): съдържанието е
// списък от десетки редове и ярък етикет на всеки ред прави колона от петна,
// която спори със заглавията — същата грешка в „бюджета за визуална тежест",
// поправена вече в съдържанието на Библията. Бледо запълнен фон, приглушени
// букви, тънки черти помежду им: личи, когато го търсиш.
//
// Тап върху етикета показва отдолу пояснение с пълните имена. Той е свой
// жест — не отваря реда под себе си.

import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'bible_reader.dart' show kLanguageFontFamilies;

const Map<String, String> _kAbbr = {'bg': 'бг', 'csl': 'цс', 'csr': 'цс гр.'};
const Map<String, String> _kName = {
  'bg': 'български (бг)',
  'csl': 'църковнославянски (цс)',
  'csr': 'църковнославянски с граждански шрифт (цс гр.)',
};

/// „Налично на български (бг) и църковнославянски (цс)."
String langsExplanation(List<String> langs) {
  final names = [for (final l in langs) _kName[l] ?? l];
  if (names.isEmpty) return '';
  final list = names.length == 1
      ? names.first
      : '${names.sublist(0, names.length - 1).join(', ')} и ${names.last}';
  return 'Налично на $list.';
}

TextStyle _csStyle(TextStyle base) {
  final chain = kLanguageFontFamilies['cslavonic'] ?? const <String>[];
  return base.copyWith(
    fontFamily: chain.isEmpty ? null : chain.first,
    fontFamilyFallback: chain.length < 2 ? null : chain.sublist(1),
    fontSize: 14, // цс шрифтът е по-дребен на око при същия кегел
    fontWeight: FontWeight.w400,
    letterSpacing: 0.6,
  );
}

class LangChip extends StatelessWidget {
  final List<String> langs;
  const LangChip(this.langs, {super.key});

  @override
  Widget build(BuildContext context) {
    if (langs.isEmpty) return const SizedBox.shrink();
    const text = TextStyle(
        color: AppColors.textSecondary,
        fontSize: 11.5,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.3,
        height: 1.1);
    const sep = TextStyle(color: AppColors.textMuted, fontSize: 11.5, height: 1.1);
    return Tooltip(
      message: langsExplanation(langs),
      triggerMode: TooltipTriggerMode.tap,
      showDuration: const Duration(seconds: 4),
      preferBelow: true,
      verticalOffset: 14,
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.backgroundCard,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.sectionDivider),
        boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 10, offset: Offset(0, 3))],
      ),
      textStyle: const TextStyle(color: AppColors.textPrimary, fontSize: 14, height: 1.35),
      child: Container(
        // Малко по-широко поле за пръста, отколкото е самото петно.
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: AppColors.textPrimary.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(5),
          ),
          child: Text.rich(TextSpan(children: [
            for (var i = 0; i < langs.length; i++) ...[
              if (i > 0) const TextSpan(text: '\u2009│\u2009', style: sep),
              TextSpan(
                  text: _kAbbr[langs[i]] ?? langs[i],
                  // ⚠ „цс" е изписано СЪС САМИЯ цс шрифт, „цс гр." — със
                  // системния: така двете се различават и на око, а
                  // етикетът показва кой шрифт ще види човек (потребителят).
                  style: langs[i] == 'csl' ? _csStyle(text) : text),
            ],
          ])),
        ),
      ),
    );
  }
}
