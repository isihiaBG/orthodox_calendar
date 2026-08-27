// bible_language_pair.dart
//
// Кои два превода се четат в секцията „Библия" и кой от двата се гледа в
// момента.
//
// ДВОЙКА, а не един език — защото цялото устройство на четеца стъпва на нея:
//
//   изправено   показва се ЕДИН от двата; плъзгане наляво/надясно минава на
//               другия, без да губи мястото;
//   легнало     двата стоят успоредно, всеки в своя колона, с черта по
//               средата.
//
// Тоест „вторият език" не е допълнение, а равноправна половина. Затова се
// пазят заедно, а не като „език" плюс „още един".
//
// ⚠ ValueNotifier, а не голи static полета. Езикът се сменя от падащо меню в
// лентата — тоест ВЪРХУ отворения четец, без да го затваря. Без слушател
// смяната би се видяла чак при следващото отваряне на главата. Същият урок
// вече беше платен с [ReaderDropCapScale].
//
// Записът е ВЕДНАГА, не отложен: смяната на език е рядко, съзнателно
// действие, а не поредица нетърпеливи тапвания като при +/- на шрифта.

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Двойката преводи плюс кой от тях се гледа.
@immutable
class BibleLanguagePair {
  /// Кодовете на двата превода — както са в `languages.code`.
  final String first;
  final String second;

  /// 0 или 1 — кой се показва в изправено положение. В легнало се виждат и
  /// двата, но стойността пак се пази: при завъртане обратно човекът трябва
  /// да се върне там, откъдето е тръгнал.
  final int active;

  const BibleLanguagePair({
    required this.first,
    required this.second,
    this.active = 0,
  });

  String get activeCode => active == 0 ? first : second;
  String get otherCode => active == 0 ? second : first;

  /// Двата кода по реда на показване. Гръбнакът на подравняването е ПЪРВИЯТ
  /// — виж [BibleDb.alignChapter].
  List<String> get both => [first, second];

  BibleLanguagePair copyWith({String? first, String? second, int? active}) =>
      BibleLanguagePair(
        first: first ?? this.first,
        second: second ?? this.second,
        active: active ?? this.active,
      );

  @override
  bool operator ==(Object other) =>
      other is BibleLanguagePair &&
      other.first == first &&
      other.second == second &&
      other.active == active;

  @override
  int get hashCode => Object.hash(first, second, active);
}

/// Запомнящият се избор. Общ за цялата секция „Библия".
class BibleLanguages {
  static const String _keyFirst = 'bible_lang_first';
  static const String _keySecond = 'bible_lang_second';
  static const String _keyActive = 'bible_lang_active';

  /// По подразбиране български + църковнославянски в цс графика.
  ///
  /// Дотогава тук стоеше `cs` (гражданската азбука), защото цс графиката
  /// нямаше свой шрифт и системният ѝ рисуваше квадратче на мястото на `ᲂ`
  /// (U+1C82, 6159 срещания). Шрифтът вече е налице — Triodion, SIL OFL —
  /// тъй че подразбирането е автентичната графика, както си беше уговорено.
  ///
  /// ⚠ Засяга САМО нови инсталации: `loadOnce` пипа стойността единствено
  /// когато в SharedPreferences няма нищо. Направен избор винаги печели.
  static const BibleLanguagePair _fallback =
      BibleLanguagePair(first: 'bg', second: 'utfcs');

  static final ValueNotifier<BibleLanguagePair> notifier =
      ValueNotifier<BibleLanguagePair>(_fallback);

  static BibleLanguagePair get value => notifier.value;

  static bool _loaded = false;

  /// Вика се веднъж при отваряне на секцията, заедно с
  /// `ReaderTheme.loadOnce()` и `ReaderFontSize.loadOnce()`.
  ///
  /// [available] са преводите, които РЕАЛНО ги има в базата. Запазен избор,
  /// сочещ към превод, който вече го няма (или още не е свален), се подменя
  /// — иначе четецът отваря празен екран без обяснение.
  static Future<void> loadOnce(List<String> available) async {
    if (_loaded) return;
    _loaded = true;
    if (available.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    var first = prefs.getString(_keyFirst) ?? _fallback.first;
    var second = prefs.getString(_keySecond) ?? _fallback.second;
    final active = prefs.getInt(_keyActive) ?? 0;

    if (!available.contains(first)) first = available.first;
    if (!available.contains(second) || second == first) {
      second = available.firstWhere((c) => c != first, orElse: () => first);
    }

    notifier.value = BibleLanguagePair(
      first: first,
      second: second,
      active: active == 1 ? 1 : 0,
    );
  }

  /// Сверява двойката срещу преводите, които РЕАЛНО са налични в момента.
  ///
  /// Вика се, когато наборът се промени, докато приложението върви — тоест
  /// при изтриване на езиков пакет от настройките. При СВАЛЯНЕ няма какво да
  /// свери (изборът си е валиден) и нищо не се случва.
  ///
  /// ⚠ Отделен метод, а не повторно [loadOnce]: той е пазен с `_loaded` и
  /// освен това чете от SharedPreferences: пуснат наново, би върнал стария
  /// запис върху текущия избор.
  ///
  /// Правилото за подмяна е същото като в [loadOnce] — изчезнал превод се
  /// заменя с първия наличен, а двете половини не бива да станат еднакви.
  static void reconcile(List<String> available) {
    if (available.isEmpty) return;
    final p = notifier.value;
    var first = p.first;
    var second = p.second;
    if (available.contains(first) && available.contains(second)) return;

    if (!available.contains(first)) first = available.first;
    if (!available.contains(second) || second == first) {
      second = available.firstWhere((c) => c != first, orElse: () => first);
    }
    set(p.copyWith(first: first, second: second));
  }

  static void set(BibleLanguagePair pair) {
    if (notifier.value == pair) return;
    notifier.value = pair;
    _save(pair);
  }

  /// Сменя показвания превод, като пази другия.
  ///
  /// ⚠ Ако новият съвпада с другата половина, двата се РАЗМЕНЯТ, вместо да
  /// станат еднакви. Инак човек, избрал „руски" върху двойка българо-руска,
  /// би останал с руски от двете страни и плъзгането не би водило наникъде.
  static void setActiveCode(String code) {
    final p = notifier.value;
    if (code == p.activeCode) return;
    if (code == p.otherCode) {
      set(p.copyWith(active: p.active == 0 ? 1 : 0));
      return;
    }
    set(p.active == 0 ? p.copyWith(first: code) : p.copyWith(second: code));
  }

  /// Минава на другата половина — това прави плъзгането в изправено
  /// положение.
  static void toggleActive() {
    final p = notifier.value;
    set(p.copyWith(active: p.active == 0 ? 1 : 0));
  }

  static void _save(BibleLanguagePair p) {
    SharedPreferences.getInstance().then((prefs) {
      prefs.setString(_keyFirst, p.first);
      prefs.setString(_keySecond, p.second);
      prefs.setInt(_keyActive, p.active);
    });
  }
}
