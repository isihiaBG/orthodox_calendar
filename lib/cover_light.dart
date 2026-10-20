// Обем и отблясъци върху корица — прилагат се ПРИ ПОКАЗВАНЕ (19.10.2026).
//
// Кориците в assets не се пипат: [LitCover] обвива който и да е
// ImageProvider, прекарва картинката веднъж през шейдъра
// shaders/cover_light.frag (корица × карта на светлината) и подава готовата.
// Така важи и за всяка бъдеща корица, а Cover Flow, отражението и летящата
// корица при отваряне получават едно и също, без да знаят за ефекта.
//
// Картата прави tools/chitalnya/scripts/05_cover_light.py от маската на
// потребителя. Друга карта = друго име в [CoverLight] — по същия начин могат
// да се добавят и алтернативни шейдъри.

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart' show rootBundle;

/// Радиусът на заоблените ъгли — дял от ширината. ⚠ Същото число стои като
/// `kCorner` в shaders/cover_light.frag; менят се заедно.
const double kCoverCornerRadius = 0.012;

/// Картите на светлината в пакета.
class CoverLight {
  static const book1 = 'assets/cover_light/book1.png';
}

class LitCover extends ImageProvider<LitCover> {
  final ImageProvider base;
  final String light;

  const LitCover(this.base, {this.light = CoverLight.book1});

  static Future<ui.FragmentProgram>? _program;
  static final Map<String, Future<ui.Image>> _lights = {};

  @override
  Future<LitCover> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(LitCover key, ImageDecoderCallback decode) =>
      OneFrameImageStreamCompleter(_load());

  Future<ImageInfo> _load() async {
    final cover = await _resolve(base);
    try {
      final program = await (_program ??=
          ui.FragmentProgram.fromAsset('shaders/cover_light.frag'));
      final lightImg = await (_lights[light] ??= _decodeAsset(light));
      final w = cover.image.width, h = cover.image.height;
      final shader = program.fragmentShader()
        ..setFloat(0, w.toDouble())
        ..setFloat(1, h.toDouble())
        ..setImageSampler(0, cover.image)
        ..setImageSampler(1, lightImg);
      final rec = ui.PictureRecorder();
      ui.Canvas(rec).drawRect(
          ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
          ui.Paint()..shader = shader);
      final pic = rec.endRecording();
      final out = await pic.toImage(w, h);
      pic.dispose();
      shader.dispose();
      cover.dispose();
      return ImageInfo(image: out);
    } catch (e) {
      // ⚠ Без ефекта, но не без корица.
      debugPrint('LitCover: $e');
      return cover;
    }
  }

  /// Картинката на [p], собствено копие (кешът може да изхвърли своето).
  static Future<ImageInfo> _resolve(ImageProvider p) {
    final c = Completer<ImageInfo>();
    final stream = p.resolve(ImageConfiguration.empty);
    late final ImageStreamListener l;
    l = ImageStreamListener((info, _) {
      if (!c.isCompleted) c.complete(info.clone());
      stream.removeListener(l);
    }, onError: (e, st) {
      if (!c.isCompleted) c.completeError(e, st);
      stream.removeListener(l);
    });
    stream.addListener(l);
    return c.future;
  }

  static Future<ui.Image> _decodeAsset(String path) async {
    final data = await rootBundle.load(path);
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    return (await codec.getNextFrame()).image;
  }

  @override
  bool operator ==(Object other) =>
      other is LitCover && other.base == base && other.light == light;

  @override
  int get hashCode => Object.hash(base, light);
}
