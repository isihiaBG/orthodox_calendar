import 'package:flutter/material.dart';
import 'app_theme.dart';
import 'app_settings.dart';
import 'calendar_style_picker.dart';
import 'database_helper.dart';

/// Превключва между графичния избор на стил (трите корици, като на
/// въвеждащия екран) и старите двойка превключватели. Стойността по
/// подразбиране е графичният избор — старите НЕ са изтрити, само загасени
/// тук, в случай че потрябват отново или се предложи избор между двата
/// начина в самите настройки.
const bool _kUseGraphicalCalendarStylePicker = true;

/// Категориите, на които се делят настройките. Всяка е флаг: бързата
/// връзка (напр. иконата горе вдясно в календара) вдига само категорията
/// на екрана, откъдето е повикана, а пълният екран от менюто ги вдига
/// всички наведнъж, разделени с малко заглавие.
///
/// ЧЕТЕЦ засега е празна категория (общи настройки за двата четеца —
/// жития и книги — предстоят); съществува тук, за да не се пренарежда
/// всичко наново, когато се появят.
enum SettingsSection { calendar, reader }

const _kAllSections = {SettingsSection.calendar, SettingsSection.reader};

const _kSectionTitles = {
  SettingsSection.calendar: 'КАЛЕНДАР',
  SettingsSection.reader: 'ЧЕТЕЦ',
};

// ─── Общото съдържание на настройките ────────────────────────────────────
class SettingsContent extends StatefulWidget {
  final Function(bool styleChanged, [DateTime? capturedMiddleDate])? onChanged;
  /// Кои категории да се покажат. По подразбиране — всички (пълния екран
  /// от менюто); бързите връзки подават само своята.
  final Set<SettingsSection> sections;
  const SettingsContent({
    super.key,
    this.onChanged,
    this.sections = _kAllSections,
  });

  @override
  State<SettingsContent> createState() => _SettingsContentState();
}

class _SettingsContentState extends State<SettingsContent> {
  bool _isOldStyle = AppSettings.isOldStyle;
  bool _oldStyleFirst = AppSettings.oldStyleFirst;
  bool _showWelcome = AppSettings.showWelcome;

  /// Заглавието на секция. Разделителна линия само ако НЕ е първата
  /// показана секция — инак виси самотна над нищото.
  Widget _sectionTitle(String text, {required bool withDivider}) {
    return Padding(
      padding: EdgeInsets.only(top: withDivider ? 28 : 4, bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (withDivider) ...[
            Divider(color: AppColors.textMuted.withValues(alpha: 0.25)),
            const SizedBox(height: 16),
          ],
          Text(text,
              style: TextStyle(
                  color: AppColors.textMuted, fontSize: 11, letterSpacing: 1.5)),
        ],
      ),
    );
  }

  List<Widget> _calendarSection() {
    return [
      // ─── Стар/Нов стил + водеща дата ───────────────────────────────────
      // Графичният избор (трите корици) замества старите два
      // превключвателя по подразбиране — виж
      // _kUseGraphicalCalendarStylePicker.
      ...(_kUseGraphicalCalendarStylePicker
          ? [CalendarStylePicker(onChanged: widget.onChanged)]
          : _legacyStyleAndLeadingDateSwitches()),

      // ─── Въвеждащият екран ─────────────────────────────────────────────
      // Стои НАКРАЯ, защото не мени как изглежда календарът, а само дали
      // да се пита за стила при стартиране. Същото поле пипа и чекбоксът
      // „Не показвай повече" на самия екран.
      const SizedBox(height: 24),
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text('ПРИ ОТВАРЯНЕ',
            style: TextStyle(
              color: AppColors.textMuted,
              fontSize: 11,
              letterSpacing: 1.5,
            )),
      ),
      Center(
        child: SegmentedButton<bool>(
          style: SegmentedButton.styleFrom(
            backgroundColor: AppColors.backgroundCard,
            foregroundColor: AppColors.textMuted,
            selectedForegroundColor: AppColors.textPrimary,
            selectedBackgroundColor: AppColors.appBarWeekday,
          ),
          // ⚠ height: 1.0 на надписите — без него подразбиращото се
          // междуредие на Text е по-високо от реда, който SegmentedButton
          // отделя за него, и „Направо в календара" (по-дългият, чупи се
          // на два реда) изтича извън копчето.
          segments: const [
            ButtonSegment(
              value: true,
              label: Text('Питай за стила', style: TextStyle(height: 1.0)),
              icon: Icon(Icons.auto_stories, size: 16),
            ),
            ButtonSegment(
              value: false,
              label: Text('Направо в календара', style: TextStyle(height: 1.0)),
              icon: Icon(Icons.calendar_month, size: 16),
            ),
          ],
          selected: {_showWelcome},
          onSelectionChanged: (value) {
            setState(() {
              _showWelcome = value.first;
              AppSettings.showWelcome = value.first;
            });
            AppSettings.scheduleSave();
          },
        ),
      ),
      Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.backgroundCard,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          _showWelcome
              ? 'При всяко отваряне ще се показва изборът на календар.'
              : 'Приложението се отваря направо на днешния ден.',
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 13,
            height: 1.5,
          ),
        ),
      ),
    ];
  }

  /// Старите два превключвателя (стар/нов стил, водеща дата) — заменени по
  /// подразбиране от графичния избор [CalendarStylePicker], но НЕИЗТРИТИ:
  /// стоят зад [_kUseGraphicalCalendarStylePicker] в случай че потрябват
  /// отново, или се добави превключване между двата начина в самите
  /// настройки.
  List<Widget> _legacyStyleAndLeadingDateSwitches() {
    return [
      // ─── Стар/Нов стил ───────────────────────────────────────────────
      Center(
        child: SegmentedButton<bool>(
          style: SegmentedButton.styleFrom(
            backgroundColor: AppColors.backgroundCard,
            foregroundColor: AppColors.textMuted,
            selectedForegroundColor: AppColors.textPrimary,
            selectedBackgroundColor: AppColors.appBarWeekday,
          ),
          segments: const [
            ButtonSegment(
              value: true,
              label: Text('Стар стил'),
              icon: Icon(Icons.history, size: 16),
            ),
            ButtonSegment(
              value: false,
              label: Text('Нов стил'),
              icon: Icon(Icons.today, size: 16),
            ),
          ],
          selected: {_isOldStyle},
          onSelectionChanged: (value) async {
            final newIsOldStyle = value.first;
            // Улавяме КОЯ дата в момента е "по средата" на месечния
            // изглед ПРЕДИ да мутираме isOldStyle — виж докстринга на
            // AppSettings.captureMonthMiddleDate за причината редът да
            // има значение.
            final capturedMiddleDate =
                AppSettings.captureMonthMiddleDate?.call();
            setState(() {
              _isOldStyle = newIsOldStyle;
              AppSettings.isOldStyle = newIsOldStyle;
            });
            AppSettings.scheduleSave();
            await DatabaseHelper.resetDatabase();
            await DatabaseHelper.database;
            widget.onChanged?.call(true, capturedMiddleDate);
          },
        ),
      ),
      const SizedBox(height: 16),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.backgroundCard,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          _isOldStyle
              ? 'Юлиански (стар) стил. В горната лента ще се показва справочно и датата по Григориански (нов) стил.'
              : 'Григориански (нов) стил. Показва се само датата по нов стил.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.5),
        ),
      ),

      // ─── Водеща дата — плавно разширяване/свиване ────────────────────
      AnimatedSize(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        child: SizedBox(
          width: double.infinity,
          child: _isOldStyle
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 24),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text('ВОДЕЩА ДАТА',
                        style: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 11,
                          letterSpacing: 1.5,
                        )),
                    ),
                    Center(
                      child: SegmentedButton<bool>(
                        style: SegmentedButton.styleFrom(
                          backgroundColor: AppColors.backgroundCard,
                          foregroundColor: AppColors.textMuted,
                          selectedForegroundColor: AppColors.textPrimary,
                          selectedBackgroundColor: AppColors.appBarWeekday,
                        ),
                        segments: const [
                          ButtonSegment(
                            value: true,
                            label: Text('Стар стил'),
                            icon: Icon(Icons.history, size: 16),
                          ),
                          ButtonSegment(
                            value: false,
                            label: Text('Нов стил'),
                            icon: Icon(Icons.today, size: 16),
                          ),
                        ],
                        selected: {_oldStyleFirst},
                        onSelectionChanged: (value) {
                          // Улавяме СРЕДНИЯ ден ПРЕДИ мутацията — виж
                          // докстринга на AppSettings.captureMonthMiddleDate.
                          // Тук е особено важно: текущо показаните редове
                          // на екрана се тълкуват през призмата на СТАРАТА
                          // (все още активна) стойност на oldStyleFirst.
                          // Ако уловим датата СЛЕД мутацията, тя ще се
                          // конвертира през НОВАТА настройка върху редове,
                          // построени при СТАРАТА — двойно изместване.
                          final capturedMiddleDate =
                              AppSettings.captureMonthMiddleDate?.call();
                          setState(() {
                            _oldStyleFirst = value.first;
                            AppSettings.oldStyleFirst = value.first;
                          });
                          AppSettings.scheduleSave();
                          widget.onChanged?.call(false, capturedMiddleDate);
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.backgroundCard,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _oldStyleFirst
                            ? 'Църковната дата (стар стил) е на преден план вляво.'
                            : 'Гражданската дата (нов стил) е на преден план вляво.',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                )
              : const SizedBox.shrink(),
        ),
      ),
    ];
  }

  /// Общи настройки за четеца (жития + книги) — предстоят. Празна секция
  /// не рисува нищо, дори заглавие — виж build().
  List<Widget> _readerSection() => const [];

  @override
  Widget build(BuildContext context) {
    final sectionContent = {
      SettingsSection.calendar: _calendarSection,
      SettingsSection.reader: _readerSection,
    };

    final children = <Widget>[];
    var isFirst = true;
    for (final section in SettingsSection.values) {
      if (!widget.sections.contains(section)) continue;
      final content = sectionContent[section]!();
      if (content.isEmpty) continue;
      children.add(_sectionTitle(_kSectionTitles[section]!, withDivider: !isFirst));
      children.addAll(content);
      isFirst = false;
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: children,
    );
  }
}

// ─── Пълен екран (от менюто) ─────────────────────────────────────────────
class SettingsScreen extends StatelessWidget {
  final Function(bool styleChanged, [DateTime? capturedMiddleDate])? onChanged;
  /// Пълният екран показва ВСИЧКИ категории — виж SettingsSection.
  final Set<SettingsSection> sections;
  const SettingsScreen({
    super.key,
    this.onChanged,
    this.sections = _kAllSections,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.toolbar,
        toolbarHeight: 40,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary, size: 24),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Настройки',
          style: TextStyle(color: AppColors.textPrimary, fontSize: 20)),
      ),
      backgroundColor: AppColors.background,
      body: SettingsContent(onChanged: onChanged, sections: sections),
    );
  }
}

// ─── Десен Drawer (от toolbar) ───────────────────────────────────────────
class SettingsDrawer extends StatelessWidget {
  final Function(bool styleChanged, [DateTime? capturedMiddleDate])? onChanged;
  /// Бързата връзка показва САМО категорията на екрана, откъдето е
  /// повикана — затова е задължителен параметър, не по подразбиране.
  final Set<SettingsSection> sections;
  const SettingsDrawer({
    super.key,
    this.onChanged,
    required this.sections,
  });

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: AppColors.background,
      child: Column(
        children: [
          Container(
            color: AppColors.toolbar,
            height: 40 + MediaQuery.of(context).padding.top,
            padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top),
            child: Row(
              children: [
                const Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(left: 16),
                    child: Text('Настройки',
                      style: TextStyle(color: AppColors.textPrimary, fontSize: 20)),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.arrow_forward, color: AppColors.textPrimary, size: 24),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          Expanded(child: SettingsContent(onChanged: onChanged, sections: sections)),
        ],
      ),
    );
  }
}
