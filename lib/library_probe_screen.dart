// library_probe_screen.dart
//
// ВРЕМЕНЕН екран — най-тънкият възможен срез на „Читанка".
//
// Цели едно-единствено нещо: да докаже, че .epub се отваря НАЖИВО на
// устройството, че съдържанието се чете и че главата се показва бързо.
// Нищо тук не е окончателно — нито видът, нито устройството на кода.
// Като мине проверката, оттук излизат три отделни неща:
//
//   • библиотеката (избор на книга, корици)
//   • ReaderCore (общото между този четец и ReaderScreen)
//   • BookReader (съдържание, прелистване, запомнена позиция)
//
// Затова умишлено НЕ е красиво и НЕ ползва стиловете на четеца — за да не
// се изкуши някой да го остави.

import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'book_reader.dart';
import 'epub_source.dart';

const List<String> _books = [
  'assets/books/Жития на светиите - 01(яну) - Димитрий Ростовски.epub',
  'assets/books/Жития на светиите - 02(фев) - Димитрий Ростовски.epub',
  'assets/books/Жития на светиите - 03(мар) - Димитрий Ростовски.epub',
  'assets/books/Жития на светиите - 04(апр) - Димитрий Ростовски.epub',
  'assets/books/Жития на светиите - 05(май) - Димитрий Ростовски.epub',
  'assets/books/Жития на светиите - 06(юни) - Димитрий Ростовски.epub',
  'assets/books/Жития на светиите - 07(юли) - Димитрий Ростовски.epub',
  'assets/books/Жития на светиите - 08(авг) - Димитрий Ростовски.epub',
  'assets/books/Жития на светиите - 09(сеп) - Димитрий Ростовски.epub',
  'assets/books/Жития на светиите - 10(окт) - Димитрий Ростовски.epub',
  'assets/books/Жития на светиите - 11(ное) - Димитрий Ростовски.epub',
  'assets/books/Жития на светиите - 12(дек) - Димитрий Ростовски.epub',
];

class LibraryProbeScreen extends StatelessWidget {
  const LibraryProbeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.toolbar,
        title: const Text('Читанка'),
      ),
      body: ListView.separated(
        itemCount: _books.length,
        separatorBuilder: (_, __) =>
            const Divider(height: 1, color: AppColors.sectionDivider),
        itemBuilder: (context, i) {
          final name = _books[i]
              .split('/')
              .last
              .replaceAll('Жития на светиите - ', '')
              .replaceAll(' - Димитрий Ростовски.epub', '');
          return ListTile(
            leading: const Icon(Icons.menu_book, color: AppColors.sectionTitle),
            title: Text(name,
                style: const TextStyle(color: AppColors.textPrimary)),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => _TocProbe(assetPath: _books[i]),
            )),
          );
        },
      ),
    );
  }
}

/// Съдържанието на един том. Мери и колко е отнело отварянето — това е
/// същинският въпрос на проверката.
class _TocProbe extends StatefulWidget {
  final String assetPath;
  const _TocProbe({required this.assetPath});

  @override
  State<_TocProbe> createState() => _TocProbeState();
}

class _TocProbeState extends State<_TocProbe> {
  EpubBook? _book;
  Object? _error;
  int _ms = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final t = DateTime.now();
    try {
      final book = await EpubBook.open(widget.assetPath);
      if (!mounted) return;
      setState(() {
        _book = book;
        _ms = DateTime.now().difference(t).inMilliseconds;
      });
    } catch (e, st) {
      debugPrint('epub: $e\n$st');
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final book = _book;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.toolbar,
        title: Text(book?.title ?? 'Отварям…',
            style: const TextStyle(fontSize: 16)),
      ),
      body: _error != null
          ? Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Грешка: $_error',
                  style: const TextStyle(color: AppColors.textSecondary)))
          : book == null
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      color: AppColors.toolbar,
                      child: Text(
                        'отворен за ${_ms} ms · ${book.spine.length} файла · '
                        '${book.toc.length} дяла в съдържанието',
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 12),
                      ),
                    ),
                    // Отваряне на КНИГАТА, а не на конкретна глава. Разликата
                    // не е козметична: тапне ли се глава от съдържанието,
                    // човекът вече е казал къде иска да бъде и четецът
                    // нарочно НЕ предлага връщане към отметката (виж
                    // BookReader._loadSavedPosition). Само по този път
                    // подканата за продължаване изобщо се явява.
                    InkWell(
                      onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => BookReader(book: book))),
                      child: const Padding(
                        padding: EdgeInsets.fromLTRB(16, 14, 16, 14),
                        child: Row(children: [
                          Icon(Icons.play_arrow,
                              size: 20, color: AppColors.sectionTitle),
                          SizedBox(width: 10),
                          Text('Отвори книгата',
                              style: TextStyle(
                                  color: AppColors.sectionTitle, fontSize: 16)),
                        ]),
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(child: _tocList(book)),
                  ],
                ),
    );
  }

  Widget _tocList(EpubBook book) {
    // Съдържанието е двуетажно: ден → жития в него. Показваме го плоско, с
    // отстъп, само за да се види, че вложеността е разчетена правилно.
    final rows = <(EpubTocEntry, int)>[];
    void walk(List<EpubTocEntry> list, int depth) {
      for (final e in list) {
        rows.add((e, depth));
        walk(e.children, depth + 1);
      }
    }

    walk(book.toc, 0);

    return ListView.builder(
      itemCount: rows.length,
      itemBuilder: (context, i) {
        final (entry, depth) = rows[i];
        return InkWell(
          onTap: entry.href.isEmpty
              ? null
              : () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => BookReader(book: book, start: entry),
                  )),
          child: Padding(
            padding: EdgeInsets.fromLTRB(16.0 + depth * 20, 10, 16, 10),
            child: Text(
              entry.title,
              style: TextStyle(
                color: depth == 0
                    ? AppColors.sectionTitle
                    : AppColors.textPrimary,
                fontSize: depth == 0 ? 15 : 14,
                fontWeight: depth == 0 ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
        );
      },
    );
  }
}
