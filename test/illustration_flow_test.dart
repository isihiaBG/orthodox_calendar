// Деленето на текста около илюстрация — [splitFlow].
//
// ⚠⚠ ТАЗИ ФУНКЦИЯ ВЕЧЕ ДВА ПЪТИ ПРОИЗВЕДЕ ДОКЛАДВАН ДЕФЕКТ:
//   • 04.09.2026 — празнина под картинката (липсваше третият изход);
//   • 05.09.2026 — при СЪСЕДНИ размери на шрифта резултатът е коренно
//     различен: веднъж текстът обтича докрай, веднъж целият абзац слиза долу.
//
// И двата пъти окото не стигаше, защото поведението зависи от мерки, които се
// менят с шрифта. Затова проверката мете ЦЕЛИЯ обхват на размера — точно
// каквото прави човек с бутоните „−" и „+".

import 'package:flutter_test/flutter_test.dart';
import 'package:orthodox_calendar/reader_font_size.dart';
import 'package:orthodox_calendar/reader_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Двата абзаца от житието на св. Кирил Философ, с които дефектът беше
  // докладван (разговорът с агаряните за Светата Троица).
  const p1 = '<p>- Ако можеш, обясни ни как вие славите единия Бог в три, '
      'Които наричате Отец и Син и Дух! Щом така говорите, тогава остана да '
      'Му дадете и жена, та да се разплодят много богове от Него!</p>';
  const p2 = '<p>- Не говорете такива обидни хули! Ние правилно сме възприели '
      'да славим Светата Троица от пророците, отците и учителите: Отец и '
      'Слово и Дух три Ипостаси в едно Същество. А Това Слово се въплъти в '
      'Дева и се роди заради нашето спасение, както и вашият пророк Мохамед '
      'свидетелства, като написал така: "Изпратихме Нашия Дух при Девицата, '
      'понеже благоволихме тя да роди!" Аз от него ви проповядвам Светата '
      'Троица!"</p>';

  /// Всички стъпки на размера, отдолу нагоре — както ги дават бутоните.
  List<double> everyStep() {
    final out = <double>[];
    for (var v = ReaderFontSize.min; v <= ReaderFontSize.max + 0.01;
        v += ReaderFontSize.step) {
      out.add(v);
    }
    return out;
  }

  void withFontSize(double want, void Function() body) {
    // ⚠ Стойността се мени само през `nudge` — няма setter, и това е добре:
    // тестът стига до нея по същия път като бутоните.
    while (ReaderFontSize.value > want + 0.01) {
      ReaderFontSize.nudge(-ReaderFontSize.step);
    }
    while (ReaderFontSize.value < want - 0.01) {
      ReaderFontSize.nudge(ReaderFontSize.step);
    }
    body();
  }

  test('⚠⚠ НИТО ЕДИН размер не изхвърля цял абзац, който може да се среже',
      () {
    // Зона колкото средна портретна илюстрация с надпис под нея.
    const zone = 520.0;
    const colWidth = 300.0;

    for (final size in everyStep()) {
      withFontSize(size, () {
        final (beside, below) = splitFlow('$p1\n$p2', zone, colWidth);

        expect(beside.trim(), isNotEmpty,
            reason: 'при $size зоната остава ПРАЗНА');

        if (below.trim().isEmpty) return; // всичко се е побрало — добре

        // ⚠ ТОВА Е СЪЩИНАТА. Слезе ли нещо долу, то трябва да е
        // ПРОДЪЛЖЕНИЕ на срязан абзац, а не цял абзац, изхвърлен нацяло.
        expect(below.trimLeft(), startsWith('<p class="contflow">'),
            reason: 'при $size цял абзац е слязъл долу, вместо да се среже — '
                'точно това прави празнината до картинката');
      });
    }
  });

  test('⚠ съседните размери не дават КОРЕННО различен резултат', () {
    const zone = 520.0;
    const colWidth = 300.0;

    final beside = <double, int>{};
    for (final size in everyStep()) {
      withFontSize(size, () {
        final (b, _) = splitFlow('$p1\n$p2', zone, colWidth);
        // Броим ЗНАЦИТЕ на видимия текст, без таговете.
        beside[size] = b.replaceAll(RegExp(r'<[^>]+>'), '').length;
      });
    }

    // При по-едър шрифт до картинката се събира по-малко текст — това е
    // естествено. Скокът обаче трябва да е ПЛАВЕН: рязко пропадане значи, че
    // някъде сме паднали от другата страна на праг.
    final sizes = beside.keys.toList()..sort();
    for (var i = 1; i < sizes.length; i++) {
      final prev = beside[sizes[i - 1]]!, cur = beside[sizes[i]]!;
      if (prev == 0) continue;
      expect(cur, greaterThan(prev * 0.45),
          reason: 'между ${sizes[i - 1]} и ${sizes[i]} текстът до картинката '
              'пада от $prev на $cur знака — това е ръб, не наклон');
    }
  });

  test('⚠ липсващ край на изречение не изхвърля абзаца долу', () {
    // Абзац без нито една точка — дотук такъв слизаше ЦЯЛ под картинката,
    // защото разрезът се търсеше само по край на изречение.
    final longP = '<p>${'дума ' * 200}</p>';
    withFontSize(22.0, () {
      final (beside, below) = splitFlow('$p1\n$longP', 520.0, 300.0);
      expect(beside.trim(), isNotEmpty);
      if (below.trim().isNotEmpty) {
        expect(below.trimLeft(), startsWith('<p class="contflow">'),
            reason: 'реже се по ДУМА, щом изречение няма');
      }
    });
  });
}
