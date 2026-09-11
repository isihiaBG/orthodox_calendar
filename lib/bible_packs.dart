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

  /// Двубуквеното съкращение за полето в лентата („гд", „ив").
  ///
  /// ⚠ ЗАШИТО ТУК, а не четено от пакета: точно когато трябва — при
  /// НЕсвален превод — пакетът го няма на диска, тъй че `languages()` не
  /// може да го каже. Без него лентата показваше ЧЕРТА и човекът не
  /// разбираше кой език му липсва. Стойностите са същите като в
  /// `languages.bg_abbr`. (11.09.2026.)
  final String abbr;

  /// Големина на файла в байтове — показва се ПРЕДИ тегленето, за да знае
  /// човек какво почва, особено на мобилни данни.
  final int bytes;

  const BiblePack({
    required this.code,
    required this.title,
    required this.short,
    required this.abbr,
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
  BiblePack(code: 'cs', title: 'Църковнославянски (гражданска)', short: 'Църковнослав. (гражд.)', abbr: 'цг', bytes: 8581120),
  BiblePack(code: 'r', title: 'Руски (синодален)', short: 'Руски', abbr: 'ру', bytes: 13688832),
  BiblePack(code: 'el', title: 'Гръцки (Нов и Стар завет, като Старият завет е по Септуагинта)', short: 'Гръцки', abbr: 'гр', bytes: 10498048),
  BiblePack(code: 'l', title: 'Латински (Nova Vulgata)', short: 'Латински', abbr: 'лт', bytes: 5910528),
  BiblePack(code: 'en-kjv', title: 'Английски (KJV)', short: 'Английски', abbr: 'ан', bytes: 8486912),
  BiblePack(code: 'sb', title: 'Сръбски (синодален)', short: 'Сръбски', abbr: 'ср', bytes: 8966144),
  BiblePack(code: 'i', title: 'Иврит', short: 'Иврит', abbr: 'ив', bytes: 7536640),
  BiblePack(code: 'u', title: 'Грузински', short: 'Грузински', abbr: 'гз', bytes: 11608064),
  BiblePack(code: 'y', title: 'Грузински (древен)', short: 'Грузински (др.)', abbr: 'гд', bytes: 2752512),
];

/// ⚠ ЕДИНСТВЕНАТА точка, през която се разбира какво може да се свали.
/// Дойде ли ден за манифест от сървъра, подменя се само тя.
/// ⚠⚠ ДВАТА ГРЪЦКИ БЯХА СЛЕТИ В ЕДИН (11.09.2026).
///
/// Дотук гръцкият се предлагаше на две: `g` (Нов завет) и `el-r`
/// (Септуагинта, Стар завет). Човек сваляше единия, отваряше книга от
/// другия завет и намираше празно — после сваляше и втория. Двата обаче НЕ
/// СЕ ПРЕПОКРИВАТ никъде (мерено: 7942 + 28057 стиха, 27 + 49 книги,
/// сечение НУЛА), тъй че са едно нещо, разделено по недоразумение.
/// (Наблюдение на потребителя.)
///
/// ⚠ Старите кодове ОСТАВАТ разпознаваеми: вече инсталирани копия ги носят
/// на диска, а споделени линкове ги назоваваt в адреса си (`@g`, `@el-r`).
/// Приравняват се към `el` — виж [greekCanonical].
const kGreekLegacy = {'g', 'el-r'};

/// Кодът, под който този превод се предлага ДНЕС.
///
/// ⚠ Ползва се при разчитане на споделен адрес: линк с `@g` или `@el-r`
/// сочи гръцкия, а не „непознат превод". Старите два файла вече ги НЯМА в
/// изданието (изтрити 11.09.2026), тъй че предложение да се свали `g` би
/// завело човека на 404.
///
/// ⚠⚠ БЕЗУСЛОВНО, дори старият файл още да стои на диска. Първата версия
/// го запазваше „щом човекът има какво да прочете веднага" — и в това има
/// ДУПКА: старият пакет покрива само ЕДИН завет. Линк с `@g` (Нов завет)
/// към Псалом тогава дава ПРАЗНА колона, защото `g` няма Стария завет, а
/// падането към вградените не се задейства (другата половина е налице).
/// Точно това недоразумение сливането премахва — не бива да се връща през
/// задната врата. (Потвърдено от потребителя, 11.09.2026.)
String greekCanonical(String code) =>
    kGreekLegacy.contains(code) ? 'el' : code;

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
