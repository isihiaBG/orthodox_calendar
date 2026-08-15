// app_drawer.dart
//
// Главното меню на приложението — ОБЩО за всички екрани, които го
// показват (календара, "Празници", "За приложението"…). По-рано живееше
// само в main.dart и затова вторичните екрани имаха само стрелка "назад";
// сега всеки от тях може да отвори менюто директно и да скочи в друг
// раздел, без да минава обратно през календара.

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'about_screen.dart';
import 'app_settings.dart';
import 'app_theme.dart';
import 'library_screen.dart';
import 'reference_pager.dart';
import 'settings_screen.dart';

/// Реакцията на календара при промяна в настройките (смяна на стил и др.)
/// живее в състоянието на CalendarPageView — то се регистрира тук при
/// стартиране (виж main.dart). Така менюто може да я задейства и когато е
/// отворено от вторичен екран, без да има пряка връзка с календара.
typedef SettingsChangedHook = void Function(bool styleChanged,
    [DateTime? capturedMiddleDate]);
SettingsChangedHook? appSettingsChangedHook;

class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  /// Затваря менюто и се връща до календара (първия екран в стека), ако в
  /// момента сме навътре в някой вторичен екран.
  void _backToCalendar(BuildContext context) {
    Navigator.pop(context); // менюто
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  /// Затваря менюто, връща се до календара и оттам отваря новия екран —
  /// така стекът не расте безкрайно при разходка между разделите. Връща
  /// Future-а на push-а, за да може извикващият да реагира на затварянето
  /// на новия екран (виж употребата при "Настройки").
  Future<void> _openScreen(BuildContext context, WidgetBuilder builder) {
    Navigator.pop(context); // менюто
    final navigator = Navigator.of(context);
    navigator.popUntil((route) => route.isFirst);
    return navigator.push(MaterialPageRoute(builder: builder));
  }

  /// Справочните секции — само затваря менюто и оставя ReferencePager да
  /// реши дали да прелисти (вече е отворен) или да бутне нов екран.
  void _openSection(BuildContext context, ReferenceSection section) {
    Navigator.pop(context); // менюто
    ReferencePager.open(context, section);
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: AppColors.drawerBackground,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: const BoxDecoration(color: AppColors.toolbar),
            // DrawerHeader е с фиксирана височина 160 и подразбиращо се
            // поле 16 отгоре/отдолу. При надпис от 26 пункта иконата (100)
            // и редът вече не се събират в оставащите 128 и излизаше
            // „BOTTOM OVERFLOWED BY 3 PIXELS". Свиваме полето, вместо да
            // смаляваме шрифта — той е нарочно едър.
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Image.asset('assets/icon_trans.png', width: 100, height: 100),
                const SizedBox(height: 0),
                const Text(
                  'Православен календар',
                  style: TextStyle(
                    fontFamily: 'TamburinModern',
                    color: AppColors.textPrimary,
                    fontSize: 28,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.only(left: 16, top: 8, bottom: 4),
            child: Text('ОСНОВНИ',
                style: TextStyle(
                    color: AppColors.textMuted, fontSize: 11, letterSpacing: 1.5)),
          ),
          _item(Icons.calendar_month, 'Календар', () => _backToCalendar(context)),
          _item(Icons.auto_stories, 'Молитвослов', () {}),
          _item(Icons.book, 'Библия', () {}),
          // „Месецослов" — кътът за четене на книги: тесте корици, което се
          // разлиства (library_screen.dart).
          _item(Icons.menu_book, 'Месецослов', () {
            Navigator.of(context).pop();
            Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const LibraryScreen(),
            ));
          }),
          // Четирите справочни секции живеят в ОБЩ екран с плъзгане
          // настрани (reference_pager.dart). Менюто само посочва коя да е
          // отгоре; ако екранът вече е отворен, ReferencePager.open просто
          // прелиства до нея, вместо да го пресъздава — така избраната
          // година оцелява при разходка между четирите.
          _item(Icons.church, 'Празници',
              () => _openSection(context, ReferenceSection.holidays)),
          _itemSvg('assets/icons/candle.svg', 'Дни за помени',
              () => _openSection(context, ReferenceSection.memorial)),
          _item(Icons.no_meals, 'Пости',
              () => _openSection(context, ReferenceSection.fasts)),
          _item(Icons.info_outline, 'Справочник',
              () => _openSection(context, ReferenceSection.book)),
          const Divider(color: AppColors.drawerDivider),
          const Padding(
            padding: EdgeInsets.only(left: 16, top: 4, bottom: 4),
            child: Text('ДРУГИ',
                style: TextStyle(
                    color: AppColors.textMuted, fontSize: 11, letterSpacing: 1.5)),
          ),
          _item(Icons.settings, 'Настройки', () {
            _openScreen(
              context,
              (_) => SettingsScreen(onChanged: appSettingsChangedHook),
            ).then((_) => AppSettings.saveNow());
          }),
          _itemText('❈', 'Оцени приложението', () {}),
          SafeArea(
            top: false,
            child: _item(Icons.help_outline, 'За приложението', () {
              _openScreen(context, (_) => const AboutScreen());
            }),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _item(IconData icon, String title, VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon, color: AppColors.drawerIcon, size: 26),
      title: Text(title,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 18)),
      onTap: onTap,
      dense: true,
    );
  }

  Widget _itemSvg(String svgPath, String title, VoidCallback onTap) {
    return ListTile(
      leading: SvgPicture.asset(
        svgPath,
        width: 22,
        height: 22,
        colorFilter: const ColorFilter.mode(AppColors.drawerIcon, BlendMode.srcIn),
      ),
      title: Text(title,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 18)),
      onTap: onTap,
      dense: true,
    );
  }

  Widget _itemText(String symbol, String title, VoidCallback onTap) {
    return ListTile(
      leading: Text(symbol,
          style: const TextStyle(color: AppColors.drawerIcon, fontSize: 30)),
      title: Text(title,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 18)),
      onTap: onTap,
      dense: true,
    );
  }
}
