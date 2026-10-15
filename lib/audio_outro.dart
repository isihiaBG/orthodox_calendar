// Музиката в края на беседа (13.10.2026, по замисъл на автора на
// „Разговори…“): дудукът влиза едва доловимо под последното изречение, след
// гласа се засилва, звучи сам и затихва бавно — а заглавието на следващата
// беседа се чете върху затихването.
//
// ⚠ Записите на беседите НЕ се пипат: музиката е ОТДЕЛЕН плейър, а силата ѝ
// се движи оттук. Времената са одобрени на слух от автора (демонстрациите в
// tools/tts — виж CLAUDE.md, „Музиката между беседите").

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'audiobook.dart';

/// Фрагментите. Не са вързани за една книга.
const List<String> kOutroClips = [
  // ⚠ По 125 s: най-дългото — 60 s фон + надпис под илюстрацията + 44,6 s
  // засилване, задържане и затихване. По-късите записи са зациклени с
  // плавно преливане.
  'assets/audio_outro/duduk_1.mp3', // I. Mazia
  'assets/audio_outro/duduk_2.mp3', // арменска народна песен (Ikuzusotnek)
  'assets/audio_outro/duduk_3.mp3', // импровизация (SERGO.TEL)
  'assets/audio_outro/duduk_4.mp3', // същата песен, по-нататък
];

/// Кой дудук след коя беседа — ВИНАГИ един и същ (искане на автора,
/// 13.10.2026). Ключът е частта от регистъра на звука. Смяна за една
/// беседа — само тук. Номерът е индекс в [kOutroClips].
const Map<String, Map<String, int>> kOutroByBook = {
  'assets/chitalnya/razgovori.epub': {
    'title': 1,
    'c01': 0, 'c02': 2, 'c03': 3, 'c04': 1, 'c05': 0, 'c06': 2,
    'c07': 3, 'c08': 1, 'c09': 0, 'c10': 2, 'c11': 3, 'c12': 1,
    'c13': 0, 'c14': 2, 'c15': 3, 'c16': 1, 'c17': 0,
  },
};

/// Дудукът за беседа [part] (глава с пореден номер [index]) в книга
/// [bookAsset]. Книга без таблица — редуват се по номера на главата.
String outroClipFor(String bookAsset, String? part, int index) {
  final i = kOutroByBook[bookAsset]?[part];
  return kOutroClips[(i ?? index) % kOutroClips.length];
}

/// Времената (секунди) и силата (dB спрямо пълната).
class OutroTiming {
  static const double bedDb = -24; // фонът под гласа
  static const double bedIn = 5; // от нищо до фона
  static const double after = 0.6; // тишина на гласа преди засилването
  static const double swell = 4; // от фона до пълна сила
  static const double hold = 20; // пълна сила (26 беше „с една идея по-дълго“ — авторът)
  static const double fade = 14; // затихването до нищо
  static const double nextAt = 5; // следващата беседа — толкова след началото на затихването
  static const double minLead = 6; // музиката влиза поне толкова преди края на гласа
  static const double maxLead = 30; // …и най-много толкова (кратка беседа)
  static const double maxLeadLong = 60; // …дълга беседа (фрагментите са по 125 s)
  static const double longChapter = 20 * 60; // „дълга" беседа
  static const double shortSentence = 3; // по-кратко изречение не се брои за отделно
  static const double silentDb = -55;
  static const double titleLeadIn = 2.2; // заглавната: пауза, в която дудукът изплува преди посвещението
}

/// Откъде в беседата да влезе музиката (правила на автора, 13.10.2026):
/// - краят е последното изречение на САМАТА беседа — надписите под
///   илюстрацията накрая не се броят (под тях музиката просто остава фон);
/// - кратка беседа — от последното изречение, дълга (над 20 мин) — от
///   предпоследното: там и заключението е по-дълго;
/// - съвсем кратките изречения („Амин.") не се броят за отделни;
/// - влиза поне [OutroTiming.minLead] и най-много [maxLead] s преди края
///   на гласа — при по-дълги изречения влиза насред (тихо, не се усеща).
///
/// ⚠ Заглавната страница е различна (искане на автора): музиката е
/// постоянен фон под цялото посвещение и влиза малко преди него.
double outroStartOf(AudioChapter ch, {bool titlePage = false}) {
  final ss = ch.sentences;
  if (titlePage) {
    // Надписът под иконата вече не се чете — музиката влиза с посвещението
    // (или в паузата преди него — виж onCaptionSkip в book_reader.dart).
    final d = ss.indexWhere((s) => s.kind == 'dedication');
    if (d >= 0) return ss[d].start;
  }
  if (ss.isEmpty) return math.max(0, ch.duration - OutroTiming.minLead);
  var last = ss.length - 1;
  while (last > 0 && kOutroCaptionKinds.contains(ss[last].kind)) {
    last--;
  }
  final end = ss[last].end;
  final long = ch.duration >= OutroTiming.longChapter;
  final need = long ? 2 : 1;
  var k = last, counted = 0;
  while (k > 0) {
    if (ss[k].end - ss[k].start >= OutroTiming.shortSentence) counted++;
    if (counted >= need && end - ss[k].start >= OutroTiming.minLead) break;
    k--;
  }
  return math.max(ss[k].start, end - (long ? OutroTiming.maxLeadLong : OutroTiming.maxLead));
}

/// Надписи под илюстрации — не са край на беседата.
const Set<String> kOutroCaptionKinds = {'figcaption', 'caption'};

/// Да звучи ли музиката. Включено по подразбиране; пази се.
class AudioOutroSetting {
  static const _key = 'audio_outro_music';
  static final ValueNotifier<bool> notifier = ValueNotifier(true);
  static bool _loaded = false;

  static bool get value => notifier.value;

  static Future<void> loadOnce() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final p = await SharedPreferences.getInstance();
      notifier.value = p.getBool(_key) ?? true;
    } catch (_) {}
  }

  static Future<void> toggle() async {
    notifier.value = !notifier.value;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(_key, notifier.value);
    } catch (_) {}
  }
}

/// Един плейър за музиката, със силата в dB.
///
/// ⚠ Силата се мени ЛИНЕЙНО В dB (равномерно за ухото), на малки стъпки —
/// линейно по амплитуда затихването „пада" накрая.
class AudioOutro {
  // ⚠ Без собствено поемане на прекъсванията: аудио сесията я държи
  // плейърът на беседата, а музиката е само придружаване.
  final AudioPlayer _p = AudioPlayer(handleInterruptions: false);
  Timer? _ramp;
  double _db = OutroTiming.silentDb;
  int _gen = 0;
  bool _active = false;
  bool _disposed = false;

  /// Звучи ли (или затихва).
  bool get active => _active;

  static double _gain(double db) =>
      db <= OutroTiming.silentDb ? 0 : math.pow(10, db / 20).toDouble();

  Future<void> _rampTo(double target, double seconds, int gen) {
    _ramp?.cancel();
    final done = Completer<void>();
    final from = _db;
    final total = (seconds * 1000).round();
    if (total <= 0) {
      _db = target;
      unawaited(_p.setVolume(_gain(target)));
      done.complete();
      return done.future;
    }
    // ⚠ Времето се НАТРУПВА на стъпки от най-много 60 ms, а не се чете
    // направо от часовника. Задъха ли се нишката (точно когато се строи
    // следващата беседа), по часовника силата щеше да прескочи няколко dB
    // наведнъж — затихването звучеше като рязко спиране (автор, 13.10.2026).
    // Така то просто трае малко по-дълго.
    final sw = Stopwatch()..start();
    var last = 0, acc = 0;
    _ramp = Timer.periodic(const Duration(milliseconds: 40), (t) {
      if (gen != _gen || _disposed) {
        t.cancel();
        if (!done.isCompleted) done.complete();
        return;
      }
      final now = sw.elapsedMilliseconds;
      if (now - last > 400) audioLogAdd('музика: стъпката закъсня ${now - last} ms');
      acc += math.min(now - last, 60);
      last = now;
      final k = math.min(1.0, acc / total);
      _db = from + (target - from) * k;
      unawaited(_p.setVolume(_gain(_db)));
      if (k >= 1) {
        t.cancel();
        if (!done.isCompleted) done.complete();
      }
    });
    return done.future;
  }

  /// Пуска [asset] от нищо до фона под гласа (за [seconds], по подразбиране
  /// [OutroTiming.bedIn]).
  Future<void> beginBed(String asset, {double? seconds}) async {
    final gen = ++_gen;
    _active = true;
    audioLogAdd('музика: влиза ($asset)');
    try {
      await _p.setAsset(asset);
      if (gen != _gen) return;
      _db = OutroTiming.silentDb;
      await _p.setVolume(0);
      unawaited(_p.play());
      await _rampTo(OutroTiming.bedDb, seconds ?? OutroTiming.bedIn, gen);
    } catch (_) {
      if (gen == _gen) _active = false;
    }
  }

  /// Гласът свърши: засилване, задържане, затихване. [onNext] се вика
  /// [OutroTiming.nextAt] секунди след началото на затихването (тогава
  /// почва следващата беседа). Връща false, ако е прекъснато.
  Future<bool> finish({required VoidCallback onNext}) async {
    final gen = _gen;
    if (!_active) {
      audioLogAdd('музика: finish — НЕ звучи, преход няма');
      return false;
    }
    audioLogAdd('музика: finish — засилване');
    await Future.delayed(Duration(milliseconds: (OutroTiming.after * 1000).round()));
    if (gen != _gen) return _cut('след паузата');
    await _rampTo(0, OutroTiming.swell, gen);
    if (gen != _gen) return _cut('при засилването');
    audioLogAdd('музика: пълна сила');
    await Future.delayed(Duration(milliseconds: (OutroTiming.hold * 1000).round()));
    if (gen != _gen) return _cut('при задържането');
    audioLogAdd('музика: затихва');
    final fading = _rampTo(OutroTiming.silentDb, OutroTiming.fade, gen);
    await Future.delayed(Duration(milliseconds: (OutroTiming.nextAt * 1000).round()));
    if (gen != _gen) return _cut('при затихването');
    audioLogAdd('музика: следващата беседа');
    onNext();
    await fading;
    if (gen != _gen) return true;
    _active = false;
    await _p.stop();
    audioLogAdd('музика: свърши');
    return true;
  }

  bool _cut(String where) {
    audioLogAdd('музика: прекъсната $where');
    return false;
  }

  /// Прекъсване от човека (пауза, превъртане, затваряне): бързо, но
  /// плавно затихване — без рязко отрязване.
  Future<void> stop({double seconds = 1.0, String why = ''}) async {
    if (_active) audioLogAdd('музика: стоп ($why)');
    if (!_active) {
      _gen++;
      return;
    }
    final gen = ++_gen;
    await _rampTo(OutroTiming.silentDb, seconds, gen);
    if (gen != _gen) return;
    _active = false;
    try {
      await _p.stop();
    } catch (_) {}
  }

  Future<void> dispose() async {
    await stop(seconds: 0.8, why: 'четецът се затвори');
    _disposed = true;
    _ramp?.cancel();
    await _p.dispose();
  }
}
