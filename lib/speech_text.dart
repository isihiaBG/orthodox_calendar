// speech_text.dart
//
// Текстът, който вижда човек → текстът, който чете гласът на телефона.
//
// Разгъва съкращенията, годините, вековете, числата и препратките към
// Писанието с думи („(Мат.12:5-7)" → „(Евангелие от Матей, дванадесета глава,
// стихове от пети до седми)"), а църковнославянските думи — с български
// букви. Това е ПРЕВОД от Python (tools/tts: pilot.expand_abbr,
// numbers_bg, bible_speak, cs_translit), който подготвя текста за
// ElevenLabs. ⚠ Двете страни трябва да дават едно и също —
// test/speech_text_test.dart ги сверява; поправка в правило се прави И на
// двете места.
//
// Изговорът (ударенията) НЕ е тук: за гласа на Google той е отделен речник
// (виж docs/notes/tts-audio.md).
//
// ⚠ Позициите: всяка буква на изговорения текст помни откъде в показания
// текст идва (`SpokenText.sourceRange`). Гласът съобщава коя дума чете в
// СВОЯ текст, а маркира се показаният. Разгънатото парче сочи цялото
// съкращение, от което е дошло.
//
// ⚠ `\b` и `\w` в Dart (както в JS) са само за латиница, а в Python — за
// всички букви. Затова навсякъде стоят `_wb` / `_we` (не-буква отпред /
// отзад), а не `\b`.

import 'bible_ref.dart';
import 'bible_link.dart' show bibleRefFromUrl;
import 'speech_tables.g.dart';

/// Текстът за гласа + откъде е всяка буква в показания текст.
class SpokenText {
  final String source;
  String _text;
  List<int> _from;
  List<int> _to;

  SpokenText(this.source)
      : _text = source,
        _from = List<int>.generate(source.length, (i) => i),
        _to = List<int>.generate(source.length, (i) => i + 1);

  String get text => _text;

  /// Обхватът в показания текст, от който идват буквите [start, end) на
  /// изговорения.
  (int, int) sourceRange(int start, int end) {
    if (_text.isEmpty) return (0, 0);
    start = start.clamp(0, _text.length - 1);
    end = end.clamp(start + 1, _text.length);
    var a = _from[start], b = _to[end - 1];
    for (var i = start; i < end; i++) {
      if (_from[i] < a) a = _from[i];
      if (_to[i] > b) b = _to[i];
    }
    return (a, b);
  }

  /// Замества обхвати от ПОКАЗАНИЯ текст — само преди всяка друга смяна.
  void replaceSpans(List<(int, int, String)> spans) {
    assert(_text == source);
    final sorted = [...spans]..sort((a, b) => a.$1.compareTo(b.$1));
    final ok = <(int, int, String)>[];
    var end = 0;
    for (final s in sorted) {
      if (s.$1 >= end && s.$2 <= source.length && s.$1 < s.$2) {
        ok.add(s);
        end = s.$2;
      }
    }
    if (ok.isEmpty) return;
    var i = 0;
    final sb = StringBuffer();
    final from = <int>[], to = <int>[];
    for (final (a, b, rep) in ok) {
      sb.write(source.substring(i, a));
      for (var k = i; k < a; k++) {
        from.add(k);
        to.add(k + 1);
      }
      sb.write(rep);
      for (var k = 0; k < rep.length; k++) {
        from.add(a);
        to.add(b);
      }
      i = b;
    }
    sb.write(source.substring(i));
    for (var k = i; k < source.length; k++) {
      from.add(k);
      to.add(k + 1);
    }
    _text = sb.toString();
    _from = from;
    _to = to;
  }

  /// Като `re.sub` с функция: `f` връща заместителя (или самото съвпадение).
  void sub(RegExp re, String Function(RegExpMatch m) f) {
    final ms = re.allMatches(_text).toList();
    if (ms.isEmpty) return;
    final sb = StringBuffer();
    final from = <int>[], to = <int>[];
    var last = 0;
    void keep(int a, int b) {
      sb.write(_text.substring(a, b));
      from.addAll(_from.sublist(a, b));
      to.addAll(_to.sublist(a, b));
    }

    for (final m in ms) {
      keep(last, m.start);
      final old = m[0]!;
      final rep = f(m);
      if (rep == old) {
        keep(m.start, m.end);
      } else {
        // Общото начало и край остават буква за буква; само средата сочи
        // целия заменен обхват.
        var p = 0;
        while (p < old.length && p < rep.length && old[p] == rep[p]) {
          p++;
        }
        var s = 0;
        while (s < old.length - p && s < rep.length - p &&
            old[old.length - 1 - s] == rep[rep.length - 1 - s]) {
          s++;
        }
        keep(m.start, m.start + p);
        final ma = m.start + p, mb = m.end - s;
        final mid = rep.substring(p, rep.length - s);
        int fa, fb;
        if (ma < mb) {
          fa = _from[ma];
          fb = _to[mb - 1];
          for (var i = ma; i < mb; i++) {
            if (_from[i] < fa) fa = _from[i];
            if (_to[i] > fb) fb = _to[i];
          }
        } else {
          // Чисто вмъкване — сочи мястото преди него.
          fa = fb = ma < _text.length ? _from[ma] : (ma > 0 ? _to[ma - 1] : 0);
        }
        sb.write(mid);
        for (var i = 0; i < mid.length; i++) {
          from.add(fa);
          to.add(fb);
        }
        keep(m.end - s, m.end);
      }
      last = m.end;
    }
    keep(last, _text.length);
    _text = sb.toString();
    _from = from;
    _to = to;
  }
}

/// Връзка в показания текст: [start, end) и адресът ѝ.
typedef SpeechLink = (int start, int end, String href);

/// Показаният текст (един абзац, без HTML) → текстът за гласа на телефона.
///
/// [links] — връзките в абзаца. Препратка към Писанието с връзка се чете по
/// РАЗЧЕТЕНАТА връзка (същата, по която се отваря „Библия"), не по текста ѝ
/// (бележка на автора, 28.10.2026): там съкращенията са какви ли не, а
/// връзките са проверени.
SpokenText speechText(String shown, {List<SpeechLink> links = const []}) =>
    _forPhoneVoice(speechExpand(shown, links: links));

/// Само разгъването — общото с ElevenLabs (сверява се с Python).
SpokenText speechExpand(String shown, {List<SpeechLink> links = const []}) {
  final t = SpokenText(shown);
  _bibleLinks(t, links);
  csConvert(t);
  expandAbbr(t);
  return t;
}

// ── общо ──────────────────────────────────────────────────────────────────

RegExp _re(String p) => RegExp(p, unicode: true);

/// Начало на дума: отпред няма буква, цифра или „_" (`\b` на Python).
const _wb = r'(?<![\p{L}\p{N}_])';

/// Край на дума.
const _we = r'(?![\p{L}\p{N}_])';

// ── числата (numbers_bg.py) ──────────────────────────────────────────────

const _unitsM = ['', 'един', 'два', 'три', 'четири', 'пет', 'шест', 'седем', 'осем', 'девет'];
const _unitsF = ['', 'една', 'две', 'три', 'четири', 'пет', 'шест', 'седем', 'осем', 'девет'];
const _unitsN = ['', 'едно', 'две', 'три', 'четири', 'пет', 'шест', 'седем', 'осем', 'девет'];
const _teens = [
  'десет', 'единадесет', 'дванадесет', 'тринадесет', 'четиринадесет',
  'петнадесет', 'шестнадесет', 'седемнадесет', 'осемнадесет', 'деветнадесет'
];
const _tens = [
  '', '', 'двадесет', 'тридесет', 'четиридесет', 'петдесет',
  'шестдесет', 'седемдесет', 'осемдесет', 'деветдесет'
];
const _hundreds = [
  '', 'сто', 'двеста', 'триста', 'четиристотин', 'петстотин',
  'шестстотин', 'седемстотин', 'осемстотин', 'деветстотин'
];
const _ordUnits = ['', 'първ', 'втор', 'трет', 'четвърт', 'пет', 'шест', 'седм', 'осм', 'девет'];
const _ordHundreds = [
  '', 'стотн', 'двестотн', 'тристотн', 'четиристотн', 'петстотн',
  'шестстотн', 'седемстотн', 'осемстотн', 'деветстотн'
];

typedef _Part = (String kind, int v, String word);

List<_Part> _parts(int n, String gender) {
  assert(n > 0 && n < 10000);
  final out = <_Part>[];
  final th = n ~/ 1000;
  var rest = n % 1000;
  if (th == 1) {
    out.add(('th', 1, 'хиляда'));
  } else if (th > 1) {
    out.add(('th', th, '${_unitsF[th]} хиляди'));
  }
  final h = rest ~/ 100;
  rest %= 100;
  if (h > 0) out.add(('h', h, _hundreds[h]));
  if (rest >= 10 && rest <= 19) {
    out.add(('teen', rest, _teens[rest - 10]));
  } else {
    final t = rest ~/ 10, u = rest % 10;
    if (t > 0) out.add(('t', t, _tens[t]));
    if (u > 0) {
      final units = gender == 'f' ? _unitsF : gender == 'n' ? _unitsN : _unitsM;
      out.add(('u', u, units[u]));
    }
  }
  return out;
}

String _join(List<String> words) {
  // „и" стои пред ПОСЛЕДНАТА съставка: триста четиридесет и три.
  if (words.length == 1) return words[0];
  return '${words.sublist(0, words.length - 1).join(' ')} и ${words.last}';
}

/// Бройно: 343 → „триста четиридесет и три".
String cardinal(int n, [String gender = 'm']) {
  if (n == 0) return 'нула';
  return _join([for (final p in _parts(n, gender)) p.$3]);
}

String _ordWord(String kind, int v, String gender) {
  final end = gender == 'f' ? 'а' : gender == 'n' ? 'о' : 'и';
  final String stem = switch (kind) {
    'u' => _ordUnits[v],
    'teen' => _teens[v - 10],
    't' => _tens[v],
    'h' => _ordHundreds[v],
    _ => v == 1 ? 'хилядн' : '${_unitsF[v]}хилядн',
  };
  if (gender == 'm' && (stem.endsWith('тн') || stem.endsWith('дн'))) {
    // стотен, хиляден — мъжкият род вмъква „е"
    return '${stem.substring(0, stem.length - 1)}ен';
  }
  return stem + end;
}

/// Редно: 343 → „триста четиридесет и трета" (ж. р. — „година").
String ordinal(int n, [String gender = 'f']) {
  final parts = _parts(n, gender);
  final words = [for (final p in parts.sublist(0, parts.length - 1)) p.$3];
  final last = parts.last;
  words.add(_ordWord(last.$1, last.$2, gender));
  return _join(words);
}

const _romanV = {'I': 1, 'V': 5, 'X': 10, 'L': 50, 'C': 100};

int roman(String s) {
  var total = 0;
  for (var i = 0; i < s.length; i++) {
    final v = _romanV[s[i]]!;
    final next = i + 1 < s.length ? (_romanV[s[i + 1]] ?? 0) : 0;
    total += next > v ? -v : v;
  }
  return total;
}

const _dash = r'\s*[-–—]\s*';
const _yearSuffix = r'(?:\s*(?:г\.|гг\.|година|години))';
// „г." е и край на изречението: „през 304 г. Мощите ѝ…" — точката остава.
// ⚠ В Python е `(?=(…))?`. В Dart квантор върху поглед напред не се приема,
// а `(?:(?=…))?` никога не хваща групата (празно повторение се отхвърля) —
// затова избор „поглед или нищо", без квантор.
const _gEnd = r'\s*г\.(?:(?=(\s+[А-ЯA-Z„"(]|\s*$))|)';

String _g(RegExpMatch m, int gi) => ' година${m[gi] != null ? '.' : ''}';

int _second(int a, int b) {
  // „1833–34" → 1834: вторият край, даден съкратено.
  final la = '$a'.length, lb = '$b'.length;
  if (b < a && lb < la) {
    var p = 1;
    for (var i = 0; i < lb; i++) {
      p *= 10;
    }
    b = a ~/ p * p + b;
  }
  return b;
}

String? _range(String pre, int a, int b) {
  b = _second(a, b);
  if (b <= a) return null;
  final p = pre.trim();
  if (p == 'между') return 'между ${ordinal(a)} и ${ordinal(b)} година';
  if (p == 'през' || p == 'в') return '$p ${ordinal(a)} – ${ordinal(b)} година';
  return '${(p != '' && p != 'от') ? pre : ''}от ${ordinal(a)} до ${ordinal(b)} година';
}

int _i(String? s) => int.parse(s!);

const _eras = [
  (r'\s*(?:пр\.|преди)\s*Р\.\s*Хр\.', ' преди Христа'),
  (r'\s*(?:сл\.|след)\s*Р\.\s*Хр\.', ' след Христа'),
  (r'\s*(?:пр\.|преди)\s*Хр\.', ' преди Христа'),
  (r'\s*(?:сл\.|след)\s*Хр\.', ' след Христа'),
];

void yearsText(SpokenText t) {
  // „(+235 г.)" — кончина, с „г." (без „г." го поема miscText).
  t.sub(_re(r'\(\s*[+†]\s*([1-9]\d{1,3})\s*г\.\s*\)'),
      (m) => '(почил през ${ordinal(_i(m[1]))} година)');
  // Диапазон с „г.": „(343–356 г.)", „от 813–820 г.", „между 471–474 г.".
  t.sub(
      _re('($_wb(?:от|между|през|в)\\s+)?$_wb([1-9]\\d{0,3})$_dash([1-9]\\d{0,3})$_yearSuffix'),
      (m) => _range(m[1] ?? '', _i(m[2]), _i(m[3])) ?? m[0]!);
  // „от 81 до 96 г.", „от 527 г. до 565 г."
  t.sub(_re('$_wb([Оо]т)\\s+([1-9]\\d{0,3})(?:\\s*г\\.)?\\s+до\\s+([1-9]\\d{0,3})$_gEnd'),
      (m) => '${m[1]} ${ordinal(_i(m[2]))} до ${ordinal(_i(m[3]))}${_g(m, 4)}');
  // „през 267 и 269 г."
  t.sub(_re('$_wb([1-9]\\d{0,3})\\s+и\\s+([1-9]\\d{0,3})$_gEnd'),
      (m) => '${ordinal(_i(m[1]))} и ${ordinal(_i(m[2]))}${_g(m, 3)}');
  // „(ок. 130–ок. 202)" — години на живот, и двата края приблизителни.
  t.sub(_re('\\(\\s*ок\\.\\s*([1-9]\\d{1,3})$_dashок\\.\\s*([1-9]\\d{1,3})\\s*\\)'),
      (m) => '(около ${ordinal(_i(m[1]))} – около ${ordinal(_i(m[2]))} година)');
  // В скоби, без „г.": (98–117), (1389–1425) — владетел, понтификат.
  t.sub(_re('\\(\\s*([1-9]\\d{1,3})$_dash([1-9]\\d{1,3})\\s*\\)'), (m) {
    final r = _range('', _i(m[1]), _i(m[2]));
    return r != null ? '($r)' : m[0]!;
  });
  // Единична година: „през 1866 г.".
  t.sub(_re('$_wb([1-9]\\d{0,3})$_gEnd'), (m) => ordinal(_i(m[1])) + _g(m, 2));
  // Векове: „XV в.", „XV–XVI в."
  t.sub(_re('$_wb([IVXLC]+)$_dash([IVXLC]+)\\s*в(?:в)?\\.'),
      (m) => '${ordinal(roman(m[1]!), 'm')} – ${ordinal(roman(m[2]!), 'm')} век');
  t.sub(_re('$_wb([IVXLC]+)\\s*в(?:в)?\\.'), (m) => '${ordinal(roman(m[1]!), 'm')} век');
  // И изписаното с думата: „в VI век".
  t.sub(_re('$_wb([IVXLC]+)\\s+(век|века|векове)$_we'),
      (m) => '${ordinal(roman(m[1]!), 'm')} ${m[2]}');
  for (final (p, rep) in _eras) {
    t.sub(_re(p), (_) => rep);
  }
  suffixedText(t);
  miscText(t);
}

// Редно с окончание след тире: „1-ва", „13-та", „8-мия", „12-ата", „1-вото".
const _suffixes = [
  ('ият', 'm', 'ят'), ('ия', 'm', 'я'), ('ата', 'f', 'та'), ('ото', 'n', 'то'),
  ('ите', 'm', 'те'), ('и', 'm', ''), ('а', 'f', ''), ('о', 'n', ''),
];

void suffixedText(SpokenText t) {
  // „52-годишния" → „петдесет и двегодишния"
  t.sub(_re('$_wb([1-9]\\d{0,3})\\s*[-–]\\s*(годишн[а-я]*)'), (m) {
    final words = cardinal(_i(m[1]), 'n');
    final k = words.lastIndexOf(' ');
    return k < 0 ? words + m[2]! : '${words.substring(0, k)} ${words.substring(k + 1)}${m[2]}';
  });
  t.sub(_re('$_wb([1-9]\\d{0,3})\\s*[-–]\\s*([а-я]{1,4})$_we'), (m) {
    for (final (end, gender, art) in _suffixes) {
      if (m[2]!.endsWith(end)) return ordinal(_i(m[1]), gender) + art;
    }
    return m[0]!;
  });
}

const _months = 'януари|февруари|март|април|май|юни|юли|август|септември|октомври|ноември|декември';

/// Останалите числа, които гласът би прочел криво.
void miscText(SpokenText t) {
  // Празни скоби — от махнатия номер на бележка.
  t.sub(_re(r'\s*\(\s*виж тук\s*\[\s*\]\s*\)'), (_) => '');
  t.sub(_re(r'\s*(?:\(\s*\)|\[\s*\])'), (_) => '');
  t.sub(_re(r'\s*\(\s*0\s*K\s*\)'), (_) => '');
  // „(+637)" — годината на кончината.
  t.sub(_re(r'\(\s*[+†]\s*([1-9]\d{2,3})\s*\)'),
      (m) => '(почил през ${ordinal(_i(m[1]))} година)');
  // „(ок. 306–373)"
  t.sub(_re('\\(\\s*ок\\.\\s*([1-9]\\d{1,3})$_dash([1-9]\\d{1,3})\\s*\\)'),
      (m) => '(около ${ordinal(_i(m[1]))} – ${ordinal(_i(m[2]))} година)');
  // „28 декември 1895" — денят е редно в мъжки род; годината след месеца — също.
  t.sub(
      _re('$_wb([1-9]|[12]\\d|3[01])\\s+($_months)$_we'
          '(?:\\s+([1-9]\\d{3})$_we(?!\\s*(?:г\\.|година)))?'),
      (m) => '${ordinal(_i(m[1]), 'm')} ${m[2]}'
          '${m[3] != null ? ' ${ordinal(_i(m[3]))} година' : ''}');
  // „през 1605 година" — само три- и четирицифрени (иначе „1 година" е срок).
  t.sub(_re('$_wb([1-9]\\d{2,3})(\\s+година)$_we'), (m) => ordinal(_i(m[1])) + m[2]!);
  // „17 век", „2 – 3 век"
  t.sub(_re('$_wb([1-9]\\d?)$_dash([1-9]\\d?)\\s+(век|века)$_we'),
      (m) => '${ordinal(_i(m[1]), 'm')} – ${ordinal(_i(m[2]), 'm')} ${m[3]}');
  t.sub(_re('$_wb([1-9]\\d?)\\s+(век|века)$_we'), (m) => '${ordinal(_i(m[1]), 'm')} ${m[2]}');
  // „-273,14 ᵒC"
  t.sub(_re(r'[-–−]\s*([1-9]\d*),(\d\d)\s*[ᵒ°]\s*C'), (m) {
    final a = _i(m[1]);
    if (a >= 10000) return m[0]!;
    return 'минус ${cardinal(a)} цяло и ${cardinal(_i(m[2]), 'f')} стотни градуса';
  });
  // „3.5 години"
  t.sub(_re('$_wb([1-9]\\d*)[.,]5$_we'), (m) {
    final a = _i(m[1]);
    return a < 10000 ? '${cardinal(a, 'f')} и половина' : m[0]!;
  });
  // „5%"
  t.sub(_re('$_wb(\\d+)\\s*%'), (m) {
    if (m[1] == '1') return 'един процент';
    final a = int.parse(m[1]!);
    return a < 10000 ? '${cardinal(a)} процента' : m[0]!;
  });
  // „(6=7–1)"
  t.sub(_re(r'\((\d)\s*=\s*(\d)\s*[–-]\s*(\d)\)'),
      (m) => '(${cardinal(_i(m[1]), 'n')} е равно на ${cardinal(_i(m[2]), 'n')} '
          'минус ${cardinal(_i(m[3]), 'n')})');
  // Изброяване „(1) … (2) …" и „… или 2) …" → „първо, …"
  t.sub(_re(r'(^|\s)\(?([1-9])\)\s+'), (m) => '${m[1]}${ordinal(_i(m[2]), 'n')}, ');
}

// ── Писанието (bible_speak.py) ───────────────────────────────────────────

final _bibleRe = _re(r'(?<![\p{L}\p{N}_])([1-4]\s*)?([А-Яа-яЁё]{2,8})\.?\s*'
    r'(\d{1,3}\s*[:,]\s*\d{1,3}'
    '(?:(?:$_dash|\\s*,\\s*)\\d{1,3}(?:\\s*:\\s*\\d{1,3})?)*)');

String _bookKey(String s) =>
    s.toLowerCase().replaceAll('ё', 'е').replaceAll(RegExp(r'[^0-9a-zа-я]'), '');

String _v(int n) => ordinal(n, 'm');

String _verses(List<(int, int)> items) {
  // b == -1: „до края на главата" (само от връзките).
  if (items.length == 1 && items[0].$2 == -1) {
    return 'стихове от ${_v(items[0].$1)} до края на главата';
  }
  if (items.length == 1 && items[0].$1 == items[0].$2) return '${_v(items[0].$1)} стих';
  if (items.length == 1 && items[0].$2 == items[0].$1 + 1) {
    return 'стихове ${_v(items[0].$1)} и ${_v(items[0].$2)}';
  }
  final words = [
    for (final (a, b) in items)
      a == b ? _v(a) : b == -1 ? 'от ${_v(a)} до края на главата' : 'от ${_v(a)} до ${_v(b)}'
  ];
  final body = words.length == 1
      ? words[0]
      : '${words.sublist(0, words.length - 1).join(', ')} и ${words.last}';
  return 'стихове $body';
}

String _chapter(String code, int c) => code == 'Ps' ? '${_v(c)} псалом' : '${ordinal(c)} глава';

final _crossChapter = RegExp(r'^(\d+):(\d+)-(\d+):(\d+)$');
final _placeTok = RegExp(r'^(?:(\d+):)?(\d+)(?:-(\d+))?$');

/// „5:15" → „пета глава, петнадесети стих". null, ако не се разчита.
String? speakPlace(String code, String place) {
  var p = place.replaceAll(RegExp(r'\s+'), '').replaceAll('–', '-').replaceAll('—', '-');
  p = p.replaceFirstMapped(RegExp(r'^(\d+),'), (m) => '${m[1]}:'); // руското „2, 21"
  final cc = _crossChapter.firstMatch(p);
  if (cc != null) {
    final c1 = _i(cc[1]), v1 = _i(cc[2]), c2 = _i(cc[3]), v2 = _i(cc[4]);
    return 'от ${_chapter(code, c1)}, ${_v(v1)} стих, до ${_chapter(code, c2)}, ${_v(v2)} стих';
  }
  final groups = <(int, List<(int, int)>)>[];
  for (final tok in p.split(',')) {
    final mm = _placeTok.firstMatch(tok);
    if (mm == null) return null;
    final a = _i(mm[2]), b = int.parse(mm[3] ?? mm[2]!);
    if (b < a || a == 0) return null;
    if (mm[1] != null) {
      final c = _i(mm[1]);
      if (c == 0) return null;
      groups.add((c, []));
    } else if (groups.isEmpty) {
      return null;
    }
    groups.last.$2.add((a, b));
  }
  return [for (final (c, vs) in groups) '${_chapter(code, c)}, ${_verses(vs)}'].join(', ');
}

/// Разчетена препратка → думи. null, ако книгата е непозната.
String? speakBibleRef(BibleRef r) {
  if (r.passages.isEmpty) return null;
  final code = r.passages.first.book;
  final title = kSpeechBookTitle[code];
  if (title == null) return null;
  final parts = <String>[];
  for (final p in r.passages) {
    if (p.book != code) return null;
    if (p.isWholeChapter) {
      parts.add(_chapter(code, p.chapter));
    } else {
      final items = [
        for (final v in p.ranges) (v.from, v.to == kToEndOfChapter ? -1 : v.to)
      ];
      parts.add('${_chapter(code, p.chapter)}, ${_verses(items)}');
    }
  }
  final spoken = parts.join(', ');
  if (code == 'Ps') return spoken[0].toUpperCase() + spoken.substring(1);
  return '$title, $spoken';
}

void _bibleLinks(SpokenText t, List<SpeechLink> links) {
  final spans = <(int, int, String)>[];
  for (final (a, b, href) in links) {
    final ref = bibleRefFromUrl(href);
    final spoken = ref == null ? null : speakBibleRef(ref);
    if (spoken != null) spans.add((a, b, spoken));
  }
  t.replaceSpans(spans);
}

void bibleText(SpokenText t) {
  t.sub(_bibleRe, (m) {
    final code = kSpeechBookAbbr[_bookKey((m[1] ?? '') + m[2]!)];
    if (code == null) return m[0]!;
    final spoken = speakPlace(code, m[3]!);
    if (spoken == null) return m[0]!;
    if (code == 'Ps') return spoken[0].toUpperCase() + spoken.substring(1);
    return '${kSpeechBookTitle[code]}, $spoken';
  });
}

// ── съкращенията (pilot.expand_abbr) ─────────────────────────────────────

void expandAbbr(SpokenText t) {
  for (final e in kSpeechTextFixes.entries) {
    t.sub(RegExp(RegExp.escape(e.key)), (_) => e.value);
  }
  // Препратките към Писанието — ПРЕДИ „св. ап." в имената на книгите.
  bibleText(t);
  // „св." става „свети"/„света" по името след него.
  t.sub(_re(r'(?<![А-Яа-я])([Сс]в)\.(\s+)?([А-Яа-я]+)'), (m) {
    final low = m[3]!.toLowerCase();
    var w = 'аяАЯ'.contains(low[low.length - 1]) && !kSpeechSvMale.contains(low)
        ? 'света'
        : 'свети';
    if (m[1]![0] == 'С') w = w[0].toUpperCase() + w.substring(1);
    return w + (m[2] ?? ' ') + m[3]!;
  });
  // Годините и вековете — ПРЕДИ „г." да стане „година".
  t.sub(_re(r'(\d)\s*год\.'), (m) => '${m[1]} г.');
  yearsText(t);
  t.sub(_re(r'(\d)\s*гг\.'), (m) => '${m[1]} години');
  t.sub(_re(r'(\d)\s*г\.'), (m) => '${m[1]} година');
  t.sub(_re(r'([IVXLC])\s*вв\.'), (m) => '${m[1]} век');
  t.sub(_re(r'([IVXLC])\s*в\.'), (m) => '${m[1]} век');
  const nb = r'(?<![А-Яа-я])';
  t.sub(_re('$nbт\\.\\s?е\\.'), (_) => 'тоест');
  t.sub(_re('$nbравноап\\.'), (_) => 'равноапостол');
  t.sub(_re('$nbт\\.\\s?н\\.(?=\\s+[А-Я„])'), (_) => 'така нататък.');
  t.sub(_re('$nbт\\.\\s?н\\.'), (_) => 'така нататък');
  t.sub(_re('$nbнапр\\.'), (_) => 'например');
  t.sub(_re('$nbс\\.\\s*(?=[А-Я])'), (_) => 'село ');
  t.sub(_re('$nbап\\.'), (_) => 'апостол');
  t.sub(_re('$nbи сл\\.'), (_) => 'и следващите');
  t.sub(_re('$nbи др\\.'), (_) => 'и други');
  t.sub(_re('$nb([Вв])ж\\.'), (m) => m[1] == 'В' ? 'Виж' : 'виж');
  t.sub(_re('$nb([Сс])рв\\.'), (m) => '${m[1]}равни');
  t.sub(_re(r'(\d)\s*гл\.'), (m) => '${m[1]} глава');
  // Знаци, които гласът би прочел като нещо странно.
  t.sub(_re(r'^\s*[•▪◦·]\s*'), (_) => '');
  t.sub(_re(r'\s*[•▪◦]\s*'), (_) => ', ');
  t.sub(_re(r'\s*-+>\s*'), (_) => ' – ');
  t.sub(_re(r'§\s*(\d+)'), (m) {
    final n = int.parse(m[1]!);
    return n < 10000 ? 'параграф ${cardinal(n)}' : m[0]!;
  });
}

// ── църковнославянското (cs_translit.py) ─────────────────────────────────

const _acute = '́';

/// Съкращение под титла → разгънато (ударенията — от cs_translit.ABBR).
const _csAbbr = {
  'гдⷭ҇ь': 'Госпо́д',
  'гдⷭ҇и': 'Го́споди',
  'гдⷭ҇нѧ': 'Госпо́дня',
  'а́гг҃лы': 'а́нгели',
  'іи҃лѧ': 'Изра́иля',
  'првⷣными': 'пра́ведними',
  'ст҃и': 'свя́ти',
  'іерⷭ҇ли́мѣ': 'Иерусали́ме',
  'премⷣростїю': 'прему́дростию',
};

const _csLetters = {
  'ѣ': 'е', 'ы': 'и', 'ѧ': 'я', 'ꙗ': 'я', 'ѹ': 'у', 'ꙋ': 'у', 'ѡ': 'о',
  'ѻ': 'о', 'ѿ': 'от', 'і': 'и', 'ї': 'и', 'є': 'е', 'ѯ': 'кс', 'ѱ': 'пс',
  'ѳ': 'ф', 'ѵ': 'и', 'ѕ': 'з', 'ꙁ': 'з', 'ꙃ': 'з', 'ѽ': 'о', 'ѫ': 'у',
  'Ѣ': 'Е', 'Ы': 'И', 'Ѧ': 'Я', 'Ꙗ': 'Я', 'Ѹ': 'У', 'Ꙋ': 'У', 'Ѡ': 'О',
  'Ѻ': 'О', 'Ѿ': 'От', 'І': 'И', 'Ї': 'И', 'Є': 'Е', 'Ѯ': 'Кс', 'Ѱ': 'Пс',
  'Ѳ': 'Ф', 'Ѵ': 'И', 'Ѕ': 'З', 'Ꙁ': 'З', 'Ꙃ': 'З', 'Ѽ': 'О', 'Ѫ': 'У',
};

const _csStress = {'́': _acute, '̀': _acute, '̑': _acute};
const _csDrop = '҆҅'; // дишане
final _csTitlo = RegExp('[҃҇ⷠ-ⷿ]');
final _csSign = RegExp('[ѣыѧꙗѹꙋѡѻѿіїєѯѱѳѵѕꙁꙃѽѫЀ-ЏѠ-ҁ'
    'Ꙁ-ꚟ҃-҉ⷠ-ⷿ̀̑]');
final _csToken = RegExp('[A-Za-zА-Яа-яЀ-ӿꙀ-ꚟ'
    '̀-ͯ҃-҉ⷠ-ⷿ]+');
final _csMark = RegExp('[́̀̑ѐѝЀЍ]');
const _bgVowels = 'аеиоуъюяАЕИОУЪЮЯ';

/// ⚠ Python нормализира (NFC/NFD); в Dart няма нормализация — тук
/// предварително съставените ѐ/ѝ се разлагат на ръка, другото в изворите
/// е вече разложено.
String _decompose(String s) => s
    .replaceAll('ѐ', 'ѐ')
    .replaceAll('ѝ', 'ѝ')
    .replaceAll('Ѐ', 'Ѐ')
    .replaceAll('Ѝ', 'Ѝ');

String _csKey(String w) =>
    _decompose(w).split('').where((c) => !_csDrop.contains(c)).join().toLowerCase();

String _csWord(String w) {
  final k = _csKey(w);
  if (_csTitlo.hasMatch(k)) {
    // Python спира при непознато; тук — без титлата, по-добре нещо.
    final out = _csAbbr[k] ?? k.replaceAll(_csTitlo, '');
    return w.isNotEmpty && w[0] != w[0].toLowerCase()
        ? out[0].toUpperCase() + out.substring(1)
        : out;
  }
  var s = _decompose(w)
      .split('')
      .where((c) => !_csDrop.contains(c))
      .map((c) => _csStress[c] ?? c)
      .join();
  s = s.replaceAll('оу', 'у').replaceAll('Оу', 'У');
  s = s.split('').map((c) => _csLetters[c] ?? c).join();
  s = s.replaceAll('$_acute$_acute', _acute);
  if (s.endsWith('ъ')) s = s.substring(0, s.length - 1); // краен ер
  if (s.split('').where(_bgVowels.contains).length < 2) s = s.replaceAll(_acute, '');
  return s;
}

/// Всяка църковнославянска дума → с български букви. Такава е думата с
/// буква или знак, каквито българският няма, И думата с ударение до нея.
void csConvert(SpokenText t) {
  final toks = _csToken.allMatches(t.text).toList();
  if (toks.isEmpty) return;
  final cs = [
    for (final m in toks) _csSign.hasMatch(m[0]!) || m[0]!.endsWith('ъ') || m[0]!.endsWith('Ъ')
  ];
  if (!cs.contains(true)) return;
  var changed = true;
  while (changed) {
    changed = false;
    for (var i = 0; i < toks.length; i++) {
      if (cs[i] || !_csMark.hasMatch(toks[i][0]!)) continue;
      if ((i > 0 && cs[i - 1]) || (i + 1 < toks.length && cs[i + 1])) {
        cs[i] = changed = true;
      }
    }
  }
  final which = {for (var i = 0; i < toks.length; i++) if (cs[i]) toks[i].start};
  t.sub(_csToken, (m) => which.contains(m.start) ? _csWord(m[0]!) : m[0]!);
}

// ── само за гласа на телефона ────────────────────────────────────────────

/// Гласът на Google ПРЕСКАЧА дума със знак за ударение (проба, 28.10.2026).
/// Ударено „о"/„у" става латинското „ó"/„ú" — то се чете правилно; другите
/// знаци се махат. Дължината на „о́" → „ó" пада с едно, позициите се пазят.
SpokenText _forPhoneVoice(SpokenText t) {
  t.sub(RegExp('([оОуУ])[́̀̑]'), (m) => switch (m[1]) {
        'о' => 'ó',
        'О' => 'Ó',
        'у' => 'ú',
        _ => 'Ú',
      });
  t.sub(RegExp('[́̀̑]'), (_) => '');
  t.sub(RegExp('ѐ'), (_) => 'е');
  return t;
}
