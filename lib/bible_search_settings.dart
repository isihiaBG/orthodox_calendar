// bible_search_settings.dart
//
// Настройките на ТЪРСЕНЕТО в секцията „Библия".
//
// ⚠ Отделно от [BibleZachala] и другите в bible_settings.dart, макар да са
// от същата секция. Тези тук се отварят от ДРУГО място и в друг миг: не от
// менюто зад трите точки, а от зъбното колело, което се явява в лентата
// САМО докато полето за търсене е отворено. Панелът им е за човек, който
// вече търси и не намира каквото очаква — затова стои на един тап от
// полето, а не три нива навътре в общите настройки.
//
// ⚠ И двете се пазят ВЕДНАГА, без отлагане — рядко, съзнателно
// превключване, не поредица нетърпеливи тапвания (същият довод като при
// [BibleZachala]).

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'kathisma.dart';

/// Къде да търси полето в указателя.
enum BibleSearchWhere {
  /// В имената на книгите — намереното свети на място в списъка.
  names,

  /// В самия текст на Писанието — отваря списък с намерените стихове.
  text,
}

/// Докъде се простира търсенето в текста.
enum BibleSearchRange {
  /// Само в отворения дял — Нов завет, Стар завет или Псалтир.
  tab,

  /// В цялото Писание, независимо кой таб е отворен.
  all,

  /// В книги и катизми, избрани поименно.
  picked,
}

/// Кои книги и катизми са отметнати за търсене.
///
/// ⚠ ДВЕ ОТДЕЛНИ МНОЖЕСТВА, а не едно. Книгите се избират цели, а Псалтирът
/// може да се избере и на части — по катизми, тоест по НАБОР ГЛАВИ вътре в
/// една книга. Смесени в общ списък, двата вида избор биха се сблъскали:
/// „Ps" в книгите значи целият Псалтир и би обезсмислил отметнатите катизми.
///
/// Затова: попадне ли „Ps" в [books], катизмите не се четат изобщо.
class BibleScopePick {
  final Set<String> books;
  final Set<int> kathismata;

  const BibleScopePick({this.books = const {}, this.kathismata = const {}});

  bool get isEmpty => books.isEmpty && kathismata.isEmpty;

  /// Записва се като един ред: „Mt,Mk,Lk|3,7,12".
  String encode() =>
      '${books.join(",")}|${kathismata.join(",")}';

  static BibleScopePick decode(String? raw) {
    if (raw == null || raw.isEmpty) return const BibleScopePick();
    final parts = raw.split('|');
    Set<String> b = {};
    Set<int> k = {};
    if (parts.isNotEmpty && parts[0].isNotEmpty) {
      b = parts[0].split(',').where((e) => e.isNotEmpty).toSet();
    }
    if (parts.length > 1 && parts[1].isNotEmpty) {
      k = parts[1]
          .split(',')
          .map(int.tryParse)
          .whereType<int>()
          .toSet();
    }
    return BibleScopePick(books: b, kathismata: k);
  }
}

/// Общото за двете: `ValueNotifier` + незабавен запис.
///
/// ⚠ `ValueNotifier`, а не голо поле — панелът стои НАД указателя и не го
/// затваря, тъй че без слушател смяната би се видяла чак при следващо
/// отваряне. Същият похват като при [BibleZachala] и [ReaderDropCapScale];
/// платен е вече няколко пъти в този проект.
class _EnumSetting<T> {
  _EnumSetting(this._key, this._values, T initial)
      : notifier = ValueNotifier<T>(initial);

  final String _key;
  final List<T> _values;
  final ValueNotifier<T> notifier;
  bool _loaded = false;

  T get value => notifier.value;

  Future<void> loadOnce() async {
    if (_loaded) return;
    _loaded = true;
    final prefs = await SharedPreferences.getInstance();
    final i = prefs.getInt(_key);
    // ⚠ Няма ли записано — стойността НЕ се пипа: подразбирането живее на
    // едно място (при обявяването), а съществуващ избор винаги печели.
    if (i != null && i >= 0 && i < _values.length) notifier.value = _values[i];
  }

  Future<void> set(T v) async {
    if (notifier.value == v) return;
    notifier.value = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_key, _values.indexOf(v));
  }
}

/// Къде търси полето в указателя.
///
/// ⚠ По подразбиране В ИМЕНАТА, не в текста. Полето стои в лентата на
/// СЪДЪРЖАНИЕТО, а работата на съдържанието е да отвежда до книга — тъй че
/// очакваното от него е „намери ми книгата". Пълнотекстовото търсене е
/// друго занятие: то не отвежда никъде в този списък, а отваря нов екран с
/// извадки. По-скъпо е и като чакане (пълен прочит на осем мегабайта текст
/// срещу мигновено пресяване на седемдесет имена).
final _where = _EnumSetting<BibleSearchWhere>(
    'bible_search_where', BibleSearchWhere.values, BibleSearchWhere.names);

/// Докъде стига търсенето в текста.
///
/// ⚠ По подразбиране ЦЯЛОТО ПИСАНИЕ. Човек, който търси дума, обикновено не
/// знае предварително в кой завет е — а ако знаеше, нямаше да търси. Стесняването
/// е за онзи, който вече е получил твърде много намерено.
final _range = _EnumSetting<BibleSearchRange>(
    'bible_search_range', BibleSearchRange.values, BibleSearchRange.all);

/// Поименният избор — пази се между пусканията, за да не се отмята наново.
class _PickSetting {
  static const _key = 'bible_search_pick';
  final ValueNotifier<BibleScopePick> notifier =
      ValueNotifier<BibleScopePick>(const BibleScopePick());
  bool _loaded = false;

  Future<void> loadOnce() async {
    if (_loaded) return;
    _loaded = true;
    final prefs = await SharedPreferences.getInstance();
    notifier.value = BibleScopePick.decode(prefs.getString(_key));
  }

  Future<void> set(BibleScopePick v) async {
    notifier.value = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, v.encode());
  }
}

final _pick = _PickSetting();

class BibleSearchSettings {
  BibleSearchSettings._();

  static ValueNotifier<BibleScopePick> get pickNotifier => _pick.notifier;
  static BibleScopePick get pick => _pick.notifier.value;
  static Future<void> setPick(BibleScopePick v) => _pick.set(v);

  static ValueNotifier<BibleSearchWhere> get whereNotifier => _where.notifier;
  static ValueNotifier<BibleSearchRange> get rangeNotifier => _range.notifier;

  static BibleSearchWhere get where => _where.value;
  static BibleSearchRange get range => _range.value;

  static Future<void> loadOnce() async {
    await _where.loadOnce();
    await _range.loadOnce();
    await _pick.loadOnce();
  }

  static Future<void> setWhere(BibleSearchWhere v) => _where.set(v);
  static Future<void> setRange(BibleSearchRange v) => _range.set(v);
}

/// Кои ГЛАВИ влизат в обхвата — днес само катизмите на Псалтира.
///
/// ⚠ Стои тук, а не във всеки екран поотделно: указателят и четецът задават
/// един и същ въпрос и трябва да получават един и същ отговор. Преписан на
/// две места, той се разминава при първата промяна в устройството на
/// катизмите.
///
/// ⚠ Иска `kathisma.dart` — затова е функция тук, а не метод на
/// [BibleScopePick]: моделът на настройките няма защо да знае как е разделен
/// Псалтирът.
Map<String, Set<int>> scopeChaptersFor(
    BibleSearchRange range, BibleScopePick pick) {
  if (range != BibleSearchRange.picked || pick.kathismata.isEmpty) {
    return const {};
  }
  final psalms = <int>{};
  for (final k in kKathismata) {
    if (pick.kathismata.contains(k.number)) psalms.addAll(k.psalms);
  }
  return psalms.isEmpty ? const {} : {'Ps': psalms};
}
