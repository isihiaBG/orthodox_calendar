// reader_sup_extension.dart
//
// Как се рисува горен индекс (<sup>) при четене — ОБЩО за двата четеца.
//
// Защо изобщо е нужно:
//
// Номерът на бележка се явява на ДВЕ различни места, рисувани от различни
// неща — началото на четивото минава през буквицата (ръчен Text.rich, за
// да има истинско обтичане), а останалото през flutter_html. Ако двамата
// повдигат различно, номерът подскача насред житието: в началото стои
// правилно, а по-нататък пада надолу.
//
// Точно това се случваше. Вграденото правило на пакета
// (VerticalAlignBuiltIn) вдига знака с fontSize / -2.5, но НЕ задава
// подравняване на запълнителя и остава подразбиращото се „по долен ръб".
// При по-дребен шрифт долният ръб е по-високо от базовата линия, тъй че
// видимо номерът сяда по-ниско, отколкото трябва.
//
// Тук същото се прави с подравняване ПО БАЗОВА ЛИНИЯ и със същия
// коефициент като в drop_cap.dart, за да съвпаднат двата начина.

import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';

/// Колко от размера на текста да се вдигне горният индекс.
/// Същата стойност се ползва и в drop_cap.dart — ако се промени тук,
/// трябва да се промени и там, иначе номерът пак ще подскача.
const double kSupRaise = 0.34;

class ReaderSupExtension extends HtmlExtension {
  const ReaderSupExtension();

  @override
  Set<String> get supportedTags => {'sup'};

  @override
  InlineSpan build(ExtensionContext context) {
    final style = context.styledElement!.style;
    // Размерът идва от правилото за „sup" в reader_styles.dart. Ако по
    // някаква причина липсва, се пада към разумно смаляване, вместо да се
    // рисува наравно с текста.
    final size = style.fontSize?.value ?? 12.0;
    return WidgetSpan(
      alignment: PlaceholderAlignment.baseline,
      baseline: TextBaseline.alphabetic,
      child: Transform.translate(
        offset: Offset(0, -size / 0.62 * kSupRaise),
        child: CssBoxWidget.withInlineSpanChildren(
          children: context.inlineSpanChildren!,
          style: style,
        ),
      ),
    );
  }
}
