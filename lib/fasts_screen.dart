// fasts_screen.dart
//
// "Пости" — многодневните пости, еднодневните и седмиците, освободени от
// пост. Едно от четирите тела на reference_pager.dart: НЯМА собствен
// Scaffold, лента и drawer — те са на домакина, за да не подскачат при
// плъзгане между секциите. Оттам идват и годината, и размерът на шрифта.
//
// По устройство е близнак на holidays_screen.dart (същото форматиране на
// датите според потребителските предпочитания), но с една съществена
// разлика: тук НИЩО не се чете от календарната база.
//
// Всичко се ИЗЧИСЛЯВА:
//  - подвижните периоди — от Пасха (виж paschalion.dart), с константни
//    отмествания в дни, които не се менят от година на година;
//  - неподвижните — просто се цитират по дата.
// Затова екранът работи за произволна година, включително извън обхвата
// на текущата календарна база.
//
// Слъговете (пояснителните текстове към всеки пост) още не съществуват в
// lives.db. Затова всеки запис носи поле `slug`; щом текстовете бъдат
// добавени, редовете автоматично ще станат разгъващи се, без промяна тук
// освен попълването на имената на слъговете.

import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'database_helper.dart';
import 'dual_date_text.dart';
import 'paschalion.dart';
import 'section_header.dart';
import 'saint_expandable_tile.dart'
    show SaintExpandableTile, SaintLookup, parseHymnCounts;

// Системният шрифт на телефона, не Charis SIL — `null` значи „каквото дава
// устройството". Същото решение както в дневния и месечния изглед: тези
// екрани са СПРАВОЧНИ, четат се на прескок и стоят по-добре с шрифта, с
// който човек чете всичко останало на телефона си.
//
// ⚠ Спира дотук. Хедърът (section_header.dart) си остава с TamburinModern
// за заглавието и годината и с Charis SIL за подканата под тях; четецът, в
// който се отварят самите четива, също не се пипа.
const String? _bodyFamily = null;
const Color _ink = AppColors.textPrimary;
const Color _dim = AppColors.textSecondary;
const Color _headingRed = Color(0xFFBB8C9C);

/// Един запис в списъка. Периодите са два вида:
///  - подвижни: отмествания в дни спрямо Пасха (fromPascha / toPascha);
///  - неподвижни: месец/ден (fixedFrom / fixedTo), цитирани както са.
/// `slug` сочи към пояснителния текст в lives.db — засега null навсякъде.
class _FastSpec {
  final String name;
  final String? slug;
  final int? fromPascha;
  final int? toPascha;
  final (int month, int day)? fixedFrom;
  final (int month, int day)? fixedTo;
  /// Началото пада в ПРЕДХОДНАТА календарна година (Светките започват на
  /// 25 декември по църковен календар, а се отнасят към следващата година).
  final bool startsPrevYear;
  /// Еднодневен пост — показва се като "дата – име", не като период.
  final bool singleDay;

  const _FastSpec({
    required this.name,
    // ignore: unused_element_parameter — попълва се, щом слъговете за
    // поясненията към постовете влязат в lives.db (виж бележката горе).
    this.slug,
    this.fromPascha,
    this.toPascha,
    this.fixedFrom,
    this.fixedTo,
    this.startsPrevYear = false,
    this.singleDay = false,
  });
}

// ─── Многодневни пости ───────────────────────────────────────────────
// Велик пост: 48 дни преди Пасха, до деня преди нея.
// Петров пост: започва в понеделника след Неделя на всички светии
//   (Пасха + 57 дни) и свършва в деня преди Петровден. Дължината му
//   затова е РАЗЛИЧНА всяка година — виж _petrovRange.
// Богородичен и Рождественски: изцяло неподвижни.
const List<_FastSpec> _multiDayFasts = [
  _FastSpec(name: 'Велик пост', fromPascha: -48, toPascha: -1),
  _FastSpec(name: 'Петров пост'), // специален случай — виж _petrovRange
  _FastSpec(name: 'Богородичен пост', fixedFrom: (8, 1), fixedTo: (8, 14)),
  _FastSpec(name: 'Рождественски пост', fixedFrom: (11, 15), fixedTo: (12, 24)),
];

// ─── Еднодневни пости ────────────────────────────────────────────────
const List<_FastSpec> _singleDayFasts = [
  _FastSpec(
      name: 'Навечерие на Богоявление (Йордановден)',
      fixedFrom: (1, 5),
      singleDay: true),
  _FastSpec(
      name: 'Отсичане главата на св. Йоан Предтеча',
      fixedFrom: (8, 29),
      singleDay: true),
  _FastSpec(
      name: 'Въздвижение на Честния и Животворящ Кръст Господен',
      fixedFrom: (9, 14),
      singleDay: true),
];

// ─── Седмици, освободени от пост ─────────────────────────────────────
// Всички без Светките са подвижни и се смятат от Пасха.
const List<_FastSpec> _fastFreeWeeks = [
  _FastSpec(
      name: 'След Рождество Христово',
      fixedFrom: (12, 25),
      fixedTo: (1, 4),
      startsPrevYear: true),
  _FastSpec(name: 'На Митаря и фарисея', fromPascha: -69, toPascha: -63),
  _FastSpec(name: 'Сирна седмица', fromPascha: -55, toPascha: -49),
  _FastSpec(name: 'Пасхална (Светла)', fromPascha: 1, toPascha: 7),
  _FastSpec(name: 'След Петдесетница', fromPascha: 50, toPascha: 56),
];

/// Петровден — 29 юни по църковен календар.
DateTime _petrovden(int year) => civilFromChurch(year, 6, 29);

/// Петровият пост: от понеделника след Неделя на всички светии до деня
/// преди Петровден. При късна Пасха периодът се скъсява и в граничните
/// случаи може да излезе нулев/отрицателен — тогава връщаме null и
/// показваме пояснение вместо дати.
({DateTime start, DateTime end})? _petrovRange(int year) {
  final start = paschaCivil(year).add(const Duration(days: 57));
  final end = _petrovden(year).subtract(const Duration(days: 1));
  if (!end.isAfter(start) && !end.isAtSameMomentAs(start)) return null;
  return (start: start, end: end);
}

class FastsSection extends StatefulWidget {
  final SaintLookup lookup;
  final int year;
  final ValueChanged<int> onYearChanged;
  final double baseFont;

  /// Расте при смяна на настройките (стар/нов стил) — тук датите се
  /// смятат при всяко рисуване, тъй че самото преначертаване стига.
  final int revision;

  const FastsSection({
    super.key,
    required this.lookup,
    required this.year,
    required this.onYearChanged,
    required this.baseFont,
    required this.revision,
  });

  @override
  State<FastsSection> createState() => _FastsSectionState();
}

class _FastsSectionState extends State<FastsSection> {
  // Всички размери са производни от базовия (_fs), за да реагират ВСИЧКИ
  // на бутоните −/+ в лентата на домакина.
  double _fs(double delta) => widget.baseFont + delta;

  int get _selectedYear => widget.year;

  // Флагове дали за даден слъг има текстове — попълва се само за записите
  // със slug (засега няма такива).
  final Map<String, _TextFlags> _flags = {};

  @override
  void initState() {
    super.initState();
    _loadFlags();
  }

  /// Проверява за кои слъгове ИМА текстове в lives.db. Докато слъгове не
  /// са попълнени, това е празна работа и никой ред не се разгъва.
  Future<void> _loadFlags() async {
    final slugs = [
      for (final f in [..._multiDayFasts, ..._singleDayFasts, ..._fastFreeWeeks])
        if (f.slug != null) f.slug!
    ];
    if (slugs.isEmpty) return;
    final db = await DatabaseHelper.database;
    for (final slug in slugs) {
      final rows = await db.rawQuery('''
        SELECT (SELECT group_concat(kind || ':' || n, ',') FROM
                  (SELECT kind, count(*) AS n FROM lives.hymns
                   WHERE slug = t.slug GROUP BY kind)) AS hymn_counts,
               (t.life    IS NOT NULL AND t.life    != '') AS has_life,
               (t.sluzhba IS NOT NULL AND t.sluzhba != '') AS has_sluzhba
        FROM lives.texts t WHERE t.slug = ? LIMIT 1
      ''', [slug]);
      if (rows.isEmpty) continue;
      final r = rows.first;
      _flags[slug] = _TextFlags(
        hymnCounts: parseHymnCounts(r['hymn_counts'] as String?),
        hasLife: (r['has_life'] as int? ?? 0) == 1,
        hasSluzhba: (r['has_sluzhba'] as int? ?? 0) == 1,
      );
    }
    if (mounted) setState(() {});
  }

  DateTime? _resolveFixed((int, int)? md, int year, {bool prevYear = false}) {
    if (md == null) return null;
    return civilFromChurch(prevYear ? year - 1 : year, md.$1, md.$2);
  }

  List<InlineSpan> _dateSpans(DateTime d, double size) => dualDateSpans(
        d,
        size,
        ink: _ink,
        dim: _dim,
        fontFamily: _bodyFamily,
      );

  /// Обвива реда в разгъващия се компонент САМО ако за слъга има текстове.
  Widget _maybeExpandable(_FastSpec spec, Widget row) {
    final flags = spec.slug == null ? null : _flags[spec.slug];
    if (flags == null) return row;
    return SaintExpandableTile(
      collapsedRow: row,
      hymnCounts: flags.hymnCounts,
      hasLife: flags.hasLife,
      hasSluzhba: flags.hasSluzhba,
      lifeLabel: 'Сказание',
      loadTexts: () async => widget.lookup(spec.slug!),
      lookup: widget.lookup,
      arrowSlotWidth: 6,
    );
  }

  Widget _periodRow(_FastSpec spec) {
    final nameStyle =
        TextStyle(fontFamily: _bodyFamily, fontSize: _fs(1), color: _ink, height: 1.35);

    DateTime? start;
    DateTime? end;
    String? note;

    if (spec.name == 'Петров пост') {
      final range = _petrovRange(_selectedYear);
      if (range == null) {
        note = 'няма в тази година — Пасха е по-късна';
      } else {
        start = range.start;
        end = range.end;
      }
    } else if (spec.fromPascha != null) {
      final pascha = paschaCivil(_selectedYear);
      start = pascha.add(Duration(days: spec.fromPascha!));
      end = pascha.add(Duration(days: spec.toPascha!));
    } else {
      start = _resolveFixed(spec.fixedFrom, _selectedYear,
          prevYear: spec.startsPrevYear);
      end = _resolveFixed(spec.fixedTo, _selectedYear);
    }

    // Заглавието на периода на СВОЙ ред, а самият период — на следващия:
    // с двата стила периодът е дълъг и иначе се пренася грозно.
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: _maybeExpandable(
        spec,
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(spec.name, style: nameStyle),
            const SizedBox(height: 2),
            if (note != null)
              Text(
                note,
                style: TextStyle(
                    fontFamily: _bodyFamily,
                    fontSize: _fs(-1),
                    fontStyle: FontStyle.italic,
                    color: _dim),
              )
            else
              Text.rich(
                TextSpan(
                  children: dualDateRangeSpans(start!, end!, _fs(1),
                      ink: _ink, dim: _dim, fontFamily: _bodyFamily),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _singleDayRow(_FastSpec spec) {
    final nameStyle =
        TextStyle(fontFamily: _bodyFamily, fontSize: _fs(1), color: _ink, height: 1.35);
    final date = _resolveFixed(spec.fixedFrom, _selectedYear)!;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: _maybeExpandable(
        spec,
        Text.rich(
          TextSpan(
            children: [
              ..._dateSpans(date, _fs(1)),
              const TextSpan(text: '  –  ', style: TextStyle(color: _dim)),
              TextSpan(text: spec.name, style: nameStyle),
            ],
          ),
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

  Widget _note(String text) => Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 12),
        child: Text(text,
            style: TextStyle(
                fontFamily: _bodyFamily,
                fontSize: _fs(0),
                fontStyle: FontStyle.italic,
                color: _dim,
                height: 1.35)),
      );

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            title: 'Постни дни и периоди',
            background: AppColors.sectionFasts,
            baseFont: widget.baseFont,
            year: _selectedYear,
            onYearChanged: widget.onYearChanged,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 6, 24, 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _h2('Многодневни пости'),
                for (final f in _multiDayFasts) _periodRow(f),
                _h2('Еднодневни пости'),
                for (final f in _singleDayFasts) _singleDayRow(f),
                _note('Сряда и петък през цялата година, с изключение на '
                    'седмиците, освободени от пост.'),
                _h2('Седмици, освободени от пост'),
                for (final f in _fastFreeWeeks) _periodRow(f),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TextFlags {
  final Map<String, int> hymnCounts;
  final bool hasLife;
  final bool hasSluzhba;
  const _TextFlags({
    this.hymnCounts = const {},
    required this.hasLife,
    required this.hasSluzhba,
  });
}
