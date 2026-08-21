// reference_pager.dart
//
// Домакинът на четирите справочни секции от главното меню — "Празници",
// "Дни за помени", "Пости" и "Справочник". Устроен е като дневния изглед
// (виж CalendarPageView в main.dart): Scaffold-ът, лентата и двата drawer-а
// стоят НЕПОДВИЖНИ, а PageView-ът сменя само тялото. Така плъзгането
// настрани мести секцията, без лентата да подскача.
//
// Какво живее тук (а не в самите секции):
//  - ГОДИНАТА — обща за трите секции, които имат такава. Пази се само в
//    паметта на този екран, НЕ в потребителските настройки: справочна е.
//    Понеже екранът се създава наново при влизане отвън, годината сама се
//    нулира до текущата — а разходката между секциите (плъзгане ИЛИ през
//    менюто, виж ReferencePager.open) не пресъздава нищо и я запазва.
//  - РАЗМЕРЪТ НА ШРИФТА — общ за четирите секции и запазван на диска
//    (за разлика от годината, това е предпочитание, не справка).
//  - Реакцията на смяна на стила (стар/нов) — секциите получават
//    `revision` и се преизчисляват, когато то се промени.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_drawer.dart';
import 'app_theme.dart';
import 'calendar_style_picker.dart';
import 'fasts_screen.dart';
import 'holidays_screen.dart';
import 'memorial_days_screen.dart';
import 'reference_book_screen.dart';
import 'round_icon_button.dart';
import 'saint_expandable_tile.dart' show lookupBySlug;
import 'settings_screen.dart';

enum ReferenceSection { holidays, memorial, fasts, book }

const List<String> _sectionTitles = [
  'Празници',
  'Дни за помени',
  'Пости',
  'Справочник',
];

class ReferencePager extends StatefulWidget {
  final ReferenceSection initial;
  const ReferencePager({super.key, required this.initial});

  /// Отваря секцията. Ако екранът ВЕЧЕ е отворен (човекът е в някоя от
  /// четирите и избира друга през менюто), само прелиства до нея — така
  /// избраната година оцелява. Иначе се бута нов екран, отгоре на
  /// календара, и годината започва от текущата.
  static Future<void> open(BuildContext context, ReferenceSection section) {
    final active = _ReferencePagerState._active;
    if (active != null && active.mounted) {
      active._jumpTo(section);
      return Future.value();
    }
    final navigator = Navigator.of(context);
    navigator.popUntil((route) => route.isFirst);
    return navigator.push(MaterialPageRoute(
      builder: (_) => ReferencePager(initial: section),
    ));
  }

  @override
  State<ReferencePager> createState() => _ReferencePagerState();
}

class _ReferencePagerState extends State<ReferencePager> {
  /// Текущо живият екран — нужен на ReferencePager.open, за да разпознае
  /// "вече сме вътре" и да прелисти, вместо да пресъздава.
  static _ReferencePagerState? _active;

  // ─── Шрифт (общ за четирите секции, пази се на диска) ────────────────
  // Стойностите са същите като в предишните отделни екрани; ключът е нов
  // и общ, защото размерът вече не е поотделно за "Празници" и "Пости".
  static double _baseFont = 17.0;
  static const double _fontStep = 1.0;
  static const double _fontMin = 13.0;
  static const double _fontMax = 26.0;
  static const String _fontKey = 'reference_font_size';
  static bool _fontLoadedFromDisk = false;
  static double? _lastSavedFont;
  Timer? _fontSaveTimer;

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  late final PageController _controller =
      PageController(initialPage: widget.initial.index);

  late int _page = widget.initial.index;

  /// Годината — обща за секциите, които имат такава. Само в паметта.
  int _year = DateTime.now().year;

  /// Расте при всяка промяна на настройките; секциите го следят и
  /// преизчисляват датите си (стар/нов стил ги мени).
  int _revision = 0;

  @override
  void initState() {
    super.initState();
    _active = this;
    _loadPersistedFontOnce().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    if (_active == this) _active = null;
    if (_fontSaveTimer != null) {
      _fontSaveTimer!.cancel();
      _flushFontSave();
    }
    _controller.dispose();
    super.dispose();
  }

  static Future<void> _loadPersistedFontOnce() async {
    if (_fontLoadedFromDisk) return;
    _fontLoadedFromDisk = true;
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getDouble(_fontKey);
    if (saved != null) {
      _baseFont = saved.clamp(_fontMin, _fontMax);
      _lastSavedFont = _baseFont;
    }
  }

  /// Записът чака 3 сек. покой — човек обикновено цъка няколко пъти,
  /// докато намери размера.
  void _scheduleFontSave() {
    _fontSaveTimer?.cancel();
    _fontSaveTimer = Timer(const Duration(seconds: 3), _flushFontSave);
  }

  void _flushFontSave() {
    _fontSaveTimer = null;
    if (_lastSavedFont == _baseFont) return;
    _lastSavedFont = _baseFont;
    SharedPreferences.getInstance()
        .then((prefs) => prefs.setDouble(_fontKey, _baseFont));
  }

  void _bumpFont(double delta) {
    setState(() => _baseFont = (_baseFont + delta).clamp(_fontMin, _fontMax));
    _scheduleFontSave();
  }

  void _jumpTo(ReferenceSection section) {
    if (!_controller.hasClients) return;
    _controller.animateToPage(
      section.index,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
    );
  }

  void _onYearChanged(int year) => setState(() => _year = year);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: AppColors.toolbar,
      drawer: const AppDrawer(),
      onEndDrawerChanged: (isOpen) {
        if (isOpen) return;
        // При затваряне преизчисляваме — стилът може да е сменен, а
        // датите в секциите са кеширани. Флъш ПРЕДИ това — ако графичният
        // избор на стил чака отлагането си (CalendarStylePicker),
        // затварянето не бива да го остави да увисне цяла секунда след
        // като панелът вече не се вижда.
        flushPendingCalendarStylePick?.call();
        if (mounted) setState(() => _revision++);
      },
      endDrawer: SettingsDrawer(
        sections: const {SettingsSection.calendar},
        onChanged: (styleChanged, [capturedMiddleDate]) {
          appSettingsChangedHook?.call(styleChanged, capturedMiddleDate);
          if (mounted) setState(() => _revision++);
        },
      ),
      appBar: AppBar(
        backgroundColor: AppColors.toolbar,
        toolbarHeight: 44,
        title: Text(_sectionTitles[_page]),
        actions: [
          RoundIconButton(
            icon: Icons.remove,
            tooltip: 'По-дребен шрифт',
            enabled: _baseFont > _fontMin,
            onTap: () => _bumpFont(-_fontStep),
            size: 22,
          ),
          const SizedBox(width: 18),
          RoundIconButton(
            icon: Icons.add,
            tooltip: 'По-едър шрифт',
            enabled: _baseFont < _fontMax,
            onTap: () => _bumpFont(_fontStep),
            size: 22,
          ),
          const SizedBox(width: 14),
          IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            icon: const Icon(Icons.settings,
                color: AppColors.textPrimary, size: 24),
            onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Container(
          color: AppColors.background,
          // Спира в двата края (без превъртане в кръг) — стандартното
          // поведение на PageView, изрично потвърдено от потребителя.
          child: PageView(
            controller: _controller,
            onPageChanged: (i) => setState(() => _page = i),
            children: [
              HolidaysSection(
                lookup: lookupBySlug,
                year: _year,
                onYearChanged: _onYearChanged,
                baseFont: _baseFont,
                revision: _revision,
              ),
              MemorialDaysSection(
                year: _year,
                onYearChanged: _onYearChanged,
                baseFont: _baseFont,
                revision: _revision,
              ),
              FastsSection(
                lookup: lookupBySlug,
                year: _year,
                onYearChanged: _onYearChanged,
                baseFont: _baseFont,
                revision: _revision,
              ),
              ReferenceBookSection(baseFont: _baseFont),
            ],
          ),
        ),
      ),
    );
  }
}
