import 'package:flutter/material.dart';
import 'database_helper.dart';
import 'app_theme.dart';
import 'app_settings.dart';

class MonthScreen extends StatefulWidget {
  final DateTime initialDate;
  final Function(DateTime) onDateSelected;

  const MonthScreen({
    super.key,
    required this.initialDate,
    required this.onDateSelected,
  });

  @override
  State<MonthScreen> createState() => _MonthScreenState();
}

class _MonthScreenState extends State<MonthScreen> {
  late PageController _pageController;
  late int _currentMonthIndex;

  static final DateTime _baseDate = DateTime(2026, 1, 1);

  static const _monthNames = [
    '', 'Јануари', 'Февруари', 'Март', 'Април', 'Май', 'Юни',
    'Юли', 'Август', 'Септември', 'Октомври', 'Ноември', 'Декември'
  ];

  static const _monthNamesShort = [
    '', 'ян', 'фе', 'мр', 'ап', 'ма', 'юн',
    'юл', 'ав', 'се', 'ок', 'но', 'де'
  ];

  static const _weekDaysShort = ['', 'пн', 'вт', 'ср', 'чт', 'пт', 'сб', 'нд'];

  static DateTime _indexToMonth(int index) {
    int year  = _baseDate.year + index ~/ 12;
    int month = _baseDate.month + index % 12;
    if (month > 12) { month -= 12; year++; }
    return DateTime(year, month, 1);
  }

  static int _monthToIndex(DateTime date) {
    return (date.year - _baseDate.year) * 12 + (date.month - _baseDate.month);
  }

  @override
  void initState() {
    super.initState();
    _currentMonthIndex = _monthToIndex(widget.initialDate);
    _pageController = PageController(initialPage: _currentMonthIndex + 100);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Четем настройките тук за да се рендерира при смяна
    final bool showOldStyle = AppSettings.isOldStyle;
    final bool oldFirst = !AppSettings.oldStyleFirst;

    final String leftLabel  = showOldStyle ? (oldFirst ? 'ст.с.' : 'н.с.') : '';
    final String rightLabel = showOldStyle ? (oldFirst ? 'н.с.' : 'ст.с.') : '';

    return PageView.builder(
      controller: _pageController,
      onPageChanged: (page) => setState(() => _currentMonthIndex = page - 100),
      itemBuilder: (context, page) {
        final monthDate = _indexToMonth(page - 100);
        // KEY включва настройките — при смяна страницата се пресъздава
        return _MonthPage(
          key: ValueKey('${monthDate.year}_${monthDate.month}_${showOldStyle}_$oldFirst'),
          year: monthDate.year,
          month: monthDate.month,
          showOldStyle: showOldStyle,
          oldFirst: oldFirst,
          leftLabel: leftLabel,
          rightLabel: rightLabel,
          monthNames: _monthNames,
          monthNamesShort: _monthNamesShort,
          weekDaysShort: _weekDaysShort,
          onDateSelected: widget.onDateSelected,
        );
      },
    );
  }
}

// ─── Един месец ───────────────────────────────────────────────────────────
class _MonthPage extends StatefulWidget {
  final int year;
  final int month;
  final bool showOldStyle;
  final bool oldFirst;
  final String leftLabel;
  final String rightLabel;
  final List<String> monthNames;
  final List<String> monthNamesShort;
  final List<String> weekDaysShort;
  final Function(DateTime) onDateSelected;

  const _MonthPage({
    super.key,
    required this.year,
    required this.month,
    required this.showOldStyle,
    required this.oldFirst,
    required this.leftLabel,
    required this.rightLabel,
    required this.monthNames,
    required this.monthNamesShort,
    required this.weekDaysShort,
    required this.onDateSelected,
  });

  @override
  State<_MonthPage> createState() => _MonthPageState();
}

class _MonthPageState extends State<_MonthPage> {
  Map<String, List<Map<String, dynamic>>> _saintsCache = {};
  bool _loading = true;

  // Конвертори
  static DateTime _toNewStyle(DateTime d) => d.add(const Duration(days: 13));
  static DateTime _toOldStyle(DateTime d) => d.subtract(const Duration(days: 13));

  static Color _signColor(String? hexColor) {
    if (hexColor == AppColors.signRedHex) return AppColors.signRed;
    return AppColors.signWhite;
  }

  @override
  void initState() {
    super.initState();
    _loadMonth();
  }

  // Генерира дните в месеца СПОРЕД ВОДЕЩИЯ СТИЛ
  List<DateTime> _getDaysInMonth() {
    final days = <DateTime>[];
    final last = DateTime(widget.year, widget.month + 1, 0);
    for (int d = 1; d <= last.day; d++) {
      days.add(DateTime(widget.year, widget.month, d));
    }
    return days;
  }

  // Конвертира водещия ден към дата за заявка в базата (винаги нов стил)
  DateTime _toDbDate(DateTime leadingDay) {
    if (widget.showOldStyle) {
      // Базата е по нов стил — конвертираме стар→нов
      return _toNewStyle(leadingDay);
    } else {
      // Базата е по нов стил — директно
      return leadingDay;
    }
  }

  Future<void> _loadMonth() async {
    setState(() => _loading = true);
    final db = await DatabaseHelper.database;
    final days = _getDaysInMonth();
    final Map<String, List<Map<String, dynamic>>> cache = {};

    for (final day in days) {
      final dbDate  = _toDbDate(day);
      final dateStr = dbDate.toIso8601String().substring(0, 10);

      final results = await db.rawQuery('''
        SELECT s.name, s.rank, s.sign, r.sign_color
        FROM saints s
        LEFT JOIN saint_ranks r ON s.rank = r.id
        WHERE s.date = ?
        ORDER BY s.rank ASC
        LIMIT 3
      ''', [dateStr]);

      final dayResult = await db.rawQuery('''
        SELECT cd.*, sn.name as sunday_name
        FROM calendar_days cd
        LEFT JOIN sundays sn ON cd.sunday_id = sn.id
        WHERE cd.date = ?
      ''', [dateStr]);

      cache[dateStr] = [
        ...results,
        if (dayResult.isNotEmpty && dayResult.first['sunday_name'] != null)
          {'_sunday': dayResult.first['sunday_name']},
      ];
    }

    if (mounted) {
      setState(() {
        _saintsCache = cache;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final days = _getDaysInMonth();
    final headerMonth = '${widget.monthNames[widget.month]} ${widget.year}';

    // Справочният месец на първия ден
    final DateTime firstDbDate = _toDbDate(days.first);
    final DateTime firstRefDate = widget.showOldStyle
        ? firstDbDate                // нов стил като справочна
        : _toOldStyle(days.first);   // стар стил като справочна
    final bool firstRowShowsMonth = firstRefDate.month != widget.month
        || firstRefDate.year != widget.year;

    return Column(
      children: [
        // ─── Хедър — плъзга се с месеца ──────────────────────────────
        Container(
          color: AppColors.appBarWeekday,
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
          child: Row(
            children: [
              if (widget.showOldStyle) ...[
                Icon(
                  widget.oldFirst ? Icons.church : Icons.tv,
                  color: AppColors.textSecondary,
                  size: 22,
                ),
                const SizedBox(width: 4),
                Text(widget.leftLabel,
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 11)),
              ],
              Expanded(
                child: Text(
                  headerMonth,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (widget.showOldStyle) ...[
                Text(widget.rightLabel,
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 11)),
                const SizedBox(width: 4),
                Icon(
                  widget.oldFirst ? Icons.tv : Icons.church,
                  color: AppColors.textSecondary,
                  size: 22,
                ),
              ],
            ],
          ),
        ),

        // ─── Списък с дни ─────────────────────────────────────────────
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : ListView.separated(
                  padding: EdgeInsets.zero,
                  itemCount: days.length,
                  separatorBuilder: (_, __) =>
                      Divider(color: AppColors.sectionDivider, height: 1),
                  itemBuilder: (context, index) {
                    final day    = days[index];
                    final bool isSunday = day.weekday == 7;
                    final dbDate  = _toDbDate(day);
                    final dateStr = dbDate.toIso8601String().substring(0, 10);
                    final saints  = _saintsCache[dateStr] ?? [];

                    // Справочна дата
                    final DateTime refDate = widget.showOldStyle
                        ? dbDate             // нов стил
                        : _toOldStyle(day);  // стар стил

                    // Показваме месеца в справочната колона когато:
                    // 1. Първо число на справочния месец
                    // 2. Първи ред и месецът се различава от водещия
                    final bool isFirstOfRefMonth = refDate.day == 1;
                    final bool showRefMonth = isFirstOfRefMonth ||
                        (index == 0 && firstRowShowsMonth);

                    final String refMonthShort = showRefMonth
                        ? widget.monthNamesShort[refDate.month]
                        : '';

                    return GestureDetector(
                      onTap: () => widget.onDateSelected(dbDate),
                      child: Container(
                        color: isSunday
                            ? AppColors.appBarSunday.withOpacity(0.15)
                            : Colors.transparent,
                        padding: const EdgeInsets.symmetric(
                            vertical: 8, horizontal: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Лява колона: водеща дата + ден
                            SizedBox(
                              width: 36,
                              child: Column(
                                children: [
                                  Text(
                                    '${day.day}',
                                    style: TextStyle(
                                      color: isSunday
                                          ? AppColors.appBarSunday
                                          : AppColors.textPrimary,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    widget.weekDaysShort[day.weekday],
                                    style: TextStyle(
                                      color: isSunday
                                          ? AppColors.appBarSunday
                                          : AppColors.textMuted,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            // Средна колона: светии
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (isSunday)
                                      for (final s in saints)
                                        if (s['_sunday'] != null)
                                          Text(
                                            s['_sunday'] as String,
                                            style: const TextStyle(
                                              color: AppColors.appBarSunday,
                                              fontSize: 13,
                                              fontStyle: FontStyle.italic,
                                            ),
                                          ),
                                    for (final s in saints)
                                      if (s['_sunday'] == null)
                                        Padding(
                                          padding: const EdgeInsets.only(bottom: 2),
                                          child: Text(
                                            '${s['sign'] ?? '•'} ${s['name']}',
                                            style: TextStyle(
                                              color: _signColor(
                                                  s['sign_color'] as String?),
                                              fontSize: 13,
                                            ),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                  ],
                                ),
                              ),
                            ),

                            // Дясна колона: справочна дата
                            if (widget.showOldStyle)
                              SizedBox(
                                width: 28,
                                child: Column(
                                  children: [
                                    Text(
                                      '${refDate.day}',
                                      style: const TextStyle(
                                        color: AppColors.textMuted,
                                        fontSize: 13,
                                      ),
                                    ),
                                    if (showRefMonth)
                                      ...refMonthShort.split('').map((c) => Text(
                                            c,
                                            style: const TextStyle(
                                              color: AppColors.textMuted,
                                              fontSize: 10,
                                            ),
                                          )),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
