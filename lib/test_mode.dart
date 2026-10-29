// test_mode.dart
//
// ТЕСТОВИЯТ РЕЖИМ — инструментите на автора (28.10.2026).
//
// Включва се и се изключва със 7 докосвания на номера на версията в „За
// приложението" — без парола (решение на автора): случайно включен, режимът
// не вреди, поправките остават на същото устройство.
//
// Първият инструмент — „Грешно ударение": гласът на телефона (Google) чете
// над 90% вярно, а думите, които бърка, авторът ги отбелязва при маркиране
// (иконката „а́" в менюто). Поправката важи веднага на устройството; оттам
// стига до общия речник (assets/speech/phone_accents.txt) през „Копирай
// поправките" (Сподели → Копирай → в чата) — както дневника на звука.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_theme.dart';
import 'phone_voice.dart';
import 'reader_theme.dart';
import 'speech_text.dart';

class TestMode {
  TestMode._();

  static const _kOn = 'test_mode_on', _kTools = 'test_mode_tools';

  /// Включен ли е режимът (разделът в настройките се вижда).
  static final ValueNotifier<bool> on = ValueNotifier(false);

  /// Показват ли се инструментите — изключено, приложението изглежда като
  /// при потребителите, без да се губи режимът.
  static final ValueNotifier<bool> tools = ValueNotifier(true);

  static bool get showTools => on.value && tools.value;

  static Future<void>? _loading;
  static Future<void> loadOnce() => _loading ??= () async {
        try {
          final p = await SharedPreferences.getInstance();
          on.value = p.getBool(_kOn) ?? false;
          tools.value = p.getBool(_kTools) ?? true;
        } catch (_) {}
      }();

  static Future<void> setOn(bool v) async {
    on.value = v;
    if (v) tools.value = true;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(_kOn, v);
      await p.setBool(_kTools, tools.value);
    } catch (_) {}
  }

  static Future<void> setTools(bool v) async {
    tools.value = v;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(_kTools, v);
    } catch (_) {}
  }

  // ── 7 докосвания ──
  static int _taps = 0;
  static DateTime _lastTap = DateTime(0);

  /// Докосване по номера на версията. Седмото поред (без пауза над 1.5 s)
  /// превключва режима и казва как се връща обратно.
  static Future<void> tapVersion(BuildContext context) async {
    final now = DateTime.now();
    _taps = now.difference(_lastTap).inMilliseconds > 1500 ? 1 : _taps + 1;
    _lastTap = now;
    if (_taps < 7) return;
    _taps = 0;
    await loadOnce();
    final v = !on.value;
    await setOn(v);
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.backgroundCard,
        title: Text(v ? 'Тестовият режим е включен' : 'Тестовият режим е изключен',
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 19)),
        content: Text(
          v
              ? 'В настройките, в раздел „Звук“, има нов ред „Тестов режим“.\n\n'
                  'Изключва се оттам или със същите 7 докосвания на версията.'
              : 'Включва се отново със 7 докосвания на версията.',
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 16, height: 1.35),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Добре')),
        ],
      ),
    );
  }
}

// ── речникът на ударенията за гласа на телефона ──────────────────────────

const _vowels = 'аеиоуъюяѝ';

/// Как се показва ударението на гласа (проба с автора, 28.10.2026): всеки
/// начин сработва на различни думи, затова авторът избира на слух.
enum StressWay {
  /// Ударено о/у → латинско ó/ú. Най-естествено, но само за о и у.
  latin('латинска'),

  /// Удвоена гласна: „немотаата". Сработва навсякъде, малко провлачено.
  double('двойна'),

  /// Тире след ударената сричка: „Ком-нин", „немота-та". Естествено.
  dash('тире'),

  /// Свой изговор, изписан на ръка — когато трите не стигат (автора,
  /// 29.10.2026): тирета, интервали, латиница, каквото сработи на слух.
  custom('свой');

  final String label;
  const StressWay(this.label);

  static StressWay? byLabel(String s) {
    for (final w in values) {
      if (w.label == s || w.name == s) return w;
    }
    return null;
  }
}

/// С каква буква трябва да е думата в текста, за да важи поправката:
/// „Го́спода" (Бог) е с главна, „господа́" — с малка (автора, 29.10.2026).
enum StressCase {
  any(''),
  upper('главна'),
  lower('малка');

  final String label;
  const StressCase(this.label);

  static StressCase byLabel(String s) {
    for (final c in values) {
      if (c != any && (c.label == s || c.name == s)) return c;
    }
    return any;
  }

  bool fits(String w) => switch (this) {
        any => true,
        upper => w.isNotEmpty && w[0] != w[0].toLowerCase(),
        lower => w.isNotEmpty && w[0] == w[0].toLowerCase(),
      };
}

/// Една поправка: думата (малки букви), мястото на ударената гласна (-1 —
/// няма, при свой изговор), начинът (null — сам: латинска за о/у, иначе
/// двойна), своят изговор (при [StressWay.custom]), буквата ([StressCase]),
/// изразът (думата преди и/или след нея — тогава важи само там) и дали е
/// пратена (копирана) към автора на речника.
class StressFix {
  final String word;
  final int index;
  final StressWay? way;
  final String? custom;
  final StressCase letter;
  final String? before, after;
  final bool sent;
  const StressFix(this.word, this.index,
      {this.way, this.custom, this.letter = StressCase.any, this.before, this.after, this.sent = false});

  StressFix asSent() => StressFix(word, index,
      way: way, custom: custom, letter: letter, before: before, after: after, sent: true);

  /// Едно и също място в речника (думата, буквата и изразът).
  bool sameSlot(StressFix o) =>
      o.word == word && o.letter == letter && o.before == before && o.after == after;

  /// Колко е тясна — по-тясната печели.
  int get _narrow => (before != null ? 2 : 0) + (after != null ? 2 : 0) + (letter != StressCase.any ? 1 : 0);

  /// Важи ли за [w] между [prev] и [next] (малки букви; null — няма дума).
  bool fits(String w, String? prev, String? next) =>
      letter.fits(w) && (before == null || before == prev) && (after == null || after == next);

  /// „ко́мнин (тире)", „го́спода (тире, с главна, „пред … бога")",
  /// „ко́мнин → ко мнин (свой)" — както се чете от човек.
  String get marked {
    final w = index < 0 || index >= word.length
        ? word
        : '${word.substring(0, index + 1)}́${word.substring(index + 1)}';
    final notes = [
      if (way != null) way!.label,
      if (letter != StressCase.any) 'с ${letter.label}',
      if (before != null || after != null)
        '„${[if (before != null) before, '…', if (after != null) after].join(' ')}“',
    ];
    final head = way == StressWay.custom ? '$w → $custom' : w;
    return notes.isEmpty ? head : '$head (${notes.join(', ')})';
  }

  /// Какво получава гласът вместо [w] (думата, както е в текста).
  String spoken(String w) {
    if (way == StressWay.custom && custom != null && custom!.isNotEmpty) {
      // Главна начална буква в текста — и в изговора.
      final c = custom!;
      return w.isNotEmpty && w[0] != w[0].toLowerCase() ? c[0].toUpperCase() + c.substring(1) : c;
    }
    return PhoneStress.spokenForm(w, index, way);
  }
}

class PhoneStress {
  PhoneStress._();

  static const _asset = 'assets/speech/phone_accents.txt';
  static const _kFixes = 'phone_stress_fixes';

  static final Map<String, List<StressFix>> _bundled = {};
  static final List<StressFix> _fixes = [];

  /// Расте при всяка промяна — за реда в настройките.
  static final ValueNotifier<int> revision = ValueNotifier(0);

  static Future<void>? _loading;
  static Future<void> loadOnce() => _loading ??= () async {
        try {
          final txt = await rootBundle.loadString(_asset);
          for (final line in txt.split('\n')) {
            final f = parseLine(line);
            if (f != null) (_bundled[f.word] ??= []).add(f);
          }
        } catch (_) {}
        try {
          final p = await SharedPreferences.getInstance();
          for (final r in p.getStringList(_kFixes) ?? const <String>[]) {
            final f = r.split('\t');
            if (f.length < 2) continue;
            final i = int.tryParse(f[1]);
            if (i == null) continue;
            String? at(int k) => f.length > k && f[k].isNotEmpty ? f[k] : null;
            final way = at(3) == null ? null : StressWay.byLabel(f[3]);
            if (way == StressWay.custom && at(4) == null) continue;
            _fixes.add(StressFix(f[0], i,
                sent: at(2) == '1',
                way: way,
                custom: at(4),
                letter: StressCase.byLabel(at(5) ?? ''),
                before: at(6),
                after: at(7)));
          }
        } catch (_) {}
        _matcher = null;
        revision.value++;
      }();

  /// Ред от речника:
  ///   „кОмнин", „кОмнин тире", „комнин = ко мнин" (свой — вдясно дословно)
  /// и по желание, след „ | ": „главна" / „малка", „преди: пред",
  /// „след: бога" — напр. „госпОда тире | главна".
  static StressFix? parseLine(String line) {
    final parts = line.split('#').first.split(' | ').map((s) => s.trim()).toList();
    if (parts.first.isEmpty) return null;
    var letter = StressCase.any;
    String? before, after;
    for (final p in parts.skip(1)) {
      if (p.startsWith('преди:')) {
        before = p.substring(6).trim().toLowerCase();
      } else if (p.startsWith('след:')) {
        after = p.substring(5).trim().toLowerCase();
      } else {
        letter = StressCase.byLabel(p);
      }
    }
    final head = parts.first;
    final eq = head.indexOf(' = ');
    if (eq > 0) {
      final w = head.substring(0, eq).trim();
      final c = head.substring(eq + 3).trim();
      if (c.isEmpty) return null;
      return StressFix(w.toLowerCase(), _stressIndex(w) ?? -1,
          way: StressWay.custom, custom: c, letter: letter, before: before, after: after);
    }
    final f = head.split(RegExp(r'\s+'));
    if (f.length > 2) return null;
    final i = _stressIndex(f.first);
    final way = f.length > 1 ? StressWay.byLabel(f[1]) : null;
    if (i == null || way == StressWay.custom) return null;
    return StressFix(f.first.toLowerCase(), i,
        way: way, letter: letter, before: before, after: after);
  }

  /// „кОмнин" → 1: ГЛАВНАТА гласна (начална главна на име не се брои, ако
  /// има и друга — както в tools/tts/accent.py).
  static int? _stressIndex(String w) {
    final caps = [
      for (var i = 0; i < w.length; i++)
        if (_vowels.contains(w[i].toLowerCase()) && w[i] != w[i].toLowerCase()) i
    ];
    if (caps.length == 2 && caps[0] == 0) caps.removeAt(0);
    return caps.length == 1 ? caps[0] : null;
  }

  static List<StressFix> get fixes => List.unmodifiable(_fixes);
  static List<StressFix> get unsent => [for (final f in _fixes) if (!f.sent) f];

  /// Поправката за думата [w] (както е в текста) между [prev] и [next]:
  /// най-тясната, която важи — изразът пред буквата, буквата пред „всякак";
  /// при равни — тази на устройството пред речника в пакета.
  static StressFix? lookup(String w, {String? prev, String? next}) {
    final low = w.toLowerCase();
    StressFix? best;
    for (final f in [..._fixes.reversed, ...?_bundled[low]]) {
      if (f.word != low || !f.fits(w, prev, next)) continue;
      if (best == null || f._narrow > best._narrow) best = f;
    }
    return best;
  }

  static const _latin = {'о': 'ó', 'О': 'Ó', 'у': 'ú', 'У': 'Ú'};

  /// Може ли латинската буква — само при ударено о/у.
  static bool latinFits(String w, int i) => i >= 0 && i < w.length && _latin.containsKey(w[i]);

  /// Как да го каже гласът. Без [way]: латинска за о/у, иначе двойна.
  static String spokenForm(String w, int i, [StressWay? way]) {
    if (i < 0 || i >= w.length) return w;
    if (way == StressWay.custom) way = null; // своят е в StressFix.spoken
    way ??= latinFits(w, i) ? StressWay.latin : StressWay.double;
    final v = w[i];
    switch (way) {
      case StressWay.custom:
        return w;
      case StressWay.latin:
        final l = _latin[v];
        if (l != null) return w.substring(0, i) + l + w.substring(i + 1);
        return spokenForm(w, i, StressWay.double);
      case StressWay.double:
        return w.substring(0, i + 1) + v.toLowerCase() + w.substring(i + 1);
      case StressWay.dash:
        // Тирето — в края на ударената сричка: съгласна след гласната
        // остава при нея, ако и следващата е съгласна („Ком-нин"), иначе
        // тирето е веднага след гласната („немота-та").
        var cut = i + 1;
        bool cons(int k) => k < w.length && !_vowels.contains(w[k].toLowerCase());
        if (cons(cut) && cons(cut + 1)) cut++;
        if (cut >= w.length) return w; // ударена последната сричка — тире няма къде
        return '${w.substring(0, cut)}-${w.substring(cut)}';
    }
  }

  static final _word = RegExp(r'[А-Яа-яЍѝ]+');
  static final _lastWord = RegExp(r'([А-Яа-яЍѝ]+)[^А-Яа-яЍѝ]*$');
  static final _firstWord = RegExp(r'^[^А-Яа-яЍѝ]*([А-Яа-яЍѝ]+)');

  /// Съседните думи на [a]..[b] в [s] (малки букви), за изразите.
  static (String?, String?) neighbours(String s, int a, int b) {
    final p = _lastWord.firstMatch(s.substring(a < 40 ? 0 : a - 40, a))?[1];
    final n = _firstWord.firstMatch(s.substring(b, b + 40 > s.length ? s.length : b + 40))?[1];
    return (p?.toLowerCase(), n?.toLowerCase());
  }

  /// Прилага речника върху текста за гласа. Откъсите („по-") и думите —
  /// с ЕДНО минаване: откъсът е пръв в алтернативата и печели на същото
  /// място, а замененото не се търси пак (инак „по-" → „по -" щеше да
  /// хване и поправката на предлога „по").
  static void apply(SpokenText t) {
    if (_bundled.isEmpty && _fixes.isEmpty) return;
    t.sub(_matcher ??= _buildMatcher(), (m) {
      final w = m[0]!;
      final key = w.replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
      if (_isPhrase(key)) {
        final f = lookup(key);
        return f != null && f.letter.fits(w) ? f.spoken(w) : w;
      }
      final (prev, next) = neighbours(m.input, m.start, m.end);
      final f = lookup(w, prev: prev, next: next);
      return f == null ? w : f.spoken(w);
    });
  }

  static RegExp? _matcher;

  /// Откъсите (най-дългите първи), после думата. Буква в края на откъса —
  /// граница на дума от тази страна.
  static RegExp _buildMatcher() {
    final phrases = {
      for (final f in [..._fixes, for (final l in _bundled.values) ...l])
        if (_isPhrase(f.word)) f.word
    }.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    const l = '[А-Яа-яЍѝ]';
    final alts = [
      for (final p in phrases)
        '${RegExp('^$l').hasMatch(p) ? '(?<!$l)' : ''}'
            '${p.split(' ').map(RegExp.escape).join(r'\s+')}'
            '${RegExp('$l\$').hasMatch(p) ? '(?!$l)' : ''}',
      _word.pattern,
    ];
    return RegExp(alts.join('|'), caseSensitive: false, unicode: true);
  }

  static Future<void> add(StressFix fix) async {
    _fixes.removeWhere(fix.sameSlot);
    _fixes.add(fix);
    await _save();
  }

  /// Отбелязва поправките като пратени (след „Копирай").
  static Future<void> markSent(Iterable<StressFix> list) async {
    for (var i = 0; i < _fixes.length; i++) {
      final f = _fixes[i];
      if (list.any(f.sameSlot)) _fixes[i] = f.asSent();
    }
    await _save();
  }

  static Future<void> clearSent() async {
    _fixes.removeWhere((f) => f.sent);
    await _save();
  }

  static Future<void> _save() async {
    _matcher = null;
    revision.value++;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setStringList(_kFixes, [
        for (final f in _fixes)
          [
            f.word, f.index, f.sent ? 1 : 0, f.way?.name ?? '', f.custom ?? '',
            f.letter == StressCase.any ? '' : f.letter.name, f.before ?? '', f.after ?? '',
          ].join('\t')
      ]);
    } catch (_) {}
  }

  /// Текстът за „Копирай поправките".
  static String exportText(List<StressFix> list) {
    final d = DateTime.now();
    final date = '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
    return 'Поправки на ударенията (${list.length}, от $date)\n'
        '${list.map((f) => f.marked).join('\n')}';
  }
}

/// Може ли маркираното да се поправя: една дума — каквато и да е, и
/// едносричните („гняв"), и предлозите без гласна („с", „в"; автора,
/// 29.10.2026: „искам пълен контрол"). Поправката важи само за цялата
/// дума — „с" не пипа „село" (речникът търси цели думи).
///
/// И откъс, който не е една дума — „по-" (превъзходната степен, не
/// предлогът „по"): търси се и се заменя дословно, като „find & replace"
/// (автора, 29.10.2026). Буква в края му не бива да е част от по-дълга дума.
String? stressWordOf(String? selected) {
  final w = (selected ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
  if (w.isEmpty || w.length > 40 || !w.contains(PhoneStress._word)) return null;
  return w;
}

/// Откъс, не дума: „по-", „света Петка".
bool _isPhrase(String w) => !RegExp(r'^[А-Яа-яЍѝ]+$').hasMatch(w);

// ── панелът „Грешно ударение" ────────────────────────────────────────────

/// Думата, разделена на букви; докосване по гласна я прави ударена.
/// [prev]/[next] — съседните думи в текста (за „само в израза").
Future<void> showStressSheet(BuildContext context, String word, {String? prev, String? next}) async {
  await PhoneStress.loadOnce();
  if (!context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  final saved = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: ReaderTheme.palette.sheet,
    showDragHandle: true,
    // Своят изговор се пише — панелът се вдига над клавиатурата.
    isScrollControlled: true,
    builder: (_) => _StressSheet(word: word, prev: prev, next: next),
  );
  if (saved != null) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('Запазено: $saved')));
  }
}

class _StressSheet extends StatefulWidget {
  final String word;
  final String? prev, next;
  const _StressSheet({required this.word, this.prev, this.next});

  @override
  State<_StressSheet> createState() => _StressSheetState();
}

class _StressSheetState extends State<_StressSheet> {
  late final StressFix? _saved =
      PhoneStress.lookup(widget.word, prev: widget.prev, next: widget.next);
  late StressCase _case = _saved?.letter ?? StressCase.any;
  late bool _withPrev = _saved?.before != null;
  late bool _withNext = _saved?.after != null;
  // Едносрична дума — гласната е само една, избрана отначало.
  late int? _i = _phrase ? null : (_saved?.index ?? -1) >= 0 ? _saved!.index : _onlyVowel(widget.word);

  static int? _onlyVowel(String w) {
    final v = [for (var k = 0; k < w.length; k++) if (_vowels.contains(w[k].toLowerCase())) k];
    return v.length == 1 ? v.first : null;
  }
  // Без гласна („с", „в") ударение няма — остава само своят изговор.
  // Откъсът („по-") — също: заменя се дословно, без ударена гласна и без
  // съседни думи.
  late final bool _phrase = _isPhrase(widget.word);
  late final bool _noVowel = _phrase || !widget.word.toLowerCase().split('').any(_vowels.contains);
  late StressWay? _way = _saved?.way ?? (_noVowel ? StressWay.custom : null);
  late final _custom = TextEditingController(
      text: _saved?.way == StressWay.custom ? _saved!.spoken(widget.word) : _noVowel ? widget.word : '');

  bool get _isCustom => _way == StressWay.custom;

  /// Избраният начин, ако става за тази гласна; иначе — сам.
  StressWay? get _wayFor =>
      _way == StressWay.latin && !PhoneStress.latinFits(widget.word, _i ?? -1) ? null : _way;

  /// Своят изговор — без табулации и нови редове (те делят полетата при
  /// запис).
  String get _customText => _custom.text.replaceAll(RegExp(r'[\t\n\r#]'), ' ').trim();

  String get _spoken {
    if (_isCustom) return _customText.isEmpty ? widget.word : _customText;
    return _i == null ? widget.word : PhoneStress.spokenForm(widget.word, _i!, _wayFor);
  }

  bool get _canSave => _isCustom ? _customText.isNotEmpty : _i != null;

  void _pickWay(StressWay? v) => setState(() {
        // „Свой" започва от това, което гласът получава сега — остава само
        // да се доизправи.
        if (v == StressWay.custom && _customText.isEmpty) _custom.text = _spoken;
        _way = v;
      });

  @override
  void dispose() {
    _custom.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = ReaderTheme.palette;
    // Златото на печата „екстра" — същите мерени стойности (audio_ui.dart).
    final gold = p.dark ? const Color(0xFFCDA757) : const Color(0xFF8F6420);
    final w = widget.word;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(24, 0, 24, 20 + MediaQuery.viewInsetsOf(context).bottom),
        // С клавиатурата не се събира — долното („всякак…", съседите) се
        // превърта, горното остава.
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('УДАРЕНИЕТО ЗА ГЛАСА НА УСТРОЙСТВОТО',
                style: TextStyle(color: p.dim, fontSize: 12, letterSpacing: 1.4)),
            const SizedBox(height: 6),
            Text(_noVowel ? 'Напишете как да прозвучи' : 'Докоснете ударената гласна',
                style: TextStyle(color: p.dim, fontSize: 14)),
            const SizedBox(height: 18),
            if (_phrase)
              Text(w, style: TextStyle(fontSize: 34, height: 1.3, color: p.ink))
            else
              Wrap(alignment: WrapAlignment.center, children: [
                for (var k = 0; k < w.length; k++)
                  _letter(w[k], k, gold, p.ink),
              ]),
            const SizedBox(height: 18),
            // Начинът — кой сработва, се чува: „Чуй" след всяка смяна.
            SegmentedButton<StressWay>(
              showSelectedIcon: false,
              emptySelectionAllowed: true,
              style: SegmentedButton.styleFrom(
                selectedBackgroundColor: gold.withValues(alpha: p.dark ? 0.28 : 0.22),
                selectedForegroundColor: p.ink,
                foregroundColor: p.dim,
                side: BorderSide(color: p.dim.withValues(alpha: 0.4)),
                visualDensity: VisualDensity.compact,
                // „латинска" се пренасяше на два реда.
                padding: const EdgeInsets.symmetric(horizontal: 4),
              ),
              segments: [
                ButtonSegment(
                    value: StressWay.latin,
                    enabled: _i != null && PhoneStress.latinFits(w, _i!),
                    label: const Text('латинска')),
                ButtonSegment(value: StressWay.double, enabled: !_noVowel, label: const Text('двойна')),
                ButtonSegment(value: StressWay.dash, enabled: !_noVowel, label: const Text('тире')),
                const ButtonSegment(value: StressWay.custom, label: Text('свой')),
              ],
              selected: {
                if (_isCustom)
                  StressWay.custom
                else if (_i != null)
                  _wayFor ??
                      (PhoneStress.latinFits(w, _i!) ? StressWay.latin : StressWay.double)
              },
              onSelectionChanged: (v) => _pickWay(v.isEmpty ? null : v.first),
            ),
            const SizedBox(height: 10),
            if (_isCustom) ...[
              // Свой изговор: пише се, както трябва да прозвучи.
              TextField(
                controller: _custom,
                autofocus: _customText.isEmpty,
                textAlign: TextAlign.center,
                style: TextStyle(color: p.ink, fontSize: 24),
                cursorColor: gold,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: w.toLowerCase(),
                  hintStyle: TextStyle(color: p.dim.withValues(alpha: 0.6)),
                  enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: p.dim.withValues(alpha: 0.4))),
                  focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: gold, width: 1.5)),
                ),
              ),
              const SizedBox(height: 8),
              Text('както да прозвучи: тире, интервал, удвоена буква, латиница…',
                  textAlign: TextAlign.center, style: TextStyle(color: p.dim, fontSize: 13)),
            ] else
              // Какво точно получава гласът.
              Text(_i == null ? ' ' : 'гласът получава: $_spoken',
                  style: TextStyle(color: p.dim, fontSize: 14)),
            // „Чуй" и „Запази" — веднага под написаното: при „свой" клавиатурата
            // закрива долната част, а тук се пробва често (автора, 29.10.2026).
            const SizedBox(height: 16),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              OutlinedButton.icon(
                onPressed: () => PhoneVoice.preview(_spoken),
                icon: const Icon(Icons.volume_up_rounded, size: 20),
                label: const Text('Чуй'),
              ),
              const SizedBox(width: 14),
              FilledButton(
                onPressed: !_canSave
                    ? null
                    : () async {
                        final nav = Navigator.of(context);
                        final fix = StressFix(w.toLowerCase(), _i ?? -1,
                            way: _wayFor,
                            custom: _isCustom ? _customText : null,
                            letter: _case,
                            before: _withPrev ? widget.prev : null,
                            after: _withNext ? widget.next : null);
                        await PhoneStress.add(fix);
                        nav.pop(fix.marked);
                      },
                child: const Text('Запази'),
              ),
            ]),
            const SizedBox(height: 20),
            // Кога важи: с каква буква и дали само до съседна дума.
            SegmentedButton<StressCase>(
              showSelectedIcon: false,
              style: SegmentedButton.styleFrom(
                selectedBackgroundColor: gold.withValues(alpha: p.dark ? 0.28 : 0.22),
                selectedForegroundColor: p.ink,
                foregroundColor: p.dim,
                side: BorderSide(color: p.dim.withValues(alpha: 0.4)),
                visualDensity: VisualDensity.compact,
              ),
              segments: const [
                ButtonSegment(value: StressCase.any, label: Text('всякак')),
                ButtonSegment(value: StressCase.upper, label: Text('с главна')),
                ButtonSegment(value: StressCase.lower, label: Text('с малка')),
              ],
              selected: {_case},
              onSelectionChanged: (v) => setState(() => _case = v.first),
            ),
            if (!_phrase && (widget.prev != null || widget.next != null)) ...[
              const SizedBox(height: 12),
              Text('само в израза — докоснете съседна дума',
                  style: TextStyle(color: p.dim, fontSize: 13)),
              const SizedBox(height: 6),
              Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                children: [
                  if (widget.prev != null)
                    _neighbour(widget.prev!, _withPrev, () => setState(() => _withPrev = !_withPrev), gold, p),
                  Text(w, style: TextStyle(color: p.ink, fontSize: 16, fontWeight: FontWeight.w600)),
                  if (widget.next != null)
                    _neighbour(widget.next!, _withNext, () => setState(() => _withNext = !_withNext), gold, p),
                ],
              ),
            ],
          ]),
        ),
      ),
    );
  }

  /// Съседна дума за израза — включена е в златно.
  Widget _neighbour(String word, bool on, VoidCallback tap, Color gold, ReaderPalette p) => InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: tap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: on ? gold.withValues(alpha: p.dark ? 0.28 : 0.22) : null,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: on ? gold : p.dim.withValues(alpha: 0.4)),
          ),
          child: Text(word, style: TextStyle(color: on ? p.ink : p.dim, fontSize: 16)),
        ),
      );

  Widget _letter(String c, int k, Color gold, Color ink) {
    final vowel = _vowels.contains(c.toLowerCase());
    final on = _i == k;
    final style = TextStyle(
      fontSize: 34,
      height: 1.3,
      color: on ? gold : ink,
      fontWeight: on ? FontWeight.w600 : FontWeight.w400,
    );
    final t = Text(on ? '$c\u0301' : c, style: style);
    if (!vowel) return Padding(padding: const EdgeInsets.symmetric(horizontal: 1), child: t);
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      // При „свой" гласната само се отбелязва (за прегледа), изговорът е
      // написаният.
      onTap: () => setState(() => _i = k),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        decoration: BoxDecoration(
          // Гласните се познават по тънка черта отдолу — без нея не личи
          // кое се докосва.
          border: Border(bottom: BorderSide(color: on ? gold : ink.withValues(alpha: 0.35), width: 1.5)),
        ),
        child: t,
      ),
    );
  }
}

// ── редът в настройките ─────────────────────────────────────────────────

/// „Тестов режим" в Настройки → „Звук" — само докато режимът е включен.
class TestModeSettings extends StatelessWidget {
  const TestModeSettings({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: TestMode.on,
      builder: (context, on, _) {
        if (!on) return const SizedBox.shrink();
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Divider(height: 28, color: AppColors.sectionDivider, thickness: 1),
          const Padding(
            padding: EdgeInsets.only(bottom: 4),
            child: Text('ТЕСТОВ РЕЖИМ',
                style: TextStyle(color: AppColors.textMuted, fontSize: 11, letterSpacing: 1.5)),
          ),
          ValueListenableBuilder<bool>(
            valueListenable: TestMode.tools,
            builder: (_, v, _) => SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: v,
              onChanged: TestMode.setTools,
              title: const Text('Показвай тестовите инструменти'),
              subtitle: const Text(
                  'Изключено — приложението изглежда като при потребителите.',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
            ),
          ),
          FutureBuilder(
            future: PhoneStress.loadOnce(),
            builder: (_, _) => ValueListenableBuilder<int>(
              valueListenable: PhoneStress.revision,
              builder: (context, _, _) {
                final fresh = PhoneStress.unsent;
                final all = PhoneStress.fixes;
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text('Поправки на ударенията'),
                  subtitle: Text(
                      all.isEmpty
                          ? 'Още няма. Маркирайте дума в четивото → „а́".'
                          : '${fresh.length} нови · ${all.length} общо',
                      style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    TextButton(
                      onPressed: fresh.isEmpty ? null : () => _copy(fresh),
                      child: const Text('Копирай'),
                    ),
                    PopupMenuButton<String>(
                      tooltip: 'Още',
                      icon: const Icon(Icons.more_vert, color: AppColors.textMuted),
                      color: AppColors.backgroundCard,
                      onSelected: (v) {
                        if (v == 'all') _copy(all);
                        if (v == 'clear') PhoneStress.clearSent();
                      },
                      itemBuilder: (_) => [
                        PopupMenuItem(
                            value: 'all', enabled: all.isNotEmpty, child: const Text('Копирай всички')),
                        PopupMenuItem(
                            value: 'clear',
                            enabled: all.length > fresh.length,
                            child: const Text('Изчисти изпратените')),
                      ],
                    ),
                  ]),
                );
              },
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => TestMode.setOn(false),
              child: const Text('Изключи тестовия режим'),
            ),
          ),
        ]);
      },
    );
  }

  /// През „Сподели" (там е и „Копирай") — както дневника на звука.
  /// Отбелязват се като пратени; нищо не се трие.
  Future<void> _copy(List<StressFix> list) async {
    await Share.share(PhoneStress.exportText(list));
    await PhoneStress.markSent(list);
  }
}
