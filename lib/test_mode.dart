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

/// Една поправка: думата (малки букви), мястото на ударената гласна и дали е
/// пратена (копирана) към автора на речника.
class StressFix {
  final String word;
  final int index;
  final bool sent;
  const StressFix(this.word, this.index, {this.sent = false});

  /// „Ко́мнин" — с ударението, както се чете от човек.
  String get marked => '${word.substring(0, index + 1)}́${word.substring(index + 1)}';
}

class PhoneStress {
  PhoneStress._();

  static const _asset = 'assets/speech/phone_accents.txt';
  static const _kFixes = 'phone_stress_fixes';

  static final Map<String, int> _bundled = {};
  static final List<StressFix> _fixes = [];

  /// Расте при всяка промяна — за реда в настройките.
  static final ValueNotifier<int> revision = ValueNotifier(0);

  static Future<void>? _loading;
  static Future<void> loadOnce() => _loading ??= () async {
        try {
          final txt = await rootBundle.loadString(_asset);
          for (var line in txt.split('\n')) {
            line = line.split('#').first.trim();
            if (line.isEmpty || line.contains(' ')) continue;
            final i = _stressIndex(line);
            if (i != null) _bundled[line.toLowerCase()] = i;
          }
        } catch (_) {}
        try {
          final p = await SharedPreferences.getInstance();
          for (final r in p.getStringList(_kFixes) ?? const <String>[]) {
            final f = r.split('\t');
            if (f.length < 2) continue;
            final i = int.tryParse(f[1]);
            if (i == null) continue;
            _fixes.add(StressFix(f[0], i, sent: f.length > 2 && f[2] == '1'));
          }
        } catch (_) {}
        revision.value++;
      }();

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

  /// Мястото на ударението за думата: поправката на устройството, иначе
  /// речникът в пакета.
  static int? indexOf(String lower) {
    for (final f in _fixes.reversed) {
      if (f.word == lower) return f.index;
    }
    return _bundled[lower];
  }

  /// Как да го каже гласът: ударено о/у → латинско ó/ú (същата дължина);
  /// другите — удвоена гласна (проба с автора, 28.10.2026).
  static String spokenForm(String w, int i) {
    if (i < 0 || i >= w.length) return w;
    const lat = {'о': 'ó', 'О': 'Ó', 'у': 'ú', 'У': 'Ú'};
    final v = w[i];
    final l = lat[v];
    if (l != null) return w.substring(0, i) + l + w.substring(i + 1);
    return w.substring(0, i + 1) + v.toLowerCase() + w.substring(i + 1);
  }

  static final _word = RegExp(r'[А-Яа-яЍѝ]+');

  /// Прилага речника върху текста за гласа.
  static void apply(SpokenText t) {
    if (_bundled.isEmpty && _fixes.isEmpty) return;
    t.sub(_word, (m) {
      final w = m[0]!;
      final i = indexOf(w.toLowerCase());
      return i == null ? w : spokenForm(w, i);
    });
  }

  static Future<void> add(String word, int index) async {
    final low = word.toLowerCase();
    _fixes.removeWhere((f) => f.word == low);
    _fixes.add(StressFix(low, index));
    await _save();
  }

  /// Отбелязва поправките като пратени (след „Копирай").
  static Future<void> markSent(Iterable<StressFix> list) async {
    final words = {for (final f in list) f.word};
    for (var i = 0; i < _fixes.length; i++) {
      final f = _fixes[i];
      if (words.contains(f.word)) _fixes[i] = StressFix(f.word, f.index, sent: true);
    }
    await _save();
  }

  static Future<void> clearSent() async {
    _fixes.removeWhere((f) => f.sent);
    await _save();
  }

  static Future<void> _save() async {
    revision.value++;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setStringList(_kFixes,
          [for (final f in _fixes) '${f.word}\t${f.index}\t${f.sent ? 1 : 0}']);
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

/// Може ли маркираното да се поправя: една дума, поне две гласни.
String? stressWordOf(String? selected) {
  final w = selected?.trim() ?? '';
  if (!RegExp(r'^[А-Яа-яЍѝ]+$').hasMatch(w)) return null;
  final n = w.toLowerCase().split('').where(_vowels.contains).length;
  return n >= 2 ? w : null;
}

// ── панелът „Грешно ударение" ────────────────────────────────────────────

/// Думата, разделена на букви; докосване по гласна я прави ударена.
Future<void> showStressSheet(BuildContext context, String word) async {
  await PhoneStress.loadOnce();
  if (!context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  final saved = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: ReaderTheme.palette.sheet,
    showDragHandle: true,
    builder: (_) => _StressSheet(word: word),
  );
  if (saved != null) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('Запазено: $saved')));
  }
}

class _StressSheet extends StatefulWidget {
  final String word;
  const _StressSheet({required this.word});

  @override
  State<_StressSheet> createState() => _StressSheetState();
}

class _StressSheetState extends State<_StressSheet> {
  late int? _i = PhoneStress.indexOf(widget.word.toLowerCase());

  @override
  Widget build(BuildContext context) {
    final p = ReaderTheme.palette;
    // Златото на печата „екстра" — същите мерени стойности (audio_ui.dart).
    final gold = p.dark ? const Color(0xFFCDA757) : const Color(0xFF8F6420);
    final w = widget.word;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('УДАРЕНИЕТО ЗА ГЛАСА НА ТЕЛЕФОНА',
              style: TextStyle(color: p.dim, fontSize: 12, letterSpacing: 1.4)),
          const SizedBox(height: 6),
          Text('Докоснете ударената гласна',
              style: TextStyle(color: p.dim, fontSize: 14)),
          const SizedBox(height: 18),
          Wrap(alignment: WrapAlignment.center, children: [
            for (var k = 0; k < w.length; k++)
              _letter(w[k], k, gold, p.ink),
          ]),
          const SizedBox(height: 22),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            OutlinedButton.icon(
              onPressed: () =>
                  PhoneVoice.preview(_i == null ? w : PhoneStress.spokenForm(w, _i!)),
              icon: const Icon(Icons.volume_up_rounded, size: 20),
              label: const Text('Чуй'),
            ),
            const SizedBox(width: 14),
            FilledButton(
              onPressed: _i == null
                  ? null
                  : () async {
                      final nav = Navigator.of(context);
                      await PhoneStress.add(w, _i!);
                      nav.pop(StressFix(w, _i!).marked);
                    },
              child: const Text('Запази'),
            ),
          ]),
        ]),
      ),
    );
  }

  Widget _letter(String c, int k, Color gold, Color ink) {
    final vowel = _vowels.contains(c.toLowerCase());
    final on = _i == k;
    final style = TextStyle(
      fontSize: 34,
      height: 1.3,
      color: on ? gold : ink,
      fontWeight: on ? FontWeight.w600 : FontWeight.w400,
    );
    final t = Text(on ? '$ć' : c, style: style);
    if (!vowel) return Padding(padding: const EdgeInsets.symmetric(horizontal: 1), child: t);
    return InkWell(
      borderRadius: BorderRadius.circular(6),
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
