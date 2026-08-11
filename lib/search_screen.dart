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
  // житие
  'жит': 'life', 'жив': 'life', 'жиз': 'life',
  'житие': 'life', 'живот': 'life',
  'lif': 'life', 'life': 'life', 'liv': 'life', 'live': 'life',
  // служба (по същата логика — махни реда, ако не я искаш)
  'сл': 'sluzhba', 'слу': 'sluzhba', 'служ': 'sluzhba', 'служба': 'sluzhba',
  'sl': 'sluzhba', 'slu': 'sluzhba', 'sluj': 'sluzhba', 'slujb': 'sluzhba', 'slujba': 'sluzhba', 'sluzhba': 'sluzhba',
};

/// SQL условието за всеки филтър по съдържание.
/// Текстовете живеят в lives.texts (виж DatabaseHelper._initDatabase),
/// не в saints — затова сочат към l.*, а не към s.*.
const Map<String, String> _contentSql = {
  'tropar':  "(l.tropar  IS NOT NULL AND l.tropar  != '')",
  'kondak':  "(l.kondak  IS NOT NULL AND l.kondak  != '')",
  'life':    "(l.life    IS NOT NULL AND l.life    != '')",
  'sluzhba': "(l.sluzhba IS NOT NULL AND l.sluzhba != '')",
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
  const _ParsedQuery(this.words, this.groups, this.content, this.excludeContent,
      this.years, this.excludeYears);

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
  for (final token in raw.replaceAll('*', '%').trim().split(RegExp(r'\s+'))) {
    if (token.isEmpty) continue;

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
  return _ParsedQuery(
      words, groups, content, excludeContent, years, excludeYears);
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
		  'SELECT s.name, s.date, s.rank, \'saint\' as result_type '
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
		    'SELECT sn.name, cd.date, 0 as rank, \'sunday\' as result_type '
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
		    'SELECT w.name, cd.date, 0 as rank, \'week\' as result_type '
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
    
    // Динамична височина: search field + резултати.
    // Третият ред с годината прави редовете по-високи — иначе последният
    // резултат остава отрязан долу.
    final resultsHeight = _results.length * (_showYear ? 68.0 : 56.0);
    final contentHeight = 80.0 + (resultsHeight > 0 ? resultsHeight + 8 : 0);

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
    final sheetHeight = contentHeight.clamp(80.0, maxHeight);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      height: sheetHeight + keyboardHeight,
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
                      hintText: 'Търси...  (#bg #троп #!кон #25 #25-27)',
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
          if (_results.isNotEmpty || _loading)
            Divider(color: AppColors.sectionDivider, height: 1),
          // Резултати
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(),
            )
          else
            Expanded(
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
                      Navigator.pop(context);
                      widget.onDateSelected(_parseDate(date));
                    },
                    child: Padding(
                      padding:
                          const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          SizedBox(width: 24, child: Center(child: leadingIcon)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              name,
                              style: TextStyle(
                                color: textColor,
                                fontSize: 15,
                                fontStyle: resultType == 'saint'
                                    ? FontStyle.normal
                                    : FontStyle.italic,
                              ),
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
    );
  }
}
