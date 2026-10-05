// „Справка за деня" — дневният изглед в изскачащ прозорец отдолу (90% от
// екрана), без да се напуска Молитвословът. Отваря се от реда най-отгоре в
// „Богослужебни" и от плаващото копче в четеца (указание на потребителя,
// 05.10.2026): при четене на часовете тропарите и кондаците на деня са на
// един тап.
//
// ⚠ Дневният изглед е СЪЩИЯТ `DayScreen` като в календара — не преписан и не
// орязан, за да не се разминат двете при първата промяна. Различна е само
// лентата: стрелка назад (затваря прозореца) вместо меню, „днес" и избор на
// дата; плъзгането между дните е като в календара.

import 'package:flutter/material.dart';

import 'app_settings.dart';
import 'app_theme.dart';
import 'database_helper.dart';
import 'day_screen.dart';
import 'search_screen.dart';

/// Изборът на дата — същият вид като в календара (main.dart).
Future<DateTime?> pickCalendarDate(BuildContext context,
    {required DateTime initial, required DateTime first, required DateTime last}) async {
  final picked = await showDatePicker(
    context: context,
    helpText: AppSettings.isOldStyle && AppSettings.oldStyleFirst
        ? 'Изберете дата по нов стил'
        : null,
    initialDate: initial.isBefore(first) ? first : (initial.isAfter(last) ? last : initial),
    firstDate: first,
    lastDate: last,
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
  return picked == null ? null : DateTime(picked.year, picked.month, picked.day);
}

/// Отваря справката за деня — изскачащ прозорец отдолу, на 90% от екрана.
Future<void> showDayReference(BuildContext context) async {
  final h = MediaQuery.of(context).size.height;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    // Ивицата с чертичката — като при препратките в Часослова: хващане за
    // затваряне и горен ръб, който не се слива с потъмнения фон.
    builder: (_) => SizedBox(
      height: h * 0.9,
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        child: Column(children: [
          Container(
            width: double.infinity,
            color: AppColors.backgroundCard,
            padding: const EdgeInsets.only(top: 10, bottom: 8),
            alignment: Alignment.center,
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                  color: AppColors.textMuted, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const Expanded(child: DayReference()),
        ]),
      ),
    ),
  );
}

class DayReference extends StatefulWidget {
  const DayReference({super.key});

  @override
  State<DayReference> createState() => _DayReferenceState();
}

class _DayReferenceState extends State<DayReference> {
  DateTime? _start;
  int _total = 0;
  PageController? _pages;
  late DateTime _current;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _current = DateTime(now.year, now.month, now.day);
    _load();
  }

  /// Границите идват от базата (както в календара след уточняването им);
  /// дотогава — въртележка, за да не се строи PageView с временни граници.
  Future<void> _load() async {
    await DatabaseHelper.database;
    final min = DatabaseHelper.dataMinDate, max = DatabaseHelper.dataMaxDate;
    if (!mounted || min == null || max == null) return;
    final start = DateTime.utc(min.year, min.month, min.day);
    final end = DateTime.utc(max.year, max.month, max.day);
    setState(() {
      _start = start;
      _total = end.difference(start).inDays + 1;
      _pages = PageController(initialPage: _pageFor(_current));
    });
  }

  @override
  void dispose() {
    _pages?.dispose();
    super.dispose();
  }

  DateTime _dateFor(int page) {
    final d = _start!.add(Duration(days: page));
    return DateTime(d.year, d.month, d.day);
  }

  int _pageFor(DateTime d) => DateTime.utc(d.year, d.month, d.day)
      .difference(_start!)
      .inDays
      .clamp(0, _total - 1);

  void _goTo(DateTime d) {
    final c = _pages;
    if (c == null || !c.hasClients) return;
    final target = _pageFor(d);
    // Близко — с плъзгане; далече — направо (иначе се прелистват месеци).
    if ((target - (c.page ?? 0)).abs() <= 7) {
      c.animateToPage(target,
          duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
    } else {
      c.jumpToPage(target);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = _pages;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.toolbar,
        toolbarHeight: AppSizes.toolbarHeight,
        titleSpacing: 0,
        automaticallyImplyLeading: false,
        // Стрелка назад вместо меню — затваря прозореца.
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          tooltip: 'Назад',
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Справка за деня',
            style: TextStyle(color: AppColors.textPrimary, fontSize: 17)),
        actions: [
          // Търсенето — същото като в календара; избраният резултат
          // прелиства ТУК, не в календара отзад.
          IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            tooltip: 'Търсене',
            icon: const Icon(Icons.search, color: AppColors.textPrimary, size: 24),
            onPressed: _start == null
                ? null
                : () => showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      useSafeArea: true,
                      backgroundColor: Colors.transparent,
                      builder: (_) => SearchBottomSheet(
                        onDateSelected: (d) => _goTo(DateTime(d.year, d.month, d.day)),
                      ),
                    ),
          ),
          IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            tooltip: 'Днес',
            icon: const Icon(Icons.today, color: AppColors.textPrimary, size: 24),
            onPressed: () {
              final now = DateTime.now();
              _goTo(DateTime(now.year, now.month, now.day));
            },
          ),
          IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            tooltip: 'Избери дата',
            icon: const Icon(Icons.calendar_month, color: AppColors.textPrimary, size: 24),
            onPressed: _start == null
                ? null
                : () async {
                    final d = await pickCalendarDate(context,
                        initial: _current,
                        first: _dateFor(0),
                        last: _dateFor(_total - 1));
                    if (d != null) _goTo(d);
                  },
          ),
          const SizedBox(width: 10),
        ],
      ),
      body: pages == null
          ? const Center(child: CircularProgressIndicator())
          : PageView.builder(
              controller: pages,
              itemCount: _total,
              onPageChanged: (p) => _current = _dateFor(p),
              itemBuilder: (context, index) => DayScreen(
                key: ValueKey('ref_${AppSettings.isOldStyle}_$index'),
                date: _dateFor(index),
              ),
            ),
    );
  }
}

/// Редът „Справка за деня" — най-отгоре в „Богослужебни" и в плаващото
/// копче. Под името — днешната дата, за да личи, че води към календара.
class DayReferenceRow extends StatelessWidget {
  /// Вика се преди отварянето (плаващото копче първо затваря себе си).
  final VoidCallback? beforeOpen;
  const DayReferenceRow({super.key, this.beforeOpen});

  static const _months = ['януари', 'февруари', 'март', 'април', 'май', 'юни', 'юли',
      'август', 'септември', 'октомври', 'ноември', 'декември'];

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          final nav = Navigator.of(context);
          beforeOpen?.call();
          showDayReference(nav.context);
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Справка за деня',
                    style: TextStyle(color: AppColors.textPrimary, fontSize: 17)),
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text('Днес, ${now.day} ${_months[now.month - 1]}',
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                ),
              ]),
            ),
            const Icon(Icons.calendar_month, color: AppColors.sectionTitle),
          ]),
        ),
      ),
    );
  }
}
