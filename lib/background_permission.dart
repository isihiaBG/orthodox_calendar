import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_theme.dart';
import 'audiobook.dart' show audioLogAdd;

/// Четенето на глас във фонов режим и пестенето на батерия (27.10.2026).
///
/// ⚠⚠ ПРИЧИНАТА, НАМЕРЕНА ОТ АВТОРА: устройството (Honor) пести батерия и
/// ЗАМРАЗЯВА приложението във фонов режим — и с услугата „медия“ от 2200.
/// Звукът замръзва насред изречение и тръгва чак при връщане. Лекът е в
/// настройките на системата; след смяната им проблемът изчезна.
///
/// ⚠ НЕ СЕ ПИТА ПРЕДВАРИТЕЛНО (автора: хората се плашат, когато приложение
/// иска промени в настройките). Пита се САМО след като замръзване е
/// засечено (book_reader: часовникът във фонов режим изостава) — тогава
/// човек вече знае защо. „Не сега“ спира питането завинаги; редът в
/// Настройки → „ЗВУК“ остава ([BackgroundAudioTile]).
///
/// „Позволи“: стандартното прозорче на Android (изключение от пестенето);
/// на Honor/Huawei след него и техният екран „Стартиране на приложения“ —
/// там е отделна настройка, която стандартното прозорче не пипа.
class BackgroundAudio {
  BackgroundAudio._();

  static const _channel = MethodChannel('isihiabg/update');
  static const _kDeclined = 'bg_audio_declined';
  // Позволено е през стандартното прозорче — замръзне ли пак, значи
  // производителят има СВОЯ пазач (Xiaomi, Oppo, Vivo…): второ съобщение.
  static const _kAllowedOnce = 'bg_audio_allowed_once';
  static const _kVendorHint = 'bg_audio_vendor_hint_shown';

  /// (позволено ли е от системата, производителят с малки букви).
  static Future<(bool, String)> state() async {
    if (kIsWeb) return (true, '');
    try {
      final m = await _channel.invokeMapMethod<String, dynamic>('bgState');
      return ((m?['allowed'] as bool?) ?? true, (m?['vendor'] as String?) ?? '');
    } catch (_) {
      return (true, '');
    }
  }

  static bool isHonorLike(String vendor) =>
      vendor.contains('honor') || vendor.contains('huawei');

  /// След засечено замръзване: прозорчето (веднъж, ако не е отказано).
  static Future<void> askAfterFreeze(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_kDeclined) ?? false) return;
    final (allowed, vendor) = await state();
    if (allowed && !isHonorLike(vendor)) {
      // Стандартното е позволено, а пак замръзна — собствена настройка на
      // производителя. Веднъж; страницата на приложението (Батерия).
      if (!(prefs.getBool(_kAllowedOnce) ?? false) ||
          (prefs.getBool(_kVendorHint) ?? false) || !context.mounted) {
        return;
      }
      await prefs.setBool(_kVendorHint, true);
      audioLogAdd('фонов режим: пак замръзна при позволено ($vendor)');
      if (!context.mounted) return;
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.backgroundCard,
          title: const Text('Четенето на глас пак прекъсна'),
          content: const Text(
            'Устройството Ви има и собствена настройка за работа във фонов '
            'режим.\n\n'
            'Ще отворим страницата на приложението — изберете „Батерия“ и '
            '„Без ограничения“.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Не сега')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Отвори')),
          ],
        ),
      );
      if (go == true) {
        try {
          await _channel.invokeMethod('bgAppInfo');
        } catch (_) {}
      }
      return;
    }
    if (!context.mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.backgroundCard,
        title: const Text('Четенето на глас прекъсна'),
        content: const Text(
          'Докато бяхте в друго приложение, устройството спря четенето, '
          'за да пести батерия.\n\n'
          'Да позволим ли на приложението да работи във фонов режим без това '
          'ограничение, за да не прекъсва звукът отново?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Не сега')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Позволи')),
        ],
      ),
    );
    if (ok == null) return;
    if (!ok) {
      await prefs.setBool(_kDeclined, true);
      audioLogAdd('фонов режим: „Не сега“');
      return;
    }
    if (context.mounted) await allow(context);
  }

  /// Пътят на „Позволи“ — и от прозорчето, и от настройките.
  static Future<void> allow(BuildContext context) async {
    final (allowed, vendor) = await state();
    if (!allowed) {
      try {
        await _channel.invokeMethod('bgRequest');
      } catch (_) {}
      // Изчакай човека да се върне от прозорчето на системата.
      await _nextResume();
    }
    final (nowAllowed, _) = await state();
    audioLogAdd('фонов режим: позволено=$nowAllowed ($vendor)');
    if (nowAllowed) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kAllowedOnce, true);
    }
    if (!isHonorLike(vendor) || !context.mounted) return;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.backgroundCard,
        title: const Text('Още една стъпка'),
        content: const Text(
          'На устройствата Honor и Huawei има и отделна настройка.\n\n'
          'В екрана, който ще се отвори, намерете „Православен календар“, '
          'изключете „Управлявай автоматично“ и в прозорчето включете '
          '„Работа във фонов режим“.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Не сега')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Отвори')),
        ],
      ),
    );
    if (go != true) return;
    try {
      await _channel.invokeMethod('bgVendor');
    } catch (_) {}
  }

  /// Следващото връщане в приложението (най-много 2 минути).
  static Future<void> _nextResume() {
    final c = Completer<void>();
    late final AppLifecycleListener l;
    var left = false;
    l = AppLifecycleListener(onStateChange: (s) {
      if (s != AppLifecycleState.resumed) left = true;
      if (s == AppLifecycleState.resumed && left && !c.isCompleted) c.complete();
    });
    return c.future
        .timeout(const Duration(minutes: 2), onTimeout: () {})
        .whenComplete(l.dispose);
  }
}

/// Редът в Настройки → „ЗВУК“: състоянието и копчето.
class BackgroundAudioTile extends StatefulWidget {
  const BackgroundAudioTile({super.key});

  @override
  State<BackgroundAudioTile> createState() => _BackgroundAudioTileState();
}

class _BackgroundAudioTileState extends State<BackgroundAudioTile> {
  bool? _allowed;
  String _vendor = '';

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final (a, v) = await BackgroundAudio.state();
    if (mounted) setState(() { _allowed = a; _vendor = v; });
  }

  @override
  Widget build(BuildContext context) {
    final a = _allowed;
    if (a == null) return const SizedBox.shrink();
    final honor = BackgroundAudio.isHonorLike(_vendor);
    final String status;
    if (!a) {
      status = 'Ограничена — устройството може да спира четенето на глас, '
          'докато сте в друго приложение.';
    } else if (honor) {
      status = 'Разрешена. На Honor и Huawei проверете и „Стартиране на '
          'приложения“ — копчето отваря екрана.';
    } else {
      status = 'Разрешена — четенето на глас продължава и в друго приложение.';
    }
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: const Text('Работа във фонов режим'),
      subtitle: Text(status, style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
      trailing: (!a || honor)
          ? TextButton(
              onPressed: () async {
                await BackgroundAudio.allow(context);
                _refresh();
              },
              child: Text(a ? 'Отвори' : 'Позволи'),
            )
          : null,
    );
  }
}
