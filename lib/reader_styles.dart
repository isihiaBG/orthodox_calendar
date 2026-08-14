// reader_styles.dart
//
// Стиловете за flutter_html при четене — ОБЩИ за житията/службите
// (reader_screen.dart) и за книгите от „Читанка" (book_reader.dart).
//
// Изнесено от reader_screen.dart. Класовете (.csl, .trans, .prayerhead,
// .source, .dropcap…) идват от самите текстове в базите и в .epub-ите, тъй
// че двата четеца трябва да ги рисуват ЕДНАКВО — иначе едно и също житие
// би изглеждало различно според това откъде е отворено.
//
// Функцията е чиста: получава размер и палитра, връща картата. Няма
// състояние и не знае нищо за светии, книги или екрани.

import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';

import 'reader_theme.dart';

/// [strongInWine] — дали <strong> да е в виненочервено вместо мастилено.
/// В службата този таг носи богослужебните указания („На велицей вечерни",
/// „стихиры, глас 2", „Подобен:") и по традиция се пише в червено; в
/// житието същият таг е обикновено ударение.
Map<String, Style> readerStyles({
  required double fontSize,
  required ReaderPalette palette,
  bool strongInWine = false,
}) {
  final ink = palette.ink;
  final dim = palette.dim;
  final wine = palette.wine;

  return {
    // flutter_html обвива съдържанието в имплицитни <html> и <body> с
    // браузърни подразбирания за margin/padding. Тях ги нулираме, за да
    // ляга HTML текстът точно на същата ширина като първия абзац (той се
    // рендва ръчно в DropCapParagraph и няма такива отстъпи).
    'html': Style(margin: Margins.zero, padding: HtmlPaddings.zero),
    'body': Style(margin: Margins.zero, padding: HtmlPaddings.zero),
    'p': Style(
      fontFamily: kBodyFamily,
      fontSize: FontSize(fontSize),
      lineHeight: const LineHeight(kReaderLineHeight),
      margin: Margins.only(top: 8, bottom: 8),
      textAlign: TextAlign.justify,
      color: ink,
    ),
    // Двете кутии около буквицата: като обикновен абзац, но без полета —
    // отстоянията там се мерят в редове и се задават отвън.
    '.dropcap': Style(
      fontFamily: kBodyFamily,
      fontSize: FontSize(fontSize),
      lineHeight: const LineHeight(kReaderLineHeight),
      margin: Margins.zero,
      padding: HtmlPaddings.zero,
      textAlign: TextAlign.justify,
      color: ink,
    ),
    '.dropcap-rest': Style(
      fontFamily: kBodyFamily,
      fontSize: FontSize(fontSize),
      lineHeight: const LineHeight(kReaderLineHeight),
      margin: Margins.only(top: 2),
      padding: HtmlPaddings.zero,
      textAlign: TextAlign.justify,
      color: ink,
    ),
    // Заглавието на четивото. Едро и СТЕГНАТО: при междуредието на текста
    // (1.25) по-дългите заглавия се разсипват на разредени редове, вместо да
    // стоят като един надпис. Числата са общи за двата четеца — същите носи
    // и заглавието, което reader_screen рисува със свой Text.
    'h3': Style(
      fontFamily: kTitleFamily,
      fontSize: FontSize(fontSize + 12),
      lineHeight: const LineHeight(1.05),
      fontWeight: FontWeight.normal,
      textAlign: TextAlign.center,
      // bottom се управлява от отстоянието заглавие → текст в четеца
      margin: Margins.only(top: 18, bottom: 0),
      color: ink,
    ),
    // Гол <div>. В житията от базата такъв няма изобщо — идва от .epub-ите
    // на „Читанка", където заглавната страница на тома е построена от
    // <div>-ове вместо от абзаци. Без това правило те се рисуват със
    // системния шрифт и подразбиращия се цвят, тъй че единствената
    // страница, която е чиста типография, изглежда чужда на книгата.
    'div': Style(
      fontFamily: kBodyFamily,
      fontSize: FontSize(fontSize),
      color: ink,
    ),
    'strong': Style(color: strongInWine ? wine : ink),
    '.csl': Style(
      fontFamily: kBodyFamily,
      fontSize: FontSize(fontSize + 0.5),
      lineHeight: const LineHeight(1.3),
      color: ink,
    ),
    '.prayerhead': Style(
      fontFamily: kBodyFamily,
      fontSize: FontSize(fontSize + 1),
      fontWeight: FontWeight.w600,
      margin: Margins.only(top: 18, bottom: 4),
      color: wine,
    ),
    '.trans': Style(
      fontFamily: kBodyFamily,
      fontSize: FontSize(fontSize - 1),
      fontStyle: FontStyle.italic,
      color: dim,
      margin: Margins.only(bottom: 16),
    ),
    '.translabel': Style(
      fontWeight: FontWeight.w600,
      fontStyle: FontStyle.normal,
      color: dim,
    ),
    '.source': Style(
      fontFamily: kBodyFamily,
      fontSize: FontSize(fontSize - 2),
      fontStyle: FontStyle.italic,
      color: dim,
      margin: Margins.only(top: 24),
    ),
    // Курсивен абзац, пропуснат за буквица — центриран.
    '.italic-center': Style(textAlign: TextAlign.center),
    // Редът с паметта в началото на житие („Памет на 1 септември").
    //
    // Той е указание кога се чества светията, не част от разказа, затова
    // стои отделно и не носи буквицата. Оформен е като ПОДЗАГЛАВИЕ:
    // центриран, близо до заглавието отгоре и с ясно поле към текста
    // отдолу — така окото го чете заедно със заглавието, а не като първи
    // ред на житието.
    '.memorydate': Style(
      fontFamily: kBodyFamily,
      fontSize: FontSize(fontSize - 1),
      fontStyle: FontStyle.italic,
      color: dim,
      textAlign: TextAlign.center,
      margin: Margins.only(top: 2, bottom: 26),
    ),
    // Линковете следват ТЕМАТА НА ЧЕТЕЦА, не тази на приложението: на
    // светлия кремав фон синьото на секциите избледнява (виж palette.link).
    'a': Style(
      color: palette.link,
      textDecoration: TextDecoration.none,
    ),
    // Препратките към бележки под линия. В томовете от „Читанка" те са
    // <sup> вътре в <a>, а flutter_html не ги повдига и не ги смалява сам —
    // без това правило номерът стои наравно с текста и се чете като част
    // от изречението („Декий1690").
    'sup': Style(
      fontSize: FontSize(fontSize * 0.62),
      verticalAlign: VerticalAlign.sup,
    ),
    // Маркиране на съвпаденията от търсенето.
    '.hit': Style(backgroundColor: palette.hit),
    '.hit-current': Style(backgroundColor: palette.hitCurrent),
  };
}
