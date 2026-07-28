// info_sheet.dart
//
// Обща bottom sheet рамка за справочни/пояснителни панели в цялото
// приложение: заглавие, подзаглавие, регулируем шрифт (+/-, по аналогия
// на reader_screen.dart) и списък от елементи (лидираща икона/буква +
// заглавие + описание). Първи потребител: typikon_legend_sheet.dart —
// за нови справочни панели другаде в приложението просто викай
// showInfoSheet(...) с подходящи items.

import 'package:flutter/material.dart';

import 'app_theme.dart';

/// Кръгло копче с контур — ползва се за (−)/(+) регулиране на шрифта.
/// Извлечено от reader_screen.dart, за да се ползва навсякъде еднакво.
class RoundIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool enabled;
  final VoidCallback onTap;
  final double size;
  final Color color;

  const RoundIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.enabled,
    required this.onTap,
    required this.color,
    this.size = 26,
  });

  @override
  Widget build(BuildContext context) {
    final c = enabled ? color : color.withOpacity(0.35);
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: enabled ? onTap : null,
        customBorder: const CircleBorder(),
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: c, width: 1.3),
          ),
          child: Icon(icon, size: size * 0.58, color: c),
        ),
      ),
    );
  }
}

/// Един ред от справочния панел: лидираща икона/буква + заглавие + текст.
class InfoSheetItem {
  final Widget leading;
  final String title;
  final String description;

  const InfoSheetItem({
    required this.leading,
    required this.title,
    required this.description,
  });
}

void showInfoSheet({
  required BuildContext context,
  required String title,
  required String subtitle,
  required List<InfoSheetItem> items,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _InfoSheet(title: title, subtitle: subtitle, items: items),
  );
}

class _InfoSheet extends StatefulWidget {
  final String title;
  final String subtitle;
  final List<InfoSheetItem> items;

  const _InfoSheet({
    required this.title,
    required this.subtitle,
    required this.items,
  });

  @override
  State<_InfoSheet> createState() => _InfoSheetState();
}

class _InfoSheetState extends State<_InfoSheet> {
  // static, за да се пази размерът за сесията — както във reader_screen.
  static double _fontSize = 15.5;
  static const double _step = 1.5;
  static const double _min = 11.0;
  static const double _max = 22.0;
  static const double _btnSize = 26.0;

  void _bump(double d) {
    setState(() => _fontSize = (_fontSize + d).clamp(_min, _max));
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: screenHeight * 0.85),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.drawerBackground,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 20,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 8, bottom: 4),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.textMuted,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Импровизирана лента с инструменти: (−)/(+) шрифт, самостоятелно
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 12, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  RoundIconButton(
                    icon: Icons.remove,
                    tooltip: 'По-дребен шрифт',
                    enabled: _fontSize > _min,
                    onTap: () => _bump(-_step),
                    size: _btnSize,
                    color: AppColors.textPrimary,
                  ),
                  const SizedBox(width: 16),
                  RoundIconButton(
                    icon: Icons.add,
                    tooltip: 'По-едър шрифт',
                    enabled: _fontSize < _max,
                    onTap: () => _bump(_step),
                    size: _btnSize,
                    color: AppColors.textPrimary,
                  ),
                ],
              ),
            ),
            // Заглавието — отделено под лентата с инструменти, за да не се
            // асоциира визуално с бутоните.
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  widget.title,
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: _fontSize + 4,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  widget.subtitle,
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: _fontSize - 1,
                    height: 1.4,
                  ),
                ),
              ),
            ),
            Divider(color: AppColors.sectionDivider, height: 1),
            Flexible(
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                shrinkWrap: true,
                itemCount: widget.items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 14),
                itemBuilder: (context, index) {
                  final e = widget.items[index];
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(width: 26, height: 26, child: e.leading),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(e.title,
                                style: TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: _fontSize + 2,
                                  fontWeight: FontWeight.w600,
                                )),
                            const SizedBox(height: 2),
                            Text(e.description,
                                style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: _fontSize,
                                  height: 1.4,
                                )),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            SizedBox(height: 8 + MediaQuery.of(context).padding.bottom),
          ],
        ),
      ),
    );
  }
}
