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

/// Фрагментите. Не са вързани за една книга — всяка книга със звук ги
/// редува по реда на главите си ([outroClipFor]).
const List<String> kOutroClips = [
  'assets/audio_outro/duduk_1.mp3', // I. Mazia — любимият на автора, затова първи
  'assets/audio_outro/duduk_2.mp3', // арменска народна песен (Ikuzusotnek)
  'assets/audio_outro/duduk_3.mp3', // импровизация (SERGO.TEL)
  'assets/audio_outro/duduk_4.mp3', // същата песен, по-нататък
];

/// Кой фрагмент звучи след глава с пореден номер [index] в книгата.
/// ⚠ Тук е мястото за изрично закачане на фрагмент към глава, ако авторът
/// поиска — засега фрагментите просто се редуват.
String outroClipFor(String bookAsset, int index) =>
    kOutroClips[index % kOutroClips.length];

/// Времената (секунди) и силата (dB спрямо пълната).
class OutroTiming {
  static const double bedDb = -24; // фонът под гласа
  static const double bedIn = 5; // от нищо до фона
  static const double after = 0.6; // тишина на гласа преди засилването
  static const double swell = 4; // от фона до пълна сила
  static const double hold = 16; // пълна сила
  static const double fade = 14; // затихването до нищо
  static const double nextAt = 5; // следващата беседа — толкова след началото на затихването
  static const double minLead = 6; // музиката влиза поне толкова преди края на гласа
  static const double maxLead = 40; // …и най-много толкова (фрагментът е 80 s)
  static const double silentDb = -55;
}

/// Откъде в беседата да влезе музиката: началото на последното изречение,
/// а ако то е по-късо от [OutroTiming.minLead] — на по-ранно.
double outroStartOf(AudioChapter ch) {
  if (ch.sentences.isEmpty) return math.max(0, ch.duration - OutroTiming.minLead);
  final end = ch.sentences.last.end;
  var t = ch.sentences.first.start;
  for (final s in ch.sentences.reversed) {
    if (end - s.start >= OutroTiming.minLead) {
      t = s.start;
      break;
    }
  }
  return math.max(t, end - OutroTiming.maxLead);
}

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
    final sw = Stopwatch()..start();
    _ramp = Timer.periodic(const Duration(milliseconds: 40), (t) {
      if (gen != _gen || _disposed) {
        t.cancel();
        if (!done.isCompleted) done.complete();
        return;
      }
      final k = math.min(1.0, sw.elapsedMilliseconds / total);
      _db = from + (target - from) * k;
      unawaited(_p.setVolume(_gain(_db)));
      if (k >= 1) {
        t.cancel();
        if (!done.isCompleted) done.complete();
      }
    });
    return done.future;
  }

  /// Пуска [asset] от нищо до фона под гласа.
  Future<void> beginBed(String asset) async {
    final gen = ++_gen;
    _active = true;
    try {
      await _p.setAsset(asset);
      if (gen != _gen) return;
      _db = OutroTiming.silentDb;
      await _p.setVolume(0);
      unawaited(_p.play());
      await _rampTo(OutroTiming.bedDb, OutroTiming.bedIn, gen);
    } catch (_) {
      if (gen == _gen) _active = false;
    }
  }

  /// Гласът свърши: засилване, задържане, затихване. [onNext] се вика
  /// [OutroTiming.nextAt] секунди след началото на затихването (тогава
  /// почва следващата беседа). Връща false, ако е прекъснато.
  Future<bool> finish({required VoidCallback onNext}) async {
    final gen = _gen;
    if (!_active) return false;
    await Future.delayed(Duration(milliseconds: (OutroTiming.after * 1000).round()));
    if (gen != _gen) return false;
    await _rampTo(0, OutroTiming.swell, gen);
    if (gen != _gen) return false;
    await Future.delayed(Duration(milliseconds: (OutroTiming.hold * 1000).round()));
    if (gen != _gen) return false;
    final fading = _rampTo(OutroTiming.silentDb, OutroTiming.fade, gen);
    await Future.delayed(Duration(milliseconds: (OutroTiming.nextAt * 1000).round()));
    if (gen != _gen) return false;
    onNext();
    await fading;
    if (gen != _gen) return true;
    _active = false;
    await _p.stop();
    return true;
  }

  /// Прекъсване от човека (пауза, превъртане, затваряне): бързо, но
  /// плавно затихване — без рязко отрязване.
  Future<void> stop({double seconds = 1.0}) async {
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
    await stop(seconds: 0.8);
    _disposed = true;
    _ramp?.cancel();
    await _p.dispose();
  }
}
