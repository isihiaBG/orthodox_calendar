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
import 'readings_lookup.dart';
import 'saint_expandable_tile.dart';
import 'prokimen_lookup.dart';

class DayReadingsSection extends StatefulWidget {
  final DateTime date;

  /// Гласът на седмицата (0 = няма).
  ///
  /// ⚠ Нужен е за ПРОКИМЕНА: в неделя се чете възкресният по глас. Подава
  /// се отвън, защото дневният изглед и без това го е прочел — втора
  /// заявка за същото число би била излишна.
  final int tone;

  const DayReadingsSection({super.key, required this.date, this.tone = 0});

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

  /// ⚠ Чете се И ПРЕДНИЯТ ДЕН — заради дванайсетте страстни евангелия, които
  /// в базата стоят на Велики четвъртък, а принадлежат на утренята на Велики
  /// петък. Виж [effectiveRows]: пренасянето е симетрично, тъй че на
  /// четвъртъка те вече не се показват.
  ///
  /// ⚠ Втората заявка е ЕВТИНА (един индексиран ред по дата) и се прави за
  /// всеки ден — по-добре, отколкото правило „само при Велики четвъртък",
  /// което би зависело от разпознаване на деня.
  /// ⚠⚠ ЧЕТИВАТА СЕ СМЯТАТ, НЕ СЕ ЧЕТАТ ОТ БАЗАТА.
  ///
  /// Таблицата `readings` е парсната за ЕДНА църковна година и е ключирана
  /// по ГРАЖДАНСКА дата, тъй че не важи за друга година; а в новостилната
  /// база е копирана непроменена и неподвижните четива излизаха с 13 дни
  /// встрани. Сега [readingsFor] ги извежда от два пласта, независими от
  /// годината И от стила — виж `readings_lookup.dart`.
  ///
  /// ⚠ Старата таблица НЕ Е трита: тя е парсната от източник и служи за
  /// сверка на генерираното (правило на потребителя). Тестът
  /// `test/readings_cycle_test.dart` я ползва точно за това.
  List<ReadingRow> _rowsFor(DateTime d) {
    final church = SaintTexts.churchDateOf(
        d.toIso8601String().substring(0, 10), 0);
    if (church == null) return const [];
    final key = '${church.month.toString().padLeft(2, '0')}-'
        '${church.day.toString().padLeft(2, '0')}';
    return [
      for (final r in readingsFor(d, key, oldStyle: AppSettings.isOldStyle))
        (r.type, r.ref),
    ];
  }

  Future<List<ReadingGroup>> _load() async {
    // ⚠ И вчерашният ден — заради дванайсетте страстни евангелия, които се
    // пишат на Велики четвъртък, а принадлежат на утренята на Велики петък
    // (виж [effectiveRows]).
    final today = _rowsFor(widget.date);
    final yesterday = _rowsFor(widget.date.subtract(const Duration(days: 1)));
    return groupReadings(effectiveRows(today, yesterday));
  }

  /// ⚠ Проверява се, че книгата НАИСТИНА я има в `bible.db`, преди да се
  /// отвори каквото и да е — същият довод като в [openBibleLink]: разчитането
  /// е работа с низове и ще приеме и повредена препратка, а четецът тогава се
  /// отваря на празен екран.
  Future<void> _open(ReadingLine line) async {
    final ref = line.ref;
    if (ref == null || ref.passages.isEmpty) return;
    final book = await BibleDb.book(ref.passages.first.book);
    if (book == null || !mounted) return;
    // ⚠ ПРОКИМЕНЪТ се разрешава ТУК, а не в четеца: тук се знае денят, гласът
    // и зачалото, а четецът вижда само препратката. Той получава наготово
    // онова, което трябва да нарисува.
    final prok = line.isApostle ? _prokimenFor(line) : null;
    await Navigator.of(context).push(
      // ⚠ Обръщението („Братя,") и прокименът се добавят САМО при апостолско
      // четиво. Флагът е по подразбиране `false`, тъй че всяко друго отваряне
      // на четеца — включително вече споделените линкове — остава непроменено.
      MaterialPageRoute(
        builder: (_) => BibleReader.forRef(ref,
            liturgical: line.isApostle, prokimen: prok?.prokimen),
      ),
    );
  }

  /// Кой прокимен се пада на това четиво — виж [prokimenFor].
  ///
  /// ⚠ ЦЪРКОВНАТА ДАТА, не гражданската. При СТАР стил тя е гражданската
  /// минус 13 дни; при нов двете съвпадат — същото правило, което
  /// `SaintTexts.churchDateOf` пази на едно място.
  ProkimenHit? _prokimenFor(ReadingLine line) {
    final d = widget.date;
    final church = AppSettings.isOldStyle
        ? d.subtract(const Duration(days: 13))
        : d;
    final pascha = DatabaseHelper.paschaOf(d.year);
    return prokimenFor(
      churchMonthDay: '${church.month.toString().padLeft(2, '0')}-'
          '${church.day.toString().padLeft(2, '0')}',
      weekday: d.weekday,
      tone: widget.tone > 0 ? widget.tone : null,
      zachalo: line.zachalo,
      daysFromPascha: d.difference(pascha).inDays,
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
