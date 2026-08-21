// calendar_style_picker.dart
//
// Мащабиран избор на стил на календара (стар/нов стил + водеща дата) за
// настройките — същите три корици като въвеждащия екран
// (welcome_screen.dart, CalendarStyleOption/kCalendarStyleOptions оттам),
// но вградени направо в лентата на настройките: БЕЗ отделен
// Scaffold/AppBar/системна лента и БЕЗ бутон за потвърждение —
// центрирането на корица САМО е изборът.
//
// ⚠ Прилагането е ОТЛОЖЕНО с 1 секунда след последната смяна на
// централната корица (debounce в _onSelected), за да не се засича
// анимацията при бързо прелистване или разцъкване. Тап направо върху
// централната корица прилага веднага, без да чака отлагането — явно
// потвърждение. Ако настройките се затворят преди да изтече секундата,
// изборът се прилага веднага при затваряне — виж
// flushPendingCalendarStylePick.

import 'dart:async';

import 'package:flutter/material.dart';

import 'app_settings.dart';
import 'app_theme.dart';
import 'cover_flow.dart';
import 'database_helper.dart';
import 'welcome_screen.dart' show CalendarStyleOption, kCalendarStyleOptions;

/// Флъш на чакащия избор — вика се при затваряне на настройките (drawer
/// или пълен екран), за да не се чака оставащата секунда от анимацията.
///
/// ⚠ СТАТИЧНО, по същата причина като AppSettings.captureMonthMiddleDate:
/// съдържанието на настройките НЕ се разрушава при затваряне на
/// Scaffold.endDrawer — той го държи постоянно монтирано, само визуално
/// скрито, тъй че dispose() на picker-а не е сигнал за "затворено".
/// Регистрира се от активния picker в initState() и се разкача в
/// dispose().
VoidCallback? flushPendingCalendarStylePick;

class CalendarStylePicker extends StatefulWidget {
  /// Вика се, когато изборът РЕАЛНО се приложи (след отлагането или при
  /// флъш) — същият подпис като старите превключватели: първият булев е
  /// "стилът (стар/нов) ли се смени", вторият — уловената по-рано средна
  /// дата на месечния изглед.
  final Function(bool styleChanged, [DateTime? capturedMiddleDate])? onChanged;

  const CalendarStylePicker({super.key, this.onChanged});

  @override
  State<CalendarStylePicker> createState() => _CalendarStylePickerState();
}

class _CalendarStylePickerState extends State<CalendarStylePicker> {
  late int _centered = _currentIndex();
  Timer? _debounce;

  int _currentIndex() {
    final i = kCalendarStyleOptions.indexWhere((s) =>
        s.isOldStyle == AppSettings.isOldStyle &&
        (!s.isOldStyle || s.oldStyleFirst == AppSettings.oldStyleFirst));
    return i < 0 ? 0 : i;
  }

  @override
  void initState() {
    super.initState();
    flushPendingCalendarStylePick = _flushNow;
  }

  @override
  void dispose() {
    // Тук picker-ът РЕАЛНО се разрушава (пълният екран от менюто, при
    // връщане назад) — за разлика от drawer-а, където това никога не се
    // случва (виж бележката над flushPendingCalendarStylePick). Затова
    // чакащият избор се прилага и тук, не само там: инак затварянето с
    // назад в прозореца на секундата би изгубило избора мълчаливо.
    _debounce?.cancel();
    _apply(_centered);
    // Само ако все още сме РЕГИСТРИРАНИЯТ picker — иначе бихме разкачили
    // хука на друг, по-нов picker (напр. пълния екран, отворен докато
    // drawer-ът стои мълчаливо монтиран отзад).
    if (flushPendingCalendarStylePick == _flushNow) {
      flushPendingCalendarStylePick = null;
    }
    super.dispose();
  }

  void _onSelected(int i) {
    setState(() => _centered = i);
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 1), () => _apply(i));
  }

  /// Тап направо върху централната корица — явно потвърждение, прилага се
  /// веднага, без да се чака отлагането.
  void _onOpen(int i) {
    _debounce?.cancel();
    _apply(i);
  }

  void _flushNow() {
    _debounce?.cancel();
    _apply(_centered);
  }

  /// Прилага избора, ако наистина се различава от текущо активния — иначе
  /// нищо не прави (флъш при затваряне без промяна не бута излишно
  /// презареждане, точно както поръча потребителят).
  void _apply(int i) {
    final s = kCalendarStyleOptions[i];
    final changed = s.isOldStyle != AppSettings.isOldStyle ||
        (s.isOldStyle && s.oldStyleFirst != AppSettings.oldStyleFirst);
    if (!changed) return;

    final styleChanged = s.isOldStyle != AppSettings.isOldStyle;
    // Улавяме СРЕДНИЯ ден на месечния изглед ПРЕДИ мутацията — виж
    // докстринга на AppSettings.captureMonthMiddleDate за причината редът
    // да има значение.
    final capturedMiddleDate = AppSettings.captureMonthMiddleDate?.call();
    AppSettings.isOldStyle = s.isOldStyle;
    AppSettings.oldStyleFirst = s.oldStyleFirst;
    AppSettings.scheduleSave();

    if (styleChanged) {
      _reloadAfterStyleChange(capturedMiddleDate);
    } else {
      widget.onChanged?.call(false, capturedMiddleDate);
    }
  }

  Future<void> _reloadAfterStyleChange(DateTime? capturedMiddleDate) async {
    await DatabaseHelper.resetDatabase();
    await DatabaseHelper.database;
    widget.onChanged?.call(true, capturedMiddleDate);
  }

  /// Колко високо мястото, което остава РЕЗЕРВИРАНО под етикета (виж
  /// build() — OverflowBox отдолу го оставя по-нисък от нужното нарочно).
  /// Всичко над това от истинската височина на етикета изпълзява НАГОРЕ,
  /// върху опашката на CoverFlow-а — по-малко тук значи по-дълбоко
  /// застъпване. Не зависи от дължината на бележката: по-дълга бележка
  /// просто застъпва малко повече, вместо да събори оразмеряването.
  static const double _captionReservedHeight = 44;

  Widget _caption(CalendarStyleOption s) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.backgroundCard,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(s.name,
              style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(s.note,
              style: TextStyle(
                  color: AppColors.textSecondary, fontSize: 13, height: 1.4)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 384 (320 + 20%): надписите са ВЪРХУ самите корици (jpg-та в
        // assets/calendar_covers/), не отделен Flutter текст — свие ли се
        // кутията, шрифтът им се смалява с образа и стават нечетими.
        SizedBox(
          height: 384,
          child: CoverFlow(
            covers: [for (final o in kCalendarStyleOptions) AssetImage(o.cover)],
            initialIndex: _centered,
            onSelected: _onSelected,
            onOpen: _onOpen,
          ),
        ),
        // Резервираме само _captionReservedHeight, а истинският етикет
        // (по-висок) изпълзява НАГОРЕ през OverflowBox — застъпва долната
        // част на отражението, без да увисва в празно под кориците и без
        // да чупи оразмеряването на Column-а (за разлика от отрицателен
        // margin/padding — виж бележката до _captionReservedHeight).
        SizedBox(
          height: _captionReservedHeight,
          child: OverflowBox(
            maxHeight: double.infinity,
            alignment: Alignment.bottomCenter,
            child: _caption(kCalendarStyleOptions[_centered]),
          ),
        ),
      ],
    );
  }
}
