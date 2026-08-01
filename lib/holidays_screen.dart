// holidays_screen.dart
//
// "Църковни празници" — дванадесетте велики празника (подвижни и
// неподвижни) и другите големи (неподвижни) празници. Структурата
// (заглавия, категории, ред) е фиксирана в кода; ДАТИТЕ се вземат
// динамично от текущо избраната календарна база (calendar_old.db /
// calendar_new.db — вижте DatabaseHelper), за избраната година.

import 'package:flutter/material.dart';

import 'app_settings.dart';
import 'app_theme.dart';
import 'database_helper.dart';

const String _titleFamily = 'TamburinModern';
const String _bodyFamily = 'Cambria';
const Color _ink = AppColors.textPrimary;
const Color _dim = AppColors.textSecondary;
// Заглавията на категориите (h2/h3) — червени, за разлика от основното
// заглавие и годината (те си остават в основния мастилен цвят). Същият
// винен нюанс, ползван и в about_screen.dart за буквицата.
const Color _headingRed = Color(0xFFBB8C9C); //0xFFA0555B);

// Съвпада с month_screen.dart._monthNamesShort — за консистентност на
// съкратените имена на месеците в цялото приложение.
const List<String> _monthAbbr = [
  '', 'яну', 'фев', 'мар', 'апр', 'май', 'юни',
  'юли', 'авг', 'сеп', 'окт', 'ное', 'дек'
];

String _fmtDate(DateTime d) => '${d.day.toString().padLeft(2, '0')}.${_monthAbbr[d.month]}';

enum _FeastCategory { pascha, movable12, fixed12, otherGreat }

/// Едно търсено празненство: `pattern` е УНИКАЛНА разпознаваема част от
/// името в базата (валидирано ръчно спрямо реалните данни — виж чат
/// историята), `requireRank1` добавя допълнителен филтър rank=1 само
/// където е нужно, за да се различи главното празненство от
/// предпразненство/попразненство записи със сходни имена.
class _FeastSpec {
  final String pattern;
  final bool requireRank1;
  final String displayName;
  final _FeastCategory category;
  const _FeastSpec(this.pattern, this.requireRank1, this.displayName, this.category);
}

const List<_FeastSpec> _feasts = [
  // --- Пасха — отделно, НАД дванадесетте (реално са 13, ако се брои с нея) ---
  _FeastSpec('ВЕЛИКДЕН', true, 'ВЕЛИКДЕН — ПАСХА ХРИСТОВА', _FeastCategory.pascha),

  // --- Дванадесетте: неподвижни, по хронологията на църковната година
  // (започва от 1 септември) ---
  _FeastSpec('РОЖДЕСТВО НА ПРЕСВЕТА БОГОРОДИЦА', true, 'Рождество на Пресвета Богородица (Малка Богородица)', _FeastCategory.fixed12),
  _FeastSpec('ВЪЗДВИЖЕНИЕ НА ЧЕСТНИЯ', true, 'Въздвижение на Светия Кръст Господен (Кръстовден)', _FeastCategory.fixed12),
  _FeastSpec('ВЪВЕДЕНИЕ БОГОРОДИЧНО', true, 'Въведение Богородично (Ден на християнското семейство)', _FeastCategory.fixed12),
  _FeastSpec('РОЖДЕСТВО ХРИСТОВО', true, 'Рождество Христово (Коледа)', _FeastCategory.fixed12),
  _FeastSpec('БОГОЯВЛЕНИЕ', true, 'Богоявление (Йордановден)', _FeastCategory.fixed12),
  _FeastSpec('СРЕТЕНИЕ НА ГОСПОДА', true, 'Сретение Господне', _FeastCategory.fixed12),
  _FeastSpec('БЛАГОВЕЩЕНИЕ НА ПРЕСВЕТА', true, 'Благовещение', _FeastCategory.fixed12),
  _FeastSpec('ПРЕОБРАЖЕНИЕ ГОСПОДНЕ', true, 'Преображение Господне', _FeastCategory.fixed12),
  _FeastSpec('УСПЕНИЕ НА ПРЕСВЕТА', false, 'Успение на Пресвета Богородица (Голяма Богородица)', _FeastCategory.fixed12),

  // --- Дванадесетте: от тях подвижни (спрямо Пасха, хронологичен ред) ---
  _FeastSpec('ВХОД ГОСПОДЕН', false, 'Вход Господен в Йерусалим (Връбница / Цветница)', _FeastCategory.movable12),
  _FeastSpec('ВЪЗНЕСЕНИЕ ГОСПОДНЕ', true, 'Възнесение Господне (Спасовден)', _FeastCategory.movable12),
  _FeastSpec('ПЕТДЕСЕТНИЦА', true, 'Петдесетница - Ден на Светата Троица', _FeastCategory.movable12),

  // --- Други големи празници (неподвижни) ---
  _FeastSpec('ОБРЕЗАНИЕ ГОСПОДНЕ', false, 'Обрезание Господне', _FeastCategory.otherGreat),
  _FeastSpec('Рождество на св. Йоан Предтеча', false, 'Рождество на св. Йоан Предтеча (Еньовден)', _FeastCategory.otherGreat),
  _FeastSpec('Петър и Павел', false, 'Петровден - Свв. апп. Петър и Павел', _FeastCategory.otherGreat),
  _FeastSpec('Отсичане честната глава', false, 'Отсичане главата на св. Йоан Предтеча', _FeastCategory.otherGreat),
  _FeastSpec('Покров на Пресвета', false, 'Покров на Пресвета Богородица', _FeastCategory.otherGreat),
];

class _FeastResult {
  final _FeastSpec spec;
  final DateTime civilDate; // датата от базата (номерация по нов стил)
  const _FeastResult(this.spec, this.civilDate);
}

class HolidaysScreen extends StatefulWidget {
  const HolidaysScreen({super.key});

  @override
  State<HolidaysScreen> createState() => _HolidaysScreenState();
}

class _HolidaysScreenState extends State<HolidaysScreen> {
  List<int> _availableYears = const [];
  int? _selectedYear;
  List<_FeastResult>? _results;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    // Изчаква базата да се отвори (нужно е за DatabaseHelper.dataMinDate).
    await DatabaseHelper.database;
    // "Църковната" година в бандъла започва ок. 14 януари и продължава до
    // 13 януари следващата — виж DatabaseHelper.dataMinDate/dataMaxDate.
    // Годината в падащото меню е именувана по НАЧАЛНАТА календарна година
    // на този диапазон. В момента базата съдържа само ЕДНА такава година;
    // ако занапред се разшири с повече, списъкът автоматично ще ги поеме.
    final minDate = DatabaseHelper.dataMinDate;
    final year = minDate?.year ?? DateTime.now().year;
    _availableYears = [year];
    await _loadYear(year);
  }

  Future<void> _loadYear(int year) async {
    if (mounted) setState(() => _loading = true);
    final db = await DatabaseHelper.database;
    final startDate = '$year-01-14';
    final endDate = '${year + 1}-01-13';
    final results = <_FeastResult>[];
    for (final spec in _feasts) {
      final rows = await db.rawQuery(
        'SELECT date FROM saints WHERE date BETWEEN ? AND ? AND name LIKE ?'
        '${spec.requireRank1 ? ' AND rank = 1' : ''} LIMIT 1',
        [startDate, endDate, '%${spec.pattern}%'],
      );
      if (rows.isEmpty) continue;
      final dateStr = rows.first['date'] as String;
      results.add(_FeastResult(
        spec,
        DateTime.utc(
          int.parse(dateStr.substring(0, 4)),
          int.parse(dateStr.substring(5, 7)),
          int.parse(dateStr.substring(8, 10)),
        ),
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

  /// Форматираната дата на един ред — единична (чист нов стил) или двойна
  /// (стар/нов, с иконки църква/телевизор — виж месечния изглед за същата
  /// конвенция). Водещата част е в основния цвят, справочната (заедно с
  /// разделителя "/") — по-бледа. Иконките са НАРОЧНО малко по-големи от
  /// текста, за да не изглеждат дребни/незабележими до него.
  List<InlineSpan> _dateSpans(DateTime civilDate, double fontSize) {
    final iconSize = fontSize + 6;
    final leadStyle = TextStyle(
        color: _ink, fontFamily: _bodyFamily, fontSize: fontSize, fontWeight: FontWeight.w600);
    final dimStyle = TextStyle(
        color: _dim, fontFamily: _bodyFamily, fontSize: fontSize, fontWeight: FontWeight.w600);

    if (!AppSettings.isOldStyle) {
      return [TextSpan(text: _fmtDate(civilDate), style: leadStyle)];
    }

    final oldStyleDate = civilDate.subtract(const Duration(days: 13));
    final oldIsLeading = !AppSettings.oldStyleFirst;

    WidgetSpan iconSpan(IconData icon, Color color) => WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Padding(
            padding: const EdgeInsets.only(right: 2),
            // Леко повдигане (2-3px) — само визуално подравняване спрямо
            // текста, не мести нищо друго около себе си.
            child: Transform.translate(
              offset: const Offset(0, -3),
              child: Icon(icon, size: iconSize, color: color),
            ),
          ),
        );

    if (oldIsLeading) {
      return [
        iconSpan(Icons.church, _ink),
        TextSpan(text: _fmtDate(oldStyleDate), style: leadStyle),
        TextSpan(text: '  /  ', style: dimStyle),
        iconSpan(Icons.live_tv, _dim),
        TextSpan(text: _fmtDate(civilDate), style: dimStyle),
      ];
    }
    return [
      TextSpan(text: _fmtDate(civilDate), style: leadStyle),
      TextSpan(text: '  /  ', style: dimStyle),
      iconSpan(Icons.church, _dim),
      TextSpan(text: _fmtDate(oldStyleDate), style: dimStyle),
    ];
  }

  Widget _feastRow(_FeastResult r) {
    const nameStyle = TextStyle(fontFamily: _bodyFamily, fontSize: 17, color: _ink, height: 1.35);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text.rich(
        TextSpan(
          children: [
            ..._dateSpans(r.civilDate, 17),
            const TextSpan(text: '  –  ', style: TextStyle(color: _dim)),
            TextSpan(text: r.spec.displayName, style: nameStyle),
          ],
        ),
      ),
    );
  }

  /// Редът на Пасха — визуално отделен от останалите: центрирано, червено,
  /// bold заглавие, а под него центрирана дата в обичайните цветове/формат.
  Widget _paschaRow(_FeastResult r) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        children: [
          Text(
            r.spec.displayName,
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontFamily: _bodyFamily,
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: _headingRed),
          ),
          const SizedBox(height: 6),
          Text.rich(
            TextSpan(children: _dateSpans(r.civilDate, 20)),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _h2(String text) => Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 6),
        child: Text(text,
            style: const TextStyle(
                fontFamily: _bodyFamily,
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: _headingRed)),
      );

  /// Пояснение под заглавие — сиво (не червено), курсив.
  Widget _hint(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(text,
            style: const TextStyle(
                fontFamily: _bodyFamily,
                fontSize: 17,
                fontStyle: FontStyle.italic,
                color: _dim)),
      );

  Widget _h3(String text) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 8),
        child: Text(text,
            style: const TextStyle(
                fontFamily: _bodyFamily,
                fontSize: 19,
                fontWeight: FontWeight.bold,
                color: _headingRed)),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.toolbar,
      appBar: AppBar(
        backgroundColor: AppColors.toolbar,
        title: const Text('Празници'),
      ),
      body: SafeArea(
        child: Container(
          color: AppColors.background,
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Църковни празници',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontFamily: _titleFamily, fontSize: 40, height: 1.25, color: _ink),
                      ),
                      const SizedBox(height: 15),
                      const Text(
                        'изберете година',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontFamily: _bodyFamily,
                            fontSize: 18,
                            fontStyle: FontStyle.italic,
                            color: _dim),
                      ),
                      //const SizedBox(height: 0),
                      Center(
                        child: DropdownButton<int>(
                          value: _selectedYear,
                          dropdownColor: AppColors.toolbar,
                          underline: const SizedBox.shrink(),
                          style: const TextStyle(
                              fontFamily: _titleFamily, fontSize: 40, color: _ink),
                          items: _availableYears
                              .map((y) => DropdownMenuItem(value: y, child: Text('$y')))
                              .toList(),
                          onChanged: (y) {
                            if (y != null) _loadYear(y);
                          },
                        ),
                      ),
                      const SizedBox(height: 36),
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
