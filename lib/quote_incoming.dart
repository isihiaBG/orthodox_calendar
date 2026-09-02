// Линк към цитат, отворен ОТВЪН — от Viber, WhatsApp, браузър.
//
// ⚠ Android доставя такъв линк по ДВА различни начина и двата са нужни:
//
//   • приложението е ЗАТВОРЕНО → адресът идва като „начален" при пускане
//     (`getInitialLink`), веднъж;
//   • приложението е ОТВОРЕНО → адресът идва като събитие в потока
//     (`uriLinkStream`), докато то върви.
//
// Пропусне ли се вторият, линк, натиснат докато приложението е на заден
// план, просто го изважда отпред, без да отиде никъде — и изглежда счупен.
//
// ⚠ ЗА ДА СТИГНЕ ДОТУК ЛИНКЪТ, трябват и трите неща от CLAUDE.md
// („Споделяне на цитати навън"): intent-filter с autoVerify, файлът
// `assetlinks.json` в КОРЕНА на домейна, и съвпадащи package name + подпис.
// Липсва ли което и да е, Android тихо отваря браузъра и този код никога не
// се вика.

import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';

import 'quote_link.dart';
import 'quotes.dart';
import 'reader_screen.dart';
import 'saint_expandable_tile.dart' show SaintLookup;

/// Слуша за входящи линкове към цитати и ги отваря.
///
/// Пуска се веднъж, от корена на приложението.
class IncomingQuoteLinks {
  static StreamSubscription<Uri>? _sub;

  /// [navigatorKey] — навигаторът на приложението.
  ///
  /// ⚠ Ключ, а НЕ `BuildContext`: линкът може да дойде когато си иска, а
  /// контекст, уловен при пускането, отдавна е разрушен. Същият капан вече е
  /// платен веднъж — виж `_openBible` в app_drawer.dart, където проверката
  /// `context.mounted` след `await` мълчаливо отказваше отварянето.
  static Future<void> start({
    required GlobalKey<NavigatorState> navigatorKey,
    required SaintLookup lookup,
  }) async {
    final links = AppLinks();

    Future<void> handle(Uri uri) async {
      final parsed = parseQuoteLink(uri);
      // Непознат адрес — не е наша работа. Мълчи: Android вече е решил да го
      // даде на нас, но ако не го разбираме, по-добре нищо, отколкото да
      // отворим наслуки.
      if (parsed == null) return;
      await _open(navigatorKey, lookup, parsed);
    }

    // Приложението е било затворено.
    final initial = await links.getInitialLink();
    if (initial != null) await handle(initial);

    // Приложението върви.
    await _sub?.cancel();
    _sub = links.uriLinkStream.listen(handle);
  }

  static Future<void> _open(
    GlobalKey<NavigatorState> navigatorKey,
    SaintLookup lookup,
    ParsedQuoteLink q,
  ) async {
    final nav = navigatorKey.currentState;
    if (nav == null) return;

    switch (q.anchor.source) {
      case QuoteSource.life:
        final texts = await lookup(q.anchor.locator);
        if (texts == null) {
          // Слъгът не съществува в тази версия на базата — четивото е
          // преименувано или още не е добавено.
          final ctx = navigatorKey.currentContext;
          if (ctx != null && ctx.mounted) {
            ScaffoldMessenger.of(ctx).showSnackBar(
              const SnackBar(content: Text('Това четиво го няма в календара.')),
            );
          }
          return;
        }
        nav.push(MaterialPageRoute(
          builder: (_) => ReaderScreen.life(
            texts: texts,
            lookup: lookup,
            openAtQuote: q,
          ),
        ));
      case QuoteSource.book:
      case QuoteSource.bible:
        // ⚠ Още не се споделят цитати оттам, тъй че такъв линк може да дойде
        // само от бъдеща версия. Мълчаливото нищо е по-добре от отваряне на
        // грешно място.
        return;
    }
  }

  /// Спира слушането — при затваряне на приложението.
  static Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
  }
}
