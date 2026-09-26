// day_hymns.dart
//
// Секцията „ТРОПАРИ И КОНДАЦИ" в дневния изглед — САМО РЕДОВЕ-ЛИНКОВЕ, както
// в руското календарче. Тапът отваря песнопенията в четеца
// (`ReaderScreen.prayers`), същия, в който се отварят и тези на празниците.
//
// ⚠⚠ ПРАЗНИЦИТЕ И СВЕТИИТЕ НЕ СЕ ДУБЛИРАТ. Тяхните песнопения вече живеят в
// `lives.hymns` — и то с български превод — и се отварят от реда на самия
// празник. Тук стои само ОЩЕ ЕДИН ЛИНК към същото четиво (решение на
// потребителя, 26.09.2026). Свои данни имат единствено възкресните и дневните
// — таблица `lives.hymn_cycle` (прави я `tools/Troparion/`).
//
// ⚠ Подредбата е по ранг, пак по искане на потребителя:
//     1  празник от ранг 1
//     2  възкресни, глас N              — само в неделя
//     3  ранг 2, 3, 4 + българските светии (без оглед на ранга)
//     4  дневни („За понеделник")       — не и в празник от ранг 1
// Светлата седмица е изключение: тогава стои само Пасха (глас в смисъла на
// възкресния тропар няма, а дневните не се пеят).

import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'database_helper.dart';
import 'models/day_model.dart';
import 'paschalion.dart';
import 'reader_screen.dart';
import 'saint_expandable_tile.dart';

const String kPaschaSlug = 'prazdnik-pasha-svetloe-hristovo-voskresenie';

const _kWeekdayLabel = {
  1: 'За понеделник',
  2: 'За вторник',
  3: 'За сряда',
  4: 'За четвъртък',
  5: 'За петък',
  6: 'За събота',
};

/// Един ред в секцията: надпис и как се отваря.
class DayHymnRow {
  final String label;

  /// Слъг на светия/празник — отваря ЗАВАРЕНИТЕ му песнопения.
  final String? slug;

  /// Ключ в `hymn_cycle` („voskr-3", „dnevni-1") — възкресни/дневни.
  final String? cycleKey;

  const DayHymnRow.saint(this.label, String this.slug) : cycleKey = null;
  const DayHymnRow.cycle(this.label, String this.cycleKey) : slug = null;
}

/// Редовете за деня, по установения приоритет.
///
/// ⚠ Чиста функция — не пита базата, за да се проверява без екран.
List<DayHymnRow> dayHymnRows({
  required DateTime date,
  required List<Saint> saints,
  required int tone,
}) {
  bool hasHymns(Saint s) =>
      (s.slug ?? '').isNotEmpty && (s.hymnCounts ?? '').isNotEmpty;

  // Светлата седмица — само Пасха.
  final pascha = paschaCivil(date.year);
  final d = DateTime(date.year, date.month, date.day);
  final fromPascha = d.difference(DateTime(pascha.year, pascha.month, pascha.day)).inDays;
  if (fromPascha >= 0 && fromPascha <= 6) {
    final p = saints.where((s) => s.slug == kPaschaSlug).toList();
    return [DayHymnRow.saint(p.isNotEmpty ? p.first.name : 'Пасха', kPaschaSlug)];
  }

  final seen = <String>{};
  final out = <DayHymnRow>[];
  void addSaint(Saint s) {
    if (!hasHymns(s) || !seen.add(s.slug!)) return;
    out.add(DayHymnRow.saint(s.name, s.slug!));
  }

  final rank1 = saints.where((s) => s.rank == 1 && hasHymns(s)).toList();
  rank1.forEach(addSaint);
  if (date.weekday == DateTime.sunday && tone >= 1 && tone <= 8) {
    out.add(DayHymnRow.cycle('Възкресни, глас $tone', 'voskr-$tone'));
  }
  for (final s in saints) {
    if ((s.rank >= 2 && s.rank <= 4) || s.groupCode == 'BG') addSaint(s);
  }
  final daily = _kWeekdayLabel[date.weekday];
  if (daily != null && rank1.isEmpty) {
    out.add(DayHymnRow.cycle(daily, 'dnevni-${date.weekday}'));
  }
  return out;
}

/// Песнопенията на един ключ от цикъла — готови за четеца.
Future<SaintTexts?> loadCycleTexts(String key, String title) async {
  final db = await DatabaseHelper.database;
  final rows = await db.rawQuery('''
    SELECT kind, kind_ru, glas, csl, bg
    FROM lives.hymn_cycle WHERE key = ? ORDER BY ord
  ''', [key]);
  if (rows.isEmpty) return null;
  return SaintTexts(name: title, hymns: rows.map(Hymn.fromMap).toList());
}

class DayHymnsSection extends StatelessWidget {
  final List<DayHymnRow> rows;
  final SaintLookup lookup;

  const DayHymnsSection({super.key, required this.rows, required this.lookup});

  Future<void> _open(BuildContext context, DayHymnRow r) async {
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final texts = r.slug != null
        ? await lookup(r.slug!)
        : await loadCycleTexts(r.cycleKey!, r.label);
    // ⚠ Липсващо четиво се СЪОБЩАВА, не се подминава мълчаливо.
    if (texts == null || !texts.hasPrayers) {
      messenger.showSnackBar(
          const SnackBar(content: Text('Песнопенията не са намерени.')));
      return;
    }
    await nav.push(MaterialPageRoute(
      builder: (_) => ReaderScreen.prayers(texts: texts, lookup: lookup),
    ));
  }

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return const Text('За този ден няма песнопения.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 15));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final r in rows)
          InkWell(
            onTap: () => _open(context, r),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 3, right: 8),
                    child: Icon(Icons.music_note_outlined,
                        size: 16, color: AppColors.sectionTitle),
                  ),
                  Expanded(
                    child: Text(
                      r.label,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.sectionTitle,
                        fontSize: 15,
                        height: 1.5,
                        decoration: TextDecoration.underline,
                        decorationStyle: TextDecorationStyle.dotted,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
