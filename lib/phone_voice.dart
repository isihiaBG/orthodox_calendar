// phone_voice.dart
//
// Четене на глас с гласа на ТЕЛЕФОНА (Google, безплатно, без мрежа) — за
// всяко четиво, и за онези без запис (замисъл на автора, 28.10.2026). Записът
// ([AudioPlayback]) остава по-доброто: свален ли е, слушалките пускат него.
//
// ⚠ Гласът получава НЕ показания текст, а разгънатия (speech_text.dart):
// годините, съкращенията и препратките — с думи.
//
// ⚠ ЦЕЛИ АБЗАЦИ, не изречения: гласът чете с по-добра интонация, когато вижда
// повече. Коя дума чете, той съобщава сам (мерено на Honor, 28.10.2026: дума
// по дума, ~15 знака в секунда) — оттам идва маркирането на изречението.
//
// ⚠ Пауза в Android няма — „пауза" спира, а „пусни" почва изречението отначало.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'audiobook.dart';
import 'speech_text.dart';

/// Готов ли е гласът на телефона.
enum PhoneVoiceState {
  ready,

  /// Няма български глас (или двигател) — може да се свали.
  noBulgarian,
}

/// Двигателят — един за цялото приложение.
class PhoneVoice {
  PhoneVoice._();

  static final FlutterTts _tts = FlutterTts();
  static const _channel = MethodChannel('isihiabg/update');
  static const _google = 'com.google.android.tts';

  /// Знаци в секунда — за приблизителното време в плейъра.
  static const charsPerSecond = 15.0;

  static Future<PhoneVoiceState>? _ready;
  static PhoneVoicePlayback? _owner;

  static Future<PhoneVoiceState> ready() => _ready ??= _init();

  static Future<PhoneVoiceState> _init() async {
    try {
      final engines = ((await _tts.getEngines) as List?)?.cast<Object?>() ?? const [];
      if (engines.contains(_google)) await _tts.setEngine(_google);
      final available = await _tts.isLanguageAvailable('bg-BG');
      if (available != true) {
        audioLogAdd('гласът на телефона: няма български (двигатели: $engines)');
        _ready = null; // да се провери пак, след като човекът го свали
        return PhoneVoiceState.noBulgarian;
      }
      await _tts.setLanguage('bg-BG');
      // Гласът без мрежа, ако го има — мрежовият спира без връзка.
      final voices = ((await _tts.getVoices) as List?) ?? const [];
      Map? local;
      for (final v in voices) {
        if (v is Map && '${v['locale']}'.toLowerCase().startsWith('bg') &&
            '${v['network_required']}' != '1' &&
            '${v['name']}'.contains('-x-')) {
          local = v;
          break;
        }
      }
      if (local != null) {
        await _tts.setVoice({'name': '${local['name']}', 'locale': '${local['locale']}'});
      }
      await _tts.setSpeechRate(0.5);
      await _tts.awaitSpeakCompletion(false);
      _tts.setProgressHandler((_, s, e, _) => _owner?._onProgress(s, e));
      _tts.setStartHandler(() => _owner?._started = true);
      _tts.setCompletionHandler(() => _owner?._onDone());
      _tts.setErrorHandler((msg) => _owner?._onError('$msg'));
      audioLogAdd('гласът на телефона: готов (${local?['name'] ?? 'по подразбиране'})');
      return PhoneVoiceState.ready;
    } catch (e) {
      audioLogAdd('гласът на телефона: грешка при подготовка — $e');
      _ready = null;
      return PhoneVoiceState.noBulgarian;
    }
  }

  /// Отваря екрана на Google за сваляне на гласовете. false — не се отвори.
  static Future<bool> install() async {
    try {
      return await _channel.invokeMethod<bool>('ttsInstall') ?? false;
    } catch (_) {
      return false;
    }
  }
}

// ── текстът ──────────────────────────────────────────────────────────────

/// Блок от четивото: текстът (както в цитатите/търсенето) + връзките в него
/// и местата, които гласът прескача (номерата на бележките под линия).
class ReadingBlock {
  final String text;
  final List<SpeechLink> links;
  final List<(int, int)> drop;
  const ReadingBlock(this.text, [this.links = const [], this.drop = const []]);

  /// Друг блок, сложен отзад с [sep] между тях.
  ReadingBlock join(ReadingBlock b, String sep) {
    final d = text.length + sep.length;
    return ReadingBlock(text + sep + b.text, [
      ...links,
      for (final (x, y, h) in b.links) (x + d, y + d, h),
    ], [
      ...drop,
      for (final (x, y) in b.drop) (x + d, y + d),
    ]);
  }

  ReadingBlock prefixed(String head) => head.isEmpty ? this : ReadingBlock(head).join(this, '');
}

final _tag = RegExp(r'<[^>]+>');
final _href = RegExp(r'''href\s*=\s*["']([^"']*)["']''');

/// HTML → [ReadingBlock]. Текстът е ТОЧНО като в четеца (`_plainOf`: без
/// таговете, празното свито до един интервал, без краищата) — инак позициите
/// не съвпадат с маркирането.
ReadingBlock readingBlockOf(String html) {
  final raw = StringBuffer();
  final links = <(int, int, String)>[];
  final drop = <(int, int)>[];
  final openA = <(int, String?)>[];
  final openSup = <int>[];
  var last = 0;
  for (final m in _tag.allMatches(html)) {
    raw.write(html.substring(last, m.start));
    last = m.end;
    final t = m[0]!.toLowerCase();
    final at = raw.length;
    if (t.startsWith('<a ') || t == '<a>') {
      openA.add((at, _href.firstMatch(m[0]!)?[1]));
    } else if (t.startsWith('</a')) {
      if (openA.isNotEmpty) {
        final (s, h) = openA.removeLast();
        if (h != null && at > s) links.add((s, at, h));
      }
    } else if (t.startsWith('<sup')) {
      openSup.add(at);
    } else if (t.startsWith('</sup')) {
      if (openSup.isNotEmpty) {
        final s = openSup.removeLast();
        if (at > s) drop.add((s, at));
      }
    }
  }
  raw.write(html.substring(last));
  final r = raw.toString();
  // Свиване на празното, с карта стара позиция → нова.
  final out = StringBuffer();
  final map = List<int>.filled(r.length + 1, 0);
  var inSpace = false;
  for (var i = 0; i < r.length; i++) {
    map[i] = out.length;
    final c = r.codeUnitAt(i);
    final ws = c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D || c == 0x0C || c == 0x0B;
    if (ws) {
      if (!inSpace) out.write(' ');
      inSpace = true;
    } else {
      out.write(r[i]);
      inSpace = false;
    }
  }
  map[r.length] = out.length;
  var s = out.toString();
  final lead = s.length - s.trimLeft().length;
  s = s.trim();
  int pos(int i) => (map[i] - lead).clamp(0, s.length);
  return ReadingBlock(s, [
    for (final (a, b, h) in links)
      if (pos(b) > pos(a)) (pos(a), pos(b), h),
  ], [
    for (final (a, b) in drop)
      if (pos(b) > pos(a)) (pos(a), pos(b)),
  ]);
}

// Съкращения, след чиято точка изречението НЕ свършва (accent.NO_SPLIT).
const _noSplit = {
  'св', 'свт', 'свв', 'прп', 'преп', 'мч', 'мчк', 'ап', 'равноап', 'гл', 'вж', 'срв',
  'стр', 'архим', 'йером', 'йеросхим', 'еп', 'митр', 'прот', 'о', 'т', 'е',
  'напр', 'др', 'сл', 'пр', 'р', 'ок', 'бел', 'вл', 'ст', 'изд', 'т.е',
  // Само тук (маркирането): „в с. Скрино", „гр. Солун".
  'с', 'гр',
};
final _sentEnd = RegExp('[.!?…]+[»“”"\')\\]]*(?=\\s+[„"«(–—-]?\\s*[А-ЯA-ZЍ])');
final _wordBefore = RegExp(r'([А-Яа-яA-Za-z.]+)$');

/// Изреченията на текста като (начало, край). Нов ред също дели.
List<(int, int)> splitSentences(String text) {
  final out = <(int, int)>[];
  var lineStart = 0;
  for (final line in text.split('\n')) {
    var last = 0;
    for (final m in _sentEnd.allMatches(line)) {
      final before = _wordBefore.firstMatch(line.substring(last, m.start));
      final bw = before?[1] ?? '';
      var word = bw.toLowerCase();
      while (word.endsWith('.')) {
        word = word.substring(0, word.length - 1);
      }
      final closers = m[0]!.replaceAll(RegExp('[»“”"\')\\]]+\$'), '');
      if (m[0]!.startsWith('.') && closers.length == 1 &&
          (_noSplit.contains(word) || (bw.length == 1 && bw != bw.toLowerCase()))) {
        continue;
      }
      var cut = m.end;
      while (cut < line.length && line[cut] == ' ') {
        cut++;
      }
      out.add((lineStart + last, lineStart + cut));
      last = cut;
    }
    if (last < line.length && line.substring(last).trim().isNotEmpty) {
      out.add((lineStart + last, lineStart + line.length));
    }
    lineStart += line.length + 1;
  }
  return out;
}

// ── плейърът ─────────────────────────────────────────────────────────────

/// Едно изречение: блокът му и мястото в него.
typedef PhoneSentence = (int block, int start, int end);

class PhoneVoicePlayback implements ReadAloud {
  final String id;
  final List<ReadingBlock> blocks;
  final List<PhoneSentence> sents;
  @override
  final AudioChapter chapter;

  @override
  final ValueNotifier<int> sentence = ValueNotifier(-1);
  @override
  final ValueNotifier<bool> playing = ValueNotifier(false);
  @override
  final ValueNotifier<double> position = ValueNotifier(0);

  @override
  VoidCallback? onFinished;
  @override
  VoidCallback? onUserAction;
  @override
  Future<Duration> Function(int to)? onCaptionSkip;

  /// Гласът се спъна — съобщение за човека.
  void Function(String message)? onError;

  bool _completed = false;
  int _gen = 0;

  // Тръгнало ли е изговарянето — закъсняло „свърших" от спряното преди
  // него не бива да прескочи напред.
  bool _started = false;

  // Изговаряното в момента: блок, откъде, докъде, текстът за гласа.
  int _uBlock = -1, _uFrom = 0, _uEnd = 0;
  SpokenText? _uSpoken;

  PhoneVoicePlayback._(this.id, this.blocks, this.sents, this.chapter);

  /// [part] — ключ на главата; [blocks] — блоковете ѝ поред.
  factory PhoneVoicePlayback(String id, String part, List<ReadingBlock> blocks) {
    final sents = <PhoneSentence>[];
    for (var b = 0; b < blocks.length; b++) {
      for (final (s, e) in splitSentences(blocks[b].text)) {
        sents.add((b, s, e));
      }
    }
    var t = 0.0;
    final list = <AudioSentence>[];
    for (final (b, s, e) in sents) {
      final d = (e - s) / PhoneVoice.charsPerSecond;
      list.add(AudioSentence(t, t + d, blocks[b].text.substring(s, e), const []));
      t += d;
    }
    return PhoneVoicePlayback._(id, blocks, sents, AudioChapter(part, '', t, list));
  }

  @override
  String get mediaId => 'phone:$id:${chapter.part}';

  @override
  bool get isPhoneVoice => true;

  @override
  bool get completed => _completed;

  @override
  Future<void> start({int fromSentence = 0}) => _speakFrom(fromSentence);

  Future<void> _speakFrom(int k) async {
    if (sents.isEmpty) return;
    k = k.clamp(0, sents.length - 1);
    final gen = ++_gen;
    _completed = false;
    if (await PhoneVoice.ready() != PhoneVoiceState.ready || gen != _gen) {
      if (gen == _gen) _onError('няма български глас');
      return;
    }
    PhoneVoice._owner = this;
    final (b, from, _) = sents[k];
    final text = blocks[b].text;
    // Дълъг абзац — до края на изречение под ~3500 знака (таванът на
    // Android е 4000).
    var end = text.length;
    if (end - from > 3500) {
      for (var j = k; j < sents.length && sents[j].$1 == b; j++) {
        if (sents[j].$3 - from > 3500 && j > k) break;
        end = sents[j].$3;
      }
    }
    final blk = blocks[b];
    final spoken = speechText(text.substring(from, end), links: [
      for (final (x, y, h) in blk.links)
        if (x >= from && y <= end) (x - from, y - from, h),
    ], drop: [
      for (final (x, y) in blk.drop)
        if (x >= from && y <= end) (x - from, y - from),
    ]);
    _uBlock = b;
    _uFrom = from;
    _uEnd = end;
    _uSpoken = spoken;
    _setSentence(k);
    playing.value = true;
    _started = false;
    await PhoneVoice._tts.stop();
    if (gen != _gen) return;
    final text0 = spoken.text.trim();
    if (text0.isEmpty) {
      _started = true;
      _onDone();
      return;
    }
    await PhoneVoice._tts.speak(spoken.text);
  }

  void _setSentence(int k) {
    sentence.value = k;
    position.value = chapter.sentences[k].start;
  }

  void _onProgress(int s, int e) {
    final sp = _uSpoken;
    if (sp == null || sp.text.isEmpty) return;
    final (a, _) = sp.sourceRange(s, e > s ? e : s + 1);
    final abs = _uFrom + a;
    var k = sentence.value < 0 ? 0 : sentence.value;
    while (k + 1 < sents.length && sents[k + 1].$1 == _uBlock && sents[k + 1].$2 <= abs) {
      k++;
    }
    if (k != sentence.value) sentence.value = k;
    final st = sents[k];
    position.value = chapter.sentences[k].start +
        ((abs - st.$2).clamp(0, st.$3 - st.$2)) / PhoneVoice.charsPerSecond;
  }

  void _onDone() {
    if (!playing.value || !_started) return;
    _started = false;
    // Следващото: остатъкът от дългия абзац или първото изречение нататък.
    var next = -1;
    for (var j = 0; j < sents.length; j++) {
      final (b, s, _) = sents[j];
      if ((b == _uBlock && s >= _uEnd) || b > _uBlock) {
        next = j;
        break;
      }
    }
    if (next < 0) {
      playing.value = false;
      _completed = true;
      _uSpoken = null;
      onFinished?.call();
      return;
    }
    unawaited(_speakFrom(next));
  }

  void _onError(String msg) {
    audioLogAdd('гласът на телефона: грешка — $msg');
    _gen++;
    playing.value = false;
    onError?.call(msg);
  }

  @override
  Future<void> seekToSentence(int i, {bool user = true}) async {
    if (sents.isEmpty) return;
    if (user) onUserAction?.call();
    i = i.clamp(0, sents.length - 1);
    if (playing.value) {
      await _speakFrom(i);
    } else {
      _completed = false;
      _setSentence(i);
    }
  }

  @override
  Future<void> toggle() async {
    onUserAction?.call();
    if (playing.value) {
      _gen++;
      playing.value = false;
      await PhoneVoice._tts.stop();
    } else {
      await _speakFrom(_completed ? 0 : (sentence.value < 0 ? 0 : sentence.value));
    }
  }

  /// Назад/напред — по изречения: назад връща в началото на текущото, а
  /// ако то едва е почнало — на предишното.
  @override
  Future<void> skip(double seconds) async {
    final k = sentence.value < 0 ? 0 : sentence.value;
    final into = position.value - chapter.sentences[k].start;
    final to = seconds < 0 ? (into > 2 ? k : k - 1) : k + 1;
    if (to >= sents.length) return;
    await seekToSentence(to);
  }

  @override
  void resync() {}

  @override
  Future<void> dispose() async {
    _gen++;
    if (PhoneVoice._owner == this) {
      PhoneVoice._owner = null;
      await PhoneVoice._tts.stop();
    }
    sentence.dispose();
    playing.dispose();
    position.dispose();
  }
}
