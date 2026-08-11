// holidays_screen.dart
//
// "Църковни празници" — дванадесетте велики празника (подвижни и
// неподвижни) и другите големи (неподвижни) празници. Структурата
// (заглавия, категории, ред) е фиксирана в кода; ДАТИТЕ се вземат
// динамично от текущо избраната календарна база (calendar_old.db /
// calendar_new.db — вижте DatabaseHelper), за избраната година.
//
// Едно от четирите тела на reference_pager.dart: НЯМА собствен Scaffold,
// лента и drawer — те са на домакина. Годината и размерът на шрифта също
// идват отвън, за да са общи за четирите секции.

import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'database_helper.dart';
import 'dual_date_text.dart';
import 'paschalion.dart';
import 'section_header.dart';
import 'saint_expandable_tile.dart'
    show SaintExpandableTile, SaintLookup, SaintTexts, lifeLabelFor;

const String _bodyFamily = 'Cambria';
const Color _ink = AppColors.textPrimary;
const Color _dim = AppColors.textSecondary;
// Заглавията на категориите (h2/h3) — червени, за разлика от основното
// заглавие и годината (те си остават в основния мастилен цвят). Същият
// винен нюанс, ползван и в about_screen.dart за буквицата.
const Color _headingRed = Color(0xFFBB8C9C); //0xFFA0555B);

enum _FeastCategory { pascha, movable12, fixed12, otherGreat }

/// Едно празненство. ДАТАТА се изчислява (не се чете от базата):
///  - подвижните — отместване в дни спрямо Пасха (fromPascha);
///  - неподвижните — църковна (юлианска) дата (church), преобразувана към
///    гражданска според режима (виж civilFromChurch).
///
/// В базата се търси САМО слъгът/текстовете, и то по ИМЕ, без дата — така
/// екранът работи за всяка година, включително извън обхвата на базата.
/// Търсенето е по НАЧАЛОТО на името (prefix), защото предпразненствата и
/// попразненствата съдържат пълното име на празника в себе си и иначе
/// биха се хващали вместо самия празник.
class _FeastSpec {
  final String namePrefix;
  final String displayName;
  final _FeastCategory category;
  final int? fromPascha;
  final (int month, int day)? church;
  const _FeastSpec(
    this.namePrefix,
    this.displayName,
    this.category, {
    this.fromPascha,
    this.church,
  });
}

const List<_FeastSpec> _feasts = [
  // --- Пасха — отделно, НАД дванадесетте ---
  _FeastSpec('СВЕТЛО ХРИСТОВО ВЪЗКРЕСЕНИЕ', 'ВЕЛИКДЕН — ПАСХА ХРИСТОВА',
      _FeastCategory.pascha, fromPascha: 0),

  // --- Дванадесетте: неподвижни, по хронологията на църковната година
  // (започва от 1 септември) ---
  _FeastSpec('РОЖДЕСТВО НА ПРЕСВЕТА БОГОРОДИЦА',
      'Рождество на Пресвета Богородица (Малка Богородица)',
      _FeastCategory.fixed12, church: (9, 8)),
  _FeastSpec('ВЪЗДВИЖЕНИЕ НА ЧЕСТНИЯ',
      'Въздвижение на Светия Кръст Господен (Кръстовден)',
      _FeastCategory.fixed12, church: (9, 14)),
  _FeastSpec('ВЪВЕДЕНИЕ БОГОРОДИЧНО',
      'Въведение Богородично (Ден на християнското семейство)',
      _FeastCategory.fixed12, church: (11, 21)),
  _FeastSpec('РОЖДЕСТВО ХРИСТОВО', 'Рождество Христово',
      _FeastCategory.fixed12, church: (12, 25)),
  _FeastSpec('БОГОЯВЛЕНИЕ', 'Богоявление (Йордановден)',
      _FeastCategory.fixed12, church: (1, 6)),
  _FeastSpec('СРЕТЕНИЕ НА ГОСПОДА', 'Сретение Господне',
      _FeastCategory.fixed12, church: (2, 2)),
  _FeastSpec('БЛАГОВЕЩЕНИЕ НА ПРЕСВЕТА', 'Благовещение',
      _FeastCategory.fixed12, church: (3, 25)),
  _FeastSpec('ПРЕОБРАЖЕНИЕ ГОСПОДНЕ', 'Преображение Господне',
      _FeastCategory.fixed12, church: (8, 6)),
  _FeastSpec('УСПЕНИЕ НА ПРЕСВЕТА',
      'Успение на Пресвета Богородица (Голяма Богородица)',
      _FeastCategory.fixed12, church: (8, 15)),

  // --- Дванадесетте: от тях подвижни (спрямо Пасха) ---
  _FeastSpec('ВХОД ГОСПОДЕН', 'Вход Господен в Йерусалим (Връбница / Цветница)',
      _FeastCategory.movable12, fromPascha: -7),
  _FeastSpec('ВЪЗНЕСЕНИЕ ГОСПОДНЕ', 'Възнесение Господне (Спасовден)',
      _FeastCategory.movable12, fromPascha: 39),
  _FeastSpec('ДЕН НА СВЕТА ТРОИЦА', 'Петдесетница - Ден на Светата Троица',
      _FeastCategory.movable12, fromPascha: 49),

  // --- Други големи празници (неподвижни) ---
  _FeastSpec('ОБРЕЗАНИЕ ГОСПОДНЕ', 'Обрезание Господне',
      _FeastCategory.otherGreat, church: (1, 1)),
  _FeastSpec('Рождество на св. Йоан Предтеча',
      'Рождество на св. Йоан Предтеча (Еньовден)',
      _FeastCategory.otherGreat, church: (6, 24)),
  _FeastSpec('Свв. славни и всехвални', 'Петровден - Свв. апп. Петър и Павел',
      _FeastCategory.otherGreat, church: (6, 29)),
  _FeastSpec('Отсичане честната глава',
      'Отсичане главата на св. Йоан Предтеча',
      _FeastCategory.otherGreat, church: (8, 29)),
  _FeastSpec('Покров на Пресвета', 'Покров на Пресвета Богородица',
      _FeastCategory.otherGreat, church: (10, 1)),
];

class _FeastResult {
  final _FeastSpec spec;
  final DateTime civilDate; // датата от базата (номерация по нов стил)
  final int? id;
  final String? slug;
  final int rank;
  final bool hasTropar;
  final bool hasKondak;
  final bool hasLife;
  final bool hasSluzhba;
  const _FeastResult(
    this.spec,
    this.civilDate, {
    this.id,
    this.slug,
    required this.rank,
    this.hasTropar = false,
    this.hasKondak = false,
    this.hasLife = false,
    this.hasSluzhba = false,
  });
}

class HolidaysSection extends StatefulWidget {
  final SaintLookup lookup;
  final int year;
  final ValueChanged<int> onYearChanged;
  final double baseFont;

  /// Расте при смяна на настройките (стар/нов стил). Тук датите са
  /// ИЗЧИСЛЕНИ ВЕДНЪЖ и кеширани в _results, тъй че само преначертаване
  /// не стига — при промяна се преизчислява целият списък.
  final int revision;

  const HolidaysSection({
    super.key,
    required this.lookup,
    required this.year,
    required this.onYearChanged,
    required this.baseFont,
    required this.revision,
  });

  @override
  State<HolidaysSection> createState() => _HolidaysSectionState();
}

class _HolidaysSectionState extends State<HolidaysSection> {
  /// Размер спрямо базовия — единственият начин за задаване на шрифт тук.
  double _fs(double delta) => widget.baseFont + delta;

  List<_FeastResult>? _results;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    // Годините вече НЕ зависят от обхвата на базата — датите се смятат
    // (виж _loadYearInner), а изборът е решетка (виж year_selector.dart).
    _loadYear(widget.year);
  }

  @override
  void didUpdateWidget(covariant HolidaysSection old) {
    super.didUpdateWidget(old);
    // Смяна на годината ИЛИ на стила — и в двата случая кешираните дати
    // вече не важат.
    if (old.year != widget.year || old.revision != widget.revision) {
      _loadYear(widget.year);
    }
  }

  Future<void> _loadYear(int year) async {
    if (mounted) setState(() => _loading = true);
    try {
      await _loadYearInner(year);
    } catch (e) {
      // Без този catch една провалена заявка оставяше _loading = true
      // завинаги — екранът висеше на въртящ се спинър, без никакъв знак
      // какво е станало.
      debugPrint('[holidays] грешка при зареждане на година $year: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadYearInner(int year) async {
    final db = await DatabaseHelper.database;
    final pascha = paschaCivil(year);
    final results = <_FeastResult>[];
    for (final spec in _feasts) {
      // ДАТАТА се смята, не се чете: подвижните — от Пасха, неподвижните —
      // от църковната си дата (виж civilFromChurch). Затова екранът работи
      // и за години извън обхвата на базата.
      final DateTime civilDate = spec.fromPascha != null
          ? pascha.add(Duration(days: spec.fromPascha!))
          : civilFromChurch(year, spec.church!.$1, spec.church!.$2);

      // От базата взимаме САМО слъга и флаговете за текстовете — по ИМЕ,
      // без дата (те не зависят от годината). Търсенето е по НАЧАЛОТО на
      // името, за да не хване предпразненство/попразненство, чиито имена
      // съдържат пълното име на празника.
      final rows = await db.rawQuery("""
        SELECT s.id, s.rank, s.slug,
              (l.tropar  IS NOT NULL AND l.tropar  != '') AS has_tropar,
              (l.kondak  IS NOT NULL AND l.kondak  != '') AS has_kondak,
              (l.life    IS NOT NULL AND l.life    != '') AS has_life,
              (l.sluzhba IS NOT NULL AND l.sluzhba != '') AS has_sluzhba
        FROM saints s
        LEFT JOIN lives.texts l ON l.slug = s.slug
        WHERE s.name LIKE ?
        LIMIT 1
      """, ['${spec.namePrefix}%']);

      final row = rows.isEmpty ? null : rows.first;
      results.add(_FeastResult(
        spec,
        civilDate,
        id: row?['id'] as int?,
        slug: row?['slug'] as String?,
        rank: row?['rank'] as int? ?? 6,
        hasTropar: (row?['has_tropar'] as int? ?? 0) == 1,
        hasKondak: (row?['has_kondak'] as int? ?? 0) == 1,
        hasLife: (row?['has_life'] as int? ?? 0) == 1,
        hasSluzhba: (row?['has_sluzhba'] as int? ?? 0) == 1,
      ));
    }
    if (!mounted) return;
    setState(() {
      _results = results;
      _loading = false;
    });
  }

  List<_FeastResult> _byCategory(_FeastCategory c) =>
      (_results ?? const []).where((r) => r.spec.category == c).toList();

  /// Пълните текстове на ЕДИН конкретен календарен ред (по id) — същата
  /// заявка, ползвана от дневния изглед (main.dart._loadSaintTexts).
  Future<SaintTexts?> _loadTextsById(int? id) async {
    if (id == null) return null;
    final db = await DatabaseHelper.database;
    final r = await db.rawQuery('''
      SELECT COALESCE(NULLIF(s.name, ''), l.name) AS name,
             l.tropar, l.tropar_trans, l.tropar2, l.tropar2_trans,
             l.kondak, l.kondak_trans, l.kondak2, l.kondak2_trans,
             l.life, l.sluzhba, l.source, s.slug
      FROM saints s
      LEFT JOIN lives.texts l ON l.slug = s.slug
      WHERE s.id = ?
      LIMIT 1
    ''', [id]);
    if (r.isEmpty) return null;
    return SaintTexts.fromMap(r.first);
  }

  Widget _expandableWrap(_FeastResult r, Widget collapsedRow) {
    return SaintExpandableTile(
      collapsedRow: collapsedRow,
      hasTropar: r.hasTropar,
      hasKondak: r.hasKondak,
      hasLife: r.hasLife,
      hasSluzhba: r.hasSluzhba,
      lifeLabel: lifeLabelFor(rank: r.rank, name: r.spec.displayName),
      // По id на КОНКРЕТНИЯ ред, не по slug: предпразненство/попразненство
      // споделят slug-а на самия празник, така че търсене по slug връща
      // произволен от тях (наблюдавано: "Предпразненство на Въздвижение"
      // вместо самия празник). id-то се чете живо при всяко отваряне на
      // екрана и никъде не се запазва, затова е безопасно спрямо бъдещи
      // промени в базата.
      loadTexts: () => _loadTextsById(r.id),
      lookup: widget.lookup,
      // По-тесен слот за стрелката — редовете тук са по-дълги (дата + име)
      // и при естествената ѝ широчина често се пренасяха на трети ред.
      arrowSlotWidth: 6,
    );
  }

  Widget _feastRow(_FeastResult r) {
    final nameStyle = TextStyle(fontFamily: _bodyFamily, fontSize: _fs(1), color: _ink, height: 1.35);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: _expandableWrap(
        r,
        Text.rich(
          TextSpan(
            children: [
              ...dualDateSpans(r.civilDate, _fs(1), ink: _ink, dim: _dim, fontFamily: _bodyFamily),
              const TextSpan(text: '  –  ', style: TextStyle(color: _dim)),
              TextSpan(text: r.spec.displayName, style: nameStyle),
            ],
          ),
        ),
      ),
    );
  }

  /// Редът на Пасха — визуално отделен от останалите: центрирано, червено,
  /// bold заглавие, а под него центрирана дата в обичайните цветове/формат.
  Widget _paschaRow(_FeastResult r) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: _expandableWrap(
        r,
        Column(
          children: [
            Text(
              r.spec.displayName,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontFamily: _bodyFamily,
                  fontSize: _fs(2),
                  fontWeight: FontWeight.bold,
                  color: _headingRed),
            ),
            const SizedBox(height: 6),
            Text.rich(
              TextSpan(children: dualDateSpans(r.civilDate, _fs(3), ink: _ink, dim: _dim, fontFamily: _bodyFamily)),
              textAlign: TextAlign.center,
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

  /// Пояснение под заглавие — сиво (не червено), курсив.
  Widget _hint(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(text,
            style: TextStyle(
                fontFamily: _bodyFamily,
                fontSize: _fs(0),
                fontStyle: FontStyle.italic,
                color: _dim)),
      );

  Widget _h3(String text) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 8),
        child: Text(text,
            style: TextStyle(
                fontFamily: _bodyFamily,
                fontSize: _fs(2),
                fontWeight: FontWeight.bold,
                color: _headingRed)),
      );

  @override
  Widget build(BuildContext context) {
    // Хедърът стои над спинъра — при смяна на годината заглавието и
    // самата година не бива да изчезват, докато датите се преизчисляват.
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            title: 'Църковни празници',
            background: AppColors.sectionHolidays,
            baseFont: widget.baseFont,
            year: widget.year,
            onYearChanged: widget.onYearChanged,
          ),
          if (_loading)
            const Padding(
              padding: EdgeInsets.only(top: 40),
              child: Center(child: CircularProgressIndicator()),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 6, 24, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final r in _byCategory(_FeastCategory.pascha)) _paschaRow(r),
                  _h2('Дванадесетте Господски и Богородични празници'),
                  _hint('(по хронология на църковната година, която започва от 1-ви септември)'),
                  _h3(' - неподвижни (постоянни дати)'),
                  for (final r in _byCategory(_FeastCategory.fixed12)) _feastRow(r),
                  _h3(' - подвижни (променливи дати)'),
                  for (final r in _byCategory(_FeastCategory.movable12)) _feastRow(r),
                  _h2('Други големи празници (неподвижни):'),
                  for (final r in _byCategory(_FeastCategory.otherGreat)) _feastRow(r),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
