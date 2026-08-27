// bible_settings.dart
//
// Настройките, които важат САМО за секцията „Библия".
//
// ⚠ Отделен файл и отделна категория в настройките, а не под общото „ЗА
// ЧЕТИВАТА". Там живеят неща от четенето на ЖИТИЯ и КНИГИ (размерът на
// буквицата), които в Писанието изобщо не се срещат — Библията няма
// буквици. Смесени, двете категории се четат като „настройки, които може и
// да не важат тук", а това е по-лошо от една категория повече.

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Да се показват ли богослужебните зачала („[Зач. 1]") в началото на
/// съответните стихове.
///
/// ⚠ `ValueNotifier`, а не голо поле. Настройката се мени от панела, който
/// стои НАД отворения четец (не го затваря), тъй че без слушател ефектът би
/// се видял чак при следващо отваряне на глава. Същият похват като при
/// [ReaderDropCapScale] (drop_cap_scale.dart).
///
/// ⚠ Записът е ВЕДНАГА, не отложен: това е рядко, съзнателно превключване в
/// настройките, а не поредица нетърпеливи тапвания като при +/- на шрифта.
class BibleZachala {
  BibleZachala._();

  static const _key = 'bible_show_zachala';

  /// ⚠ По подразбиране ИЗКЛЮЧЕНИ — решено на 26.08.2026, обратно на първия
  /// избор.
  ///
  /// Доводът дотук беше „зачалото е част от богослужебното устройство на
  /// Писанието, а не украса". Вярно е, но не е довод за ПОДРАЗБИРАНЕ:
  /// зачалото е указател за СВЕЩЕНИКА — кое четиво се чете на коя служба —
  /// а мнозинството хора отварят Евангелието да четат, не да служат. За тях
  /// „[Зач. 122]" пред първите думи е шум, при това точно на първия екран,
  /// по който се съди за всичко останало.
  ///
  /// Обратната посока е и по-добрата изненада: чистата страница не изисква
  /// обяснение, а онзи, комуто зачалата трябват, ги намира в настройките и
  /// печели нещо. Включени по подразбиране, те не могат да зарадват никого —
  /// само да озадачат.
  static final ValueNotifier<bool> notifier = ValueNotifier<bool>(false);

  static bool get value => notifier.value;

  static bool _loaded = false;

  static Future<void> loadOnce() async {
    if (_loaded) return;
    _loaded = true;
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getBool(_key);
    // ⚠ Няма ли записано — стойността НЕ се пипа. Така подразбирането живее
    // на едно място (горе), а съществуващ избор винаги печели.
    if (v != null) notifier.value = v;
  }

  static void set(bool v) {
    if (notifier.value == v) return;
    notifier.value = v;
    SharedPreferences.getInstance().then((p) => p.setBool(_key, v));
  }
}

/// Да се показва ли въвеждащият екран с трите корици, преди съдържанието на
/// „Библия".
///
/// ⚠ Огледален на [AppSettings.showWelcome] (избора на календар при пускане):
/// същият чекбокс „Не показвай повече" долу и същата възможност да се върне
/// от настройките. Човек, изключил един такъв екран, търси същия ключ и за
/// другия — затова двата се държат еднакво, макар да пазят различни неща.
///
/// ⚠ ВКЛЮЧЕН по подразбиране. За разлика от зачалата, тук показването не е
/// шум: екранът има работа (избира в кой дял да се влезе) и е единственото
/// място в секцията, което не е списък. Комуто пречи, го изключва с един тап
/// още на първото виждане.
class BibleWelcome {
  BibleWelcome._();

  static const _key = 'bible_show_welcome';

  static final ValueNotifier<bool> notifier = ValueNotifier<bool>(true);

  static bool get value => notifier.value;

  static bool _loaded = false;

  static Future<void> loadOnce() async {
    if (_loaded) return;
    _loaded = true;
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getBool(_key);
    // Няма ли записано — подразбирането горе остава непокътнато.
    if (v != null) notifier.value = v;
  }

  static void set(bool v) {
    if (notifier.value == v) return;
    notifier.value = v;
    SharedPreferences.getInstance().then((p) => p.setBool(_key, v));
  }
}

/// Коя от трите книги е била избрана последно на въвеждащия екран.
///
/// Пази се ИНДЕКСЪТ в тестето (0 Стар завет, 1 Нов завет, 2 Псалтир), а не
/// табът: екранът се отваря на корица, не на списък.
///
/// ⚠ Пише се САМО от въвеждащия екран. Библейските препратки в житията
/// отварят четеца направо и НЕ пипат тази стойност — те са отклонение от
/// чуждо четиво, а не избор коя книга чете човекът. Инак една препратка към
/// Псалом насред житие би пренаредила екрана, който той вижда следващия път.
class BibleLastPart {
  BibleLastPart._();

  static const _key = 'bible_last_part';

  /// По подразбиране Новият завет — той е и в средата на тестето.
  static int value = 1;

  static bool _loaded = false;

  static Future<void> loadOnce() async {
    if (_loaded) return;
    _loaded = true;
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getInt(_key);
    if (v != null && v >= 0 && v <= 2) value = v;
  }

  static void set(int i) {
    if (value == i) return;
    value = i;
    SharedPreferences.getInstance().then((p) => p.setInt(_key, i));
  }
}
