// reader_text_utils.dart
//
// Дребните текстови помощници на четенето — ОБЩИ за reader_screen.dart,
// drop_cap.dart и (занапред) четеца на книги.
//
// Изнесени, защото буквицата и търсенето ги ползват и двете: буквицата
// рендва обтичащата зона като чист Text (там entity-тата не се разкодират
// сами, както при flutter_html), а търсенето сравнява без ударения и
// регистър.

/// Разкодира HTML entity-тата (&ndash; &nbsp; &laquo; …) в истински символи.
/// Нужна е за обтичащата зона около буквицата, където текстът се рендва
/// като чист Text, а не през flutter_html (той си ги разкодира сам).
String decodeEntities(String s) {
  const named = {
    '&ndash;': '\u2013', // –
    '&mdash;': '\u2014', // —
    '&nbsp;': '\u00A0',
    '&laquo;': '\u00AB', // «
    '&raquo;': '\u00BB', // »
    '&bdquo;': '\u201E', // „
    '&ldquo;': '\u201C', // “
    '&rdquo;': '\u201D', // ”
    '&lsquo;': '\u2018',
    '&rsquo;': '\u2019',
    '&hellip;': '\u2026',  // …
    '&middot;': '\u00B7',
    '&deg;': '\u00B0',
    // Гръцки букви — срещат се в цитирани оригинални имена.
    '&Alpha;': '\u0391', '&Epsilon;': '\u0395',
    '&zeta;': '\u03B6', '&eta;': '\u03B7',
    '&theta;': '\u03B8', '&iota;': '\u03B9',
    '&kappa;': '\u03BA', '&lambda;': '\u03BB',
    '&nu;': '\u03BD', '&xi;': '\u03BE',
    '&omicron;': '\u03BF', '&rho;': '\u03C1',
    '&sigma;': '\u03C3', '&sigmaf;': '\u03C2',
    '&tau;': '\u03C4', '&omega;': '\u03C9',
    '&egrave;': '\u00E8',
    '&dagger;': '\u2020',  // † кръст
    '&amp;': '&',
    '&lt;': '<',
    '&gt;': '>',
    '&quot;': '"',
    '&apos;': "'",
  };
  var out = s;
  named.forEach((k, v) => out = out.replaceAll(k, v));
  // Числови: &#1234; и &#x04D1;
  out = out.replaceAllMapped(
    RegExp(r'&#(\d+);'),
    (m) => String.fromCharCode(int.parse(m.group(1)!)),
  );
  out = out.replaceAllMapped(
    RegExp(r'&#[xX]([0-9a-fA-F]+);'),
    (m) => String.fromCharCode(int.parse(m.group(1)!, radix: 16)),
  );
  return out;
}

/// "Изчистен" текст за търсене (малки букви, без ударения над буквите:
/// U+0300–U+036F — комбиниращи диакритични знаци) + карта на позициите,
/// за да можем да маркираме точно оригиналния (с ударения) откъс.
class Folded {
  final String text;
  final List<int> origIndex;
  const Folded(this.text, this.origIndex);
}

Folded fold(String s) {
  final buf = StringBuffer();
  final idx = <int>[];
  for (int i = 0; i < s.length; i++) {
    final code = s.codeUnitAt(i);
    if (code >= 0x0300 && code <= 0x036F) continue; // ударение/диакритика
    buf.write(s[i].toLowerCase());
    idx.add(i);
  }
  return Folded(buf.toString(), idx);
}

// ── Търсене с алтернативи („|") ─────────────────────────────────────────
//
// Заявката в четците е ЦЯЛА ФРАЗА (изгладена с [fold]). Знакът „|" дели
// няколко фрази, свързани с логическо ИЛИ: „отче наш|богородице" намира и
// двете. Както в Молитвослова.
//
// ⚠⚠ ВСЯКО търсене в четците минава през [nextFoldedMatch] — броенето,
// маркирането, позиционирането по ред, буквицата и съдържанието. Остане ли
// някъде голо `indexOf(заявка)`, при „|" там броят и маркираното се
// разминават и стрелките сочат празно място.

String _altKey = '';
List<String> _altList = const [];

/// Фразите в заявката — разделени по „|", изчистени, без празните.
List<String> queryAlternatives(String foldedQuery) {
  if (identical(foldedQuery, _altKey) || foldedQuery == _altKey) return _altList;
  _altKey = foldedQuery;
  return _altList = [
    for (final a in foldedQuery.split('|'))
      if (a.trim().isNotEmpty) a.trim()
  ];
}

/// Следващото съвпадение в изгладения [hay] от позиция [from]:
/// (начало, дължина), или null.
///
/// Печели НАЙ-РАННОТО; при еднакво начало — по-дългото („отче|отче наш"
/// маркира цялото „отче наш").
(int, int)? nextFoldedMatch(String hay, String foldedQuery, int from) {
  if (!foldedQuery.contains('|')) {
    if (foldedQuery.isEmpty) return null;
    final at = hay.indexOf(foldedQuery, from);
    return at < 0 ? null : (at, foldedQuery.length);
  }
  (int, int)? best;
  for (final a in queryAlternatives(foldedQuery)) {
    final at = hay.indexOf(a, from);
    if (at < 0) continue;
    if (best == null || at < best.$1 || (at == best.$1 && a.length > best.$2)) {
      best = (at, a.length);
    }
  }
  return best;
}

/// Има ли в заявката поне една истинска фраза („|" сам не търси нищо).
bool hasSearchText(String foldedQuery) =>
    queryAlternatives(foldedQuery).isNotEmpty;
