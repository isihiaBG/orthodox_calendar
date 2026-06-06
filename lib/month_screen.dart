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
  State<MonthScreen> createState() => MonthScreenState();
}

class MonthScreenState extends State<MonthScreen> {
  late PageController _pageController;
  late int _currentMonthIndex;

  // GlobalKey за достъп до текущата _MonthPage
  final Map<int, GlobalKey<_MonthPageState>> _pageKeys = {};

  static final DateTime _baseDate = DateTime(2026, 1, 1);

  static const _monthNames = [
    '', 'Януари', 'Февруари', 'Март', 'Април', 'Май', 'Юни',
    'Юли', 'Август', 'Септември', 'Октомври', 'Ноември', 'Декември'
  ];

  static const _monthNamesShort = [
    '', 'яну', 'фев', 'мар', 'апр', 'май', 'юни',
    'юли', 'авг', 'сеп', 'окт', 'ное', 'дек'
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

	DateTime get currentDate {
	  final index = _pageController.page?.round() ?? _currentMonthIndex;
	  final monthDate = _indexToMonth(index - 100);
	  // При водещ стар стил — конвертираме към нов стил за датепикъра
	  final bool oldIsLeading = !AppSettings.oldStyleFirst;
	  if (AppSettings.isOldStyle && oldIsLeading) {
		return DateTime(monthDate.year, monthDate.month, 1)
			.add(const Duration(days: 13));
	  }
	  return DateTime(monthDate.year, monthDate.month, 1);
	}

  @override
  void initState() {
    super.initState();
    // Инициализираме днешната дата
    final now = DateTime.now();
    AppSettings.today = DateTime(now.year, now.month, now.day);
    _currentMonthIndex = _monthToIndex(widget.initialDate);
    _pageController = PageController(initialPage: _currentMonthIndex + 100);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  // Навигира до дата — плъзга месеца и скролира до деня
	void navigateToDate(DateTime date, {bool flash = true}) {
	  // date е винаги по нов стил
	  // При водещ стар стил — навигираме до месеца по стар стил
	  final bool oldIsLeading = !AppSettings.oldStyleFirst;
	  final DateTime leadingDate = (AppSettings.isOldStyle && oldIsLeading)
		  ? date.subtract(const Duration(days: 13))  // конвертираме към стар стил
		  : date;

	  final targetIndex = _monthToIndex(leadingDate);  // месец по водещия стил
	  final targetPage  = targetIndex + 100;

	  if (flash) AppSettings.flashDate = date;

	  _pageController.animateToPage(
		targetPage,
		duration: const Duration(milliseconds: 400),
		curve: Curves.easeInOut,
	  ).then((_) {
		final key = _pageKeys[targetIndex];
		key?.currentState?.scrollToDate(date);
	  });
	}

  @override
  Widget build(BuildContext context) {
    return PageView.builder(
      controller: _pageController,
      onPageChanged: (page) => setState(() => _currentMonthIndex = page - 100),
      itemBuilder: (context, page) {
        final monthDate  = _indexToMonth(page - 100);
        final monthIndex = page - 100;

        _pageKeys[monthIndex] ??= GlobalKey<_MonthPageState>();

        return KeyedSubtree(
          key: ValueKey('${monthDate.year}_${monthDate.month}_${AppSettings.isOldStyle}'),
          child: _MonthPage(
            key: _pageKeys[monthIndex]!,
            //stateKey: _pageKeys[monthIndex]!,
            year: monthDate.year,
            month: monthDate.month,
            monthNames: _monthNames,
            monthNamesShort: _monthNamesShort,
            weekDaysShort: _weekDaysShort,
            onDateSelected: widget.onDateSelected,
          ),
        );
      },
    );
  }
}

// ─── Един месец ───────────────────────────────────────────────────────────
class _MonthPage extends StatefulWidget {
  //final GlobalKey<_MonthPageState> stateKey;
  final int year;
  final int month;
  final List<String> monthNames;
  final List<String> monthNamesShort;
  final List<String> weekDaysShort;
  final Function(DateTime) onDateSelected;

  const _MonthPage({
    required Key key,
    //required this.stateKey,
    required this.year,
    required this.month,
    required this.monthNames,
    required this.monthNamesShort,
    required this.weekDaysShort,
    required this.onDateSelected,
  }) : super(key: key);

  @override
  State<_MonthPage> createState() => _MonthPageState();
}

class _MonthPageState extends State<_MonthPage>
    with TickerProviderStateMixin {
  Map<String, List<Map<String, dynamic>>> _cache = {};
  bool _loading = true;
  final ScrollController _scrollController = ScrollController();
  final Map<int, GlobalKey> _rowKeys = {};
  DateTime? _pendingScrollDate;

  // Flash анимация
  late AnimationController _flashController;
  late Animation<double> _flashAnimation;
  DateTime? _flashingDate;

	static DateTime _toNewStyle(DateTime d) => 
		DateTime.utc(d.year, d.month, d.day).add(const Duration(days: 13));
	static DateTime _toOldStyle(DateTime d) => 
		DateTime.utc(d.year, d.month, d.day).subtract(const Duration(days: 13));

  static Color _signColor(String? hexColor) {
    if (hexColor == AppColors.signRedHex) return AppColors.signRed;
    return AppColors.signWhite;
  }

  @override
  void initState() {
    super.initState();

    // Flash анимация — плавно изсветляване и изчезване (~1.5 сек)
    _flashController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    _flashAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 30),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.0), weight: 20),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 50),
    ]).animate(CurvedAnimation(
      parent: _flashController,
      curve: Curves.easeInOut,
    ));

    _loadMonth();

    // Проверяваме дали има flashDate за този месец
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkFlash();
    });
  }

  @override
  void dispose() {
    _flashController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _checkFlash() {
    final flash = AppSettings.flashDate;
    if (flash == null) return;

    // Конвертираме flash датата към водещия стил за сравнение
    final bool oldIsLeading = !AppSettings.oldStyleFirst;
    final DateTime leadingFlash = (AppSettings.isOldStyle && oldIsLeading)
        ? _toOldStyle(flash)
        : flash;

    if (leadingFlash.year == widget.year && leadingFlash.month == widget.month) {
      _flashingDate = leadingFlash;
      _flashController.forward(from: 0).then((_) {
        AppSettings.flashDate = null;
        _flashingDate = null;
      });
    }
  }

  // Скролира до конкретна дата в 2:1 позиция (горна:долна)
	void scrollToDate(DateTime date) {
	  if (_loading) {
		// Запазваме датата и скролираме след зареждане
		_pendingScrollDate = date;
		return;
	  }
	  _doScroll(date);
	}

	void _doScroll(DateTime date) {
	  final bool oldIsLeading = !AppSettings.oldStyleFirst;
	  final DateTime leadingDate = (AppSettings.isOldStyle && oldIsLeading)
		  ? _toOldStyle(date)
		  : date;

	  final days = _getDaysToShow();
	  final index = days.indexWhere((d) =>
		  d.day == leadingDate.day &&
		  d.month == leadingDate.month &&
		  d.year == leadingDate.year);

	  if (index < 0 || !_scrollController.hasClients) return;

	  // final approxOffset = (index / days.length) *
		//   _scrollController.position.maxScrollExtent;
	  // _scrollController.jumpTo(
		//   approxOffset.clamp(0.0, _scrollController.position.maxScrollExtent));

	  WidgetsBinding.instance.addPostFrameCallback((_) {
		final rowKey = _rowKeys[index];
		if (rowKey?.currentContext != null) {
		  Scrollable.ensureVisible(
			rowKey!.currentContext!,
			alignment: 0.33,
			duration: const Duration(milliseconds: 400),
			curve: Curves.easeInOut,
		  );
		} else {
			// Редът не е видим — приблизително скролиране първо
			final approxOffset = (index / days.length) *
				_scrollController.position.maxScrollExtent;
			_scrollController.jumpTo(
				approxOffset.clamp(0.0, _scrollController.position.maxScrollExtent));
			Future.delayed(const Duration(milliseconds: 100), () {
			  final rowKey2 = _rowKeys[index];
			  if (rowKey2?.currentContext != null) {
				Scrollable.ensureVisible(
				  rowKey2!.currentContext!,
				  alignment: 0.33,
				  duration: const Duration(milliseconds: 400),
				  curve: Curves.easeInOut,
				);
			  }
			});
		}
		setState(() => _flashingDate = leadingDate);
		_flashController.forward(from: 0).then((_) {
		  if (mounted) setState(() => _flashingDate = null);
		});
	  });
	}

  Future<void> _loadMonth() async {
    setState(() => _loading = true);
    final db = await DatabaseHelper.database;

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
		  // Изпълняваме отложения скрол ако има такъв
		  if (_pendingScrollDate != null) {
			final pending = _pendingScrollDate!;
			_pendingScrollDate = null;
			WidgetsBinding.instance.addPostFrameCallback((_) => _doScroll(pending));
		  }
		  WidgetsBinding.instance.addPostFrameCallback((_) => _checkFlash());
		}
  }

  List<DateTime> _getDaysToShow() {
    final days = <DateTime>[];
    final last = DateTime(widget.year, widget.month + 1, 0);
    for (int d = 1; d <= last.day; d++) {
      days.add(DateTime(widget.year, widget.month, d));
    }
    return days;
  }

  String _cacheKey(DateTime day) {
    final bool oldIsLeading = !AppSettings.oldStyleFirst;
    final DateTime newStyleDate = (AppSettings.isOldStyle && oldIsLeading)
        ? _toNewStyle(day)
        : day;
    return newStyleDate.toIso8601String().substring(0, 10);
  }

  DateTime _refDate(DateTime day) {
    final bool oldIsLeading = !AppSettings.oldStyleFirst;
    if (AppSettings.isOldStyle && oldIsLeading) {
      return _toNewStyle(day);
    } else if (AppSettings.isOldStyle && !oldIsLeading) {
      return _toOldStyle(day);
    }
    return day;
  }

  // Определя фона на реда
  Color _rowBackground(DateTime day, bool isSunday) {
    final bool oldIsLeading = !AppSettings.oldStyleFirst;
    final DateTime dbDate = (AppSettings.isOldStyle && oldIsLeading)
        ? _toNewStyle(day)
        : day;

    final today = AppSettings.today;
    final bool isToday = today != null &&
        dbDate.year == today.year &&
        dbDate.month == today.month &&
        dbDate.day == today.day;

    final bool isFlashing = _flashingDate != null &&
        day.day == _flashingDate!.day &&
        day.month == _flashingDate!.month &&
        day.year == _flashingDate!.year;

    if (isSunday) {
      if (isToday) return AppColors.sundayTodayBg;
      return AppColors.appBarSundayBg;
    } else {
      if (isToday) return AppColors.todayBg;
      return Colors.transparent;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool showOldStyle = AppSettings.isOldStyle;
    final bool oldIsLeading = !AppSettings.oldStyleFirst;

    final String leftLabel  = showOldStyle ? (oldIsLeading ? 'стар' : 'нов') : '';
    final String leftLabel2 = showOldStyle ? 'стил' : '';
    final String rightLabel  = showOldStyle ? (oldIsLeading ? 'нов' : 'стар') : '';
    final String rightLabel2 = showOldStyle ? 'стил' : '';
    final headerMonth = '${widget.monthNames[widget.month]} ${widget.year}';

    final days = _getDaysToShow();

    final DateTime firstRefDate = showOldStyle ? _refDate(days.first) : days.first;
    final bool firstRowShowsMonth = showOldStyle &&
        (firstRefDate.month != widget.month || firstRefDate.year != widget.year);

    return Column(
      children: [
        // ─── Хедър ────────────────────────────────────────────────────
        Container(
          color: AppColors.appBarWeekday,
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
          child: Row(
            children: [
              if (showOldStyle) ...[
                Icon(oldIsLeading ? Icons.church : Icons.live_tv,
                    color: AppColors.textSecondary, size: 22),
                const SizedBox(width: 4),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(leftLabel, style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: AppFonts.monthHeaderLabel,
                        height: 1.0)),
                    Text(leftLabel2, style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: AppFonts.monthHeaderLabel,
                        height: 1.0)),
                  ],
                ),
              ],
              Expanded(
                child: Text(headerMonth,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: AppFonts.monthHeaderMonth,
                    fontWeight: FontWeight.w500,
                  )),
              ),
              if (showOldStyle) ...[
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(rightLabel, style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: AppFonts.monthHeaderLabel,
                        height: 1.0)),
                    Text(rightLabel2, style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: AppFonts.monthHeaderLabel,
                        height: 1.0)),
                  ],
                ),
                const SizedBox(width: 4),
                Icon(oldIsLeading ? Icons.live_tv : Icons.church,
                    color: AppColors.textSecondary, size: 22),
              ],
            ],
          ),
        ),

        // ─── Списък с дни ─────────────────────────────────────────────
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              //: AnimatedBuilder(
              : ListView.separated(
                  //animation: _flashAnimation,
                  //builder: (context, child) {
                    //return ListView.separated(
                      controller: _scrollController,
                      padding: EdgeInsets.zero,
                      itemCount: days.length,
                      separatorBuilder: (context, index) =>
                          Divider(color: AppColors.sectionDivider, height: 1),
                      itemBuilder: (context, index) {
                        final day = days[index];
												// Денят от седмицата е еднакъв по двата стила — взимаме от новостиловата дата
												final DateTime dbDate = (AppSettings.isOldStyle && oldIsLeading)
													? _toNewStyle(day)
													: day;
												final bool isSunday = dbDate.weekday == 7;
                        final String key = _cacheKey(day);
												final saints = _cache[key] ?? [];
												if (index >= 11 && index <= 13) {
												  print('day: ${day.day}, key: $key, saints: ${saints.length}');
												}
                        final DateTime refDate = _refDate(day);

                        final bool isFirstOfRefMonth = refDate.day == 1;
                        final bool showRefMonth = showOldStyle &&
                            (isFirstOfRefMonth ||
                                (index == 0 && firstRowShowsMonth));
                        final String refMonthShort = showRefMonth
                            ? widget.monthNamesShort[refDate.month]
                            : '';

                        final DateTime tapDate =
                            (AppSettings.isOldStyle && oldIsLeading)
                                ? _toNewStyle(day)
                                : day;

                        // Изчисляваме фона с flash
                        final bool isFlashing = _flashingDate != null &&
                            day.day == _flashingDate!.day &&
                            day.month == _flashingDate!.month &&
                            day.year == _flashingDate!.year;

                        Color baseColor = _rowBackground(day, isSunday);
                        
                        Color rowColor = baseColor;
                        if (isFlashing) {
                          final flashColor = isSunday
                              ? AppColors.sundayFlash
                              : AppColors.todayFlash;
                          rowColor = Color.lerp(
                              baseColor, flashColor, _flashAnimation.value)!;
                        }
                        
                        _rowKeys[index] ??= GlobalKey();

												return GestureDetector(
                          key: _rowKeys[index],
												  onTap: () => widget.onDateSelected(tapDate),
												  child: AnimatedBuilder(
													animation: _flashAnimation,
													builder: (context, _) {
													  Color rowColor = baseColor;
													  if (isFlashing) {
														final flashColor = isSunday
															? AppColors.sundayFlash
															: AppColors.todayFlash;
														rowColor = Color.lerp(
															baseColor, flashColor, _flashAnimation.value)!;
													  }
													  return Container(
														color: rowColor,
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
																  Text('${day.day}',
																	style: TextStyle(
																	  color: isSunday
																		  ? AppColors.monthTitleSunday
																		  : AppColors.textPrimary,
																	  fontSize: AppFonts.monthDayNumber,
																	  fontWeight: FontWeight.w600,
																	)),
																  Text(widget.weekDaysShort[dbDate.weekday],
																	style: TextStyle(
																	  color: isSunday
																		  ? AppColors.monthTitleSunday
																		  : AppColors.textMuted,
																	  fontSize: AppFonts.monthWeekDay,
																	)),
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
																		  Text(s['_sunday'] as String,
																			style: const TextStyle(
																			  color: AppColors.monthTitleSunday,
																			  fontSize: AppFonts.monthSundayName,
																			  fontWeight: FontWeight.w600,
																			)),
																	for (final s in saints)
																	  if (s['_sunday'] == null)
																		Padding(
																		  padding: const EdgeInsets.only(bottom: 2),
																		  child: Text(
																			'${s['sign'] ?? '•'} ${s['name']}',
																			style: TextStyle(
																			  color: _signColor(s['sign_color'] as String?),
																			  fontSize: AppFonts.monthSaintName,
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
																	Text('${refDate.day}',
																	  style: const TextStyle(
																		color: AppColors.textMuted,
																		fontSize: AppFonts.monthRefDate,
																	  )),
																	if (showRefMonth)
																	  ...refMonthShort.split('').map((c) => Text(c,
																		style: const TextStyle(
																		  color: AppColors.textMuted,
																		  fontSize: AppFonts.monthRefMonth,
																		))),
																  ],
																),
															  ),
														  ],
														),
													  );
													},
												  ),
												);
                      },
                    ),
                  //},
                //),
        ),
      ],
    );
  }
}
