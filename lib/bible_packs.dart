// bible_packs.dart
//
// Езиковите пакети на Библията — преводите, които НЕ пътуват в APK-то.
//
// ⚠ ЗАЩО ИЗОБЩО. Пълната база с дванайсетте превода е 99 MB и в пакета тя
// влиза цялата: всеки потребител тегли и грузинския, и иврита, за да чете на
// български. В приложението остават ДВА превода (български и
// църковнославянски — 20 MB), а останалите се свалят по желание.
//
// ⚠ ПАКЕТЪТ Е ОТДЕЛЕН ФАЙЛ, а не вливане в основната база. Причината е
// твърда: `BibleDb.database` ТРИЕ и презаписва `bible.db` от assets при всяко
// пускане (за да стига поправка в assets/db/ до устройството), тъй че всичко
// влято в нея живее до първото рестартиране.
//
// ⚠ СПИСЪКЪТ Е ЗАШИТ ТУК, НА ЕДНО МЯСТО. Обсъдено и решено съзнателно
// (27.08.2026): манифест на сървъра би позволил нов език без нов билд, но е
// още една подвижна част и още едно нещо, което може да откаже.
//
// ⚠ Източникът обаче предлага доста повече от тези десет превода, тъй че
// добавянето на нов е въпрос на време. Затова целият списък живее в
// [kBiblePacks] и НИКОЙ друг файл не го изброява: дойде ли ден за манифест,
// подменя се [availablePacks] — една функция — а екранът с настройките и
// [BibleDb] остават непокътнати.

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' show join;
import 'package:path_provider/path_provider.dart';

/// Един превод, който може да се свали.
class BiblePack {
  final String code;
  final String title;
  final String short;

  /// Големина на файла в байтове — показва се ПРЕДИ тегленето, за да знае
  /// човек какво почва, особено на мобилни данни.
  final int bytes;

  const BiblePack({
    required this.code,
    required this.title,
    required this.short,
    required this.bytes,
  });

  String get fileName => 'bible-$code.db';

  /// „13,1 MB" — за списъка в настройките.
  String get sizeLabel {
    final mb = bytes / 1048576;
    return '${mb.toStringAsFixed(1).replaceAll('.', ',')} MB';
  }
}

/// ⚠ ТАГЪТ НЕ СЕ СМЕНЯ НИКОГА.
///
/// Адресите са зашити в приложението, а вече инсталираните копия теглят
/// точно от тук. Смени ли се тагът при следващо издание на приложението, те
/// спират да свалят езици — и това не може да се поправи без нов APK. Затова
/// изданието с пакетите е ОТДЕЛНО от изданията на приложението и живее само
/// за тях.
const String kPacksTag = 'bible-packs-v1';
const String kPacksBaseUrl =
    'https://github.com/isihiaBG/orthodox_calendar/releases/download/$kPacksTag';

/// Преводите в основната база — те не се свалят, винаги ги има.
const List<String> kBuiltInLangs = ['bg', 'utfcs'];

/// Големините са МЕРЕНИ от готовите файлове (05_build_packs.py), не гадани.
const List<BiblePack> kBiblePacks = [
  BiblePack(code: 'cs', title: 'Църковнославянски (гражданска)', short: 'Църковнослав. (гражд.)', bytes: 8581120),
  BiblePack(code: 'r', title: 'Руски (синодален)', short: 'Руски', bytes: 13688832),
  BiblePack(code: 'el-r', title: 'Гръцки (Септуагинта)', short: 'Гръцки (LXX)', bytes: 8523776),
  BiblePack(code: 'g', title: 'Гръцки (Нов завет)', short: 'Гръцки (НЗ)', bytes: 2113536),
  BiblePack(code: 'l', title: 'Латински (Nova Vulgata)', short: 'Латински', bytes: 5910528),
  BiblePack(code: 'en-kjv', title: 'Английски (KJV)', short: 'Английски', bytes: 8486912),
  BiblePack(code: 'sb', title: 'Сръбски (синодален)', short: 'Сръбски', bytes: 8966144),
  BiblePack(code: 'i', title: 'Иврит', short: 'Иврит', bytes: 7536640),
  BiblePack(code: 'u', title: 'Грузински', short: 'Грузински', bytes: 11608064),
  BiblePack(code: 'y', title: 'Грузински (древен)', short: 'Грузински (др.)', bytes: 2752512),
];

/// ⚠ ЕДИНСТВЕНАТА точка, през която се разбира какво може да се свали.
/// Дойде ли ден за манифест от сървъра, подменя се само тя.
List<BiblePack> availablePacks() => kBiblePacks;

/// Свалянето, съхранението и изтриването на пакетите.
class BiblePacks {
  BiblePacks._();

  static Directory? _dir;

  /// ⚠ СОБСТВЕНА ПАПКА, извън `getDatabasesPath()`. Там живее `bible.db`,
  /// която се трие при всяко пускане; пакетите не бива да са ѝ съседи, за да
  /// не ги помете някое бъдещо чистене „на едро".
  static Future<Directory> _packDir() async {
    if (_dir != null) return _dir!;
    final base = await getApplicationSupportDirectory();
    final d = Directory(join(base.path, 'bible_packs'));
    if (!await d.exists()) await d.create(recursive: true);
    return _dir = d;
  }

  static Future<String> pathFor(String code) async =>
      join((await _packDir()).path, 'bible-$code.db');

  /// Кои пакети са налични на устройството.
  static Future<Set<String>> installed() async {
    final d = await _packDir();
    final out = <String>{};
    for (final f in d.listSync()) {
      final name = f.path.split(Platform.pathSeparator).last;
      if (name.startsWith('bible-') && name.endsWith('.db')) {
        out.add(name.substring(6, name.length - 3));
      }
    }
    return out;
  }

  static Future<bool> isInstalled(String code) async =>
      File(await pathFor(code)).exists();

  /// Сваля пакет, като известява за напредъка (0..1).
  ///
  /// ⚠ ПИШЕ СЕ В `.part` И СЕ ПРЕИМЕНУВА НАКРАЯ. Прекъсне ли се тегленето —
  /// изгубена мрежа, затворено приложение — на диска остава само недовършено
  /// парче с друго име. Инак половин файл би изглеждал като инсталиран език и
  /// четецът щеше да гърми при първото отваряне на глава, вместо просто да
  /// предложи ново сваляне.
  ///
  /// ⚠ Върнатата стойност е грешка или `null` при успех — не хвърля.
  /// Тегленето е нещо, което ЧЕСТО се проваля по съвсем обикновени причини
  /// (няма мрежа, няма място), и повикващият трябва да ги показва спокойно,
  /// а не да ги лови като изключение.
  static Future<String?> download(
    String code, {
    void Function(double progress, int received, int total)? onProgress,
    CancelToken? cancel,
  }) async {
    final target = await pathFor(code);
    final part = File('$target.part');
    HttpClient? client;
    IOSink? sink;
    try {
      if (await part.exists()) await part.delete();
      client = HttpClient();
      final req =
          await client.getUrl(Uri.parse('$kPacksBaseUrl/bible-$code.db'));
      final resp = await req.close();
      if (resp.statusCode != 200) {
        return 'Сървърът отговори с ${resp.statusCode}.';
      }
      final total = resp.contentLength;
      var received = 0;
      final out = part.openWrite();
      sink = out;
      await for (final chunk in resp) {
        if (cancel?.isCancelled ?? false) {
          await out.close();
          sink = null;
          if (await part.exists()) await part.delete();
          return null;
        }
        out.add(chunk);
        received += chunk.length;
        if (total > 0) {
          onProgress?.call(received / total, received, total);
        }
      }
      await out.flush();
      await out.close();
      sink = null;

      // ⚠ Проверка ПРЕДИ преименуването: сървър зад прокси може да върне
      // страница с грешка със статус 200. Файл под мегабайт не е превод.
      if (await part.length() < 500000) {
        await part.delete();
        return 'Полученото не прилича на езиков пакет.';
      }
      final dst = File(target);
      if (await dst.exists()) await dst.delete();
      await part.rename(target);
      return null;
    } catch (e) {
      return _friendly(e);
    } finally {
      await sink?.close();
      client?.close(force: true);
      if (await part.exists()) {
        try {
          await part.delete();
        } catch (_) {}
      }
    }
  }

  /// Изтрива свален пакет.
  static Future<void> remove(String code) async {
    final f = File(await pathFor(code));
    if (await f.exists()) await f.delete();
  }

  /// ⚠ Съобщенията са на човешки език, не техническият текст на грешката.
  /// „SocketException: Failed host lookup" не казва нищо на човек, който
  /// просто е извън обхват.
  static String _friendly(Object e) {
    final s = e.toString();
    if (e is SocketException || s.contains('Failed host lookup')) {
      return 'Няма връзка с интернет.';
    }
    if (s.contains('No space left')) {
      return 'Няма достатъчно място на устройството.';
    }
    return 'Свалянето не успя.';
  }
}

/// Дребен ключ за отказ — тегленето може да трае минута и човек трябва да
/// може да се откаже, без да чака.
class CancelToken {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;
}
