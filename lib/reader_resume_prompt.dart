// reader_resume_prompt.dart
//
// „Продължи оттам, докъдето стигна" — прозорчето с обратно броене, което
// изскача при отваряне на четиво със запазена позиция. ОБЩО за двата
// четеца.
//
// Само предлага; не действа само. Ако човекът не го докосне, изчезва след
// няколко секунди и оставя четивото от началото — затова е ненатрапчиво.
// Докосването го задържа (пауза), за да не изчезне точно докато го чете.
//
// Не знае нищо за отметки, слъгове и глави: получава цветове и три
// отпратки — „скочи", „изтрий позицията", „затвори".

import 'dart:async';

import 'package:flutter/material.dart';

/// Долна подкана "продължи от последната позиция" — показва се при отваряне
/// на четиво със запазена отметка. Две състояния:
///  - "пълно": обяснение + брояч 5→0 + бутон "иди" + бутон "пауза" (ако
///    броячът стигне 0 без реакция, автоматично скача на позицията);
///  - "slim" (на пауза): един ред, полупрозрачен, безсрочен, само бутоните.
/// Swipe на "пълно" пита за потвърждение преди да изтрие отметката; swipe
/// на "slim" просто се "събужда" обратно към пълно с пресен брояч.
class ResumePrompt extends StatefulWidget {
  final Color background;
  final Color ink;
  final Color dim;
  final VoidCallback onJump;
  final VoidCallback onDeleted;
  final VoidCallback onClosed;

  const ResumePrompt({
    required this.background,
    required this.ink,
    required this.dim,
    required this.onJump,
    required this.onDeleted,
    required this.onClosed,
  });

  @override
  State<ResumePrompt> createState() => ResumePromptState();
}

class ResumePromptState extends State<ResumePrompt> {
  static const int _countdownStart = 10;
  int _secondsLeft = _countdownStart;
  bool _paused = false;
  Timer? _timer;
  bool _closing = false; // пази от двойно извикване на onJump/onClosed

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), _tick);
  }

  void _tick(Timer t) {
    if (!mounted) {
      t.cancel();
      return;
    }
    if (_secondsLeft <= 0) {
      t.cancel();
      _jump();
      return;
    }
    setState(() => _secondsLeft--);
  }

  void _startCountdown() {
    _timer?.cancel();
    setState(() => _secondsLeft = _countdownStart);
    _timer = Timer.periodic(const Duration(seconds: 1), _tick);
  }

  void _togglePause() {
    setState(() => _paused = !_paused);
    if (_paused) {
      _timer?.cancel();
    } else {
      _startCountdown();
    }
  }

  void _jump() {
    if (_closing) return;
    _closing = true;
    _timer?.cancel();
    widget.onJump();
    widget.onClosed();
  }

  Future<bool> _confirmDelete() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'Заличаване на отметката',
          style: TextStyle(fontSize: 20),
        ),
        content: const Text(
            'Наистина ли искате да ЗАЛИЧИТЕ запазената отметка за това четиво?',
          style: TextStyle(fontSize: 16),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Не', style: TextStyle(fontSize: 20)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Да', style: TextStyle(fontSize: 20)),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Widget _circleButton({
    required IconData icon,
    required VoidCallback onTap,
    bool active = false,
  }) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 34,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: active ? widget.ink : Colors.transparent,
          border: Border.all(color: widget.ink, width: 1.3),
        ),
        child: Icon(
          icon,
          size: 18,
          color: active ? widget.background : widget.ink,
        ),
      ),
    );
  }

  Widget _buildFull() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Имате запазена позиция в това четиво.',
                style: TextStyle(color: widget.ink, fontSize: 18),
              ),
            ),
            const SizedBox(width: 8),
            _circleButton(icon: Icons.arrow_forward, onTap: _jump),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: Text(
                'Отваря се след $_secondsLeft…',
                style: TextStyle(color: widget.dim, fontSize: 13),
              ),
            ),
            Text('Изчакай', style: TextStyle(color: widget.dim, fontSize: 13)),
            const SizedBox(width: 6),
            _circleButton(icon: Icons.pause, onTap: _togglePause),
          ],
        ),
      ],
    );
  }

  Widget _buildSlim() {
    return Row(
      children: [
        _circleButton(icon: Icons.pause, onTap: _togglePause, active: true),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            'Отиди на отметката',
              textAlign: TextAlign.right,
            style: TextStyle(color: widget.ink, fontSize: 14),
          ),
        ),
        const SizedBox(width: 10),
        _circleButton(icon: Icons.arrow_forward, onTap: _jump),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final card = Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: widget.background,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(color: Colors.black45, blurRadius: 8, offset: Offset(0, 2)),
        ],
      ),
      child: _paused ? _buildSlim() : _buildFull(),
    );

    return Dismissible(
      key: ValueKey(_paused ? 'resume-slim' : 'resume-full'),
      direction: DismissDirection.horizontal,
      confirmDismiss: (_) async {
        if (_paused) {
          // Swipe на slim = "събуди се" — обратно към пълно с пресен брояч.
          _togglePause();
          return false;
        }
        // Спираме брояча веднага — иначе докато диалогът за потвърждение
        // виси, той продължава да тече във фонов режим и може да "скочи"
        // към отметката точно докато потребителят чете диалога.
        _timer?.cancel();
        final confirmed = await _confirmDelete();
        if (confirmed) {
          widget.onDeleted();
          widget.onClosed();
          return true;
        }
        _startCountdown(); // "Не" -> нулира брояча отначало
        return false;
      },
      child: card,
    );
  }
}
