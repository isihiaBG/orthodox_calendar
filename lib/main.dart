import 'package:flutter/material.dart';
import 'database_helper.dart';
import 'models/day_model.dart';
import 'app_theme.dart';
import 'app_settings.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'settings_screen.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'search_screen.dart';
import 'month_screen.dart';
import 'saint_expandable_tile.dart';

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

  Widget _buildDrawer() {
    return Drawer(
      backgroundColor: AppColors.drawerBackground,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: BoxDecoration(color: AppColors.toolbar),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Image.asset('assets/icon_trans.png', width: 100, height: 100),
                const SizedBox(height: 0),
                const Text(
                  'Православен Календар',
                  style: TextStyle(color: AppColors.textPrimary, fontSize: 18),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 16, top: 8, bottom: 4),
            child: Text('ОСНОВНИ',
                style: TextStyle(color: AppColors.textMuted, fontSize: 11, letterSpacing: 1.5)),
          ),
          _drawerItem(Icons.calendar_month, 'Календар', () => Navigator.pop(context)),
          _drawerItem(Icons.auto_stories, 'Молитвослов', () {}),
          _drawerItem(Icons.book, 'Библия', () {}),
          _drawerItem(Icons.menu_book, 'Месецослов', () {}),
          _drawerItem(Icons.church, 'Празници', () {}),
          _drawerItemSvg('assets/icons/candle.svg', 'Дни за помени', () {}),
          _drawerItem(Icons.no_meals, 'Пости', () {}),
          _drawerItem(Icons.info_outline, 'Справочник', () {}),
          const Divider(color: AppColors.drawerDivider),
          Padding(
            padding: const EdgeInsets.only(left: 16, top: 4, bottom: 4),
            child: Text('ДРУГИ',
                style: TextStyle(color: AppColors.textMuted, fontSize: 11, letterSpacing: 1.5)),
          ),
          _drawerItem(Icons.settings, 'Настройки', () {
            Navigator.pop(context);
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => SettingsScreen(
                onChanged: _onSettingsChanged,
              )),
            ).then((_) => setState(() {}));
          }),
          _drawerItemText('❈', 'Оцени приложението', () {}),
          SafeArea(
            top: false,
            child: _drawerItem(Icons.help_outline, 'За приложението', () {}),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _drawerItem(IconData icon, String title, VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon, color: AppColors.drawerIcon, size: 26),
      title: Text(title, style: const TextStyle(color: AppColors.textPrimary, fontSize: 18)),
      onTap: onTap,
      dense: true,
    );
  }

  Widget _drawerItemSvg(String svgPath, String title, VoidCallback onTap) {
    return ListTile(
      leading: SvgPicture.asset(
        svgPath,
        width: 22,
        height: 22,
        colorFilter: ColorFilter.mode(AppColors.drawerIcon, BlendMode.srcIn),
      ),
      title: Text(title, style: const TextStyle(color: AppColors.textPrimary, fontSize: 18)),
      onTap: onTap,
      dense: true,
    );
  }

  Widget _drawerItemText(String symbol, String title, VoidCallback onTap) {
    return ListTile(
      leading: Text(symbol, style: TextStyle(color: AppColors.drawerIcon, fontSize: 30)),
      title: Text(title, style: const TextStyle(color: AppColors.textPrimary, fontSize: 18)),
      onTap: onTap,
      dense: true,
    );
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
      drawer: _buildDrawer(),
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
class ExpandableSection extends StatefulWidget {
  final String title;
  final Widget content;
  final bool initiallyExpanded;
  final bool isSunday;

  const ExpandableSection({
    super.key,
    required this.title,
    required this.content,
    this.initiallyExpanded = false,
    this.isSunday = false,
  });

  @override
  State<ExpandableSection> createState() => _ExpandableSectionState();
}

class _ExpandableSectionState extends State<ExpandableSection> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.isSunday
        ? AppColors.sectionTitleSunday
        : AppColors.sectionTitle;

    return Column(
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: AppColors.sectionDivider, width: 0.5),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: RichText(
                    text: TextSpan(
                      children: [
                        TextSpan(
                          text: widget.title.substring(0, 2),
                          style: const TextStyle(fontSize: 20),
                        ),
                        TextSpan(
                          text: widget.title.substring(2),
                          style: TextStyle(color: color, fontSize: 14, letterSpacing: 0.5),
                        ),
                      ],
                    ),
                  ),
                ),
                Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  color: color,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          child: _expanded
              ? Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: widget.content,
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

// ─── DayScreen ────────────────────────────────────────────────────────────
class DayScreen extends StatefulWidget {
  final DateTime date;
  const DayScreen({super.key, required this.date});

  @override
  State<DayScreen> createState() => _DayScreenState();
}

class _DayScreenState extends State<DayScreen> {
  CalendarDay? _day;
  List<Saint> _saints = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadDay();
  }

  Future<void> _loadDay() async {
    final db = await DatabaseHelper.database;
    final dateStr = widget.date.toIso8601String().substring(0, 10);

    final dayResult = await db.rawQuery('''
      SELECT cd.*, 
            w.name as week_name,
            w.note as week_note,
            s.name as sunday_name,
            s.note as sunday_note
      FROM calendar_days cd
      LEFT JOIN weeks w ON cd.week_id = w.id
      LEFT JOIN sundays s ON cd.sunday_id = s.id
      WHERE cd.date = ?
    ''', [dateStr]);

    final saintsResult = await db.rawQuery('''
    SELECT s.id, s.date, s.name, s.rank, s.group_code,
          r.sign, r.sign_color,
          (s.tropar IS NOT NULL AND s.tropar != '') AS has_tropar,
          (s.kondak IS NOT NULL AND s.kondak != '') AS has_kondak,
          (s.life   IS NOT NULL AND s.life   != '') AS has_life,
          (s.sluzhba IS NOT NULL AND s.sluzhba != '') AS has_sluzhba
    FROM saints s
    LEFT JOIN saint_ranks r ON s.rank = r.id
    LEFT JOIN saint_groups sg ON s.group_code = sg.code
    WHERE s.date = ?
    ORDER BY sg.id ASC, s.rank ASC
    ''', [dateStr]);

    setState(() {
      _day = dayResult.isNotEmpty ? CalendarDay.fromMap(dayResult.first) : null;
      _saints = saintsResult.map((s) => Saint.fromMap(s)).toList();
      _loading = false;
    });
  }

  /// Пълните текстове на светия — зареждат се чак при тап върху секция.
  Future<SaintTexts?> _loadSaintTexts(int id) async {
    final db = await DatabaseHelper.database;
    final r = await db.query('saints',
        columns: ['name', 'tropar', 'tropar_trans', 'tropar2',
                  'tropar2_trans', 'kondak', 'kondak_trans', 'kondak2',
                  'kondak2_trans', 'life', 'sluzhba', 'source', 'slug'],
        where: 'id = ?', whereArgs: [id], limit: 1);
    if (r.isEmpty) return null;
    return SaintTexts.fromMap(r.first);
  }

  /// Търсене по слъг — за saint:// линковете в житията.
  Future<SaintTexts?> _lookupBySlug(String slug) async {
    final db = await DatabaseHelper.database;
    final r = await db.query('saints',
        columns: ['name', 'tropar', 'tropar_trans', 'tropar2',
                  'tropar2_trans', 'kondak', 'kondak_trans', 'kondak2',
                  'kondak2_trans', 'life', 'sluzhba', 'source', 'slug'],
        where: 'slug = ?', whereArgs: [slug], limit: 1);
    if (r.isEmpty) return null;
    return SaintTexts.fromMap(r.first);
  }

  String _toneText(int tone) {
    const tones = ['', '1', '2', '3', '4', '5', '6', '7', '8'];
    return 'Глас\u00A0${tone < tones.length ? tones[tone] : tone.toString()}';
  }

  String _fastText(CalendarDay day) {
    final period = DatabaseHelper.fastPeriods[day.fastPeriod] ?? '';
    final type = DatabaseHelper.fastTypes[day.fastType] ?? '';
    if (type.isEmpty) return period;
    return '$period ($type)';
  }

  // Връща цвят според семантичния маркер от базата данни.
  // Базата казва 'red' или '#CC0000' — темата решава точния цвят.
  Color _signColor(String? colorCode) {
    if (colorCode == AppColors.signRedHex) return AppColors.signRed;
    return AppColors.signWhite;
  }

  DateTime _toOldStyle(DateTime date) => date.subtract(const Duration(days: 13));

  String _dayMonth(DateTime date) {
    const months = ['', 'яну', 'фев', 'март', 'апр', 'май', 'юни',
        'юли', 'авг', 'сеп', 'окт', 'ное', 'дек'];
    return '${date.day} ${months[date.month]}';
  }

  String _weekDayName(DateTime date) {
    const weekDays = ['', 'ПОНЕДЕЛНИК', 'ВТОРНИК', 'СРЯДА',
        'ЧЕТВЪРТЪК', 'ПЕТЪК', 'СЪБОТА', 'НЕДЕЛЯ'];
    return weekDays[date.weekday];
  }

  Widget _buildHeader() {
    final bool isSunday = date.weekday == 7;
    final Color headerColor = isSunday ? AppColors.appBarSunday : AppColors.appBarWeekday;
    final String periodName = isSunday
        ? (_day?.fullSundayName ?? '')
        : (_day?.fullWeekName ?? '');

    final DateTime oldDate = _toOldStyle(date);
    
    // Определяме лява и дясна дата според oldStyleFirst
    final bool showOldStyle = AppSettings.isOldStyle;
    final bool oldFirst = AppSettings.oldStyleFirst;
    
    // Лява дата = водещата
    final DateTime leftDate  = (showOldStyle && !oldFirst) ? oldDate : date;
    final DateTime rightDate = (showOldStyle && !oldFirst) ? date : oldDate;
    final String leftLabel   = showOldStyle ? (oldFirst ? 'нов стил' : 'стар стил') : '';
    final String rightLabel  = showOldStyle ? (oldFirst ? 'стар стил' : 'нов стил') : '';

    return Container(
      width: double.infinity,
      color: headerColor,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              const double minCenterWidth = 80.0;

              return Column(
                children: [
                  // Ред 1: надписи ляво / ден от седмицата / дясно
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Text(
                          leftLabel,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                        ),
                      ),
                      ConstrainedBox(
                        constraints: BoxConstraints(minWidth: minCenterWidth),
                        child: Text(
                          _weekDayName(date),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Color.fromARGB(179, 255, 255, 255),
                            fontSize: 18,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          rightLabel,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  // Ред 2: дати и година
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      // Ляво — иконка (църква/телевизор) + дата
                      Expanded(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            if (showOldStyle)
                              // Padding(
                              //   padding: const EdgeInsets.only(right: 10, top: 0),
                              Transform.translate(
                                offset: const Offset(-10, -3), // -3 => нагоре с 3 пиксела
                                child: Icon(
                                  oldFirst ? Icons.live_tv : Icons.church,
                                  color: AppColors.textPrimary,
                                  size: 24, // Църква/Телевизор
                                ),
                              ),
                            Text(
                              showOldStyle ? _dayMonth(leftDate) : '',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 18,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Център — година
                      ConstrainedBox(
                        constraints: BoxConstraints(minWidth: minCenterWidth),
                        child: Text(
                          showOldStyle
                              ? (!oldFirst ? _toOldStyle(date).year.toString() : date.year.toString())
                              : '${_dayMonth(date)}  ${date.year}',
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      // Дясно — дата + иконка (телевизор/църква)
                      Expanded(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Text(
                              showOldStyle ? _dayMonth(rightDate) : '',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 18,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            if (showOldStyle)
                              //Padding(
                                //padding: const EdgeInsets.only(left: 10, top: 0),
                              Transform.translate(
                                offset: const Offset(10, -3), // -3 => нагоре с 3 пиксела
                                child: Icon(
                                  oldFirst ? Icons.church : Icons.live_tv,
                                  color: AppColors.textPrimary,
                                  size: 24, // Църква/Телевизор
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 4),
          if (_day != null) ...[
            Text(
              periodName.isNotEmpty
                  ? (isSunday // ако е неделя ще сложи † кръстче
                      ? '† $periodName${_day!.tone > 0 ? '. ${_toneText(_day!.tone)}' : ''}'
                        // а в обикновен седмичен ден ще бъде без † кръстче
                      : '$periodName${_day!.tone > 0 ? '. ${_toneText(_day!.tone)}' : ''}')
                  : (_day!.tone > 0 ? _toneText(_day!.tone) : ''),
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 16),
            ),
            const SizedBox(height: 2),
            Text(
              _fastText(_day!),
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.fastText, fontSize: 16),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSaintsList() {
    if (_saints.isEmpty) {
      return Center(
        child: Text('Няма данни за този ден',
            style: TextStyle(color: AppColors.textMuted)),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: _saints.map((saint) {
        final (iconPath, iconColor) = AppIcons.forRank(saint.rank ?? 6);

        // Редът както досега — знак + име (визуално непроменен)
        final row = Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 24,
                height: 24,
                child: iconPath != null
                    ? SvgPicture.asset(
                        iconPath,
                        width: 19,
                        height: 19,
                        colorFilter: ColorFilter.mode(
                          iconColor ?? AppColors.signWhite,
                          BlendMode.srcIn,
                        ),
                      )
                    : Center(
                        child: Text(
                          '•',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Text(
                    saint.name,
                    style: TextStyle(
                      fontSize: 16,
                      color:      saint.rank == 0 ? AppColors.monthTextSecondary : iconColor ?? AppColors.signWhite,
                      fontStyle:  saint.rank == 0 ? FontStyle.italic : FontStyle.normal,
                      fontWeight: saint.rank == 0 ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );

        return SaintExpandableTile(
          collapsedRow: row,
          hasTropar: saint.hasTropar,
          hasKondak: saint.hasKondak,
          hasLife: saint.hasLife,
          hasSluzhba: saint.hasSluzhba,
          loadTexts: () => _loadSaintTexts(saint.id),
          lookup: _lookupBySlug,
        );
      }).toList(),
    );
  }

  
  DateTime get date => widget.date;

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    final bool isSunday = date.weekday == 7;

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: _buildHeader()),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSaintsList(),
                const SizedBox(height: 8),
                ExpandableSection(
                  title: '📖  ЕВАНГЕЛИЕ И АПОСТОЛ',
                  isSunday: isSunday,
                  content: const Text(
                    'Тук ще се показват евангелските и апостолски четива за деня.',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 15, height: 1.6),
                  ),
                ),
                ExpandableSection(
                  title: '🕯️  ТРОПАРИ И КОНДАЦИ',
                  isSunday: isSunday,
                  content: const Text(
                    'Тук ще се показват тропарите и кондаците за деня.',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 15, height: 1.6),
                  ),
                ),
                ExpandableSection(
                  title: '📜  МИСЛИ ОТ ТЕОФАН ЗАТВОРНИК',
                  isSunday: isSunday,
                  content: const Text(
                    'Тук ще се показват мислите на Св. Теофан Затворник за деня.',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 15, height: 1.6),
                  ),
                ),
                ExpandableSection(
                  title: '⛪  ОТ ОПТИНСКИТЕ СТАРЦИ',
                  isSunday: isSunday,
                  content: const Text(
                    'Тук ще се показват изреченията от Оптинските старци.',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 15, height: 1.6),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
