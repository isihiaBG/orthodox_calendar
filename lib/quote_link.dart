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
import 'dart:typed_data';
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
/// Колко СУРОВИ знака от цитата пътуваха в адреса на версии 1 и 2.
///
/// ⚠⚠ ОТ ВЕРСИЯ 3 ТЕКСТЪТ НЕ ПЪТУВА ИЗОБЩО и константата служи само на
/// РАЗЧИТАНЕТО на стари адреси. Пътят дотук минава през два извода:
///
///   • на версия 2 текстът беше свит от 60 на 8 знака — и това щеше да убие
///     МЪЛЧАЛИВО цялата устойчивост, защото отпечатъкът се извеждаше от него,
///     а осем сурови знака се сгъват под прага [kFingerprintChars];
///   • на версия 3 стана ясно, че щом отпечатъкът пътува сам, текстът не
///     върши нищо освен показване — а целият цитат и без това стои в самото
///     съобщение, над линка. Тъй че отпадна.
///
/// Цената: страницата за хора БЕЗ приложението вече не показва откъса, а само
/// поканата да го отворят. Приета съзнателно заради дължината на адреса.
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

/// ⚠⚠ ЛОКАТОР, СВИТ ДО НЯКОЛКО БАЙТА — виж [kQuoteLinkVersion] версия 3.
///
/// Разчетеният адрес носи МАРКЕР вместо истинския локатор, защото свиването е
/// необратимо без базата (за житие) и без списъка с томове (за книга).
/// [resolveQuoteLocator] го превръща обратно, преди четивото да се отвори.
///
///     ~a1b2c3d4        житие: отпечатък на слъга
///     ~09/397          книга: том 09, глава „Text/index_split_397.xhtml"
///
/// ⚠ Знакът „~" не се среща нито в слъг (те са само `a-z0-9-`), нито в път до
/// том, тъй че маркерът не може да се сбърка с истински локатор.
const String kLocatorMarker = '~';

/// Отпечатък на локатор — четири байта, изписани шестнайсетично.
///
/// ⚠ СЪЩИЯТ [_hash] като при цитата, но приложен върху слъга. Сблъсък при
/// около 1600 слъга и четири байта е под 0,03%, а и се проверява при
/// СГЛОБЯВАНЕТО: не е ли отпечатъкът единствен, слъгът влиза цял.
String locatorFingerprint(String locator) => _hash(locator);

/// Свива локатора на КНИГА до „том/глава", или `null`, ако не се разпознава.
///
/// ⚠ Пътят до тома е дълъг и кирилски („Жития на светиите - 09(сеп) -
/// Димитрий Ростовски.epub" — над шейсет байта), а от него носи смисъл
/// единствено НОМЕРЪТ. Главите пък се казват всичките „index_split_NNN".
/// Проверено срещу всичките дванайсет тома: 141 записа в първия, нито един с
/// друга форма и нито един с котва.
///
/// ⚠ Не съвпадне ли шаблонът (нов том, друг сглобяващ скрипт), се връща
/// `null` и локаторът влиза литерално. По-дълъг адрес, но работещ.
(int, int)? compactBookLocator(String locator) {
  final parts = locator.split('|');
  if (parts.length != 2) return null;
  final vol = RegExp(r'-\s*(\d{2})\s*\(').firstMatch(parts[0]);
  final ch = RegExp(r'index_split_(\d+)\.xhtml$').firstMatch(parts[1]);
  if (vol == null || ch == null) return null;
  return (int.parse(vol.group(1)!), int.parse(ch.group(1)!));
}

// ── Двоичният пакет на версия 3 ──────────────────────────────────────────
//
// байт 0   версия<<4 | вид                    (вид: 0 житие, 1 книга, 2 Библия)
// байт 1   флагове<<4 | (прозорец − 1)
//            бит 0  има отпечатък
//            бит 1  краят НЕ се извежда — следват две РАЗЛИКИ
//            бит 2  има пореден номер
//            бит 3  локаторът е СВИТ (как — решава видът)
// varint   блок, начален знак, дължина
// [бит 1]  varint разлика на блока, varint разлика на знака
// [бит 0]  4 байта отпечатък
// [бит 2]  varint кое поред, varint от колко
// локатор  [бит 3] житие: 4 байта; книга: байт том + varint глава
//          [иначе] varint дължина + байтове
//
// ⚠ Прозорецът се пише като „−1", за да се събере в четири бита: стойностите
// му са 1..16, а нула значи „няма отпечатък" и се носи от бит 0.

/// ⚠⚠ РАЗЛИКИТЕ МОГАТ ДА СА ОТРИЦАТЕЛНИ и това не е рядкост: при цитат през
/// няколко блока `charEnd` е знак в ПОСЛЕДНИЯ блок, а `charStart+charLength`
/// сочи в първия, тъй че разликата обикновено е под нулата. Обикновеният
/// varint не носи знак — първата версия просто изяждаше отрицателните и
/// краят на цитата се разместваше. Хванато от тест, не на око.
///
/// Зигзагът препъва числата така: 0→0, −1→1, 1→2, −2→3, … тъй че малките по
/// модул стойности остават малки и след кодирането.
int _zigzag(int n) => (n << 1) ^ (n >> 63);
int _unzigzag(int z) => (z >> 1) ^ -(z & 1);

void _putVarint(List<int> out, int v) {
  var n = v < 0 ? 0 : v;
  while (n >= 0x80) {
    out.add((n & 0x7F) | 0x80);
    n >>= 7;
  }
  out.add(n);
}

int _getVarint(List<int> b, List<int> pos) {
  var res = 0, shift = 0;
  while (pos[0] < b.length) {
    final c = b[pos[0]++];
    res |= (c & 0x7F) << shift;
    if (c < 0x80) return res;
    shift += 7;
    if (shift > 35) break;
  }
  return res;
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
  return 'https://$kQuoteLinkHost$kQuotePath/${_packV3(q)}';
}

/// Двоичният пакет на версия 3 — устройството е описано по-горе.
String _packV3(Quote q) {
  final a = q.anchor;
  final out = <int>[];

  // ⚠ Отпечатъкът се смята от ЦЕЛИЯ цитат, а не от отрязък: от версия 3
  // текстът изобщо не пътува, тъй че няма откъде да се извлече после.
  final (fp, fpLen) = quoteFingerprint(q.text.trim());
  final hasFp = fp.isNotEmpty && fpLen >= 1 && fpLen <= 16;

  // Краят се ИЗВЕЖДА при цитат в един блок — обичайното. Пише се само когато
  // наистина носи нещо.
  final endBlockDelta = a.blockEnd - a.block;
  final endCharDelta = a.charEnd - (a.charStart + a.charLength);
  final hasEnd = endBlockDelta != 0 || endCharDelta != 0;

  final hasOcc = a.occurrence > 0 && a.occurrenceTotal > 0;

  // Свиване на локатора — виж [kLocatorMarker].
  List<int>? compact;
  switch (a.source) {
    case QuoteSource.life:
      if (a.locator.isNotEmpty) {
        compact = [
          for (var i = 0; i < 8; i += 2)
            int.parse(locatorFingerprint(a.locator).substring(i, i + 2), radix: 16)
        ];
      }
    case QuoteSource.book:
      final c = compactBookLocator(a.locator);
      if (c != null) {
        compact = [c.$1];
        _putVarint(compact, c.$2);
      }
    case QuoteSource.bible:
      compact = null;
  }

  var flags = 0;
  if (hasFp) flags |= 1;
  if (hasEnd) flags |= 2;
  if (hasOcc) flags |= 4;
  if (compact != null) flags |= 8;

  out.add((kQuoteLinkVersion << 4) | a.source.index);
  out.add((flags << 4) | (hasFp ? fpLen - 1 : 0));
  _putVarint(out, a.block);
  _putVarint(out, a.charStart);
  _putVarint(out, a.charLength);
  if (hasEnd) {
    _putVarint(out, _zigzag(endBlockDelta));
    _putVarint(out, _zigzag(endCharDelta));
  }
  if (hasFp) {
    for (var i = 0; i < 8; i += 2) {
      out.add(int.parse(fp.substring(i, i + 2), radix: 16));
    }
  }
  if (hasOcc) {
    _putVarint(out, a.occurrence);
    _putVarint(out, a.occurrenceTotal);
  }
  if (compact != null) {
    out.addAll(compact);
  } else {
    final raw = utf8.encode(a.locator);
    _putVarint(out, raw.length);
    out.addAll(raw);
  }

  // ⚠ „b"/„c" вместо „r"/„z": първият знак различава ДВОИЧНИЯ пакет от
  // текстовия на версии 1 и 2. Без свой знак двата вида не се разпознават —
  // първият байт на двоичния е 0x30..0x32, тоест точно „0"/„1"/„2", каквито
  // започват и текстовите.
  final bytes = Uint8List.fromList(out);
  final z = ZLibCodec(level: 9).encode(bytes);
  final useZ = z.length < bytes.length;
  final body =
      base64Url.encode(useZ ? z : bytes).replaceAll('=', '');
  return (useZ ? 'c' : 'b') + body;
}

/// Обратното на [_packV3]. `null` при повреден или непознат пакет.
ParsedQuoteLink? _unpackV3(String packed) {
  List<int> b;
  try {
    var body = packed.substring(1);
    body = body.padRight((body.length + 3) ~/ 4 * 4, '=');
    b = base64Url.decode(body);
    if (packed[0] == 'c') b = ZLibCodec().decode(b);
  } catch (_) {
    return null;
  }
  if (b.length < 5) return null;

  final v = b[0] >> 4;
  // ⚠ По-нова версия се отхвърля МЪЛЧАЛИВО, вместо да се чете „както дойде":
  // по-добре линкът да се отвори в браузъра, отколкото приложението да
  // заведе човека на произволно място с вид на правилно.
  if (v > kQuoteLinkVersion) return null;
  final kindIdx = b[0] & 0x0F;
  if (kindIdx >= QuoteSource.values.length) return null;
  final source = QuoteSource.values[kindIdx];

  final flags = b[1] >> 4;
  final fpLen = (b[1] & 0x0F) + 1;
  final hasFp = flags & 1 != 0;
  final hasEnd = flags & 2 != 0;
  final hasOcc = flags & 4 != 0;
  final compact = flags & 8 != 0;

  final pos = [2];
  final block = _getVarint(b, pos);
  final charStart = _getVarint(b, pos);
  final charLength = _getVarint(b, pos);
  var blockEnd = block, charEnd = charStart + charLength;
  if (hasEnd) {
    blockEnd = block + _unzigzag(_getVarint(b, pos));
    charEnd = charStart + charLength + _unzigzag(_getVarint(b, pos));
  }
  var fp = '';
  if (hasFp) {
    if (pos[0] + 4 > b.length) return null;
    final sb = StringBuffer();
    for (var i = 0; i < 4; i++) {
      sb.write(b[pos[0]++].toRadixString(16).padLeft(2, '0'));
    }
    fp = sb.toString();
  }
  var occ = 0, total = 0;
  if (hasOcc) {
    occ = _getVarint(b, pos);
    total = _getVarint(b, pos);
  }

  String locator;
  if (compact) {
    switch (source) {
      case QuoteSource.life:
        if (pos[0] + 4 > b.length) return null;
        final sb = StringBuffer(kLocatorMarker);
        for (var i = 0; i < 4; i++) {
          sb.write(b[pos[0]++].toRadixString(16).padLeft(2, '0'));
        }
        locator = sb.toString();
      case QuoteSource.book:
        if (pos[0] >= b.length) return null;
        final vol = b[pos[0]++];
        final ch = _getVarint(b, pos);
        locator = '$kLocatorMarker${vol.toString().padLeft(2, '0')}/$ch';
      case QuoteSource.bible:
        return null;
    }
  } else {
    final n = _getVarint(b, pos);
    if (pos[0] + n > b.length) return null;
    locator = utf8.decode(b.sublist(pos[0], pos[0] + n), allowMalformed: true);
  }
  if (locator.isEmpty) return null;

  return ParsedQuoteLink(
    anchor: QuoteAnchor(
      source: source,
      locator: locator,
      block: block,
      charStart: charStart,
      charLength: charLength,
      blockEnd: blockEnd,
      charEnd: charEnd,
      occurrence: occ,
      occurrenceTotal: total,
    ),
    fingerprint: fp,
    fingerprintLength: hasFp ? fpLen : 0,
  );
}

/// ⚠ СГЛОБЯВАНЕТО на версии 1 и 2 е МАХНАТО, разчитането — не.
///
/// Вече споделени адреси трябва да продължат да се отварят, но нови такива
/// не се правят: версия 3 е двоична и по-къса. Тестът, който пази
/// съвместимостта, си строи стар пакет сам (`_packV1`) — нарочно препис, за
/// да може да строи вид, който кодът вече не умее.

/// Разекранира едно поле — обратното на екранирането при версии 1 и 2.
///
/// ⚠⚠ РАЗДЕЛИТЕЛЯТ „|" СЕ СРЕЩАШЕ В САМИТЕ ДАННИ. `locator` за книга е
/// „път до тома|href на главата", а за Библия — „език|код|глава". Без
/// екраниране полетата се разместваха при разчитане и линкът се отваряше в
/// КАЛЕНДАРА. Житията работеха през цялото време, защото техният `locator` е
/// слъг и чертичка няма. (Докладвано от потребителя, 03.09.2026, три пъти.)
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

/// Разчита ТЕКСТОВИЯ пакет на версии 1 и 2. `null` при повреден низ.
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

  /// САМИЯТ цитат, както е бил при споделянето.
  ///
  /// ⚠ ПРАЗЕН за адреси от версия 3 — те не носят текст. Пълни се само при
  /// разчитане на стар адрес (версии 1 и 2).
  ///
  /// ⚠ Пътува в адреса, за да може и СТРАНИЦАТА за хора без приложението да
  /// покаже за какво иде реч. Вътре в приложението не се ползва за
  /// намирането — там работи отпечатъкът.
  final String text;

  /// С колко СГЪНАТИ знака е смятан [fingerprint] — виж [quoteFingerprint].
  ///
  /// ⚠ НЕ СЕ ИЗВЕЖДА от [text]: той е отрязан (а от версия 3 изобщо го няма),
  /// а сгъването маха интервалите и пунктуацията, тъй че суровата дължина не
  /// казва нищо за сгънатата. Затова числото пътува само.
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

  // ⚠ ДВОИЧНИЯТ ПАКЕТ (версия 3) се разпознава по първия си знак. Без свой
  // знак двата вида не могат да се различат: първият БАЙТ на двоичния е
  // 0x30..0x32, тоест точно „0"/„1"/„2", с каквито започват и текстовите.
  final packed = tail;
  if (packed.isNotEmpty && (packed[0] == 'b' || packed[0] == 'c')) {
    return _unpackV3(packed);
  }

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
  final title = q.title.trim();
  if (title.isNotEmpty) {
    // ⚠⚠ ПИСАНИЕТО СЕ ЦИТИРА ПО СВОЯ РЕД. „— из «Евангелие от Йоан 2»" е
    // вярно, но нестандартно: за Библията установеният запис е съкратената
    // препратка в скоби. За всичко останало („Св. Иоан Рилски (Житие)")
    // такъв запис няма и си остава „— из".
    // (Поискано от потребителя, 05.09.2026.)
    b
      ..writeln(q.anchor.source == QuoteSource.bible
          ? '($title)'
          : '— из „$title"')
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
