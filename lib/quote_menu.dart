// „Запази цитат" в контекстното меню при маркиране на текст.
//
// ⚠ ОБЩО ЗА ТРИТЕ ЧЕТЕЦА — жития, книги, Библия. Всеки от тях вече обгръща
// скрола си в `SelectionArea`; тук тя се заменя с [QuotableSelectionArea],
// която прави същото плюс още един бутон в изскачащото меню.
//
// Наученото в този проект е, че първата разлика между преписани на две места
// неща минава тихо (виж `kReaderMenuItems` в reader_more_menu.dart — менюто
// зад трите точки беше преписано и в книгите липсваше точката за PDF, не по
// решение, а по недоглеждане). Затова тук е един клас, а не образец за
// копиране.

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import 'quote_capture.dart';
import 'quote_link.dart';
import 'quotes.dart';
import 'reader_theme.dart';
import 'selection_toolbar.dart';

/// Обгръща съдържанието в `SelectionArea` и добавя „Запази цитат".
///
/// Данните за четивото се подават като ФУНКЦИИ, не като стойности: и в трите
/// четеца отвореното се сменя, без widget-ът да се пресъздава (смяна на
/// глава, на стих, на превод). Подадени наготово, те щяха да остареят тихо —
/// същият капан като „уловено при построяване състояние остарява", описан за
/// библейския четец в CLAUDE.md.
class QuotableSelectionArea extends StatefulWidget {
  final Widget child;

  /// Откъде е цитатът и как се адресира четивото — виж [QuoteSource].
  final QuoteSource source;
  final String Function() locator;
  final String Function() title;

  /// Обикновеният текст на блоковете, в реда на четене.
  final List<String> Function() blocks;

  /// Индексът на блока с БУКВИЦА, или -1 — виж [captureSelection].
  final int Function()? dropCapBlock;

  /// ⚠⚠ КЛЮЧЪТ НА ВСЕКИ БЛОК — с него се познава КОЙ блок е под селекцията.
  ///
  /// Без този ориентир [captureSelection] намира ПЪРВОТО срещане на
  /// маркирания текст в цялото четиво. За дълъг откъс това е безобидно (той
  /// се среща веднъж), но за къс — не: „година" се среща петнайсет пъти в
  /// житието на св. Кирил Философ, тъй че маркираното дълбоко в текста се
  /// запазваше като първото горе, и оттам нататък ВСИЧКО беше последователно
  /// сгрешено — и линкът, и осветяването.
  /// (Докладвано от потребителя, 05.09.2026.)
  ///
  /// ⚠ ОРИЕНТИРЪТ Е САМАТА СЕЛЕКЦИЯ, не „най-горният видим ред". Второто е
  /// по-лесно, но е приблизително: на един екран може да има две срещания и
  /// човекът да е маркирал второто. `SelectableRegion` знае къде точно стои
  /// селекцията (`contextMenuAnchors` — точките, около които се строи самото
  /// меню), тъй че се пита тя.
  ///
  /// ⚠ Достатъчна е ТОЧНОСТ ДО БЛОК. Вътре в блока мястото се оценява по
  /// дела от височината му — груба сметка, но в един абзац едно и също късо
  /// съвпадение рядко стои повече от веднъж-дваж, а вече знаем кой е абзацът.
  ///
  /// `null` за блок, който в момента не е построен (мързелив списък) — той се
  /// прескача, а селекцията и без това е на екрана, тоест блокът ѝ е построен.
  final GlobalKey? Function(int index)? blockKey;

  /// Замества извеждания адрес — виж [buildQuote]. Ползва се от Библията,
  /// където числата значат стих и отрязване, а не абзац и знак.
  final QuoteAnchor Function(CapturedSpot spot, List<String> blocks)? anchorOf;

  /// Замества [title], когато то зависи от МАРКИРАНОТО, а не само от четивото.
  ///
  /// ⚠ Ползва се от Библията: там надписът под цитата е стандартната съкратена
  /// препратка („Мат. 3:15"), а тя иска да се знае докъде стига откъсът —
  /// нещо, което [title] няма откъде да разбере, защото се вика без данни.
  final String Function(CapturedSpot spot, List<String> blocks)? titleOf;

  const QuotableSelectionArea({
    super.key,
    required this.child,
    required this.source,
    required this.locator,
    required this.title,
    required this.blocks,
    this.dropCapBlock,
    this.blockKey,
    this.anchorOf,
    this.titleOf,
  });

  @override
  State<QuotableSelectionArea> createState() => _QuotableSelectionAreaState();
}

class _QuotableSelectionAreaState extends State<QuotableSelectionArea> {
  String? _selected;

  /// Сглобява цитат от текущата селекция, или `null`, ако не се улови.
  Quote? _quoteFromSelection(SelectableRegionState region) {
    final text = _selected?.trim();
    if (text == null || text.isEmpty) return null;
    final blocks = widget.blocks();
    final spot = captureSelection(blocks, text,
        dropCapBlock: widget.dropCapBlock?.call() ?? -1,
        hint: _hintFor(region, blocks));
    if (spot == null) return null;
    return buildQuote(
      source: widget.source,
      locator: widget.locator(),
      title: widget.titleOf?.call(spot, blocks) ?? widget.title(),
      blocks: blocks,
      spot: spot,
      anchor: widget.anchorOf?.call(spot, blocks),
    );
  }

  /// Къде на екрана стои селекцията, преведено в (блок, знак).
  ///
  /// ⚠ Взима се СРЕДАТА между двете котви на менюто, а не горната: горната
  /// стои НАД началото на селекцията и при откъс, започващ на първия ред на
  /// абзац, пада в предишния. Средата е вътре в селекцията по определение, а
  /// за къс откъс двете котви са на един ред и средата е точно върху него.
  ///
  /// ⚠ Не намери ли блок ПОД точката, взима се най-близкият, вместо да се
  /// върне `null`: тихият отказ е най-скъпият вид отказ в този проект
  /// (платен вече няколко пъти — виж CLAUDE.md), а тук цената му е връщане
  /// към стария бъг с първото срещане.
  (int, int)? _hintFor(SelectableRegionState region, List<String> blocks) {
    final keyOf = widget.blockKey;
    if (keyOf == null || blocks.isEmpty) return null;

    final anchors = region.contextMenuAnchors;
    final top = anchors.primaryAnchor;
    final bottom = anchors.secondaryAnchor ?? top;
    final y = (top.dy + bottom.dy) / 2;

    int? bestBlock;
    var bestGap = double.infinity;
    var bestFrac = 0.0;
    for (var i = 0; i < blocks.length; i++) {
      final ctx = keyOf(i)?.currentContext;
      if (ctx == null) continue;
      final box = ctx.findRenderObject();
      if (box is! RenderBox || !box.hasSize || !box.attached) continue;
      final boxTop = box.localToGlobal(Offset.zero).dy;
      final h = box.size.height;
      final gap = y < boxTop
          ? boxTop - y
          : (y > boxTop + h ? y - (boxTop + h) : 0.0);
      if (gap < bestGap) {
        bestGap = gap;
        bestBlock = i;
        bestFrac = h <= 0 ? 0.0 : ((y - boxTop) / h).clamp(0.0, 1.0);
      }
      if (gap == 0) break;
    }
    if (bestBlock == null) return null;
    return (bestBlock, (bestFrac * blocks[bestBlock].length).round());
  }

  /// ⚠ ЗАМЕСТВА системното „Сподели", което праща гол текст.
  ///
  /// Навън тръгва самият цитат в кавички, източникът и ЛИНК, който отваря
  /// приложението право на мястото — виж [quoteShareText]. Смисълът е, че
  /// получателят вижда откъса в контекста му, а не изваден от нищото.
  /// (Описано от потребителя, 02.09.2026.)
  Future<void> _share(SelectableRegionState region) async {
    final q = _quoteFromSelection(region);
    region.hideToolbar();
    if (!mounted) return;
    if (q == null) {
      _tell('Маркирай откъс в рамките на един абзац');
      return;
    }
    await Share.share(quoteShareText(q));
  }

  Future<void> _save(SelectableRegionState region) async {
    final text = _selected?.trim();
    if (text == null || text.isEmpty) {
      region.hideToolbar();
      return;
    }

    // ⚠ ОРИЕНТИРЪТ СЕ ВЗИМА ПРЕДИ СКРИВАНЕТО НА МЕНЮТО. Той се смята от
    // котвите, около които менюто е построено (`contextMenuAnchors`) — тоест
    // от живата селекция. Скрито първо, менюто отнася и тях, а грешката би
    // била тиха: цитатът пак се запазва, само че на първото срещане, тъй че
    // изглежда сякаш поправката изобщо не е направена.
    final blocks = widget.blocks();
    final hint = _hintFor(region, blocks);

    // Менюто се скрива ПРЕДИ останалата работа: инак стои на екрана, докато
    // съобщението изскача под него.
    region.hideToolbar();

    final spot = captureSelection(blocks, text,
        dropCapBlock: widget.dropCapBlock?.call() ?? -1,
        hint: hint);
    if (!mounted) return;
    if (spot == null) {
      // ⚠ Случва се при маркиране ПРЕЗ няколко блока: селекцията носи текст,
      // какъвто нито един блок не съдържа цял. Казва се направо, вместо да
      // се запази нещо приблизително — човекът стои пред текста и може да
      // маркира наново.
      _tell('Маркирай откъс в рамките на един абзац');
      return;
    }

    final q = buildQuote(
      source: widget.source,
      locator: widget.locator(),
      title: widget.titleOf?.call(spot, blocks) ?? widget.title(),
      blocks: blocks,
      spot: spot,
      anchor: widget.anchorOf?.call(spot, blocks),
    );
    await QuotesStore.add(q);
    if (!mounted) return;
    _tell('Цитатът е запазен');
  }

  void _tell(String message) {
    final palette = ReaderTheme.palette;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message, style: TextStyle(color: palette.ink)),
        backgroundColor: palette.sheet,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ));
  }

  @override
  Widget build(BuildContext context) {
    return SelectionArea(
      onSelectionChanged: (content) => _selected = content?.plainText,
      contextMenuBuilder: (context, region) {
        // ⚠ Стандартните бутони се ВЗИМАТ от региона, не се пресъздават:
        // те се менят според платформата и според това какво е маркирано.
        // [IconSelectionToolbar] после ги разделя по вид — познатите стават
        // иконки отпред, платформените отиват зад трите точки.
        return IconSelectionToolbar(
          anchors: region.contextMenuAnchors,
          items: region.contextMenuButtonItems,
          onSaveQuote: () => _save(region),
          onShareQuote: () => _share(region),
        );
      },
      child: widget.child,
    );
  }
}
