// hyphenate.dart
//
// Динамично сричкопренасяне: вмъква меки преноси (U+00AD) по сричките,
// за да може двустранното подравняване (justify) да не оставя "реки" от
// разредени интервали. Базата не се пипа — прилага се при рендване.
//
// Обхваща САМО кирилски думи. Латиницата се пропуска нарочно: така
// HTML entity-тата (&ndash;) и адресите в href (saint://sv-andrej) остават
// недокоснати. Таговете също се прескачат.
//
// ВНИМАНИЕ: резултатът трябва да се кешира — обработката на 130 KB житие
// при всеки build е скъпа. Виж бележката в дъното.

const String _shy = '\u00AD'; // soft hyphen

// Гласните. Забележи, че "ъ" е тук: в българския е гласна ("въз-ход").
// В руския е ер голям (твърд знак) — това се разпознава по-долу.
const String _vowels = 'аъеиоуыэюяёАЪЕИОУЫЭЮЯЁ';

// Букви, които не могат да ЗАПОЧВАТ сричка — винаги вървят с предната.
const String _neverStarts = 'йьъЙЬЪ';

// След "ъ" идва някоя от тези → значи е руски твърд знак, не гласна
// ("подъ-езд", "объ-явление"), а не българското "въз-ход".
const String _afterHardSign = 'яеюёиЯЕЮЁИ';

bool _isMark(int code) => code >= 0x0300 && code <= 0x036F;

/// Кирилска дума (с комбиниращите ударения от църковните текстове).
final RegExp _cyrWord = RegExp(r'[А-Яа-яЀ-ӿ\u0300-\u036F]{5,}');

/// Тагове — прескачат се изцяло.
final RegExp _tag = RegExp(r'<[^>]*>');

/// Вмъква меки преноси в една дума.
String hyphenateWord(String w) {
  final ch = w.split('');
  final n = ch.length;
  if (n < 5) return w;

  // Класификация на всяка позиция
  final mark = List<bool>.filled(n, false);
  final vowel = List<bool>.filled(n, false);
  for (var i = 0; i < n; i++) {
    final code = ch[i].codeUnitAt(0);
    if (_isMark(code)) {
      mark[i] = true;
      continue;
    }
    if (_vowels.contains(ch[i])) {
      // "ъ" пред я/е/ю/ё/и е руски твърд знак → не е гласна
      if ((ch[i] == 'ъ' || ch[i] == 'Ъ') && i + 1 < n) {
        var j = i + 1;
        while (j < n && mark[j]) j++;
        if (j < n && _afterHardSign.contains(ch[j])) continue;
      }
      vowel[i] = true;
    }
  }

  final vpos = <int>[];
  for (var i = 0; i < n; i++) {
    if (vowel[i]) vpos.add(i);
  }
  if (vpos.length < 2) return w; // едносрична дума

  final breaks = <int>{};
  for (var k = 0; k < vpos.length - 1; k++) {
    final v1 = vpos[k], v2 = vpos[k + 1];

    // Съгласните между двете гласни (ударенията се прескачат)
    final cons = <int>[];
    for (var i = v1 + 1; i < v2; i++) {
      if (!mark[i]) cons.add(i);
    }

    int bp;
    if (cons.isEmpty) {
      bp = v2; // гласна до гласна: "ра-я"
    } else if (cons.length == 1) {
      bp = cons[0]; // една съгласна: "ма-ма"
    } else {
      bp = cons[1]; // две и повече: "сес-тра", "пре-по-доб-ный"
    }

    // й/ь/ъ не могат да започват сричка → преносът се мести напред
    // ("пис-ьмо" → "пись-мо", "по-дъезд" → "подъ-езд")
    while (bp < n && _neverStarts.contains(ch[bp])) {
      bp++;
    }
    // и не бива да остава сама буква в началото или в края
    if (bp < 2 || bp > n - 2) continue;

    breaks.add(bp);
  }
  if (breaks.isEmpty) return w;

  final buf = StringBuffer();
  for (var i = 0; i < n; i++) {
    if (breaks.contains(i)) buf.write(_shy);
    buf.write(ch[i]);
  }
  return buf.toString();
}

/// Обикновен текст (без тагове).
String hyphenateText(String text) =>
    text.replaceAllMapped(_cyrWord, (m) => hyphenateWord(m.group(0)!));

/// HTML: обработва само текста МЕЖДУ таговете, самите тагове не се пипат.
String hyphenateHtml(String html) {
  final buf = StringBuffer();
  var last = 0;
  for (final m in _tag.allMatches(html)) {
    buf.write(hyphenateText(html.substring(last, m.start)));
    buf.write(m.group(0));
    last = m.end;
  }
  buf.write(hyphenateText(html.substring(last)));
  return buf.toString();
}

// ---------------------------------------------------------------------------
// Кеш: житието е до 130 KB — не го обработвай при всеки build.
// В четеца използвай нещо такова:
//
//   static final _cache = <String, String>{};
//   String _hyphenated(String slug, String html) =>
//       _cache.putIfAbsent(slug, () => hyphenateHtml(html));
//
// и подавай _hyphenated(widget.texts.slug, html) на Html(data: …).
// ---------------------------------------------------------------------------
