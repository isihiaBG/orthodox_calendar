import 'package:flutter/material.dart';
import 'database_helper.dart';
import 'models/day_model.dart';
import 'app_theme.dart';
import 'app_settings.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'settings_screen.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'search_screen.dart';

//import 'package:logger/logger.dart';

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
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.appBarWeekday,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: AppColors.background,
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
  //final _logger = Logger();  // ← тук
  final DateTime _startDate = DateTime.utc(2026, 1, 1);
  final int _totalDays = 365;
  late PageController _pageController;
  late int _currentPage;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    final today = DateTime.now();
		_currentPage = DateTime.utc(today.year, today.month, today.day)
			.difference(DateTime.utc(_startDate.year, _startDate.month, _startDate.day))
			.inDays;
    _pageController = PageController(initialPage: _currentPage);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  DateTime _dateForPage(int page) {
    final d = _startDate.add(Duration(days: page));
    return DateTime(d.year, d.month, d.day); // нормализираме без часове
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
                Image.asset('assets/icon.png', width: 64, height: 64),
                const SizedBox(height: 8),
                const Text(
                  'Православен Календар',
                  style: TextStyle(
                    color: AppColors.textPrimary, fontSize: 18),
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
						MaterialPageRoute(builder: (_) => const SettingsScreen()),
					  ).then((_) {
						setState(() {}); // презарежда CalendarPageView
					  });
					}),
          //_drawerItem(Icons.star, 'Оцени приложението', () {}),
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
      title: Text(title, style: const TextStyle(
        color: AppColors.textPrimary, fontSize: 18)),
      onTap: onTap,
      dense: true,
    );
  }
	Widget _drawerItemText(String symbol, String title, VoidCallback onTap) {
	  return ListTile(
		leading: Text(
		  symbol,
		  style: TextStyle(
        color: AppColors.drawerIcon, fontSize: 30),
		),
		title: Text(title, style: const TextStyle(
      color: AppColors.textPrimary, fontSize: 18)),
		onTap: onTap,
		dense: true,
	  );
	}

	void _showSearch(BuildContext context) {
	  showModalBottomSheet(
		context: context,
		isScrollControlled: true,
		backgroundColor: Colors.transparent,
		builder: (_) => SearchBottomSheet(
		  onDateSelected: (date) {
			final page = DateTime.utc(date.year, date.month, date.day)
				.difference(DateTime.utc(_startDate.year, _startDate.month, _startDate.day))
				.inDays;
			_pageController.animateToPage(
			  page,
			  duration: const Duration(milliseconds: 300),
			  curve: Curves.easeInOut,
			);
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
      endDrawer: SettingsDrawer(onChanged: () => setState(() {})),
      appBar: AppBar(
        backgroundColor: AppColors.toolbar,
        toolbarHeight: 40,
        leading: IconButton(
          icon: const Icon(Icons.menu, color: AppColors.textPrimary, size: 28),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
				actions: [
          IconButton(
            icon: const Icon(Icons.search, color: AppColors.textPrimary, size: 24),
            onPressed: () => _showSearch(context),
          ),
					IconButton(
					  icon: const Icon(Icons.today, color: AppColors.textPrimary, size: 24),
					  onPressed: () {
						final today = DateTime.now();
						final page = DateTime.utc(today.year, today.month, today.day)
							.difference(DateTime.utc(_startDate.year, _startDate.month, _startDate.day))
							.inDays;
						_pageController.animateToPage(
						  page,
						  duration: const Duration(milliseconds: 300),
						  curve: Curves.easeInOut,
						);
					  },
					),
					IconButton(
					  icon: const Icon(Icons.calendar_month, color: AppColors.textPrimary, size: 24),
					  onPressed: () async {
						final picked = await showDatePicker(
						  context: context,
						  initialDate: _dateForPage(_currentPage),
						  firstDate: _startDate,
						  lastDate: _startDate.add(Duration(days: _totalDays - 1)),
						);
						if (picked != null) {
							final page = DateTime.utc(picked.year, picked.month, picked.day)
								.difference(DateTime.utc(_startDate.year, _startDate.month, _startDate.day))
								.inDays;
							_pageController.jumpToPage(page);
						}
					  },
					),
				  IconButton(
					icon: const Icon(Icons.settings, color: AppColors.textPrimary, size: 24),
					onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
				  ),
				],
      ),
			body: PageView.builder(
			  key: ValueKey(AppSettings.isOldStyle),
			  controller: _pageController,
			  onPageChanged: (page) => setState(() => _currentPage = page),
			  itemCount: _totalDays,
			  itemBuilder: (context, index) => DayScreen(
				key: ValueKey('${AppSettings.isOldStyle}_$index'),
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
										  text: widget.title.substring(0, 2), // емоджито
										  style: TextStyle(fontSize: 20),
										),
										TextSpan(
										  text: widget.title.substring(2), // останалия текст
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
      SELECT s.*, r.sign, r.sign_color
      FROM saints s
      LEFT JOIN saint_ranks r ON s.rank = r.id
      WHERE s.date = ?
      ORDER BY s.rank ASC
    ''', [dateStr]);

    setState(() {
      _day = dayResult.isNotEmpty ? CalendarDay.fromMap(dayResult.first) : null;
      _saints = saintsResult.map((s) => Saint.fromMap(s)).toList();
      _loading = false;
    });
  }

  String _toneText(int tone) {
    //const tones = ['', '1-ви', '2-ри', '3-ти', '4-ти', '5-ти', '6-ти', '7-ми', '8-ми'];
    const tones = ['', '1', '2', '3', '4', '5', '6', '7', '8'];
    return 'Глас ${tone < tones.length ? tones[tone] : tone.toString()}';
  }

	String _fastText(CalendarDay day) {
	  final period = DatabaseHelper.fastPeriods[day.fastPeriod] ?? '';
	  final type = DatabaseHelper.fastTypes[day.fastType] ?? '';

	  if (type.isEmpty) return period;
	  return '$period ($type)';
	}

  Color _signColor(String? hexColor) {
    if (hexColor == AppColors.signRedHex) return AppColors.signRed;
    return AppColors.signWhite;
  }

  // Изчислява датата по стар стил (- 13 дни)
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

    // Датата по стар стил (само при стар стил)
    final DateTime oldDate = _toOldStyle(date);

    return Container(
      width: double.infinity,
      color: headerColor,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
      child: Column(
				mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
					// Използваме LayoutBuilder за да синхронизираме двата реда
					LayoutBuilder(
					  builder: (context, constraints) {
						// Изчисляваме ширината на средната колона
						// (колкото е нужно за деня от седмицата, но минимум 80)
						const double minCenterWidth = 80.0;
						//final totalWidth = constraints.maxWidth;

						return Column(
						  children: [
							// Ред 1: надписи нов стил / ден от седмицата / стар стил
							Row(
							  crossAxisAlignment: CrossAxisAlignment.end,
							  children: [
								Expanded(
								  child: Text(
									AppSettings.isOldStyle ? 'нов стил' : '',
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
									AppSettings.isOldStyle ? 'стар стил' : '',
									textAlign: TextAlign.center,
									style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
								  ),
								),
							  ],
							),
							const SizedBox(height: 2),
							// Ред 2: дати и година — същата структура
							Row(
							  crossAxisAlignment: CrossAxisAlignment.baseline,
							  textBaseline: TextBaseline.alphabetic,
							  children: [
								Expanded(
								  // --- Ляво -----------
                  child: Text(
									AppSettings.isOldStyle ? _dayMonth(date) : '',
									textAlign: TextAlign.center,
									style: const TextStyle(
									  color: AppColors.textPrimary,
									  fontSize: 18,
									  fontWeight: FontWeight.w500,
									),
								  ),
								),
								ConstrainedBox(
								  constraints: BoxConstraints(minWidth: minCenterWidth),
								  child: Text(
									AppSettings.isOldStyle 
										? date.year.toString() 
										: '${_dayMonth(date)}  ${date.year}',
									textAlign: TextAlign.center,
									maxLines: 1,  // ← добави
									overflow: TextOverflow.ellipsis,  // ← добави
									style: const TextStyle(
									  color: Colors.white,
									  fontSize: 18,
									  fontWeight: FontWeight.w500,
									),
								  ),
								),
								Expanded(
								  // --- Дясно -------------
								  child: Text(
									AppSettings.isOldStyle ? _dayMonth(oldDate) : '',
									textAlign: TextAlign.center,
									style: const TextStyle(
									  color: AppColors.textPrimary,
									  fontSize: 18,
									  fontWeight: FontWeight.w500,
									),
								  ),
								),
							  ],
							),
						  ],
						);
					  },
					),
          const SizedBox(height: 4),
          // Ред 2: седмица/неделя + глас
          if (_day != null) ...[
            Text(
              periodName.isNotEmpty
                ? (_day!.tone > 0 ? '$periodName. ${_toneText(_day!.tone)}' : periodName)
                : (_day!.tone > 0 ? _toneText(_day!.tone) : ''),

              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 16),
            ),
            const SizedBox(height: 2),
            // Ред 3: пост (центриран)
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
      children: _saints.map((saint) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 6, right: 10),
              child: Icon(Icons.circle, size: 8, color: _signColor(saint.signColor)),
            ),
            Expanded(
              child: Text(
                '${saint.sign ?? ''}${saint.sign != null ? ' ' : ''}${saint.name}',
                style: TextStyle(fontSize: 16, color: _signColor(saint.signColor)),
              ),
            ),
          ],
        ),
      )).toList(),
    );
  }

  DateTime get date => widget.date;

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    final bool isSunday = date.weekday == 7;

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: _buildHeader(),
        ),
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
                  title: '⛪  ИЗРЕЧЕНИЯ ОТ ОПТИНСКИТЕ СТАРЦИ',
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
