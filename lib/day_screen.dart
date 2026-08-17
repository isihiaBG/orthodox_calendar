// day_screen.dart
//
// Дневният изглед — един ден от календара: заглавна лента с датите (стар
// и нов стил), седмица/неделя, глас, пост, списък със светиите (всеки
// разгъващ се към житие/тропари/служба — виж SaintExpandableTile) и
// разгъващите се секции с четивата.
//
// Изнесен от main.dart, където беше заедно с всичко останало. Там вече
// остават само старт на приложението, темата и превключването между
// дневен и месечен изглед (CalendarPageView).

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'app_settings.dart';
import 'app_theme.dart';
import 'database_helper.dart';
import 'fast_explanation_sheet.dart';
import 'mini_reader.dart';
import 'models/day_model.dart';
import 'saint_expandable_tile.dart';
import 'typikon_legend_sheet.dart';

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

class _DayScreenState extends State<DayScreen>
    with SingleTickerProviderStateMixin {
  CalendarDay? _day;
  List<Saint> _saints = [];
  bool _loading = true;

  /// Кой ред да просветне — идва от търсенето през
  /// [AppSettings.flashSaintId]. Изчиства се веднага щом се вземе, за да
  /// не мига пак при следващо отваряне на същия ден.
  int? _flashSaintId;
  late AnimationController _flashController;
  late Animation<double> _flashAnimation;

  @override
  void initState() {
    super.initState();
    // Същата крива като в месечния изглед: бързо светва, задържа се и
    // гасне бавно. Виж MonthScreen._flashAnimation — нарочно е еднаква,
    // за да е един и същ жестът, откъдето и да дойде човек.
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
    // Слуша за сигнал от търсенето. Проверката СЛЕД зареждането (в края
    // на _loadDay) покрива страница, която тепърва се строи; слушателят —
    // онази, която вече съществува в PageView и няма да мине пак през
    // initState. Нужни са и двете.
    AppSettings.flashSaintId.addListener(_checkFlash);
    _loadDay();
  }

  @override
  void dispose() {
    AppSettings.flashSaintId.removeListener(_checkFlash);
    _flashController.dispose();
    super.dispose();
  }

  /// Взима заявката за флаш, ако тя е за някой от светиите на ТОЗИ ден.
  ///
  /// ⚠ Проверката е нужна, защото дневният изглед живее в PageView и
  /// съседните страници се строят предварително. Без нея флашът щеше да
  /// се изяде от съседен ден, който човек дори не вижда.
  void _checkFlash() {
    if (!mounted) return;
    final id = AppSettings.flashSaintId.value;
    if (id == null) return;
    if (!_saints.any((s) => s.id == id)) return;
    // Изчиства се веднага: сигналът е за ЕДИН ден и не бива да мига пак
    // при следващо построяване, нито да го поеме друга страница.
    AppSettings.flashSaintId.value = null;
    setState(() => _flashSaintId = id);
    _flashController.forward(from: 0);
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

    // Текстовете живеят в прикачената база lives (виж DatabaseHelper).
    // Тук взимаме САМО евтините флагове — житието може да е 130 KB и няма
    // работа в дневната заявка. Пълните текстове се четат при тап.
    // Ред без slug няма партньор → LEFT JOIN дава NULL → флаговете са 0.
    final saintsResult = await db.rawQuery('''
    SELECT s.id, s.date, s.name, s.rank, s.group_code,
          r.sign, r.sign_color,
          -- Видовете песнопения с броя им, кодирани в едно поле:
          -- "tropar:3,kondak:5". Едно поле, а не колона за всеки вид —
          -- утрешен нов вид минава, без да се пипа заявката.
          (SELECT group_concat(kind || ':' || n, ',') FROM
             (SELECT kind, count(*) AS n FROM lives.hymns
              WHERE slug = s.slug GROUP BY kind)) AS hymn_counts,
          (l.life    IS NOT NULL AND l.life    != '') AS has_life,
          (l.sluzhba IS NOT NULL AND l.sluzhba != '') AS has_sluzhba
    FROM saints s
    LEFT JOIN saint_ranks r ON s.rank = r.id
    LEFT JOIN saint_groups sg ON s.group_code = sg.code
    LEFT JOIN lives.texts l ON l.slug = s.slug
    WHERE s.date = ?
    ORDER BY sg.id ASC, s.rank ASC, s.id ASC
    ''', [dateStr]);

    // Двете заявки по-горе са асинхронни — при бързо прелистване екранът
    // може да е напуснат, докато траят. Без тази проверка setState гърми
    // върху унищожен state ("setState() called after dispose()").
    if (!mounted) return;

    setState(() {
      _day = dayResult.isNotEmpty ? CalendarDay.fromMap(dayResult.first) : null;
      _saints = saintsResult.map((s) => Saint.fromMap(s)).toList();
      _loading = false;
    });

    // Чак сега — списъкът трябва да е налице, за да се провери дали
    // търсеният светия е от ТОЗИ ден.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _checkFlash();
    });
  }

  /// Пълните текстове на светия — зареждат се чак при тап върху секция.
  ///
  /// Името: календарното (българското, твоето) има предимство. Пада към
  /// това от lives.texts само ако календарният ред няма име — на практика
  /// при справочните записи без ред в календара (виж _lookupBySlug).
  Future<SaintTexts?> _loadSaintTexts(int id) async {
    final db = await DatabaseHelper.database;
    final r = await db.rawQuery('''
      SELECT COALESCE(NULLIF(s.name, ''), l.name) AS name,
             l.life, l.sluzhba, l.source, s.slug
      FROM saints s
      LEFT JOIN lives.texts l ON l.slug = s.slug
      WHERE s.id = ?
      LIMIT 1
    ''', [id]);
    if (r.isEmpty) return null;
    return SaintTexts.fromMap(r.first,
        hymns: await loadHymns((r.first['slug'] ?? '') as String));
  }

  /// Търсене по слъг — за saint:// линковете в житията.
  ///
  /// ТУК Е ПЕЧАЛБАТА ОТ ОТДЕЛНАТА БАЗА: тръгва се от lives.texts, не от
  /// календара. Досега линк към светия без календарен ред казваше "няма
  /// запис" — а такива са стотици: светогорците, които се честват само на
  /// подвижния съборен ден, и всички, към които житията препращат, без да
  /// са в тазгодишния календар.
  ///
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
    final bool oldFirst = !AppSettings.oldStyleFirst;
    
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
            InkWell(
              onTap: () => showFastExplanationSheet(
                context,
                day: _day!,
                saintsToday: _saints,
              ),
              child: Text(
                _fastText(_day!),
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.fastText, fontSize: 16),
              ),
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
              InkWell(
                onTap: () => showTypikonLegendSheet(context),
                customBorder: const CircleBorder(),
                child: SizedBox(
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

        // Просветване на реда, избран от търсенето. Обвива се целият
        // булет, не само името: така се вижда докъде се простира записът,
        // а разгъващият се компонент отдолу остава непокътнат.
        final tile = saint.id == _flashSaintId
            ? AnimatedBuilder(
                animation: _flashAnimation,
                builder: (context, child) => DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppColors.todayFlash
                        .withValues(alpha: _flashAnimation.value * 0.55),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: child,
                ),
                child: row,
              )
            : row;

        return SaintExpandableTile(
          collapsedRow: tile,
          hymnCounts: parseHymnCounts(saint.hymnCounts),
          hasLife: saint.hasLife,
          hasSluzhba: saint.hasSluzhba,
          lifeLabel: lifeLabelFor(rank: saint.rank, name: saint.name),
          loadTexts: () => _loadSaintTexts(saint.id),
          lookup: lookupBySlug,
        );
      }).toList(),
    );
  }

  
  DateTime get date => widget.date;

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    final bool isSunday = date.weekday == 7;

    return Container(
      color: isSunday ? AppColors.sundayBackground : null,
      child: CustomScrollView(
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
                  // Заявката тръгва при разгъване, не тук — MiniReader
                  // зарежда в initState, а ExpandableSection монтира
                  // съдържанието си чак когато е разгънато.
                  content: MiniReader(
                    load: () => DatabaseHelper.teofanThought(date),
                    emptyMessage:
                        'За този ден няма записани мисли от свт. Теофан '
                        'Затворник.',
                  ),
                ),
                ExpandableSection(
                  title: '⛪  ОТ ОПТИНСКИТЕ СТАРЦИ',
                  isSunday: isSunday,
                  content: MiniReader(
                    load: () => DatabaseHelper.optinaSaying(date),
                    // За разлика от Теофан тук всеки от 366-те дни има запис,
                    // тъй че това съобщение не бива да се показва никога.
                    // Види ли се, базата не се е отворила или е стара.
                    emptyMessage:
                        'За този ден няма записана сентенция от Оптинските '
                        'старци.',
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
      ),
    );
  }
}
