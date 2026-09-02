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

import 'quote_capture.dart';
import 'quotes.dart';
import 'reader_theme.dart';

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

  const QuotableSelectionArea({
    super.key,
    required this.child,
    required this.source,
    required this.locator,
    required this.title,
    required this.blocks,
    this.dropCapBlock,
  });

  @override
  State<QuotableSelectionArea> createState() => _QuotableSelectionAreaState();
}

class _QuotableSelectionAreaState extends State<QuotableSelectionArea> {
  String? _selected;

  Future<void> _save(SelectableRegionState region) async {
    final text = _selected?.trim();
    // Менюто се скрива ПРЕДИ работата: инак стои на екрана, докато
    // съобщението изскача под него.
    region.hideToolbar();
    if (text == null || text.isEmpty) return;

    final spot = captureSelection(widget.blocks(), text,
        dropCapBlock: widget.dropCapBlock?.call() ?? -1);
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
      title: widget.title(),
      blocks: widget.blocks(),
      spot: spot,
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
        // „Копирай", „Сподели", „Избери всичко" се менят според платформата и
        // според това какво е маркирано.
        final items = [...region.contextMenuButtonItems];
        items.add(ContextMenuButtonItem(
          onPressed: () => _save(region),
          label: 'Запази цитат',
        ));
        return AdaptiveTextSelectionToolbar.buttonItems(
          anchors: region.contextMenuAnchors,
          buttonItems: items,
        );
      },
      child: widget.child,
    );
  }
}
