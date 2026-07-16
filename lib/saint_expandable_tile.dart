// saint_expandable_tile.dart
//
// Разгъващ се булет на светия за дневния изглед — LAZY версия,
// интегрирана към реалната архитектура на приложението:
//
//  - Дневната заявка НЕ тегли текстовете (те са до 130 KB на житие!),
//    а само два евтини флага: has_prayers, has_life.
//  - Пълните текстове се зареждат чак при тап върху секция, през
//    подадената loadTexts() функция.
//  - В свито състояние редът изглежда точно както досега (подава се
//    готов collapsedRow). Триъгълниче вдясно има само ако има текстове.
//  - Разгънато: до две секции с chevron — "Тропар и кондак" и "Житие".

import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'reader_screen.dart';

/// Текстовете на един светия (ред от таблицата saints с новите колони).
class SaintTexts {
  final String name;
  final String tropar, troparTrans, tropar2, tropar2Trans;
  final String kondak, kondakTrans, kondak2, kondak2Trans;
  final String lifeHtml;
  final String sluzhba;
  final String source; // URL за атрибуция под житието
  final String slug;

  const SaintTexts({
    required this.name,
    this.tropar = '',
    this.troparTrans = '',
    this.tropar2 = '',
    this.tropar2Trans = '',
    this.kondak = '',
    this.kondakTrans = '',
    this.kondak2 = '',
    this.kondak2Trans = '',
    this.lifeHtml = '',
    this.sluzhba = '',
    this.source = '',
    this.slug = '',
  });

  factory SaintTexts.fromMap(Map<String, dynamic> m) => SaintTexts(
        name: (m['name'] ?? '') as String,
        tropar: (m['tropar'] ?? '') as String,
        troparTrans: (m['tropar_trans'] ?? '') as String,
        tropar2: (m['tropar2'] ?? '') as String,
        tropar2Trans: (m['tropar2_trans'] ?? '') as String,
        kondak: (m['kondak'] ?? '') as String,
        kondakTrans: (m['kondak_trans'] ?? '') as String,
        kondak2: (m['kondak2'] ?? '') as String,
        kondak2Trans: (m['kondak2_trans'] ?? '') as String,
        lifeHtml: (m['life'] ?? '') as String,
        sluzhba: (m['sluzhba'] ?? '') as String,
        source: (m['source'] ?? '') as String,
        slug: (m['slug'] ?? '') as String,
      );

  bool get hasPrayers => tropar.isNotEmpty || kondak.isNotEmpty;
  bool get hasLife => lifeHtml.isNotEmpty;
  bool get hasSluzhba => sluzhba.isNotEmpty;
}

/// Търсене по слъг — за saint:// линковете в житията.
typedef SaintLookup = Future<SaintTexts?> Function(String slug);

/// Кой раздел се отваря при тап върху секция.
enum _Section { prayers, life, sluzhba }

/// Етикетът на секцията с молитвите според това какво реално има:
/// "Тропар", "Кондак" или "Тропар и кондак". Празен низ = няма нищо.
String prayersLabel({required bool hasTropar, required bool hasKondak}) {
  if (hasTropar && hasKondak) return 'Тропар и кондак';
  if (hasTropar) return 'Тропар';
  if (hasKondak) return 'Кондак';
  return '';
}

/// Същото, но от заредените текстове (ползва се в четеца за заглавието).
String prayersTitleFor(SaintTexts t) => prayersLabel(
      hasTropar: t.tropar.isNotEmpty,
      hasKondak: t.kondak.isNotEmpty,
    );

class SaintExpandableTile extends StatefulWidget {
  /// Редът, както се рендва сега (SVG знак + име) — не се променя визуално.
  final Widget collapsedRow;

  /// Евтините флагове от дневната заявка.
  final bool hasTropar;
  final bool hasKondak;
  final bool hasLife;
  final bool hasSluzhba;

  /// Зарежда пълните текстове от базата — вика се чак при тап.
  final Future<SaintTexts?> Function() loadTexts;

  /// Търсене по слъг за вътрешните линкове (подава се на четеца).
  final SaintLookup lookup;

  const SaintExpandableTile({
    super.key,
    required this.collapsedRow,
    required this.hasTropar,
    required this.hasKondak,
    required this.hasLife,
    required this.hasSluzhba,
    required this.loadTexts,
    required this.lookup,
  });

  @override
  State<SaintExpandableTile> createState() => _SaintExpandableTileState();
}

class _SaintExpandableTileState extends State<SaintExpandableTile> {
  bool _expanded = false;

  String get _prayersLabel => prayersLabel(
        hasTropar: widget.hasTropar,
        hasKondak: widget.hasKondak,
      );

  bool get _hasAnything =>
      _prayersLabel.isNotEmpty || widget.hasLife || widget.hasSluzhba;

  void _toggle() {
    if (!_hasAnything) return;
    setState(() => _expanded = !_expanded);
  }

  Future<void> _open(_Section section) async {
    final texts = await widget.loadTexts();
    if (!mounted || texts == null) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) {
        if (section == _Section.prayers) {
          return ReaderScreen.prayers(texts: texts, lookup: widget.lookup);
        } else if (section == _Section.sluzhba) {
          return ReaderScreen.sluzhba(texts: texts, lookup: widget.lookup);
        }
        return ReaderScreen.life(texts: texts, lookup: widget.lookup);
      },
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: _toggle,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: widget.collapsedRow),
              if (_hasAnything)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: AnimatedRotation(
                    turns: _expanded ? 0.25 : 0.0, // ▸ → ▾
                    duration: const Duration(milliseconds: 180),
                    child: Icon(
                      Icons.arrow_right,
                      size: 20,
                      color: Theme.of(context).hintColor,
                    ),
                  ),
                ),
            ],
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeInOut,
          alignment: Alignment.topCenter,
          child: !_expanded
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(left: 32, bottom: 4),
                  child: Column(
                    children: [
                      if (_prayersLabel.isNotEmpty)
                        _SectionRow(
                          icon: Icons.music_note_outlined,
                          label: _prayersLabel,
                          onTap: () => _open(_Section.prayers),
                        ),
                      if (widget.hasLife)
                        _SectionRow(
                          icon: Icons.menu_book_outlined,
                          label: 'Житие',
                          onTap: () => _open(_Section.life),
                        ),
                      if (widget.hasSluzhba)
                        _SectionRow(
                          icon: Icons.local_library_outlined,
                          label: 'Служба',
                          onTap: () => _open(_Section.sluzhba),
                        ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}

class _SectionRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _SectionRow({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(
          children: [
            Icon(icon, size: 18, color: AppColors.sectionTitle), 
            const SizedBox(width: 10),
            Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
            Icon(Icons.chevron_right, size: 20, color: theme.hintColor),
          ],
        ),
      ),
    );
  }
}
