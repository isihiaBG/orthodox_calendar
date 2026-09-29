// rate_app.dart
//
// „Оцени приложението" — редът в главното меню.
//
//   инсталирано от Google Play   → прозорецът на Play за оценка, без изход
//                                  от приложението (in_app_review)
//   Play не го показва           → страницата на приложението в Play Store
//   инсталирано по друг път      → кратко съобщение, че оценката идва с
//                                  публикуването
//
// ⚠ Дотогава APK-тата се раздават на ръка, а Google Play показва прозореца
// за оценка САМО на приложение, инсталирано от него — иначе заявката се
// подминава МЪЛЧАЛИВО. Затова изворът на инсталацията се пита изрично и
// редът никога не остава мъртъв. В деня на публикуването проработва сам,
// без нов код. (Решение на потребителя, 30.09.2026: само оценка, без
// обратна връзка по е-поща.)
//
// ⚠ Прозорецът на Play е ограничен от самия Play по брой показвания — той
// може да не излезе и при инсталация от Play. Затова резервният път е
// страницата в магазина, а не нищо.

import 'package:flutter/material.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Инсталаторът на Google Play.
const _kPlayInstaller = 'com.android.vending';

Future<void> rateApp(ScaffoldMessengerState? messenger) async {
  String? installer;
  try {
    installer = (await PackageInfo.fromPlatform()).installerStore;
  } catch (_) {
    installer = null; // браузърът и всичко непознато — като „не от Play"
  }
  if (installer != _kPlayInstaller) {
    messenger?.showSnackBar(const SnackBar(
      content: Text('Оценяването ще бъде възможно след публикуването '
          'на приложението в Google Play.'),
    ));
    return;
  }
  final review = InAppReview.instance;
  try {
    if (await review.isAvailable()) {
      await review.requestReview();
    } else {
      await review.openStoreListing();
    }
  } catch (_) {
    messenger?.showSnackBar(const SnackBar(
      content: Text('Google Play не можа да се отвори.'),
    ));
  }
}
