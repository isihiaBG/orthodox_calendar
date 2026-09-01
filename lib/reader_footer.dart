// reader_footer.dart
//
// Опашката под четивото в „Месецослов": кръгли бутони със стрелки и
// табелки към тях.
//
// Живее ВЪТРЕ в скрола, а не като постоянна лента отдолу. Това е цялата
// идея: докато човек чете, тя не отнема нищо от екрана, а заглавната
// страница се вижда цяла — може дори да се скролне толкова, че горната
// лента да се скрие, и опашката все още да не се е показала. Появява се
// чак когато той потърси какво има по-нататък.
//
// (Дотогава същата работа вършеше постоянна долна лента — _navBar в
// book_reader.dart, изключена на 12.08.2026 с бележка „яде ред от текста"
// и оставена до решаването на прехода между главите. Опашката я замества.)
//
// Две подредби, едно устройство:
//
//   заглавна страница   [        ] [ към първото четиво ] [ > ]
//   житие               [ < ] предишно ......... следващо [ > ]
//
// ⚠ Левият слот се пази ДОРИ когато е празен (на заглавната). Иначе
// централният текст застава по средата на цялата ширина и се разминава с
// подредбата на житията, където отляво има бутон.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Един източник в опашката: пояснение + име на сайта, което е връзката.
///
/// ⚠ Двете са разделени нарочно. Подчертава се САМО [name]; [prefix] е
/// пояснение („за съвременния български:") и не води наникъде — подчертано,
/// то би обещавало връзка, каквато няма.
class FooterSource {
  /// Пояснение пред името. Може да е празно.
  final String prefix;

  /// Името на източника — то е връзката.
  final String name;

  /// Отваря адреса. Обикновено през `openExternal`, тъй че човек вижда
  /// къде отива, преди да излезе навън.
  final VoidCallback? onTap;

  const FooterSource({required this.name, this.prefix = '', this.onTap});
}

/// Размерът на бутоните в опашката.
///
/// ⚠ Нарочно по-голям от [RoundIconButton]'s 26 в лентите с инструменти:
/// тези тук се натискат с палец насред четене, а не се целят внимателно
/// в лента. 44 е и обичайният минимум за цел на докосване.
const double kFooterButtonSize = 44;

/// Шрифтът на табелките. СИСТЕМНИЯТ, не Charis SIL — надписите не са част
/// от четивото и трябва да се четат като друг глас. Затова и размерът е
/// нормален, а не дребен: те са за натискане, не за четене под линия.
const double kFooterLabelSize = 16;

/// Въздухът между края на текста (или източника) и опашката.
///
/// ⚠ Голям НАРОЧНО, и то двойно повече, отколкото изглежда нужно. Сбие ли
/// се с абзаците, окото чете опашката като част от житието; тук се иска
/// обратното — тя да е отделно нещо. Затова няма и черта: разделя
/// разстоянието, не линия.
///
/// ⚠ Числото има и втора работа, заради която не бива да се смалява. На
/// заглавната страница то е празнината между дъното на екрана и бутоните:
/// докато е по-голямо от височината на горната лента (44), човек може да
/// плъзне точно толкова, че лентата да се скрие, и заглавната да застане
/// сама на екрана — без лента отгоре и без бутони отдолу.
const double kFooterTopGap = 112;
const double kFooterBottomGap = 40;

/// Въздухът между края на текста и реда с ИЗТОЧНИКА, когато го има.
///
/// ⚠ Чувствително по-малък от [kFooterTopGap] нарочно. Източникът
/// принадлежи на четивото — той казва откъде е самият текст — тъй че
/// стои близо до него; опашката с бутоните е навигация и си остава
/// отделена от двете с голямата празнина.
const double kFooterSourceTopGap = 44;

/// Един край на опашката: стрелка и надпис към нея.
class FooterAction {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const FooterAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });
}

class ReaderFooter extends StatelessWidget {
  /// Лявата стрелка („предишно"). null = няма накъде наляво.
  final FooterAction? left;

  /// Дясната стрелка („следващо"). null = няма накъде надясно.
  final FooterAction? right;

  /// Текст по средата — ползва се на заглавната страница („към първото
  /// четиво" / „продължете от последно отваряното четиво"). Може да е на
  /// два реда и си остава центриран спрямо бутоните.
  final String? centerLabel;

  /// Какво прави тапът върху централния текст. Обикновено същото като
  /// [right] — надписът и стрелката са едно действие.
  final VoidCallback? onCenterTap;

  /// Ред с ИЗТОЧНИКА на четивото, над бутоните. null = няма такъв ред.
  ///
  /// Ползва се в четеца на Библията, където всяка глава има свой адрес в
  /// azbyka.ru. Стои ТУК, а не в текста, защото не е част от Писанието —
  /// казва откъде е то.
  final String? sourceLabel;

  /// Какво прави тапът върху реда с източника. Обикновено отваря навън
  /// през `openExternal`, тъй че човек вижда адреса, преди да излезе.
  final VoidCallback? onSourceTap;

  /// НЯКОЛКО източника, всеки със свое пояснение и своя връзка.
  ///
  /// Поводът е Библията: съвременният български текст идва от едно място, а
  /// всички останали преводи — от друго. Един ред не може да го каже честно,
  /// а и двата адреса трябва да се отварят поотделно.
  ///
  /// ⚠ Има ли [sources], [sourceLabel] се пренебрегва. Двете не се смесват:
  /// или един източник с един ред, или списък с пояснения.
  final List<FooterSource>? sources;

  /// Цветът на бутоните и надписите.
  ///
  /// ⚠ Идва ОТВЪН, от палитрата на четеца (`palette.dim`), а не от
  /// [AppColors]. Първо стоеше закован `textSecondary` — полупрозрачно
  /// бяло, което в тъмна тема изглежда добре, а в СВЕТЛА се слива с
  /// кремавия фон и опашката изчезва. Палитрата знае в коя тема сме:
  /// #9A948A в тъмна, #6B675F в светла.
  final Color color;

  const ReaderFooter({
    super.key,
    required this.color,
    this.left,
    this.right,
    this.centerLabel,
    this.onCenterTap,
    this.sourceLabel,
    this.onSourceTap,
    this.sources,
  });

  @override
  Widget build(BuildContext context) {
    final row = Row(
      // Централно по вертикала: надпис на два реда остава центриран
      // спрямо кръгчетата, вместо да ги избутва нагоре.
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Левият край. SizedBox, а не нищо — държи мястото, когато го
        // няма (виж бележката най-горе).
        SizedBox(
          width: kFooterButtonSize,
          child: left == null ? null : _button(left!),
        ),
        if (left != null) ...[
          const SizedBox(width: 10),
          _label(left!.label, left!.onTap),
        ],
        Expanded(
          child: centerLabel == null
              ? const SizedBox.shrink()
              : Center(
                  child: _label(
                    centerLabel!,
                    onCenterTap,
                    align: TextAlign.center,
                  ),
                ),
        ),
        if (right != null) ...[
          _label(right!.label, right!.onTap, align: TextAlign.right),
          const SizedBox(width: 10),
        ],
        SizedBox(
          width: kFooterButtonSize,
          child: right == null ? null : _button(right!),
        ),
      ],
    );

    return Padding(
      // Има ли източник, горният въздух се дели на две: малкият остава над
      // него, а голямият слиза между него и бутоните — вижте
      // [kFooterSourceTopGap]. Без източник всичко е както преди.
      padding: EdgeInsets.fromLTRB(
        16,
        hasSource ? kFooterSourceTopGap : kFooterTopGap,
        16,
        kFooterBottomGap,
      ),
      child: !hasSource
          ? row
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (sources != null && sources!.isNotEmpty)
                  _sourceList(sources!)
                else
                  _source(sourceLabel!),
                const SizedBox(height: kFooterTopGap),
                row,
              ],
            ),
    );
  }

  /// Има ли изобщо ред с източник — по единия или по другия път.
  bool get hasSource =>
      (sources != null && sources!.isNotEmpty) || sourceLabel != null;

  /// Блокът с няколко източника: заглавен ред и по един ред на всеки.
  ///
  /// ⚠ Подчертано е САМО името на сайта, не и поясненията пред него.
  /// Пояснението („за съвременния български:") не води наникъде; подчертано,
  /// то би обещавало връзка, каквато няма. Затова редът е `RichText` с два
  /// спана, а не един `Text` с общ жест.
  Widget _sourceList(List<FooterSource> items) => Column(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      Text(
        items.length == 1 ? 'Източник:' : 'Източници:',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: kFooterLabelSize - 2,
          color: color,
          height: 1.5,
        ),
      ),
      for (final item in items)
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: RichText(
            textAlign: TextAlign.center,
            text: TextSpan(
              style: TextStyle(
                fontSize: kFooterLabelSize - 2,
                color: color,
                height: 1.35,
              ),
              children: [
                if (item.prefix.isNotEmpty) TextSpan(text: '${item.prefix} '),
                TextSpan(
                  text: item.name,
                  style: TextStyle(
                    decoration: TextDecoration.underline,
                    decorationColor: color,
                  ),
                  recognizer: item.onTap == null
                      ? null
                      : (TapGestureRecognizer()..onTap = item.onTap),
                ),
              ],
            ),
          ),
        ),
    ],
  );

  /// Редът с източника: центриран, с една степен по-дребен от табелките и
  /// подчертан, за да се чете като връзка навън, а не като бутон.
  Widget _source(String text) => GestureDetector(
    onTap: onSourceTap,
    behavior: HitTestBehavior.opaque,
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: kFooterLabelSize - 2,
        color: color,
        height: 1.3,
        decoration: TextDecoration.underline,
        decorationColor: color,
      ),
    ),
  );

  Widget _button(FooterAction a) =>
      _FooterButton(icon: a.icon, onTap: a.onTap, color: color);

  Widget _label(
    String text,
    VoidCallback? onTap, {
    TextAlign align = TextAlign.left,
  }) => GestureDetector(
    onTap: onTap,
    behavior: HitTestBehavior.opaque,
    child: Text(
      text,
      textAlign: align,
      style: TextStyle(
        // Без fontFamily → системният шрифт на телефона.
        fontSize: kFooterLabelSize,
        color: color,
        height: 1.25,
      ),
    ),
  );
}

/// Кръгчето със стрелка. Различава се от [RoundIconButton] по размера и по
/// това, че тук няма tooltip — надписът до него казва същото.
class _FooterButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final Color color;

  const _FooterButton({
    required this.icon,
    required this.onTap,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: kFooterButtonSize,
        height: kFooterButtonSize,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: color, width: 1.4),
        ),
        child: Icon(icon, size: kFooterButtonSize * 0.62, color: color),
      ),
    );
  }
}
