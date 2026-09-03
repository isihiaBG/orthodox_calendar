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
import 'quotes_list.dart' show openBookQuote, openBibleQuote;
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

  /// ⚠ ПРИКЛЮЧИЛА ЛИ Е ПРОВЕРКАТА за начален линк.
  ///
  /// `getInitialLink` е АСИНХРОНЕН, а главният екран решава още в `initState`
  /// дали да покаже посрещането. Дотук двете се надбягваха: при по-бавен
  /// отговор екранът с избора на календар вече беше показан, а линкът
  /// пристигаше подире му — човекът засядаше там. (Докладвано от потребителя,
  /// 03.09.2026: „засядаш на първия екран с избор на календар, а този екран
  /// изобщо не бива да се вижда при външните линкове".)
  ///
  /// Затова главният екран ЧАКА това, вместо да гадае.
  static final ready = Completer<void>();

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
      // ⚠ ДВАТА ПЪТЯ СЕ ТРЕТИРАТ ЕДНАКВО — през [_pending] и изчакване.
      //
      // Първата версия отваряше веднага при работещо приложение, „защото
      // всичко е готово". Не беше: линк, натиснат докато приложението е
      // отворено, оставяше четеца на безкраен спинър. (Докладвано от
      // потребителя, 03.09.2026.)
      //
      // Разликата между двата случая е тънка и зависи от състоянието на
      // Android-ския task (виж `taskAffinity=""` в манифеста) — по-надеждно е
      // изобщо да няма два пътя. Изчакването струва един кадър и при вече
      // отворено приложение е незабележимо.
      _pending = parsed;
      if (appIsUp) {
        await openPending(navigatorKey: navigatorKey, lookup: lookup);
      }
    }

    // ⚠ ПРИ СТУДЕН СТАРТ адресът само се запазва — виж [_pending].
    try {
      final initial = await links.getInitialLink();
      if (initial != null) await handle(initial, appIsUp: false);
    } finally {
      // ⚠ ВИНАГИ, дори при грешка: главният екран чака този сигнал и без него
      // би висял на празен изглед.
      if (!ready.isCompleted) ready.complete();
    }

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
        // ⚠⚠ ВСИЧКИ ЕКРАНИ ПОД ЧЕТЕЦА СЕ РАЗРУШАВАТ (`(r) => false`).
        //
        // Човек, дошъл по линк от Viber, очаква „назад" да го върне ТАМ, а не
        // да го прекара през календара и списъка. Дотук стекът беше
        // календар → (каквото е имало) → четец, и връщането минаваше през два
        // чужди екрана, преди да излезе. (Предложение на потребителя,
        // 03.09.2026.)
        //
        // ⚠ САМО ЗА ВЪНШЕН ЛИНК. Отварянето от списъка с любими цитати е
        // обикновен `push` (виж quotes_list.dart) — там човекът е ВЪТРЕ в
        // приложението и „назад" трябва да го върне в списъка.
        //
        // ⚠ Следствие, което е приемливо: този сеанс остава само с четеца, тъй
        // че от него не се стига до календара. Приложението обаче не е
        // „заключено" — отворено наново от иконата си, то тръгва нормално.
        nav.pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) => ReaderScreen.life(
              texts: texts,
              lookup: lookup,
              openAtQuote: q,
            ),
          ),
          (route) => false,
        );
      // ⚠⚠ ПОДАВА СЕ ГОТОВИЯТ `nav`, а контекстът служи само за съобщения.
      //
      // Дотук тези два клона взимаха `navigatorKey.currentContext` и
      // разчитаха вътре на `Navigator.of(ctx)`. Но `Navigator.of` търси
      // НАГОРЕ от подадения контекст — а контекстът на самия навигатор НЕ
      // намира него. Житията (по-горе) открай време ползват
      // `currentState` и затова работеха, докато цитат от „Месецослов"
      // оставаше в календара. (Докладвано от потребителя, 03.09.2026.)
      case QuoteSource.book:
        final ctx = navigatorKey.currentContext;
        if (ctx != null) {
          // ⚠ `replaceStack` — същият довод като при житията по-горе.
          await openBookQuote(ctx, q.anchor, q.fingerprint,
              text: q.text, replaceStack: true, navigator: nav);
        }
      case QuoteSource.bible:
        final bctx = navigatorKey.currentContext;
        if (bctx != null) {
          await openBibleQuote(bctx, q.anchor, q.fingerprint,
              text: q.text, replaceStack: true, navigator: nav);
        }
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
