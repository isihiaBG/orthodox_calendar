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
