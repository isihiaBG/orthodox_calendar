// fast_explanation_sheet.dart
//
// Справка за поста на деня — обяснение по Типика за конкретното правило,
// определило поста днес (calendar_days.fast_explanation_key), плюс
// изречение, сочещо кой светия причинява послаблението — само за
// ключовете, отбелязани с relaxation в fast_explanations. Ключът се
// избира еднозначно в build.py (fasts.fast_explanation_key), защото
// няколко различни правила на Устава могат да делят едно и също
// (fast_period, fast_type) — напр. четирите повода за "Велик пост с
// олио" (събота/неделя, Обретение/40 мчч., Велики четвъртък, четвъртък
// на 5-та седмица). Отваря се от тап върху текста на поста в заглавната
// лента на дневния изглед — виж showFastExplanationSheet(). Изградена
// върху общия info_sheet.dart инструмент, по аналогия на
// typikon_legend_sheet.dart.

import 'package:flutter/material.dart';

import 'database_helper.dart';
import 'info_sheet.dart';
import 'models/day_model.dart';

// Само тези рангове и групи омекотяват пост — виж FEAST_RANKS/FEAST_GROUPS
// в tools/calendar_gen/fasts.py (същата логика, пренесена тук за да
// познаем кой светия е причината).
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

Future<void> showFastExplanationSheet(
  BuildContext context, {
  required CalendarDay day,
  required List<Saint> saintsToday,
}) async {
  final db = await DatabaseHelper.database;
  final rows = await db.query(
    'fast_explanations',
    where: 'key = ?',
    whereArgs: [day.fastExplanationKey],
    limit: 1,
  );

  // Заглавието на панела е титлата на самото правило от базата (напр.
  // „Велик пост — с олио (Обретение и свв. 40 мчч.)") — тя вече съдържа
  // и това, което пише в хедъра на дневния изглед, но по-подробно, затова
  // под чертата остава само поясняващият текст, без повторения.
  // Резервен вариант, ако правилото липсва в базата — текстът от хедъра
  // (същият, който day_screen._fastText сглобява).
  String title;
  String text;
  if (rows.isEmpty) {
    final periodName = DatabaseHelper.fastPeriods[day.fastPeriod] ?? '';
    final typeName = DatabaseHelper.fastTypes[day.fastType] ?? '';
    title = typeName.isEmpty ? periodName : '$periodName ($typeName)';
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
    title: title,
    items: [
      InfoSheetItem(description: text),
    ],
  );
}
