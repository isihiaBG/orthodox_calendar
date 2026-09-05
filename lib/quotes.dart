// Любими цитати — маркиран откъс от четиво, запазен и споделим.
//
// ## Защо адресирането изглежда така
//
// ⚠ ГЛАВНОТО РЕШЕНИЕ В ТОЗИ ФАЙЛ Е, ЧЕ ЦИТАТЪТ НОСИ И САМИЯ СИ ТЕКСТ.
//
// Изкушението е да се пази само „къде": четиво + абзац + знак. Точно това
// правят отметките ([BookPositionStore]) и там е достатъчно. Тук НЕ Е, по
// две причини наведнъж:
//
//   1. ⚠ ИНДЕКСЪТ НА ЗНАКА НЕ Е ИНВАРИАНТЕН СПРЯМО ТЕКСТА. Поправка в
//      превода размества всичко след себе си, а такива правим редовно
//      (виж `tools/corrections/` — 287 замени „служене"→„служение" в един
//      ден). За отметка това значи „скача с ред-два". За цитат значи, че
//      запазеният откъс сочи насред друго изречение.
//
//   2. ⚠ СПОДЕЛЕНИЯТ ЛИНК ЖИВЕЕ НА ЧУЖД ТЕЛЕФОН, с друга версия на базата.
//      Там разминаването не е „ред-два" — може да е цял абзац. И получателят
//      НЯМА КАК ДА РАЗБЕРЕ, че вижда сгрешен пасаж: текстът е смислен, само
//      не е този, който му пратили.
//
// Затова числата са ПОДСКАЗКА ОТКЪДЕ ДА ЗАПОЧНЕ ТЪРСЕНЕТО, а намирането е по
// съдържание — виж [QuoteAnchor.locate]. Открие ли се текстът на 200 знака
// встрани, цитатът е там; не се ли открие изобщо, отваря се посоченият абзац
// и толкова.
//
// ## Форматът е ЗАМРАЗЕН след първия споделен линк
//
// ⚠ Щом един линк тръгне по Viber, форматът му вече не се сменя — чуждият
// телефон ще получи адрес, който новата версия не разбира. Затова [kVersion]
// стои в самия адрес: разчитането може да поддържа стари версии, но само ако
// знае коя чете.

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Версия на формата за адресиране. Влиза в споделения линк като `v`.
///
/// ⚠ Увеличава се САМО когато старите линкове трябва да продължат да работят
/// по стария начин. Промяна без нова версия чупи вече споделеното.
const int kQuoteLinkVersion = 2;

/// ⚠ ВЕРСИЯ 2 (05.09.2026) добави ЧЕТИРИ неща наведнъж, всяко от които е
/// поправка на реален пропуск:
///
///   1. `blockEnd`/`charEnd` — дотук ги нямаше в адреса ИЗОБЩО, тъй че всеки
///      споделен цитат през няколко абзаца пристигаше отрязан до първия.
///   2. Отпечатъкът пътува като СВОЕ поле, вместо да се извежда от текста.
///      Без това скъсяването на текста (виж [kLinkTextChars]) би убило
///      мълчаливо цялата устойчивост.
///   3. [QuoteAnchor.occurrence] — кое поред съвпадение е маркираното.
///   4. [QuoteAnchor.occurrenceTotal] — колко са били общо, за да се познае
///      дали текстът се е променил, откакто линкът е тръгнал.
///
/// ⚠ Версия 1 продължава да се чете (виж `parseQuoteLink`): вече споделени
/// адреси не бива да спират да работят.

/// Домейнът, който потвърждава приложението за App Links.
///
/// ⚠ Трябва да съвпада с `android:host` в AndroidManifest.xml И с хоста, на
/// който стои `.well-known/assetlinks.json` (в КОРЕНА му, не в подпапка).
/// Виж CLAUDE.md, „Споделяне на цитати навън".
const String kQuoteLinkHost = 'isihiabg.github.io';

/// Откъде идва цитатът. Трите четеца адресират по различен начин, тъй че
/// видът решава как се разчита [QuoteAnchor.locator].
enum QuoteSource {
  /// Житие от `lives.db`. `locator` = слъгът.
  life,

  /// Четиво от том на „Месецослов". `locator` = „път до тома|href на главата".
  book,

  /// Библия. `locator` = „език|код на книгата|глава".
  bible,
}

/// Къде се намира цитатът — и достатъчно от него, за да бъде намерен наново.
class QuoteAnchor {
  final QuoteSource source;

  /// Адресът на самото четиво. Смисълът зависи от [source] — виж enum-а.
  final String locator;

  /// Индекс на абзаца/региона, В КОЙТО ЗАПОЧВА цитатът.
  ///
  /// ⚠⚠ ПРИ [QuoteSource.bible] ЗНАЧИ ДРУГО — НОМЕРА НА ПЪРВИЯ СТИХ, а
  /// [blockEnd] е номерът на последния. Съответно [charStart] е колко знака
  /// се отрязват от НАЧАЛОТО на първия стих, а [charEnd] — колко от КРАЯ на
  /// последния; [charLength] не се ползва.
  ///
  /// Не е трик, а следствие от устройството на Писанието: там единицата не е
  /// „абзац номер N на екрана" (той зависи от избраната двойка преводи), а
  /// стихът — чийто номер не се мени НИКОГА. Оттам и четимият адрес
  /// „Mt.2:3-5(9;15)@bg" (виж [buildBibleQuoteLink]), и това, че цитат от
  /// Библията изобщо няма нужда от отпечатък и пореден номер.
  final int block;

  /// Начален знак в [block].
  final int charStart;

  /// Дължина В ПЪРВИЯ блок — колко знака от него влизат.
  final int charLength;

  /// Индекс на абзаца, В КОЙТО СВЪРШВА цитатът, и докъде стига в него.
  ///
  /// ⚠ ЦИТАТ ПРЕЗ НЯКОЛКО АБЗАЦА (03.09.2026, по искане на потребителя:
  /// „важно е да можеш да маркираш в повече от един абзац и дори много
  /// абзаци без ограничение").
  ///
  /// Първата версия държеше само (блок, знак, дължина) и отказваше всяка
  /// селекция, пресякла граница на абзац — а това е обичайното при цитиране
  /// на разказ. Сега краят е изричен: `blockEnd` е същият като [block] при
  /// цитат в един абзац, и по-голям при цитат през няколко.
  ///
  /// ⚠ Междинните абзаци НЕ се изброяват — те влизат ЦЕЛИ по определение.
  final int blockEnd;
  final int charEnd;

  /// Кое ПОРЕД съвпадение на този откъс е цитатът — брои се в цялото четиво,
  /// от 1. Нула значи „неизвестно" (стар запис или линк от версия 1).
  ///
  /// ⚠⚠ ЗАЩО НЕ СТИГАТ КООРДИНАТИТЕ. Стигат, докато текстът не се промени —
  /// а той се мени редовно (всяко пускане на конвейера пренаписва `life`).
  /// Тогава числата се разместват, а поредният номер оцелява: „единайсетата
  /// «година» в житието" остава единайсета и след като абзац пред нея е
  /// пренаписан.
  ///
  /// ⚠ И ОБРАТНОТО Е ВЯРНО, затова двете вървят ЗАЕДНО: вмъкне ли се нова
  /// „година" преди нашата, номерът се разминава, а координатите — не чак
  /// толкова. Кое от двете печели решава [occurrenceTotal].
  ///
  /// (Поискано от потребителя, 05.09.2026: „аз експериментирах с маркиране
  /// на «година» дълбоко в текста… 11/15 съвпадение".)
  final int occurrence;

  /// Колко съвпадения е имало ОБЩО, когато цитатът е бил запазен.
  ///
  /// ⚠ Служи за ЕДНО-ЕДИНСТВЕНО нещо: да се познае дали текстът още е онзи.
  /// Съвпадне ли броят, [occurrence] е меродавен; не съвпадне ли, значи
  /// текстът е пренаписан и се пада обратно на „най-близкото до
  /// координатите" — старото, изпитано правило.
  final int occurrenceTotal;

  const QuoteAnchor({
    required this.source,
    required this.locator,
    required this.block,
    required this.charStart,
    required this.charLength,
    int? blockEnd,
    int? charEnd,
    this.occurrence = 0,
    this.occurrenceTotal = 0,
  })  : blockEnd = blockEnd ?? block,
        charEnd = charEnd ?? (charStart + charLength);

  /// Обхваща ли цитатът повече от един абзац.
  bool get spansBlocks => blockEnd > block;

  Map<String, dynamic> toJson() => {
        's': source.name,
        'l': locator,
        'b': block,
        'c': charStart,
        'n': charLength,
        // ⚠ Пишат се САМО при цитат през няколко абзаца — иначе се извеждат.
        // Така старите записи се четат без промяна.
        if (blockEnd != block) 'be': blockEnd,
        if (blockEnd != block) 'ce': charEnd,
        // ⚠ Само когато ги знаем — иначе старите записи биха се сдобили с
        // нула, която после изглежда като истинска стойност.
        if (occurrence > 0) 'o': occurrence,
        if (occurrenceTotal > 0) 'ot': occurrenceTotal,
      };

  static QuoteAnchor fromJson(Map<String, dynamic> j) => QuoteAnchor(
        source: QuoteSource.values.firstWhere(
          (e) => e.name == j['s'],
          orElse: () => QuoteSource.life,
        ),
        locator: j['l'] as String? ?? '',
        block: (j['b'] as num?)?.toInt() ?? 0,
        charStart: (j['c'] as num?)?.toInt() ?? 0,
        charLength: (j['n'] as num?)?.toInt() ?? 0,
        blockEnd: (j['be'] as num?)?.toInt(),
        charEnd: (j['ce'] as num?)?.toInt(),
        occurrence: (j['o'] as num?)?.toInt() ?? 0,
        occurrenceTotal: (j['ot'] as num?)?.toInt() ?? 0,
      );
}

/// Запазен цитат.
class Quote {
  final QuoteAnchor anchor;

  /// САМИЯТ откъс. Пази се дословно — той е и това, което се показва в
  /// списъка, и това, по което цитатът се намира наново.
  final String text;

  /// Заглавието на четивото, за да се чете списъкът без отваряне.
  final String title;

  final int savedAtMs;

  const Quote({
    required this.anchor,
    required this.text,
    required this.title,
    required this.savedAtMs,
  });

  /// Устойчив ключ — по МЯСТОТО, не по времето на запазване.
  ///
  /// ⚠ Нарочно НЕ включва `savedAtMs`: така повторното маркиране на същия
  /// откъс не прави втори запис, а изместване с няколко знака (човек влачи
  /// пръст) не се брои за същия цитат.
  String get id => '${anchor.source.name}|${anchor.locator}'
      '|${anchor.block}|${anchor.charStart}';

  Map<String, dynamic> toJson() => {
        'a': anchor.toJson(),
        't': text,
        'ti': title,
        'ms': savedAtMs,
      };

  static Quote fromJson(Map<String, dynamic> j) => Quote(
        anchor: QuoteAnchor.fromJson(
            (j['a'] as Map).cast<String, dynamic>()),
        text: j['t'] as String? ?? '',
        title: j['ti'] as String? ?? '',
        savedAtMs: (j['ms'] as num?)?.toInt() ?? 0,
      );
}

/// Съхранението — един ключ в SharedPreferences, JSON списък.
///
/// ⚠ По същия довод като при [BibleScopePresets]: записите са малко (никой
/// няма да маркира хиляди), а един ключ значи един прочит и един запис — без
/// индекс и без сираци, ако запис се провали по средата.
class QuotesStore {
  static const _key = 'favourite_quotes';

  static Future<List<Quote>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw) as List;
      return [
        for (final e in list) Quote.fromJson((e as Map).cast<String, dynamic>())
      ];
    } catch (_) {
      // ⚠ Повреден запис НЕ се трие — връща се празен списък, а редът остава
      // на диска. Ако утре форматът се разчете, нищо не е загубено; човек и
      // без това не може да поправи JSON от телефона си. (Същото правило
      // като при запазените селекции книги.)
      return const [];
    }
  }

  static Future<void> _save(List<Quote> quotes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _key, jsonEncode([for (final q in quotes) q.toJson()]));
  }

  static Future<void> add(Quote q) async {
    final all = [...await load()];
    all.removeWhere((x) => x.id == q.id);
    all.add(q);
    await _save(all);
  }

  static Future<void> remove(String id) async {
    final all = await load();
    await _save([for (final q in all) if (q.id != id) q]);
  }

  static Future<bool> contains(String id) async =>
      (await load()).any((q) => q.id == id);
}
