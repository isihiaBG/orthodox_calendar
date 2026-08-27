// welcome_screen.dart
//
// Посрещането: по кой стил да се чете календарът.
//
// Показва се при стартиране, докато човек не го изключи — от чекбокса тук
// или от суича в настройките. И двете пипат AppSettings.showWelcome.
//
// ЗАЩО ГО ИМА. Изборът на стил е първото решение, което календарът иска от
// човека, а дотогава той стоеше скрит в настройките: приложението мълчаливо
// избираше вместо него и го посрещаше с таблица от числа. По-честно е да се
// попита направо — и по-хубаво като първо впечатление.
//
// Устроен е като „Месецослов" НАРОЧНО: същото тесте корици, същото
// разположение, същият градиент отдолу. Скелетът е общ
// (cover_picker.dart), тъй че двата екрана не могат да се разминат.
//
// CalendarStyleOption/kCalendarStyleOptions по-долу са ПУБЛИЧНИ (21.08.2026)
// — освен тук ги ползва и мащабираният picker в настройките
// (calendar_style_picker.dart), тъй че списъкът с корици/имена/бележки да
// не се дублира на две места и да не се разминава.

import 'package:flutter/material.dart';

import 'app_settings.dart';
import 'app_drawer.dart';
import 'app_theme.dart';
import 'book_open_transition.dart';
import 'cover_flow.dart';
import 'cover_picker.dart';

/// Един стил на четене — корица и какво значи.
class CalendarStyleOption {
  final String cover;
  final String name;
  final String note;

  /// Стойностите, които изборът записва. Двете заедно дават трите
  /// смислени подредби (четвъртата — нов стил с водеща стара дата — няма
  /// смисъл и затова я няма).
  final bool isOldStyle;
  final bool oldStyleFirst;

  const CalendarStyleOption({
    required this.cover,
    required this.name,
    required this.note,
    required this.isOldStyle,
    required this.oldStyleFirst,
  });
}

const List<CalendarStyleOption> kCalendarStyleOptions = [
  CalendarStyleOption(
    cover: 'assets/calendar_covers/Cover_01.jpg',
    name: 'Нов стил',
    note: 'Празниците са по Григорианския календар. '
        'Показва се само нов стил.',
    isOldStyle: false,
    oldStyleFirst: false,
  ),
  CalendarStyleOption(
    cover: 'assets/calendar_covers/Cover_02.jpg',
    name: 'Стар стил',
    note: 'Празниците вървят по Юлианския календар, '
        'а водеща датата отпред е гражданската.',
    isOldStyle: true,
    oldStyleFirst: false,
  ),
  CalendarStyleOption(
    cover: 'assets/calendar_covers/Cover_03.jpg',
    name: 'Стар стил',
    note: 'Водеща е църковната дата, а гражданската стои справочно след нея. '
        'По-трудно е за ориентиране.',
    isOldStyle: true,
    oldStyleFirst: true,
  ),
];

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  final GlobalKey<CoverFlowState> _flow = GlobalKey<CoverFlowState>();

  /// Тестето се отваря на стила, който е нагласен в момента — човек вижда
  /// къде се намира, а не започва отначало.
  late int _index = _currentIndex();

  bool _dontShowAgain = false;
  bool _opening = false;

  int _currentIndex() {
    final i = kCalendarStyleOptions.indexWhere((s) =>
        s.isOldStyle == AppSettings.isOldStyle &&
        (!s.isOldStyle || s.oldStyleFirst == AppSettings.oldStyleFirst));
    return i < 0 ? 0 : i;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    for (final s in kCalendarStyleOptions) {
      precacheImage(AssetImage(s.cover), context);
    }
  }

  /// Прилага избора — без анимация, само настройките.
  void _apply(int i) {
    final s = kCalendarStyleOptions[i];
    AppSettings.isOldStyle = s.isOldStyle;
    AppSettings.oldStyleFirst = s.oldStyleFirst;
    AppSettings.showWelcome = !_dontShowAgain;
    // Записва се веднага, не с отлагане: оттук се излиза и екранът се
    // разрушава, тъй че отложен запис би могъл да не се случи.
    AppSettings.saveNow();
  }

  /// Избраната корица политва към човека, пелената почернява, а изпод нея се
  /// открива календарът — същото движение, с което се отварят том в
  /// „Месецослов" и дял в „Библия".
  ///
  /// ⚠ ТУК механизмът е ДРУГ, макар движението да е същото. Онези два екрана
  /// правят `push` и остават в стека, тъй че могат сами да карат хода. Този
  /// прави `pop` и се РАЗРУШАВА по средата — негови контролери не биха
  /// доживели вдигането на пелената. Затова слоят е самоуправляващ се
  /// ([SelfDrivenCoverLaunch]): живее в `rootOverlay`, кара се сам и сменя
  /// екрана отдолу в мига, в който пелената е плътна.
  void _choose(int i) {
    if (_opening) return;
    setState(() => _opening = true);

    final rect = _flow.currentState?.centerCoverRect();
    if (rect == null) {
      // Без геометрия няма какво да лети — прилагаме направо, вместо да
      // оставим човека пред екран, който не отговаря.
      _apply(i);
      Navigator.of(context).pop(true);
      return;
    }

    // ⚠ И двете се взимат ПРЕДИ анимацията: подир `pop` този контекст вече
    // не е валиден, а слоят трябва да се махне точно тогава.
    final nav = Navigator.of(context);
    final overlay = Overlay.of(context, rootOverlay: true);

    OverlayEntry? entry;
    entry = OverlayEntry(
      builder: (_) => SelfDrivenCoverLaunch(
        from: rect,
        cover: AssetImage(kCalendarStyleOptions[i].cover),
        onCovered: () {
          _apply(i);
          nav.pop(true);
        },
        onDone: () {
          entry?.remove();
          entry = null;
        },
      ),
    );
    overlay.insert(entry!);
  }

  @override
  Widget build(BuildContext context) {
    return CoverPickerScaffold(
      title: 'Изберете календар',
      covers: [for (final s in kCalendarStyleOptions) AssetImage(s.cover)],
      index: _index,
      onIndexChanged: (i) => setState(() => _index = i),
      onOpen: _choose,
      flowKey: _flow,
      // ⚠ Хамбургер вместо ✕ — по-спокойно е за окото и е същото копче,
      // каквото стои във всяка друга секция. Екранът е стартов, но НЕ е
      // единственият: той е върху календара, тъй че менюто има къде да води.
      drawer: const AppDrawer(),
      infoBuilder: (_, i) => _info(i),
      landscapeLabel: (i) => kCalendarStyleOptions[i].name,
      extra: _checkbox(),
    );
  }

  Widget _info(int i) {
    final s = kCalendarStyleOptions[i];
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 4),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            s.name,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 26,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            s.note,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: () => _choose(i),
            icon: const Icon(Icons.check, size: 18),
            label: const Text('Отвори календара'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.sectionTitle,
              foregroundColor: Colors.white,
              padding:
                  const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  /// Тикването се ЗАПИСВА ВЕДНАГА.
  ///
  /// ⚠ Дотук се записваше само заедно с избора на стил, с довода „да няма
  /// състояние «изключен екран без избран стил»". Доводът не издържа: стил
  /// ВИНАГИ има — или запазен, или подразбиращият се, — тъй че такова
  /// състояние не съществува. Затова пък се губеше нещо истинско: човек
  /// тиква чекбокса, излиза през менюто (или ✕) без да избира, и желанието
  /// му изчезва мълчаливо.
  ///
  /// ⚠ Полярността е ОБРАТНА: `_dontShowAgain == true` значи
  /// `AppSettings.showWelcome == false`.
  void _setDontShow(bool v) {
    setState(() => _dontShowAgain = v);
    AppSettings.showWelcome = !v;
    // Веднага на диска: оттук се излиза и екранът се разрушава, тъй че
    // отложен запис може и да не се случи.
    AppSettings.saveNow();
  }

  Widget _checkbox() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        onTap: () => _setDontShow(!_dontShowAgain),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 22,
                height: 22,
                child: Checkbox(
                  value: _dontShowAgain,
                  onChanged: (v) => _setDontShow(v ?? false),
                  side: const BorderSide(
                      color: AppColors.textSecondary, width: 1.4),
                  checkColor: Colors.white,
                  activeColor: AppColors.sectionTitle,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                'Не показвай повече',
                style: TextStyle(
                    color: AppColors.textSecondary, fontSize: 14),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
