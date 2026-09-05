// Устойчивостта на адресирането на цитат.
//
// ⚠ Тези проверки пазят единственото, което НЕ БИВА да се счупи: споделен
// линк да отвежда на ВЯРНОТО място дори когато текстът е бил редактиран,
// след като линкът е бил пратен. Виж докстринга на `lib/quotes.dart`.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:orthodox_calendar/quote_capture.dart';
import 'package:orthodox_calendar/quote_link.dart';
import 'package:orthodox_calendar/quotes.dart';

void main() {
  const block = 'Свети Иоан Рилски бил роден в село Скрино. Още от млади години '
      'той възлюбил Бога и оставил всичко земно, за да Му служи. '
      'Подвизавал се в Рилската пустиня четиридесет години.';

  group('сглобяване и разчитане', () {
    test('линкът се разчита обратно до същия адрес', () {
      const q = Quote(
        anchor: QuoteAnchor(
          source: QuoteSource.life,
          locator: 'sv-ioan-rilski',
          block: 12,
          charStart: 43,
          charLength: 60,
        ),
        text: 'Още от млади години той възлюбил Бога',
        title: 'Св. Иоан Рилски',
        savedAtMs: 0,
      );
      final link = buildQuoteLink(q);
      expect(link, startsWith('https://isihiabg.github.io/orthodox_calendar/q/'));
      // ⚠ Адресът трябва да е КЪС: кирилицата в обикновен параметър го
      // раздуваше над 230 знака.
      expect(link.length, lessThan(200), reason: 'long адрес в чата пълзи');

      // ⚠ ЦЕЛТА НА ВЕРСИЯ 3 Е ДЪЛЖИНАТА. Житийният адрес беше 156 знака и
      // потребителят го отхвърли като „никак естетичен"; сега е около 70.
      expect(link.length, lessThan(90), reason: 'long адрес в чата пълзи');

      final p = parseQuoteLink(Uri.parse(link))!;
      expect(p.anchor.source, QuoteSource.life);
      expect(p.anchor.block, 12);
      expect(p.anchor.charStart, 43);
      expect(p.anchor.charLength, 60);
      expect(p.fingerprint, fingerprint(q.text),
          reason: 'отпечатъкът пътува като свое поле, но за достатъчно дълъг '
              'цитат стойността е същата, каквато е била винаги');

      // ⚠ СЛЪГЪТ СЕ СВИВА ДО ОТПЕЧАТЪК — 28 знака стават 4 байта. Обратно се
      // разгъва чак при отваряне, срещу базата (виж [resolveQuoteLocator]),
      // затова тук стои МАРКЕР, а не самият слъг.
      expect(p.anchor.locator, '${kLocatorMarker}${locatorFingerprint('sv-ioan-rilski')}');
      expect(p.text, isEmpty,
          reason: 'от версия 3 откъсът изобщо не пътува — целият цитат и без '
              'това стои в самото съобщение, над линка');
    });

    test('⚠ версия 2 носи КРАЯ на цитата — дотук го нямаше изобщо', () {
      // Точно този пропуск режеше всеки споделен цитат през няколко абзаца
      // до първия от тях.
      const q = Quote(
        anchor: QuoteAnchor(
          source: QuoteSource.life,
          locator: 'sv-x',
          block: 3,
          charStart: 10,
          charLength: 40,
          blockEnd: 6,
          charEnd: 25,
        ),
        text: 'първи абзац\n\nвтори абзац\n\nтрети абзац докрай',
        title: 'нещо',
        savedAtMs: 0,
      );
      final p = parseQuoteLink(Uri.parse(buildQuoteLink(q)))!;
      expect(p.anchor.block, 3);
      expect(p.anchor.blockEnd, 6);
      expect(p.anchor.charEnd, 25);
    });

    test('⚠ версия 1 продължава да се чете (вече споделени адреси)', () {
      // Пакетът е сглобен на ръка по СТАРИЯ ред на полетата.
      final packed = _packV1([
        '1', 'life', '12', '43', '60', 'sv-ioan-rilski',
        'Още от млади години той възлюбил Бога',
      ]);
      final p = parseQuoteLink(
          Uri.parse('https://isihiabg.github.io/orthodox_calendar/q/$packed'))!;
      expect(p.anchor.locator, 'sv-ioan-rilski');
      expect(p.anchor.block, 12);
      expect(p.anchor.charStart, 43);
      expect(p.anchor.charLength, 60);
      // Краят се извежда, както е било: начало + дължина, в същия блок.
      expect(p.anchor.blockEnd, 12);
      expect(p.anchor.charEnd, 103);
      // Отпечатъкът се извежда от текста, защото свое поле е нямало.
      expect(p.fingerprint,
          fingerprint('Още от млади години той възлюбил Бога'));
      expect(p.anchor.occurrence, 0, reason: 'версия 1 не носи пореден номер');
    });

    test('дълъг цитат се отрязва, но линкът остава разчетим', () {
      final long = Quote(
        anchor: const QuoteAnchor(
            source: QuoteSource.life, locator: 'sv-x', block: 1,
            charStart: 0, charLength: 400),
        text: 'дума ' * 80,
        title: 'нещо',
        savedAtMs: 0,
      );
      final p = parseQuoteLink(Uri.parse(buildQuoteLink(long)))!;
      expect(p.text.length, lessThanOrEqualTo(kLinkTextChars));
      expect(p.anchor.charLength, 400, reason: 'координатите са пълни');
    });

    test('непозната бъдеща версия се отхвърля, не се гадае', () {
      // Пакет с версия 99 — сглобен на ръка.
      final u = Uri.parse('https://isihiabg.github.io/orthodox_calendar/q/'
          '${base64Url.encode(utf8.encode("99|life|0|0|5|x|текст")).replaceAll("=", "")}');
      expect(parseQuoteLink(Uri.parse('https://x/q/r${u.path.substring(3)}')), isNull);
    });

    test('чужд път не се разпознава', () {
      final u = Uri.parse('https://isihiabg.github.io/about/abc');
      expect(parseQuoteLink(u), isNull);
    });

    test('повреден пакет не гърми, а се отказва', () {
      expect(parseQuoteLink(Uri.parse('https://x/q/rЩЕ-НЕ-Е-BASE64')), isNull);
      expect(parseQuoteLink(Uri.parse('https://x/q/')), isNull);
    });
  });

  group('намиране в текста', () {
    const quote = 'Още от млади години той възлюбил Бога';
    final print_ = fingerprint(quote);
    final exactAt = block.indexOf(quote);

    test('намира на точното място', () {
      final hit = locateQuote(block, exactAt, quote.length, print_);
      expect(hit.kind, QuoteHitKind.exact);
      expect(hit.start, exactAt);
    });

    test('⚠ намира и след като текстът е бил разместен от редакция', () {
      // Точно случаят, срещу който е направено всичко: дума пред цитата е
      // заменена с по-дълга и всички индекси след нея са се преместили.
      final edited = block.replaceFirst('в село Скрино',
          'в село Скрино, Дупнишко (по преданието)');
      final moved = edited.indexOf(quote);
      expect(moved, isNot(exactAt), reason: 'редакцията наистина мести');

      final hit = locateQuote(edited, exactAt, quote.length, print_);
      expect(hit.kind, QuoteHitKind.shifted);
      expect(hit.start, moved, reason: 'намерен е ИСТИНСКИЯТ нов индекс');
    });

    test('⚠ пунктуация и главни букви не пречат', () {
      final repunct = block
          .replaceFirst('Още от млади години', 'Още — от млади години,')
          .replaceFirst('възлюбил', 'Възлюбил');
      final hit = locateQuote(repunct, exactAt, quote.length, print_);
      expect(hit.kind, isNot(QuoteHitKind.byCoordinates),
          reason: 'сгъването маха точно тези разлики');
    });

    test('липсващ текст → чисто по координати, без гадаене', () {
      final hit = locateQuote(
          block, 10, 20, fingerprint('съвсем друг текст, какъвто тук няма'));
      expect(hit.kind, QuoteHitKind.byCoordinates);
      expect(hit.start, 10, reason: 'отваря се точно каквото сочат числата');
    });

    test('⚠ КЪС цитат („а") НЕ получава отпечатък изобщо', () {
      // Доводът на потребителя: сподели ли човек една буква, отпечатъкът не
      // различава нищо — а при редактиран текст би отвел до НАЙ-БЛИЗКОТО
      // съвпадение, тоест по-далеч от истината, отколкото координатите.
      expect(fingerprint('а'), isEmpty);
      final hit = locateQuote(block, 55, 1, fingerprint('а'));
      expect(hit.kind, QuoteHitKind.byCoordinates);
      expect(hit.start, 55, reason: 'координатите командват безусловно');
    });

    test('⚠ границата е по СГЪНАТАТА дължина, не по суровата', () {
      // „и рече му" е 9 знака сурово, но само 7 сгънато — под прозореца.
      expect(fingerprint('и рече му'), isEmpty);
      final hit = locateQuote(block, 7, 9, fingerprint('и рече му'));
      expect(hit.kind, QuoteHitKind.byCoordinates);
    });

    test('⚠ отпечатъкът е ХЕШ — къс и без кирилица в адреса', () {
      final fp = fingerprint(quote);
      expect(fp.length, 8, reason: 'осем шестнайсетични знака');
      expect(RegExp(r'^[0-9a-f]{8}$').hasMatch(fp), isTrue,
          reason: 'кирилица в URL се кодира по шест знака на буква');
    });

    test('⚠ при няколко съвпадения печели НАЙ-БЛИЗКОТО до подсказката', () {
      // Достатъчно дълъг, за да получи отпечатък (над прозореца).
      const repeated = 'и рече му с тихи думи на самия праг';
      final twice = 'Тогава $repeated едно. '
          'После мина доста време и стана съвсем друго. '
          'Накрая $repeated второ.';
      final secondAt = twice.lastIndexOf(repeated);

      final hit = locateQuote(
          twice, secondAt, repeated.length, fingerprint(repeated));
      expect(hit.start, secondAt,
          reason: 'първото съвпадение в текста би отвело далеч от мястото');
    });
  });

  group('улавяне на селекция', captureTests);
  group('буквицата', dropCapTests);
  group('фонът под цитата', wrapTests);
  group('текстът за споделяне', shareTests);
  group('дълъг цитат', longQuoteTests);
  group('маркиране върху истински HTML', wrapRealTests);
  group('координатите на wrapQuoteByText', coordinateBugTests);
  group('отрязването в линка', linkTruncationTests);
  group('разделителят в данните', separatorTests);
  group('четимият адрес за Писанието', bibleLinkTests);
  group('цялата верига за Писанието', bibleChainTests);
  group('поредното съвпадение', occurrenceTests);
  group('двоичният пакет (версия 3)', v3Tests);
}

// ── улавяне на селекция ──────────────────────────────────────────────────
//
// ⚠ Тук се проверява ОБРАТНАТА посока: от маркиран текст към координати.
// Тя трябва да е огледална на locateQuote(), инак цитатът се запазва на
// едно място, а се отваря на друго.

void captureTests() {
  const blocks = [
    'Свети Иоан Рилски бил роден в село Скрино.',
    'Още от млади години той възлюбил Бога и оставил всичко земно.',
    'Подвизавал се в Рилската пустиня четиридесет години.',
  ];

  test('намира в кой блок е маркираното и на кой знак', () {
    final spot = captureSelection(blocks, 'той възлюбил Бога')!;
    expect(spot.block, 1);
    expect(blocks[1].substring(spot.charStart, spot.charStart + spot.charLength),
        'той възлюбил Бога');
  });

  test('⚠ дължината се мери в СУРОВИЯ текст, не в сгънатия', () {
    // Между „млади" и „Бога" стоят интервали, които сгъването изхвърля —
    // мерена там, дължината би излязла по-къса и осветяването би отрязало.
    final spot = captureSelection(blocks, 'млади години той възлюбил')!;
    final cut = blocks[1]
        .substring(spot.charStart, spot.charStart + spot.charLength);
    expect(cut, 'млади години той възлюбил');
  });

  test('пунктуация в селекцията не пречи', () {
    final spot = captureSelection(blocks, 'в село Скрино.')!;
    expect(spot.block, 0);
  });

  test('текст, който го няма, не се запазва наслуки', () {
    expect(captureSelection(blocks, 'съвсем друго изречение'), isNull);
  });

  test('⚠ уловеното се отваря на СЪЩОТО място', () {
    // Кръгът, който трябва да е затворен: улавяме, сглобяваме цитат,
    // после го намираме наново — както би станало при отваряне на линк.
    final spot = captureSelection(blocks, 'оставил всичко земно')!;
    final q = buildQuote(
      source: QuoteSource.life,
      locator: 'sv-ioan-rilski',
      title: 'Св. Иоан Рилски',
      blocks: blocks,
      spot: spot,
    );
    final hit = locateQuote(
        blocks[q.anchor.block], q.anchor.charStart, q.anchor.charLength,
        fingerprint(q.text));
    expect(hit.kind, QuoteHitKind.exact);
    expect(hit.start, q.anchor.charStart);
    expect(q.text, 'оставил всичко земно');
  });
}

// ── буквицата ────────────────────────────────────────────────────────────
//
// ⚠ Инициалът се рисува с отделен `Text` в `Stack` (drop_cap.dart) и е ИЗВЪН
// текстовия поток. Оттам две несиметрични последици, които се проявяват
// заедно и се маскират взаимно:
//   • селекцията ГО ВКЛЮЧВА  → връща „Свети Иоан…"
//   • текстът на блока го НЯМА → съдържа „вети Иоан…"
// Резултатът беше отказ „маркирай в рамките на един абзац" за всяко първо
// изречение. (Докладвано от потребителя, 02.09.2026.)

void dropCapTests() {
  // Както четецът ги подава СЛЕД поправката: буквицата е в блока.
  const blocks = [
    'Свети Иоан Рилски бил роден в село Скрино.',
    'Още от млади години той възлюбил Бога.',
  ];

  test('⚠ селекция С буквицата се улавя от началото', () {
    final spot =
        captureSelection(blocks, 'Свети Иоан Рилски', dropCapBlock: 0)!;
    expect(spot.block, 0);
    expect(spot.charStart, 0, reason: 'цитатът започва от буквицата');
    expect(blocks[0].substring(spot.charStart, spot.charStart + spot.charLength),
        'Свети Иоан Рилски');
  });

  test('⚠ селекция БЕЗ буквицата се разширява назад до нея', () {
    // Ако Flutter върне текста без инициала — цитатът пак трябва да е цял.
    final spot = captureSelection(blocks, 'вети Иоан Рилски', dropCapBlock: 0)!;
    expect(spot.charStart, 0, reason: 'първата буква се връща обратно');
  });

  test('⚠ в ОБИКНОВЕН абзац разширяване НЕ се прави', () {
    // Там човек може да маркира нарочно от втората буква и добавянето на
    // чужда буква отпред би било грешка.
    final spot = captureSelection(blocks, 'ще от млади', dropCapBlock: 0);
    expect(spot, isNotNull);
    expect(spot!.block, 1);
    expect(blocks[1].substring(spot.charStart, spot.charStart + spot.charLength),
        'ще от млади');
  });
}

// ── фонът под цитата ─────────────────────────────────────────────────────

void wrapTests() {
  test('обгражда точния диапазон', () {
    const html = '<p>Свети Иоан бил роден в Скрино.</p>';
    final out = wrapRangeHtml(html, 6, 4, 'q');
    expect(out, contains('<span class="q">Иоан</span>'));
  });

  test('⚠ диапазон ПРЕЗ таг се обгражда на части', () {
    // Един span през целия диапазон би обхванал чуждото </em> и
    // flutter_html би оцветил остатъка от абзаца.
    const html = '<p>и <em>рече</em> му</p>';
    final out = wrapRangeHtml(html, 0, 8, 'q');
    // „и ", „рече", „ му" — три парчета гол текст между таговете, тъй че
    // и span-овете са три. Един общ би обхванал чуждото </em>.
    expect('<span class="q">'.allMatches(out).length, 3);
    expect('</span>'.allMatches(out).length, 3, reason: 'всеки се затваря');
    // ⚠ Span-ът стои ВЪТРЕ в <em>, не го обхваща: така курсивът остава
    // курсив, а фонът не изтича извън диапазона.
    expect(out, contains('<em><span class="q">рече</span></em>'));
    // Целият текст оцелява, само с добавени span-ове.
    expect(out.replaceAll(RegExp(r'</?span[^>]*>'), ''), html);
  });

  test('извън обхвата не пипа нищо', () {
    const html = '<p>кратко</p>';
    expect(wrapRangeHtml(html, 100, 5, 'q'), html);
    expect(wrapRangeHtml(html, 0, 0, 'q'), html);
  });
}

// ── текстът за споделяне ─────────────────────────────────────────────────

void shareTests() {
  const q = Quote(
    anchor: QuoteAnchor(
      source: QuoteSource.life,
      locator: 'sv-ioan-rilski',
      block: 3,
      charStart: 10,
      charLength: 24,
    ),
    text: 'Още от млади години той възлюбил Бога',
    title: 'Житие на св. Иоан Рилски',
    savedAtMs: 0,
  );

  test('видът е: цитат, източник, покана, линк', () {
    final lines = quoteShareText(q).split('\n');
    expect(lines.first, '„Още от млади години той възлюбил Бога"');
    expect(lines, contains('— из „Житие на св. Иоан Рилски"'));
    expect(lines, contains('Чети в контекст:'));
    expect(lines.last, startsWith('https://isihiabg.github.io/orthodox_calendar/q/'));
  });

  test('⚠ линкът е на СОБСТВЕН ред — чатовете го правят кликаем', () {
    final lines = quoteShareText(q).split('\n');
    expect(lines.last, startsWith('https://'));
    expect(lines.last.contains(' '), isFalse, reason: 'нищо друго на реда');
  });

  test('без заглавие редът за източника отпада', () {
    const noTitle = Quote(
      anchor: QuoteAnchor(
          source: QuoteSource.life, locator: 'x', block: 0,
          charStart: 0, charLength: 5),
      text: 'нещо',
      title: '',
      savedAtMs: 0,
    );
    expect(quoteShareText(noTitle), isNot(contains('— из')));
  });

  test('⚠ споделеното се разчита обратно', () {
    // Кръгът, който трябва да е затворен: линкът от споделянето води на
    // същото място, откъдето е тръгнал.
    final link = quoteShareText(q).split('\n').last;
    final parsed = parseQuoteLink(Uri.parse(link))!;
    expect(parsed.anchor.locator,
        '${kLocatorMarker}${locatorFingerprint('sv-ioan-rilski')}');
    expect(parsed.anchor.block, 3);
    expect(parsed.anchor.charStart, 10);
    expect(parsed.fingerprint, fingerprint(q.text));
  });
}

// ── дълъг цитат ──────────────────────────────────────────────────────────

void longQuoteTests() {
  Quote make(String text) => Quote(
        anchor: const QuoteAnchor(
            source: QuoteSource.life, locator: 'sv-x', block: 0,
            charStart: 0, charLength: 10),
        text: text,
        title: 'Житие',
        savedAtMs: 0,
      );

  test('къс цитат: „Чети в контекст"', () {
    expect(quoteShareText(make('кратък откъс от текста')),
        contains('Чети в контекст:'));
  });

  test('⚠ дълъг цитат: съкратен и „Виж продължението"', () {
    final t = quoteShareText(make('дума ' * 200));
    expect(t, contains('Виж продължението:'));
    expect(t, contains('…"'), reason: 'многоточие преди затварящата кавичка');
    final quoted = t.split('\n').first;
    expect(quoted.length, lessThan(kLongQuoteChars + 20));
  });

  test('⚠ реже се по ДУМА, не насред нея', () {
    final t = quoteShareText(make('думичка ' * 100));
    final quoted = t.split('\n').first;
    expect(quoted, isNot(contains('дум…')), reason: 'счупена дума');
  });
}

// ── маркиране върху истински HTML ────────────────────────────────────────
//
// ⚠ Тези проверки хванаха бъг, който не се виждаше от нищо друго: в едни
// абзаци фонът се появяваше, в други не, а разликата беше само наличието на
// entity. Диагностицирано с текст ОТ БАЗАТА, не измислен.

void wrapRealTests() {
  test('маркира обикновен абзац', () {
    const html = '<p>Предсказанието на светия мъченик, убит с меч, най-напред '
        'се изпълнило върху брат му. Скоро Маломир умрял.</p>';
    expect(wrapQuoteByText(html, 'Скоро Маломир умрял', 'q'), contains('"q"'));
  });

  test('⚠ ENTITY-та не чупят търсенето', () {
    // `&nbsp;` се сгъваше като буквите „nbsp" (n, b, s, p са латински знаци),
    // тъй че „рече&nbsp;му" ставаше „речеnbspму", а цитатът — дошъл от
    // _plainTextOf, който декодира — беше „речему".
    const html = '<p>Той  рече&nbsp;му:\n„Иди в мир."</p>';
    expect(wrapQuoteByText(html, 'Той рече му: „Иди в мир."', 'q'),
        contains('"q"'));
  });

  test('⚠ вложените тагове не пречат', () {
    const html = '<p>и <em>рече</em> му <strong>тихо</strong> насаме</p>';
    final out = wrapQuoteByText(html, 'рече му тихо', 'q');
    expect(out, contains('"q"'));
    expect(out.replaceAll(RegExp(r'</?span[^>]*>'), ''), html,
        reason: 'текстът и таговете остават непокътнати');
  });

  test('липсващ цитат оставя HTML-а както е', () {
    const html = '<p>кратък текст</p>';
    expect(wrapQuoteByText(html, 'съвсем друго', 'q'), html);
  });
}

// ── координатите на wrapQuoteByText спрямо wrapRangeHtml ────────────────
//
// ⚠⚠ РЕАЛЕН БЪГ, докладван и диагностициран от потребителя (03.09.2026)
// върху истинските жития на св. Кирил Философ и св. Методий Моравски:
// маркирането излизаше отместено с точно толкова знака, колкото е
// дължината на тага ПРЕДИ намереното. wrapQuoteByText броеше позиции в
// СУРОВИЯ html (с таговете), а wrapRangeHtml очаква позиции в ПЛОСКИЯ
// текст (без тях).

void coordinateBugTests() {
  test('⚠ абзац, започващ директно с таг — точното начало на реалния бъг', () {
    const html = '<p>А след това, като се огради от съмнения и възложи '
        'печалта си на Бога, и по-рано.</p>';
    const quote = 'А след това, като се огради от съмнения и възложи '
        'печалта си на Бога';
    final out = wrapQuoteByText(html, quote, 'q');
    final m = RegExp(r'<span class="q">(.*?)</span>').firstMatch(out);
    expect(m?.group(1), quote, reason: 'без изместване от дължината на <p>');
  });

  test('съвпада с резултата БЕЗ никакъв обграждащ таг', () {
    const withTag = '<p>Кратък текст за проба тук.</p>';
    const noTag = 'Кратък текст за проба тук.';
    const quote = 'текст за проба';
    final a = wrapQuoteByText(withTag, quote, 'q');
    final b = wrapQuoteByText(noTag, quote, 'q');
    final ma = RegExp(r'<span class="q">(.*?)</span>').firstMatch(a);
    final mb = RegExp(r'<span class="q">(.*?)</span>').firstMatch(b);
    expect(ma?.group(1), mb?.group(1));
  });

  test('⚠ верен и след вложен таг (<em>) преди цитата', () {
    const html = '<p>Уводна дума. <em>Курсив тук.</em> А после следва '
        'търсеният откъс за проверка.</p>';
    const quote = 'търсеният откъс за проверка';
    final out = wrapQuoteByText(html, quote, 'q');
    final m = RegExp(r'<span class="q">(.*?)</span>').firstMatch(out);
    expect(m?.group(1), quote);
  });
}

void linkTruncationTests() {
  // ⚠ ОТРЯЗВАНЕТО В САМИЯ АДРЕС ОТПАДНА с версия 3 — откъсът вече не пътува
  // в него изобщо. Правилото „реже се по ДУМА" обаче важи с пълна сила там,
  // където текстът СЕ показва: в съобщението за споделяне. Проверката се
  // мести при него, вместо да се изхвърли.
  test('⚠ съкращаването в съобщението е по ДУМА, не насред нея', () {
    final q = Quote(
      anchor: const QuoteAnchor(
          source: QuoteSource.life, locator: 'sv-x', block: 0,
          charStart: 0, charLength: 400),
      // ⚠ Достатъчно дълъг, за да мине прага [kLongQuoteChars].
      text: 'дума ' * 200,
      title: 'нещо',
      savedAtMs: 0,
    );
    final shown = quoteShareText(q).split('\n').first;
    expect(shown, contains('…'), reason: 'дълъг цитат се съкращава');
    expect(shown, isNot(contains('дум…')), reason: 'не реже насред дума');
  });

  test('⚠ адресът вече не носи откъса изобщо', () {
    final q = Quote(
      anchor: const QuoteAnchor(
          source: QuoteSource.life, locator: 'sv-x', block: 0,
          charStart: 0, charLength: 400),
      text: 'дума ' * 30,
      title: 'нещо',
      savedAtMs: 0,
    );
    final p = parseQuoteLink(Uri.parse(buildQuoteLink(q)))!;
    expect(p.text, isEmpty);
  });
}


// ── разделителят „|" в самите данни ────────────────────────────────────
//
// ⚠⚠ РЕАЛЕН БЪГ (03.09.2026): `locator` за книга е „път|href", за Библия
// „език|код|глава" — а „|" е и разделителят между полетата в пакета. Без
// екраниране locator се режеше до първата чертичка и `openBookQuote`
// излизаше мълчаливо (parts.length < 2), тъй че цитат от „Месецослов"
// оставяше човека в календара.

void separatorTests() {
  Quote bookQuote(String locator) => Quote(
        anchor: QuoteAnchor(
          source: QuoteSource.book,
          locator: locator,
          block: 12,
          charStart: 40,
          charLength: 25,
        ),
        text: 'Скоро при императора дошли посланици',
        title: 'Преставяне на св. Кирил',
        savedAtMs: 0,
      );

  test('⚠ locator с „|" оцелява цял (книга)', () {
    const loc = 'assets/books/09.epub|OEBPS/Text/index_split_397.xhtml';
    final p = parseQuoteLink(Uri.parse(buildQuoteLink(bookQuote(loc))))!;
    expect(p.anchor.locator, loc);
    expect(p.anchor.source, QuoteSource.book);
  });

  test('⚠ locator с ДВЕ чертички оцелява (Библия)', () {
    final q = Quote(
      anchor: const QuoteAnchor(
        source: QuoteSource.bible,
        locator: 'bg|Mt|5',
        block: 3,
        charStart: 0,
        charLength: 30,
      ),
      text: 'Блажени нищите духом',
      title: 'Матей 5',
      savedAtMs: 0,
    );
    final p = parseQuoteLink(Uri.parse(buildQuoteLink(q)))!;
    expect(p.anchor.locator, 'bg|Mt|5');
    expect(p.anchor.source, QuoteSource.bible);
  });

  test('полетата след locator не се разместват', () {
    const loc = 'a|b|c|d';
    final p = parseQuoteLink(Uri.parse(buildQuoteLink(bookQuote(loc))))!;
    expect(p.anchor.locator, loc);
    expect(p.anchor.block, 12);
    expect(p.anchor.charStart, 40);
    expect(p.anchor.charLength, 25);
  });

  test('⚠ обратна наклонена черта в текста не чупи разчитането', () {
    final q = Quote(
      anchor: const QuoteAnchor(
          source: QuoteSource.life, locator: 'sv-x', block: 0,
          charStart: 0, charLength: 20),
      text: r'нещо с \ и още \p вътре',
      title: 'проба',
      savedAtMs: 0,
    );
    final p = parseQuoteLink(Uri.parse(buildQuoteLink(q)))!;
    expect(p.anchor.locator, '${kLocatorMarker}${locatorFingerprint('sv-x')}');
  });

  test('обикновен житиен locator минава непроменен (съвместимост)', () {
    final q = Quote(
      anchor: const QuoteAnchor(
          source: QuoteSource.life, locator: 'sv-ioan-rilski', block: 4,
          charStart: 10, charLength: 50),
      text: 'някакъв цитат от житие',
      title: 'Св. Иоан Рилски',
      savedAtMs: 0,
    );
    final p = parseQuoteLink(Uri.parse(buildQuoteLink(q)))!;
    expect(p.anchor.locator,
        '${kLocatorMarker}${locatorFingerprint('sv-ioan-rilski')}');
    expect(p.anchor.block, 4);
  });
}

/// Сглобява пакет по реда на полетата от ВЕРСИЯ 1 — за проверката, че вече
/// споделени адреси продължават да се четат.
///
/// ⚠ Нарочно е препис, а не повикване на `_pack`: тя е частна и, по-важното,
/// вече пакетира по НОВИЯ ред. Тестът трябва да строи стария вид, дори след
/// като кодът вече не умее да го прави.
String _packV1(List<String> fields) {
  final esc = fields.map((v) =>
      v.replaceAll(r'\', r'\\').replaceAll('|', r'\p'));
  // ⚠ Винаги СУРОВ пакет („r"), без zlib: `ZLibCodec` живее в `dart:io`, а
  // тестът няма нужда от свиване — разчитането приема и двата вида.
  final body =
      base64Url.encode(utf8.encode(esc.join('|'))).replaceAll('=', '');
  return 'r$body';
}

/// Четимият адрес за Писанието — предложението на потребителя от 05.09.2026.
void bibleLinkTests() {
  Quote bible(String locator, int from, int to, int trimStart, int trimEnd) =>
      Quote(
        anchor: QuoteAnchor(
          source: QuoteSource.bible,
          locator: locator,
          block: from,
          charStart: trimStart,
          charLength: 0,
          blockEnd: to,
          charEnd: trimEnd,
        ),
        text: 'нещо',
        title: 'Матей 2',
        savedAtMs: 0,
      );

  test('адресът е ЧЕТИМ, а не пакетиран', () {
    expect(buildQuoteLink(bible('bg|Mt|2', 3, 5, 9, 15)),
        'https://isihiabg.github.io/orthodox_calendar/q/Mt.2:3-5(9;15)@bg');
  });

  test('⚠ адресът минава през Uri БЕЗ да се промени', () {
    final link = buildQuoteLink(bible('bg|Mt|2', 3, 5, 9, 15));
    expect(Uri.parse(link).toString(), link,
        reason: 'кръглите скоби оцеляват, за разлика от < > и [ ]');
  });

  test('без отрязване скобите ги няма — „(0;0)" е шум', () {
    expect(buildQuoteLink(bible('bg|Mt|2', 3, 5, 0, 0)),
        endsWith('/Mt.2:3-5@bg'));
  });

  test('един стих не пише диапазон', () {
    expect(buildQuoteLink(bible('bg|Mt|5', 9, 9, 0, 0)),
        endsWith('/Mt.5:9@bg'));
  });

  group('разчитане — всичко след препратката е ПО ИЗБОР', () {
    ParsedQuoteLink read(String tail) => parseQuoteLink(Uri.parse(
        'https://isihiabg.github.io/orthodox_calendar/q/$tail'))!;

    test('пълният вид', () {
      final p = read('Mt.2:3-5(9;15)@bg');
      expect(p.anchor.source, QuoteSource.bible);
      expect(p.anchor.locator, 'bg|Mt|2');
      expect(p.anchor.block, 3);
      expect(p.anchor.blockEnd, 5);
      expect(p.anchor.charStart, 9);
      expect(p.anchor.charEnd, 15);
    });

    test('⚠ БЕЗ скоби → цели стихове', () {
      final p = read('Mt.2:3-5@bg');
      expect(p.anchor.charStart, 0);
      expect(p.anchor.charEnd, 0);
      expect(p.anchor.block, 3);
      expect(p.anchor.blockEnd, 5);
    });

    test('⚠ БЕЗ език → преводът на получателя', () {
      final p = read('Mt.2:3-5(9;15)');
      expect(p.anchor.locator, '|Mt|2');
      expect(p.anchor.charStart, 9);
    });

    test('⚠ БЕЗ нищо — гола вътрешна препратка е валиден външен линк', () {
      final p = read('Mt.2:3-5');
      expect(p.anchor.locator, '|Mt|2');
      expect(p.anchor.block, 3);
      expect(p.anchor.blockEnd, 5);
      expect(p.anchor.charStart, 0);
      expect(p.anchor.charEnd, 0);
    });

    test('един стих', () {
      final p = read('Mt.5:9');
      expect(p.anchor.block, 9);
      expect(p.anchor.blockEnd, 9);
    });

    test('книга с цифра отпред', () {
      final p = read('1Pet.1:3-4@utfcs');
      expect(p.anchor.locator, 'utfcs|1Pet|1');
      expect(p.anchor.block, 3);
      expect(p.anchor.blockEnd, 4);
    });

    test('само едното число в скобите', () {
      final p = read('Mt.2:3(9)');
      expect(p.anchor.charStart, 9);
      expect(p.anchor.charEnd, 0);
    });

    test('⚠ цяла глава — отваря я, без да маркира', () {
      final p = read('Mt.2');
      expect(p.anchor.block, 0, reason: 'нула значи „няма какво да се маркира"');
    });

    test('⚠ уловеното се сглобява обратно до същия адрес', () {
      const tail = 'Mt.2:3-5(9;15)@bg';
      final p = read(tail);
      expect(buildBibleQuoteLink(p.anchor), endsWith('/$tail'));
    });
  });

  test('⚠ препратка от НЯКОЛКО пасажа не е цитат', () {
    // „Апок.12:3,20:2" е законна за четене, но цитатът е един непрекъснат
    // откъс — тук се отказваме, вместо да вземем първия пасаж наслуки.
    expect(
        parseQuoteLink(Uri.parse(
            'https://isihiabg.github.io/orthodox_calendar/q/Apok.12:3,20:2')),
        isNull);
  });

  test('⚠ пакетираният вид продължава да се разпознава', () {
    const q = Quote(
      anchor: QuoteAnchor(
          source: QuoteSource.life, locator: 'sv-x', block: 1,
          charStart: 0, charLength: 10),
      text: 'някакъв цитат от житие',
      title: 'нещо',
      savedAtMs: 0,
    );
    final p = parseQuoteLink(Uri.parse(buildQuoteLink(q)))!;
    expect(p.anchor.source, QuoteSource.life,
        reason: 'в base64url няма точка, тъй че двата вида не се бъркат');
  });
}

/// ⚠⚠ ЦЯЛАТА ВЕРИГА ЗА ПИСАНИЕТО: маркиране през няколко стиха → адрес →
/// линк → разчитане → същите стихове и същото отрязване.
///
/// Точно това не работеше: селекция през два стиха се отказваше, а споделен
/// адрес не носеше края на цитата изобщо.
void bibleChainTests() {
  // Три съседни стиха, както ги дава `_quoteBlocks` — БЕЗ номерата: те вече
  // са извън селекцията (виж `_unselectable` в bible_reader.dart).
  const blocks = [
    'И като чу това, цар Ирод се смути, и цял Иерусалим с него.',
    'И като събра всички първосвещеници и книжници народни, питаше ги.',
    'А те му казаха: в Витлеем Иудейски, защото тъй е писано чрез пророка.',
  ];
  const verses = ['3', '4', '5'];

  test('⚠ маркиране от средата на един стих до средата на друг', () {
    // Човекът маркира „цар Ирод се смути…" през целия стих 4 и спира на
    // „в Витлеем Иудейски" в стих 5.
    const selected = 'цар Ирод се смути, и цял Иерусалим с него. '
        'И като събра всички първосвещеници и книжници народни, питаше ги. '
        'А те му казаха: в Витлеем Иудейски';
    final spot = captureSelection(blocks, selected);
    expect(spot, isNotNull, reason: 'селекция през три стиха трябва да се улови');
    expect(spot!.block, 0);
    expect(spot.blockEnd, 2);

    final a = bibleAnchorFromSpot(
        spot: spot, blocks: blocks, verses: verses,
        lang: 'bg', book: 'Mt', chapter: 2);
    expect(a.block, 3, reason: 'номер на СТИХ, не индекс на ред');
    expect(a.blockEnd, 5);
    expect(a.charStart, blocks[0].indexOf('цар Ирод'));
    expect(a.charEnd, blocks[2].length - blocks[2].indexOf('Иудейски') - 'Иудейски'.length,
        reason: 'отрязаното от КРАЯ на последния стих');

    // и обратно през адреса
    final link = buildBibleQuoteLink(a)!;
    expect(link, endsWith('/Mt.2:3-5(${a.charStart};${a.charEnd})@bg'));
    final p = parseQuoteLink(Uri.parse(link))!;
    expect(p.anchor.block, 3);
    expect(p.anchor.blockEnd, 5);
    expect(p.anchor.charStart, a.charStart);
    expect(p.anchor.charEnd, a.charEnd);
  });

  test('цял стих → без скоби в адреса', () {
    final spot = captureSelection(blocks, blocks[1]);
    final a = bibleAnchorFromSpot(
        spot: spot!, blocks: blocks, verses: verses,
        lang: 'bg', book: 'Mt', chapter: 2);
    expect(a.block, 4);
    expect(a.blockEnd, 4);
    expect(a.charStart, 0);
    expect(a.charEnd, 0, reason: 'нищо не се реже отзад');
    expect(buildBibleQuoteLink(a), endsWith('/Mt.2:4@bg'));
  });

  test('⚠ отрязаното се прилага обратно и дава ТОЧНО маркирания текст', () {
    const selected = 'смути, и цял Иерусалим с него. '
        'И като събра всички първосвещеници';
    final spot = captureSelection(blocks, selected);
    final a = bibleAnchorFromSpot(
        spot: spot!, blocks: blocks, verses: verses,
        lang: 'bg', book: 'Mt', chapter: 2);
    final p = parseQuoteLink(Uri.parse(buildBibleQuoteLink(a)!))!;

    // Така четецът възстановява откъса: първи стих от отрязването нататък,
    // последен — до дължината минус отрязаното отзад.
    final first = blocks[0].substring(p.anchor.charStart);
    final last = blocks[1].substring(0, blocks[1].length - p.anchor.charEnd);
    expect(first, 'смути, и цял Иерусалим с него.');
    expect(last, 'И като събра всички първосвещеници');
  });

  test('⚠ надписание на псалом („0") не се прави на адрес', () {
    final spot = captureSelection(blocks, blocks[0]);
    final a = bibleAnchorFromSpot(
        spot: spot!, blocks: blocks, verses: const ['0', '1', '2'],
        lang: 'bg', book: 'Ps', chapter: 50);
    expect(a.block, 0);
    expect(buildBibleQuoteLink(a), isNull,
        reason: 'пада на пакетирания вид, вместо да сглоби „Ps.50:0"');
  });
}

/// ⚠⚠ ПЕТНАЙСЕТТЕ „ГОДИНА" — случаят, докладван от потребителя (05.09.2026).
///
/// Къс откъс, който се среща много пъти в едно четиво. Дотук се запазваше
/// ПЪРВОТО срещане, където и да е бил маркиран, и оттам нататък всичко беше
/// последователно сгрешено — и линкът, и осветяването.
void occurrenceTests() {
  // Петнайсет абзаца, всеки с по едно „година" — единайсетият е нашият.
  final blocks = [
    for (var i = 1; i <= 15; i++)
      'Абзац номер $i разказва как през тази година се случило нещо и подир '
          'това людете се разотишли по домовете си.',
  ];

  /// Ориентир „човекът гледа абзац [i]" — така го дава [QuotableSelectionArea]
  /// от геометрията на самата селекция.
  (int, int) at(int i) => (i, blocks[i].indexOf('година'));

  test('⚠ БЕЗ ориентир се хваща първото — това беше бъгът', () {
    final spot = captureSelection(blocks, 'година')!;
    expect(spot.block, 0);
  });

  test('⚠ С ориентир се хваща тъкмо маркираното', () {
    final spot = captureSelection(blocks, 'година', hint: at(10))!;
    expect(spot.block, 10, reason: 'единайсетият абзац');
    expect(spot.occurrence, 11);
    expect(spot.occurrenceTotal, 15);
  });

  test('⚠ поредният номер пътува в линка и връща на СЪЩОТО място', () {
    final spot = captureSelection(blocks, 'година', hint: at(10))!;
    final q = buildQuote(
      source: QuoteSource.life,
      locator: 'sv-kirill-filosof',
      title: 'Св. Кирил Философ',
      blocks: blocks,
      spot: spot,
    );
    final p = parseQuoteLink(Uri.parse(buildQuoteLink(q)))!;
    expect(p.anchor.occurrence, 11);
    expect(p.anchor.occurrenceTotal, 15);

    final hit = locateParsedQuote(blocks, p);
    expect(hit.block, 10, reason: 'единайсетото, не първото');
    expect(blocks[hit.block].substring(hit.start, hit.start + hit.length),
        'година');
  });

  test('⚠⚠ номерът оцелява РЕДАКЦИЯ, която мести координатите', () {
    final spot = captureSelection(blocks, 'година', hint: at(10))!;
    final q = buildQuote(
      source: QuoteSource.life, locator: 'sv-x', title: 'нещо',
      blocks: blocks, spot: spot,
    );
    final p = parseQuoteLink(Uri.parse(buildQuoteLink(q)))!;

    // Конвейерът пренаписва четивото: първите абзаци стават по-дълги, тъй че
    // всички координати подир тях се разместват. Броят „година" не се мени.
    final edited = [
      for (var i = 0; i < blocks.length; i++)
        i < 5 ? 'Допълнено начало на абзаца. ${blocks[i]}' : blocks[i],
    ];
    final hit = locateParsedQuote(edited, p);
    expect(hit.block, 10);
    expect(edited[hit.block].substring(hit.start, hit.start + hit.length),
        'година');
  });

  test('⚠ смени ли се БРОЯТ, се пада на най-близкото до координатите', () {
    final spot = captureSelection(blocks, 'година', hint: at(10))!;
    final q = buildQuote(
      source: QuoteSource.life, locator: 'sv-x', title: 'нещо',
      blocks: blocks, spot: spot,
    );
    final p = parseQuoteLink(Uri.parse(buildQuoteLink(q)))!;

    // Появява се ОЩЕ едно „година" в началото — единайсетото вече е друго.
    final edited = ['През оная година било тихо.', ...blocks];
    final hit = locateParsedQuote(edited, p);
    // Координатите сочат абзац 10, а той в новия текст е бившият девети;
    // истинският е 11. Важното е, че НЕ се пада на първия и че намереното
    // пак е „година" — по-добре съсед, отколкото начало на четивото.
    expect(hit.block, greaterThan(5));
    expect(edited[hit.block].substring(hit.start, hit.start + hit.length),
        'година');
  });
}

/// Двоичният пакет на версия 3 — това, което направи адреса къс.
void v3Tests() {
  Quote life(String slug, {int block = 3, int start = 10, int len = 20,
          int? blockEnd, int? charEnd, int occ = 0, int total = 0}) =>
      Quote(
        anchor: QuoteAnchor(
          source: QuoteSource.life, locator: slug, block: block,
          charStart: start, charLength: len,
          blockEnd: blockEnd, charEnd: charEnd,
          occurrence: occ, occurrenceTotal: total,
        ),
        text: 'достатъчно дълъг цитат, за да има отпечатък',
        title: 'нещо', savedAtMs: 0,
      );

  test('⚠ пакетът се различава по ПЪРВИЯ знак — „b"/„c", не „r"/„z"', () {
    final packed = buildQuoteLink(life('sv-x')).split('/').last;
    expect(packed[0], anyOf('b', 'c'),
        reason: 'първият БАЙТ на двоичния пакет е 0x30..0x32, тоест „0"/„1"/'
            '„2" — точно с каквито започват текстовите пакети');
  });

  test('⚠⚠ ОТРИЦАТЕЛНА разлика за края оцелява (цитат през няколко блока)', () {
    // Тук charEnd (25 в ПОСЛЕДНИЯ блок) е ПО-МАЛКО от charStart+charLength
    // (10+40 в първия) — обикновен varint изяждаше знака и краят се
    // разместваше. Оттам зигзагът.
    final q = life('sv-x', block: 3, start: 10, len: 40,
        blockEnd: 6, charEnd: 25);
    final p = parseQuoteLink(Uri.parse(buildQuoteLink(q)))!;
    expect(p.anchor.block, 3);
    expect(p.anchor.blockEnd, 6);
    expect(p.anchor.charStart, 10);
    expect(p.anchor.charLength, 40);
    expect(p.anchor.charEnd, 25);
  });

  test('краят НЕ се пише, когато се извежда', () {
    final short = buildQuoteLink(life('sv-x')).length;
    final long =
        buildQuoteLink(life('sv-x', blockEnd: 9, charEnd: 7)).length;
    expect(short, lessThan(long), reason: 'изводимият край не заема място');
  });

  test('⚠ локаторът на КНИГА се свива до „том/глава"', () {
    final q = Quote(
      anchor: const QuoteAnchor(
        source: QuoteSource.book,
        locator: 'assets/books/Жития на светиите - 09(сеп) - Димитрий '
            'Ростовски.epub|Text/index_split_397.xhtml',
        block: 12, charStart: 430, charLength: 96,
      ),
      text: 'достатъчно дълъг цитат, за да има отпечатък',
      title: 'нещо', savedAtMs: 0,
    );
    final link = buildQuoteLink(q);
    expect(link.length, lessThan(90),
        reason: 'пътят до тома е над шейсет байта сам по себе си');
    final p = parseQuoteLink(Uri.parse(link))!;
    expect(p.anchor.locator, '${kLocatorMarker}09/397');
    expect(p.anchor.block, 12);
    expect(p.anchor.charStart, 430);
  });

  test('⚠ непознат път до том влиза ЛИТЕРАЛНО, вместо да се загуби', () {
    const odd = 'assets/books/друго.epub|Text/glava.xhtml';
    final q = Quote(
      anchor: const QuoteAnchor(
          source: QuoteSource.book, locator: odd,
          block: 1, charStart: 0, charLength: 30),
      text: 'достатъчно дълъг цитат, за да има отпечатък',
      title: 'нещо', savedAtMs: 0,
    );
    final p = parseQuoteLink(Uri.parse(buildQuoteLink(q)))!;
    expect(p.anchor.locator, odd,
        reason: 'по-дълъг адрес, но работещ — вместо тих отказ');
  });

  test('⚠ поредният номер оцелява през двоичния пакет', () {
    final p = parseQuoteLink(
        Uri.parse(buildQuoteLink(life('sv-x', occ: 11, total: 15))))!;
    expect(p.anchor.occurrence, 11);
    expect(p.anchor.occurrenceTotal, 15);
  });

  test('⚠ по-нова версия се отхвърля, вместо да се гадае', () {
    final packed = buildQuoteLink(life('sv-x')).split('/').last;
    final bytes = base64Url.decode(
        packed.substring(1).padRight((packed.length + 2) ~/ 4 * 4, '='));
    // Вдигаме версията в горните четири бита на първия байт.
    bytes[0] = (15 << 4) | (bytes[0] & 0x0F);
    final broken = packed[0] +
        base64Url.encode(bytes).replaceAll('=', '');
    expect(
        parseQuoteLink(Uri.parse(
            'https://isihiabg.github.io/orthodox_calendar/q/$broken')),
        isNull);
  });

  test('повреден двоичен пакет не гърми, а се отказва', () {
    for (final s in ['b', 'b!!!!', 'bAA', 'c', 'cZZZZZZZZ']) {
      expect(
          () => parseQuoteLink(Uri.parse(
              'https://isihiabg.github.io/orthodox_calendar/q/$s')),
          returnsNormally);
    }
  });
}
