// holidays_screen.dart
//
// "Църковни празници" — дванадесетте велики празника (подвижни и
// неподвижни) и другите големи (неподвижни) празници. Структурата
// (заглавия, категории, ред) е фиксирана в кода; ДАТИТЕ се вземат
// динамично от текущо избраната календарна база (calendar_old.db /
// calendar_new.db — вижте DatabaseHelper), за избраната година.

import 'dart:async';

import 'package:flutter/material.dart';

import 'app_drawer.dart';
import 'app_theme.dart';
import 'database_helper.dart';
import 'dual_date_text.dart';
import 'paschalion.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'settings_screen.dart';
import 'round_icon_button.dart';
import 'year_selector.dart';
import 'saint_expandable_tile.dart'
    show SaintExpandableTile, SaintLookup, SaintTexts, lifeLabelFor;

const String _titleFamily = 'TamburinModern';
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

class HolidaysScreen extends StatefulWidget {
  final SaintLookup lookup;
  const HolidaysScreen({super.key, required this.lookup});

  @override
  State<HolidaysScreen> createState() => _HolidaysScreenState();
}

class _HolidaysScreenState extends State<HolidaysScreen> {
  // БАЗОВ размер на шрифта — всички размери в екрана са производни от
  // него (виж _fs), за да реагират ВСИЧКИ на бутоните -/+ ; никъде не
  // бива да остава фиксирана стойност, иначе тя няма да се променя.
  // static: пази се за сесията; на диска се записва с debounce (виж
  // _scheduleFontSizeSave), както в четеца.
  static double _baseFont = 17.0;
  static const double _fontStep = 1.0;
  static const double _fontMin = 13.0;
  static const double _fontMax = 26.0;
  static const String _fontKey = 'holidays_font_size';
  static bool _fontLoadedFromDisk = false;
  static double? _lastSavedFont;
  Timer? _fontSaveTimer;

  /// Размер спрямо базовия — единственият начин за задаване на шрифт тук.
  double _fs(double delta) => _baseFont + delta;

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  int? _selectedYear;
  List<_FeastResult>? _results;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadPersistedFontOnce().then((_) {
      if (mounted) setState(() {});
    });
    _init();
  }

  static Future<void> _loadPersistedFontOnce() async {
    if (_fontLoadedFromDisk) return;
    _fontLoadedFromDisk = true;
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getDouble(_fontKey);
    if (saved != null) {
      _baseFont = saved.clamp(_fontMin, _fontMax);
      _lastSavedFont = _baseFont;
    }
  }

  /// Записът чака 3 сек. покой (потребителят обикновено цъка няколко пъти,
  /// докато намери размера) и се случва само при реална промяна.
  void _scheduleFontSave() {
    _fontSaveTimer?.cancel();
    _fontSaveTimer = Timer(const Duration(seconds: 3), _flushFontSave);
  }

  void _flushFontSave() {
    _fontSaveTimer = null;
    if (_lastSavedFont == _baseFont) return;
    _lastSavedFont = _baseFont;
    SharedPreferences.getInstance()
        .then((prefs) => prefs.setDouble(_fontKey, _baseFont));
  }

  void _bumpFont(double delta) {
    setState(() {
      _baseFont = (_baseFont + delta).clamp(_fontMin, _fontMax);
    });
    _scheduleFontSave();
  }

  @override
  void dispose() {
    // Недовършил своите 3 секунди запис — пускаме го веднага, иначе
    // промяната би се загубила при излизане от екрана.
    if (_fontSaveTimer != null) {
      _fontSaveTimer!.cancel();
      _flushFontSave();
    }
    super.dispose();
  }

  Future<void> _init() async {
    // Годините вече НЕ зависят от обхвата на базата — датите се смятат
    // (виж _loadYearInner), а изборът е решетка (виж year_selector.dart).
    await _loadYear(DateTime.now().year);
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
      _selectedYear = year;
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
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: AppColors.toolbar,
      // Меню вместо стрелка "назад" — виж коментара в about_screen.dart.
      drawer: const AppDrawer(),
      // Настройките — 1:1 както в дневния изглед (виж main.dart): същият
      // endDrawer, същият бутон. onEndDrawerChanged + hook-ът правят
      // промените видими ЖИВО зад отворения drawer.
      onEndDrawerChanged: (isOpen) {
        // При затваряне също преизчисляваме — стилът може да е сменен, а
        // датите тук са кеширани (виж бележката при endDrawer).
        if (!isOpen && mounted) _loadYear(_selectedYear ?? DateTime.now().year);
      },
      endDrawer: SettingsDrawer(onChanged: (styleChanged) {
        appSettingsChangedHook?.call(styleChanged);
        // ВАЖНО: тук датите са ИЗЧИСЛЕНИ ВЕДНЪЖ и кеширани в _results, за
        // разлика от "Пости", където се смятат при всяко рисуване. Затова
        // при смяна на стила не стига преначертаване — трябва пълно
        // преизчисляване, иначе остават стойности от предишния режим.
        if (mounted) _loadYear(_selectedYear ?? DateTime.now().year);
      }),
      appBar: AppBar(
        backgroundColor: AppColors.toolbar,
        toolbarHeight: 44,
        title: const Text('Празници'),
        actions: [
          // Същите бутони като в четеца — общият RoundIconButton, същият
          // размер и разстояние помежду им (виж reader_screen.dart).
          RoundIconButton(
            icon: Icons.remove,
            tooltip: 'По-дребен шрифт',
            enabled: _baseFont > _fontMin,
            onTap: () => _bumpFont(-_fontStep),
            size: 22,
          ),
          const SizedBox(width: 18),
          RoundIconButton(
            icon: Icons.add,
            tooltip: 'По-едър шрифт',
            enabled: _baseFont < _fontMax,
            onTap: () => _bumpFont(_fontStep),
            size: 22,
          ),
          const SizedBox(width: 14),
          // ================ Настройки =================
          IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            icon: const Icon(Icons.settings, color: AppColors.textPrimary, size: 24),
            onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Container(
          color: AppColors.background,
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 6, 24, 40),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Църковни празници',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontFamily: _titleFamily,
                            fontSize: _fs(23),
                            height: 1.25,
                            color: _ink),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'изберете година',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontFamily: _bodyFamily,
                            fontSize: _fs(2),
                            fontStyle: FontStyle.italic,
                            color: _dim),
                      ),
                      //const SizedBox(height: 0),
                      Center(
                        child: YearSelector(
                          value: _selectedYear ?? DateTime.now().year,
                          onChanged: _loadYear,
                          fontSize: _fs(23),
                          fontFamily: _titleFamily,
                          color: _ink,
                        ),
                      ),
                      const SizedBox(height: 12),
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
        ),
      ),
    );
  }
}
