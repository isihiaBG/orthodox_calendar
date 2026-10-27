// update_download_overlay.dart
//
// Свалянето на новата версия — прозорец, който се свива в плаващо кръгче
// (замисъл на автора, 27.10.2026). Свалянето не заключва приложението:
// „Във фонов режим" свива прозореца в кръгче под ☰, със синя дъга по
// часовниковата стрелка за напредъка. Кръгчето стои НАД ВСИЧКИ екрани
// (MaterialApp.builder) и с натискане се разгъва обратно в прозореца.
// Свърши ли свалянето, дъгата се затваря, стрелката става отметка, кръгчето
// пулсира веднъж и се разгъва в „Свалянето приключи успешно" + „Инсталирай".
//
// ⚠ Прозорецът и кръгчето са ЕДНА кутия, а не диалог и отделен бутон: при
// свиване съдържанието избледнява, а самата кутия се смалява и лети към
// мястото на кръгчето — окото вижда къде е отишъл прозорецът. Затова тя е
// тук, над навигатора, а не в showDialog.
//
// Състоянието е само в AppUpdate.download / AppUpdate.view; тук нищо не се
// пази освен анимациите.

import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'app_update.dart';

/// Синьото на напредъка — избрано от автора (27.10.2026): като синьото на
/// въртящото се кръгче в приложението на Claude (взето от снимка на екрана).
/// sectionTitle (сиво-син) върху сивата следа почти не се различава.
const Color kDownloadBlue = Color(0xFF4276CE);

class UpdateDownloadOverlay extends StatefulWidget {
  const UpdateDownloadOverlay({super.key});

  @override
  State<UpdateDownloadOverlay> createState() => _UpdateDownloadOverlayState();
}

class _UpdateDownloadOverlayState extends State<UpdateDownloadOverlay>
    with TickerProviderStateMixin {
  /// 0 — кръгче, 1 — прозорец.
  late final AnimationController _morph = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 460));

  /// Появяване/скриване на цялото (0 — няма нищо).
  late final AnimationController _appear = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 220));

  /// Еднократният пулс при завършване.
  late final AnimationController _pulse = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 520));

  /// Въртенето, докато още няма първите байтове.
  late final AnimationController _spin = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1100));

  final _contentKey = GlobalKey();
  double _cardH = 196;
  DownloadPhase _lastPhase = DownloadPhase.idle;

  @override
  void initState() {
    super.initState();
    AppUpdate.view.addListener(_onView);
    AppUpdate.download.addListener(_onDownload);
    _onView();
  }

  @override
  void dispose() {
    AppUpdate.view.removeListener(_onView);
    AppUpdate.download.removeListener(_onDownload);
    _morph.dispose();
    _appear.dispose();
    _pulse.dispose();
    _spin.dispose();
    super.dispose();
  }

  void _onView() {
    switch (AppUpdate.view.value) {
      case DownloadView.hidden:
        _appear.reverse();
      case DownloadView.expanded:
        if (_appear.value == 0) _morph.value = 1; // от нищото — направо прозорец
        _appear.forward();
        _morph.animateTo(1, curve: Curves.easeInOutCubic);
      case DownloadView.collapsed:
        _appear.forward();
        _morph.animateBack(0, curve: Curves.easeInOutCubic);
    }
    setState(() {});
  }

  void _onDownload() {
    final s = AppUpdate.download.value;
    final spin = s.phase == DownloadPhase.running && s.fraction == 0;
    if (spin && !_spin.isAnimating) {
      _spin.repeat();
    } else if (!spin && _spin.isAnimating) {
      _spin.stop();
    }
    if (s.phase == DownloadPhase.done &&
        _lastPhase != DownloadPhase.done &&
        AppUpdate.view.value == DownloadView.collapsed) {
      // Дъгата се затваря, кръгчето пулсира — и чак тогава се разгъва.
      _pulse.forward(from: 0).whenComplete(() {
        if (mounted && AppUpdate.view.value == DownloadView.collapsed) {
          AppUpdate.view.value = DownloadView.expanded;
        }
      });
    }
    _lastPhase = s.phase;
    setState(() {});
  }

  void _measure() {
    final h = _contentKey.currentContext?.size?.height;
    if (h != null && (h - _cardH).abs() > 0.5) setState(() => _cardH = h);
  }

  @override
  Widget build(BuildContext context) {
    if (!AppUpdate.supported) return const SizedBox.shrink();
    return AnimatedBuilder(
      animation: Listenable.merge([_morph, _appear, _pulse, _spin]),
      builder: (context, _) {
        if (_appear.value == 0) return const SizedBox.shrink();
        WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
        final mq = MediaQuery.of(context);
        final size = mq.size;
        final t = _morph.value;
        final expanded = AppUpdate.view.value == DownloadView.expanded;

        // Кръгчето — точно под ☰ (иконата е центрирана на 28 px от ръба,
        // лентата е AppSizes.toolbarHeight висока).
        const d = 44.0;
        final small = Rect.fromLTWH(mq.padding.left + 28 - d / 2,
            mq.padding.top + AppSizes.toolbarHeight + 10, d, d);
        final w = math.min(size.width - 48, 360.0);
        final big = Rect.fromCenter(
            center: size.center(Offset.zero), width: w, height: _cardH);
        final r = Rect.lerp(small, big, t)!;
        final radius = lerpDouble(d / 2, 20, t)!;

        // Съдържанието избледнява ПРЕДИ кутията да се смали, кръгът изплува
        // чак когато вече е малка.
        final contentOp = Curves.easeOut.transform(((t - 0.45) / 0.55).clamp(0, 1));
        final ringOp = Curves.easeIn.transform(((0.35 - t) / 0.35).clamp(0, 1));
        final pulse = math.sin(_pulse.value * math.pi);
        final scale = lerpDouble(0.92, 1, Curves.easeOut.transform(_appear.value))! *
            (1 + 0.14 * pulse * (1 - t));

        return Opacity(
          opacity: _appear.value,
          child: Stack(children: [
            // Затъмнението — само при разгънат прозорец; докосване извън
            // него при сваляне го свива, иначе го затваря.
            Positioned.fill(
              child: IgnorePointer(
                ignoring: !expanded,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _outside,
                  child: ColoredBox(color: Colors.black.withValues(alpha: 0.5 * t)),
                ),
              ),
            ),
            Positioned.fromRect(
              rect: r,
              child: Transform.scale(
                scale: scale,
                child: GestureDetector(
                  onTap: expanded ? null : () => AppUpdate.view.value = DownloadView.expanded,
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.backgroundCard,
                      borderRadius: BorderRadius.circular(radius),
                      border: Border.all(color: AppColors.sectionDivider),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.55),
                          blurRadius: lerpDouble(10, 28, t)!,
                          offset: Offset(0, lerpDouble(3, 10, t)!),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(radius),
                      child: Stack(children: [
                        if (contentOp > 0)
                          Opacity(
                            opacity: contentOp,
                            child: OverflowBox(
                              alignment: Alignment.topCenter,
                              minWidth: w,
                              maxWidth: w,
                              minHeight: 0,
                              maxHeight: double.infinity,
                              child: KeyedSubtree(
                                key: _contentKey,
                                child: Material(
                                  type: MaterialType.transparency,
                                  child: _Panel(state: AppUpdate.download.value),
                                ),
                              ),
                            ),
                          ),
                        if (ringOp > 0)
                          Center(
                            child: Opacity(
                              opacity: ringOp,
                              child: SizedBox.square(
                                dimension: d,
                                child: _Bubble(
                                  state: AppUpdate.download.value,
                                  spin: _spin.value,
                                ),
                              ),
                            ),
                          ),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
          ]),
        );
      },
    );
  }

  void _outside() {
    if (AppUpdate.download.value.phase == DownloadPhase.running) {
      AppUpdate.collapse();
    } else {
      AppUpdate.close();
    }
  }
}

/// Кръгчето: сива следа, синя дъга от 12 часа по часовниковата стрелка,
/// в средата — стрелка надолу, отметка или удивителна.
class _Bubble extends StatelessWidget {
  final DownloadState state;
  final double spin;
  const _Bubble({required this.state, required this.spin});

  @override
  Widget build(BuildContext context) {
    final failed = state.phase == DownloadPhase.failed;
    final done = state.phase == DownloadPhase.done;
    final icon = done
        ? Icons.check_rounded
        : failed
            ? Icons.priority_high_rounded
            : Icons.arrow_downward_rounded;
    return Semantics(
      button: true,
      label: done
          ? 'Свалянето приключи'
          : failed
              ? 'Свалянето прекъсна'
              : 'Сваляне на новата версия, ${(state.fraction * 100).round()}%',
      child: CustomPaint(
        painter: _RingPainter(
          fraction: done ? 1 : state.fraction,
          color: failed ? kUpdateOrange : kDownloadBlue,
          spin: state.phase == DownloadPhase.running && state.fraction == 0
              ? spin
              : null,
        ),
        child: Center(
          child: Icon(icon,
              size: 20,
              color: done
                  ? kDownloadBlue
                  : failed
                      ? kUpdateOrange
                      : AppColors.textPrimary.withValues(alpha: 0.85)),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double fraction;
  final Color color;

  /// Не е null — още няма байтове: въртящо се късо парче вместо дъга.
  final double? spin;
  _RingPainter({required this.fraction, required this.color, this.spin});

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 3.2;
    final rect = (Offset.zero & size).deflate(5 + stroke / 2);
    canvas.drawArc(
        rect,
        0,
        2 * math.pi,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..color = const Color(0xFF4A4A4A));
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = color;
    final s = spin;
    if (s != null) {
      canvas.drawArc(rect, -math.pi / 2 + s * 2 * math.pi, math.pi / 3, false, p);
    } else if (fraction > 0) {
      canvas.drawArc(rect, -math.pi / 2, 2 * math.pi * fraction.clamp(0, 1), false, p);
    }
  }

  @override
  bool shouldRepaint(_RingPainter o) =>
      o.fraction != fraction || o.color != color || o.spin != spin;
}

/// Съдържанието на разгънатия прозорец — по фазата.
class _Panel extends StatelessWidget {
  final DownloadState state;
  const _Panel({required this.state});

  static String _mb(num bytes) => (bytes / 1048576).round().toString();

  static String _eta(double seconds) {
    if (seconds < 60) return 'още ~${math.max(5, (seconds / 5).round() * 5)} s';
    final m = (seconds / 60).round();
    return 'още ~$m мин';
  }

  @override
  Widget build(BuildContext context) {
    final info = AppUpdate.available.value;
    final title = switch (state.phase) {
      DownloadPhase.done => 'Свалянето приключи успешно',
      DownloadPhase.failed => 'Свалянето прекъсна',
      _ => 'Сваляне на новата версия',
    };
    final done = state.phase == DownloadPhase.done;
    final failed = state.phase == DownloadPhase.failed;
    final gotMb = '${_mb(state.fraction * state.total)} / ${_mb(state.total)} MB';

    final Widget body;
    if (done) {
      body = Text(
          info == null
              ? 'Новата версия е готова за инсталиране.'
              : 'Версия 0.9.${info.build} е готова за инсталиране.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 14, height: 1.35));
    } else {
      final speed = state.speed;
      final right = failed
          ? (state.error ?? '')
          : speed > 0
              ? '${(speed / 1048576).toStringAsFixed(1).replaceAll('.', ',')} MB/s · '
                  '${_eta((1 - state.fraction) * state.total / speed)}'
              : '';
      body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: state.phase == DownloadPhase.running && state.fraction == 0
                ? null
                : state.fraction,
            minHeight: 6,
            color: failed ? kUpdateOrange : kDownloadBlue,
            backgroundColor: const Color(0xFF3A3A3A),
          ),
        ),
        const SizedBox(height: 10),
        Row(children: [
          Text(gotMb,
              style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  fontFeatures: [FontFeature.tabularFigures()])),
          const SizedBox(width: 12),
          Expanded(
            child: Text(right,
                textAlign: TextAlign.right,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: failed ? kUpdateOrange : AppColors.textMuted,
                    fontSize: 13,
                    fontFeatures: const [FontFeature.tabularFigures()])),
          ),
        ]),
        if (failed) ...[
          const SizedBox(height: 6),
          Text('Изтегленото е запазено — ще продължи оттам.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
        ],
      ]);
    }

    final secondary = TextButton.styleFrom(foregroundColor: AppColors.textSecondary);
    final primary = FilledButton.styleFrom(
      backgroundColor: done ? kDownloadBlue : AppColors.sectionTitle,
      foregroundColor: Colors.white,
      visualDensity: VisualDensity.compact,
    );
    final List<Widget> actions = switch (state.phase) {
      DownloadPhase.done => [
          TextButton(onPressed: AppUpdate.close, style: secondary, child: const Text('По-късно')),
          FilledButton.icon(
            onPressed: AppUpdate.installDownloaded,
            style: primary,
            icon: const Icon(Icons.install_mobile, size: 18),
            label: const Text('Инсталирай'),
          ),
        ],
      DownloadPhase.failed => [
          TextButton(onPressed: AppUpdate.close, style: secondary, child: const Text('Затвори')),
          FilledButton.icon(
            onPressed: AppUpdate.retry,
            style: primary,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Продължи'),
          ),
        ],
      _ => [
          TextButton(onPressed: AppUpdate.cancel, style: secondary, child: const Text('Отказ')),
          FilledButton.icon(
            onPressed: AppUpdate.collapse,
            style: primary,
            icon: const Icon(Icons.south_west_rounded, size: 18),
            label: const Text('Във фонов режим'),
          ),
        ],
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 14, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            if (done) ...[
              const Icon(Icons.check_circle_rounded, color: kDownloadBlue, size: 24),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Text(title,
                  style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w600)),
            ),
          ]),
          Padding(
            padding: const EdgeInsets.only(top: 16, right: 6, bottom: 10),
            child: body,
          ),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 6,
            children: actions,
          ),
        ],
      ),
    );
  }
}
