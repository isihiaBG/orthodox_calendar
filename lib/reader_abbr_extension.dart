// reader_abbr_extension.dart
//
// Колоната със съкращенията в „Справочник" → „Съкращения":
//
//     <p class="abbr"><abbrk>мч.</abbrk> мъченик</p>
//
// Съкращението стои в кутия с ЕДНАКВА ширина, тъй че обясненията започват
// от една и съща вертикала — като подравнени с Tab (искане на потребителя).
// flutter_html няма таблици без допълнителен пакет, а и такава не трябва:
// един ред е един абзац.
//
// ⚠ PDF-ът не знае за таговете — маха го и редът излиза „мч. мъченик",
// което се чете също толкова добре.
//
// ⚠ Подравняване ПО БАЗОВА ЛИНИЯ, както горния индекс
// (reader_sup_extension.dart): `TagExtension` слага кутията където реши и
// съкращението сяда по-високо или по-ниско от обяснението до него.
library;

import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';

import 'reader_font_size.dart';

/// Ширината на колоната — в дялове от кегела. Най-дългите съкращения
/// („равноапп.", „свщмчч.") се побират с въздух; при −/+ колоната расте
/// заедно с буквите.
const double kAbbrKeyWidth = 5.6;

class ReaderAbbrExtension extends HtmlExtension {
  const ReaderAbbrExtension();

  @override
  Set<String> get supportedTags => {'abbrk'};

  @override
  InlineSpan build(ExtensionContext context) {
    return WidgetSpan(
      alignment: PlaceholderAlignment.baseline,
      baseline: TextBaseline.alphabetic,
      child: SizedBox(
        width: ReaderFontSize.value * kAbbrKeyWidth,
        child: CssBoxWidget.withInlineSpanChildren(
          children: context.inlineSpanChildren!,
          style: context.styledElement!.style,
        ),
      ),
    );
  }
}
