// Преходът в края на житията (30.10.2026, по замисъл на автора): звън
// (камбани или клепало) влиза под последните думи, след няколко секунди
// пеенето се наслагва, звънът заглъхва плавно и остава едва доловим зад
// него, накрая двете затихват заедно — а следващото житие почва върху
// затихването. Без следващо — същото, като завършек.
//
// ⚠ Дудукът остава само за „Разговори…" (audio_outro.dart).
//
// Частите са в assets/audio_prehod (tools/tts/prehod.py): 9 звъна × 15
// откъса пеене; смесват се тук, на живо — затова влизането и затихването
// НЕ са в самите файлове. Времената са одобрени на слух от автора на
// страниците-проби (същите формули).

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import 'audio_outro.dart' show EndMusic;
import 'audiobook.dart' show audioLogAdd;

/// Времената (секунди) и силите (0–1).
class PrehodTiming {
  static const double lead = 4; // звънът влиза толкова преди края на гласа
  static const double fadeIn = 6; // звънът — от нищо до пълна сила
  static const double enter = 8; // пеенето влиза (от началото на звъна)
  static const double enterKlepalo = 9; // …след клепалото — малко по-късно
  static const double duck = 8; // звънът заглъхва зад пеенето
  static const double duckTo = 0.15; // …до толкова, и остава
  static const double chantIn = 5; // пеенето — от нищо до пълна сила
  static const double chantGain = 0.8;
  static const double chantLen = 40;
  static const double fadeOut = 12; // общото затихване накрая
  static const double nextAfterFade = 4; // следващото житие — толкова след началото на затихването
}

const int kPrehodZvan = 9; // 8 камбани + клепалото (последното)
const int kPrehodPesen = 15;

/// Кой звън и кое пеене за четиво [key] — ВИНАГИ едни и същи за едно
/// четиво (както дудуците на беседите), а различни четива ги редуват.
(int zvan, int pesen) prehodFor(String key) {
  // FNV-1a — стабилно между пусканията (String.hashCode не е).
  var h = 0x811c9dc5;
  for (final c in key.codeUnits) {
    h = ((h ^ c) * 0x01000193) & 0xffffffff;
  }
  final n = h % (kPrehodZvan * kPrehodPesen);
  return (n % kPrehodZvan + 1, n ~/ kPrehodZvan % kPrehodPesen + 1);
}

/// Силата на звъна в момент [t] от началото на прехода.
double prehodZvanGain(double t, double enter, double total) {
  var v = t < PrehodTiming.fadeIn ? math.pow(t / PrehodTiming.fadeIn, 2).toDouble() : 1.0;
  if (t >= enter) {
    v = t > enter + PrehodTiming.duck
        ? PrehodTiming.duckTo
        : PrehodTiming.duckTo +
            (1 - PrehodTiming.duckTo) * (0.5 + 0.5 * math.cos(math.pi * (t - enter) / PrehodTiming.duck));
  }
  if (t > total - PrehodTiming.fadeOut) v *= _qsin((total - t) / PrehodTiming.fadeOut);
  return v.clamp(0.0, 1.0);
}

/// Силата на пеенето в момент [t] от НЕГОВОТО начало.
double prehodPesenGain(double t) {
  const len = PrehodTiming.chantLen;
  var v = PrehodTiming.chantGain * _qsin(t / PrehodTiming.chantIn);
  if (t > len - PrehodTiming.fadeOut) v *= _qsin((len - t) / PrehodTiming.fadeOut);
  return v.clamp(0.0, 1.0);
}

double _qsin(double x) => math.sin(math.pi / 2 * x.clamp(0.0, 1.0));

class AudioPrehod implements EndMusic {
  // ⚠ Без собствено поемане на прекъсванията — като дудука.
  final AudioPlayer _z = AudioPlayer(handleInterruptions: false);
  final AudioPlayer _p = AudioPlayer(handleInterruptions: false);
  Timer? _tick;
  int _gen = 0;
  bool _active = false;
  bool _disposed = false;
  double _t = 0, _enter = PrehodTiming.enter, _total = 0;
  bool _pesenOn = false;
  double _master = 1; // за бързото затихване при прекъсване
  VoidCallback? _onNext;
  bool _nextDone = false;
  Completer<void>? _done;

  @override
  bool get active => _active;

  double get _nextAt => _total - PrehodTiming.fadeOut + PrehodTiming.nextAfterFade;

  /// [key] — четивото (по него се избира комбинацията).
  @override
  Future<void> beginBed(String key, {double? seconds}) async {
    final gen = ++_gen;
    _tick?.cancel();
    final (z, p) = prehodFor(key);
    _active = true;
    _t = 0;
    _pesenOn = false;
    _master = 1;
    _onNext = null;
    _nextDone = false;
    _enter = z == kPrehodZvan ? PrehodTiming.enterKlepalo : PrehodTiming.enter;
    _total = _enter + PrehodTiming.chantLen;
    final old = _done;
    if (old != null && !old.isCompleted) old.complete();
    _done = Completer<void>();
    audioLogAdd('преход: звън $z, пеене $p ($key)');
    try {
      await _z.setAsset('assets/audio_prehod/zvan_$z.mp3');
      await _p.setAsset('assets/audio_prehod/pesen_$p.mp3');
      if (gen != _gen) return;
      await _z.setVolume(0);
      await _p.setVolume(0);
      unawaited(_z.play());
    } catch (e) {
      audioLogAdd('преход: не тръгна — $e');
      if (gen == _gen) _end();
      return;
    }
    // ⚠ Времето се НАТРУПВА на стъпки от най-много 60 ms (както при
    // дудука): задъха ли се нишката, силата не прескача — само се бави.
    final sw = Stopwatch()..start();
    var last = 0;
    _tick = Timer.periodic(const Duration(milliseconds: 40), (t) {
      if (gen != _gen || _disposed) {
        t.cancel();
        return;
      }
      final now = sw.elapsedMilliseconds;
      if (now - last > 400) audioLogAdd('преход: стъпката закъсня ${now - last} ms');
      _t += math.min(now - last, 60) / 1000;
      last = now;
      if (!_pesenOn && _t >= _enter) {
        _pesenOn = true;
        unawaited(_p.play());
      }
      unawaited(_z.setVolume(_master * prehodZvanGain(_t, _enter, _total)));
      if (_pesenOn) unawaited(_p.setVolume(_master * prehodPesenGain(_t - _enter)));
      if (!_nextDone && _onNext != null && _t >= _nextAt) _fireNext();
      if (_t >= _total) {
        t.cancel();
        audioLogAdd('преход: свърши');
        _end();
      }
    });
  }

  void _fireNext() {
    _nextDone = true;
    final f = _onNext;
    _onNext = null;
    audioLogAdd('преход: следващото четиво');
    f?.call();
  }

  void _end() {
    _active = false;
    unawaited(_z.stop());
    unawaited(_p.stop());
    final d = _done;
    if (d != null && !d.isCompleted) d.complete();
  }

  /// Гласът свърши. [onNext] — в началото на общото затихване (+ малко),
  /// или веднага, ако то вече е минало. Връща false, ако е прекъснат.
  @override
  Future<bool> finish({required VoidCallback onNext}) async {
    if (!_active) {
      audioLogAdd('преход: finish — НЕ звучи');
      return false;
    }
    final gen = _gen;
    _onNext = onNext;
    if (_t >= _nextAt) _fireNext();
    await _done?.future;
    return gen == _gen;
  }

  /// Прекъсване от човека — бързо, но плавно затихване.
  @override
  Future<void> stop({double seconds = 1.0, String why = ''}) async {
    if (!_active) {
      _gen++;
      return;
    }
    audioLogAdd('преход: стоп ($why)');
    final gen = ++_gen;
    _tick?.cancel();
    _onNext = null;
    final from = _master;
    final steps = math.max(1, (seconds * 25).round());
    for (var i = 1; i <= steps; i++) {
      await Future.delayed(const Duration(milliseconds: 40));
      if (gen != _gen) return;
      _master = from * (1 - i / steps);
      unawaited(_z.setVolume(_master * prehodZvanGain(_t, _enter, _total)));
      if (_pesenOn) unawaited(_p.setVolume(_master * prehodPesenGain(_t - _enter)));
    }
    if (gen == _gen) _end();
  }

  @override
  Future<void> dispose() async {
    await stop(seconds: 0.8, why: 'четецът се затвори');
    _disposed = true;
    _tick?.cancel();
    await _z.dispose();
    await _p.dispose();
  }
}
