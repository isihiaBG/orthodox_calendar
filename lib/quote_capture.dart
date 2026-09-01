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
  /// Индекс на блока (региона) в четивото.
  final int block;

  /// Начален знак в СУРОВИЯ текст на блока и дължина.
  final int charStart;
  final int charLength;

  const CapturedSpot(this.block, this.charStart, this.charLength);
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
CapturedSpot? captureSelection(List<String> blocks, String selected) {
  final want = foldForMatch(selected);
  if (want.isEmpty) return null;

  for (var i = 0; i < blocks.length; i++) {
    final raw = blocks[i];

    // Сгъваме блока, като помним откъде идва всеки знак.
    final map = <int>[];
    final buf = StringBuffer();
    for (var j = 0; j < raw.length; j++) {
      final c = raw[j].toLowerCase();
      if (RegExp(r'[0-9a-zа-яёіѣѫ]').hasMatch(c)) {
        buf.write(c);
        map.add(j);
      }
    }
    final hay = buf.toString();
    final at = hay.indexOf(want);
    if (at < 0) continue;

    // ⚠ Дължината се мери В СУРОВИЯ текст, не в сгънатия: осветяването после
    // рисува върху суровия, а между първия и последния знак на цитата стоят
    // интервали и пунктуация, които сгъването е изхвърлило.
    final startRaw = map[at];
    final endRaw = map[at + want.length - 1] + 1;
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
  final raw = blocks[spot.block];
  final end = (spot.charStart + spot.charLength).clamp(0, raw.length);
  return Quote(
    anchor: QuoteAnchor(
      source: source,
      locator: locator,
      block: spot.block,
      charStart: spot.charStart,
      charLength: spot.charLength,
    ),
    text: raw.substring(spot.charStart.clamp(0, raw.length), end),
    title: title,
    savedAtMs: DateTime.now().millisecondsSinceEpoch,
  );
}
