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

  /// Кое поред съвпадение е това и колко са били общо — виж
  /// [QuoteAnchor.occurrence]. Нула значи „не се брои" (твърде къс откъс).
  final int occurrence;
  final int occurrenceTotal;

  const CapturedSpot(this.block, this.charStart, this.charLength,
      {int? blockEnd, int? charEnd, this.occurrence = 0, this.occurrenceTotal = 0})
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
    {int dropCapBlock = -1, (int, int)? hint}) {
  final want = foldForMatch(selected);
  if (want.isEmpty) return null;

  // ⚠⚠ ЕДНО ТЪРСЕНЕ ПРЕЗ ЦЯЛОТО ЧЕТИВО, не блок по блок. Дотук се пробваше
  // първо „в един блок" и се връщаше ПЪРВИЯТ блок, който съдържа текста — а
  // това е точно докладваният бъг: маркираш „година" дълбоко в житието на
  // св. Кирил Философ (единайсетото от петнайсет срещания), а се запазва
  // първото горе. Оттам нататък всичко е последователно сгрешено — и
  // линкът, и осветяването. (Докладвано от потребителя, 05.09.2026.)
  final f = foldBlocks(blocks);
  if (f.text.isEmpty) return null;

  final all = <int>[];
  for (var i = f.text.indexOf(want); i >= 0; i = f.text.indexOf(want, i + 1)) {
    all.add(i);
  }
  if (all.isEmpty) return null;

  final at = _pick(all, want, f, hint);

  // ⚠ ПОРЕДНИЯТ НОМЕР СЕ БРОИ ПО ПРОЗОРЕЦА НА ОТПЕЧАТЪКА, а не по целия
  // откъс — защото отварянето брои точно него (в линка пътува хеш, не
  // текст). Дълъг цитат се разпознава по първите си шестнайсет сгънати
  // знака, тъй че съвпаденията му може да са повече от съвпаденията на
  // целия откъс; двете страни трябва да гледат едно и също нещо.
  final (fp, window) = quoteFingerprint(selected);
  var occurrence = 0;
  var total = 0;
  if (fp.isNotEmpty) {
    final m = fingerprintMatches(f.text, fp, window);
    final k = m.indexOf(at);
    if (k >= 0) {
      occurrence = k + 1;
      total = m.length;
    }
  }

  final endIdx = at + want.length - 1;
  final b1 = f.ofBlock[at], b2 = f.ofBlock[endIdx];
  var c1 = f.ofChar[at];
  final c2 = f.ofChar[endIdx] + 1;

  // ⚠ Буквицата — виж докстринга. Разширяваме назад САМО ако намереното
  // започва на ВТОРИЯ сгънат знак на блока с инициала и пред него стои точно
  // един знак, който е буква: тогава той е инициалът, който селекцията не е
  // могла да хване.
  if (b1 == dropCapBlock && at == f.blockStart[b1] + 1 && c1 >= 1) {
    final before = blocks[b1].substring(0, c1);
    if (RegExp(r'^\s*[^\s]\s*$').hasMatch(before)) c1 = 0;
  }

  return CapturedSpot(
    b1,
    c1,
    // Дължината в ПЪРВИЯ блок — до края му, ако цитатът продължава нататък.
    b1 == b2 ? c2 - c1 : blocks[b1].length - c1,
    blockEnd: b2,
    charEnd: c2,
    occurrence: occurrence,
    occurrenceTotal: total,
  );
}

/// Кое от намерените съвпадения е маркираното.
///
/// ⚠ С ОРИЕНТИР — най-близкото до него. Селекцията е НА ЕКРАНА, тъй че
/// ориентирът (средата на самата селекция, преведена в „блок и знак") сочи
/// право в нея; за къс откъс двете съвпадат на знак.
///
/// ⚠ БЕЗ ОРИЕНТИР — първото, което се побира ЦЯЛО в един блок, и чак после
/// първото изобщо. Това възпроизвежда старото поведение дословно: то също
/// пробваше „в един блок" преди „през блокове". Пази и от рядкото
/// съвпадение, залепено на границата между два абзаца, каквото никой не е
/// маркирал.
int _pick(List<int> all, String want, FoldedBlocks f, (int, int)? hint) {
  if (hint != null) {
    final h = f.foldedIndexOf(hint.$1, hint.$2);
    var best = all.first;
    for (final a in all) {
      if ((a - h).abs() < (best - h).abs()) best = a;
    }
    return best;
  }
  for (final a in all) {
    if (f.ofBlock[a] == f.ofBlock[a + want.length - 1]) return a;
  }
  return all.first;
}

/// Сглобява цитат от уловеното място.
///
/// ⚠ `text` се взима от СУРОВИЯ блок, а не от онова, което е върнала
/// селекцията: Flutter понякога добавя нови редове между вътрешните части и
/// маха меките пренасяния, а в цитата трябва да стои текстът както е в
/// четивото — той се показва в списъка и се праща в споделения линк.
/// [anchor] замества извеждания адрес — за четива, чиито числа значат друго.
///
/// ⚠ Ползва се САМО от Библията: там „блок" е номер на СТИХ, а не индекс на
/// абзац, и отрязването се брои от краищата на стиха. Виж [QuoteAnchor.block]
/// и [buildBibleQuoteLink]. Текстът и тук се взима от блоковете по обичайния
/// начин — различава се адресирането, не съдържанието.
Quote buildQuote({
  required QuoteSource source,
  required String locator,
  required String title,
  required List<String> blocks,
  required CapturedSpot spot,
  QuoteAnchor? anchor,
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
    anchor: anchor ??
        QuoteAnchor(
          source: source,
          locator: locator,
          block: spot.block,
          charStart: spot.charStart,
          charLength: spot.charLength,
          blockEnd: spot.blockEnd,
          charEnd: spot.charEnd,
          occurrence: spot.occurrence,
          occurrenceTotal: spot.occurrenceTotal,
        ),
    text: parts.join('\n\n'),
    title: title,
    savedAtMs: DateTime.now().millisecondsSinceEpoch,
  );
}

/// Уловеното (ред, знак) → адрес по СТИХ и отрязване, за Писанието.
///
/// ⚠⚠ ТУК СЕ ЗАТВАРЯ КРЪГЪТ С [buildBibleQuoteLink]. Улавянето работи с
/// редове на екрана, а Писанието се адресира със стихове — номера, който не
/// се мени никога. Отрязването отзад се смята като „дължината на последния
/// стих минус докъде стига цитатът", тъй че се прави ТУК, където текстът е
/// под ръка, а не при сглобяването на адреса, където го няма.
///
/// [verses] са номерата на редовете, по реда на показване — текст, а не
/// число, защото надписанието на псалом е „0".
///
/// ⚠ Чиста функция нарочно: това е единственото място, където се превежда
/// между двете адресирания, и трябва да може да се провери без екран.
QuoteAnchor bibleAnchorFromSpot({
  required CapturedSpot spot,
  required List<String> blocks,
  required List<String> verses,
  required String lang,
  required String book,
  required int chapter,
}) {
  int verseAt(int row) =>
      row >= 0 && row < verses.length ? (int.tryParse(verses[row]) ?? 0) : 0;
  final lastLen =
      spot.blockEnd >= 0 && spot.blockEnd < blocks.length
          ? blocks[spot.blockEnd].length
          : 0;
  final firstLen =
      spot.block >= 0 && spot.block < blocks.length ? blocks[spot.block].length : 0;

  // ⚠⚠ ОПАШКА САМО ОТ ПУНКТУАЦИЯ СЕ БРОИ ЗА НУЛА. Сгъването изхвърля
  // точката, тъй че маркиран ЦЯЛ стих свършва на последната БУКВА и
  // отрязването отзад излизаше 1 — а линкът, вместо чистото „Mt.2:4",
  // се пишеше „Mt.2:4(0;1)". Същото важи и отпред, за откриваща кавичка.
  //
  // ⚠ Правилото е ТУК, а не в общото улавяне: там разширяването би добавило
  // към цитата знак, който човекът не е маркирал, и то във всички четива.
  // Тук цената е само един препинателен знак повече в осветеното, а
  // печалбата е адрес, който се чете.
  final tail = lastLen - spot.charEnd;
  final trimEnd = _noLetters(blocks, spot.blockEnd, spot.charEnd, lastLen)
      ? 0
      : (tail < 0 ? 0 : (tail > lastLen ? lastLen : tail));
  final head = spot.charStart < 0 ? 0 : spot.charStart;
  final trimStart =
      _noLetters(blocks, spot.block, 0, head) ? 0 : (head > firstLen ? firstLen : head);

  return QuoteAnchor(
    source: QuoteSource.bible,
    locator: '$lang|$book|$chapter',
    block: verseAt(spot.block),
    charStart: trimStart,
    charLength: 0,
    blockEnd: verseAt(spot.blockEnd),
    charEnd: trimEnd,
  );
}

/// Има ли БУКВА или ЦИФРА в [from]..[to) на блока [block].
bool _noLetters(List<String> blocks, int block, int from, int to) {
  if (block < 0 || block >= blocks.length) return true;
  final raw = blocks[block];
  for (var i = from < 0 ? 0 : from; i < to && i < raw.length; i++) {
    if (kWordChar.hasMatch(raw[i].toLowerCase())) return false;
  }
  return true;
}
