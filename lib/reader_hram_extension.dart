// reader_hram_extension.dart
//
// Църквицата пред църковната дата — знакът от живите дати
// (`<hram></hram>`, виж church_dates.dart).
//
// ⚠⚠ ЗАЩО Е СОБСТВЕНО РАЗШИРЕНИЕ, А НЕ `TagExtension` С ГОЛ WIDGET.
//
// `TagExtension` увива върнатото в `WidgetSpan` по СВОЙ избор, а тогава
// вертикалното място зависи от обкръжението: в сказанието за Великден
// същият знак излизаше НАД реда (той стои вътре във връзка), а в статията
// за празниците — ПОД него. Един и същи код, два различни резултата.
// (Докладвано от потребителя със снимки, 20.09.2026.)
//
// Тук спанът се строи на ръка с `PlaceholderAlignment.baseline`, тъй че
// долният ръб на кутията ляга на базовата линия НЕЗАВИСИМО от контекста —
// същият похват като при горния индекс (reader_sup_extension.dart).
//
// ⚠⚠ ЧИСЛАТА СА ИЗВЕДЕНИ ОТ САМИЯ ИКОНЕН ШРИФТ, не от око:
//
//     MaterialIcons     ascent 1,000 em, descent 0
//                       → базовата линия Е долният ръб на кутията
//     глифът „църква"   стои от 0,084 до 0,959 em
//                       → видимата височина е 0,875 × размера,
//                         а дъното ѝ виси 0,084 × размера над кутията
//     Charis SIL        цифрата е 0,687 em, главната буква — 0,671
//
// Оттам и двете константи по-долу.
library;

import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';

import 'reader_font_size.dart';

/// Размерът на иконата — в дялове от кегела.
///
/// ⚠ Видимата църква излиза 0,875 × това, тоест 0,753 от кегела — с около
/// една десета по-висока от цифрата (0,687). Знакът се чете като малко
/// подчертана главна буква, а не като картинка насред изречението.
///
/// ⚠⚠ ПРОПОРЦИОНАЛНО, А НЕ „кегел + 2". Шрифтът се мени от бутоните −/+
/// (13 до 30), а постоянна добавка прави знака относително по-едър при
/// дребния шрифт и по-дребен при едрия. (Бележка на потребителя.)
const double kHramSize = 0.86;

/// Колко виси видимото дъно на глифа над кутията му — от шрифта, не на око.
const double _kHramGlyphGap = 0.084;

/// Оптичен въздух ПОД знака, в дялове от кегела. Нула значи „стъпва точно
/// на базовата линия", както всеки друг глиф.
const double kHramRaise = 0.0;

/// Височината на кутията — в дялове от кегела.
///
/// ⚠⚠ ТЯ НЕ РЕШАВА КЪДЕ СТОИ ЗНАКЪТ (това го прави подравняването по
/// базовата линия), а САМО дали редът ще се разпъне. Държи се под
/// възходящата част на шрифта (~0,75 em), тъй че редовете СЪС знак остават
/// високи колкото останалите.
const double _kHramBox = 0.72;

class ReaderHramExtension extends HtmlExtension {
  const ReaderHramExtension(this.fallbackColor);

  /// Цветът, ако обкръжението не казва свой.
  final Color fallbackColor;

  @override
  Set<String> get supportedTags => {'hram'};

  @override
  InlineSpan build(ExtensionContext context) {
    final f = ReaderFontSize.value;
    final draw = f * kHramSize;
    // ⚠ Цветът се наследява: вътре във връзка (живите дати в сказанието за
    // Великден са линкове към календара) знакът трябва да е в цвета на
    // връзката, инак стои като чуждо тяло насред нея.
    final color = context.styledElement?.style.color ?? fallbackColor;
    return WidgetSpan(
      alignment: PlaceholderAlignment.baseline,
      baseline: TextBaseline.alphabetic,
      child: Padding(
        padding: EdgeInsets.only(right: f * 0.12),
        child: SizedBox(
          width: draw,
          height: f * _kHramBox,
          child: OverflowBox(
            // ⚠ Долният ръб, не средата: центрирано, мястото зависи от
            // разликата между кутията и рисунката.
            alignment: Alignment.bottomCenter,
            maxWidth: draw,
            maxHeight: draw * 2,
            child: Transform.translate(
              // Смъква глифа с точно толкова, с колкото той сам виси над
              // кутията си — тогава видимото дъно ляга на базовата линия.
              offset: Offset(0, draw * _kHramGlyphGap - f * kHramRaise),
              child: Icon(Icons.church, size: draw, color: color),
            ),
          ),
        ),
      ),
    );
  }
}
