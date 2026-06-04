import 'package:flutter/material.dart';
import 'database_helper.dart';
import 'app_theme.dart';

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
    if (query.trim().isEmpty) {
      setState(() => _results = []);
      return;
    }
    setState(() => _loading = true);
    final db = await DatabaseHelper.database;
    final results = await db.rawQuery('''
      SELECT s.name, s.date, s.rank
      FROM saints s
      WHERE s.name LIKE ?
      ORDER BY s.date ASC
    ''', ['%$query%']);
    setState(() {
      _results = results;
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
                      hintText: 'Търси светия...',
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
                  final result = _results[index];
                  final name = result['name'] as String;
                  final date = result['date'] as String;

                  return ListTile(
                    dense: true,
                    leading: const Icon(
                      Icons.circle,
                      size: 8,
                      color: AppColors.textMuted,
                    ),
                    title: Text(
                      name,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 15,
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
