// section_header.dart
//
// Цветният хедър на справочните секции (виж reference_pager.dart) —
// заглавие, подканата "изберете година" и самата година. Цветът е
// различен за всяка секция, за да си личи къде се намираш след плъзгане
// настрани; горната лента НЕ се оцветява — същият принцип като в дневния
// изглед, където се сменя само фонът под лентата.
//
// Секцията "Справочник" няма година — подава year: null и хедърът остава
// само със заглавието.

import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'year_selector.dart';

const String _titleFamily = 'TamburinModern';
const String _bodyFamily = 'Cambria';

class SectionHeader extends StatelessWidget {
  final String title;
  final Color background;

  /// null → секцията няма избор на година (Справочник).
  final int? year;
  final ValueChanged<int>? onYearChanged;

  /// Базовият размер на шрифта от домакина — всички размери тук са
  /// производни от него, за да реагират на бутоните −/+ в лентата.
  final double baseFont;

  const SectionHeader({
    super.key,
    required this.title,
    required this.background,
    required this.baseFont,
    this.year,
    this.onYearChanged,
  });

  double _fs(double delta) => baseFont + delta;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: background,
      padding: const EdgeInsets.fromLTRB(24, 10, 24, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: _titleFamily,
              fontSize: _fs(23),
              height: 1.25,
              color: AppColors.textPrimary,
            ),
          ),
          if (year != null) ...[
            const SizedBox(height: 10),
            Text(
              'изберете година',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: _bodyFamily,
                fontSize: _fs(2),
                fontStyle: FontStyle.italic,
                color: AppColors.textSecondary,
              ),
            ),
            Center(
              child: YearSelector(
                value: year!,
                onChanged: onYearChanged ?? (_) {},
                fontSize: _fs(23),
                fontFamily: _titleFamily,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
