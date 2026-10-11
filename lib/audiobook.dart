// audiobook.dart
//
// Четене на глас (11.10.2026). Звукът НЕ е в APK-то: сваля се по глави от
// изданията в GitHub (качва ги tools/tts/publish_audio.py).
//
// ⚠⚠ ОБЩ РЕГИСТЪР (искане на автора): едно малко издание `audio-index` с
// файл `audio.json` казва за ВСИЧКИ книги — томовете, Читалнята, каквото
// дойде — кои глави имат звук и колко тежат. Приложението го сваля веднъж на
// сесия и го пази, тъй че етикетите в съдържанията се появяват навсякъде,
// без нов билд при всяка нова озвучена книга.
//
//   AudioRegistry      регистърът: книга (път до тома) → издание и глави
//   AudioBook          една книга: сваляне и изтриване на глави
//   AudioChapter       изреченията на беседата (показан текст + секунди)
//   AudioPlayback      плейърът: изречение по изречение, бележките след
//                      изречението си, ±5 секунди
//
// ⚠ ТАГЪТ НА ИЗДАНИЕТО НЕ СЕ СМЕНЯ — адресът е зашит тук, също като при
// езиковите пакети на Библията (bible_packs.dart). Нова беседа се добавя като
// файл към СЪЩОТО издание, а манифестът казва на приложението, че я има.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data' show BytesBuilder;

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' show join;
import 'package:path_provider/path_provider.dart';

/// Една част в изданието: беседа (`c02`) или бележка (`note3`).
class AudioPart {
  final int mp3Bytes;
  final int jsonBytes;

  /// Отпечатък на звука и изреченията — сменя ли се, беседата е генерирана
  /// наново и сваленото копие е остаряло.
  final String version;
  const AudioPart(this.mp3Bytes, this.jsonBytes, this.version);

  int get bytes => mp3Bytes + jsonBytes;
}

/// Едно изречение: показаният текст и къде е в звука.
class AudioSentence {
  final double start;
  final double end;
  final String text;

  /// Номерата на бележките под линия, които стоят в изречението.
  final List<int> notes;
  const AudioSentence(this.start, this.end, this.text, this.notes);
}

class AudioChapter {
  final String part;
  final String mp3Path;
  final double duration;
  final List<AudioSentence> sentences;
  const AudioChapter(this.part, this.mp3Path, this.duration, this.sentences);

  /// Кое изречение звучи в секунда [t] (последното, което е почнало).
  int indexAt(double t) {
    var lo = 0, hi = sentences.length - 1, r = -1;
    while (lo <= hi) {
      final m = (lo + hi) >> 1;
      if (sentences[m].start <= t + 0.05) {
        r = m;
        lo = m + 1;
      } else {
        hi = m - 1;
      }
    }
    return r;
  }
}

/// Регистърът на целия звук — един за всички книги.
class AudioRegistry {
  AudioRegistry._();

  static const String _url =
      'https://github.com/isihiaBG/orthodox_calendar/releases/download/audio-index/audio.json';

  /// Расте, щом се прочете нов регистър.
  static final ValueNotifier<int> revision = ValueNotifier(0);

  /// Път до тома → (издание, глави).
  static Map<String, (String, Map<String, AudioPart>)> _books = {};
  static bool _fetched = false;
  static Future<void>? _loading;

  static (String, Map<String, AudioPart>)? entry(String assetPath) => _books[assetPath];

  /// Чете запазения регистър и (веднъж на сесия) пита GitHub за нов.
  /// ⚠ Без мрежа се ползва запазеният — свалените глави се слушат и офлайн.
  static Future<void> load() => _loading ??= _load();

  static Future<void> _load() async {
    if (kIsWeb) return; // сваляне в браузъра няма (dart:io, CORS)
    final base = await getApplicationSupportDirectory();
    final local = File(join(base.path, 'audio', 'audio.json'));
    if (await local.exists()) {
      try {
        _parse(await local.readAsString());
        revision.value++;
      } catch (_) {}
    }
    if (_fetched) return;
    _fetched = true;
    try {
      final body = await _download(_url);
      if (body != null) {
        _parse(utf8.decode(body));
        await local.parent.create(recursive: true);
        await local.writeAsBytes(body);
        revision.value++;
      }
    } catch (_) {
      // офлайн — остава запазеното
    }
  }

  static void _parse(String s) {
    final books = (jsonDecode(s) as Map)['books'] as Map;
    _books = {
      for (final b in books.entries)
        b.key as String: (
          b.value['release'] as String,
          {
            for (final e in (b.value['parts'] as Map).entries)
              e.key as String: AudioPart((e.value['mp3'] as num).toInt(),
                  (e.value['json'] as num).toInt(), e.value['v'] as String),
          }
        ),
    };
  }
}

Future<List<int>?> _download(String url) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
  try {
    final resp = await (await client.getUrl(Uri.parse(url))).close();
    if (resp.statusCode != 200) return null;
    final b = BytesBuilder();
    await for (final c in resp) {
      b.add(c);
    }
    return b.takeBytes();
  } finally {
    client.close(force: true);
  }
}

/// Звукът на една книга.
class AudioBook {
  final String assetPath;
  AudioBook._(this.assetPath) {
    AudioRegistry.revision.addListener(_onRegistry);
  }

  static final Map<String, AudioBook> _cache = {};

  /// Всяка книга получава обект — дали има звук, казва регистърът (той може
  /// да дойде и след отварянето на четеца; тогава [revision] расте).
  static AudioBook? forAsset(String assetPath) {
    if (kIsWeb) return null;
    final b = _cache.putIfAbsent(assetPath, () => AudioBook._(assetPath));
    unawaited(b.load());
    return b;
  }

  String? get _release => AudioRegistry.entry(assetPath)?.$1;
  Map<String, AudioPart> get _parts => AudioRegistry.entry(assetPath)?.$2 ?? const {};

  String get _baseUrl =>
      'https://github.com/isihiaBG/orthodox_calendar/releases/download/$_release';

  /// Частта на главата — името на файла ѝ без разширение
  /// (`Text/c02.xhtml` → `c02`, `index_split_397.xhtml` → `index_split_397`).
  static String? partOf(String href) {
    final m = RegExp(r'([^/]+)\.x?html?$').firstMatch(href.split('#').first);
    return m?.group(1);
  }

  /// Расте при всяка промяна — сваляне, изтриване, нов регистър. Слушат го
  /// съдържанието и лентата, за да сменят етикета веднага.
  final ValueNotifier<int> revision = ValueNotifier(0);

  /// Напредъкът на текущите сваляния (0..1), по част.
  final Map<String, double> progress = {};

  final Set<String> _downloaded = {};
  Future<void>? _loading;

  Future<void> load() => _loading ??= () async {
        await AudioRegistry.load();
        await _scanDownloaded();
        revision.value++;
      }();

  void _onRegistry() async {
    await _scanDownloaded();
    revision.value++;
  }

  Directory? _dir;
  Future<Directory> _folder() async {
    if (_dir != null) return _dir!;
    final base = await getApplicationSupportDirectory();
    // По името на тома — уникално и не зависи от изданието.
    final key = assetPath.split('/').last.replaceAll(RegExp(r'\.epub$'), '');
    final d = Directory(join(base.path, 'audio', key));
    if (!await d.exists()) await d.create(recursive: true);
    return _dir = d;
  }

  Future<void> _scanDownloaded() async {
    final d = await _folder();
    _downloaded.clear();
    for (final p in _parts.keys) {
      final v = File(join(d.path, '$p.v'));
      if (await v.exists() &&
          await File(join(d.path, '$p.mp3')).exists() &&
          (await v.readAsString()).trim() == _parts[p]!.version) {
        _downloaded.add(p);
      }
    }
  }

  /// Има ли беседата звук (в изданието).
  bool has(String? part) => part != null && _parts.containsKey(part);

  /// Свалена ли е — и то в текущата си версия.
  bool isDownloaded(String? part) => part != null && _downloaded.contains(part);

  bool isDownloading(String? part) => part != null && progress.containsKey(part);

  /// Колко тежи беседата заедно с бележките ѝ — бележките се знаят чак от
  /// изреченията, затова тук се брои само самата беседа (те са малки).
  int sizeOf(String part) => _parts[part]?.bytes ?? 0;

  /// Сваля беседата и бележките ѝ. Връща грешка или `null` при успех.
  ///
  /// ⚠ Пише в `.part` и преименува накрая — същото правило като при
  /// езиковите пакети: прекъснато тегление не бива да изглежда като свалено.
  Future<String?> download(String part) async {
    if (!_parts.containsKey(part)) return 'Тази беседа още няма звук.';
    progress[part] = 0;
    revision.value++;
    try {
      final total = _parts[part]!.bytes;
      var done = 0;
      for (final ext in ['json', 'mp3']) {
        final err = await _fetchTo(part, ext, (n) {
          progress[part] = (done + n) / total;
          revision.value++;
        });
        if (err != null) return err;
        done += ext == 'json' ? _parts[part]!.jsonBytes : _parts[part]!.mp3Bytes;
      }
      // Бележките, които беседата чете — малки, свалят се заедно с нея.
      final ch = await _readChapter(part);
      for (final n in {for (final s in ch.sentences) ...s.notes}) {
        final np = 'note$n';
        if (!_parts.containsKey(np) || isDownloaded(np)) continue;
        for (final ext in ['json', 'mp3']) {
          final err = await _fetchTo(np, ext, null);
          if (err != null) return err;
        }
        await _markDone(np);
      }
      await _markDone(part);
      return null;
    } catch (e) {
      return _friendly(e);
    } finally {
      progress.remove(part);
      revision.value++;
    }
  }

  Future<void> _markDone(String part) async {
    final d = await _folder();
    await File(join(d.path, '$part.v')).writeAsString(_parts[part]!.version);
    _downloaded.add(part);
  }

  /// Изтрива свалена беседа (бележките остават — те са общи и малки).
  Future<void> remove(String part) async {
    final d = await _folder();
    for (final ext in ['mp3', 'json', 'v']) {
      final f = File(join(d.path, '$part.$ext'));
      if (await f.exists()) await f.delete();
    }
    _downloaded.remove(part);
    revision.value++;
  }

  Future<String?> _fetchTo(String part, String ext, void Function(int)? onBytes) async {
    final d = await _folder();
    final target = File(join(d.path, '$part.$ext'));
    final tmp = File('${target.path}.part');
    final client = HttpClient();
    try {
      final req = await client.getUrl(Uri.parse('$_baseUrl/$part.$ext'));
      final resp = await req.close();
      if (resp.statusCode != 200) return 'Сървърът отговори с ${resp.statusCode}.';
      final out = tmp.openWrite();
      var n = 0;
      await for (final chunk in resp) {
        out.add(chunk);
        n += chunk.length;
        onBytes?.call(n);
      }
      await out.close();
      if (await target.exists()) await target.delete();
      await tmp.rename(target.path);
      return null;
    } finally {
      client.close(force: true);
      if (await tmp.exists()) {
        try {
          await tmp.delete();
        } catch (_) {}
      }
    }
  }

  Future<AudioChapter> _readChapter(String part) async {
    final d = await _folder();
    final j = jsonDecode(await File(join(d.path, '$part.json')).readAsString()) as Map;
    return AudioChapter(
      part,
      join(d.path, '$part.mp3'),
      (j['duration'] as num).toDouble(),
      [
        for (final s in j['sents'] as List)
          AudioSentence((s['t'] as num).toDouble(), (s['e'] as num).toDouble(),
              s['s'] as String, [for (final n in (s['n'] as List? ?? [])) (n as num).toInt()]),
      ],
    );
  }

  /// Изреченията на свалена беседа.
  Future<AudioChapter?> chapter(String part) async {
    if (!isDownloaded(part)) return null;
    try {
      return await _readChapter(part);
    } catch (_) {
      return null;
    }
  }

  /// Пътят до звука на бележка, ако е свалена.
  Future<String?> notePath(int n) async {
    if (!isDownloaded('note$n')) return null;
    return join((await _folder()).path, 'note$n.mp3');
  }

  static String _friendly(Object e) {
    final s = e.toString();
    if (e is SocketException || s.contains('Failed host lookup')) {
      return 'Няма връзка с интернет.';
    }
    if (s.contains('No space left')) return 'Няма достатъчно място на устройството.';
    return 'Свалянето не успя.';
  }
}

/// „22 MB" — за прозорчето и етикета.
String audioSizeLabel(int bytes) {
  final mb = bytes / (1024 * 1024);
  return mb < 1 ? '${(bytes / 1024).round()} KB' : '${mb.round()} MB';
}

/// Плейърът на една беседа.
///
/// ⚠ Бележката се пуска СЛЕД изречението си, в отделен плейър, а беседата
/// чака: така е и в печатната книга — бележката се чете, когато стигнеш до
/// номера ѝ, не в края на главата.
class AudioPlayback {
  final AudioBook book;
  final AudioChapter chapter;
  final AudioPlayer _main = AudioPlayer();
  final AudioPlayer _note = AudioPlayer();

  /// Кое изречение звучи (-1 — нищо).
  final ValueNotifier<int> sentence = ValueNotifier(-1);
  final ValueNotifier<bool> playing = ValueNotifier(false);
  final ValueNotifier<double> position = ValueNotifier(0);

  /// Да се четат ли бележките под линия.
  bool withNotes = true;

  final Set<int> _notesDone = {};
  bool _inNote = false;
  final List<StreamSubscription> _subs = [];

  AudioPlayback(this.book, this.chapter);

  Future<void> start({int fromSentence = 0}) async {
    await _main.setFilePath(chapter.mp3Path);
    _subs.add(_main.positionStream.listen(_onPosition));
    _subs.add(_main.playerStateStream.listen((s) {
      if (!_inNote) playing.value = s.playing && s.processingState != ProcessingState.completed;
      if (s.processingState == ProcessingState.completed) {
        playing.value = false;
      }
    }));
    await seekToSentence(fromSentence);
    unawaited(_main.play());
  }

  void _onPosition(Duration d) {
    if (_inNote) return;
    final t = d.inMilliseconds / 1000.0;
    position.value = t;
    final cur = sentence.value;
    // Бележката — щом изречението с нея свърши.
    if (withNotes && cur >= 0 && cur < chapter.sentences.length) {
      final s = chapter.sentences[cur];
      if (s.notes.isNotEmpty && t >= s.end && !_notesDone.contains(cur)) {
        _notesDone.add(cur);
        unawaited(_playNotes(s.notes));
        return;
      }
    }
    final i = chapter.indexAt(t);
    if (i != cur) sentence.value = i;
  }

  Future<void> _playNotes(List<int> notes) async {
    _inNote = true;
    await _main.pause();
    try {
      for (final n in notes) {
        final p = await book.notePath(n);
        if (p == null) continue;
        await _note.setFilePath(p);
        await _note.play();
        await _note.processingStateStream
            .firstWhere((s) => s == ProcessingState.completed);
        await _note.stop();
      }
    } finally {
      _inNote = false;
    }
    await _main.play();
  }

  Future<void> seekToSentence(int i) async {
    if (chapter.sentences.isEmpty) return;
    i = i.clamp(0, chapter.sentences.length - 1);
    _notesDone.removeWhere((k) => k >= i);
    sentence.value = i;
    await _main.seek(Duration(milliseconds: (chapter.sentences[i].start * 1000).round()));
  }

  Future<void> toggle() async {
    if (_inNote) {
      await _note.stop();
      _inNote = false;
    }
    if (_main.playing) {
      await _main.pause();
    } else {
      if (_main.processingState == ProcessingState.completed) await seekToSentence(0);
      await _main.play();
    }
  }

  Future<void> skip(double seconds) async {
    if (_inNote) {
      await _note.stop();
      _inNote = false;
    }
    final t = (_main.position.inMilliseconds / 1000.0 + seconds)
        .clamp(0.0, chapter.duration);
    _notesDone.removeWhere((k) => chapter.sentences[k].end > t);
    await _main.seek(Duration(milliseconds: (t * 1000).round()));
  }

  Future<void> dispose() async {
    for (final s in _subs) {
      await s.cancel();
    }
    await _main.dispose();
    await _note.dispose();
    sentence.dispose();
    playing.dispose();
    position.dispose();
  }
}
