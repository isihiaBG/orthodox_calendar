// library_screen.dart
//
// „Месецослов" — изборът на том. Оттук се влиза в четеца (book_reader.dart).
//
// Изборът НЕ е списък, а тесте корици, което се разлиства като стария Cover
// Flow от iTunes (cover_flow.dart). Причината е проста: приложението вече е
// пълно със списъци и точно тук има какво да се покаже — дванайсет корици.
//
// Изправено — тестето заема горната половина, а долната казва на кой том
// сме се спрели. Легнало — тестето взима целия екран и човек се ориентира
// по самите корици.
//
// Кориците са ОТДЕЛНИ файлове в assets/books_covers/ (виж
// tools/extract_covers.py),
// а не се вадят живо от .epub-ите: разархивирането на дванайсет тома при
// всяко влизане се вижда като забавяне тъкмо на екрана, който трябва да е
// най-хубавият.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_drawer.dart';
import 'app_theme.dart';
import 'book_open_transition.dart';
import 'book_reader.dart';
import 'cover_flow.dart';
import 'cover_picker.dart';
import 'epub_source.dart';

/// Един том. Числата са преброени от съдържанията на .epub-ите
/// (tools/extract_covers.py ги изписва) и стоят тук като константи, за да не
/// се отваря нито един архив заради долния панел.
class _Volume {
  final String month;
  final String roman;
  final int days;
  final int lives;
  final String file; // част от името на .epub-а

  const _Volume(this.month, this.roman, this.days, this.lives, this.file);

  String get cover => 'assets/books_covers/$file.jpg';
}

const List<_Volume> _volumes = [
  _Volume('януари', 'I', 31, 109, '01'),
  _Volume('февруари', 'II', 29, 89, '02'),
  _Volume('март', 'III', 31, 97, '03'),
  _Volume('април', 'IV', 30, 87, '04'),
  _Volume('май', 'V', 31, 88, '05'),
  _Volume('юни', 'VI', 30, 79, '06'),
  _Volume('юли', 'VII', 31, 88, '07'),
  _Volume('август', 'VIII', 31, 87, '08'),
  _Volume('септември', 'IX', 30, 117, '09'),
  _Volume('октомври', 'X', 31, 108, '10'),
  _Volume('ноември', 'XI', 30, 110, '11'),
  _Volume('декември', 'XII', 31, 96, '12'),
];

const Map<String, String> _epubOf = {
  '01': 'assets/books/Жития на светиите - 01(яну) - Димитрий Ростовски.epub',
  '02': 'assets/books/Жития на светиите - 02(фев) - Димитрий Ростовски.epub',
  '03': 'assets/books/Жития на светиите - 03(мар) - Димитрий Ростовски.epub',
  '04': 'assets/books/Жития на светиите - 04(апр) - Димитрий Ростовски.epub',
  '05': 'assets/books/Жития на светиите - 05(май) - Димитрий Ростовски.epub',
  '06': 'assets/books/Жития на светиите - 06(юни) - Димитрий Ростовски.epub',
  '07': 'assets/books/Жития на светиите - 07(юли) - Димитрий Ростовски.epub',
  '08': 'assets/books/Жития на светиите - 08(авг) - Димитрий Ростовски.epub',
  '09': 'assets/books/Жития на светиите - 09(сеп) - Димитрий Ростовски.epub',
  '10': 'assets/books/Жития на светиите - 10(окт) - Димитрий Ростовски.epub',
  '11': 'assets/books/Жития на светиите - 11(ное) - Димитрий Ростовски.epub',
  '12': 'assets/books/Жития на светиите - 12(дек) - Димитрий Ростовски.epub',
};

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen>
    with TickerProviderStateMixin {
  final GlobalKey<CoverFlowState> _flow = GlobalKey<CoverFlowState>();
  late final List<ImageProvider> _covers =
      _volumes.map<ImageProvider>((v) => AssetImage(v.cover)).toList();

  int _index = DateTime.now().month - 1; // тестето отваря на текущия месец
  bool _opening = false;

  /// Ходът на излитащата корица и на вдигането на пелената след това
  /// (виж book_open_transition.dart).
  late final AnimationController _launch =
      AnimationController(vsync: this, duration: kCoverLaunchDuration);
  late final AnimationController _reveal =
      AnimationController(vsync: this, duration: kPageArriveDuration);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Кориците се подготвят предварително — иначе първите две-три се явяват
    // с прескачане тъкмо докато човек разлиства.
    for (final c in _covers) {
      precacheImage(c, context);
    }
  }


  /// Отваря том с движение, а не с премигване (виж book_open_transition.dart).
  ///
  /// Редът има значение: разчитането на .epub-а тръгва ПРЕДИ анимацията и
  /// тече успоредно с нея. Така четенето на архива се скрива зад движението
  /// вместо да го забави, а ако все пак се проточи, изчакваме го върху вече
  /// потъмнелия екран — там нищо не стои и половин мигване не личи.
  Future<void> _open(int i) async {
    if (_opening) return;
    setState(() => _opening = true);

    final loading = EpubBook.open(_epubOf[_volumes[i].file]!);
    final rect = _flow.currentState?.centerCoverRect();
    OverlayEntry? flying;

    try {
      if (rect != null) {
        _reveal.value = 0;
        flying = OverlayEntry(
          builder: (_) => CoverLaunch(
            from: rect,
            cover: _covers[i],
            animation: _launch,
            reveal: _reveal,
          ),
        );
        // rootOverlay: слоят трябва да мине и над лентата на екрана, и над
        // маршрута на четеца — пелената го покрива, докато се построява.
        Overlay.of(context, rootOverlay: true).insert(flying);
        await _launch.forward(from: 0);
      }

      final book = await loading;
      if (!mounted) return;
      final opened = Navigator.of(context).push(bookOpenRoute(BookReader(
        book: book,
        hintContents: true,
        // Библиотеката сама стои без системна лента — четецът не бива да я
        // пали на излизане, инак се вижда премигване.
        keepImmersiveOnExit: true,
      )));

      // Един кадър, колкото четецът да се построи и подреди ПОД пелената.
      // Без него вдигането ѝ откроява първото му, още неуталожено рисуване.
      await Future<void>.delayed(const Duration(milliseconds: 32));

      // ⚠ НЕ `await _reveal.forward()`. Контролерът е с vsync от ТОЗИ
      // екран, а щом четецът се отвори отгоре, Flutter спира тикерите на
      // покритите маршрути: анимацията замръзва някъде към 0,4 и нейният
      // Future не се резолвва НИКОГА. Тогава редът под него не се
      // изпълнява, слоят остава в rootOverlay и черната му пелена виси
      // върху цялото четене — страницата изглежда угасена (измерено:
      // фон 18 → 5 в тъмна тема, 245 → 73 в светла).
      //
      // `finally` не спасява: той чака `await opened`, тоест докато човек
      // затвори тома.
      //
      // Затова изчакването е по ВРЕМЕ. Future.delayed не зависи от тикери
      // и се изпълнява дори когато екранът е покрит.
      _reveal.forward(from: 0);
      await Future<void>.delayed(
          kPageArriveDuration + const Duration(milliseconds: 60));
      flying?.remove();
      flying = null;

      await opened;

      // Тук нарочно НЕ се пипа системната лента. Четецът е отворен с
      // keepImmersiveOnExit и я оставя скрита, тъй че няма какво да се
      // оправя. Първият опит беше обратният — да я гасим наново, след като
      // той я е върнал, — и се виждаше точно като премигване.
    } catch (e, st) {
      debugPrint('epub: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Томът не се отвори: $e')),
        );
      }
    } finally {
      // Предпазна мрежа: ако нещо се е счупило по пътя (томът не се отвори,
      // екранът е напуснат), слоят пак трябва да си отиде.
      flying?.remove();
      _launch.value = 0;
      if (mounted) setState(() => _opening = false);
    }
  }

  /// Долният панел: кой том е избран и какво носи.
  Widget _info() {

    final v = _volumes[_index];
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'Жития на светиите',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 6),
          // Месецът е това, което човек търси — затова е най-едрото тук.
          Text(
            v.month,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 30,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'том ${v.roman} · ${v.days} дни · ${v.lives} жития',
            style: const TextStyle(
                color: AppColors.textSecondary, fontSize: 14),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: _opening ? null : () => _open(_index),
            icon: _opening
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.menu_book, size: 18),
            label: const Text('Отвори тома'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.sectionTitle,
              foregroundColor: Colors.white,
              padding:
                  const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }
  @override
  Widget build(BuildContext context) {
    return CoverPickerScaffold(
      title: 'Месецослов',
      covers: _covers,
      index: _index,
      onIndexChanged: (i) => setState(() => _index = i),
      onOpen: _open,
      flowKey: _flow,
      // Хамбургер вместо стрелка „назад" — както във всяка друга секция.
      drawer: const AppDrawer(),
      infoBuilder: (_, __) => _info(),
      landscapeLabel: (i) =>
          '${_volumes[i].month} · том ${_volumes[i].roman}',
    );
  }
}
