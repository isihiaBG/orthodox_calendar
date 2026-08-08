// fasts_screen.dart
//
// "Пости" — многодневните пости, еднодневните и седмиците, освободени от
// пост. По устройство е близнак на holidays_screen.dart (същата лента с
// инструменти, същото форматиране на датите според потребителските
// предпочитания), но с една съществена разлика: тук НИЩО не се чете от
// календарната база.
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

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_drawer.dart';
import 'app_theme.dart';
import 'database_helper.dart';
import 'dual_date_text.dart';
import 'paschalion.dart';
import 'round_icon_button.dart';
import 'year_selector.dart';
import 'saint_expandable_tile.dart'
    show SaintExpandableTile, SaintLookup;
import 'settings_screen.dart';

const String _titleFamily = 'TamburinModern';
const String _bodyFamily = 'Cambria';
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
// Успенски и Рождественски: изцяло неподвижни.
const List<_FastSpec> _multiDayFasts = [
  _FastSpec(name: 'Велик пост', fromPascha: -48, toPascha: -1),
  _FastSpec(name: 'Петров пост'), // специален случай — виж _petrovRange
  _FastSpec(name: 'Успенски пост', fixedFrom: (8, 1), fixedTo: (8, 14)),
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

class FastsScreen extends StatefulWidget {
  final SaintLookup lookup;
  const FastsScreen({super.key, required this.lookup});

  @override
  State<FastsScreen> createState() => _FastsScreenState();
}

class _FastsScreenState extends State<FastsScreen> {
  // Базов размер на шрифта — всички размери са производни от него (_fs),
  // за да реагират ВСИЧКИ на бутоните −/+ (виж holidays_screen.dart).
  static double _baseFont = 17.0;
  static const double _fontStep = 1.0;
  static const double _fontMin = 13.0;
  static const double _fontMax = 26.0;
  static const String _fontKey = 'fasts_font_size';
  static bool _fontLoadedFromDisk = false;
  static double? _lastSavedFont;
  Timer? _fontSaveTimer;

  double _fs(double delta) => _baseFont + delta;

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  late int _selectedYear;
  // Флагове дали за даден слъг има текстове — попълва се само за записите
  // със slug (засега няма такива).
  final Map<String, _TextFlags> _flags = {};

  @override
  void initState() {
    super.initState();
    final now = DateTime.now().year;
    _selectedYear = now;
    _loadPersistedFontOnce().then((_) {
      if (mounted) setState(() {});
    });
    _loadFlags();
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
    setState(() => _baseFont = (_baseFont + delta).clamp(_fontMin, _fontMax));
    _scheduleFontSave();
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
        SELECT (tropar  IS NOT NULL AND tropar  != '') AS has_tropar,
               (kondak  IS NOT NULL AND kondak  != '') AS has_kondak,
               (life    IS NOT NULL AND life    != '') AS has_life,
               (sluzhba IS NOT NULL AND sluzhba != '') AS has_sluzhba
        FROM lives.texts WHERE slug = ? LIMIT 1
      ''', [slug]);
      if (rows.isEmpty) continue;
      final r = rows.first;
      _flags[slug] = _TextFlags(
        hasTropar: (r['has_tropar'] as int? ?? 0) == 1,
        hasKondak: (r['has_kondak'] as int? ?? 0) == 1,
        hasLife: (r['has_life'] as int? ?? 0) == 1,
        hasSluzhba: (r['has_sluzhba'] as int? ?? 0) == 1,
      );
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    if (_fontSaveTimer != null) {
      _fontSaveTimer!.cancel();
      _flushFontSave();
    }
    super.dispose();
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
      hasTropar: flags.hasTropar,
      hasKondak: flags.hasKondak,
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
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: AppColors.toolbar,
      drawer: const AppDrawer(),
      onEndDrawerChanged: (isOpen) {
        if (!isOpen) setState(() {});
      },
      endDrawer: SettingsDrawer(onChanged: (styleChanged, [capturedMiddleDate]) {
        appSettingsChangedHook?.call(styleChanged, capturedMiddleDate);
        if (mounted) setState(() {}); // датите зависят от стила
      }),
      appBar: AppBar(
        backgroundColor: AppColors.toolbar,
        toolbarHeight: 44,
        title: const Text('Пости'),
        actions: [
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
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 6, 24, 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Постни дни и периоди',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontFamily: _titleFamily,
                      fontSize: _fs(23),
                      height: 1.25,
                      color: _ink),
                ),
                const SizedBox(height: 15),
                Text(
                  'изберете година',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontFamily: _bodyFamily,
                      fontSize: _fs(2),
                      fontStyle: FontStyle.italic,
                      color: _dim),
                ),
                Center(
                  child: YearSelector(
                    value: _selectedYear,
                    onChanged: (y) => setState(() => _selectedYear = y),
                    fontSize: _fs(23),
                    fontFamily: _titleFamily,
                    color: _ink,
                  ),
                ),
                const SizedBox(height: 12),
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
        ),
      ),
    );
  }
}

class _TextFlags {
  final bool hasTropar;
  final bool hasKondak;
  final bool hasLife;
  final bool hasSluzhba;
  const _TextFlags({
    required this.hasTropar,
    required this.hasKondak,
    required this.hasLife,
    required this.hasSluzhba,
  });
}
