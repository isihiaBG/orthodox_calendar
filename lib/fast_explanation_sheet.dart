// fast_explanation_sheet.dart
//
// Справка за поста на деня — обяснение по Типика за конкретната
// комбинация (fast_period, fast_type) от таблицата fast_explanations,
// плюс изречение, сочещо кой светия причинява послаблението, ако денят е
// такъв случай (колоната relaxation). Отваря се от тап върху текста на
// поста в заглавната лента на дневния изглед — виж
// showFastExplanationSheet(). Изградена върху общия info_sheet.dart
// инструмент, по аналогия на typikon_legend_sheet.dart.

import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'database_helper.dart';
import 'info_sheet.dart';
import 'models/day_model.dart';

// Само тези рангове и групи омекотяват пост извън Велики пост — виж
// FEAST_RANKS/FEAST_GROUPS в tools/calendar_gen/fasts.py (същата логика,
// пренесена тук за да познаем кой светия е причината).
const Set<int> _feastRanks = {1, 2, 3, 4};
const Set<String> _feastGroups = {'ECUMENICAL', 'BG'};

const Map<int, String> _rankNames = {
  1: 'бдение на голям празник',
  2: 'бдение',
  3: 'полиелей',
  4: 'славословна служба',
};

/// Първият светия от деня, чиято служба реално омекотява пост (по ранг и
/// група) — или null, ако денят е тип-достижим без такъв (база/именуван
/// ден по Типика).
Saint? _causingSaint(List<Saint> saintsToday) {
  for (final s in saintsToday) {
    if (_feastRanks.contains(s.rank) && _feastGroups.contains(s.groupCode)) {
      return s;
    }
  }
  return null;
}

Widget _dot(Color color) => Center(
      child: Text('•',
          style: TextStyle(
            color: color,
            fontSize: 22,
            fontWeight: FontWeight.bold,
          )),
    );

Future<void> showFastExplanationSheet(
  BuildContext context, {
  required CalendarDay day,
  required List<Saint> saintsToday,
}) async {
  final db = await DatabaseHelper.database;
  final rows = await db.query(
    'fast_explanations',
    where: 'fast_period = ? AND fast_type = ?',
    whereArgs: [day.fastPeriod, day.fastType],
    limit: 1,
  );

  final periodName = DatabaseHelper.fastPeriods[day.fastPeriod] ?? '';
  final typeName = DatabaseHelper.fastTypes[day.fastType] ?? '';
  final subtitle = typeName.isEmpty ? periodName : '$periodName ($typeName)';

  String title;
  String text;
  if (rows.isEmpty) {
    title = subtitle;
    text = 'Няма запазено пояснение за тази комбинация.';
  } else {
    title = rows.first['title'] as String;
    text = rows.first['text'] as String;

    if (rows.first['relaxation'] != null) {
      final causer = _causingSaint(saintsToday);
      if (causer != null) {
        final rankName = _rankNames[causer.rank] ?? 'празник';
        text = '$text\n\nПричина за днешното послабление: '
            '${causer.name} ($rankName).';
      }
    }
  }

  if (!context.mounted) return;

  showInfoSheet(
    context: context,
    title: 'Пост',
    subtitle: subtitle,
    items: [
      InfoSheetItem(
        leading: _dot(AppColors.fastText),
        title: title,
        description: text,
      ),
    ],
  );
}
