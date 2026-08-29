// bible_search_panel.dart
//
// Панелът с настройките на ТЪРСЕНЕТО в „Библия“.
//
// ⚠ Изглежда като [SettingsDrawer] и това е нарочно, не мързел: за човека
// това е същото нещо — панел с настройки, който излиза отдясно. Различава
// се само по заглавието и по това откъде се вика (зъбното колело в лентата,
// докато полето за търсене е отворено).
//
// ⚠ Стойностите се пишат ВЕДНАГА в [BibleSearchSettings], а `onChanged`
// само подсеща викащия да преизчисли намереното: човек, който смени обхвата,
// докато гледа резултати, очаква да види новите, без да пише пак.

import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'bible_scope_screen.dart';
import 'bible_search_settings.dart';

class BibleSearchSettingsPanel extends StatefulWidget {
  /// Вика се след всяка промяна — за да се обновят резултатите на екрана,
  /// който стои под панела.
  final VoidCallback? onChanged;

  const BibleSearchSettingsPanel({super.key, this.onChanged});

  @override
  State<BibleSearchSettingsPanel> createState() =>
      _BibleSearchSettingsPanelState();
}

class _BibleSearchSettingsPanelState extends State<BibleSearchSettingsPanel> {
  @override
  Widget build(BuildContext context) {
    final where = BibleSearchSettings.where;
    final range = BibleSearchSettings.range;

    return Drawer(
      backgroundColor: AppColors.background,
      child: Column(
        children: [
          // Лентата е една към една с тази на [SettingsDrawer] — същата
          // височина, същият цвят, същата стрелка за затваряне.
          Container(
            color: AppColors.toolbar,
            height: 40 + MediaQuery.of(context).padding.top,
            padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top),
            child: Row(
              children: [
                const Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(left: 16),
                    // ⚠ „Разширено търсене", не само „Търсене". Обикновеното
                    // търсене се случва в лентата, без този панел изобщо да
                    // се отваря — тъй че самò „Търсене" обещава повече,
                    // отколкото панелът върши, и кара човек да се чуди дали
                    // не е пропуснал нещо в него.
                    child: Text('Разширено търсене',
                        style: TextStyle(
                            color: AppColors.textPrimary, fontSize: 20)),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.arrow_forward,
                      color: AppColors.textPrimary, size: 24),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                _title('КЪДЕ ДА СЕ ТЪРСИ', first: true),
                RadioGroup<BibleSearchWhere>(
                  groupValue: where,
                  onChanged: (v) {
                    if (v != null) _set(() => BibleSearchSettings.setWhere(v));
                  },
                  child: const Column(
                    children: [
                      // ⚠ ЕДНА НАСТРОЙКА, ДВА ЕКРАНА — затова първият избор
                      // НЕ се казва „в имената на книгите". В указателя това
                      // е вярно, но същият панел се отваря и от четеца, а
                      // там имена на книги няма: там се търси в стиховете на
                      // отворената глава. Общото между двете е „каквото е
                      // пред очите ми", и точно това казва надписът; какво
                      // значи то на всяко от местата стои отдолу.
                      _Choice(
                        value: BibleSearchWhere.names,
                        title: 'На този екран',
                        subtitle: 'В указателя — по имената на книгите; в '
                            'четивото — по стиховете на главата. Намереното '
                            'свети на място.',
                      ),
                      _Choice(
                        value: BibleSearchWhere.text,
                        title: 'В целия текст на Писанието',
                        subtitle:
                            'Отваря намерените стихове като списък с извадки.',
                      ),
                    ],
                  ),
                ),

                // ⚠ Обхватът СЕ СКРИВА, вместо да посивее, когато търсенето е
                // в имената: той важи само за текста. Посивен ред пита „защо
                // не мога да го пипна" и иска обяснение; липсващият не пита
                // нищо, а се връща сам, щом стане приложим.
                if (where == BibleSearchWhere.text) ...[
                  _title('ДОКЪДЕ'),
                  RadioGroup<BibleSearchRange>(
                    groupValue: range,
                    onChanged: (v) {
                      if (v != null) {
                        _set(() => BibleSearchSettings.setRange(v));
                      }
                    },
                    child: const Column(
                      children: [
                        _Choice(
                          value: BibleSearchRange.all,
                          title: 'В цялото Писание',
                          subtitle: 'Независимо кой дял е отворен.',
                        ),
                        _Choice(
                          value: BibleSearchRange.tab,
                          title: 'Само в отворения дял',
                          subtitle: 'Нов завет, Стар завет или Псалтир — '
                              'според таба, на който стоиш.',
                        ),
                        _Choice(
                          value: BibleSearchRange.picked,
                          title: 'В избрани книги',
                          subtitle: 'Отмятат се поименно — цели завети, '
                              'дялове, отделни книги или катизми.',
                        ),
                      ],
                    ),
                  ),
                  // ⚠ Редът с избраното стои ПОД групата, а не като подред на
                  // третата възможност: той е и бутон (води към отмятането), и
                  // отчет (казва какво е отметнато). Вложен в списъка с
                  // кръгчета, щеше да изглежда като четвърта възможност.
                  if (range == BibleSearchRange.picked) _pickedRow(),
                ],

                const SizedBox(height: 20),
                // ⚠ Бележка, а не настройка: езикът се сменя в самия четец и
                // втори превключвател за него тук би създал две места за
                // едно нещо. Казва се обаче изрично, защото инак „не намирам
                // думата" изглежда като счупено търсене, а причината е, че
                // отсреща стои църковнославянският.
                Text(
                  'Търси се в превода, който четеш в момента.',
                  style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 12,
                      height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Обобщението на поименния избор — колко е отметнато и вход към екрана.
  Widget _pickedRow() {
    final pick = BibleSearchSettings.pick;
    final n = pick.books.length + (pick.kathismata.isEmpty ? 0 : 1);
    return Padding(
      padding: const EdgeInsets.only(left: 4, top: 4),
      child: InkWell(
        onTap: () async {
          final res = await pickBibleScope(context, pick);
          if (res == null) return;
          await BibleSearchSettings.setPick(res);
          if (!mounted) return;
          setState(() {});
          widget.onChanged?.call();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              const Icon(Icons.checklist, size: 20, color: AppColors.textMuted),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  // ⚠ Празният избор се казва изрично. „В избрани книги" без
                  // нито една отметната не търси НИКЪДЕ, а мълчаливият ред би
                  // оставил това да се открие чак по празния резултат.
                  n == 0
                      ? 'Нищо не е избрано — избери'
                      : 'Избрани: $n ${n == 1 ? "книга" : "книги"}',
                  style: TextStyle(
                    color: n == 0 ? AppColors.sectionTitle : AppColors.textPrimary,
                    fontSize: 15,
                  ),
                ),
              ),
              const Icon(Icons.chevron_right,
                  size: 22, color: AppColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }

  void _set(VoidCallback apply) {
    apply();
    setState(() {});
    widget.onChanged?.call();
  }

  Widget _title(String text, {bool first = false}) {
    return Padding(
      padding: EdgeInsets.only(top: first ? 4 : 26, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!first) ...[
            Divider(color: AppColors.textMuted.withValues(alpha: 0.25)),
            const SizedBox(height: 14),
          ],
          Text(text,
              style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.5)),
        ],
      ),
    );
  }

}

/// Един избор от група.
///
/// ⚠ Кръгче, а не ключ: изборите са по ДВА и се изключват взаимно, а ключ
/// („включено/изключено") би скрил втората възможност зад отрицанието на
/// първата — човек не вижда какво получава, ако я изключи.
///
/// ⚠ Без `groupValue`/`onChanged` — те са деприкирани и стойността идва от
/// обгръщащия `RadioGroup`.
class _Choice<T> extends StatelessWidget {
  final T value;
  final String title;
  final String subtitle;

  const _Choice({
    required this.value,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return RadioListTile<T>(
      contentPadding: EdgeInsets.zero,
      dense: true,
      value: value,
      title: Text(title),
      subtitle: Text(subtitle,
          style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
    );
  }
}
