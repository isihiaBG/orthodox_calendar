// year_voice.dart
//
// „ГОДИНИТЕ НА ГЛАС" — инструмент на тестовия режим (08.11.2026).
//
// Как гласът на телефона казва всяка съставка на годината: бройното стои пред
// друга съставка, редното е последната дума („хиляда шейсет и пета"). Своята
// дума важи веднага на устройството (и в четенето); оттам стига до кода през
// „Копирай" (Сподели → Копирай → в чата) — както поправките на ударенията.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_theme.dart';
import 'phone_voice.dart';
import 'speech_text.dart';
import 'test_mode.dart';

class YearWords {
  YearWords._();

  static const _kWords = 'year_words';

  static Future<void>? _loading;
  static Future<void> loadOnce() => _loading ??= () async {
        try {
          final p = await SharedPreferences.getInstance();
          final s = p.getString(_kWords);
          if (s != null) {
            phoneYearWords = Map<String, String>.from(jsonDecode(s) as Map);
          }
        } catch (_) {}
      }();

  /// [word] празно — връща думата на приложението.
  static Future<void> set(String key, String word) async {
    final m = Map<String, String>.from(phoneYearWords);
    if (word.isEmpty) {
      m.remove(key);
    } else {
      m[key] = word;
    }
    phoneYearWords = m;
    await _save();
  }

  static Future<void> clear() async {
    phoneYearWords = const {};
    await _save();
  }

  static Future<void> _save() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_kWords, jsonEncode(phoneYearWords));
    } catch (_) {}
  }

  /// „60 бройно = шестдесет (беше шейсет)" — по реда на таблицата.
  static String exportText() {
    final lines = <String>['Годините на глас'];
    for (final (key, n, card, ord) in yearParts()) {
      for (final (c, label, was) in [(0, 'бройно', card), (1, 'редно', ord)]) {
        final w = phoneYearWords['${key}_$c'];
        if (w != null) lines.add('$n $label = $w (беше $was)');
      }
    }
    return lines.join('\n');
  }
}

const _groups = [
  ('th', 'Хиляди'),
  ('h', 'Стотици'),
  ('t', 'Десетици'),
  ('teen', 'От 10 до 19'),
  ('u', 'Единици'),
];

const _samples = [12, 33, 65, 100, 250, 800, 1000, 1054, 1100, 1254, 1342, 1453, 1870, 1910, 2000, 2026];

/// Редът в тестовия режим, който отваря екрана.
class YearVoiceTile extends StatelessWidget {
  const YearVoiceTile({super.key});

  @override
  Widget build(BuildContext context) => ListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        title: const Text('Годините на глас'),
        subtitle: const Text('Как гласът казва всяка съставка на годината.',
            style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
        trailing: const Icon(Icons.chevron_right, color: AppColors.textMuted),
        onTap: () => Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const YearVoiceScreen())),
      );
}

class YearVoiceScreen extends StatefulWidget {
  const YearVoiceScreen({super.key});

  @override
  State<YearVoiceScreen> createState() => _YearVoiceScreenState();
}

class _YearVoiceScreenState extends State<YearVoiceScreen> {
  final _parts = yearParts();
  final _year = TextEditingController(text: '1054');
  final _fields = <String, TextEditingController>{};
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    () async {
      await YearWords.loadOnce();
      await PhoneStress.loadOnce();
      if (!mounted) return;
      for (final (key, _, _, _) in _parts) {
        for (final c in [0, 1]) {
          _fields['${key}_$c'] = TextEditingController(text: phoneYearWords['${key}_$c'] ?? '');
        }
      }
      setState(() => _loaded = true);
    }();
  }

  @override
  void dispose() {
    _year.dispose();
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  int? get _y {
    final y = int.tryParse(_year.text.trim());
    return y != null && y >= 1 && y <= 2999 ? y : null;
  }

  /// Точно каквото получава гласът — през същия път като четенето.
  /// Речникът има предимство: изразите с цифри („12-та", „през 1494") се
  /// хващат в показания текст, преди годината да се разгъне.
  String _spoken(int y) {
    final shown = '$y г.';
    final (spans, said) = PhoneStress.shield(shown);
    final t = speechText(shown, spans: spans);
    PhoneStress.apply(t);
    PhoneStress.unshield(t, said);
    return t.text;
  }

  Future<void> _copy() async {
    await Share.share(YearWords.exportText());
  }

  @override
  Widget build(BuildContext context) {
    final y = _y;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.toolbar,
        title: const Text('Годините на глас'),
        actions: [
          IconButton(
            tooltip: 'Копирай своите думи',
            icon: const Icon(Icons.ios_share),
            onPressed: phoneYearWords.isEmpty ? null : _copy,
          ),
        ],
      ),
      body: !_loaded
          ? const SizedBox.shrink()
          : ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 32), children: [
              const Text(
                  'Бройното стои пред друга съставка, редното е последната дума: '
                  '„хиляда шейсет и пета". Своята дума важи веднага; празно поле '
                  'връща думата на приложението.',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 13, height: 1.35)),
              const SizedBox(height: 16),
              Row(children: [
                SizedBox(
                  width: 90,
                  child: TextField(
                    controller: _year,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: AppColors.textPrimary, fontSize: 22),
                    decoration: const InputDecoration(labelText: 'Година', isDense: true),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 16),
                OutlinedButton.icon(
                  onPressed: y == null ? null : () => PhoneVoice.preview(_spoken(y)),
                  icon: const Icon(Icons.volume_up_rounded, size: 20),
                  label: const Text('Чуй'),
                ),
              ]),
              const SizedBox(height: 10),
              Text(y == null ? 'Година от 1 до 2999' : 'гласът получава: ${_spoken(y)}',
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 15)),
              const SizedBox(height: 10),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final s in _samples)
                  ActionChip(
                    label: Text('$s'),
                    visualDensity: VisualDensity.compact,
                    onPressed: () {
                      _year.text = '$s';
                      setState(() {});
                      PhoneVoice.preview(_spoken(s));
                    },
                  ),
              ]),
              for (final (kind, title) in _groups) ...[
                const SizedBox(height: 24),
                Text(title.toUpperCase(),
                    style: const TextStyle(
                        color: AppColors.sectionTitle, fontSize: 12, letterSpacing: 1.4)),
                const Padding(
                  padding: EdgeInsets.only(top: 6, bottom: 2),
                  child: Row(children: [
                    SizedBox(width: 52),
                    Expanded(
                        child: Text('бройно (пред още)',
                            style: TextStyle(color: AppColors.textMuted, fontSize: 11))),
                    SizedBox(width: 12),
                    Expanded(
                        child: Text('редно (накрая)',
                            style: TextStyle(color: AppColors.textMuted, fontSize: 11))),
                  ]),
                ),
                for (final (key, n, card, ord) in _parts)
                  if (key.startsWith('${kind}_')) _row(key, n, card, ord),
              ],
            ]),
    );
  }

  Widget _row(String key, int n, String card, String ord) {
    Widget field(int c, String def) {
      final k = '${key}_$c';
      final ctl = _fields[k]!;
      final own = ctl.text.trim().isNotEmpty && ctl.text.trim() != def;
      return Expanded(
        child: TextField(
          controller: ctl,
          autocorrect: false,
          enableSuggestions: false,
          style: TextStyle(color: own ? AppColors.signRed : AppColors.textPrimary, fontSize: 16),
          decoration: InputDecoration(
            isDense: true,
            hintText: def,
            hintStyle: const TextStyle(color: AppColors.textSecondary),
          ),
          onChanged: (v) {
            final w = v.trim();
            YearWords.set(k, w == def ? '' : w);
            setState(() {});
          },
        ),
      );
    }

    return Row(children: [
      SizedBox(
        width: 52,
        child: Text('$n',
            style: const TextStyle(color: AppColors.textMuted, fontSize: 14),
            textAlign: TextAlign.right),
      ),
      const SizedBox(width: 12),
      field(0, card),
      const SizedBox(width: 12),
      field(1, ord),
    ]);
  }
}
