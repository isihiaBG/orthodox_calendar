// bible_packs_screen.dart
//
// Списъкът с езиковите пакети — сваляне и изтриване.
//
// ⚠ ОТДЕЛЕН ЕКРАН, а не ред в настройките. Пакетите са десет, всеки с име,
// размер и състояние (свален / тегли се / липсва), плюс лента за напредъка —
// това е списък, не превключвател, и в тясната лента на настройките би се
// смачкал.

import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'bible_db.dart';
import 'bible_packs.dart';

class BiblePacksScreen extends StatefulWidget {
  const BiblePacksScreen({super.key});

  @override
  State<BiblePacksScreen> createState() => _BiblePacksScreenState();
}

class _BiblePacksScreenState extends State<BiblePacksScreen> {
  Set<String> _installed = const {};
  bool _loading = true;

  /// Кой се тегли в момента и докъде е стигнал (0..1).
  final Map<String, double> _progress = {};
  final Map<String, CancelToken> _cancels = {};

  /// Последната грешка за даден пакет — показва се на неговия ред, а не
  /// като изчезващо съобщение долу: човек, който тръгва да тегли и се
  /// разсейва, трябва да завари обяснението там, където го е оставил.
  final Map<String, String> _errors = {};

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final have = await BiblePacks.installed();
    if (!mounted) return;
    setState(() {
      _installed = have;
      _loading = false;
    });
  }

  Future<void> _download(BiblePack pack) async {
    final cancel = CancelToken();
    setState(() {
      _cancels[pack.code] = cancel;
      _progress[pack.code] = 0;
      _errors.remove(pack.code);
    });

    final err = await BiblePacks.download(
      pack.code,
      cancel: cancel,
      onProgress: (p, _, _) {
        if (!mounted || cancel.isCancelled) return;
        // ⚠ Прерисува се само при ЗАБЕЛЕЖИМА промяна. Потокът известява на
        // всяко парче — стотици пъти в секунда — а лентата няма как да
        // покаже разлика под процент.
        final old = _progress[pack.code] ?? 0;
        if (p - old >= 0.01 || p >= 1) {
          setState(() => _progress[pack.code] = p);
        }
      },
    );

    if (!mounted) return;
    setState(() {
      _progress.remove(pack.code);
      _cancels.remove(pack.code);
      if (err != null) _errors[pack.code] = err;
    });
    // ⚠ Списъкът с преводи се сглобява наново — инак новият език не се
    // появява в падащото меню на четеца до следващо пускане.
    BibleDb.forgetLanguages();
    await _refresh();
  }

  Future<void> _remove(BiblePack pack) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.backgroundCard,
        title: const Text('Да изтрия ли превода?'),
        content: Text('„${pack.title}" ще бъде премахнат от устройството. '
            'Може да се свали пак по всяко време.'),
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
    // ⚠ Първо се ЗАТВАРЯ, после се трие. Отворен SQLite файл, изтрит изпод
    // ръцете на връзката, се държи непредсказуемо; затварянето пътьом
    // забравя и списъка с преводи.
    await BibleDb.closePack(pack.code);
    await BiblePacks.remove(pack.code);
    // ⚠ ЧАК СЕГА, след като файлът е изтрит — дотук `installed()` още го
    // брои за налично. Сигналът кара отворения четец да сглоби списъка
    // наново и, ако изтритият превод е бил един от двата показвани, да
    // подмени двойката (`BibleLanguages.reconcile`).
    BibleDb.forgetLanguages();
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final packs = availablePacks();
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.toolbar,
        foregroundColor: Colors.white,
        title: const Text('Преводи на Библията'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text(
                    'Българският и църковнославянският са в приложението. '
                    'Останалите се свалят по желание и остават на '
                    'устройството, за да се четат без интернет.',
                    style: TextStyle(
                        color: AppColors.textSecondary, fontSize: 13,
                        height: 1.35),
                  ),
                ),
                const Divider(
                    height: 17, color: AppColors.sectionDivider, thickness: 1),
                for (final p in packs) _row(p),
              ],
            ),
    );
  }

  Widget _row(BiblePack pack) {
    final busy = _progress.containsKey(pack.code);
    final has = _installed.contains(pack.code);
    final err = _errors[pack.code];

    // ⚠ ОТСТЪПЪТ Е МАЛЪК, защото височината на реда я определя БУТОНЪТ, не
    // текстът. `IconButton` е 48 dp по подразбиране и с по 10 отгоре и отдолу
    // редът ставаше 68 — при два реда текст от общо 37. Списъкът зееше.
    // Тук бутонът е свит до 44 (числото, което проектът е приел за
    // „уцелва се с палец" — виж _kBookRowMinHeight), а отстъпът е 4.
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(pack.title,
                    style: TextStyle(
                        fontSize: 16,
                        color: has
                            ? AppColors.textPrimary
                            : AppColors.textSecondary)),
                const SizedBox(height: 3),
                if (busy)
                  Padding(
                    padding: const EdgeInsets.only(top: 4, right: 12),
                    child: LinearProgressIndicator(
                      value: _progress[pack.code],
                      minHeight: 3,
                      backgroundColor: AppColors.backgroundCard,
                      color: AppColors.sectionTitle,
                    ),
                  )
                else
                  Text(
                    err ?? (has ? 'свален · ${pack.sizeLabel}' : pack.sizeLabel),
                    style: TextStyle(
                      fontSize: 12.5,
                      // Грешката е единственото, което има право да е в
                      // тревожен цвят — иначе списъкът щеше да е шарен.
                      color: err != null
                          ? AppColors.signRed
                          : AppColors.textMuted,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (busy)
            _action(
              tooltip: 'Спри',
              icon: Icons.close,
              color: AppColors.textSecondary,
              onTap: () => _cancels[pack.code]?.cancel(),
            )
          else if (has)
            _action(
              tooltip: 'Изтрий',
              icon: Icons.delete_outline,
              color: AppColors.textSecondary,
              onTap: () => _remove(pack),
            )
          else
            _action(
              tooltip: 'Свали',
              icon: Icons.download_outlined,
              color: AppColors.sectionTitle,
              onTap: () => _download(pack),
            ),
        ],
      ),
    );
  }

  /// Копчето в десния край — свито до 44, без отстъпите на `IconButton`.
  Widget _action({
    required String tooltip,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(icon, color: color, size: 22),
        ),
      ),
    );
  }
}
