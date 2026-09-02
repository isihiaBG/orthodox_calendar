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

import 'quotes.dart';

/// Пътят, по който Android разпознава линка. ⚠ Трябва да съвпада с
/// `android:pathPrefix` в AndroidManifest.xml.
const String kQuotePath = '/q';

/// Колко знака от цитата влизат в линка като отпечатък.
///
/// ⚠ Мярка на око, но с довод: 48 знака стигат, за да е практически
/// невъзможно съвпадение на друго място в същото четиво, и остават под
/// разумната дължина на адрес след процентното кодиране на кирилицата.
const int kFingerprintChars = 48;

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
String foldForMatch(String s) {
  final b = StringBuffer();
  for (final r in s.toLowerCase().runes) {
    final c = String.fromCharCode(r);
    if (RegExp(r'[0-9a-zа-яёіѣѫ]').hasMatch(c)) b.write(c);
  }
  return b.toString();
}

/// Отпечатъкът, който влиза в линка.
String fingerprint(String text) {
  final f = foldForMatch(text);
  return f.length <= kFingerprintChars ? f : f.substring(0, kFingerprintChars);
}

/// Сглобява споделимия адрес.
String buildQuoteLink(Quote q) {
  final p = <String, String>{
    'v': '$kQuoteLinkVersion',
    's': q.anchor.source.name,
    'l': q.anchor.locator,
    'b': '${q.anchor.block}',
    'c': '${q.anchor.charStart}',
    'n': '${q.anchor.charLength}',
    't': fingerprint(q.text),
  };
  final query =
      p.entries.map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}');
  return 'https://$kQuoteLinkHost$kQuotePath?${query.join('&')}';
}

/// Разчетен линк. `null` при непознат формат — тогава адресът се отваря в
/// браузъра, както всеки друг.
class ParsedQuoteLink {
  final QuoteAnchor anchor;

  /// Сведеният отпечатък от оригиналния текст. Празен при стар линк без `t`.
  final String fingerprint;

  const ParsedQuoteLink({required this.anchor, required this.fingerprint});
}

ParsedQuoteLink? parseQuoteLink(Uri uri) {
  if (!uri.path.startsWith(kQuotePath)) return null;
  final q = uri.queryParameters;

  // ⚠ Непозната ВЕРСИЯ се отхвърля мълчаливо, вместо да се разчита „както
  // дойде": по-добре линкът да се отвори в браузъра, отколкото приложението
  // да заведе човека на произволно място с вид на правилно.
  final v = int.tryParse(q['v'] ?? '');
  if (v == null || v > kQuoteLinkVersion) return null;

  final source = QuoteSource.values.where((e) => e.name == q['s']).firstOrNull;
  final locator = q['l'];
  if (source == null || locator == null || locator.isEmpty) return null;

  return ParsedQuoteLink(
    anchor: QuoteAnchor(
      source: source,
      locator: locator,
      block: int.tryParse(q['b'] ?? '') ?? 0,
      charStart: int.tryParse(q['c'] ?? '') ?? 0,
      charLength: int.tryParse(q['n'] ?? '') ?? 0,
    ),
    fingerprint: q['t'] ?? '',
  );
}

/// Резултат от намирането на цитата в текста.
class QuoteHit {
  /// Начален знак В СУРОВИЯ текст на блока.
  final int start;
  final int length;

  /// Как е намерен — за да може повикващият да реши дали да предупреди.
  final QuoteHitKind kind;

  const QuoteHit(this.start, this.length, this.kind);
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
    String wantFingerprint) {
  // ⚠ КООРДИНАТИТЕ СА ОСНОВАТА, отпечатъкът е само потвърждение върху тях.
  // Няма ли отпечатък или е твърде къс, за да различава — връщаме точно
  // каквото сочат числата, без да гадаем. Виж [kMinFingerprintChars].
  if (wantFingerprint.length < kMinFingerprintChars) {
    return QuoteHit(hintStart, hintLength, QuoteHitKind.byCoordinates);
  }

  // Съответствие „позиция в сгънатото → позиция в суровото".
  final map = <int>[];
  final folded = StringBuffer();
  for (var i = 0; i < blockText.length; i++) {
    final c = blockText[i].toLowerCase();
    if (RegExp(r'[0-9a-zа-яёіѣѫ]').hasMatch(c)) {
      folded.write(c);
      map.add(i);
    }
  }
  final hay = folded.toString();
  if (hay.isEmpty) {
    return QuoteHit(hintStart, hintLength, QuoteHitKind.byCoordinates);
  }

  // Къде сочи подсказката в сгънатото пространство.
  var hintFolded = 0;
  for (var i = 0; i < map.length; i++) {
    if (map[i] >= hintStart) {
      hintFolded = i;
      break;
    }
  }

  // ⚠ Търси се НАЙ-БЛИЗКОТО съвпадение до подсказката, не първото в текста.
  // Честа фраза („и рече му") се среща по няколко пъти в едно житие; първото
  // би отвело далеч от истинското място.
  var best = -1;
  var from = 0;
  while (true) {
    final at = hay.indexOf(wantFingerprint, from);
    if (at < 0) break;
    if (best < 0 || (at - hintFolded).abs() < (best - hintFolded).abs()) {
      best = at;
    }
    from = at + 1;
  }
  if (best < 0) {
    // Текстът го няма — абзацът е пренаписан. Пак се отваря посоченото място:
    // по-добре приблизително вярно, отколкото нищо.
    return QuoteHit(hintStart, hintLength, QuoteHitKind.byCoordinates);
  }

  final rawStart = map[best];
  // Дължината се пренася от подсказката: отпечатъкът е само НАЧАЛОТО на
  // цитата, а целият откъс може да е много по-дълъг.
  final kind = (rawStart - hintStart).abs() <= 2
      ? QuoteHitKind.exact
      : QuoteHitKind.shifted;
  return QuoteHit(rawStart, hintLength, kind);
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

/// Обгражда [start]..[start]+[length] (в ПЛОСКИЯ текст) с `<span>` от класа
/// [className], без да разваля HTML-а наоколо.
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
String quoteShareText(Quote q) {
  final b = StringBuffer()
    ..writeln('„${q.text.trim()}"')
    ..writeln();
  if (q.title.trim().isNotEmpty) {
    b
      ..writeln('— из „${q.title.trim()}"')
      ..writeln();
  }
  b
    ..writeln('Чети в контекст:')
    ..write(buildQuoteLink(q));
  return b.toString();
}
