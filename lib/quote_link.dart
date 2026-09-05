// Споделеният линк към цитат — сглобяване и разчитане.
//
// Форматът е:
//
//     https://isihiabg.github.io/q?v=1&s=life&l=sv-ioan-rilski&b=12&c=340&n=180
//                                  &t=Poneze+cslovek+e+sazdaden
//
// ⚠ ЗАЩО `t` (отпечатъкът) НЕ Е ИЗЛИШЕН — виж докстринга на `quotes.dart`.
// Накратко: числата се разместват при всяка поправка в превода, а линкът
// живее на ЧУЖД телефон с друга версия на базата. Без отпечатък получателят
// отваря друг пасаж и няма как да разбере.
//
// ⚠ ОТПЕЧАТЪКЪТ Е СВЕДЕН, не дословен ([fingerprint]). Причини три:
//   1. дължина на адреса — цял цитат в URL е нечетимо и се чупи при
//      пренасяне в чатовете;
//   2. устойчивост — точно поправките, срещу които се пазим, менят
//      пунктуация и главни букви;
//   3. кирилицата в URL се процентно кодира по три байта на буква, тъй че
//      сведеният вид е и чувствително по-къс.
//
// ⚠ ЛИНКЪТ Е ЕДНОПОСОЧЕН КЪМ БЪДЕЩЕТО. Щом един тръгне по Viber, форматът
// му вече не се сменя — затова `v=1` стои вътре още от първия.

import 'dart:convert';
import 'dart:io';

import 'bible_ref.dart';
import 'quotes.dart';

/// Пътят, по който Android разпознава линка.
///
/// ⚠ Трябва да съвпада с `android:pathPrefix` в AndroidManifest.xml.
///
/// ⚠ Носи ИМЕТО НА ПРИЛОЖЕНИЕТО нарочно (03.09.2026, по искане на
/// потребителя): пакетираният адрес е непрозрачен и без това човек не вижда
/// никаква връзка с календара — а линк, който пристига в чат, се преценява
/// точно по вида си. `/orthodox_calendar/q/…` поне казва откъде идва.
///
/// ⚠ Това НЕ мени къде стои `assetlinks.json` — той остава в КОРЕНА на
/// домейна и важи за целия хост, независимо от пътя на линка.
const String kQuotePath = '/orthodox_calendar/q';

/// Колко СГЪНАТИ знака се хешват за отпечатъка.
///
/// ⚠ ФИКСИРАНО ЧИСЛО, не „колкото има". Хешът се проверява чрез плъзгащ
/// прозорец ([locateQuote]) и дължината му трябва да е известна и от двете
/// страни — при сглобяването на линка и при отварянето му. Изведена от
/// цитата, тя не може да се възстанови: в линка стои СУРОВАТА дължина, а
/// сгъването маха интервалите и пунктуацията.
///
/// 16 сгънати знака са около три думи. Първият опит беше 24 (≈пет думи) и
/// излезе висок: цитат като „оставил всичко земно" остава под него и губи
/// проверката. Шестнайсет знака български текст са достатъчно уникални —
/// при 32-битов хеш случайно съвпадение в един абзац е практически
/// невъзможно, а покритието е чувствително по-широко.
const int kFingerprintChars = 16;

/// ⚠ ПОД ТОЛКОВА ЗНАКА ОТПЕЧАТЪКЪТ НЕ СЕ ПОЛЗВА ИЗОБЩО.
///
/// Доводът е на потребителя (02.09.2026) и е решаващ: сподели ли човек една
/// буква „а", отпечатъкът „а" не различава нищо — в абзаца има стотици. Но
/// по-лошото не е, че не помага, а че може да НАВРЕДИ: при редактиран текст
/// търсенето ще предпочете най-близката „а" (примерно на 2 знака), докато
/// истинската е на 26 — и ще отведе по-далеч от мястото, отколкото чистите
/// координати.
///
/// Затова кратките цитати вървят САМО по координати. Границата е 12 сгънати
/// знака — под нея съвпадението е практически безсмислено (две-три думи в
/// българския текст дават 12+), над нея вероятността за случайно повторение
/// в същия абзац пада рязко.
const int kMinFingerprintChars = 12;

/// Колко надалеч се търси текстът около посочения индекс.
///
/// ⚠ 400 знака покриват с широк запас обичайното разместване от поправка в
/// превода (замяна на дума мести с единици знаци, не със стотици). По-голям
/// прозорец би започнал да намира ЧУЖДИ съвпадения на честа фраза.
const int kSearchWindow = 400;

/// Свежда текст до сравним вид: малки букви, само букви и цифри.
///
/// ⚠ Пунктуацията и главните букви отпадат нарочно — точно те се менят при
/// редакция („Богомайка" → „Божията Майка" смени и регистър, и дължина).
/// Интервалите също, защото сливането на два абзаца е обичайна поправка.
/// ⚠ ЕДИН ОБЕКТ, не нов при всяка буква. `RegExp(...)` в тяло на цикъл се
/// строи наново на всяка итерация, а тези цикли обхождат ЦЯЛОТО четиво —
/// при дълго житие това са милиони излишни обекта.
final RegExp kWordChar = RegExp(r'[0-9a-zа-яёіѣѫ]');

String foldForMatch(String s) {
  final b = StringBuffer();
  for (final r in s.toLowerCase().runes) {
    final c = String.fromCharCode(r);
    if (RegExp(r'[0-9a-zа-яёіѣѫ]').hasMatch(c)) b.write(c);
  }
  return b.toString();
}

/// Отпечатъкът, който влиза в линка — ХЕШ, не самият текст.
///
/// ⚠ КИРИЛИЦАТА В URL СТАВА ОГРОМНА. Всяка буква е два байта UTF-8, а
/// процентното кодиране ги превръща в шест знака (`%D0%9E`), тъй че 48
/// знака отпечатък раздуваха адреса до близо триста — нечетим ред, който
/// пълзи през три реда в чата. (Докладвано от потребителя, 03.09.2026.)
///
/// Хешът е осем шестнайсетични знака и върши същата работа: не служи да се
/// ЧЕТЕ текстът, а да се ПОТВЪРДИ, че на посоченото място стои същото.
/// [locateQuote] проверява прозорците наоколо, вместо да търси подниз.
///
/// ⚠ ЦЕНАТА: адресът вече не е прозрачен — по него не се вижда какъв е
/// цитатът. Слъгът и числата обаче остават четими, тъй че мястото личи.
/// Осъзнат компромис (потребителят: „би ми се искало линкът да бъде
/// прозрачен… но ако не може, тогава остави").
String fingerprint(String text) {
  final f = foldForMatch(text);
  // ⚠ По-къс цитат НЕ получава отпечатък. Прозорецът е фиксиран, тъй че за
  // текст под него няма какво да се хешва — а и там координатите и без това
  // командват сами (виж [kMinFingerprintChars]).
  if (f.length < kFingerprintChars) return '';
  return _hash(f.substring(0, kFingerprintChars));
}

/// Сгънатото четиво плюс откъде идва всеки негов знак.
///
/// ⚠⚠ ЕДНА ФУНКЦИЯ ЗА ДВЕТЕ СТРАНИ. Улавянето ([captureSelection]) брои кое
/// поред е съвпадението, а отварянето ([locateQuoteAcross]) брои същото, за
/// да го намери. Броят ли по два различни начина — макар и по еднакво
/// изглеждащи цикли — номерът значи едно при запазването и друго при
/// отварянето, и това не личи отникъде.
class FoldedBlocks {
  /// Сгънатият текст на ВСИЧКИ блокове, слепени БЕЗ разделител.
  final String text;

  /// За всеки сгънат знак: в кой блок е и на кой СУРОВ знак вътре в него.
  final List<int> ofBlock;
  final List<int> ofChar;

  /// Откъде почва всеки блок в [text] — за да се познае „втори знак на
  /// блока" (буквицата) без ново обхождане.
  final List<int> blockStart;

  const FoldedBlocks(this.text, this.ofBlock, this.ofChar, this.blockStart);

  /// (блок, суров знак) → позиция в сгънатото.
  int foldedIndexOf(int block, int charStart) {
    for (var i = 0; i < ofBlock.length; i++) {
      if (ofBlock[i] > block || (ofBlock[i] == block && ofChar[i] >= charStart)) {
        return i;
      }
    }
    return ofBlock.isEmpty ? 0 : ofBlock.length - 1;
  }
}

FoldedBlocks foldBlocks(List<String> blocks) {
  final buf = StringBuffer();
  final ofBlock = <int>[];
  final ofChar = <int>[];
  final starts = <int>[];
  for (var i = 0; i < blocks.length; i++) {
    starts.add(ofBlock.length);
    final raw = blocks[i];
    for (var j = 0; j < raw.length; j++) {
      final c = raw[j].toLowerCase();
      if (kWordChar.hasMatch(c)) {
        buf.write(c);
        ofBlock.add(i);
        ofChar.add(j);
      }
    }
  }
  return FoldedBlocks(buf.toString(), ofBlock, ofChar, starts);
}

/// Всички места в сгънатия текст, чийто прозорец дава този отпечатък.
///
/// ⚠ Прозорците се ЗАСТЪПВАТ нарочно: „ааа" с прозорец 2 дава две места, не
/// едно. Инак поредните номера биха се разминали при повтарящ се текст.
List<int> fingerprintMatches(String foldedHay, String fp, int window) {
  final out = <int>[];
  if (fp.isEmpty || window <= 0 || foldedHay.length < window) return out;
  for (var i = 0; i + window <= foldedHay.length; i++) {
    if (_hash(foldedHay.substring(i, i + window)) == fp) out.add(i);
  }
  return out;
}

/// Отпечатъкът за версия 2: (хеш, дължина на прозореца).
///
/// ⚠ РАЗЛИКАТА С [fingerprint] е, че тук прозорецът се СВИВА до дължината на
/// самия цитат, вместо цитатът да се отхвърля като твърде къс. Оттам идва
/// цялата полза за кратките откъси: „година" получава хеш на шест знака, по
/// който съвпаденията МОГАТ ДА СЕ ПРЕБРОЯТ — а точно преброяването дава
/// поредния номер, който потребителят поиска.
///
/// ⚠ [kMinFingerprintChars] НЕ Е махнат и продължава да важи, но само за
/// стария път: къс отпечатък без пореден номер наистина вреди (виж довода
/// там). С номер той е точен, не приблизителен — затова проверката е в
/// [locateQuoteAcross], а не тук.
///
/// ⚠ Под два сгънати знака няма какво да се хешва — тогава остават чистите
/// координати, както и досега.
(String, int) quoteFingerprint(String text) {
  final f = foldForMatch(text);
  if (f.length < 2) return ('', 0);
  final w = f.length < kFingerprintChars ? f.length : kFingerprintChars;
  return (_hash(f.substring(0, w)), w);
}

/// FNV-1a, 32 бита. Избран за краткост и за това, че се смята в един проход —
/// [locateQuote] го вика за всеки прозорец в абзаца.
///
/// ⚠ Не е криптографски и не бива да става такъв: тук се пази от СЛУЧАЙНО
/// разминаване, не от подправяне. Осем знака дават около четири милиарда
/// стойности — в абзац от няколко хиляди знака сблъсък е практически
/// невъзможен.
String _hash(String s) {
  var h = 0x811c9dc5;
  for (final c in s.codeUnits) {
    h ^= c;
    h = (h * 0x01000193) & 0xFFFFFFFF;
  }
  return h.toRadixString(16).padLeft(8, '0');
}

/// Колко СУРОВИ знака от цитата пътуват в адреса.
///
/// ⚠ Не са само за проверката — стигат и до СТРАНИЦАТА, която вижда човек
/// БЕЗ приложението. Затова текстът е суров (с интервали и пунктуация), а не
/// сгънат: сгънатият се чете „ощеотмладигодини".
///
/// ⚠⚠ ОТ ВЕРСИЯ 2 ТЕКСТЪТ Е САМО ЗА ПОКАЗВАНЕ и вече не участва в
/// намирането. Дотук отпечатъкът се ИЗВЕЖДАШЕ от него при разчитане, тъй че
/// скъсяването му би убило МЪЛЧАЛИВО цялата устойчивост: 8 сурови знака се
/// сгъват до ~7, а прагът е [kFingerprintChars] = 16 — отпечатъкът би
/// излизал празен за всеки цитат и всичко би паднало на голи координати.
/// Затова хешът пътува като СВОЕ поле (виж [quoteFingerprint]).
///
/// ⚠ Осем знака са преценка на потребителя (05.09.2026): „тези дълги
/// линкове не стоят никак естетично, когато се пращат навън". Цената е, че
/// страницата за хора БЕЗ приложението показва само началото на цитата —
/// приета е, защото целият цитат и без това стои в самото съобщение, над
/// линка, а страницата служи главно за копчето „Отвори в приложението".
const int kLinkTextChars = 8;

/// ⚠⚠ ЦИТАТ ОТ ПИСАНИЕТО СЕ АДРЕСИРА ЧЕТИМО, а не пакетирано.
///
/// Предложение на потребителя (05.09.2026), и то по-добро от пакетирания
/// вид: приложението вече има система за вътрешни препратки („Мт.3:2-5"),
/// стихът е точната единица в Писанието, а номерът му НЕ СЕ МЕНИ никога.
/// Тъй че тук няма какво да се пази с отпечатъци и поредни номера — стихът
/// сам е адресът.
///
///     …/q/Mt.2:3-5(9;15)@bg
///                └──┘ └┘
///                 │    └── преводът, на който е маркирано
///                 └─────── 9 знака отрязани от НАЧАЛОТО на ст. 3,
///                          15 знака отрязани от КРАЯ на ст. 5
///
/// ⚠ И ДВЕТЕ ДОБАВКИ СА ПО ИЗБОР. „Mt.2:3-5" сам по себе си значи цели
/// стихове на превода, който получателят чете — тъй че всеки съществуващ
/// вътрешен адрес е и валиден външен линк, без нищо да се дописва.
///
/// ⚠ КРЪГЛИ СКОБИ, не ъглови или квадратни. Измерено, не предположено:
/// „<9;15>" се превръща в „%3C9;15%3E", „[9;15]" — в „%5B9;15%5D", защото
/// RFC 3986 не ги допуска в път. Кръглите минават НЕПРОМЕНЕНИ, а точно
/// видът на адреса е целта на цялата тази работа.
///
/// ⚠ ЗАЩО ЕЗИКЪТ ИЗОБЩО ПЪТУВА: отрязването се брои в ЗНАЦИ, а те са
/// различни във всеки превод — девет знака от българския стих не са девет
/// знака от църковнославянския. Липсва ли езикът или не е свален, показва се
/// преводът на получателя, а отрязването се ПРОПУСКА (цели стихове) вместо
/// да сочи наслуки.
///
/// Връща `null`, ако адресът не се сглобява — тогава се пада на пакетирания
/// вид, както за всяко друго четиво.
String? buildBibleQuoteLink(QuoteAnchor a) {
  final parts = a.locator.split('|');
  if (parts.length < 3) return null;
  final lang = parts[0], book = parts[1];
  final chapter = int.tryParse(parts[2]);
  if (book.isEmpty || chapter == null) return null;

  final from = a.block, to = a.blockEnd;
  if (from <= 0) return null;

  final b = StringBuffer('$book.$chapter:$from');
  if (to > from) b.write('-$to');
  // ⚠ Скобите се пишат само когато има какво — „(0;0)" е шум.
  if (a.charStart > 0 || a.charEnd > 0) {
    b.write('(${a.charStart};${a.charEnd})');
  }
  if (lang.isNotEmpty) b.write('@$lang');
  return 'https://$kQuoteLinkHost$kQuotePath/$b';
}

/// Обратното на [buildBibleQuoteLink]. `null`, ако не е такъв адрес.
///
/// ⚠ Всичко подир препратката е по избор и липсата му значи подразбиране:
/// без скоби — цели стихове; без „@" — преводът на получателя. Заради това
/// и „Mt.2" (цяла глава) се приема: отваря главата, без да маркира нищо.
ParsedQuoteLink? parseBibleQuoteLink(String tail) {
  var body = tail;
  var lang = '';
  var trimStart = 0, trimEnd = 0;

  final at = body.lastIndexOf('@');
  if (at >= 0) {
    lang = body.substring(at + 1).trim();
    body = body.substring(0, at);
  }

  final open = body.indexOf('(');
  if (open >= 0) {
    final close = body.indexOf(')', open);
    if (close < 0) return null;
    final nums = body.substring(open + 1, close).split(';');
    trimStart = int.tryParse(nums[0].trim()) ?? 0;
    if (nums.length > 1) trimEnd = int.tryParse(nums[1].trim()) ?? 0;
    if (trimStart < 0 || trimEnd < 0) return null;
    body = body.substring(0, open) + body.substring(close + 1);
  }

  final ref = parseBibleRef(body.trim());
  // ⚠ ТОЧНО ЕДИН пасаж. Препратка от няколко („Апок.12:3,20:2") е законна за
  // ЧЕТЕНЕ, но не и за цитат: цитатът е един непрекъснат откъс.
  if (ref.passages.length != 1) return null;
  final p = ref.passages.first;

  final from = p.isWholeChapter ? 0 : p.ranges.first.from;
  final to = p.isWholeChapter ? 0 : p.ranges.last.to;

  return ParsedQuoteLink(
    anchor: QuoteAnchor(
      source: QuoteSource.bible,
      locator: '$lang|${p.book}|${p.chapter}',
      // ⚠⚠ ЗА БИБЛИЯТА ЧИСЛАТА ЗНАЧАТ ДРУГО — виж [QuoteAnchor].
      block: from,
      charStart: trimStart,
      charLength: 0,
      blockEnd: to < from ? from : to,
      charEnd: trimEnd,
    ),
    // Отпечатък не трябва: стихът е точният адрес и не се мени.
    fingerprint: '',
    fingerprintLength: 0,
  );
}

/// Сглобява споделимия адрес.
///
/// ⚠ ВСИЧКО Е В ЕДНО КОДИРАНО НИЗЧЕ, не в отделни параметри. Причината е
/// кирилицата: в обикновен `?t=…` всяка буква става шест знака (`%D0%9E`) и
/// адресът минаваше 230 знака — ред, който пълзи през половин екран в чата.
/// Пакетиран и кодиран в base64url, същият текст заема наполовина.
/// (Решено с потребителя, 03.09.2026.)
///
/// ⚠ Цената: адресът е напълно НЕПРОЗРАЧЕН — не се вижда нито слъгът, нито
/// цитатът. Другите два изхода бяха или дълъг адрес (текст в параметър), или
/// невъзстановим цитат (само хеш); това е третият — къс адрес И пълни данни.
String buildQuoteLink(Quote q) {
  // ⚠ Писанието получава ЧЕТИМ адрес — виж [buildBibleQuoteLink]. Не се ли
  // сглоби (повреден locator), пада на пакетирания вид: по-добре грозен
  // работещ линк, отколкото никакъв.
  if (q.anchor.source == QuoteSource.bible) {
    final readable = buildBibleQuoteLink(q.anchor);
    if (readable != null) return readable;
  }
  final text = q.text.trim();
  // ⚠ Реже се по ДУМА, не по знак — иначе полученият текст свършва насред
  // дума и осветяването на страницата за неинсталирали изглежда счупено.
  // Същият похват като в [quoteShareText].
  final short = text.length <= kLinkTextChars
      ? text
      : text.substring(0, text.lastIndexOf(' ', kLinkTextChars)).trimRight();
  // ⚠ Хешът се смята от ЦЕЛИЯ цитат, не от отрязаното `short`. Дотук двете
  // съвпадаха по случайност (60 сурови знака дават над 16 сгънати); при 8
  // вече не съвпадат и от текста няма какво да се извлече.
  final (fp, fpLen) = quoteFingerprint(text);
  final packed = _pack([
    '$kQuoteLinkVersion',
    q.anchor.source.name,
    '${q.anchor.block}',
    '${q.anchor.charStart}',
    '${q.anchor.charLength}',
    q.anchor.locator,
    // ⚠ ОТ ВЕРСИЯ 2 нататък. Редът на първите шест полета е СЪЩИЯТ като във
    // версия 1 нарочно — така разчитането на двете дели началото си, а
    // страницата в GitHub Pages различава версиите по едно число.
    '${q.anchor.blockEnd}',
    '${q.anchor.charEnd}',
    fp,
    '$fpLen',
    '${q.anchor.occurrence}',
    '${q.anchor.occurrenceTotal}',
    // ⚠ Текстът остава ПОСЛЕДЕН: само така може да съдържа какво да е.
    short,
  ]);
  return 'https://$kQuoteLinkHost$kQuotePath/$packed';
}

/// Полетата → едно низче за адреса.
///
/// ⚠ Разделителят е `|`, а НЕ запетая или интервал: той не се среща нито в
/// слъг, нито в български текст, тъй че полетата не могат да се разлепят
/// погрешно. Текстът е ПОСЛЕДЕН и точно затова може да съдържа какво да е —
/// при разчитането всичко след шестото поле се слепва обратно.
/// Екранира едно поле, за да не се сблъска с разделителя.
///
/// ⚠⚠ РАЗДЕЛИТЕЛЯТ „|" СЕ СРЕЩА В САМИТЕ ДАННИ. `locator` за книга е
/// „път до тома|href на главата", а за Библия — „език|код|глава". Без
/// екраниране полетата се разместваха при разчитане: `locator` се режеше
/// до първата чертичка, `openBookQuote` виждаше `parts.length < 2` и се
/// отказваше МЪЛЧАЛИВО — линкът се отваряше, приложението стартираше и
/// човек оставаше в КАЛЕНДАРА. Житията работеха през цялото време, защото
/// техният `locator` е слъг и чертичка няма.
/// (Докладвано от потребителя, 03.09.2026, три пъти подред.)
///
/// ⚠ СЪВМЕСТИМО СЪС ЗАВАРЕНИТЕ ЛИНКОВЕ: поле без „|" и без „\" минава
/// непроменено и в двете посоки, тъй че вече споделените житийни адреси се
/// четат както преди. А за книга и Библия работещи линкове и без това не е
/// имало — те са били счупени по определение.
String _escField(String v) =>
    v.replaceAll('\\', '\\\\').replaceAll('|', '\\p');

String _unescField(String v) {
  final b = StringBuffer();
  for (var i = 0; i < v.length; i++) {
    if (v[i] == '\\' && i + 1 < v.length) {
      final n = v[i + 1];
      if (n == 'p') {
        b.write('|');
        i++;
        continue;
      }
      if (n == '\\') {
        b.write('\\');
        i++;
        continue;
      }
    }
    b.write(v[i]);
  }
  return b.toString();
}

String _pack(List<String> fields) {
  final bytes = utf8.encode(fields.map(_escField).join('|'));
  // ⚠ Компресията се пробва, но НЕ се налага: заглавката на zlib е 11 байта
  // и при къс низ пакетът излиза ПО-ГОЛЯМ от суровия. Затова се взима
  // по-малкото от двете, а първият знак казва кое е.
  final z = ZLibCodec(level: 9).encode(bytes);
  final useZ = z.length < bytes.length;
  final body = base64Url.encode(useZ ? z : bytes).replaceAll('=', '');
  return (useZ ? 'z' : 'r') + body;
}

/// Обратното на [_pack]. `null` при повреден низ.
List<String>? _unpack(String s) {
  if (s.length < 2) return null;
  final kind = s[0];
  // base64 иска дължина, кратна на четири — допълва се обратно.
  final body = s.substring(1).padRight((s.length - 1 + 3) ~/ 4 * 4, '=');
  try {
    final raw = base64Url.decode(body);
    final bytes = kind == 'z' ? ZLibCodec().decode(raw) : raw;
    return utf8.decode(bytes).split('|').map(_unescField).toList();
  } catch (_) {
    return null;
  }
}

/// Разчетен линк. `null` при непознат формат — тогава адресът се отваря в
/// браузъра, както всеки друг.
class ParsedQuoteLink {
  final QuoteAnchor anchor;

  /// Отпечатъкът, изведен от [text] — за [locateQuote].
  final String fingerprint;

  /// САМИЯТ цитат, както е бил при споделянето (отрязан до
  /// [kLinkTextChars]).
  ///
  /// ⚠ Пътува в адреса, за да може и СТРАНИЦАТА за хора без приложението да
  /// покаже за какво иде реч. Вътре в приложението не се ползва за
  /// намирането — там работи отпечатъкът.
  final String text;

  /// С колко СГЪНАТИ знака е смятан [fingerprint] — виж [quoteFingerprint].
  ///
  /// ⚠ НЕ СЕ ИЗВЕЖДА от [text]: той е отрязан до [kLinkTextChars], а сгъването
  /// маха интервалите и пунктуацията, тъй че суровата дължина не казва нищо
  /// за сгънатата. Затова числото пътува само.
  final int fingerprintLength;

  const ParsedQuoteLink({
    required this.anchor,
    required this.fingerprint,
    this.fingerprintLength = kFingerprintChars,
    this.text = '',
  });
}

ParsedQuoteLink? parseQuoteLink(Uri uri) {
  if (!uri.path.startsWith('$kQuotePath/')) return null;
  final tail = uri.path.substring(kQuotePath.length + 1);

  // ⚠ РАЗПОЗНАВАНЕТО Е ПО ТОЧКАТА. Пакетираният вид е „r"/„z" плюс base64url
  // (букви, цифри, „-", „_") — точка в него НЯМА и не може да има. А всяка
  // библейска препратка носи точно една: „Mt.2:3-5". Тъй че признакът е
  // еднозначен и не иска нито версия, нито префикс.
  if (tail.contains('.')) {
    final b = parseBibleQuoteLink(Uri.decodeComponent(tail));
    if (b != null) return b;
  }

  final packed = tail;
  final f = _unpack(packed);
  if (f == null || f.length < 7) return null;

  // ⚠ Непозната ВЕРСИЯ се отхвърля мълчаливо, вместо да се разчита „както
  // дойде": по-добре линкът да се отвори в браузъра, отколкото приложението
  // да заведе човека на произволно място с вид на правилно.
  final v = int.tryParse(f[0]);
  if (v == null || v > kQuoteLinkVersion) return null;

  final source = QuoteSource.values.where((e) => e.name == f[1]).firstOrNull;
  final locator = f[5];
  if (source == null || locator.isEmpty) return null;

  final block = int.tryParse(f[2]) ?? 0;
  final charStart = int.tryParse(f[3]) ?? 0;
  final charLength = int.tryParse(f[4]) ?? 0;

  // ⚠ ВЕРСИЯ 1 — вече споделени адреси. Носи шест полета и текст; краят на
  // цитата, отпечатъкът и поредният номер ги няма, тъй че се извеждат както
  // преди: краят от началото плюс дължината, отпечатъкът от текста (той е
  // бил 60 знака, тоест над прага), номер — никакъв.
  if (v < 2) {
    final text = f.sublist(6).join('|');
    return ParsedQuoteLink(
      anchor: QuoteAnchor(
        source: source,
        locator: locator,
        block: block,
        charStart: charStart,
        charLength: charLength,
      ),
      fingerprint: fingerprint(text),
      text: text,
    );
  }

  // ⚠ ВЕРСИЯ 2. Непълен пакет се отхвърля, вместо да се дочита с нули:
  // липсващ `charEnd` би дал цитат, който свършва там, където започва.
  if (f.length < 13) return null;
  // ⚠ Текстът може да съдържа `|` (рядко, но възможно) — затова се сглобява
  // обратно от ВСИЧКО след дванайсетото поле, вместо да се взима само f[12].
  final text = f.sublist(12).join('|');

  return ParsedQuoteLink(
    anchor: QuoteAnchor(
      source: source,
      locator: locator,
      block: block,
      charStart: charStart,
      charLength: charLength,
      blockEnd: int.tryParse(f[6]),
      charEnd: int.tryParse(f[7]),
      occurrence: int.tryParse(f[10]) ?? 0,
      occurrenceTotal: int.tryParse(f[11]) ?? 0,
    ),
    fingerprint: f[8],
    fingerprintLength: int.tryParse(f[9]) ?? kFingerprintChars,
    text: text,
  );
}

/// Резултат от намирането на цитата в текста.
class QuoteHit {
  /// Начален знак В СУРОВИЯ текст на блока.
  final int start;
  final int length;

  /// Как е намерен — за да може повикващият да реши дали да предупреди.
  final QuoteHitKind kind;

  /// В КОЙ блок е намерен.
  ///
  /// ⚠ Може да се РАЗЛИЧАВА от подсказания: от версия 2 търсенето минава през
  /// цялото четиво наведнъж, тъй че цитат, изместен в съседен абзац (сливане
  /// или разделяне при поправка в превода), се намира там, където реално е.
  /// Дотук търсенето беше затворено в един блок и такова изместване не се
  /// поправяше — числата водеха в грешния абзац и това не личеше отникъде.
  final int block;

  const QuoteHit(this.start, this.length, this.kind, {this.block = 0});
}

/// ⚠ И ТРИТЕ СТОЙНОСТИ ОТВАРЯТ ЦИТАТА. Разликата е само доколко е потвърдено
/// мястото — нито една не е грешка и НИТО ЕДНА не се показва на човека.
enum QuoteHitKind {
  /// Текстът стои точно там, където сочат числата.
  exact,

  /// Намерен е наблизо — текстът е бил разместен от редакция след
  /// споделянето, и координатите са коригирани по съдържание.
  shifted,

  /// Ползвани са само координатите: цитатът е бил твърде къс за отпечатък,
  /// или текстът е пренаписан до неузнаваемост. Поведението е същото, което
  /// би имала система БЕЗ никакво търсене.
  byCoordinates,
}

/// Намира цитата в суровия текст на блока.
///
/// ⚠ ТУК Е СЪРЦЕВИНАТА НА ЦЯЛАТА УСТОЙЧИВОСТ. Работи в „сгънато"
/// пространство ([foldForMatch]), защото точно пунктуацията и регистърът се
/// менят при редакция — а после превежда намерената позиция обратно в
/// суровия текст, защото осветяването рисува върху него.
QuoteHit locateQuote(String blockText, int hintStart, int hintLength,
        String wantFingerprint) =>
    locateQuoteAcross(
      [blockText],
      block: 0,
      charStart: hintStart,
      charLength: hintLength,
      fingerprint: wantFingerprint,
    );

/// Готовият вид за трите четеца: намира цитата от разчетен линк.
QuoteHit locateParsedQuote(List<String> blocks, ParsedQuoteLink q) =>
    locateQuoteAcross(
      blocks,
      block: q.anchor.block,
      charStart: q.anchor.charStart,
      charLength: q.anchor.charLength,
      fingerprint: q.fingerprint,
      fingerprintLength: q.fingerprintLength,
      occurrence: q.anchor.occurrence,
      occurrenceTotal: q.anchor.occurrenceTotal,
    );

/// Намира цитата в ЦЯЛОТО четиво — виж [locateQuote] за довода зад начина.
///
/// ⚠⚠ КОЕ ПЕЧЕЛИ, КОГА. Три правила, наредени по сила:
///
///   1. **Поредният номер**, ако броят на съвпаденията е СЪЩИЯТ като при
///      запазването. Тогава мястото е известно точно, а не приблизително —
///      и точно това решава случая „«година» се среща 15 пъти".
///   2. **Най-близкото до координатите**, ако броят се е променил (текстът е
///      пренаписан) или номер изобщо няма (линк от версия 1). Старото,
///      изпитано правило.
///   3. **Голите координати**, ако отпечатъкът не се намира никъде.
///
/// ⚠ Правило 2 иска отпечатък поне [kMinFingerprintChars] знака — под това
/// „най-близкото" е по-скоро вредно, отколкото полезно (виж довода там).
/// Правило 1 няма такъв праг: то не гадае, а брои.
QuoteHit locateQuoteAcross(
  List<String> blocks, {
  required int block,
  required int charStart,
  required int charLength,
  required String fingerprint,
  int fingerprintLength = kFingerprintChars,
  int occurrence = 0,
  int occurrenceTotal = 0,
}) {
  // ⚠ КООРДИНАТИТЕ СА ОСНОВАТА, отпечатъкът е само потвърждение върху тях.
  // Няма ли отпечатък, връщаме точно каквото сочат числата, без да гадаем.
  final fallback =
      QuoteHit(charStart, charLength, QuoteHitKind.byCoordinates, block: block);
  if (blocks.isEmpty || fingerprint.isEmpty) return fallback;

  final window =
      fingerprintLength <= 0 ? kFingerprintChars : fingerprintLength;

  // ⚠ Къс отпечатък БЕЗ пореден номер не се ползва изобщо — виж
  // [kMinFingerprintChars]. С номер се ползва, защото тогава не се гадае.
  if (window < kMinFingerprintChars && occurrence <= 0) return fallback;

  // ⚠ СЪЩОТО сгъване и СЪЩОТО броене, с които [captureSelection] е смятал
  // поредния номер — виж [FoldedBlocks].
  final f = foldBlocks(blocks);
  if (f.text.length < window) return fallback;

  final hintFolded = f.foldedIndexOf(block, charStart);
  final hits = fingerprintMatches(f.text, fingerprint, window);
  if (hits.isEmpty) {
    // Текстът го няма — четивото е пренаписано. Пак се отваря посоченото
    // място: по-добре приблизително вярно, отколкото нищо.
    return fallback;
  }

  int best;
  if (occurrence > 0 &&
      occurrenceTotal > 0 &&
      hits.length == occurrenceTotal &&
      occurrence <= hits.length) {
    // ⚠ ПРАВИЛО 1 — броят съвпада, значи текстът е онзи, и номерът е точен.
    best = hits[occurrence - 1];
  } else if (window >= kMinFingerprintChars || occurrence > 0) {
    // ⚠ ПРАВИЛО 2 — най-близкото до подсказката, не първото в текста. Честа
    // фраза се среща по няколко пъти в едно житие; първото би отвело далеч.
    best = hits.first;
    for (final h in hits) {
      if ((h - hintFolded).abs() < (best - hintFolded).abs()) best = h;
    }
  } else {
    return fallback;
  }

  final b = f.ofBlock[best];
  final rawStart = f.ofChar[best];
  // ⚠ Дължината се пренася от подсказката: отпечатъкът е само НАЧАЛОТО на
  // цитата, а целият откъс може да е много по-дълъг. Свива се само ако след
  // изместването вече не се побира в блока.
  final room = blocks[b].length - rawStart;
  final len = charLength < room ? charLength : room;
  final kind = (b == block && (rawStart - charStart).abs() <= 2)
      ? QuoteHitKind.exact
      : QuoteHitKind.shifted;
  return QuoteHit(rawStart, len < 0 ? 0 : len, kind, block: b);
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

/// Обгражда [start]..[start]+[length] (в ПЛОСКИЯ текст) с `<span>` от класа
/// [className], без да разваля HTML-а наоколо.
///
/// ⚠ ПОЗИЦИИТЕ ТУК СА В СУРОВИЯ текст между таговете — без декодирани
/// entity-та и без свити интервали. Ако викащият брои по ДРУГА формула
/// (напр. `_plainTextOf`, която декодира и нормализира), двете се разминават
/// при всеки `&nbsp;` или двоен интервал. За такива случаи има
/// [wrapQuoteByText], която ТЪРСИ вместо да брои.
///
/// ⚠ Различава се от `highlightHtml` по входа: тя търси ЗАЯВКА и маркира
/// всяко нейно срещане, а тук мястото е известно предварително — цитатът е
/// вече намерен от [locateQuote]. Затова е отделна функция, а не параметър
/// на онази: двете нямат общо освен това, че и двете пишат `<span>`.
///
/// ⚠ Диапазонът може да ПРЕСИЧА тагове („…и <em>рече</em> му…"), тъй че
/// span-ът се отваря и затваря във ВСЯКО парче гол текст поотделно. Един
/// span през целия диапазон би обхванал чужди затварящи тагове и flutter_html
/// би оцветил остатъка от абзаца — същият капан като с увисналото `</a>` в
/// конвейера за жития.
String wrapRangeHtml(String html, int start, int length, String className) {
  if (length <= 0 || start < 0) return html;
  final end = start + length;
  final buf = StringBuffer();
  var plainPos = 0;

  for (final m in RegExp(r'<[^>]+>|[^<]+').allMatches(html)) {
    final piece = m.group(0)!;
    if (piece.startsWith('<')) {
      buf.write(piece);
      continue;
    }
    final pieceStart = plainPos;
    final pieceEnd = plainPos + piece.length;
    plainPos = pieceEnd;

    if (pieceEnd <= start || pieceStart >= end) {
      buf.write(piece);
      continue;
    }
    final from = start > pieceStart ? start - pieceStart : 0;
    final to = end < pieceEnd ? end - pieceStart : piece.length;
    buf
      ..write(piece.substring(0, from))
      ..write('<span class="$className">')
      ..write(piece.substring(from, to))
      ..write('</span>')
      ..write(piece.substring(to));
  }
  return buf.toString();
}

/// Текстът, който тръгва навън при споделяне на цитат.
///
/// ⚠ ОБИКНОВЕН ТЕКСТ, БЕЗ ФОРМАТИРАНЕ. Viber, WhatsApp и Telegram свеждат
/// споделеното до чист текст — курсив и по-дребен шрифт не се предават.
/// Затова йерархията е СТРУКТУРНА: кавички за цитата, тире и празен ред за
/// източника, отделен ред за поканата. (Видът е по описание на потребителя,
/// 02.09.2026 — курсивът в него е неосъществим и е заменен с тире.)
///
/// ⚠ Линкът е на СОБСТВЕН РЕД, най-отдолу. Чатовете го правят кликаем сам, а
/// сложен насред изречение би разкъсал текста при пренасяне.
/// Над колко знака цитатът се смята за ДЪЛЪГ и се съкращава в съобщението.
///
/// ⚠ 12 реда по мярката на потребителя (03.09.2026). В чат ред е около 40
/// знака, тъй че 480 е горницата — над нея съобщението заема цял екран и
/// самият линк изпада надолу, където не се вижда.
const int kLongQuoteChars = 480;

String quoteShareText(Quote q) {
  final full = q.text.trim();
  final long = full.length > kLongQuoteChars;
  // ⚠ Реже се по ДУМА, не по знак: „…поради което той реши да н…" изглежда
  // като счупено, а не като съкратено.
  final shown = long
      ? '${full.substring(0, full.lastIndexOf(' ', kLongQuoteChars)).trimRight()}…'
      : full;

  final b = StringBuffer()
    ..writeln('„$shown"')
    ..writeln();
  if (q.title.trim().isNotEmpty) {
    b
      ..writeln('— из „${q.title.trim()}"')
      ..writeln();
  }
  b
    // ⚠ Поканата е РАЗЛИЧНА при съкратен цитат: „чети в контекст" подсказва,
    // че е показано всичко и линкът само добавя обкръжението — а тук има и
    // недоказан остатък. (Искане на потребителя.)
    ..writeln(long ? 'Виж продължението:' : 'Чети в контекст:')
    ..write(buildQuoteLink(q));
  return b.toString();
}


/// Обгражда цитата в HTML-а, като го ТЪРСИ по съдържание.
///
/// ⚠⚠ ПРЕДПОЧИТАЙ ТАЗИ ПРЕД [wrapRangeHtml] за всичко, което идва отвън.
///
/// Причината е измерена, не теоретична: плоският текст на един абзац се
/// смята на няколко места в проекта и формулите не съвпадат — `_plainTextOf`
/// декодира entity-та, свива поредните интервали и реже краищата, докато
/// [wrapRangeHtml] брои суровите знаци между таговете. При кратък прост
/// абзац разликата е нула и всичко изглежда наред; в дълго житие с
/// форматиране фонът се разминава или изчезва.
/// (Докладвано от потребителя, 03.09.2026: „позиционира на цитата, но не го
/// маркира" — св. Кирил Философ.)
///
/// Търсенето минава през [foldForMatch], тъй че е нечувствително и към
/// пунктуация, и към регистър — същият механизъм, който пази споделените
/// линкове.
///
/// [hintStart] насочва избора, когато цитатът се среща няколко пъти.
String wrapQuoteByText(String html, String quoteText, String className,
    {int hintStart = 0}) {
  final want = foldForMatch(quoteText);
  if (want.isEmpty) return html;

  // Сгъваме, като помним откъде идва всеки знак — но НЕ в СУРОВИЯ html,
  // а в „ПЛОСКИЯ" му вид (без таговете), защото точно ТАКИВА позиции
  // очаква [wrapRangeHtml] по-долу (виж докстринга ѝ: „ПОЗИЦИИТЕ ТУК СА В
  // СУРОВИЯ текст МЕЖДУ таговете" — тоест броени БЕЗ самите тагове).
  //
  // ⚠⚠ ДОТУК `map` пазеше индекс в СУРОВИЯ html (броящ и `<p>`, `<em>` и
  // т.н.), а после се подаваше directно на `wrapRangeHtml`, която брои
  // без тях. Разликата е точно дължината на предходните тагове — за абзац,
  // започващ direct с `<p>`, това са 3 знака, и маркирането излизаше
  // отместено с точно толкова напред. (Диагностицирано от потребителя,
  // 03.09.2026, върху реалния текст на св. Кирил Философ и Методий
  // Моравски — „А след това…" излизаше маркирано от „лед това…".)
  //
  // ⚠ ENTITY-ТАТА СЕ ПРЕСКАЧАТ ЦЕЛИ ЗА СГЪВАНЕТО (по-раншна поправка,
  // 03.09.2026): `&nbsp;` не бива да се сгъва като буквите „nbsp". Но за
  // БРОЕНЕТО на плоска позиция ТЕ СИ УЧАСТВАТ с пълната си дължина —
  // `wrapRangeHtml` не разпознава entity-та и брои всеки неин знак
  // поотделно, тъй че плоското броене тук трябва да прави същото.
  final entity = RegExp(r'&(#\d+|#x[0-9a-fA-F]+|[a-zA-Z]+);');
  final map = <int>[];
  final folded = StringBuffer();
  var inTag = false;
  var plainPos = 0;
  var i = 0;
  while (i < html.length) {
    final ch = html[i];
    if (ch == '<') {
      inTag = true;
      i++;
      continue;
    }
    if (ch == '>') {
      inTag = false;
      i++;
      continue;
    }
    if (inTag) {
      i++;
      continue;
    }
    if (ch == '&') {
      final m = entity.matchAsPrefix(html, i);
      if (m != null) {
        plainPos += m.end - i;
        i = m.end;
        continue;
      }
    }
    final c = ch.toLowerCase();
    if (RegExp(r'[0-9a-zа-яёіѣѫ]').hasMatch(c)) {
      folded.write(c);
      map.add(plainPos);
    }
    plainPos++;
    i++;
  }
  final hay = folded.toString();

  // ⚠ Най-близкото до подсказката, не първото: цитат от няколко думи може да
  // се повтори в дълъг абзац.
  var best = -1, from = 0;
  while (true) {
    final at = hay.indexOf(want, from);
    if (at < 0) break;
    if (best < 0 || (map[at] - hintStart).abs() < (map[best] - hintStart).abs()) {
      best = at;
    }
    from = at + 1;
  }
  if (best < 0) return html;

  return wrapRangeHtml(
      html, map[best], map[best + want.length - 1] + 1 - map[best], className);
}
