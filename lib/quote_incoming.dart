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

import 'database_helper.dart';
import 'quote_link.dart';
import 'quotes.dart';
import 'quotes_list.dart' show openBookQuote;
import 'reader_screen.dart';
import 'saint_expandable_tile.dart' show SaintLookup;

/// Слуша за входящи линкове към цитати и ги отваря.
///
/// Пуска се веднъж, от корена на приложението.
class IncomingQuoteLinks {
  static StreamSubscription<Uri>? _sub;

  /// ⚠ ЛИНК, КОЙТО ЧАКА ПРИЛОЖЕНИЕТО ДА СЕ ВДИГНЕ.
  ///
  /// При студен старт адресът пристига ПРЕДИ да има какво да го поеме:
  /// навигаторът още не е построен, а базата не е отворена. Първата версия
  /// отваряше четеца веднага и той оставаше на безкраен спинър — четивото
  /// се искаше от база, която още се копира от assets.
  /// (Докладвано от потребителя, 03.09.2026.)
  ///
  /// Затова адресът само се ЗАПАЗВА тук, а главният екран го поема, щом е
  /// готов — виж [takePending].
  static ParsedQuoteLink? _pending;

  /// Има ли чакащ линк. Гледа се и от началния екран: при отваряне по линк
  /// изборът на календар се ПРОПУСКА — човекът е дошъл да види цитат в
  /// контекст, а не да настройва приложението. (Искане на потребителя.)
  static bool get hasPending => _pending != null;

  /// Взима чакащия линк и го забравя.
  static ParsedQuoteLink? takePending() {
    final p = _pending;
    _pending = null;
    return p;
  }

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

    Future<void> handle(Uri uri, {required bool appIsUp}) async {
      final parsed = parseQuoteLink(uri);
      // Непознат адрес — не е наша работа. Мълчи: Android вече е решил да го
      // даде на нас, но ако не го разбираме, по-добре нищо, отколкото да
      // отворим наслуки.
      if (parsed == null) return;
      if (appIsUp) {
        await _open(navigatorKey, lookup, parsed);
      } else {
        _pending = parsed;
      }
    }

    // ⚠ ПРИ СТУДЕН СТАРТ адресът само се запазва — виж [_pending].
    final initial = await links.getInitialLink();
    if (initial != null) await handle(initial, appIsUp: false);

    // Докато приложението върви, всичко е готово и линкът се отваря веднага.
    await _sub?.cancel();
    _sub = links.uriLinkStream.listen((u) => handle(u, appIsUp: true));
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
        final ctx = navigatorKey.currentContext;
        if (ctx != null && ctx.mounted) {
          await openBookQuote(ctx, q.anchor, q.fingerprint);
        }
      case QuoteSource.bible:
        // ⚠ Още не се споделят цитати оттам. Мълчаливото нищо е по-добре от
        // отваряне на грешно място.
        return;
    }
  }

  /// Отваря чакащия линк, ако има такъв. Вика се от главния екран, СЛЕД
  /// като той е построен и базата е отворена.
  static Future<void> openPending({
    required GlobalKey<NavigatorState> navigatorKey,
    required SaintLookup lookup,
  }) async {
    final p = takePending();
    if (p == null) return;

    // ⚠ БАЗАТА СЕ ИЗЧАКВА ИЗРИЧНО. При студен старт тя се копира от assets
    // (десетки мегабайта) и `lookup` би висял, докато това стане — а четецът
    // дотогава показва спинър, който отвън изглежда като забиване.
    // Изчакването тук е ПРЕДИ отварянето, тъй че екранът се появява готов.
    try {
      await DatabaseHelper.database;
    } catch (_) {
      // Не успя — по-добре нищо, отколкото четец, който никога няма да се
      // напълни. Човекът вижда календара и може да опита пак.
      return;
    }
    await _open(navigatorKey, lookup, p);
  }

  /// Спира слушането — при затваряне на приложението.
  static Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
  }
}
