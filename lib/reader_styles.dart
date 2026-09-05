// reader_styles.dart
//
// Стиловете за flutter_html при четене — ОБЩИ за житията/службите
// (reader_screen.dart) и за книгите от „Месецослов" (book_reader.dart).
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
    // ПРОДЪЛЖЕНИЕТО на абзац, разрязан от обтичащата илюстрация.
    //
    // ⚠ БЕЗ отстъп отгоре: това е СЪЩИЯТ абзац, който просто минава под
    // картинката, а не нов. С обичайните полета на `<p>` между двете
    // половини зее празнина и текстът се чете като прекъснат.
    // Виж `_splitFlow` в reader_screen.dart.
    '.contflow': Style(
      fontFamily: kBodyFamily,
      fontSize: FontSize(fontSize),
      lineHeight: const LineHeight(kReaderLineHeight),
      margin: Margins.only(top: 0, bottom: 8),
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
      fontFamilyFallback: kTitleFallback,
      fontSize: FontSize(fontSize + 12),
      lineHeight: const LineHeight(1.05),
      fontWeight: FontWeight.normal,
      textAlign: TextAlign.center,
      // bottom се управлява от отстоянието заглавие → текст в четеца
      margin: Margins.only(top: 18, bottom: 0),
      color: ink,
    ),
    // Заглавието на заглавната страница („ЖИТИЯ / на / СВЕТИИТЕ").
    //
    // Идва от .epub-а като инлайн стил, но book_reader._normalize го сваля и
    // слага този клас. Причината е, че числата в книгата са нагласени по
    // ОБИКНОВЕН четец, а flutter_html мери другояче: при тамошното
    // междуредие 0.62 „на" опира в „СВЕТИИТЕ". Тук стоят числата за
    // приложението, а книгата остава непокътната за четците отвън.
    //
    // По-светло от `ink`, за да излиза напред — на заглавна страница то е
    // главното, а под него всичко е второстепенно.
    //
    // Размерът е МНОЖИТЕЛ, не добавка: така заглавието расте и намалява
    // заедно с бутоните + / − и съотношението му спрямо текста остава
    // същото при всяка стъпка. С „fontSize + 30" то следваше бутоните, но
    // при дребен шрифт изглеждаше огромно, а при едър — сбито.
    '.booktitle': Style(
      fontFamily: kTitleFamily,
      fontFamilyFallback: kTitleFallback,
      fontSize: FontSize(fontSize * 3.3),
      lineHeight: const LineHeight(0.80),
      // ⚠ ПОВДИГАНЕ НА СРЕДНИЯ РЕД НЕ Е ВЪЗМОЖНО в приложението. При
      // еднакъв кегел „на" е с x-височина, а съседите му с главни букви, тъй
      // че стои ниско в реда си. В .epub-а това се изравнява с
      // `position: relative; top: -0.12em` и в обикновен четец излиза точно.
      // Тук — не: flutter_html не поддържа `position`, вложени горни индекси
      // не се сумират, а полета (нито отрицателни, нито положителни) не се
      // прилагат на тези елементи. И трите са пробвани на 15.08.2026; не си
      // хаби времето наново.
      margin: Margins.only(bottom: 28),
      color: palette.dark
          ? const Color(0xFFFFFAF0)
          : const Color(0xFF000000),
    ),
    // Гол <div>. В житията от базата такъв няма изобщо — идва от .epub-ите
    // на „Месецослов", където заглавната страница на тома е построена от
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
    // Кратко сведение на собствен ред, в скоби: „(† 14 февруари 869
    // година)", „(Превод от гръцки от Синаксара…)".
    //
    // ⚠ ЦЕНТРИРАН, за разлика от [.caption]. Двата приличат по вид (курсив,
    // приглушено, с една степен по-дребно), но играят различна роля:
    // надписът принадлежи на КАРТИНКАТА над себе си и затова е подравнен
    // вляво под нея, а това стои самостоятелно като подзаглавен ред и
    // центрирането го отделя от разказа.
    //
    // ⚠ Долният отстъп е по-малък от [.memorydate] (26): там редът въвежда
    // цялото житие, тук е бележка вътре в него.
    // ЕПИГРАФ — цитат, с който започва житието (стар препис, свидетелство),
    // преди самия разказ.
    //
    // ⚠ НЕ Е центриран, за разлика от `.centernote`: епиграфът е дълъг
    // (в житието на свщмч. Симеон Самоковски е 888 знака) и центриран би
    // изглеждал като разкъсан текст. Отличава се с отстъп отляво и
    // приглушен цвят; курсивът идва от самия `<em>` в извора.
    //
    // ⚠ Класът има и ВТОРА работа, по-скрита: `splitDropCap` търси ГОЛ
    // `<p>`, тъй че абзац с клас сам прескача буквицата — а тя трябва да
    // падне върху първите думи на РАЗКАЗА, не върху цитата преди него.
    // (Същият похват като при `.memorydate`.)
    '.epigraph': Style(
      fontFamily: kBodyFamily,
      fontSize: FontSize(fontSize - 1),
      color: dim,
      padding: HtmlPaddings.only(left: 16),
      margin: Margins.only(top: 4, bottom: 14),
    ),
    // БЕЛЕЖКАТА ПОД ЕПИГРАФА — откъде е цитатът, с който започва житието.
    //
    // ⚠ ДЯСНО подравнена, не центрирана, и с размера на САМИЯ цитат.
    // Центрирана и с една степен по-едра, тя се четеше като ПОДЗАГЛАВИЕ на
    // разказа, а не като приписка към цитата над нея. (Бележка на
    // потребителя, 05.09.2026.)
    //
    // ⚠ Отделен клас от `.centernote` нарочно: той се ползва от
    // `tools/lives_bg` за бележките за източник и там центрирането е
    // вярното.
    // БЕЛЕЖКА ЗА ИЗТОЧНИКА, дошла ОТ САМИЯ ИЗВОР („Историческа справка: …",
    // „Снимки: …"). Изглежда като нашата атрибуция, но е ДРУГ клас:
    // `source` е запазен за реда, който слага приложението НАКРАЯ, и
    // PDF-ът спира на него.
    '.credit': Style(
      fontFamily: kBodyFamily,
      fontSize: FontSize(fontSize - 2),
      fontStyle: FontStyle.italic,
      color: dim,
      margin: Margins.only(top: 18, bottom: 4),
    ),
    '.epigraphnote': Style(
      fontFamily: kBodyFamily,
      fontSize: FontSize(fontSize - 1),
      color: dim,
      textAlign: TextAlign.right,
      padding: HtmlPaddings.only(right: 16),
      margin: Margins.only(top: 2, bottom: 16),
    ),
    '.centernote': Style(
      fontFamily: kBodyFamily,
      fontSize: FontSize(fontSize - 1),
      fontStyle: FontStyle.italic,
      color: dim,
      textAlign: TextAlign.center,
      margin: Margins.only(top: 6, bottom: 14),
    ),
    // Надписът под илюстрация („Св. Прохор Пшински. Стенопис от ХV в. в
    // църквата…").
    //
    // Той е СВЕДЕНИЕ ЗА ИЗОБРАЖЕНИЕТО, не част от разказа, и трябва да се
    // чете като такъв от пръв поглед: курсив и приглушено, с една степен
    // по-дребно от текста.
    //
    // ⚠ НЕ Е центриран — нарочно, по решение на потребителя (30.08.2026).
    // Центрирането го прави да изглежда като заглавие на следващия раздел;
    // подравнен вляво, той стои като бележка към картинката над него.
    //
    // ⚠ Размерът е `-1`, не по-малко: под това надписът престава да се чете
    // удобно при най-дребната настройка на четеца, а той носи истинско
    // сведение (къде се намира стенописът, от коя година е).
    // ⚠ ЦИТАТЪТ, заради който четивото е отворено — от списъка с любими или
    // от споделен линк. Синьо, а НЕ жълтото на търсенето: двете значат
    // различни неща и могат да се появят едновременно („намерено сега"
    // срещу „това поиска да видиш"). Цветът е същият [ReaderPalette.quote],
    // с който библейският четец бележи поисканите стихове — един смисъл,
    // един цвят през цялото приложение.
    '.quotehit': Style(backgroundColor: palette.quote),
    '.caption': Style(
      fontFamily: kBodyFamily,
      fontSize: FontSize(fontSize - 1),
      fontStyle: FontStyle.italic,
      color: dim,
      textAlign: TextAlign.left,
      // Долепя се към картинката отгоре, а под него остава повече въздух —
      // така окото го чете заедно с нея, а не като начало на следващия абзац.
      margin: Margins.only(top: 2, bottom: 16),
    ),
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
    // Препратките към бележки под линия. В томовете от „Месецослов" те са
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
