import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';

import 'audiobook.dart';

/// Звукът във фонов режим (26.10.2026, доклад на автора: „Разговори…“ +
/// навигация в колата — на всяка минута-две звукът спира, а при връщане в
/// календара продължава сам, без ▶).
///
/// ⚠⚠ ПРИЧИНАТА: без услуга на преден план (foreground service) Android
/// смята приложението във фонов режим за „кеширано“ и ЗАМРАЗЯВА процеса —
/// и плейъра, и Dart кода (прескачането на надписите, бележките, следващата
/// беседа). Звукът спира насред изречение, без пауза; при връщане процесът
/// се размразява и всичко тръгва оттам, където е спряло. Huawei/Honor
/// замразяват особено рано.
///
/// Лекът е `audio_service`: докато има беседа, тече услуга „медия“ с
/// известие (▶/⏸, ±15 s) — и процесът остава жив. Пътьом идват бутоните на
/// слушалките, волана в колата и заключения екран.
///
/// ⚠ Тук е само МОСТЪТ. Плейърът остава [AudioPlayback]; бутоните в
/// известието викат същите методи като копчетата в четеца (действие на
/// човека — маха и музиката в края, както там).
///
/// ⚠ `androidStopForegroundOnPause: false` — нарочно. При пауза услугата
/// остава на преден план, инак ▶ от известието или волана при приложение
/// във фонов режим гърми на Android 12+ (стартиране на услуга от фонов
/// режим). Известието изчезва, щом беседата се затвори.
class AudioBackground {
  AudioBackground._();

  static _Handler? _handler;
  static Future<_Handler?>? _initing;

  static Future<_Handler?> _ensure() {
    if (_handler != null) return Future.value(_handler);
    return _initing ??= () async {
      try {
        _handler = await AudioService.init(
          builder: _Handler.new,
          config: const AudioServiceConfig(
            androidNotificationChannelId: 'isihiabg.orthodox_calendar.audio',
            androidNotificationChannelName: 'Четене на глас',
            androidNotificationIcon: 'mipmap/ic_launcher',
            androidStopForegroundOnPause: false,
            fastForwardInterval: Duration(seconds: 15),
            rewindInterval: Duration(seconds: 15),
          ),
        );
      } catch (e) {
        // Без услугата звукът пак върви — само не и дълго във фонов режим.
        audioLogAdd('фонова услуга: НЕ тръгна ($e)');
        debugPrint('AudioBackground: $e');
      }
      return _handler;
    }();
  }

  /// Беседата [pb] започва — известието минава на нея.
  static Future<void> attach(AudioPlayback pb, {required String title, required String book}) async {
    final h = await _ensure();
    h?._attach(pb, title, book);
  }

  /// Беседата [pb] се затваря. ⚠ Услугата спира СЛЕД малко, не веднага: при
  /// преминаване към следващата беседа старата се затваря, а новата идва
  /// след секунда — спряна междувременно, услугата не може да тръгне пак,
  /// докато приложението е във фонов режим.
  static void detach(AudioPlayback pb) => _handler?._detach(pb);
}

class _Handler extends BaseAudioHandler with SeekHandler {
  AudioPlayback? _pb;
  Timer? _idleTimer;
  int _lastSecond = -1;

  void _attach(AudioPlayback pb, String title, String book) {
    _idleTimer?.cancel();
    _unlisten();
    _pb = pb;
    mediaItem.add(MediaItem(
      id: '${pb.book.hashCode}:${pb.chapter.part}',
      title: title,
      album: book,
      duration: Duration(milliseconds: (pb.chapter.duration * 1000).round()),
    ));
    pb.playing.addListener(_push);
    pb.position.addListener(_onPosition);
    _push();
  }

  void _unlisten() {
    _pb?.playing.removeListener(_push);
    _pb?.position.removeListener(_onPosition);
  }

  void _detach(AudioPlayback pb) {
    if (_pb != pb) return;
    _unlisten();
    _pb = null;
    _idleTimer?.cancel();
    _idleTimer = Timer(const Duration(seconds: 8), () {
      if (_pb != null) return;
      playbackState.add(playbackState.value.copyWith(
        playing: false,
        processingState: AudioProcessingState.idle,
      ));
      mediaItem.add(null);
    });
  }

  // Позицията в известието — веднъж в секунда стига (лентата я дорисува).
  void _onPosition() {
    final s = _pb?.position.value.floor() ?? -1;
    if (s != _lastSecond) {
      _lastSecond = s;
      _push();
    }
  }

  void _push() {
    final pb = _pb;
    if (pb == null) return;
    final playing = pb.playing.value;
    playbackState.add(PlaybackState(
      controls: [
        MediaControl.rewind,
        playing ? MediaControl.pause : MediaControl.play,
        MediaControl.fastForward,
      ],
      systemActions: const {MediaAction.seek},
      androidCompactActionIndices: const [0, 1, 2],
      processingState: pb.completed ? AudioProcessingState.completed : AudioProcessingState.ready,
      playing: playing,
      updatePosition: Duration(milliseconds: (pb.position.value * 1000).round()),
      speed: 1.0,
    ));
  }

  @override
  Future<void> play() async {
    final pb = _pb;
    if (pb != null && !pb.playing.value) await pb.toggle();
  }

  @override
  Future<void> pause() async {
    final pb = _pb;
    if (pb != null && pb.playing.value) await pb.toggle();
  }

  @override
  Future<void> stop() => pause();

  @override
  Future<void> fastForward() async => _pb?.skip(15);

  @override
  Future<void> rewind() async => _pb?.skip(-15);

  @override
  Future<void> seek(Duration position) async {
    final pb = _pb;
    if (pb == null) return;
    await pb.skip(position.inMilliseconds / 1000.0 - pb.position.value);
  }
}
