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
const Map<String, String> _contentSql = {
  'tropar':  "(s.tropar  IS NOT NULL AND s.tropar  != '')",
  'kondak':  "(s.kondak  IS NOT NULL AND s.kondak  != '')",
  'life':    "(s.life    IS NOT NULL AND s.life    != '')",
  'sluzhba': "(s.sluzhba IS NOT NULL AND s.sluzhba != '')",
};

/// Разложена заявка: думите за търсене, груповите филтри и филтрите
/// по съдържание — поотделно.
class _ParsedQuery {
  final List<String> words;
  final List<String> groups;    // group_code стойности
  final List<String> content;   // tropar / kondak / life / sluzhba
  const _ParsedQuery(this.words, this.groups, this.content);

  bool get hasFilters => groups.isNotEmpty || content.isNotEmpty;
}

/// "иван #bg"  → words: [иван], groups: [BG]
/// "#bg"       → words: [],     groups: [BG]   (всички български светии)
/// "#bg #rs"   → words: [],     groups: [BG, RS]
/// Непознат #токен се търси като обикновен текст.
_ParsedQuery _parseQuery(String raw) {
  final words = <String>[];
  final groups = <String>[];
  final content = <String>[];
  for (final token in raw.replaceAll('*', '%').trim().split(RegExp(r'\s+'))) {
    if (token.isEmpty) continue;
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
  return _ParsedQuery(words, groups, content);
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
		final saintsResults = await db.rawQuery(
		  'SELECT s.name, s.date, s.rank, \'saint\' as result_type '
		  'FROM saints s WHERE ${saintConds.join(' AND ')} ORDER BY s.date ASC',
		  saintArgs);
		allResults.addAll(saintsResults);

		// Недели и седмици нямат нито group_code, нито колони с текстове —
		// при активен филтър ги пропускаме (иначе "#bg" или "#троп" биха
		// извадили и всички недели, което няма смисъл).
		if (!parsed.hasFilters && words.isNotEmpty) {
		  // Недели
		  final sundaysWhere = words.map((_) => 'sn.name LIKE ?').join(' AND ');
		  final sundaysResults = await db.rawQuery(
		    'SELECT sn.name, cd.date, 0 as rank, \'sunday\' as result_type '
		    'FROM sundays sn JOIN calendar_days cd ON cd.sunday_id = sn.id '
		    'WHERE $sundaysWhere ORDER BY cd.date ASC',
		    args);
		  allResults.addAll(sundaysResults);

		  // Седмици
		  final weeksWhere = words.map((_) => 'w.name LIKE ?').join(' AND ');
		  final weeksResults = await db.rawQuery(
		    'SELECT w.name, cd.date, 0 as rank, \'week\' as result_type '
		    'FROM weeks w JOIN calendar_days cd ON cd.week_id = w.id '
		    'WHERE $weeksWhere ORDER BY cd.date ASC',
		    args);
		  allResults.addAll(weeksResults);
		}

		allResults.sort((a, b) =>
			(a['date'] as String).compareTo(b['date'] as String));

		setState(() {
		  _results = allResults;
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
  /// ЗАБЕЛЕЖКА: тук се предполага, че AppSettings.isOldStyle значи
  /// "показвай и двата стила", а AppSettings.oldStyleFirst — "старият води".
  /// Ако имената/смисълът при теб са други, смени САМО двата реда по-долу.
  Widget _buildDateCell(String dateStr) {
    final DateTime newDate;
    try {
      newDate = _parseDate(dateStr);
    } catch (_) {
      return Text(dateStr, style: const TextStyle(
          color: AppColors.sectionTitle, fontSize: 13));
    }
    final oldDate = _toOldStyle(newDate);

    final bool showBoth = AppSettings.isOldStyle;      // ← провери
    final bool oldFirst = !AppSettings.oldStyleFirst;  // ← провери

    // Режим "само нов стил": една-единствена дата
    if (!showBoth) {
      return Text(
        _fmtShort(newDate),
        style: const TextStyle(color: AppColors.sectionTitle, fontSize: 13),
      );
    }

    final lead = oldFirst ? oldDate : newDate;
    final sub  = oldFirst ? newDate : oldDate;
    // Водещият ред носи църквица само когато води СТАРИЯТ стил.
    final IconData? leadIcon = oldFirst ? Icons.church : null;
    // Справочният ред: църквица за стар стил, телевизорче за нов.
    final IconData subIcon = oldFirst ? Icons.tv : Icons.church;

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
              _fmtShort(lead),
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
              '${_fmtShort(sub)}',
              style: const TextStyle(
                  color: AppColors.textMuted, fontSize: 12),
            ),
          ],
        ),
      ],
    );
  }

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
    
    // Динамична височина: search field + резултати (max 80% от екрана)
    final resultsHeight = _results.length * 56.0;
    final contentHeight = 80.0 + (resultsHeight > 0 ? resultsHeight + 8 : 0);
    final maxHeight = screenHeight * 0.80;
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
                      hintText: 'Търси...  (#bg #ru #атон #троп #жит)',
                      hintStyle: TextStyle(color: AppColors.textMuted),
                      border: InputBorder.none,
                      isDense: true,
                    ),
                    onChanged: _search,
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

                  return ListTile(
                    dense: true,
                    leading: leadingIcon,
                    title: Text(
                      name,
                      style: TextStyle(
                        color: textColor,
                        fontSize: 15,
                        fontStyle: resultType == 'saint'
                            ? FontStyle.normal
                            : FontStyle.italic,
                      ),
                    ),
                    trailing: _buildDateCell(date),
                    onTap: () {
                      Navigator.pop(context);
                      widget.onDateSelected(_parseDate(date));
                    },
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
