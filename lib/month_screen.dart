import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'database_helper.dart';
import 'app_theme.dart';
import 'app_settings.dart';
import 'moon_calculator.dart';

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
	void navigateToDate(DateTime date, {bool flash = true, bool animated = true}) {
	  // date е винаги по нов стил
	  // При водещ стар стил — навигираме до месеца по стар стил
	  final bool oldIsLeading = !AppSettings.oldStyleFirst;
	  final DateTime leadingDate = (AppSettings.isOldStyle && oldIsLeading)
		  ? date.subtract(const Duration(days: 13))  // конвертираме към стар стил
		  : date;

	  final targetIndex = _monthToIndex(leadingDate);  // месец по водещия стил
	  final targetPage  = targetIndex + 100;

	  if (flash) {
      AppSettings.flashDate = date;
    } else {
      AppSettings.flashDate = null; // изчистваме евентуален стар флаш
    }

	  _pageController.animateToPage(
		targetPage,
		duration: const Duration(milliseconds: 400),
		curve: Curves.easeInOut,
	  ).then((_) {
		final key = _pageKeys[targetIndex];
		key?.currentState?.scrollToDate(date, animated: animated);
	  });
	}

  // Връща датата (по нов стил) на реда в средата на екрана.
  // Ползва се при смяна на водеща дата за да запазим позицията.
  DateTime? getMiddleDate() {
    final key = _pageKeys[_currentMonthIndex];
    return key?.currentState?.getMiddleVisibleDate();
  }

  // Извиква се при смяна на стар/нов стил от настройките.
  // Презарежда данните на всички заредени месеци БЕЗ да пресъздава
  // widget-ите — така скрол позицията се запазва (без премигване).
  void refreshAfterSettingsChange() {
    for (final key in _pageKeys.values) {
      key.currentState?.reloadKeepingScroll();
    }
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

        return _MonthPage(
          key: _pageKeys[monthIndex]!,
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
  bool _pendingAnimated = true;
  bool _initialScrollDone = true;
  final ScrollController _scrollController = ScrollController();
  final Map<int, GlobalKey> _rowKeys = {};
  // Референтна рамка за изчисляване позицията на плаващата табела
  final GlobalKey _listStackKey = GlobalKey();
  DateTime? _pendingScrollDate;

  // Flash анимация
  late AnimationController _flashController;
  late Animation<double> _flashAnimation;
  DateTime? _flashingDate;

  // Връща датата (по нов стил) на реда който е приблизително
  // в средата на екрана. Ползва RenderBox за точно определяне.
  // Връща null ако нищо не е видимо или редовете не са рендерирани.
  DateTime? getMiddleVisibleDate() {
    if (!_scrollController.hasClients) return null;
    final days = _getDaysToShow();
    final screenHeight = MediaQuery.of(context).size.height;
    final toolbarOffset = MediaQuery.of(context).padding.top 
                        + AppSizes.toolbarHeight 
                        + AppSizes.monthHeaderHeight; // status bar + toolbar + month header
    final listHeight = screenHeight - toolbarOffset;
    final screenCenter = toolbarOffset + listHeight / 3; // 1/3 от листинг екрана = alignment: 0.33

    // final screenCenter = screenHeight / 3; // 1/3 от листинг прозореца = alignment: 0.33

    for (int i = 0; i < days.length; i++) {
      final key = _rowKeys[i];
      if (key?.currentContext == null) continue;
      final box = key!.currentContext!.findRenderObject() as RenderBox?;
      if (box == null) continue;
      final position = box.localToGlobal(Offset.zero);
      final rowTop    = position.dy;
      final rowBottom = rowTop + box.size.height;
      if (rowTop <= screenCenter && rowBottom >= screenCenter) {
        // Конвертираме към нов стил ако водещ е стар стил
        final bool oldIsLeading = AppSettings.oldStyleFirst;
        // return (AppSettings.isOldStyle && oldIsLeading)
        //     ? _toNewStyle(days[i])
        //     : days[i];
        
        // days[i] е по нов стил, но при водещ стар стил
        // показва се като стар стил — трябва да върнем нов стил
        // еквивалента на водещата (стара) дата
        return (AppSettings.isOldStyle && oldIsLeading)
            ? _toNewStyle(days[i])  // стар→нов за navigateToDate
            : days[i];              // вече е нов стил
      }
    }
    return null;
  }

  static DateTime _toNewStyle(DateTime d) => 
		DateTime.utc(d.year, d.month, d.day).add(const Duration(days: 13));
	static DateTime _toOldStyle(DateTime d) => 
		DateTime.utc(d.year, d.month, d.day).subtract(const Duration(days: 13));

  // Връща цвят според семантичния маркер от базата данни.
  // Базата казва 'red' или '#CC0000' — темата решава точния цвят.
  static Color _signColor(String? colorCode) {
    if (colorCode == AppColors.signRedHex) return AppColors.signRed;
    return AppColors.signWhite;
  }

  @override
  void initState() {
    super.initState();

    // Flash анимация — плавно изсветляване и изчезване (~1.5 сек)
    _flashController = AnimationController(
      duration: const Duration(milliseconds: 5000),
      vsync: this,
    );
    _flashAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 5),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.0), weight: 8),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 87),
    ]).animate(CurvedAnimation(
      parent: _flashController,
      curve: Curves.easeInOut,
    ));

    _loadMonth();

    // Първо появяване на табелата с месеца в дясно
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {}); // форсира изчисляване на табелата след първия рендер
    });

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
	void scrollToDate(DateTime date, {bool animated = true}) {
	  print('scrollToDate: $date, animated: $animated');
    if (_loading) {
		// Запазваме датата и скролираме след зареждане
		_pendingScrollDate = date;
    _pendingAnimated = animated;
		return;
	  }
	  _doScroll(date, animated: animated);
	}

  void _tryScrollToIndex(int index, {int attempts = 0}) {
    final rowKey = _rowKeys[index];
    if (rowKey?.currentContext != null) {
      final toolbarOffset = MediaQuery.of(context).padding.top 
          + AppSizes.toolbarHeight 
          + AppSizes.monthHeaderHeight;
      final listHeight = MediaQuery.of(context).size.height - toolbarOffset;
      final alignmentValue = toolbarOffset / MediaQuery.of(context).size.height + listHeight / 3 / MediaQuery.of(context).size.height;

      Scrollable.ensureVisible(
        rowKey!.currentContext!,
        alignment: alignmentValue,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    } else if (attempts < 10) {
      // Повтаряме докато редът се зареди — макс 10 опита по 100ms
      Future.delayed(const Duration(milliseconds: 100), () {
        _tryScrollToIndex(index, attempts: attempts + 1);
      });
    }
  }

	void _doScroll(DateTime date, {bool animated = true}) {
	  final bool oldIsLeading = !AppSettings.oldStyleFirst;
	  final DateTime leadingDate = (AppSettings.isOldStyle && oldIsLeading)
		  ? _toOldStyle(date)
		  : date;

	  final days = _getDaysToShow();
	  final index = days.indexWhere((d) =>
		  d.day == leadingDate.day &&
		  d.month == leadingDate.month &&
		  d.year == leadingDate.year);

    // print('date: $date');
    // print('leadingDate: $leadingDate');
    // print('index: $index / ${days.length}');
    // print('maxExtent: ${_scrollController.position.maxScrollExtent}');
    // print('approxOffset: ${(index / days.length) * _scrollController.position.maxScrollExtent}');
    // print('rowKey[$index] context: ${_rowKeys[index]?.currentContext}');

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
			//duration: const Duration(milliseconds: 400),
			duration: animated ? const Duration(milliseconds: 400) : Duration.zero,
      curve: Curves.easeInOut,
		  ).then((_){
        if (mounted) setState(() => _initialScrollDone = true);
      });
		} else {
			// Редът не е видим — приблизително скролиране първо
			final approxOffset = (index / days.length) *
				_scrollController.position.maxScrollExtent;
			_scrollController.jumpTo(
				approxOffset.clamp(0.0, _scrollController.position.maxScrollExtent));
			
      // Изчакваме ДВА frames вместо един — за да се рендерират новите редове
      WidgetsBinding.instance.addPostFrameCallback((_) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _tryScrollToIndex(index);
        });
      });
      // Future.delayed(const Duration(milliseconds: 100), () {
			//   final rowKey2 = _rowKeys[index];
			//   if (rowKey2?.currentContext != null) {
			// 	Scrollable.ensureVisible(
			// 	  rowKey2!.currentContext!,
			// 	  alignment: 0.33,
			// 	  duration: const Duration(milliseconds: 400),
			// 	  curve: Curves.easeInOut,
			// 	);
			//   }
			// });
		}
		// setState(() => _flashingDate = leadingDate);
		setState(() => _flashingDate = leadingDate);
		_flashController.forward(from: 0).then((_) {
		  if (mounted) setState(() => _flashingDate = null);
		});
	  });
	}

  // Презарежда данните за този месец от (новата) база, без да
  // премахва скрол позицията и без да пресъздава widget-а.
  // Извиква се при смяна на стар/нов стил от настройките.
  Future<void> reloadKeepingScroll() async {
    final savedOffset = _scrollController.hasClients
        ? _scrollController.offset
        : null;

    await _loadMonth(preserveScroll: true);

    if (savedOffset != null && _scrollController.hasClients) {
      // Възстановяваме позицията след презареждането на данните
      final maxExtent = _scrollController.position.maxScrollExtent;
      _scrollController.jumpTo(savedOffset.clamp(0.0, maxExtent));
    }
  }

  Future<void> _loadMonth({bool preserveScroll = false}) async {
    // При обикновено зареждане показваме спинъра.
    // При смяна на настройки (preserveScroll) не показваме спинър,
    // за да няма премигване — старите данни се виждат докато новите се зареждат.
    if (!preserveScroll) {
      setState(() => _loading = true);
    }
    final db = await DatabaseHelper.database;

    final rangeStart = DateTime(widget.year, widget.month, 1)
        .subtract(const Duration(days: 13));
    final rangeEnd = DateTime(widget.year, widget.month + 1, 0)
        .add(const Duration(days: 14)); // 13 + (1 ден за буфер) 

    final Map<String, List<Map<String, dynamic>>> cache = {};

    DateTime current = rangeStart;
    while (!current.isAfter(rangeEnd)) {
      final dateStr = current.toIso8601String().substring(0, 10);

      final saints = await db.rawQuery('''
        SELECT s.name, s.rank, s.sign, r.sign_color
        FROM saints s
        LEFT JOIN saint_ranks r ON s.rank = r.id
        LEFT JOIN saint_groups sg ON s.group_code = sg.code
        WHERE s.date = ?
        ORDER BY sg.id ASC, s.rank ASC
        LIMIT 3

      ''', [dateStr]);

      final dayResult = await db.rawQuery('''
        SELECT cd.*, sn.name as sunday_name, sn.tone as sunday_tone,
              w.name as week_name,
              fp.name as fast_period_name, ft.name as fast_type_name
        FROM calendar_days cd
        LEFT JOIN sundays sn ON cd.sunday_id = sn.id
        LEFT JOIN weeks w ON cd.week_id = w.id
        LEFT JOIN fast_periods fp ON cd.fast_period = fp.id
        LEFT JOIN fast_types ft ON cd.fast_type = ft.id
        WHERE cd.date = ?
      ''', [dateStr]);

      cache[dateStr] = [
        ...saints,
        if (dayResult.isNotEmpty &&
            dayResult.first['sunday_name'] != null &&
            (dayResult.first['sunday_name'] as String).trim().isNotEmpty)
          {
            '_sunday': dayResult.first['sunday_name'],
            '_tone': dayResult.first['sunday_tone'],
          },
        if (dayResult.isNotEmpty &&
            dayResult.first['week_name'] != null &&
            (dayResult.first['week_name'] as String).trim().isNotEmpty)
          {'_week': dayResult.first['week_name']},
        // ----- Добавяме и поста за всеки ден в месечния изглед --------
        if (dayResult.isNotEmpty) ...() {
            final fastPeriod = dayResult.first['fast_period_name'] as String? ?? '';
            final fastType   = dayResult.first['fast_type_name']   as String? ?? '';
            final fastText   = fastType.isNotEmpty 
                ? '$fastPeriod ($fastType)' 
                : fastPeriod;
            return fastText.trim().isNotEmpty
                ? [{
                    '_fast': fastText,
                    // id на постния период (2-5 = многодневните пости)
                    // за сивата ивица и плаващата табела вляво
                    '_fastId': dayResult.first['fast_period'],
                  }]
                : <Map<String, dynamic>>[];
          }(),
      ];

      current = current.add(const Duration(days: 1));
    }

		if (mounted) {
		  setState(() {
			_cache = cache;
			_loading = false;
		  });
      // Форсира изчисляване на плаващата табела след като редовете са рендерирани
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
		  if (!preserveScroll) {
			// Изпълняваме отложения скрол ако има такъв
			if (_pendingScrollDate != null) {
			  final pending = _pendingScrollDate!;
			  _pendingScrollDate = null;
			  WidgetsBinding.instance.addPostFrameCallback((_) => _doScroll(pending, animated: _pendingAnimated));
			}
			WidgetsBinding.instance.addPostFrameCallback((_) => _checkFlash());
		  }
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

  // Връща списък от (индекс на ред, име на справочния месец) за всяко
  // място, където започва нов справочен месец в дясната колона.
  // Ползва се от плаващата (sticky) табела със справочния месец.
  List<(int, String)> _refMonthBoundaries(List<DateTime> days) {
    final boundaries = <(int, String)>[];
    if (!AppSettings.isOldStyle) return boundaries;

    int? lastMonth;
    for (int i = 0; i < days.length; i++) {
      final refDate = _refDate(days[i]);
      if (lastMonth == null || refDate.month != lastMonth) {
        boundaries.add((i, widget.monthNamesShort[refDate.month]));
        lastMonth = refDate.month;
      }
    }
    return boundaries;
  }

  // ─── Постни периоди (лява ивица и табела) ────────────────────────────────

  // Еднодневни строги пости (нов стил: ден, месец) — винаги постни,
  // независимо от деня от седмицата. Посивяват се, но без табела.
  static const _singleFastDays = [
    (18, 1),  // Предпразненство на Богоявление
    (11, 9),  // Отсичане главата на св. Йоан Кръстител
    (27, 9),  // Въздвижение на Кръста Господен
  ];

  // Връща id на многодневния постен период (2-5) за деня, или null.
  int? _multiDayFastId(DateTime day) {
    final key = _cacheKey(day);
    final entries = _cache[key] ?? [];
    for (final e in entries) {
      final id = e['_fastId'];
      if (id is int && id >= 2 && id <= 5) return id;
    }
    return null;
  }

  // Дали денят е постен за целите на сивата ивица:
  // многодневен пост (2-5) или един от трите еднодневни строги поста.
  bool _isFastStripeDay(DateTime day) {
    if (_multiDayFastId(day) != null) return true;
    final bool oldIsLeading = !AppSettings.oldStyleFirst;
    final DateTime newStyle = (AppSettings.isOldStyle && oldIsLeading)
        ? _toNewStyle(day)
        : day;
    return _singleFastDays.contains((newStyle.day, newStyle.month));
  }

  // Връща списък от (начален индекс, краен индекс, име на поста) за
  // многодневните постни периоди, попадащи в този месец.
  // Ползва се от плаващата табела вляво.
  List<(int, int, String)> _fastPeriodBoundaries(List<DateTime> days) {
    final boundaries = <(int, int, String)>[];
    int? currentId;
    int startIndex = 0;

    for (int i = 0; i <= days.length; i++) {
      final id = i < days.length ? _multiDayFastId(days[i]) : null;
      if (id != currentId) {
        if (currentId != null) {
          // Затваряме предишния период
          final name = DatabaseHelper.fastPeriods[currentId] ?? '';
          boundaries.add((startIndex, i - 1, name.toLowerCase()));
        }
        currentId = id;
        startIndex = i;
      }
    }
    return boundaries;
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

    // Вече не се ползват — месецът се показва от плаващата табела
    // final DateTime firstRefDate = showOldStyle ? _refDate(days.first) : days.first;
    // final bool firstRowShowsMonth = showOldStyle &&
    //     (firstRefDate.month != widget.month || firstRefDate.year != widget.year);

    return Column(
      children: [
        // ─── Хедър ────────────────────────────────────────────────────
        Container(
          color: AppColors.appBarWeekday,
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
          child: Row(
            children: [
              if (showOldStyle) ...[ //--- слага иконките за църква и телевизор TV
                Icon(oldIsLeading ? Icons.church : Icons.live_tv,
                    color: AppColors.monthTextSecondary, size: 24),
                const SizedBox(width: 4),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(leftLabel, style: const TextStyle(
                        color: AppColors.monthTextSecondary,
                        fontSize: AppFonts.monthHeaderLabel,
                        height: 1.0)),
                    Text(leftLabel2, style: const TextStyle(
                        color: AppColors.monthTextSecondary,
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
                        color: AppColors.monthTextSecondary,
                        fontSize: AppFonts.monthHeaderLabel,
                        height: 1.0)),
                    Text(rightLabel2, style: const TextStyle(
                        color: AppColors.monthTextSecondary,
                        fontSize: AppFonts.monthHeaderLabel,
                        height: 1.0)),
                  ],
                ),
                const SizedBox(width: 4),
                Icon(oldIsLeading ? Icons.live_tv : Icons.church,
                    color: AppColors.monthTextSecondary, size: 24),
              ],
            ],
          ),
        ),

        // ─── Списък с дни ─────────────────────────────────────────────
        Expanded(
          child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Stack(
              key: _listStackKey,
              children: [
                Offstage(
                  offstage: !_initialScrollDone, //невидим докато не е позициониран
                  child: AnimatedOpacity(
                    opacity: _initialScrollDone ? 1.0 : 0.0,
                    duration: Duration.zero,
                    child: NotificationListener<ScrollEndNotification>(
                    onNotification: (notification) {
                      // Финално преизчисление на табелата след края на скрола
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) setState(() {});
                      });
                      return false; // пропускаме notification-а нагоре
                    },
                      child: ListView.separated(
                        controller: _scrollController,
                        cacheExtent: 2000, // ← рендерира 2000px извън видимата зона (bugfix)
                        padding: EdgeInsets.zero,
                        itemCount: days.length,
                        separatorBuilder: (context, index) =>
                            Divider(color: AppColors.sectionDivider, height: 1),
                        itemBuilder: (context, index) {
                          final day = days[index];
                          // Денят от седмицата е еднакъв по двата стила — взимаме от новостилната дата
                          final DateTime dbDate = (AppSettings.isOldStyle && oldIsLeading)
                            ? _toNewStyle(day)
                            : day;
                          final bool isSunday = dbDate.weekday == 7;
                          final String key = _cacheKey(day);
                          final saints = _cache[key] ?? [];
                          if (index >= 11 && index <= 13) {
                            //print('day: ${day.day}, key: $key, saints: ${saints.length}');
                          }
                          final DateTime refDate = _refDate(day);

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
                              child: IntrinsicHeight(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                // Постна ивица: посивява фона на реда при пост.
                                // Цветът се извежда от фона чрез придвижване към
                                // AppColors.fastStripeTint — така се адаптира към
                                // всяка тема и неделите остават различими.
                                // stretch + IntrinsicHeight → пълна височина на реда.
                                Container(
                                  width: 15, //ширина на посивената ивица за поста
                                  color: _isFastStripeDay(day)
                                    ? Color.lerp(rowColor, AppColors.fastStripeTint,
                                        AppColors.fastStripeAmount)
                                    : Colors.transparent,
                                ),
                                Expanded(
                                child: Padding(
                                padding: const EdgeInsets.only(
                                  top: 8, bottom: 8, right: 8),
                                child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                // Лява колона: водеща дата + ден от седмицата
                                SizedBox(
                                  width: 24,
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
                                      height: 1.2,  // <-- намалява разст. над текста
                                    )),
                                      // Фаза на луната — само при ключови фази
                                      Builder(builder: (context) {
                                        final keyPhase = MoonCalculator.keyPhaseForDay(dbDate);
                                        if (keyPhase == null) {
                                          return const SizedBox.shrink();
                                        }
                                        return Text(
                                          MoonCalculator.symbol(keyPhase, AppColors.moonColor, rowColor),
                                          style: const TextStyle(
                                            color: AppColors.moonColor,
                                            fontSize: 32, //MoonSize
                                          ),
                                          strutStyle: StrutStyle(
                                            fontSize: 32, // реже излишния padding
                                            height: 0.8,
                                            forceStrutHeight: true,
                                          )
                                        );
                                      }),
                                  ],
                                  ),
                                ),

                                // Средна колона: светии
                                Expanded(
                                  //child:ColoredBox(
                                  //color: Colors.red.withOpacity(0.2),
                                  child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 8),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                    // Наименование на седмицата — само в понеделник
                                    if (dbDate.weekday == 1)
                                      for (final s in saints)
                                      if (s['_week'] != null)
                                        Padding(
                                        padding: const EdgeInsets.only(bottom: 2),
                                        child: Text(
                                          s['_week'] as String,
                                          style: const TextStyle(
                                          color: AppColors.monthTextSecondary,
                                          fontSize: AppFonts.monthSaintName,
                                          fontStyle: FontStyle.italic,
                                          ),
                                        ),
                                        ),
                                    
                                    if (isSunday)
                                      for (final s in saints)
                                      // Изписва Неделята и гласа ----------------
                                      if (s['_sunday'] != null) ...[
                                        Text(
                                          s['_tone'] != null && 
                                          s['_tone'].toString().trim().isNotEmpty && 
                                          s['_tone'] != 0
                                              ? '† ${s['_sunday']}  Гл.${s['_tone']}'
                                              : '† ${s['_sunday']}',
                                          style: const TextStyle(
                                            color: AppColors.monthTitleSunday,
                                            fontSize: AppFonts.monthSundayName,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    // Изписва светиите за деня
                                    for (final s in saints)
                                      if (s['_sunday'] == null &&
                                          s['_week']   == null &&
                                          s['_fast']   == null)
                                      Builder(builder: (context) {
                                        final rank = s['rank'] as int? ?? 6;
                                        final (iconPath, iconColor) = AppIcons.forRank(rank);
                                        // Типокон - иконката се вгражда в текста като символ (WidgetSpan)
                                        return RichText(
                                          maxLines: 3, //максимален брой редове, след което: ...
                                          overflow: TextOverflow.ellipsis,    
                                          text: TextSpan(
                                            children: [
                                              if (iconPath != null)
                                                WidgetSpan(
                                                  alignment: PlaceholderAlignment.middle,
                                                  child: Padding(
                                                    padding: const EdgeInsets.only(right: 4, bottom: 2),
                                                    //padding: const EdgeInsets.only(bottom: 4),
                                                    child: SvgPicture.asset(
                                                      iconPath,
                                                      width:  18, // Размер на иконата (символа)
                                                      height: 18, // за празника според типикона
                                                      colorFilter: ColorFilter.mode(
                                                        iconColor ?? AppColors.signWhite,
                                                        BlendMode.srcIn,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              TextSpan(
                                                text: s['name'] as String,
                                                style: TextStyle(
                                                  color: s['rank'] == 0 ? AppColors.monthTextSecondary : iconColor ?? AppColors.signWhite,
                                                  fontSize: AppFonts.monthSaintName,
                                                  fontStyle:  s['rank'] == 0 ? FontStyle.italic : FontStyle.normal,
                                                  //fontWeight: s['rank'] == 0 ? FontWeight.bold : FontWeight.normal,
                                                ),
                                              ),
                                            ],
                                          ),
                                        );
                                      }),
                                    // Добавя накрая и поста за всеки ден
                                    for (final s in saints)
                                      if (s['_fast'] != null)
                                        Padding(
                                          padding: const EdgeInsets.only(top: 4, bottom: 0),
                                          child: SizedBox(
                                            width: double.infinity,
                                            child: Text(
                                              s['_fast'] as String,
                                              textAlign: TextAlign.center,
                                              style: const TextStyle(
                                                color: AppColors.textMuted,
                                                fontSize: AppFonts.monthSaintName,
                                                fontStyle: FontStyle.italic,
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                  ),
                                ),

                                // Дясна колона: справочна дата
                                // Месецът вече не се изписва тук — показва се
                                // от плаващата (sticky) табела вдясно.
                                if (showOldStyle)
                                  SizedBox(
                                  width: 32, //Ширина на дясната колона
                                  child: Align(
                                    alignment: Alignment.topLeft,
                                    child: SizedBox(
                                      width: 22,
                                      child: Text('${refDate.day}',
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                        color: AppColors.textMuted,
                                        fontSize: AppFonts.monthRefDate,
                                        )),
                                    ),
                                  ),
                                  ),
                                ],
                              ), // вътрешен Row (съдържание)
                              ), // Padding
                              ), // Expanded
                                ],
                              ), // външен Row (ивица + съдържание)
                              ), // IntrinsicHeight
                              );
                            },
                            ),
                          );
                        },
                      ),
                    ), // до тук
                  ),
                ),

                // ─── Плаваща (sticky) табела със справочния месец ────────
                // Не заема място в потока на редовете — рисува се върху тях.
                // AnimatedBuilder слуша _scrollController директно, така че
                // ListView НЕ се rebuild-ва при скрол → напълно гладко движение.
                if (showOldStyle && _initialScrollDone)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: AnimatedBuilder(
                        animation: _scrollController,
                        builder: (context, _) => _buildStickyMonthLabels(days),
                      ),
                    ),
                  ),

                // ─── Плаваща (sticky) табела с постния период (вляво) ────
                // Аналогична на месечната, но границата на избутване е
                // краят на самия постен период (постовете не граничат).
                if (_initialScrollDone)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: AnimatedBuilder(
                        animation: _scrollController,
                        builder: (context, _) => _buildStickyFastLabels(days),
                      ),
                    ),
                  ),
              ],
            ),
        ),
      ],
    );
  }

  // ─── Плаваща табела със справочния месец ────────────────────────────────
  // Изчислява позицията на всяка табела спрямо реалните позиции на редовете.
  // Табелата се "закача" горе, когато 1-во число на справочния месец излезе
  // над видимата зона, и се избутва плавно нагоре от следващата табела.
  Widget _buildStickyMonthLabels(List<DateTime> days) {
    if (!_scrollController.hasClients) return const SizedBox.shrink();

    final boundaries = _refMonthBoundaries(days);
    if (boundaries.isEmpty) return const SizedBox.shrink();

    // Височина на една буква + височина на цялата табела (3 букви)
    const double letterHeight = AppFonts.monthRefMonth * 1.15;
    const double labelHeight  = letterHeight * 3;

    // Горна граница на видимата зона на ListView (в локални координати)
    const double topLimit = 0.0;

    final listBox = _listStackKey.currentContext?.findRenderObject() as RenderBox?;
    if (listBox == null) return const SizedBox.shrink();

    final labels = <Widget>[];

    for (int b = 0; b < boundaries.length; b++) {
      final (rowIndex, monthName) = boundaries[b];

      final rowKey = _rowKeys[rowIndex];
      if (rowKey?.currentContext == null) continue;

      final rowBox = rowKey!.currentContext!.findRenderObject() as RenderBox?;
      if (rowBox == null) continue;

      // Позиция на реда спрямо ListView-а
      final rowTop = rowBox.localToGlobal(Offset.zero, ancestor: listBox).dy;

      // Позиция на СЛЕДВАЩАТА табела (за ефекта на избутване)
      double? nextTop;
      if (b + 1 < boundaries.length) {
        final nextKey = _rowKeys[boundaries[b + 1].$1];
        if (nextKey?.currentContext != null) {
          final nextBox = nextKey!.currentContext!.findRenderObject() as RenderBox?;
          if (nextBox != null) {
            nextTop = nextBox.localToGlobal(Offset.zero, ancestor: listBox).dy;
          }
        }
      }

      // Изчисляваме позицията:
      // 1. По подразбиране табелата стои залепена за своя ред
      // 2. Ако редът излезе над горната граница → табелата се закача горе
      // 3. Ако следващата табела наближи → бива избутана нагоре
      double top = rowTop + 8; //изравняване с числото
      if (top < topLimit) top = topLimit;
      if (nextTop != null && nextTop - labelHeight < top) {
        top = nextTop - labelHeight;
      }

      // Скриваме табели, които са напълно извън видимата зона
      final viewHeight = listBox.size.height;
      if (top + labelHeight < 0 || top > viewHeight) continue;

      labels.add(Positioned(
        right: 4, //разстояние в пиксели от дясната рамка на екрана
        top: top,
        child: SizedBox(
          width: 12,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: monthName.split('').map((c) => SizedBox(
              height: letterHeight,
              child: Text(c,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: AppFonts.monthRefMonth,
                  height: 1.0,
                ),
              ),
            )).toList(),
          ),
        ),
      ));
    }

    return Stack(children: labels);
  }

  // Проверява дали някой ред от диапазона е рендериран (видим или в кеша)
  bool _anyRowVisibleInRange(int start, int end) {
    for (int i = start; i <= end; i++) {
      if (_rowKeys[i]?.currentContext != null) return true;
    }
    return false;
  }

  // ─── Плаваща табела с постния период (вляво) ─────────────────────────────
  // Табелата стои в началото на постния период, закача се горе при скрол,
  // и бива избутана нагоре от КРАЯ на периода (последния му ред).
  Widget _buildStickyFastLabels(List<DateTime> days) {
    if (!_scrollController.hasClients) return const SizedBox.shrink();

    final periods = _fastPeriodBoundaries(days);
    if (periods.isEmpty) return const SizedBox.shrink();

    const double letterHeight = AppFonts.monthRefMonth * 1.15;
    const double topLimit = 0.0;

    final listBox = _listStackKey.currentContext?.findRenderObject() as RenderBox?;
    if (listBox == null) return const SizedBox.shrink();

    final labels = <Widget>[];

    for (final (startIndex, endIndex, name) in periods) {
      if (name.isEmpty) continue;

      // Височина на табелата зависи от дължината на името
      final double labelHeight = letterHeight * name.length;

      final startKey = _rowKeys[startIndex];
      final startBox = startKey?.currentContext?.findRenderObject() as RenderBox?;

      double startTop;
      if (startBox != null) {
        startTop = startBox.localToGlobal(Offset.zero, ancestor: listBox).dy + 8;
      } else {
        // Стартовият ред не е рендериран. Ако сме ВЪТРЕ в периода
        // (крайният ред е рендериран или още по-надолу) — табелата виси горе.
        // Ако целият период е далеч под нас — краят също не е рендериран,
        // но тогава и никоя част от периода не е видима.
        final anyVisible = _anyRowVisibleInRange(startIndex, endIndex);
        if (!anyVisible) continue;
        startTop = -999999; // все едно е далеч над екрана → ще се clamp-не на topLimit
      }

      //final startTop = startBox.localToGlobal(Offset.zero, ancestor: listBox).dy + 8;

      // Долна граница: краят (долният ръб) на последния ред от периода
      double? periodBottom;
      final endKey = _rowKeys[endIndex];
      if (endKey?.currentContext != null) {
        final endBox = endKey!.currentContext!.findRenderObject() as RenderBox?;
        if (endBox != null) {
          periodBottom = endBox.localToGlobal(Offset.zero, ancestor: listBox).dy
              + endBox.size.height;
        }
      }

      // Позициониране:
      // 1. По подразбиране табелата стои в началото на периода
      // 2. При скрол нагоре се закача на topLimit
      // 3. Краят на периода я избутва нагоре, когато наближи
      double top = startTop;
      if (top < topLimit) top = topLimit;
      if (periodBottom != null && periodBottom - labelHeight < top) {
        top = periodBottom - labelHeight;
      }

      final viewHeight = listBox.size.height;
      if (top + labelHeight < 0 || top > viewHeight) continue;

      labels.add(Positioned(
        left: 4, // залепена за левия ръб, върху сивата ивица
        top: top,
        //child: SizedBox(
          //width: 12,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: name.split('').map((c) => SizedBox(
              height: letterHeight,
              child: Text(c,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: AppFonts.monthRefMonth,
                  height: 1.0,
                ),
              ),
            )).toList(),
          ),
        //),
      ));
    }

    return Stack(children: labels);
  }
}
