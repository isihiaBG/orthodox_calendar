import 'package:flutter/material.dart';
import 'database_helper.dart';
import 'app_theme.dart';
import 'app_settings.dart';
import 'settings_screen.dart';
import 'app_drawer.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'search_screen.dart';
import 'day_screen.dart';
import 'month_screen.dart';

void main() {
  runApp(const OrthodoxCalendarApp());
}

class OrthodoxCalendarApp extends StatelessWidget {
  const OrthodoxCalendarApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Православен Календар',
      debugShowCheckedModeBanner: false,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('bg', 'BG'),
        Locale('en', 'US'),
      ],
      locale: const Locale('bg', 'BG'),
			theme: ThemeData(
			  useMaterial3: true,
			  scaffoldBackgroundColor: AppColors.background,
			  colorScheme: const ColorScheme.dark(
          primary: AppColors.sectionTitle,
        ),
        progressIndicatorTheme: ProgressIndicatorThemeData(
          color:   AppColors.sectionTitle,
        ),
        visualDensity: VisualDensity.compact ,
			  iconButtonTheme: IconButtonThemeData(
				style: ButtonStyle(
				  padding: WidgetStateProperty.all(
					  const EdgeInsets.symmetric(horizontal: 2)),
				  minimumSize: WidgetStateProperty.all(const Size(36, 36)),
				),
			  ),
			),
      home: const CalendarPageView(),
    );
  }
}

class CalendarPageView extends StatefulWidget {
  const CalendarPageView({super.key});

  @override
  State<CalendarPageView> createState() => _CalendarPageViewState();
}

class _CalendarPageViewState extends State<CalendarPageView> {
  // _startDate и _totalDays НЕ са вече final константи — стартират с
  // точни временни граници (изчислени синхронно, мигновено), а после
  // тихо се коригират в background с реалните граници от базата
  // (DatabaseHelper.dataMinDate/dataMaxDate), без потребителят да забележи.
  late DateTime _startDate;
  late int _totalDays;
  late PageController _pageController;
  late int _currentPage;
  late DateTime _currentDate;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  bool _isMonthView = false;
  final GlobalKey<MonthScreenState> _monthScreenKey = GlobalKey<MonthScreenState>();
  //int _settingsVersion = 0; //ползвах я в опит да обновява екрана при промяна, но намерих по-добро решение

  @override
  void initState() {
    super.initState();
    final today = DateTime.now();

    // Точни временни граници за мигновен старт, преди реалните данни
    // от базата да са известни: 1 януари [текуща година] минус 14 дни,
    // до 31 декември [текуща година] плюс 14 дни. 14-дневният буфер
    // съответства точно на изместването стар/нов стил (13-14 дни),
    // покривайки коректно и преходния период около Нова година.
    final currentYear = today.year;
    _startDate = DateTime.utc(currentYear, 1, 1).subtract(const Duration(days: 14));
    final tempEnd = DateTime.utc(currentYear, 12, 31).add(const Duration(days: 14));
    _totalDays = tempEnd.difference(_startDate).inDays + 1;

    _currentPage = DateTime.utc(today.year, today.month, today.day)
        .difference(DateTime.utc(_startDate.year, _startDate.month, _startDate.day))
        .inDays;
    _currentDate = _dateForPage(_currentPage);
    _pageController = PageController(initialPage: _currentPage);

    // Background — зарежда реалната база (бързо, тъй като вече е на
    // диска от предишно стартиране) и заменя временните граници с
    // точните MIN/MAX от calendar_days, тихо, без потребителят да
    // забележи (освен ако точно в този миг се опита да превърти
    // отвъд временната граница — много рядък случай).
    // print('today: ${DateTime.now()}');
    // print('_startDate: $_startDate');
    // print('_currentPage: $_currentPage');
    // print('_currentDate: $_currentDate');


    _refineDateBoundsFromDatabase();

    // Менюто вече е общо за всички екрани (виж app_drawer.dart) и може да
    // бъде отворено и от вторичен екран. Реакцията при промяна на
    // настройките обаче живее ТУК (нуждае се от състоянието на календара —
    // страници, контролер), затова я регистрираме като hook.
    appSettingsChangedHook = _onSettingsChanged;
  }

  Future<void> _refineDateBoundsFromDatabase() async {
    await DatabaseHelper.database; // гарантира, че границите са изчислени
    final minDate = DatabaseHelper.dataMinDate;
    final maxDate = DatabaseHelper.dataMaxDate;
    
    if (minDate == null || maxDate == null) return;
    
    final newStart = DateTime.utc(minDate.year, minDate.month, minDate.day);
    final newEnd = DateTime.utc(maxDate.year, maxDate.month, maxDate.day);
    final newTotalDays = newEnd.difference(newStart).inDays + 1;
    
    // Ако границите вече съвпадат — нищо за правене.
    if (newStart == _startDate && newTotalDays == _totalDays) return;

    // Запазваме потребителя визуално на същия ден, само индексите
    // се преизчисляват спрямо новата (по-точна) начална точка.
    final dateBeforeUpdate = _currentDate;
    final wasMonthView = _isMonthView;

    setState(() {
      _startDate = newStart;
      _totalDays = newTotalDays;
    });

    

    if (!wasMonthView) {
      final newPage = DateTime.utc(
              dateBeforeUpdate.year, dateBeforeUpdate.month, dateBeforeUpdate.day)
          .difference(_startDate)
          .inDays
          .clamp(0, _totalDays - 1);
      // Пресъздаваме контролера тихо, без анимация, на същата дата.
      _pageController.dispose();
      _pageController = PageController(initialPage: newPage);
      setState(() => _currentPage = newPage);
      // print('refineBounds: newStart=$newStart, dateBeforeUpdate=$dateBeforeUpdate, newPage=$newPage');
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  DateTime _dateForPage(int page) {
    final d = _startDate.add(Duration(days: page));
    return DateTime(d.year, d.month, d.day);
  }

  int _pageForDate(DateTime date) {
    return DateTime.utc(date.year, date.month, date.day)
        .difference(DateTime.utc(_startDate.year, _startDate.month, _startDate.day))
        .inDays;
  }

  // Изчислява целевата страница при смяна на стила
  // При смяна стар→нов: +13 дни; нов→стар: -13 дни
  // При смяна само на oldStyleFirst: без промяна
  void _onSettingsChanged(bool styleChanged) {
    if (styleChanged) {
			final date = _dateForPage(AppSettings.currentPage);
      int targetPage;
      if (AppSettings.isOldStyle) {
        // Преминахме КЪМ стар стил → -13 дни
        targetPage = _pageForDate(date.subtract(const Duration(days: 13)));
      } else {
        // Преминахме КЪМ нов стил → +13 дни
        targetPage = _pageForDate(date.add(const Duration(days: 13)));
      }
      targetPage = targetPage.clamp(0, _totalDays - 1);
      setState(() {});
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _pageController.jumpToPage(_currentPage);
      });
      // Презареждаме месечния изглед с новата база — без да губим
      // скрол позицията и без премигване (старите данни се виждат
      // докато новите се заредят в кеша).
      _monthScreenKey.currentState?.refreshAfterSettingsChange();
      // Преизчисляваме границите за новата база (стар/нов стил могат
      // да имат различен реален обхват от данни).
      _refineDateBoundsFromDatabase();
    } else {
      // Смяна на oldStyleFirst — запазваме средния ден на екрана
      // и навигираме до съответния ден по новия водещ стил (без флаш)
      if (_isMonthView) {
        final middleDate = _monthScreenKey.currentState?.getMiddleDate();
        setState(() {
          if (middleDate != null) _currentDate = middleDate;
        });
        if (middleDate != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _monthScreenKey.currentState?.navigateToDate(middleDate, flash: true);
          });
        }
      } else {
        setState(() {});
      }
    }
  }


  // Флаг за пропускане на първото onPageChanged след превключване от месечен към дневен изглед
  bool _skipNextPageChange = false;

  // Централизирана навигация до дата — работи и в дневен и в месечен изглед
  // Обновява _currentDate при всяка навигация
  void _navigateToDate(DateTime date, {bool flash = true}) {
    setState(() => _currentDate = date);
    if (_isMonthView) {
      _monthScreenKey.currentState?.navigateToDate(date, flash: flash);
    } else {
      final page = DateTime.utc(date.year, date.month, date.day)
          .difference(DateTime.utc(_startDate.year, _startDate.month, _startDate.day))
          .inDays;
      _pageController.animateToPage(
        page.clamp(0, _totalDays - 1),
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _showSearch(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SearchBottomSheet(
        onDateSelected: (date) {
          // Навигираме до избраната дата и обновяваме _currentDate
          _navigateToDate(DateTime(date.year, date.month, date.day));
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      drawer: const AppDrawer(),
      onEndDrawerChanged: (isOpen) {
        if (!isOpen) setState(() {});
      },
      endDrawer: SettingsDrawer(onChanged: _onSettingsChanged),
      appBar: AppBar(
        backgroundColor: AppColors.toolbar,
        toolbarHeight:   AppSizes.toolbarHeight, // 40 >> височина на toolbar-а 
        titleSpacing: 0,
        // ================ Меню бутон =================
        leading: IconButton(
          icon: const Icon(Icons.menu, color: AppColors.textPrimary, size: 28),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        actions: [
          // ================ Месец | Ден превключвател =================
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Бутон МЕСЕЦ — превключва към месечен изглед и флашва текущата дата
                GestureDetector(
                  onTap: () {
                    if (!_isMonthView) {
                      setState(() => _isMonthView = true);
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        _monthScreenKey.currentState?.navigateToDate(_currentDate, flash: true, animated: false);
                      });
                    }
                  },
                  child: Text('Месец',
                    style: TextStyle(
                      color: _isMonthView ? AppColors.textPrimary : AppColors.textMuted,
                      fontSize: 15,
                      fontWeight: _isMonthView ? FontWeight.bold : FontWeight.normal,
                    )),
                ),
                Text('  |  ',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 15)),
                // Бутон ДЕН — превключва към дневен изглед
                GestureDetector(
                  onTap: () {
                    if (_isMonthView) {
                      // Пресъздаваме контролера на правилната страница от _currentDate
                      final page = _pageForDate(_currentDate).clamp(0, _totalDays - 1);
                      _pageController.dispose();
                      _pageController = PageController(initialPage: page);
                      setState(() {
                        _isMonthView = false;
                        _currentPage = page;
                      });
                    }
                  },
                  child: Text('Ден',
                    style: TextStyle(
                      color: !_isMonthView ? AppColors.textPrimary : AppColors.textMuted,
                      fontSize: 15,
                      fontWeight: !_isMonthView ? FontWeight.bold : FontWeight.normal,
                    )),
                ),
              ],
            ),
          ),
          // ================ Търсене =================
          IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            icon: const Icon(Icons.search, color: AppColors.textPrimary, size: 24),
            onPressed: () => _showSearch(context),
          ),
          // ================ Днес Бутон =================
          IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            icon: const Icon(Icons.today, color: AppColors.textPrimary, size: 24),
            onPressed: () {
              final today = DateTime.now();
              final todayDate = DateTime(today.year, today.month, today.day);
              // Централизирана навигация — обновява _currentDate автоматично
              _navigateToDate(todayDate, flash: true);
            },
          ),
          // ================ Дата Пикър =================
          IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            icon: const Icon(Icons.calendar_month, color: AppColors.textPrimary, size: 24),
            onPressed: () async {
              final picked = await showDatePicker(
                context: context,
                helpText: AppSettings.isOldStyle && !AppSettings.oldStyleFirst
                    ? 'Изберете дата по нов стил'
                    : null,
                initialDate: _currentDate,
                // initialDate: _isMonthView
                //     ? (_monthScreenKey.currentState?.currentDate ?? _dateForPage(_currentPage))
                //     : _dateForPage(_currentPage),
                firstDate: _startDate,
                lastDate: _startDate.add(Duration(days: _totalDays - 1)),
                builder: (context, child) {
                  return Theme(
                    data: Theme.of(context).copyWith(
                      colorScheme: ColorScheme.dark(
                        primary: AppColors.datePickerPrimary,
                        onPrimary: AppColors.datePickerOnPrimary,
                        surface: AppColors.datePickerSurface,
                        onSurface: AppColors.datePickerOnSurface,
                        secondary: AppColors.datePickerPrimary,
                      ),
                      dialogBackgroundColor: AppColors.datePickerBackground,
                      textButtonTheme: TextButtonThemeData(
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.datePickerButtons, // цвят на ОТКАЗ и ОК
                        ),
                      ),
                    ),
                    child: child!,
                  );
                },
              );
              if (picked != null) {
                final pickedDate = DateTime(picked.year, picked.month, picked.day);
                // Централизирана навигация — обновява _currentDate автоматично
                _navigateToDate(pickedDate, flash: true);
              }
            },
          ),
          // ================ Настройки =================
          IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            icon: const Icon(Icons.settings, color: AppColors.textPrimary, size: 24),
            onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
          ),
        ],
      ),
      body: _isMonthView
          ? MonthScreen(
              key: _monthScreenKey,
							initialDate: _isMonthView 
								? (_monthScreenKey.currentState?.currentDate ?? _dateForPage(_currentPage))
								: _dateForPage(_currentPage),
              
              onDateSelected: (date) {
                // Навигираме до избрания ден и обновяваме _currentDate.
                // Важно: ползваме _dateForPage след clamp за да е сигурно
                // че _currentDate е валидна дата от базата (не извън границите).
                // Това оправя бъга при клик на дата извън базата — дневният
                // изглед правилно ни поставя на последния валиден ден, и при
                // връщане в месечен изглед се хайлайтва именно той.
                final page = DateTime.utc(date.year, date.month, date.day)
                    .difference(DateTime.utc(_startDate.year, _startDate.month, _startDate.day))
                    .inDays;
                final clampedPage = page.clamp(0, _totalDays - 1);
                setState(() {
                  _isMonthView = false;
                  _currentDate = _dateForPage(clampedPage); // винаги валидна дата
                  _currentPage = clampedPage;
                  _skipNextPageChange = true; // пропускаме onPageChanged
                });
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _pageController.jumpToPage(clampedPage);
                });
              },
            )
          : PageView.builder(
              //key: ValueKey(AppSettings.isOldStyle),
              key: ValueKey('${AppSettings.isOldStyle}_${_startDate.millisecondsSinceEpoch}'),
              controller: _pageController,
              onPageChanged: (page) {
                // Пропускаме първото извикване след превключване от месечен към дневен
                if (_skipNextPageChange) {
                  _skipNextPageChange = false;
                  return;
                }
                final newDate = _dateForPage(page);
                // Обновяваме само ако датата реално се е сменила от потребителя
                setState(() {
                  _currentPage = page;
                  _currentDate = newDate; // синхронизираме _currentDate
                  AppSettings.currentPage = page;
                });
              },
              itemCount: _totalDays,
              itemBuilder: (context, index) => DayScreen(
                key: ValueKey('\${AppSettings.isOldStyle}_\$index'),
                date: _dateForPage(index),
              ),
            ),
    );
  }
}

// ─── Разгъваща се секция ───────────────────────────────────────────────────
