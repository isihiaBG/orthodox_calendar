// app_version.dart
//
// Номерът на версията (решение на автора, 25.10.2026): ОСНОВНА.ВТОРОСТЕПЕННА.БИЛД
//
//   0.x   — преди Google Play (изпитание); с публикуването става 1.0.
//   втор. — вдига се при голяма новост (нова секция и т.н.), не при поправки.
//   билд  — versionCode, расте с всеки билд; по него се сравнява обновяването.
//
// Билдът се прави с:
//   flutter build apk --release --target-platform android-arm64 \
//     --build-name=0.9.<N> --build-number=<N> --dart-define=BUILD_DATE=<ГГГГ-ММ-ДД>
// Android показва versionName (0.9.<N>) и в информацията за приложението.
//
// ⚠ В „Какво ново" номера НЯМА — там той не значи нищо за човека.

import 'package:package_info_plus/package_info_plus.dart';

/// Датата на билда — подава се с --dart-define; празна в дебъг.
const String kBuildDate = String.fromEnvironment('BUILD_DATE');

String? _cached;

/// „Версия 0.9.2194 · 25.10.2026".
Future<String> appVersionLabel() async {
  if (_cached != null) return _cached!;
  var v = '';
  try {
    final info = await PackageInfo.fromPlatform();
    v = info.version;
    // Билд без --build-name: version е от pubspec, билдът — отделно.
    if (v.split('.').length < 3 || v.endsWith('.0')) {
      final p = v.split('.');
      v = '${p.first}.${p.length > 1 ? p[1] : '0'}.${info.buildNumber}';
    }
  } catch (_) {}
  final d = kBuildDate.split('-');
  final date = d.length == 3 ? '${d[2]}.${d[1]}.${d[0]}' : '';
  return _cached = [if (v.isNotEmpty) 'Версия $v', if (date.isNotEmpty) date].join(' · ');
}
