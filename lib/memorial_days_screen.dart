// memorial_days_screen.dart
//
// "Дни за помени" — задушниците и родителските съботи. Едно от четирите
// тела на reference_pager.dart: НЯМА собствен Scaffold и лента, а
// годината и шрифтът идват от домакина.
//
// Устроен е като fasts_screen.dart — датите се ИЗЧИСЛЯВАТ, нищо не се
// чете от календарната база, тъй че екранът работи за произволна година:
//  - подвижните — отмествания в дни спрямо Пасха;
//  - Архангеловата задушница — съботата преди Архангеловден (8.XI
//    църковно), затова се търси спрямо самата дата, а не с константа.
//
// ⚠ СПИСЪКЪТ Е ВРЕМЕНЕН. Взет е по българската практика (у нас няма
// Димитриевска събота, а Архангелова задушница), но потребителят изрично
// каза, че ще го уточни по-късно. Промяната е в _movable/_fixed по-долу
// и не изисква нищо друго да се пипа.

import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'dual_date_text.dart';
import 'paschalion.dart';
import 'section_header.dart';

const String _bodyFamily = 'CharisSIL';
const Color _ink = AppColors.textPrimary;
const Color _dim = AppColors.textSecondary;
const Color _headingRed = Color(0xFFBB8C9C);

/// Един ден за помен. Подвижните носят отместване спрямо Пасха;
/// Архангеловата задушница се смята отделно (виж _resolve).
class _MemorialSpec {
  final String name;
  final int? fromPascha;

  /// Съботата ПРЕДИ тази църковна дата (месец, ден) — за Архангеловата.
  final (int month, int day)? saturdayBefore;

  const _MemorialSpec(this.name, {this.fromPascha, this.saturdayBefore});
}

// ─── Задушници ───────────────────────────────────────────────────────
// Месопустната е съботата преди Месопустна неделя (Пасха − 56), тоест
// Пасха − 57. Петдесетничната е съботата преди Петдесетница (Пасха + 49),
// тоест Пасха + 48.
const List<_MemorialSpec> _soulSaturdays = [
  _MemorialSpec('Месопустна задушница', fromPascha: -57),
  _MemorialSpec('Петдесетнична (Троицка) задушница', fromPascha: 48),
  _MemorialSpec('Архангелова задушница', saturdayBefore: (11, 8)),
];

// ─── Родителски съботи през Великия пост ─────────────────────────────
// Чистият понеделник е Пасха − 48; съботите на 2-ра, 3-та и 4-та седмица
// падат съответно 36, 29 и 22 дни преди Пасха.
const List<_MemorialSpec> _lentSaturdays = [
  _MemorialSpec('Събота на 2-ра седмица от Великия пост', fromPascha: -36),
  _MemorialSpec('Събота на 3-та седмица от Великия пост', fromPascha: -29),
  _MemorialSpec('Събота на 4-та седмица от Великия пост', fromPascha: -22),
];

class MemorialDaysSection extends StatefulWidget {
  final int year;
  final ValueChanged<int> onYearChanged;
  final double baseFont;

  /// Расте при смяна на настройките (стар/нов стил) — датите тук се смятат
  /// при всяко рисуване, тъй че самото преначертаване стига.
  final int revision;

  const MemorialDaysSection({
    super.key,
    required this.year,
    required this.onYearChanged,
    required this.baseFont,
    required this.revision,
  });

  @override
  State<MemorialDaysSection> createState() => _MemorialDaysSectionState();
}

class _MemorialDaysSectionState extends State<MemorialDaysSection> {
  double _fs(double delta) => widget.baseFont + delta;

  /// Съботата непосредствено ПРЕДИ дадена дата. Ако самата дата е събота,
  /// се връща предходната — задушницата предхожда празника.
  DateTime _saturdayBefore(DateTime d) {
    // DateTime.saturday == 6. Остатъкът дава колко дни назад е последната
    // събота; 0 значи, че самата дата е събота — тогава връщаме
    // предходната, цяла седмица назад.
    final back = (d.weekday - DateTime.saturday) % 7;
    return d.subtract(Duration(days: back == 0 ? 7 : back));
  }

  DateTime _resolve(_MemorialSpec spec) {
    if (spec.fromPascha != null) {
      return paschaCivil(widget.year).add(Duration(days: spec.fromPascha!));
    }
    final feast =
        civilFromChurch(widget.year, spec.saturdayBefore!.$1, spec.saturdayBefore!.$2);
    return _saturdayBefore(feast);
  }

  Widget _row(_MemorialSpec spec) {
    final date = _resolve(spec);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text.rich(
        TextSpan(
          children: [
            ...dualDateSpans(date, _fs(1),
                ink: _ink, dim: _dim, fontFamily: _bodyFamily),
            const TextSpan(text: '  –  ', style: TextStyle(color: _dim)),
            TextSpan(
              text: spec.name,
              style: TextStyle(
                  fontFamily: _bodyFamily,
                  fontSize: _fs(1),
                  color: _ink,
                  height: 1.35),
            ),
          ],
        ),
      ),
    );
  }

  Widget _h2(String text) => Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 6),
        child: Text(text,
            style: TextStyle(
                fontFamily: _bodyFamily,
                fontSize: _fs(5),
                fontWeight: FontWeight.bold,
                color: _headingRed)),
      );

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            title: 'Дни за помен на починалите',
            background: AppColors.sectionMemorial,
            baseFont: widget.baseFont,
            year: widget.year,
            onYearChanged: widget.onYearChanged,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 6, 24, 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _h2('Задушници'),
                for (final s in _soulSaturdays) _row(s),
                _h2('Родителски съботи през Великия пост'),
                for (final s in _lentSaturdays) _row(s),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
