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
import 'app_theme.dart';
import 'fasts_screen.dart';
import 'holidays_screen.dart';
import 'saint_expandable_tile.dart' show lookupBySlug;
import 'settings_screen.dart';

/// Реакцията на календара при промяна в настройките (смяна на стил и др.)
/// живее в състоянието на CalendarPageView — то се регистрира тук при
/// стартиране (виж main.dart). Така менюто може да я задейства и когато е
/// отворено от вторичен екран, без да има пряка връзка с календара.
typedef SettingsChangedHook = void Function(bool styleChanged);
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
  /// така стекът не расте безкрайно при разходка между разделите.
  void _openScreen(BuildContext context, WidgetBuilder builder) {
    Navigator.pop(context); // менюто
    final navigator = Navigator.of(context);
    navigator.popUntil((route) => route.isFirst);
    navigator.push(MaterialPageRoute(builder: builder));
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
          const Padding(
            padding: EdgeInsets.only(left: 16, top: 8, bottom: 4),
            child: Text('ОСНОВНИ',
                style: TextStyle(
                    color: AppColors.textMuted, fontSize: 11, letterSpacing: 1.5)),
          ),
          _item(Icons.calendar_month, 'Календар', () => _backToCalendar(context)),
          _item(Icons.auto_stories, 'Молитвослов', () {}),
          _item(Icons.book, 'Библия', () {}),
          _item(Icons.menu_book, 'Месецослов', () {}),
          _item(Icons.church, 'Празници', () {
            _openScreen(context, (_) => const HolidaysScreen(lookup: lookupBySlug));
          }),
          _itemSvg('assets/icons/candle.svg', 'Дни за помени', () {}),
          _item(Icons.no_meals, 'Пости', () {
            _openScreen(context, (_) => const FastsScreen(lookup: lookupBySlug));
          }),
          _item(Icons.info_outline, 'Справочник', () {}),
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
            );
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
