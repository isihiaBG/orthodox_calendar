// molitvoslov_welcome_screen.dart
//
// Въвеждащият екран на „Молитвослов" — четири корици, по една за таб.
// Устроен по ПЪЛНА аналогия с bible_welcome_screen.dart и стъпва на същия
// [CoverPickerScaffold] — трите места правят едно и също нещо и трябва да се
// държат еднакво под пръста.
//
// ⚠ Кориците са ВРЕМЕННИ — засега една и съща (Новият завет), докато
// потребителят нарисува свои (изрично: „кориците ще ги направя по-късно").
// Сменят се само в `_parts`.

import 'package:flutter/material.dart';

import 'app_drawer.dart';
import 'app_theme.dart';
import 'book_open_transition.dart';
import 'cover_flow.dart';
import 'cover_picker.dart';
import 'molitvoslov_contents.dart';
import 'molitvoslov_settings.dart';

class _Part {
  final String cover;
  final String name;
  final String detail;
  const _Part(this.cover, this.name, this.detail);
}

const String _kTempCover = 'assets/bible_covers/02_NewTestament.jpg';

/// ⚠ Редът тук Е редът на табовете (индекс = таб) — за разлика от „Библия",
/// тук няма канон, който да спори с подредбата.
const List<_Part> _parts = [
  _Part(_kTempCover, 'Молитви', 'утринни, вечерни, за причастие'),
  _Part(_kTempCover, 'Канонник', 'канони и седмични служби'),
  _Part(_kTempCover, 'Акатисти', 'към Господ, Богородица, св. Николай и др.'),
  _Part(_kTempCover, 'Псалтир', 'бг по Септуагинта и цс, с молитвите след катизмите'),
  _Part(_kTempCover, 'Богослужебни', 'предстои'),
];

class MolitvoslovWelcomeScreen extends StatefulWidget {
  const MolitvoslovWelcomeScreen({super.key});

  @override
  State<MolitvoslovWelcomeScreen> createState() =>
      _MolitvoslovWelcomeScreenState();
}

class _MolitvoslovWelcomeScreenState extends State<MolitvoslovWelcomeScreen>
    with TickerProviderStateMixin {
  final GlobalKey<CoverFlowState> _flow = GlobalKey<CoverFlowState>();
  late int _index = MolitvoslovLastTab.value.clamp(0, _parts.length - 1);
  bool _opening = false;

  late final AnimationController _launch =
      AnimationController(vsync: this, duration: kCoverLaunchDuration);
  late final AnimationController _reveal =
      AnimationController(vsync: this, duration: kPageArriveDuration);

  @override
  void dispose() {
    _launch.dispose();
    _reveal.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    precacheImage(const AssetImage(_kTempCover), context);
  }

  /// ⚠ ПРЕПИСАНО от `_choose` в bible_welcome_screen.dart — всеки ред там има
  /// платена причина (push, а не pushReplacement; изчакване ПО ВРЕМЕ, а не
  /// `await _reveal.forward()`; слоят се маха и в `finally`). Не „опростявай".
  Future<void> _choose(int i) async {
    if (_opening) return;
    setState(() => _opening = true);
    MolitvoslovLastTab.set(i);

    final rect = _flow.currentState?.centerCoverRect();
    OverlayEntry? flying;
    try {
      if (rect != null) {
        _reveal.value = 0;
        flying = OverlayEntry(
          builder: (_) => CoverLaunch(
            from: rect,
            cover: AssetImage(_parts[i].cover),
            animation: _launch,
            reveal: _reveal,
          ),
        );
        Overlay.of(context, rootOverlay: true).insert(flying);
        await _launch.forward(from: 0);
      }
      if (!mounted) return;
      final opened = Navigator.of(context)
          .push(bookOpenRoute(MolitvoslovContents(initialTab: i)));
      await Future<void>.delayed(const Duration(milliseconds: 32));
      _reveal.forward(from: 0);
      await Future<void>.delayed(
          kPageArriveDuration + const Duration(milliseconds: 60));
      flying?.remove();
      flying = null;
      await opened;
    } finally {
      flying?.remove();
      _launch.value = 0;
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return CoverPickerScaffold(
      title: 'Молитвослов',
      covers: [for (final p in _parts) AssetImage(p.cover)],
      index: _index,
      onIndexChanged: (i) => setState(() => _index = i),
      onOpen: _choose,
      flowKey: _flow,
      drawer: const AppDrawer(),
      aspect: 523 / 741,
      infoBuilder: (_, i) => _info(i),
      landscapeLabel: (i) => _parts[i].name,
    );
  }

  Widget _info(int i) {
    final p = _parts[i];
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Православен молитвослов',
              style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                  letterSpacing: 1.2)),
          const SizedBox(height: 6),
          Text(p.name,
              style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 30,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(p.detail,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 14)),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: _opening ? null : () => _choose(i),
            icon: const Icon(Icons.menu_book, size: 18),
            label: const Text('Отвори'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.sectionTitle,
              foregroundColor: Colors.white,
              padding:
                  const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }
}
