// floating_illustration.dart
//
// Илюстрация с ОБТИЧАЩ текст — полиграфският похват, приложен в четеца.
//
// ## Защо изобщо
//
// В ИЗПРАВЕНО положение картинката на цял ред изглежда добре: колоната е
// тясна и изображението я запълва. В ЛЕГНАЛО обаче същият похват оставя
// широки празни петна от двете страни — редът е дълъг, а картинката не го
// запълва. Затова там текстът обтича изображението отстрани.
//
// ⚠ Flutter НЯМА `float`. `WidgetSpan` слага widget инлайн, но текстът
// продължава СЛЕД него, вместо да го обтича отстрани. Единственият път е
// ръчно мерене с [TextPainter] и рязане на текста на две части: тясна (до
// картинката) и пълна (под нея). Същият механизъм като при буквицата — виж
// [DropCapParagraph], откъдето е взет и този подход.
//
// ## Шахматната подредба
//
// Първата илюстрация застава ВЛЯВО, втората — ВДЯСНО, третата пак вляво.
// Редуването се задава отвън ([side]), защото само повикващият знае коя по
// ред е картинката в четивото.
//
// ## Рамката и подравняването
//
// ⚠ ВЪНШНИЯТ отстъп е НУЛА. Картинка вляво се долепя до лявото поле на
// текста, картинка вдясно — до дясното. Еднакъв отстъп от всички страни
// изглежда безобиден, но измества изображението спрямо текстовата колона и
// окото веднага усеща разминаването: нито ръбът на картинката, нито ръбът
// на текста стоят на една линия.
//
// Отстъп има само откъм ВЪТРЕШНАТА страна (към текста) и отдолу.

import 'package:flutter/material.dart';

/// От коя страна застава илюстрацията.
enum IllustrationSide { left, right }

/// Разстоянието между илюстрацията и обтичащия я текст.
///
/// ⚠ Само от вътрешната страна. Виж бележката за рамката най-горе.
const double kIllustrationGap = 16;

/// Въздухът под блока (картинка + надпис), преди текстът да мине на пълна
/// ширина.
const double kIllustrationBottomGap = 12;

/// От колко налична ширина нагоре текстът обтича илюстрацията.
///
/// ⚠ ПО ШИРИНА, а не по ориентация — по изрична бележка на потребителя
/// (30.08.2026), и той е прав: таблет в ИЗПРАВЕНО положение често има
/// повече пиксели от телефон в легнало. Реши ли се по `Orientation`,
/// таблетът остава с широки празни петна около картинката точно в
/// положението, в което най-много се чете.
///
/// Числото идва от сметка, не на око: илюстрацията взима
/// [kIllustrationWidthFactor] (0.38), тъй че на текста остават около 0.58 от
/// ширината. За да е четима, тясната колона трябва да побира поне ~30 знака
/// на ред, тоест около 300 dp — оттам 300 / 0.58 ≈ 520. Закръглено нагоре до
/// 560, за да не се задейства на ръба.
const double kIllustrationFloatMinWidth = 560;

/// Над това съотношение (ширина/височина) картинката НЕ се свива встрани, а
/// заема целия ред.
///
/// ⚠ По бележка на потребителя (31.08.2026): широката илюстрация, набутана в
/// 38% от реда, губи всичко — тя е панорамна сцена, а не портрет. По-добре е
/// да се покаже в пълния си размер, а текстът да мине над и под нея.
///
/// 1.15 е малко над квадрата: портретните и почти квадратните обтичат,
/// пейзажните заемат реда.
const double kIllustrationFullWidthAspect = 1.15;

/// ТАВАН за ширината на обтичаща илюстрация — дял от наличния ред.
///
/// ⚠ Таван Е НУЖЕН, въпреки че основата е размерът от изправено положение.
/// На таблет късата страна е около 800, тъй че без него картинката би заела
/// ~59% от реда и текстовата колона до нея би станала по-тясна от самата
/// картинка. Проверено с числа преди пускане (31.08.2026).
const double kIllustrationWidthFactor = 0.45;

/// ДОЛНА граница — дял от наличния ред.
///
/// ⚠ Без нея на много широк екран картинката остава с размера си от
/// изправено (напр. 320 dp при 1300 dp ред) и се губи.
const double kIllustrationMinWidthFactor = 0.30;

/// Ширината на обтичащата илюстрация.
///
/// ⚠ ОСНОВАТА Е `shortestSide` — късата страна на екрана, тоест ширината,
/// която устройството има в ИЗПРАВЕНО положение. Тя НЕ се мени при
/// завъртане, а оттам и височината на картинката е известна предварително.
/// Точно това липсваше на първия подход (дял от текущата ширина): при всяко
/// завъртане картинката се преоразмеряваше, а `SliverVariedExtentList`
/// заковава височината на региона ПРЕДИ рисуването — оценката гонеше
/// движеща се цел и текстът преливаше върху изображението.
///
/// Идея на потребителя (31.08.2026): една и съща илюстрация да изглежда
/// еднакво едра в двете положения, а текстовата колона да е предвидима.
///
/// ⚠ На по-широк екран картинката СЕ РАЗТЯГА — иначе на таблет остава
/// неоправдано дребна. Оттам долната граница по дял от реда.
double illustrationFlowWidth({
  required double availableWidth,
  required double shortestSide,
  required double pageInset,
}) {
  final portraitWidth = shortestSide - pageInset;
  final floor = availableWidth * kIllustrationMinWidthFactor;
  final ceiling = availableWidth * kIllustrationWidthFactor;
  // Никога по-широка от дела, който оставя четима колона за текста.
  return portraitWidth.clamp(floor, ceiling > floor ? ceiling : floor);
}

/// Илюстрация с надпис, около която текстът се обтича.
///
/// Приема ГОТОВИ spans (не гол текст), за да работят маркирането при
/// търсене и вътрешните връзки — точно както при [DropCapParagraph].
class FloatingIllustration extends StatelessWidget {
  /// Пътят до изображението в `assets/`.
  final String imageAsset;

  /// Надписът под илюстрацията. null = няма такъв.
  final InlineSpan? caption;

  /// Отляво или отдясно застава.
  final IllustrationSide side;

  /// Съотношението на изображението (ширина / височина), от атрибутите в
  /// текста. ⚠ Без него мястото не може да се резервира предварително — виж
  /// [LivesImageExtension].
  final double aspect;

  /// Текстът, който обтича илюстрацията.
  final List<InlineSpan> spans;

  /// Основният стил — от него се смятат редовете.
  final TextStyle baseStyle;

  final TextScaler scaler;

  const FloatingIllustration({
    super.key,
    required this.imageAsset,
    required this.side,
    required this.aspect,
    required this.spans,
    required this.baseStyle,
    this.caption,
    this.scaler = TextScaler.noScaling,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final full = constraints.maxWidth;
        final imgW = full * kIllustrationWidthFactor;
        final imgH = aspect > 0 ? imgW / aspect : imgW;

        // Височината на целия блок: картинка + надпис под нея.
        double captionH = 0;
        if (caption != null) {
          final tp = TextPainter(
            text: caption!,
            textDirection: TextDirection.ltr,
            textScaler: scaler,
          )..layout(maxWidth: imgW);
          captionH = tp.height;
          tp.dispose();
        }
        final blockH = imgH + (captionH > 0 ? captionH + 4 : 0);

        // Ширината на колоната до илюстрацията.
        final narrowW = full - imgW - kIllustrationGap;

        // ── Къде да се среже текстът ──────────────────────────────────
        //
        // ⚠ Мери се със СЪЩИЯ стил и същата ширина, с която после ще се
        // рисува. Различие тук се вижда като текст, който не съвпада с
        // мястото си — същият капан като при буквицата.
        final probe = TextPainter(
          text: TextSpan(style: baseStyle, children: spans),
          textDirection: TextDirection.ltr,
          textScaler: scaler,
          textAlign: TextAlign.justify,
        )..layout(maxWidth: narrowW);

        // Докъде стига текстът, докато картинката още го стеснява.
        final cutPos = probe.getPositionForOffset(
          Offset(narrowW, blockH + kIllustrationBottomGap),
        );
        final cut = cutPos.offset;
        probe.dispose();

        final plain = _plainOf(spans);
        final hasTail = cut > 0 && cut < plain.length;

        final narrowSpans = _sliceSpans(spans, 0, hasTail ? cut : plain.length);
        final tailSpans = hasTail ? _sliceSpans(spans, cut, plain.length) : null;

        final block = SizedBox(
          width: imgW,
          child: Column(
            crossAxisAlignment: side == IllustrationSide.left
                ? CrossAxisAlignment.start
                : CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                imageAsset,
                width: imgW,
                height: imgH,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
              if (caption != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: SizedBox(
                    // ⚠ Надписът е ТОЧНО колкото илюстрацията, не колкото
                    // колоната: той принадлежи на нея, не на страницата.
                    width: imgW,
                    child: Text.rich(caption!, textAlign: TextAlign.left),
                  ),
                ),
            ],
          ),
        );

        final textColumn = Expanded(
          child: Text.rich(
            TextSpan(style: baseStyle, children: narrowSpans),
            textAlign: TextAlign.justify,
          ),
        );

        // ⚠ Отстъпът е САМО от вътрешната страна — външният ръб на
        // илюстрацията ляга точно на полето на текста.
        final padded = Padding(
          padding: EdgeInsets.only(
            left: side == IllustrationSide.right ? kIllustrationGap : 0,
            right: side == IllustrationSide.left ? kIllustrationGap : 0,
            bottom: kIllustrationBottomGap,
          ),
          child: block,
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: side == IllustrationSide.left
                  ? [padded, textColumn]
                  : [textColumn, padded],
            ),
            if (tailSpans != null)
              Text.rich(
                TextSpan(style: baseStyle, children: tailSpans),
                textAlign: TextAlign.justify,
              ),
          ],
        );
      },
    );
  }

  /// Голият текст на набор spans — за дължините при рязането.
  static String _plainOf(List<InlineSpan> spans) {
    final b = StringBuffer();
    for (final s in spans) {
      s.visitChildren((span) {
        if (span is TextSpan && span.text != null) b.write(span.text);
        return true;
      });
    }
    return b.toString();
  }

  /// Парче от spans по индекси в ГОЛИЯ текст.
  ///
  /// ⚠ Реже вътре в span, когато границата пада по средата му — инак
  /// оформлението (получер, връзка) би прескочило на грешна дума.
  static List<InlineSpan> _sliceSpans(
      List<InlineSpan> spans, int from, int to) {
    final out = <InlineSpan>[];
    var pos = 0;
    for (final s in spans) {
      if (s is! TextSpan || s.text == null) {
        // Не-текстов span (напр. WidgetSpan) — влиза цял, ако е в обхвата.
        if (pos >= from && pos < to) out.add(s);
        continue;
      }
      final text = s.text!;
      final start = pos;
      final end = pos + text.length;
      pos = end;
      if (end <= from || start >= to) continue;
      final a = (from - start).clamp(0, text.length);
      final b = (to - start).clamp(0, text.length);
      if (a >= b) continue;
      out.add(TextSpan(
        text: text.substring(a, b),
        style: s.style,
        recognizer: s.recognizer,
      ));
    }
    return out;
  }
}
