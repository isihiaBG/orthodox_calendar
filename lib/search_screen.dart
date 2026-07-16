import 'package:flutter/material.dart';
import 'database_helper.dart';
import 'app_theme.dart';

/// Филтри по група, изписвани с # в полето за търсене.
/// Ключът е това, което потребителят пише след #; стойността е group_code.
/// Има и кирилски псевдоними — на българска клавиатура е по-удобно.
const Map<String, String> _groupAliases = {
  'bg': 'BG',        'бг': 'BG',      'бъл': 'BG',
  'ru': 'RU',        'ру': 'RU',      'рус': 'RU',
  'athos': 'ATHOS',  'aton': 'ATHOS', 'атон': 'ATHOS',
  'rs': 'RS',        'srb': 'RS',     'сръб': 'RS',   'серб': 'RS',
  'gr': 'GR',        'гр': 'GR',      'грц': 'GR',
  'ge': 'GE',        'гру': 'GE',
  'ro': 'RO',        'рум': 'RO',
  'jer': 'JER',      'йер': 'JER',
  'us': 'US',
  'vs': 'ECUMENICAL', 'вс': 'ECUMENICAL', 'все': 'ECUMENICAL',
};

/// Разложена заявка: думите за търсене отделно от груповите филтри.
class _ParsedQuery {
  final List<String> words;
  final List<String> groups;   // group_code стойности
  const _ParsedQuery(this.words, this.groups);
}

/// "иван #bg"  → words: [иван], groups: [BG]
/// "#bg"       → words: [],     groups: [BG]   (всички български светии)
/// "#bg #rs"   → words: [],     groups: [BG, RS]
/// Непознат #токен се търси като обикновен текст.
_ParsedQuery _parseQuery(String raw) {
  final words = <String>[];
  final groups = <String>[];
  for (final token in raw.replaceAll('*', '%').trim().split(RegExp(r'\s+'))) {
    if (token.isEmpty) continue;
    if (token.startsWith('#') && token.length > 1) {
      final code = _groupAliases[token.substring(1).toLowerCase()];
      if (code != null) {
        if (!groups.contains(code)) groups.add(code);
        continue;
      }
    }
    words.add(token);
  }
  return _ParsedQuery(words, groups);
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
		if (parsed.words.isEmpty && parsed.groups.isEmpty) {
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
		final saintsResults = await db.rawQuery(
		  'SELECT s.name, s.date, s.rank, \'saint\' as result_type '
		  'FROM saints s WHERE ${saintConds.join(' AND ')} ORDER BY s.date ASC',
		  saintArgs);
		allResults.addAll(saintsResults);

		// Недели и седмици нямат group_code — при активен филтър ги пропускаме
		// (иначе "#bg" би извадил и всички недели, което няма смисъл).
		if (parsed.groups.isEmpty && words.isNotEmpty) {
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

  String _formatDate(String dateStr) {
    const months = [
      '', 'януари', 'февруари', 'март', 'април',
      'май', 'юни', 'юли', 'август', 'септември',
      'октомври', 'ноември', 'декември'
    ];
    try {
      final parts = dateStr.split('-');
      final day   = int.parse(parts[2]);
      final month = int.parse(parts[1]);
      return '$day ${months[month]}';
    } catch (_) {
      return dateStr;
    }
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
                      hintText: 'Търси светия...  (#bg, #ru, #атон)',
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
                    trailing: Text(
                      _formatDate(date),
                      style: const TextStyle(
                        color: AppColors.sectionTitle,
                        fontSize: 13,
                      ),
                    ),
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
