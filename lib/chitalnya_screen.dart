// chitalnya_screen.dart
//
// „Читалня" — отделни книги, всяка цяла, в реда на оригинала. Устроена е
// като „Месецослов" (library_screen.dart): тесте корици (Cover Flow), а тап
// отваря книгата в СЪЩИЯ четец (book_reader.dart) — на заглавната страница,
// със „Съдържание" отляво в лентата.
//
// Изправено — под тестето стоят заглавието, авторът и едно-две изречения за
// книгата. Легнало — тестето е на цял екран, както в „Месецослов".
//
// ⚠ Книгите са .epub, сглобени от данните, които вече показват дневният
// изглед и словата (tools/chitalnya/). Форматът е нарочно същият като на
// томовете: така и книгите за сваляне, когато дойдат, минават по същия път.

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_drawer.dart';
import 'app_theme.dart';
import 'book_open_transition.dart';
import 'book_reader.dart';
import 'cover_flow.dart';
import 'cover_picker.dart';
import 'epub_source.dart';

/// Една книга в Читалнята.
class ChitalnyaBook {
  final String code; // името на .epub-а и на корицата
  final String title;
  final String author;
  final String about; // едно-две изречения

  /// Книгата носи оригиналния си PDF (виж EpubBook.bookPdf) — тогава в
  /// панела има и копче за споделянето му.
  final bool hasPdf;

  const ChitalnyaBook(this.code, this.title, this.author, this.about,
      {this.hasPdf = false});

  String get epub => 'assets/chitalnya/$code.epub';
  String get cover => 'assets/chitalnya_covers/$code.jpg';
}

const List<ChitalnyaBook> kChitalnyaBooks = [
  ChitalnyaBook(
    'debolsky',
    'Дни на богослужението',
    'Прот. Григорий Дебольски',
    'Поясненията за постите, празниците, неделите и дните от седмицата — '
        'какво се възпоменава и защо.',
  ),
  ChitalnyaBook(
    'zlatoust',
    'Похвални слова за светиите',
    'Свт. Йоан Златоуст',
    'Двадесет и пет беседи за мъченици, светители и праведници, '
        'произнесени в деня на паметта им.',
  ),
  ChitalnyaBook(
    'teofan',
    'Мисли за всеки ден от годината',
    'Свт. Теофан Затворник',
    'Кратки поучения върху църковните четива от Словото Божие — '
        'за всеки ден от годината.',
  ),
  ChitalnyaBook(
    'optina',
    'Изречения от Оптинските старци',
    'Прпп. Оптински старци',
    'Всички наставления на преподобните старци, подредени по темите на '
        '„Симфонията", както в оригинала.',
  ),
  // ⚠ Сглобява се от .docx-а на автора — tools/chitalnya/scripts/04_razgovori.py.
  ChitalnyaBook(
    'razgovori',
    'Разговори за Божествения промисъл, последните времена и вътрешния духовен живот',
    'Йеромонах Калиник (Пецев)',
    'Разговори на о.Калиник (православен монах) с двама от духовните чеда '
        'на архим. Евгений (техния общ старец) — на теми от разнороден '
        'духовен характер.',
    hasPdf: true,
  ),
];

/// Последно отворената книга в Читалнята — тестето застава на нея при
/// следващо влизане (както в другите секции с корици). По КОДА на книгата:
/// прибавят ли се нови, мястото се мести, а кодът не.
class ChitalnyaLast {
  ChitalnyaLast._();
  static const String _key = 'chitalnya_last_book';
  static String? value;
  static bool _loaded = false;

  static Future<void> loadOnce() async {
    if (_loaded) return;
    _loaded = true;
    value = (await SharedPreferences.getInstance()).getString(_key);
  }

  static Future<void> set(String code) async {
    value = code;
    await (await SharedPreferences.getInstance()).setString(_key, code);
  }
}

class ChitalnyaScreen extends StatefulWidget {
  /// Корицата, на която да се отвори тестето — по КОДА на книгата, не по
  /// място в списъка: прибавят ли се книги, мястото се мести, а кодът не
  /// (връзката „Виж повече за автора" в „За приложението").
  final String? initialCode;

  const ChitalnyaScreen({super.key, this.initialCode});

  @override
  State<ChitalnyaScreen> createState() => _ChitalnyaScreenState();
}

class _ChitalnyaScreenState extends State<ChitalnyaScreen>
    with TickerProviderStateMixin {
  final GlobalKey<CoverFlowState> _flow = GlobalKey<CoverFlowState>();
  late final List<ImageProvider> _covers = kChitalnyaBooks
      .map<ImageProvider>((b) => AssetImage(b.cover))
      .toList();
  int _index = 0;

  /// Тестето се строи чак когато е ясно на коя корица да застане —
  /// иначе за миг стои на първата и после подскача.
  bool _ready = false;
  bool _opening = false;

  @override
  void initState() {
    super.initState();
    ChitalnyaLast.loadOnce().then((_) {
      if (!mounted) return;
      // Изрично поискана книга (връзката в „За приложението") печели пред
      // запомнената.
      final want = widget.initialCode ?? ChitalnyaLast.value;
      final i = kChitalnyaBooks.indexWhere((b) => b.code == want);
      setState(() {
        _index = i < 0 ? 0 : i;
        _ready = true;
      });
    });
  }

  late final AnimationController _launch =
      AnimationController(vsync: this, duration: kCoverLaunchDuration);
  late final AnimationController _reveal =
      AnimationController(vsync: this, duration: kPageArriveDuration);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    for (final c in _covers) {
      precacheImage(c, context);
    }
  }

  @override
  void dispose() {
    _launch.dispose();
    _reveal.dispose();
    super.dispose();
  }

  /// Отваряне с летяща корица — дословно като `_open` в library_screen.dart
  /// (там са доводите за всеки ред, включително защо НЕ `await
  /// _reveal.forward()`).
  Future<void> _open(int i) async {
    if (_opening) return;
    setState(() => _opening = true);
    ChitalnyaLast.set(kChitalnyaBooks[i].code);
    final loading = EpubBook.open(kChitalnyaBooks[i].epub);
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
        Overlay.of(context, rootOverlay: true).insert(flying);
        await _launch.forward(from: 0);
      }
      final book = await loading;
      if (!mounted) return;
      final opened = Navigator.of(context).push(bookOpenRoute(BookReader(
        book: book,
        hintContents: true,
        keepImmersiveOnExit: true,
      )));
      await Future<void>.delayed(const Duration(milliseconds: 32));
      _reveal.forward(from: 0);
      await Future<void>.delayed(
          kPageArriveDuration + const Duration(milliseconds: 60));
      flying?.remove();
      flying = null;
      await opened;
    } catch (e, st) {
      debugPrint('epub: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Книгата не се отвори: $e')),
        );
      }
    } finally {
      flying?.remove();
      _launch.value = 0;
      if (mounted) setState(() => _opening = false);
    }
  }

  /// Целият оригинален PDF на книгата — за изпращане на приятел или за
  /// запазване (искане на автора).
  Future<void> _sharePdf(ChitalnyaBook b) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final bytes = (await EpubBook.open(b.epub)).bookPdf;
      if (bytes == null) return;
      await Printing.sharePdf(bytes: bytes, filename: '${b.title}.pdf');
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('PDF-ът не се сподели: $e')));
    }
  }

  /// Долният панел: заглавие, автор, кратко описание.
  Widget _info() {
    final b = kChitalnyaBooks[_index];
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            b.author,
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: AppColors.textSecondary, fontSize: 13, letterSpacing: 1.2),
          ),
          const SizedBox(height: 6),
          Text(
            b.title,
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                color: AppColors.textPrimary,
                // Дългото заглавие — по-дребно, за да не избута копчетата.
                fontSize: b.title.length > 40 ? 19 : 24,
                fontWeight: FontWeight.w600,
                height: 1.2),
          ),
          const SizedBox(height: 8),
          Text(
            b.about,
            textAlign: TextAlign.center,
            maxLines: 5,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _opening ? null : () => _open(_index),
            icon: _opening
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.menu_book, size: 18),
            label: const Text('Отвори книгата'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.sectionTitle,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
            ),
          ),
          if (b.hasPdf)
            TextButton.icon(
              onPressed: _opening ? null : () => _sharePdf(b),
              icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
              label: const Text('Сподели като PDF'),
              style: TextButton.styleFrom(foregroundColor: AppColors.textSecondary),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Scaffold(backgroundColor: Color(0xFF0A0A0C)); // фонът на кориците
    }
    return CoverPickerScaffold(
      title: 'Читалня',
      covers: _covers,
      index: _index,
      onIndexChanged: (i) => setState(() => _index = i),
      onOpen: _open,
      flowKey: _flow,
      drawer: const AppDrawer(),
      infoBuilder: (_, _) => _info(),
      landscapeLabel: (i) => kChitalnyaBooks[i].title,
    );
  }
}
