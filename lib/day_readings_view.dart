// day_readings_view.dart
//
// Секцията „Евангелие и Апостол" в дневния изглед.
//
// Устройството следва искането на потребителя (07.09.2026): групи със
// заглавие, а под всяко — по един ред на четиво, и ВСЕКИ РЕД е активна
// връзка, която отваря библейския четец:
//
//     Утр. Ев. 7
//        Йоан, зач. 63, гл. 20:1-10
//     Лит.
//        2 Кор., зач. 188, гл. 9:6-11
//        Матей, зач. 38, гл. 10:32-33, 37-38; 19:27-30
//     На свт.
//        Евр., зач. 318, гл. 7:26-8:2
//
// ⚠ Разчитането е в day_readings.dart (чист Dart, без Flutter — проверява се
// с `flutter test` върху истинските 1500 записа). Тук е само рисуването.

import 'package:flutter/material.dart';

import 'app_settings.dart';
import 'app_theme.dart';
import 'bible_db.dart';
import 'bible_reader.dart';
import 'database_helper.dart';
import 'day_readings.dart';

class DayReadingsSection extends StatefulWidget {
  final DateTime date;
  const DayReadingsSection({super.key, required this.date});

  @override
  State<DayReadingsSection> createState() => _DayReadingsSectionState();
}

class _DayReadingsSectionState extends State<DayReadingsSection> {
  late Future<List<ReadingGroup>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void didUpdateWidget(covariant DayReadingsSection old) {
    super.didUpdateWidget(old);
    if (old.date != widget.date) _future = _load();
  }

  Future<List<ReadingGroup>> _load() async =>
      groupReadings(await DatabaseHelper.dayReadingRows(widget.date));

  /// ⚠ Проверява се, че книгата НАИСТИНА я има в `bible.db`, преди да се
  /// отвори каквото и да е — същият довод като в [openBibleLink]: разчитането
  /// е работа с низове и ще приеме и повредена препратка, а четецът тогава се
  /// отваря на празен екран.
  Future<void> _open(ReadingLine line) async {
    final ref = line.ref;
    if (ref == null || ref.passages.isEmpty) return;
    final book = await BibleDb.book(ref.passages.first.book);
    if (book == null || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => BibleReader.forRef(ref)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<ReadingGroup>>(
      future: _future,
      builder: (context, snap) {
        // ⚠ ТРИТЕ СЪСТОЯНИЯ СЕ РАЗЛИЧАВАТ. Без клон за грешка тя изглежда
        // като „няма данни" и се търси с часове — записано е за MiniReader
        // и важи навсякъде.
        if (snap.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        if (snap.hasError) {
          return _plain('Четивата не можаха да се заредят.');
        }
        final groups = snap.data ?? const <ReadingGroup>[];
        if (groups.isEmpty) {
          return _plain('За този ден няма записани четива.');
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < groups.length; i++) ...[
              if (i > 0) const SizedBox(height: 12),
              Text(
                groups[i].title,
                style: const TextStyle(
                  color: AppColors.sectionTitle,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              for (final line in groups[i].lines) _line(line),
            ],
            // ⚠⚠ ЧЕСТНА БЕЛЕЖКА, ДОКАТО ЧЕТИВАТА НЕ СЕ ГЕНЕРИРАТ ПО СТИЛ.
            //
            // Таблицата `readings` е закотвена за СТАРИЯ стил и е копирана
            // непроменена в новостилната база. Подвижните четива са верни за
            // двата стила (Пасха пада на една и съща гражданска дата), но
            // четивата на светията по месецослова са с 13 дни встрани.
            //
            // ⚠ Проста корекция с изместване НЕ върши работа — на един и същи
            // физически ден двата стила честват РАЗЛИЧНИ светии, тъй че
            // изместените четива биха се озовали под чуждо име. Верният път е
            // четивата да се генерират отделно за всеки стил и всяка година
            // (уточнено от потребителя, 07.09.2026). Дотогава — казва се
            // направо, вместо да се показва мълчаливо разместено.
            if (!AppSettings.isOldStyle) ...[
              const SizedBox(height: 14),
              Text(
                '⚠ Четивата на светията по месецослова още не са подредени '
                'по нов стил. Четивата на деня са верни.',
                style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 13,
                  height: 1.4,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _plain(String text) => Text(
        text,
        style: const TextStyle(
            color: AppColors.textSecondary, fontSize: 15, height: 1.6),
      );

  Widget _line(ReadingLine line) {
    // ⚠ Бележка („Царските часове се пренасят на…") НЕ е връзка и не бива да
    // изглежда като такава — тя е указание за деня, не адрес на четиво.
    if (line.isNote || !line.tappable) {
      return Padding(
        padding: const EdgeInsets.only(left: 12, top: 3, bottom: 3),
        child: Text(
          line.display,
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 15,
            height: 1.45,
            fontStyle: line.isNote ? FontStyle.italic : FontStyle.normal,
          ),
        ),
      );
    }
    return InkWell(
      onTap: () => _open(line),
      child: Padding(
        // ⚠ Отстъпът е и зона за пръст: редовете са тесни, а целта трябва да
        // остане удобна за тапване.
        padding: const EdgeInsets.only(left: 12, top: 6, bottom: 6, right: 8),
        child: Text(
          line.display,
          // ⚠ Цветът е `sectionTitle` — СЪЩОТО синьо, с което са заглавията
          // на секциите и дяловете в указателя на Библията. Нищо ново не се
          // въвежда: за човека това е „води към Писанието".
          style: const TextStyle(
            color: AppColors.sectionTitle,
            fontSize: 15,
            height: 1.45,
            decoration: TextDecoration.underline,
            decorationStyle: TextDecorationStyle.dotted,
            decorationColor: AppColors.sectionDivider,
          ),
        ),
      ),
    );
  }
}
