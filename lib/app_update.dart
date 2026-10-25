// app_update.dart
//
// Актуализация на приложението ОТВЪТРЕ — за периода преди Google Play, докато
// APK-тата се раздават на ръка (решение на автора, 25.10.2026).
//
//   update.json   https://isihiabg.github.io/orthodox_calendar/update.json
//                 (docs/update.json в хранилището — пише го
//                 tools/release/publish_app.py): последният билд, адресът на
//                 APK-то в GitHub, размерът, SHA-256 и „Какво ново" по билдове.
//   APK-то        издание `app-latest` в GitHub, име с номера на билда.
//
// ⚠⚠ ПРОВЕРКАТА Е ПРИ ВСЯКО ПУСКАНЕ (~4 KB) и е НАПЪЛНО МЪЛЧАЛИВА при
// неуспех (изрично от автора): самолетен режим, лоша връзка, повреден файл —
// нищо не се съобщава и нищо не се блокира. Часът на проверката се записва
// САМО при успех, тъй че следващото пускане опитва пак. Точките идват
// единствено от ПОСЛЕДНАТА УСПЕШНО ПОЛУЧЕНА информация.
//
// ⚠ Звукът се проверява заедно с приложението (регистърът е малък), но НЕ
// се сваля — само се отбелязва кои свалени глави имат по-нова версия. Това
// отменя по-ранното „мрежа само по воля на човека" — нарочно, решение на
// автора от 25.10.2026.
//
// Точките (автора): червена — силно препоръчително (приложението);
// оранжева — по желание (обновен звук на вече свалени глави).
//
// ⚠⚠ GOOGLE PLAY ЗАБРАНЯВА самообновяване извън Play — в билда за Play
// [kAppSelfUpdate] става false и всичко тук изчезва (секцията в настройките,
// точките, прозорчето). Там пътят е „In-app updates" на Play.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' show join;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_theme.dart';
import 'audiobook.dart';

/// ⚠ false в билда за Google Play — виж горе.
const bool kAppSelfUpdate = true;

const String _manifestUrl =
    'https://isihiabg.github.io/orthodox_calendar/update.json';

/// Червената точка — силно препоръчително.
const Color kUpdateRed = Color(0xFFE5484D);

/// Оранжевата точка — по желание.
const Color kUpdateOrange = Color(0xFFF5A524);

/// Едно „какво ново" — новостите на един билд.
class UpdateNews {
  final int build;
  final String date;
  final List<String> items;
  const UpdateNews(this.build, this.date, this.items);
}

/// Последният билд според update.json.
class UpdateInfo {
  final int build;
  final String apk;
  final int size;
  final String sha256;
  final List<UpdateNews> news;

  /// Същото APK, свито с gzip (~12% по-малко) — от билд 2194 нататък се
  /// тегли то и се разархивира ДОКАТО се тегли. Липсва ли — обикновеното.
  /// ⚠ [sha256] е на РАЗАРХИВИРАНОТО APK и в двата случая.
  final String? gz;
  final int? gzSize;
  const UpdateInfo(this.build, this.apk, this.size, this.sha256, this.news,
      [this.gz, this.gzSize]);

  /// Колко се тегли реално.
  int get downloadSize => gz != null && gzSize != null ? gzSize! : size;

  static UpdateInfo parse(String text) {
    final j = jsonDecode(text) as Map;
    return UpdateInfo(
      (j['build'] as num).toInt(),
      j['apk'] as String,
      (j['size'] as num).toInt(),
      (j['sha256'] as String).toLowerCase(),
      [
        for (final n in (j['news'] as List? ?? const []))
          UpdateNews((n['build'] as num).toInt(), (n['date'] as String?) ?? '',
              [for (final i in (n['items'] as List)) i as String]),
      ],
      j['apk_gz'] as String?,
      (j['gz_size'] as num?)?.toInt(),
    );
  }

  String get sizeLabel => '${(downloadSize / 1048576).round()} MB';
}

class AppUpdate {
  AppUpdate._();

  static const _kManifest = 'app_update_manifest';
  static const _kLastOk = 'app_update_last_ok';
  static const _kDismissed = 'app_update_dismissed';


  /// По-новият билд, ако има такъв (иначе null). Слушат го точките.
  static final ValueNotifier<UpdateInfo?> available = ValueNotifier(null);

  /// Колко свалени глави имат по-нова версия на звука.
  static final ValueNotifier<int> audioOutdated = ValueNotifier(0);

  /// Свалено ли е вече APK-то на наличната версия — тогава „Свали" става
  /// „Инсталирай" (автора, 26.10.2026: повторно „Свали" изглеждаше като
  /// развалено копче).
  static final ValueNotifier<bool> downloaded = ValueNotifier(false);

  /// Последната успешна проверка (за реда в настройките).
  static final ValueNotifier<DateTime?> lastOk = ValueNotifier(null);

  static int currentBuild = 0;
  static UpdateInfo? _known;
  static int _dismissed = 0;
  static bool _started = false;

  static bool get supported =>
      kAppSelfUpdate && !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Цветът на точката до ⋮ в календара: червена над оранжева.
  static Color? get menuDotColor => available.value != null
      ? kUpdateRed
      : (audioOutdated.value > 0 ? kUpdateOrange : null);

  /// Новостите от ТЕКУЩИЯ билд до най-новия, най-новото отгоре.
  static List<UpdateNews> newsSinceCurrent() {
    final k = _known;
    if (k == null) return const [];
    final l = k.news.where((n) => n.build > currentBuild).toList()
      ..sort((a, b) => b.build.compareTo(a.build));
    return l;
  }

  /// Вика се веднъж, след първия кадър на календара. [onFound] показва
  /// прозорчето — само ако има по-нов билд от отложения.
  static Future<void> start(void Function(UpdateInfo) onFound) async {
    if (!supported || _started) return;
    _started = true;
    try {
      currentBuild = int.tryParse((await PackageInfo.fromPlatform()).buildNumber) ?? 0;
      final p = await SharedPreferences.getInstance();
      _dismissed = p.getInt(_kDismissed) ?? 0;
      final ms = p.getInt(_kLastOk);
      if (ms != null) lastOk.value = DateTime.fromMillisecondsSinceEpoch(ms);
      final saved = p.getString(_kManifest);
      if (saved != null) {
        try {
          _known = UpdateInfo.parse(saved);
        } catch (_) {}
      }
      _publish();
      AudioBook.anyChange.addListener(_audioChanged);
      AudioRegistry.revision.addListener(_audioChanged);
      unawaited(_recountAudio());
      // ⚠ При ВСЯКО пускане (автора, 26.10.2026): двата файла са ~4 KB, а
      // „веднъж на ден" криеше новата версия, ако приложението вече е било
      // отваряно днес.
      await check();
      final a = available.value;
      if (a != null && a.build > _dismissed) onFound(a);
    } catch (e) {
      debugPrint('AppUpdate.start: $e'); // ⚠ мълчаливо — никога не спира приложението
    }
  }

  /// Проверка — при пускане (веднъж на ден) или ръчно. Връща true при
  /// успех. ⚠ НЕ хвърля: всяка грешка дава false и нищо друго.
  static Future<bool> check() async {
    if (!supported) return false;
    try {
      if (currentBuild == 0) {
        currentBuild = int.tryParse((await PackageInfo.fromPlatform()).buildNumber) ?? 0;
      }
      final text = await _fetchText(
          '$_manifestUrl?t=${DateTime.now().millisecondsSinceEpoch ~/ 60000}');
      if (text == null) return false;
      final info = UpdateInfo.parse(text); // повреден файл → изключение → false
      _known = info;
      final p = await SharedPreferences.getInstance();
      await p.setString(_kManifest, text);
      final now = DateTime.now();
      await p.setInt(_kLastOk, now.millisecondsSinceEpoch);
      lastOk.value = now;
      _publish();
      // Звукът — само регистърът; свалянето е по воля на човека.
      try {
        await AudioRegistry.check().timeout(const Duration(seconds: 20));
      } catch (_) {}
      await _recountAudio();
      return true;
    } catch (e) {
      debugPrint('AppUpdate.check: $e');
      return false;
    }
  }

  /// „По-късно" — прозорчето не излиза пак за ТОЗИ билд; точките остават.
  static Future<void> dismiss(UpdateInfo i) async {
    _dismissed = i.build;
    try {
      (await SharedPreferences.getInstance()).setInt(_kDismissed, i.build);
    } catch (_) {}
  }

  static void _publish() {
    final k = _known;
    available.value = (k != null && k.build > currentBuild) ? k : null;
    unawaited(_refreshDownloaded());
  }

  /// Има ли изтеглено APK на наличната версия (размерът стига — SHA-256 е
  /// проверен при самото сваляне, а `.part` не се брои).
  static Future<void> _refreshDownloaded() async {
    final a = available.value;
    var ok = false;
    try {
      if (a != null) {
        final f = await _apkFile(a.build);
        ok = await f.exists() && await f.length() == a.size;
      } else if (currentBuild > 0) {
        // Обновено (или няма нищо ново) — старите свалени APK-та не трябват.
        final d = (await _apkFile(0)).parent;
        await for (final f in d.list()) {
          await f.delete();
        }
      }
    } catch (_) {}
    downloaded.value = ok;
  }

  static Timer? _audioDebounce;
  static void _audioChanged() {
    _audioDebounce?.cancel();
    _audioDebounce = Timer(const Duration(milliseconds: 600), _recountAudio);
  }

  static Future<void> _recountAudio() async {
    try {
      await AudioRegistry.load();
      var n = 0;
      for (final asset in AudioRegistry.books.toList()) {
        final b = AudioBook.forAsset(asset);
        if (b != null) n += await b.outdatedCount();
      }
      audioOutdated.value = n;
    } catch (_) {}
  }

  static Future<String?> _fetchText(String url) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final resp = await (await client.getUrl(Uri.parse(url)))
          .close()
          .timeout(const Duration(seconds: 12));
      if (resp.statusCode != 200) return null;
      return await resp
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 12));
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  // ─── Сваляне и инсталиране ──────────────────────────────────────────────

  static const _channel = MethodChannel('isihiabg/update');

  /// Свалено и проверено APK за този билд, ако вече го има.
  static Future<File> _apkFile(int build) async {
    final d = Directory(join((await getTemporaryDirectory()).path, 'update'));
    await d.create(recursive: true);
    return File(join(d.path, 'pravoslaven-kalendar-$build.apk'));
  }

  static bool _busy = false;

  /// Сваля (с напредък в прозорец), проверява SHA-256 и отваря инсталатора
  /// на Android. Грешките се казват — тук човекът сам е поискал.
  static Future<void> downloadAndInstall(BuildContext context) async {
    final info = available.value;
    if (info == null || _busy) return;
    if (downloaded.value) return install(context);
    _busy = true;
    final progress = ValueNotifier<double>(0);
    final cancel = Completer<void>();
    final nav = Navigator.of(context, rootNavigator: true);
    final messenger = ScaffoldMessenger.maybeOf(context);
    var dialogOpen = true;
    unawaited(showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
          backgroundColor: AppColors.backgroundCard,
          title: const Text('Сваляне на новата версия'),
          content: ValueListenableBuilder<double>(
            valueListenable: progress,
            builder: (_, v, _) => Column(mainAxisSize: MainAxisSize.min, children: [
              LinearProgressIndicator(
                value: v,
                color: AppColors.sectionTitle,
                backgroundColor: AppColors.sectionDivider,
              ),
              const SizedBox(height: 10),
              Text('${(v * info.downloadSize / 1048576).round()} / ${info.sizeLabel}',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
            ]),
          ),
          actions: [
            TextButton(
              onPressed: () {
                if (!cancel.isCompleted) cancel.complete();
              },
              child: const Text('Отказ'),
            ),
          ],
        ),
      ),
    ).whenComplete(() => dialogOpen = false));

    String? err;
    File? apk;
    try {
      apk = await _download(info, progress, cancel.future);
      if (apk == null) err = cancel.isCompleted ? null : 'Свалянето не успя.';
    } catch (e) {
      err = e is SocketException ? 'Няма връзка с интернет.' : 'Свалянето не успя.';
    }
    if (dialogOpen) nav.pop();
    _busy = false;
    if (apk == null) {
      if (err != null) messenger?.showSnackBar(SnackBar(content: Text(err)));
      return;
    }
    downloaded.value = true;
    await _install(apk, messenger);
  }

  /// „Инсталирай" — вече сваленото APK, без нов прозорец.
  static Future<void> install(BuildContext context) async {
    final a = available.value;
    if (a == null) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final f = await _apkFile(a.build);
    if (!await f.exists()) {
      downloaded.value = false;
      if (context.mounted) await downloadAndInstall(context);
      return;
    }
    await _install(f, messenger);
  }

  /// Пътят, чакащ разрешение за инсталиране. Щом човекът се върне в
  /// приложението с даденото разрешение, инсталаторът се отваря САМ —
  /// без второ натискане (автора, 26.10.2026).
  static String? _awaitingPermission;
  static AppLifecycleListener? _life;

  static Future<void> _install(File apk, ScaffoldMessengerState? messenger) async {
    try {
      final r = await _channel.invokeMethod<String>('install', {'path': apk.path});
      if (r == 'permission') {
        _awaitingPermission = apk.path;
        _life ??= AppLifecycleListener(onResume: _resumeAfterPermission);
        messenger?.showSnackBar(const SnackBar(
          duration: Duration(seconds: 8),
          content: Text('Разреши инсталирането от това приложение и се върни — '
              'инсталацията ще продължи сама.'),
        ));
      }
    } catch (e) {
      messenger?.showSnackBar(
          const SnackBar(content: Text('Инсталаторът не се отвори.')));
    }
  }

  static Future<void> _resumeAfterPermission() async {
    final path = _awaitingPermission;
    if (path == null) return;
    try {
      final can = await _channel.invokeMethod<bool>('canInstall') ?? false;
      if (!can) return; // още не е разрешено — „Инсталирай" остава под ръка
      _awaitingPermission = null;
      if (await File(path).exists()) {
        await _channel.invokeMethod<String>('install', {'path': path});
      }
    } catch (_) {}
  }

  /// ⚠ Пише в `.part` и преименува чак след проверката на SHA-256 —
  /// прекъснато тегление не оставя половин APK, което да изглежда годно.
  static Future<File?> _download(
      UpdateInfo info, ValueNotifier<double> progress, Future<void> cancel) async {
    final out = await _apkFile(info.build);
    if (await out.exists() && await out.length() == info.size) {
      if ((await sha256.bind(out.openRead()).first).toString() == info.sha256) {
        progress.value = 1;
        return out;
      }
    }
    // Старите свалени версии не трябват.
    try {
      await for (final f in out.parent.list()) {
        if (f.path != out.path) await f.delete();
      }
    } catch (_) {}
    final part = File('${out.path}.part');
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    var cancelled = false;
    unawaited(cancel.then((_) {
      cancelled = true;
      client.close(force: true);
    }));
    try {
      final packed = info.gz != null && info.gzSize != null;
      final resp =
          await (await client.getUrl(Uri.parse(packed ? info.gz! : info.apk))).close();
      if (resp.statusCode != 200) return null;
      final sink = part.openWrite();
      var wire = 0, got = 0;
      // Напредъкът е по ИЗТЕГЛЕНОТО (свитото); на диска пада разархивираното.
      Stream<List<int>> body = resp.timeout(const Duration(seconds: 30)).map((c) {
        wire += c.length;
        progress.value = (wire / info.downloadSize).clamp(0, 1);
        return c;
      });
      if (packed) body = body.transform(gzip.decoder);
      try {
        await for (final c in body) {
          sink.add(c);
          got += c.length;
        }
      } finally {
        await sink.close();
      }
      if (got != info.size) return null;
      final sum = (await sha256.bind(part.openRead()).first).toString();
      if (sum != info.sha256) {
        await part.delete();
        return null;
      }
      return await part.rename(out.path);
    } catch (e) {
      if (cancelled) return null;
      rethrow;
    } finally {
      client.close(force: true);
    }
  }
}

/// Точка в горния десен ъгъл на [child]; без цвят — само [child].
Widget withUpdateDot(Widget child, Color? color, {double size = 9}) {
  if (color == null) return child;
  return Stack(clipBehavior: Clip.none, children: [
    child,
    Positioned(
      right: -1,
      top: -1,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.toolbar, width: 1.2),
        ),
      ),
    ),
  ]);
}

/// „Какво ново" — новостите от версията на човека до най-новата.
Future<void> showWhatsNew(BuildContext context) {
  final news = AppUpdate.newsSinceCurrent();
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.backgroundCard,
      title: const Text('Какво ново'),
      content: SizedBox(
        width: double.maxFinite,
        child: news.isEmpty
            ? Text('Няма описани новости.',
                style: TextStyle(color: AppColors.textSecondary))
            : ListView(
                shrinkWrap: true,
                children: [
                  for (final n in news) ...[
                    if (n.date.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6, bottom: 4),
                        child: Text(n.date,
                            style: TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 12,
                                letterSpacing: 1)),
                      ),
                    for (final i in n.items)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Text('•  ', style: TextStyle(color: AppColors.sectionTitle)),
                          Expanded(
                              child: Text(i,
                                  style: const TextStyle(
                                      color: AppColors.textPrimary, fontSize: 15, height: 1.3))),
                        ]),
                      ),
                  ],
                ],
              ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Затвори')),
      ],
    ),
  );
}

/// Неангажиращото прозорче горе — „Има нова версия". Слиза плавно отгоре,
/// стои над деня (не го избутва) и се прибира с „По-късно" — тогава остават
/// само червените точки.
class UpdateBanner extends StatelessWidget {
  final VoidCallback onClose;
  const UpdateBanner({super.key, required this.onClose});

  @override
  Widget build(BuildContext context) {
    final info = AppUpdate.available.value;
    if (info == null) return const SizedBox.shrink();
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
      builder: (_, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, -24 * (1 - t)), child: child),
      ),
      child: Material(
        color: AppColors.backgroundCard,
        elevation: 10,
        shadowColor: Colors.black,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: AppColors.sectionDivider),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 10, 6),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.sectionTitle.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: withUpdateDot(
                    const Icon(Icons.system_update, color: AppColors.sectionTitle, size: 22),
                    kUpdateRed),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Има нова версия',
                      style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text('Приложението може да се обнови · ${info.sizeLabel}',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                ]),
              ),
            ]),
            const SizedBox(height: 4),
            Row(children: [
              TextButton(
                onPressed: () => showWhatsNew(context),
                child: const Text('Какво ново'),
              ),
              const Spacer(),
              TextButton(
                onPressed: () {
                  AppUpdate.dismiss(info);
                  onClose();
                },
                style: TextButton.styleFrom(foregroundColor: AppColors.textSecondary),
                child: const Text('По-късно'),
              ),
              const SizedBox(width: 4),
              ValueListenableBuilder<bool>(
                valueListenable: AppUpdate.downloaded,
                builder: (_, done, _) => FilledButton(
                  onPressed: () {
                    // ⚠ Преди onClose: той маха прозорчето, а с него и контекста.
                    AppUpdate.downloadAndInstall(context);
                    AppUpdate.dismiss(info);
                    onClose();
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.sectionTitle,
                    foregroundColor: Colors.white,
                    visualDensity: VisualDensity.compact,
                  ),
                  child: Text(done ? 'Инсталирай' : 'Свали'),
                ),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}
