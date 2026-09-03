// Улавяне на маркиран откъс от четивото — от селекция до [Quote].
//
// ## Защо позицията се ТЪРСИ, а не се пита Flutter
//
// `SelectionArea` дава маркирания ТЕКСТ (`SelectedContent.plainText`), но
// отместванията, които предлага, са спрямо ЦЯЛОТО си съдържание — тоест
// спрямо всички региони наведнъж, слети в един поток. А цитатът трябва да
// знае В КОЙ БЛОК е и на кой знак ВЪТРЕ в него, защото точно така се
// адресира ([QuoteAnchor]) и точно така се осветява после.
//
// ⚠ Превръщането „общо отместване → (блок, знак)" би трябвало да повтори
// наум как Flutter е слял регионите: кои са в реда, къде е сложил нов ред
// между тях, какво е направил с HTML таговете и с буквицата. Това е точно
// видът сметка, която в този проект се разминава тихо — виж целия раздел за
// позиционирането по ред в CLAUDE.md.
//
// Затова текстът се ТЪРСИ в блоковете — със същия [foldForMatch], който
// вече пази споделените линкове. Един механизъм, една проверка, едно място
// за поправка.

import 'quote_link.dart';
import 'quotes.dart';

/// Къде е намерен маркираният текст.
class CapturedSpot {
  /// Блокът, в който ЗАПОЧВА, и началният знак в него.
  final int block;
  final int charStart;

  /// Дължината в ПЪРВИЯ блок.
  final int charLength;

  /// Блокът, в който СВЪРШВА, и докъде стига в него.
  ///
  /// ⚠ Равни на [block]/[charStart]+[charLength] при цитат в един абзац.
  final int blockEnd;
  final int charEnd;

  const CapturedSpot(this.block, this.charStart, this.charLength,
      {int? blockEnd, int? charEnd})
      : blockEnd = blockEnd ?? block,
        charEnd = charEnd ?? (charStart + charLength);
}

/// Намира маркирания текст сред блоковете на четивото.
///
/// [blocks] е обикновеният текст на всеки блок, в реда на четене.
/// Връща `null`, ако текстът не се среща никъде — тогава цитатът просто не
/// се запазва (по-добре, отколкото да сочи наслуки).
///
/// ⚠ ЛИПСВА НАРОЧНО ПАДАНЕ КЪМ „първия горе-долу подходящ блок". Тук, за
/// разлика от отварянето на споделен линк, няма нищо за спасяване: човекът
/// стои пред текста и може да маркира наново.
/// [dropCapBlock] — индексът на блока, който се рисува с БУКВИЦА, или -1.
///
/// ⚠ ЗАЩО ИЗОБЩО ТРЯБВА ДА СЕ ЗНАЕ. Инициалът се рисува с отделен `Text`
/// вътре в `Stack` (виж drop_cap.dart) — тоест е ИЗВЪН текстовия поток.
/// Селекцията му не го хваща: маркира ли човек първото изречение, връща се
/// „вети Иоан Рилски…" без първата буква. (Докладвано от потребителя,
/// 02.09.2026: „не ти дава да маркираш първото изречение заради буквицата".)
///
/// Затова в този блок съвпадение, което започва на ВТОРИЯ знак, се разширява
/// назад до първия. Ограничено е точно до блока с буквицата — в обикновен
/// абзац човек може да маркира нарочно от втората буква и добавянето на
/// чужда буква отпред би било грешка.
CapturedSpot? captureSelection(List<String> blocks, String selected,
    {int dropCapBlock = -1}) {
  final want = foldForMatch(selected);
  if (want.isEmpty) return null;

  // ⚠ ПЪРВО в един блок — обичайният случай, и по-точен: там позицията се
  // мери точно, без да се гадае къде минават границите.
  final one = _captureInOneBlock(blocks, want, dropCapBlock);
  if (one != null) return one;

  // ⚠ ИНАК ПРЕЗ НЯКОЛКО БЛОКА. Слепваме всичко и търсим там; после
  // намереното се превежда обратно в (блок, знак). Без това всяка селекция,
  // пресякла граница на абзац, се отказваше — а тъкмо това е обичайното при
  // цитиране на разказ. (Искане на потребителя, 03.09.2026: „важно е да
  // можеш да маркираш в повече от един абзац и дори много абзаци без
  // ограничение".)
  return _captureAcrossBlocks(blocks, want);
}

/// Сгъва блок, като пази откъде идва всеки знак.
(String, List<int>) _fold(String raw) {
  final map = <int>[];
  final buf = StringBuffer();
  for (var j = 0; j < raw.length; j++) {
    final c = raw[j].toLowerCase();
    if (RegExp(r'[0-9a-zа-яёіѣѫ]').hasMatch(c)) {
      buf.write(c);
      map.add(j);
    }
  }
  return (buf.toString(), map);
}

CapturedSpot? _captureAcrossBlocks(List<String> blocks, String want) {
  // Сгънатият текст на всички блокове, наред, плюс за всеки сгънат знак —
  // в кой блок е и на кой суров знак вътре в него.
  final hay = StringBuffer();
  final ofBlock = <int>[];
  final ofChar = <int>[];
  for (var i = 0; i < blocks.length; i++) {
    final (f, map) = _fold(blocks[i]);
    hay.write(f);
    for (final c in map) {
      ofBlock.add(i);
      ofChar.add(c);
    }
  }
  final at = hay.toString().indexOf(want);
  if (at < 0) return null;

  final endIdx = at + want.length - 1;
  final b1 = ofBlock[at], b2 = ofBlock[endIdx];
  final c1 = ofChar[at], c2 = ofChar[endIdx] + 1;
  return CapturedSpot(
    b1,
    c1,
    // Дължината в ПЪРВИЯ блок — до края му, ако цитатът продължава нататък.
    b1 == b2 ? c2 - c1 : blocks[b1].length - c1,
    blockEnd: b2,
    charEnd: c2,
  );
}

CapturedSpot? _captureInOneBlock(
    List<String> blocks, String want, int dropCapBlock) {
  for (var i = 0; i < blocks.length; i++) {
    final raw = blocks[i];

    final (hay, map) = _fold(raw);
    final at = hay.indexOf(want);
    if (at < 0) continue;

    // ⚠ Дължината се мери В СУРОВИЯ текст, не в сгънатия: осветяването после
    // рисува върху суровия, а между първия и последния знак на цитата стоят
    // интервали и пунктуация, които сгъването е изхвърлило.
    var startRaw = map[at];
    final endRaw = map[at + want.length - 1] + 1;

    // ⚠ Буквицата — виж докстринга. Разширяваме назад САМО ако пред
    // намереното стои точно един знак и той е буква: тогава той е
    // инициалът, който селекцията не е могла да хване.
    if (i == dropCapBlock && at == 1 && startRaw >= 1) {
      final before = raw.substring(0, startRaw);
      if (RegExp(r'^\s*[^\s]\s*$').hasMatch(before)) startRaw = 0;
    }

    return CapturedSpot(i, startRaw, endRaw - startRaw);
  }
  return null;
}

/// Сглобява цитат от уловеното място.
///
/// ⚠ `text` се взима от СУРОВИЯ блок, а не от онова, което е върнала
/// селекцията: Flutter понякога добавя нови редове между вътрешните части и
/// маха меките пренасяния, а в цитата трябва да стои текстът както е в
/// четивото — той се показва в списъка и се праща в споделения линк.
Quote buildQuote({
  required QuoteSource source,
  required String locator,
  required String title,
  required List<String> blocks,
  required CapturedSpot spot,
}) {
  // ⚠ При цитат ПРЕЗ НЯКОЛКО АБЗАЦА текстът се сглобява от всички — с празен
  // ред помежду, както се чете на екрана.
  final parts = <String>[];
  for (var i = spot.block; i <= spot.blockEnd && i < blocks.length; i++) {
    final raw = blocks[i];
    final from = i == spot.block ? spot.charStart.clamp(0, raw.length) : 0;
    final to = i == spot.blockEnd
        ? spot.charEnd.clamp(0, raw.length)
        : raw.length;
    if (to > from) parts.add(raw.substring(from, to));
  }
  return Quote(
    anchor: QuoteAnchor(
      source: source,
      locator: locator,
      block: spot.block,
      charStart: spot.charStart,
      charLength: spot.charLength,
      blockEnd: spot.blockEnd,
      charEnd: spot.charEnd,
    ),
    text: parts.join('\n\n'),
    title: title,
    savedAtMs: DateTime.now().millisecondsSinceEpoch,
  );
}
