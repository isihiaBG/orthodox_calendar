import 'package:flutter/foundation.dart' show kIsWeb;
import 'audiobook.dart' show AudioQuality;
import 'audio_outro.dart' show AudioOutroSetting;
import 'package:flutter/material.dart';
import 'app_theme.dart';
import 'app_update.dart';
import 'app_version.dart';
import 'app_settings.dart';
import 'calendar_style_picker.dart';
import 'database_helper.dart';
import 'bible_packs_screen.dart';
import 'bible_settings.dart';
import 'drop_cap_scale.dart';

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
/// ⚠ Редът тук е редът на екрана. `app` (актуализацията) е първа — към
/// нея водят червените точки.
enum SettingsSection { app, calendar, reader, bible, audio }

const _kAllSections = {
  SettingsSection.app,
  SettingsSection.calendar,
  SettingsSection.reader,
  SettingsSection.bible,
  SettingsSection.audio,
};

/// ⚠ Заглавията са КРАТКИ нарочно — тук са уместни, защото човекът вече е в
/// екрана „Настройки" и „ЗА ЧЕТИВАТА" се чете еднозначно като „настройките
/// за четивата". В МЕНЮТО зад трите точки същият надпис създава съвсем
/// друга асоциация (звучи като раздел с четива), затова там редът се казва
/// просто „Настройки" — виж kReaderSettingsMenuItem.
const _kSectionTitles = {
  SettingsSection.app: 'ПРИЛОЖЕНИЕ',
  SettingsSection.calendar: 'КАЛЕНДАР',
  SettingsSection.reader: 'ЗА ЧЕТИВАТА',
  SettingsSection.bible: 'БИБЛИЯ',
  SettingsSection.audio: 'ЗВУК',
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
  DropCapScale _dropCapScale = ReaderDropCapScale.value;
  bool _zachala = BibleZachala.value;
  bool _bibleWelcome = BibleWelcome.value;
  bool _audioLow = AudioQuality.low.value;
  bool _outro = AudioOutroSetting.value;

  @override
  void initState() {
    super.initState();
    // Настройките може да се отворят и БЕЗ да е минато през четец преди
    // това (напр. направо от главното меню) — тогава ReaderDropCapScale
    // още не е зареден от диска.
    ReaderDropCapScale.loadOnce().then((_) {
      if (mounted) setState(() => _dropCapScale = ReaderDropCapScale.value);
    });
    // ⚠ Същото важи и за двете настройки на „Библия": те се четат от диска в
    // `BibleContents._load` и в `_openBible`, тоест ЧАК при влизане в
    // секцията. Отвори ли се този екран пръв след пускане на приложението,
    // без тях суичовете показват подразбирането вместо запазеното — тихо и
    // правдоподобно, докато човек не забележи, че е „изключил" нещо, което
    // вече е било изключено.
    BibleZachala.loadOnce().then((_) {
      if (mounted) setState(() => _zachala = BibleZachala.value);
    });
    BibleWelcome.loadOnce().then((_) {
      if (mounted) setState(() => _bibleWelcome = BibleWelcome.value);
    });
    AudioQuality.loadOnce().then((_) {
      if (mounted) setState(() => _audioLow = AudioQuality.low.value);
    });
    AudioOutroSetting.loadOnce().then((_) {
      if (mounted) setState(() => _outro = AudioOutroSetting.value);
    });
  }

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
                  color: AppColors.textMuted, 
                  fontSize: 13, 
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.5)),
        ],
      ),
    );
  }

  bool _checking = false;

  Future<void> _checkNow() async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    setState(() => _checking = true);
    final ok = await AppUpdate.check();
    if (!mounted) return;
    setState(() => _checking = false);
    // Тук човекът сам е поискал — затова се казва и неуспехът.
    messenger?.showSnackBar(SnackBar(
      content: Text(!ok
          ? 'Няма връзка — опитай пак по-късно.'
          : AppUpdate.available.value != null
              ? 'Има нова версия.'
              : 'Приложението е актуално.'),
    ));
  }

  static String _when(DateTime? t) {
    if (t == null) return 'Още не е проверявано.';
    final now = DateTime.now();
    String two(int x) => x.toString().padLeft(2, '0');
    final hm = '${two(t.hour)}:${two(t.minute)}';
    final d0 = DateTime(now.year, now.month, now.day);
    final d1 = DateTime(t.year, t.month, t.day);
    final days = d0.difference(d1).inDays;
    final day = days == 0
        ? 'днес'
        : days == 1
            ? 'вчера'
            : '${t.day}.${two(t.month)}.${t.year}';
    return 'Последна проверка: $day, $hm';
  }

  /// „ПРИЛОЖЕНИЕ" — актуализацията (app_update.dart). Без нея (уеб, билдът
  /// за Google Play) секцията е празна и изобщо не се показва.
  List<Widget> _appSection() {
    if (!AppUpdate.supported) return const [];
    return [
      FutureBuilder<String>(
        future: appVersionLabel(),
        builder: (_, s) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(s.data ?? '',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 14)),
        ),
      ),
      ListenableBuilder(
        listenable: Listenable.merge([AppUpdate.available, AppUpdate.lastOk]),
        builder: (context, _) {
          final a = AppUpdate.available.value;
          final checkBtn = _checking
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                )
              : TextButton(onPressed: _checkNow, child: const Text('Провери'));
          if (a == null) {
            return Row(children: [
              Icon(Icons.verified_outlined, color: AppColors.textMuted, size: 22),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                      AppUpdate.lastOk.value == null
                          ? 'Проверка за нова версия'
                          : 'Приложението е актуално',
                      style: const TextStyle(color: AppColors.textPrimary, fontSize: 16)),
                  const SizedBox(height: 2),
                  Text(_when(AppUpdate.lastOk.value),
                      style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                ]),
              ),
              checkBtn,
            ]);
          }
          // Има нова версия — карта, към която водят червените точки.
          return Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 10, 6),
            decoration: BoxDecoration(
              color: AppColors.backgroundCard,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: kUpdateRed.withValues(alpha: 0.35)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                withUpdateDot(
                    const Icon(Icons.system_update, color: AppColors.textPrimary, size: 26),
                    kUpdateRed),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Налична е нова версия',
                        style: TextStyle(color: AppColors.textPrimary, fontSize: 16)),
                    const SizedBox(height: 2),
                    ValueListenableBuilder<bool>(
                      valueListenable: AppUpdate.downloaded,
                      builder: (_, done, _) => Text(
                          done
                              ? 'Свалена е — готова за инсталиране'
                              : '${a.sizeLabel} · ${_when(AppUpdate.lastOk.value)}',
                        style: TextStyle(color: AppColors.textMuted, fontSize: 12))),
                  ]),
                ),
              ]),
              const SizedBox(height: 6),
              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                TextButton(
                    onPressed: () => showWhatsNew(context),
                    child: const Text('Какво ново')),
                const SizedBox(width: 4),
                // Свалено ли е вече — „Инсталирай" (автора, 26.10.2026).
                ValueListenableBuilder<bool>(
                  valueListenable: AppUpdate.downloaded,
                  builder: (_, done, _) => FilledButton.icon(
                    onPressed: () => done
                        ? AppUpdate.install(context)
                        : AppUpdate.downloadAndInstall(context),
                    icon: Icon(done ? Icons.install_mobile : Icons.download, size: 18),
                    label: Text(done ? 'Инсталирай' : 'Свали'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.sectionTitle,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ]),
            ]),
          );
        },
      ),
    ];
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
              label: Text('Питай за стила', style: TextStyle(fontSize: 14, height: 1.0)),
              icon: Icon(Icons.auto_stories, size: 16),
            ),
            ButtonSegment(
              value: false,
              label: Text('Направо в календара', style: TextStyle(fontSize: 14, height: 1.0)),
              icon: Icon(Icons.calendar_month, size: 18),
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

  /// Общи настройки за четеца (жития + книги). Първата, за размера на
  /// буквицата — виж drop_cap_scale.dart.
  List<Widget> _readerSection() {
    return [
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text('РАЗМЕР НА ВОДЕЩАТА БУКВА',
            style: TextStyle(
              color: AppColors.textMuted,
              fontSize: 11,
              letterSpacing: 1.5,
            )),
      ),
      Center(
        child: SegmentedButton<DropCapScale>(
          style: SegmentedButton.styleFrom(
            backgroundColor: AppColors.backgroundCard,
            foregroundColor: AppColors.textMuted,
            selectedForegroundColor: AppColors.textPrimary,
            selectedBackgroundColor: AppColors.appBarWeekday,
            // ⚠ При избран сегмент Flutter показва отметка ПРЕДИ текста —
            // и за нея закача фиксиран отстъп (12/16 пункта), който НЕ се
            // подчинява на `padding` тук (виж segmented_button.dart в
            // самия Flutter SDK: изрично overwrite, само за сегмента с
            // икона). С трите надписа („Малка"/„Средна"/„Голяма") това
            // стигаше „Средна" да се пренесе на втори ред. Свиваме каквото
            // РЕАЛНО се подчинява — иконата и шрифта — за да остане място.
            iconSize: 14,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            visualDensity: VisualDensity.compact,
            textStyle: const TextStyle(fontSize: 14, height: 1.0),
          ),
          segments: [
            for (final s in DropCapScale.values)
              ButtonSegment(
                value: s,
                label: Text(  //--- Етикетите за размера на Буквицата
                  s.label, 
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.visible,
                  style: const TextStyle(height: 1.0)),
              ),
          ],
          selected: {_dropCapScale},
          onSelectionChanged: (value) {
            final v = value.first;
            setState(() => _dropCapScale = v);
            ReaderDropCapScale.set(v);
          },
        ),
      ),
    ];
  }

  /// Настройки САМО за секцията „Библия".
  ///
  /// ⚠ Отделна категория, а не под „ЗА ЧЕТИВАТА". Там живеят неща от
  /// четенето на жития и книги (размерът на буквицата), които в Писанието
  /// изобщо не се срещат — Библията няма буквици. Смесени, двете се четат
  /// като „настройки, които може и да не важат тук".
  List<Widget> _bibleSection() {
    return [
      // ⚠ Отделен ЕКРАН, не ред тук: пакетите са десет, всеки с размер,
      // състояние и лента за напредъка — списък, не превключвател.
      ListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        leading: Icon(Icons.translate, color: AppColors.textSecondary),
        title: const Text('Преводи на Библията'),
        subtitle: Text(
          'Добавяне и премахване на езици.',
          style: TextStyle(color: AppColors.textMuted, fontSize: 12),
        ),
        trailing: Icon(Icons.chevron_right, color: AppColors.textMuted),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => const BiblePacksScreen())),
      ),
      const Divider(height: 18, color: AppColors.sectionDivider, thickness: 1),
      // ⚠ Редът в секцията върви от общото към частното: какви преводи имаш →
      // как се влиза → какво се вижда в самия текст. Затова въвеждащият екран
      // стои между двете, а не най-долу.
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        value: _bibleWelcome,
        onChanged: (v) {
          setState(() => _bibleWelcome = v);
          BibleWelcome.set(v);
        },
        title: const Text('Показвай въвеждащия екран'),
        subtitle: Text(
          'Изборът с трите корици, преди съдържанието.',
          style: TextStyle(color: AppColors.textMuted, fontSize: 12),
        ),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        value: _zachala,
        onChanged: (v) {
          setState(() => _zachala = v);
          BibleZachala.set(v);
        },
        title: const Text('Показвай зачалата'),
        subtitle: Text(
          // Обяснението е нужно: „зачало" е богослужебен термин и човек,
          // който не го знае, няма как да отгатне какво изключва.
          'Указателите „[Зач. 1]" в началото на богослужебните четива.',
          style: TextStyle(color: AppColors.textMuted, fontSize: 12),
        ),
      ),
    ];
  }

  /// Качеството на звука, който се сваля (18.10.2026, искане на автора).
  /// ⚠ В браузъра звук няма (сваляне с dart:io), затова там секцията е празна
  /// и изобщо не се показва.
  List<Widget> _audioSection() {
    if (kIsWeb) return const [];
    return [
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text('КАЧЕСТВО НА ЗВУКА',
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
            iconSize: 14,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            visualDensity: VisualDensity.compact,
            textStyle: const TextStyle(fontSize: 14, height: 1.0),
          ),
          segments: const [
            ButtonSegment(value: true, label: Text('Икономично')),
            ButtonSegment(value: false, label: Text('Високо')),
          ],
          selected: {_audioLow},
          onSelectionChanged: (v) {
            setState(() => _audioLow = v.first);
            AudioQuality.set(v.first);
          },
        ),
      ),
      const SizedBox(height: 12),
      Text(
        _audioLow
            ? 'Файловете са около три пъти по-малки (около 9 MB на час) и се '
                'свалят по-лесно. Гласът звучи почти както в оригинала.'
            : 'Оригиналният запис (около 29 MB на час) — най-доброто качество, '
                'но файловете са около три пъти по-големи.',
        style: TextStyle(color: AppColors.textMuted, fontSize: 12),
      ),
      const SizedBox(height: 6),
      Text(
        'Изборът важи за следващите сваляния. Вече свалените беседи остават '
            'в качеството, в което са свалени.',
        style: TextStyle(color: AppColors.textMuted, fontSize: 12),
      ),
      const Divider(height: 28, color: AppColors.sectionDivider, thickness: 1),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        value: _outro,
        onChanged: (v) {
          setState(() => _outro = v);
          AudioOutroSetting.set(v);
        },
        title: const Text('Музика в края на беседата'),
        subtitle: Text(
          'Тиха мелодия на дудук след последните думи, преди следващата беседа.',
          style: TextStyle(color: AppColors.textMuted, fontSize: 12),
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final sectionContent = {
      SettingsSection.app: _appSection,
      SettingsSection.calendar: _calendarSection,
      SettingsSection.reader: _readerSection,
      SettingsSection.bible: _bibleSection,
      SettingsSection.audio: _audioSection,
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

    // Изричното `padding` изключва автоматичния отстъп на ListView от
    // системната лента отдолу — затова той се добавя на ръка, плюс въздух,
    // за да не опира последното каре в чертата за жестове.
    return ListView(
      padding: EdgeInsets.fromLTRB(
          16, 16, 16, 32 + MediaQuery.paddingOf(context).bottom),
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
