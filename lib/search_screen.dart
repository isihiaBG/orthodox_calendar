import 'package:flutter/material.dart';
import 'database_helper.dart';
import 'app_theme.dart';
import 'app_settings.dart';

/// Филтри по група, изписвани с # в полето за търсене.
/// Ключът е това, което потребителят пише след #; стойността е group_code.
/// Има и кирилски псевдоними — на българска клавиатура е по-удобно.
const Map<String, String> _groupAliases = {
  'bg': 'BG',        'бг': 'BG',      'бъл': 'BG',
  'ru': 'RU',        'ру': 'RU',      'рус': 'RU',
  'athos': 'ATHOS',  'aton': 'ATHOS', 'атон': 'ATHOS',
  'rs': 'RS',        'srb': 'RS',     'сръб': 'RS',   'серб': 'RS',
  'gr': 'GR',        'гр': 'GR',      'грц': 'GR',
  'ge': 'GE',        'гру': 'GE',     'груз': 'GE',
  'ro': 'RO',        'рум': 'RO',
  'jer': 'JER',      'йер': 'JER',
  'us': 'US',
  'vs': 'ECUMENICAL', 'вс': 'ECUMENICAL', 'все': 'ECUMENICAL', 'old': 'ECUMENICAL',
  'ecu': 'ECUMENICAL', 'ecum': 'ECUMENICAL', 'ecumeni': 'ECUMENICAL',
};

/// Филтри по СЪДЪРЖАНИЕ — показват само светии, за които има съответният
/// текст. Няколко филтъра се комбинират с логическо И (както при групите).
const Map<String, String> _contentAliases = {
  // тропар
  'тро': 'tropar', 'троп': 'tropar', 'тропар': 'tropar',
  'tro': 'tropar', 'trop': 'tropar', 'tropar': 'tropar',
  // кондак
  'кон': 'kondak', 'конд': 'kondak', 'кондак': 'kondak',
  'kon': 'kondak', 'kond': 'kondak', 'kondak': 'kondak',
  // молитва — ⚠ НЕ бива да почва с 'мол'+'и', че да не се бърка с
  // „молитва" като дума за търсене; затова само кратките форми.
  'мол': 'molitva', 'моли': 'molitva', 'молит': 'molitva',
  'молитва': 'molitva',
  'mol': 'molitva', 'moli': 'molitva', 'molit': 'molitva',
  'molitva': 'molitva', 'pray': 'molitva', 'prayer': 'molitva',
  // величание
  'вел': 'velichanie', 'вели': 'velichanie', 'велич': 'velichanie',
  'величание': 'velichanie',
  'vel': 'velichanie', 'veli': 'velichanie', 'velich': 'velichanie',
  'velichanie': 'velichanie',
  // песнопение — всичко останало от тропарите (стихира и каквото дойде)
  'песн': 'other', 'песноп': 'other', 'песнопение': 'other',
  'pes': 'other', 'pesn': 'other', 'hymn': 'other',
  // житие
  'жит': 'life', 'жив': 'life', 'жиз': 'life',
  'житие': 'life', 'живот': 'life',
  'lif': 'life', 'life': 'life', 'liv': 'life', 'live': 'life',
  // служба (по същата логика — махни реда, ако не я искаш)
  'сл': 'sluzhba', 'слу': 'sluzhba', 'служ': 'sluzhba', 'служба': 'sluzhba',
  'sl': 'sluzhba', 'slu': 'sluzhba', 'sluj': 'sluzhba', 'slujb': 'sluzhba', 'slujba': 'sluzhba', 'sluzhba': 'sluzhba',
};

/// Условие „светията има поне едно песнопение от този вид".
///
/// ⚠ Песнопенията вече НЕ са колони на texts, а редове в lives.hymns —
/// светия може да има три тропара и пет кондака. Затова тук стои EXISTS
/// по вида, а не проверка за непразна колона. Индексът hymns(slug, kind)
/// прави подзаявката евтина.
String _hymnKindSql(String kind) =>
    "EXISTS (SELECT 1 FROM lives.hymns h "
    "WHERE h.slug = s.slug AND h.kind = '$kind')";

/// SQL условието за всеки филтър по съдържание. Житието и службата си
/// остават колони на lives.texts (виж DatabaseHelper._initDatabase), тъй
/// че сочат към l.*, а не към s.*.
final Map<String, String> _contentSql = {
  'tropar': _hymnKindSql('tropar'),
  'kondak': _hymnKindSql('kondak'),
  'molitva': _hymnKindSql('molitva'),
  'velichanie': _hymnKindSql('velichanie'),
  'other': _hymnKindSql('other'),
  'life': "(l.life    IS NOT NULL AND l.life    != '')",
  'sluzhba': "(l.sluzhba IS NOT NULL AND l.sluzhba != '')",
};

/// Хаштагът за помощ. Заявка, която го съдържа, НЕ търси нищо — вместо
/// резултати се показва списъкът с всички хаштагове.
///
/// Нарочно не изчиства полето: човек, който търси нещо и се е запънал за
/// някой хаштаг, дописва „#?“, прочита каквото му трябва и го трие —
/// написаното дотогава го чака непокътнато.
/// ⚠ Редът тук е редът на изписване в помощта (Set пази реда на
/// вмъкване): първо кирилските от кратко към дълго, после латинските.
const Set<String> _helpTags = {
  '?', 'п', 'пом', 'помощ',
  'h', 'help',
};

/// Интервал от години, изписан с #: #25, #2025, #25-27, #2025-2027.
/// Затворен от двата края; една година е интервал от себе си до себе си.
class _YearSpan {
  final int from;
  final int to;
  const _YearSpan(this.from, this.to);
}

/// #25 / #2025 / #25-27 / #!26 / #!25-26 — годината или интервалът.
final RegExp _reYearTag = RegExp(r'^#(!?)(\d{2}|\d{4})(?:-(\d{2}|\d{4}))?$');

/// Двуцифрените се четат като 20xx.
int _normYear(String s) => s.length == 2 ? 2000 + int.parse(s) : int.parse(s);

/// Гражданските граници на църковната година. При СТАР стил годината върви
/// от 14 януари до 13 януари следващата (така я генерира и build.py — виж
/// обхвата на calendar_old.db); при нов стил съвпада с календарната.
({String start, String end}) _civilWindow(_YearSpan span) {
  final old = AppSettings.isOldStyle;
  return (
    start: old ? '${span.from}-01-14' : '${span.from}-01-01',
    end: old ? '${span.to + 1}-01-13' : '${span.to}-12-31',
  );
}

/// Разложена заявка: думите за търсене, груповите филтри, филтрите
/// по съдържание (наличие и липса) и филтрите по година — поотделно.
class _ParsedQuery {
  final List<String> words;
  final List<String> groups;         // group_code стойности
  final List<String> content;        // tropar / kondak / life / sluzhba — ИМА
  final List<String> excludeContent; // tropar / kondak / life / sluzhba — НЯМА
  final List<_YearSpan> years;        // #25 — комбинират се с ИЛИ
  final List<_YearSpan> excludeYears; // #!25 — комбинират се с И

  /// В заявката има #? (или #h, #помощ…). Тогава всичко останало се
  /// подминава и на мястото на резултатите застава списъкът с хаштагове.
  final bool wantsHelp;
  const _ParsedQuery(this.words, this.groups, this.content, this.excludeContent,
      this.years, this.excludeYears, {this.wantsHelp = false});

  /// Филтри, които НЕ важат за недели и седмици (те нямат нито група, нито
  /// текстове). Годините съзнателно не влизат тук — те стесняват периода,
  /// а не вида на резултата, тъй че неделите си остават търсими.
  bool get hasFilters =>
      groups.isNotEmpty || content.isNotEmpty || excludeContent.isNotEmpty;

  bool get hasYearFilter => years.isNotEmpty || excludeYears.isNotEmpty;
}

/// "иван #bg"       → words: [иван], groups: [BG]
/// "#bg"            → words: [],     groups: [BG]   (всички български светии)
/// "#bg #rs"        → words: [],     groups: [BG, RS]
/// "#троп #!кон"    → content: [tropar], excludeContent: [kondak]
///                    (има тропар, И НЯМА кондак — логическо И между всички филтри)
/// Непознат #/#! токен се търси като обикновен текст.
_ParsedQuery _parseQuery(String raw) {
  final words = <String>[];
  final groups = <String>[];
  final content = <String>[];
  final excludeContent = <String>[];
  final years = <_YearSpan>[];
  final excludeYears = <_YearSpan>[];
  var wantsHelp = false;
  for (final token in raw.replaceAll('*', '%').trim().split(RegExp(r'\s+'))) {
    if (token.isEmpty) continue;

    // Помощта се проверява ПЪРВА и излиза от разбора: щом я има, нищо
    // друго в заявката няма значение.
    if (token.startsWith('#') &&
        _helpTags.contains(token.substring(1).toLowerCase())) {
      wantsHelp = true;
      continue;
    }

    // Годините се проверяват ПЪРВИ: те са чисти числа и не могат да се
    // объркат с псевдоним на група или на съдържание.
    final ym = _reYearTag.firstMatch(token);
    if (ym != null) {
      final a = _normYear(ym.group(2)!);
      final b = ym.group(3) != null ? _normYear(ym.group(3)!) : a;
      final span = _YearSpan(a < b ? a : b, a < b ? b : a);
      (ym.group(1) == '!' ? excludeYears : years).add(span);
      continue;
    }

    // Отрицателен филтър по съдържание: #!троп → липсва тропар.
    // Проверяваме го ПРЕДИ обикновения #, защото го съдържа като префикс.
    if (token.startsWith('#!') && token.length > 2) {
      final key = token.substring(2).toLowerCase();
      final c = _contentAliases[key];
      if (c != null) {
        if (!excludeContent.contains(c)) excludeContent.add(c);
        continue;
      }
      words.add(token);
      continue;
    }

    if (token.startsWith('#') && token.length > 1) {
      final key = token.substring(1).toLowerCase();
      final g = _groupAliases[key];
      if (g != null) {
        if (!groups.contains(g)) groups.add(g);
        continue;
      }
      final c = _contentAliases[key];
      if (c != null) {
        if (!content.contains(c)) content.add(c);
        continue;
      }
    }
    words.add(token);
  }
  return _ParsedQuery(words, groups, content, excludeContent, years,
      excludeYears, wantsHelp: wantsHelp);
}

/// Условието по година за дадена колона с дата. Връща null, ако няма какво
/// да се ограничава.
///
/// Правилата (по искане на потребителя):
///  • без нито един годишен хаштаг → само текущата година;
///  • няколко положителни (#25 #27) → ИЛИ помежду им;
///  • отрицателните (#!26) → И, тоест изваждат се едновременно;
///  • само отрицателни → основата е "всички години", минус изваденото.
/// Излишният обхват не се отсича изрично: ако поискаш #20-26, а в базата
/// има само 2025-2027, BETWEEN просто няма какво да върне отвън.
String? _yearCondition(String column, _ParsedQuery p, List<Object?> args) {
  final parts = <String>[];

  final spans = p.years.isNotEmpty
      ? p.years
      : (p.excludeYears.isEmpty
          ? [_YearSpan(DateTime.now().year, DateTime.now().year)]
          : const <_YearSpan>[]);

  if (spans.isNotEmpty) {
    final ors = <String>[];
    for (final s in spans) {
      final w = _civilWindow(s);
      ors.add('$column BETWEEN ? AND ?');
      args.addAll([w.start, w.end]);
    }
    parts.add('(${ors.join(' OR ')})');
  }
  for (final s in p.excludeYears) {
    final w = _civilWindow(s);
    parts.add('NOT ($column BETWEEN ? AND ?)');
    args.addAll([w.start, w.end]);
  }
  return parts.isEmpty ? null : parts.join(' AND ');
}

class SearchBottomSheet extends StatefulWidget {
  final Function(DateTime) onDateSelected;

  const SearchBottomSheet({super.key, required this.onDateSelected});

  @override
  State<SearchBottomSheet> createState() => _SearchBottomSheetState();
}

class _SearchBottomSheetState extends State<SearchBottomSheet> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  List<Map<String, dynamic>> _results = [];
  bool _loading = false;
  /// Има ли годишен хаштаг в текущата заявка — виж _buildDateCell.
  bool _showYear = false;

  /// В заявката има #? — на мястото на резултатите стои помощта.
  bool _showHelp = false;

  /// Думите от последната заявка (без хаштаговете) — по тях се маркира
  /// намереното в списъка. Пазят се отделно, защото списъкът се рисува
  /// наново при всеки кадър, а разборът на заявката става веднъж.
  List<String> _lastWords = const [];

  @override
  void initState() {
    super.initState();
    // Фокус върху полето при отваряне
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

	Future<void> _search(String query) async {
		final parsed = _parseQuery(query);

		// #? — помощта измества резултатите. Заявката не се пуска изобщо;
		// написаното в полето остава, за да може човек да прочете и да
		// продължи оттам, докъдето е стигнал.
		if (parsed.wantsHelp) {
		  setState(() {
			_showHelp = true;
			_results = [];
			_loading = false;
		  });
		  return;
		}
		if (_showHelp) setState(() => _showHelp = false);

		// Нищо за търсене: нито дума, нито филтър
		if (parsed.words.isEmpty && !parsed.hasFilters) {
		  setState(() => _results = []);
		  return;
		}
		setState(() => _loading = true);
		final db = await DatabaseHelper.database;

		final words = parsed.words;
		final args = words.map((w) => '%$w%').toList();

		final List<Map<String, dynamic>> allResults = [];

		// Светии — тук важат и думите, и груповите филтри
		final saintConds = <String>[];
		final saintArgs = <Object?>[];
		for (final w in words) {
		  saintConds.add('s.name LIKE ?');
		  saintArgs.add('%$w%');
		}
		if (parsed.groups.isNotEmpty) {
		  final ph = List.filled(parsed.groups.length, '?').join(',');
		  saintConds.add('s.group_code IN ($ph)');
		  saintArgs.addAll(parsed.groups);
		}
		// Филтри по съдържание — комбинират се с И
		for (final c in parsed.content) {
		  final sql = _contentSql[c];
		  if (sql != null) saintConds.add(sql);
		}
		// Отрицателни филтри по съдържание (#!троп и пр.) — И НЕ го съдържа
		for (final c in parsed.excludeContent) {
		  final sql = _contentSql[c];
		  if (sql != null) saintConds.add('NOT $sql');
		}
		// Периодът — НАКРАЯ, за да лягат новите аргументи след досегашните
		// (sqflite ги свързва по ред на появяване в текста на заявката).
		final saintYearCond = _yearCondition('s.date', parsed, saintArgs);
		if (saintYearCond != null) saintConds.add(saintYearCond);
		final saintsResults = await db.rawQuery(
		  // s.id пътува с резултата, за да може избраният светия да
		  // просветне в дневния изглед (виж AppSettings.flashSaintId).
		  // Неделите и седмиците по-долу нямат такъв — там няма кого да
		  // се флашва, самият ден е резултатът.
		  'SELECT s.id, s.name, s.date, s.rank, \'saint\' as result_type '
		  'FROM saints s '
		  'LEFT JOIN lives.texts l ON l.slug = s.slug '
		  'WHERE ${saintConds.join(' AND ')} ORDER BY s.date ASC',
		  saintArgs);
		allResults.addAll(saintsResults);

		// Недели и седмици нямат нито group_code, нито колони с текстове —
		// при активен филтър ги пропускаме (иначе "#bg" или "#троп" биха
		// извадили и всички недели, което няма смисъл).
		if (!parsed.hasFilters && words.isNotEmpty) {
		  // Недели
		  final sundayArgs = <Object?>[...args];
		  final sundayConds = words.map((_) => 'sn.name LIKE ?').toList();
		  final sundayYear = _yearCondition('cd.date', parsed, sundayArgs);
		  if (sundayYear != null) sundayConds.add(sundayYear);
		  final sundaysResults = await db.rawQuery(
		    'SELECT NULL as id, sn.name, cd.date, 0 as rank, \'sunday\' as result_type '
		    'FROM sundays sn JOIN calendar_days cd ON cd.sunday_id = sn.id '
		    'WHERE ${sundayConds.join(' AND ')} ORDER BY cd.date ASC',
		    sundayArgs);
		  allResults.addAll(sundaysResults);

		  // Седмици
		  final weekArgs = <Object?>[...args];
		  final weekConds = words.map((_) => 'w.name LIKE ?').toList();
		  final weekYear = _yearCondition('cd.date', parsed, weekArgs);
		  if (weekYear != null) weekConds.add(weekYear);
		  final weeksResults = await db.rawQuery(
		    'SELECT NULL as id, w.name, cd.date, 0 as rank, \'week\' as result_type '
		    'FROM weeks w JOIN calendar_days cd ON cd.week_id = w.id '
		    'WHERE ${weekConds.join(' AND ')} ORDER BY cd.date ASC',
		    weekArgs);
		  allResults.addAll(weeksResults);
		}

		allResults.sort((a, b) =>
			(a['date'] as String).compareTo(b['date'] as String));

		setState(() {
		  _results = allResults;
		  // Годината се изписва под датата само когато има годишен хаштаг —
		  // иначе всичко е от текущата година и номерът само би шумял.
		  _showYear = parsed.hasYearFilter;
		  // По тях се маркира намереното в списъка (виж _highlight).
		  _lastWords = parsed.words;
		  _loading = false;
		});
	}

  // Съкратени месеци за формата d.mmm
  static const List<String> _monthsShort = [
    '', 'ян', 'фев', 'мар', 'апр', 'май', 'юни',
    'юли', 'авг', 'сеп', 'окт', 'ное', 'дек'
  ];

  String _fmtShort(DateTime d) => '${d.day} ${_monthsShort[d.month]}';

  /// saints.date е в НОВ стил (григориански) — така е по замисъл, за да
  /// работят вградените изчисления за ден от седмицата и пр.
  /// Старият стил е нов минус 13 дни (валидно за XX–XXI век).
  DateTime _toOldStyle(DateTime newStyle) =>
      newStyle.subtract(const Duration(days: 13));

  /// Клетката с датата вдясно.
  ///
  ///  • само нов стил          → една дата
  ///  • двете, водещ нов стил  → нов отгоре; отдолу посивено /стар с църквица
  ///  • двете, водещ стар стил → стар отгоре с църквица; отдолу /нов с телевизор
  ///
  /// AppSettings.isOldStyle значи "показвай и двата стила", а
  /// AppSettings.oldStyleFirst — "старият води" (потвърдено).
  Widget _buildDateCell(String dateStr) {
    final DateTime newDate;
    try {
      newDate = _parseDate(dateStr);
    } catch (_) {
      return Text(dateStr, style: const TextStyle(
          color: AppColors.sectionTitle, fontSize: 13));
    }
    final oldDate = _toOldStyle(newDate);

    final bool showBoth = AppSettings.isOldStyle;
    final bool oldFirst = AppSettings.oldStyleFirst;

    // Режим "само нов стил": една-единствена дата
    if (!showBoth) {
      if (!_showYear) {
        return Text(
          _fmtShort(newDate),
          style: const TextStyle(color: AppColors.sectionTitle, fontSize: 13),
        );
      }
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(_fmtShort(newDate),
              style: const TextStyle(
                  color: AppColors.sectionTitle, fontSize: 13)),
          _yearLine(newDate),
        ],
      );
    }

    final lead = oldFirst ? oldDate : newDate;
    final sub  = oldFirst ? newDate : oldDate;
    // Водещият ред носи църквица само когато води СТАРИЯТ стил.
    final IconData? leadIcon = oldFirst ? Icons.church : null;
    // Справочният ред: църквица за стар стил, телевизорче за нов.
    final IconData subIcon = oldFirst ? Icons.tv : Icons.church;

    // Тринайсет дни в годината двата стила падат в РАЗЛИЧНИ години
    // (новостилни 1–13 януари = старостилни 19–31 декември от предходната).
    // Тогава един общ ред с годината отдолу би бил двусмислен — не се знае
    // за коя от двете дати се отнася. В такъв случай годината се лепва до
    // всяка дата поотделно и третият ред отпада. В обичайния случай
    // (съвпадаща година) остава компактният вид с ред отдолу.
    final bool splitYears = _showYear && lead.year != sub.year;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (leadIcon != null) ...[
              Icon(leadIcon, size: 13, color: AppColors.sectionTitle),
              const SizedBox(width: 3),
            ],
            Text(
              splitYears ? '${_fmtShort(lead)} ${lead.year}' : _fmtShort(lead),
              style: const TextStyle(
                  color: AppColors.sectionTitle, fontSize: 13),
            ),
          ],
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(subIcon, size: 12, color: AppColors.textMuted),
            const SizedBox(width: 2),
            Text(
              splitYears ? '${_fmtShort(sub)} ${sub.year}' : _fmtShort(sub),
              style: const TextStyle(
                  color: AppColors.textMuted, fontSize: 12),
            ),
          ],
        ),
        // Общата година — трети ред, само когато двете дати са в една и
        // съща година (иначе тя вече стои до всяка от тях).
        if (_showYear && !splitYears) _yearLine(lead),
      ],
    );
  }

  Widget _yearLine(DateTime d) => Text(
        '${d.year}',
        style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
      );

  DateTime _parseDate(String dateStr) {
    final parts = dateStr.split('-');
    return DateTime.utc(
      int.parse(parts[0]),
      int.parse(parts[1]),
      int.parse(parts[2]),
    );
  }

  @override
  Widget build(BuildContext context) {
		final screenHeight = MediaQuery.of(context).size.height;
		final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    
    // ⚠ Височината на панела НЕ се смята от броя резултати. Дълго време
    // стоеше `брой × 56` (или 68 с годината) и това беше вярно само за
    // ред на ЕДИН ред: „Събор на свв. славни и всехвални 12 апостоли:
    // Петър, брат му Андрей…“ заема четири реда, а панелът оставаше висок
    // колкото един — текстът се режеше долу заедно с датата отдясно.
    // Същото важеше и за помощта, само че обратно: тя няма нито един
    // резултат, тъй че сметката даваше нула.
    //
    // Затова тук се смята само ТАВАНЪТ, а истинската височина я определя
    // самото съдържание: Column с mainAxisSize.min и ListView с
    // shrinkWrap в Flexible. Панелът е точно колкото трябва и никога
    // по-голям от позволеното.

    // Таванът е ДВОЕН. Освен старите 80% от екрана (за да се вижда нещо от
    // календара отдолу), панелът трябва да се събере и в мястото, което
    // остава НАД клавиатурата и ПОД лентата на телефона. Без второто
    // ограничение височината ставаше sheetHeight + клавиатурата, което при
    // много резултати надхвърляше екрана и полето за въвеждане се качваше
    // върху часовника и батерията.
    // Двете ограничения работят заедно и НЕ се дублират:
    //   useSafeArea в _showSearch (main.dart) е твърдата граница — панелът
    //     физически не може да влезе под системната лента;
    //   сметката тук е просветът НАД тази граница, за да не изглежда залепен.
    // Затова topInset се вади и тук: screenHeight е цялата височина на
    // екрана, не остатъкът след SafeArea. Без него исканата височина излиза
    // по-голяма от позволената, SafeArea я отрязва и просветът изчезва.
    final topInset = MediaQuery.of(context).padding.top;
    const topGap = 48.0;
    final available = screenHeight - keyboardHeight - topInset - topGap;
    final cap = screenHeight * 0.80;
    var maxHeight = available < cap ? available : cap;
    if (maxHeight < 80.0) maxHeight = 80.0;

    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      alignment: Alignment.bottomCenter,
      child: Container(
      constraints: BoxConstraints(maxHeight: maxHeight + keyboardHeight),
      decoration: BoxDecoration(
        color: AppColors.drawerBackground,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        // Панелът е точно колкото съдържанието си — виж бележката горе
        // защо височината вече не се смята от броя резултати.
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 8, bottom: 4),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.textMuted,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // Search field
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                const Icon(Icons.search, color: AppColors.textMuted, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 16,
                    ),
                    decoration: const InputDecoration(
                      // Подсказката изброяваше пет хаштага и не се
                      // побираше. Сега показва два за пример и сочи към
                      // помощта — тя ги изброява всичките.
                      hintText: 'Търси...       #троп #кон (#? - помощ)',
                      hintStyle: TextStyle(color: AppColors.textMuted),
                      border: InputBorder.none,
                      isDense: true,
                    ),
                    onChanged: _search,
                  ),
                ),
                // Броячът на намереното — само числото, без дума след него:
                // тя изяждаше ширина от полето за въвеждане, а и не казваше
                // нищо, което мястото ѝ да не подсказва. Показва се само при
                // поне един резултат; при нула мълчи, защото празният списък
                // отдолу вече е отговорът.
                if (_results.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: Text(
                      '${_results.length}',
                      style: const TextStyle(
                        color: AppColors.sectionTitle,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                if (_controller.text.isNotEmpty)
                  GestureDetector(
                    onTap: () {
                      _controller.clear();
                      _search('');
                    },
                    child: const Icon(Icons.clear, color: AppColors.textMuted, size: 18),
                  ),
              ],
            ),
          ),
          // Разделител
          if (_results.isNotEmpty || _loading || _showHelp)
            Divider(color: AppColors.sectionDivider, height: 1),
          // Резултати
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(),
            )
          else if (_showHelp)
            // Flexible, не Expanded: списъкът заема колкото му трябва и
            // спира на тавана от constraints-ите, вместо да разпъва
            // панела до дъно и при два резултата.
            const Flexible(child: _HashtagHelp())
          else
            Flexible(
              child: ListView.separated(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: _results.length,
                separatorBuilder: (_, __) => Divider(
                  color: AppColors.sectionDivider,
                  height: 1,
                  indent: 16,
                ),
                itemBuilder: (context, index) {
                  final result     = _results[index];
                  final name       = result['name'] as String;
                  final date       = result['date'] as String;
                  final resultType = result['result_type'] as String? ?? 'saint';

                  // Иконка според типа резултат
                  final Widget leadingIcon = resultType == 'saint'
                      ? const Icon(Icons.circle, size: 8, color: AppColors.textMuted)
                      : const Icon(Icons.church, size: 14, color: AppColors.sectionTitle);

                  // Цвят на текста според типа
                  final Color textColor = resultType == 'saint'
                      ? AppColors.textPrimary
                      : AppColors.sectionTitle;

                  // Собствен ред вместо ListTile: ListTile НЕ включва
                  // височината на trailing, когато мери реда — брои само
                  // заглавието. С трети ред в клетката с датата (годината)
                  // това преливаше с точно толкова, колкото е новият ред.
                  return InkWell(
                    onTap: () {
                      // Кой ред да просветне в дневния изглед. При неделя
                      // или седмица е null — там самият ден е резултатът
                      // и флашът на месечния изглед стига.
                      AppSettings.flashSaintId.value = result['id'] as int?;
                      Navigator.pop(context);
                      widget.onDateSelected(_parseDate(date));
                    },
                    child: Padding(
                      padding:
                          const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      // Датата стои ЦЕНТРИРАНА спрямо реда — така се чете
                      // ясно към кой запис спада. Това е безопасно само
                      // защото името е ограничено до 4 реда: без него
                      // съборните имена разпъваха реда и датата увисваше
                      // насред него, а долният ѝ край се режеше.
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          SizedBox(width: 24, child: Center(child: leadingIcon)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text.rich(
                              _highlight(
                                name,
                                _lastWords,
                                TextStyle(
                                  color: textColor,
                                  fontSize: 15,
                                  fontStyle: resultType == 'saint'
                                      ? FontStyle.normal
                                      : FontStyle.italic,
                                ),
                              ),
                              // Списъкът е за ОРИЕНТИР, не за четене:
                              // по-дългото се отрязва с многоточие. Инак
                              // един съборен ред заема половин екран и
                              // изтласква останалите резултати.
                              maxLines: 4,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 12),
                          _buildDateCell(date),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
					// Padding за клавиатурата
					SizedBox(height: keyboardHeight),
        ],
      ),
      ),
    );
  }
}

/// Човешките имена на филтрите, по стойността им в картите по-горе.
///
/// ⚠ Помощта се СТРОИ от `_groupAliases` и `_contentAliases`, а не се
/// преписва на ръка. Затова нов псевдоним се вижда в нея веднага, а нов
/// ФИЛТЪР иска само ред тук — забрави ли се, той изпъква като „(без
/// име)“ вместо да изчезне мълчаливо от списъка.
const Map<String, String> _contentTitles = {
  'tropar': 'тропар',
  'kondak': 'кондак',
  'molitva': 'молитва',
  'velichanie': 'величание',
  'other': 'друго песнопение',
  'life': 'житие',
  'sluzhba': 'служба',
};

/// ⚠ Женски род — съгласуват се с „църква“ от заглавието на раздела
/// („От коя поместна църква“), не със „светии“.
const Map<String, String> _groupTitles = {
  'BG': 'българска',
  'RU': 'руска',
  // ⚠ „Атон", не „атонска": атонска поместна църква НЯМА — Света гора е
  // под Вселенската патриаршия. Стои в този списък, защото е достатъчно
  // особено и познато място, за да има свой филтър; затова единствено то
  // е съществително, а не прилагателно към „църква".
  'ATHOS': 'Атон',
  'RS': 'сръбска',
  'GR': 'гръцка',
  'GE': 'грузинска',
  'RO': 'румънска',
  'JER': 'йерусалимска',
  'US': 'американска',
  'ECUMENICAL': 'вселенска',
};

/// Обръща карта „псевдоним → стойност“ в „стойност → псевдонимите ѝ“,
/// запазвайки реда на изписване от оригинала.
Map<String, List<String>> _aliasesByValue(Map<String, String> aliases) {
  final out = <String, List<String>>{};
  aliases.forEach((alias, value) => out.putIfAbsent(value, () => []).add(alias));
  return out;
}

/// Списъкът с всички хаштагове — застава на мястото на резултатите,
/// когато заявката съдържа #? (виж [_helpTags]).
class _HashtagHelp extends StatelessWidget {
  const _HashtagHelp();

  @override
  Widget build(BuildContext context) {
    final content = _aliasesByValue(_contentAliases);
    final groups = _aliasesByValue(_groupAliases);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 2),
          child: Text(
            'Помощна информация',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const _HelpNote('Долните предложения се въвеждат в полето за '
            'търсене, разделени с интервал, заедно с ключовите думи, по '
            'които се търси, или самостоятелно.'),

        const _HelpSection('Търсене за налични тропар, кондак и т.н.'),
        for (final e in _contentTitles.entries)
          if (content[e.key] != null) _HelpRow(content[e.key]!, e.value),
        const _HelpNote('Няколко филтъра се съчетават: показва се само онзи, '
            'за когото важат всички.'),
        const _HelpExample('#троп #кон', 'има и тропар, и кондак'),

        const _HelpSection('От коя поместна църква'),
        for (final e in _groupTitles.entries)
          if (groups[e.key] != null) _HelpRow(groups[e.key]!, e.value),
        const _HelpExample('йоан #бг', 'Йоан само сред българските светии'),

        const _HelpSection('В коя година'),
        const _HelpRow(['25', '2025'], 'само тази година'),
        const _HelpRow(['25-27'], 'от — до'),
        const _HelpNote('Без годишен хаштаг се търси само в текущата година.'),
        const _HelpExample('#бг #25-27', 'българските светии за трите години'),

        const _HelpSection('Изключване от списъка'),
        const _HelpRow(['!троп', '!кон', '!бг'], 'НЯМА го / не е оттам'),
        const _HelpNote('Удивителната застава веднага след решетката.'),
        const _HelpExample('#троп #!кон', 'има тропар, но няма кондак'),

        const _HelpSection('Помощ'),
        _HelpRow(_helpTags.toList(), 'показва този списък'),
        const _HelpNote('Изтрий го, за да се върнеш към резултатите — '
            'останалото в полето стои непокътнато.'),
      ],
    );
  }
}

class _HelpSection extends StatelessWidget {
  final String title;
  const _HelpSection(this.title);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 6),
        child: Text(
          title.toUpperCase(),
          style: const TextStyle(
            color: AppColors.sectionTitle,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.8,
          ),
        ),
      );
}

class _HelpRow extends StatelessWidget {
  final List<String> tags;
  final String meaning;
  const _HelpRow(this.tags, this.meaning);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 5,
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final t in tags)
                    Text('#$t',
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        )),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 4,
              child: Text(meaning,
                  style: const TextStyle(
                      color: AppColors.textMuted, fontSize: 13)),
            ),
          ],
        ),
      );
}

class _HelpNote extends StatelessWidget {
  final String text;
  const _HelpNote(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(text,
            style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 12,
                fontStyle: FontStyle.italic)),
      );
}

/// Пример за употреба — самата заявка и какво връща. Стои с курсив и
/// приглушено, като бележка: това е показване, не още един ред за четене.
class _HelpExample extends StatelessWidget {
  final String query;
  final String meaning;
  const _HelpExample(this.query, this.meaning);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 4, left: 2),
        child: RichText(
          text: TextSpan(
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 12,
              fontStyle: FontStyle.italic,
            ),
            children: [
              TextSpan(
                text: query,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              TextSpan(text: '  —  $meaning'),
            ],
          ),
        ),
      );
}

/// Разбива [text] на парчета и слага жълт фон зад онези, които съвпадат с
/// някоя от [words] — така окото хваща веднага защо редът е в списъка.
///
/// ⚠ Сравнението е по `toLowerCase()` от двете страни, не буквално:
/// човек пише „йоан", а в календара стои „Йоан". Dart-овият toLowerCase
/// се справя с кирилицата — за разлика от SQLite-ския LIKE, който е
/// нечувствителен само за ASCII.
///
/// ⚠ Звездичката в заявката се превежда на `%` за SQL-а още в
/// _parseQuery. Тук тя няма смисъл и се маха, инак се търси буквален
/// процент и нищо не светва.
TextSpan _highlight(String text, List<String> words, TextStyle base) {
  final needles = words
      .map((w) => w.replaceAll('%', '').toLowerCase())
      .where((w) => w.isNotEmpty)
      .toList();
  if (needles.isEmpty) return TextSpan(text: text, style: base);

  final lower = text.toLowerCase();
  // Кои позиции са част от съвпадение — маска, а не списък от интервали:
  // две различни думи от заявката може да се застъпват в текста и с
  // интервали трябваше да се слепват на ръка.
  final marked = List<bool>.filled(text.length, false);
  for (final n in needles) {
    var from = 0;
    while (true) {
      final at = lower.indexOf(n, from);
      if (at < 0) break;
      for (var i = at; i < at + n.length && i < marked.length; i++) {
        marked[i] = true;
      }
      from = at + n.length;
    }
  }

  final spans = <TextSpan>[];
  var start = 0;
  for (var i = 1; i <= text.length; i++) {
    if (i == text.length || marked[i] != marked[start]) {
      spans.add(TextSpan(
        text: text.substring(start, i),
        style: marked[start]
            ? base.copyWith(
                backgroundColor: AppColors.hitDark,
                color: AppColors.hitOnDark,
              )
            : base,
      ));
      start = i;
    }
  }
  return TextSpan(children: spans, style: base);
}
