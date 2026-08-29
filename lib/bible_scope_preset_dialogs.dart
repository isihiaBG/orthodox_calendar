// bible_scope_preset_dialogs.dart
//
// Двата диалога около запомнените набори книги: „запиши" и „зареди".
//
// ⚠ Отделно от екрана, защото са затворени в себе си: получават списък и
// връщат резултат, без да знаят нищо за отмятането. Така екранът остава за
// избора, а не расте с още двеста реда управление на записи.

import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'bible_scope_presets.dart';

/// ⚠ Датите се пишат по БЪЛГАРСКИ ред (ден.месец.година), а часът — без
/// секунди. Секундата не помага да се различат два записа, а прави реда
/// по-дълъг от името до него.
String _formatDate(DateTime d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.day)}.${two(d.month)}.${d.year} г., '
      '${two(d.hour)}:${two(d.minute)}';
}

/// Пита за име и връща го, или `null` при отказ.
///
/// ⚠ ЦИКЪЛЪТ Е ТУК, а не при викащия: съвпадне ли името със записан набор,
/// пита се за презапис и при „не" се ВРЪЩА В ПОЛЕТО с написаното — човек не
/// започва отначало. Изнесено навън, това би значело викащият да знае за
/// презаписа, а той иска само име.
Future<String?> askPresetName(
  BuildContext context, {
  required List<BibleScopePreset> existing,
  required String initial,
  required int count,
}) async {
  var name = initial;
  while (true) {
    final entered = await showDialog<String>(
      context: context,
      builder: (ctx) => _NameDialog(initial: name, count: count),
    );
    if (entered == null) return null;
    name = entered;

    final clash = BibleScopePresets.findByName(existing, name);
    if (clash == null) return name;

    if (!context.mounted) return null;
    final overwrite = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.backgroundCard,
        title: const Text('Има вече такава селекция'),
        content: Text(
          '„${clash.name}" е записана на ${_formatDate(clash.saved)} '
          'и съдържа ${clash.count} ${clash.count == 1 ? "книга" : "книги"}.\n\n'
          'Да запиша ли новата върху нея?',
          style: const TextStyle(height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Не, обратно'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Да, презапиши'),
          ),
        ],
      ),
    );
    if (overwrite == true) return name;
    if (!context.mounted) return null;
    // „Не" — цикълът се върти пак и полето се отваря с написаното.
  }
}

class _NameDialog extends StatefulWidget {
  final String initial;
  final int count;
  const _NameDialog({required this.initial, required this.count});

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.initial);

  @override
  void initState() {
    super.initState();
    // ⚠ Целият текст е ИЗБРАН при отваряне. Предложеното име („Селекция 3")
    // е за приемане, не за дописване — който иска свое, започва да пише и то
    // изчезва; който иска предложеното, натиска направо „Запиши".
    _ctrl.selection =
        TextSelection(baseOffset: 0, extentOffset: _ctrl.text.length);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final v = _ctrl.text.trim();
    if (v.isEmpty) return;
    Navigator.pop(context, v);
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.count;
    return AlertDialog(
      backgroundColor: AppColors.backgroundCard,
      title: const Text('Запиши селекцията'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _ctrl,
            autofocus: true,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            style: const TextStyle(fontSize: 16),
            decoration: const InputDecoration(
              hintText: 'име на селекцията',
              isDense: true,
            ),
          ),
          const SizedBox(height: 14),
          // ⚠ Какво точно се записва — един ред, приглушен. Диалогът се отваря
          // от друг екран и без него човек записва „нещо", без да види какво.
          Text(
            'Ще се запишат $n ${n == 1 ? "избрана книга" : "избрани книги"}.',
            style: const TextStyle(
                color: AppColors.textMuted, fontSize: 13, height: 1.35),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отказ'),
        ),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: _ctrl,
          // ⚠ Празно име не се приема — записът се намира по име и без него
          // редът в списъка би бил безименен и неотличим от следващия такъв.
          builder: (_, v, _) => TextButton(
            onPressed: v.text.trim().isEmpty ? null : _submit,
            child: const Text('Запиши'),
          ),
        ),
      ],
    );
  }
}

/// Показва записаните набори и връща избрания, или `null`.
Future<BibleScopePreset?> pickPreset(BuildContext context) {
  return showDialog<BibleScopePreset>(
    context: context,
    builder: (_) => const _LoadDialog(),
  );
}

class _LoadDialog extends StatefulWidget {
  const _LoadDialog();

  @override
  State<_LoadDialog> createState() => _LoadDialogState();
}

class _LoadDialogState extends State<_LoadDialog> {
  List<BibleScopePreset> _list = const [];
  bool _loading = true;
  BiblePresetSort _sort = BiblePresetSort.date;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final all = await BibleScopePresets.all();
    if (!mounted) return;
    setState(() {
      _list = all;
      _loading = false;
    });
  }

  Future<void> _delete(BibleScopePreset p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.backgroundCard,
        title: const Text('Да изтрия ли селекцията?'),
        content: Text('„${p.name}" ще бъде премахната. '
            'Самите книги остават, разбира се.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отказ')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Изтрий')),
        ],
      ),
    );
    if (ok != true) return;
    await BibleScopePresets.remove(p);
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final rows = BibleScopePresets.sorted(_list, _sort);
    return AlertDialog(
      backgroundColor: AppColors.backgroundCard,
      // ⚠ Заглавието носи и превключвателя за подредбата. Отделен ред за него
      // би отнел от малкото височина, която остава за самия списък, а двете
      // се четат наведнъж: „записани селекции, подредени по дата".
      titlePadding: const EdgeInsets.fromLTRB(24, 20, 12, 0),
      title: Row(
        children: [
          const Expanded(child: Text('Записани селекции')),
          if (rows.length > 1) _sortButton(),
        ],
      ),
      contentPadding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
      content: SizedBox(
        width: double.maxFinite,
        child: _loading
            ? const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            : rows.isEmpty
                ? const Padding(
                    padding: EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: Text('Още няма записани селекции.',
                        style: TextStyle(color: AppColors.textMuted)),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: rows.length,
                    separatorBuilder: (_, _) => const Divider(
                        height: 1, color: AppColors.sectionDivider),
                    itemBuilder: (_, i) => _row(rows[i]),
                  ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Затвори'),
        ),
      ],
    );
  }

  /// Превключва подредбата — по дата и по име.
  ///
  /// ⚠ Един бутон, който КАЗВА текущата подредба, а не две отделни копчета:
  /// изборите са два и взаимно изключващи се, тъй че вторият е винаги
  /// „другият". Надписът е и състояние, и действие.
  Widget _sortButton() {
    final byDate = _sort == BiblePresetSort.date;
    return TextButton.icon(
      onPressed: () => setState(() => _sort =
          byDate ? BiblePresetSort.name : BiblePresetSort.date),
      icon: Icon(byDate ? Icons.schedule : Icons.sort_by_alpha, size: 22),
      label: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('подредба', style: TextStyle(fontSize: 13, height: 1.05)),
          Text(byDate ? 'по дата' : 'по име',
              style: const TextStyle(fontSize: 13, height: 1.05)),
        ],
      ),
      style: TextButton.styleFrom(
        foregroundColor: AppColors.textMuted,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  Widget _row(BibleScopePreset p) {
    return InkWell(
      onTap: () => Navigator.pop(context, p),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 4, 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.name,
                      style: const TextStyle(
                          fontSize: 16, color: AppColors.textPrimary)),
                  const SizedBox(height: 3),
                  // ⚠ Датата и броят СА НА ЕДИН РЕД и в един тон: заедно те са
                  // едно изречение („кога и колко"), а разделени на два реда
                  // правят списъка двойно по-висок за същото сведение.
                  Text(
                    '${_formatDate(p.saved)}  ·  ${p.count} '
                    '${p.count == 1 ? "книга" : "книги"}',
                    style: const TextStyle(
                        fontSize: 13, color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 20),
              color: AppColors.textMuted,
              tooltip: 'Изтрий селекцията',
              onPressed: () => _delete(p),
            ),
          ],
        ),
      ),
    );
  }
}
