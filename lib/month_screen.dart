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
    '', 'Януари', 'Февруари', 'Март', 'Април', 'Май', 'Юни',
    'Юли', 'Август', 'Септември', 'Октомври', 'Ноември', 'Декември'
  ];

  static const _monthNamesShort = [
    '', 'ян', 'фе', 'мр', 'ап', 'ма', 'юн',
    'юл', 'ав', 'се', 'ок', 'но', 'де'
  ];

  static const _weekDaysShort = [
    '', 'пн', 'вт', 'ср', 'чт', 'пт', 'сб', 'нд'
  ];

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
    return PageView.builder(
      controller: _pageController,
      onPageChanged: (page) => setState(() => _currentMonthIndex = page - 100),
      itemBuilder: (context, page) {
        final monthDate = _indexToMonth(page - 100);
        // Key включва isOldStyle — при смяна на базата пресъздаваме
        // oldStyleFirst НЕ е в key — при смяна само UI се обновява
        return _MonthPage(
          key: ValueKey('${monthDate.year}_${monthDate.month}_${AppSettings.isOldStyle}'),
          year: monthDate.year,
          month: monthDate.month,
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
  final List<String> monthNames;
  final List<String> monthNamesShort;
  final List<String> weekDaysShort;
  final Function(DateTime) onDateSelected;

  const _MonthPage({
    super.key,
    required this.year,
    required this.month,
    required this.monthNames,
    required this.monthNamesShort,
    required this.weekDaysShort,
    required this.onDateSelected,
  });

  @override
  State<_MonthPage> createState() => _MonthPageState();
}

class _MonthPageState extends State<_MonthPage> {
  // Кешът съдържа РАЗШИРЕН диапазон по нов стил:
  // от (1-ви - 13 дни) до 31-во число
  // Ключ: '2026-01-14' (дата по нов стил)
  Map<String, List<Map<String, dynamic>>> _cache = {};
  bool _loading = true;

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

  Future<void> _loadMonth() async {
    setState(() => _loading = true);
    final db = await DatabaseHelper.database;

    // Разширен диапазон: 13 дни преди + целия месец
    // Всичко по НОВ стил (ключовете в базата)
    final rangeStart = DateTime(widget.year, widget.month, 1)
      .subtract(const Duration(days: 13));
		final rangeEnd = DateTime(widget.year, widget.month + 1, 0)
			.add(const Duration(days: 13));

    final Map<String, List<Map<String, dynamic>>> cache = {};

    DateTime current = rangeStart;
    while (!current.isAfter(rangeEnd)) {
      final dateStr = current.toIso8601String().substring(0, 10);

      final saints = await db.rawQuery('''
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
        ...saints,
        if (dayResult.isNotEmpty && dayResult.first['sunday_name'] != null)
          {'_sunday': dayResult.first['sunday_name']},
      ];

      current = current.add(const Duration(days: 1));
    }

    if (mounted) {
      setState(() {
        _cache = cache;
        _loading = false;
      });
    }
  }

  // Генерира дните за показване според водещия стил
  List<DateTime> _getDaysToShow() {
    final days = <DateTime>[];
    final last = DateTime(widget.year, widget.month + 1, 0);
    for (int d = 1; d <= last.day; d++) {
      days.add(DateTime(widget.year, widget.month, d));
    }
    return days;
  }

  // Връща ключа за кеша (винаги нов стил)
  String _cacheKey(DateTime day) {
    // oldStyleFirst=false в AppSettings означава стар стил е водещ (инверсия)
    final bool oldIsLeading = !AppSettings.oldStyleFirst;
    final DateTime newStyleDate = (AppSettings.isOldStyle && oldIsLeading)
        ? _toNewStyle(day)  // деня е по стар стил → конвертираме за кеша
        : day;              // деня е по нов стил → директно
    return newStyleDate.toIso8601String().substring(0, 10);
  }

  // Справочната дата (другия стил)
  DateTime _refDate(DateTime day) {
    final bool oldIsLeading = !AppSettings.oldStyleFirst;
    if (AppSettings.isOldStyle && oldIsLeading) {
      // Водещ стар стил → справочна е нов стил
      return _toNewStyle(day);
    } else if (AppSettings.isOldStyle && !oldIsLeading) {
      // Водещ нов стил → справочна е стар стил
      return _toOldStyle(day);
    }
    return day; // нов стил режим → само нов стил
  }

  @override
  Widget build(BuildContext context) {
    final bool showOldStyle = AppSettings.isOldStyle;
    final bool oldIsLeading = !AppSettings.oldStyleFirst;

    final String leftLabel  = showOldStyle ? (oldIsLeading ? 'ст.с.' : 'н.с.') : '';
    final String rightLabel = showOldStyle ? (oldIsLeading ? 'н.с.' : 'ст.с.') : '';
    final headerMonth = '${widget.monthNames[widget.month]} ${widget.year}';

    final days = _getDaysToShow();

    // Определяме дали първия ред трябва да показва справочния месец
    final DateTime firstRefDate = showOldStyle ? _refDate(days.first) : days.first;
    final bool firstRowShowsMonth = showOldStyle &&
        (firstRefDate.month != widget.month || firstRefDate.year != widget.year);

    return Column(
      children: [
        // ─── Хедър — плъзга се с месеца ──────────────────────────────
        Container(
          color: AppColors.appBarWeekday,
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
          child: Row(
            children: [
              if (showOldStyle) ...[
                Icon(
                  oldIsLeading ? Icons.church : Icons.tv,
                  color: AppColors.textSecondary,
                  size: 22,
                ),
                const SizedBox(width: 4),
                Text(leftLabel,
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
              if (showOldStyle) ...[
                Text(rightLabel,
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 11)),
                const SizedBox(width: 4),
                Icon(
                  oldIsLeading ? Icons.tv : Icons.church,
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
                    final day = days[index];
                    final bool isSunday = day.weekday == 7;
                    final String key = _cacheKey(day);
                    final saints = _cache[key] ?? [];
                    final DateTime refDate = _refDate(day);

                    // Показваме справочния месец при:
                    // 1. Първо число на справочния месец
                    // 2. Първи ред ако справочния месец ≠ водещия
                    final bool isFirstOfRefMonth = refDate.day == 1;
                    final bool showRefMonth = showOldStyle &&
                        (isFirstOfRefMonth || (index == 0 && firstRowShowsMonth));
                    final String refMonthShort = showRefMonth
                        ? widget.monthNamesShort[refDate.month]
                        : '';

                    // При клик отиваме на деня по нов стил (ключа в базата)
                    final DateTime tapDate = (AppSettings.isOldStyle && oldIsLeading)
                        ? _toNewStyle(day)
                        : day;

                    return GestureDetector(
                      onTap: () => widget.onDateSelected(tapDate),
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
                            if (showOldStyle)
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
