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
// Кориците са ОТДЕЛНИ файлове в assets/covers/ (виж tools/extract_covers.py),
// а не се вадят живо от .epub-ите: разархивирането на дванайсет тома при
// всяко влизане се вижда като забавяне тъкмо на екрана, който трябва да е
// най-хубавият.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_theme.dart';
import 'book_open_transition.dart';
import 'book_reader.dart';
import 'cover_flow.dart';
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

  String get cover => 'assets/covers/$file.jpg';
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

  /// Скрита ли е системната лента в момента. Пази се, за да не се вика
  /// SystemChrome при всяко преизграждане — всяка смяна на режима
  /// преоразмерява прозореца веднъж.
  bool _immersive = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Кориците се подготвят предварително — иначе първите две-три се явяват
    // с прескачане тъкмо докато човек разлиства.
    for (final c in _covers) {
      precacheImage(c, context);
    }
    _setImmersive(true);
  }

  /// Системната лента се скрива за ЦЕЛИЯ екран, не само легнало.
  ///
  /// Легнало причината е хармонията: лентата реже горния ръб на тестето.
  /// Изправено причината е друга и по-важна — ЧЕТЕЦЪТ също се отваря без
  /// лента (виж BookReader.initState). Различават ли се двата екрана,
  /// смяната на режима пада точно по средата на прехода между тях: полето
  /// отгоре изчезва, целият изглед се пренарежда и страницата подскача
  /// нагоре, докато се проявява. Преходът не бива да пресича такава граница.
  void _setImmersive(bool on) {
    if (_immersive == on) return;
    _immersive = on;
    SystemChrome.setEnabledSystemUIMode(
      on ? SystemUiMode.immersiveSticky : SystemUiMode.manual,
      overlays: on ? const [] : SystemUiOverlay.values,
    );
  }

  @override
  void dispose() {
    // ЗАДЪЛЖИТЕЛНО: режимът важи за ЦЯЛОТО приложение, не за екрана. Без това
    // календарът остава без системна лента, ако човек излезе оттук легнало.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual,
        overlays: SystemUiOverlay.values);
    super.dispose();
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
      await _reveal.forward(from: 0);
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

  /// Подът под тестето: отражението трябва да ляга върху нещо, инак виси в
  /// празното. Тъмно горе, малко по-светло долу — както при оригинала.
  Widget _backdrop({required Widget child}) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0A0A0C), Color(0xFF17171B), Color(0xFF0E0E11)],
          stops: [0.0, 0.62, 1.0],
        ),
      ),
      child: child,
    );
  }

  Widget _deck() => CoverFlow(
        key: _flow,
        covers: _covers,
        initialIndex: _index,
        onSelected: (i) => setState(() => _index = i),
        onOpen: _open,
      );

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

  /// Стрелката „назад" за легналия изглед.
  ///
  /// Легнало лента няма — тя би отнела височина тъкмо там, където всяка е
  /// нужна на кориците, и би разбила тъмнината. Но с нея си отива и
  /// единственият изход от екрана, тъй че стрелката остава сама, като
  /// плаващо копче.
  ///
  /// Мястото и размерът ѝ са ТОЧНО тези на лентовата стрелка: гнездо 56×44,
  /// иконка в средата му. Така, ако човек завърти телефона, копчето не
  /// подскача.
  Widget _floatingBack() {
    return Positioned(
      left: 0,
      top: 0,
      child: SizedBox(
        width: 56,
        height: 44,
        child: Center(
          child: Material(
            color: Colors.black.withValues(alpha: 0.38),
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => Navigator.of(context).maybePop(),
              child: const SizedBox(
                width: 40,
                height: 40,
                child: Icon(Icons.arrow_back,
                    size: 22, color: AppColors.textPrimary),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Легнало: тестето е целият екран, а името на тома стои дискретно долу —
  /// колкото да се провери, не да се чете.
  Widget _landscape() {
    final v = _volumes[_index];
    return Stack(
      children: [
        Positioned.fill(child: _deck()),
        _floatingBack(),
        Positioned(
          left: 0,
          right: 0,
          bottom: 10,
          child: IgnorePointer(
            child: Text(
              '${v.month} · том ${v.roman}',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textSecondary.withValues(alpha: 0.85),
                fontSize: 13,
                letterSpacing: 1.1,
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final landscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0C),
      extendBodyBehindAppBar: landscape,
      appBar: landscape
          ? null
          : AppBar(
              backgroundColor: AppColors.toolbar,
              // Същата височина като в справочните секции и в четеца —
              // лентите на приложението не бива да си играят на различни.
              toolbarHeight: 44,
              title: const Text('Месецослов'),
            ),
      body: _backdrop(
        child: SafeArea(
          child: landscape
              ? _landscape()
              : Column(
                  children: [
                    Expanded(child: _deck()),
                    Expanded(child: _info()),
                  ],
                ),
        ),
      ),
    );
  }
}
