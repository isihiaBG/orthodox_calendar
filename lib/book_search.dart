// book_search.dart
//
// Търсенето в ЦЕЛИЯ ТОМ („Месецослов") и в ЦЯЛАТА КНИГА („Читалня").
//
// По модела на „Библия": зъбното колело в лентата за търсене отваря панела
// „Разширено търсене" с два избора — на този екран / в целия том, — а Enter
// при втория отваря списък с намерените места. Без избор на книги и глави и
// без запомнени селекции: томът е една книга.
//
// ⚠⚠ НАЧИНЪТ НА ТЪРСЕНЕ Е СЪЩИЯТ КАТО В ЧЕТЕЦА — цяла фраза, изгладена без
// ударения и регистър, с „|" за няколко фрази. Минава през СЪЩАТА функция
// ([nextFoldedMatch]), тъй че „в целия том" намира точно онова, което би
// намерило търсенето в отделното четиво. (Решение на потребителя: Библията
// търси по ключови думи, тук остава по фраза — и Библията НЕ се пипа.)
//
// ⚠ Тап върху място ЗАТВАРЯ списъка и връща (четиво, кое поред съвпадение)
// на четеца, който отваря четивото с вече включено търсене. Същият четец, не
// нов върху него — иначе стекът расте с всеки тап. Връщането към списъка е
// Enter в същото поле: резултатът е запомнен и излиза веднага.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_theme.dart';
import 'book_reader.dart' show bookReadingPlain;
import 'reader_text_utils.dart';
import 'reader_theme.dart';

/// Къде търси полето в четеца и в съдържанието.
enum BookSearchWhere {
  /// В отвореното четиво (в съдържанието — по заглавията). Намереното
  /// свети на място.
  screen,

  /// В целия том — отваря списък с намерените места.
  book,
}

class BookSearchSettings {
  static const _key = 'book_search_where';
  static BookSearchWhere where = BookSearchWhere.screen;
  static bool _loaded = false;

  static Future<void> loadOnce() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getString(_key);
      where = BookSearchWhere.values
          .firstWhere((e) => e.name == v, orElse: () => BookSearchWhere.screen);
    } catch (_) {}
  }

  /// ⚠ Пише се ВЕДНАГА — рядко, съзнателно превключване (както в Библията).
  static Future<void> setWhere(BookSearchWhere v) async {
    where = v;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, v.name);
    } catch (_) {}
  }
}

// ── Панелът ────────────────────────────────────────────────────────────

/// Отваря панела „Разширено търсене" отдясно.
///
/// ⚠ Не като `endDrawer`: панелът се вика и от СЪДЪРЖАНИЕТО, което е долен
/// лист НАД четеца — неговият drawer би излязъл зад листа. Затова е свой
/// маршрут, който само изглежда като drawer (същият като в Библията).
Future<void> showBookSearchPanel(BuildContext context,
    {required bool wholeBook}) {
  return showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Затвори',
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (ctx, _, _) => Align(
      alignment: Alignment.centerRight,
      child: _BookSearchPanel(wholeBook: wholeBook),
    ),
    transitionBuilder: (ctx, anim, _, child) => SlideTransition(
      position: Tween(begin: const Offset(1, 0), end: Offset.zero)
          .animate(CurvedAnimation(parent: anim, curve: Curves.easeOut)),
      child: child,
    ),
  );
}

class _BookSearchPanel extends StatefulWidget {
  /// Книга от „Читалня" (true) или том от „Месецослов" — само за надписите.
  final bool wholeBook;
  const _BookSearchPanel({required this.wholeBook});

  @override
  State<_BookSearchPanel> createState() => _BookSearchPanelState();
}

class _BookSearchPanelState extends State<_BookSearchPanel> {
  @override
  Widget build(BuildContext context) {
    final unit = widget.wholeBook ? 'книга' : 'том';
    return Drawer(
      backgroundColor: AppColors.background,
      child: Column(
        children: [
          // Лентата — една към една с тази в Библията и в [SettingsDrawer].
          Container(
            color: AppColors.toolbar,
            height: 40 + MediaQuery.of(context).padding.top,
            padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top),
            child: Row(
              children: [
                const Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(left: 16),
                    child: Text('Разширено търсене',
                        style: TextStyle(
                            color: AppColors.textPrimary, fontSize: 20)),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.arrow_forward,
                      color: AppColors.textPrimary, size: 24),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 4, bottom: 8),
                  child: Text('КЪДЕ ДА СЕ ТЪРСИ',
                      style: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.5)),
                ),
                RadioGroup<BookSearchWhere>(
                  groupValue: BookSearchSettings.where,
                  onChanged: (v) async {
                    if (v == null) return;
                    await BookSearchSettings.setWhere(v);
                    if (mounted) setState(() {});
                  },
                  child: Column(
                    children: [
                      // ⚠ Една настройка, два екрана — затова „На този
                      // екран", а не „в четивото": в съдържанието се търси
                      // по заглавията (същият довод като в Библията).
                      const _Choice(
                        value: BookSearchWhere.screen,
                        title: 'На този екран',
                        subtitle: 'В четивото — по текста му; в съдържанието '
                            '— по заглавията. Намереното свети на място.',
                      ),
                      _Choice(
                        value: BookSearchWhere.book,
                        title: 'В цял${widget.wholeBook ? "ата" : "ия"} $unit',
                        subtitle: 'След Enter отваря намерените места като '
                            'списък с извадки.',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                // Бележка, не настройка — правилото за фразата важи и за
                // двата избора, а без него „не намирам" изглежда като
                // счупено търсене.
                Text(
                  'Търси се цялата фраза, без значение от ударенията и '
                  'главните букви. Няколко фрази се разделят с „|" — '
                  'намира се коя да е от тях.',
                  style: TextStyle(
                      color: AppColors.textMuted, fontSize: 12, height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Choice<T> extends StatelessWidget {
  final T value;
  final String title;
  final String subtitle;
  const _Choice(
      {required this.value, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) => RadioListTile<T>(
        contentPadding: EdgeInsets.zero,
        dense: true,
        value: value,
        title: Text(title),
        subtitle: Text(subtitle,
            style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
      );
}

// ── Самото търсене ─────────────────────────────────────────────────────

/// Едно намерено място: извадката и кое поред съвпадение е в четивото.
class BookSnippet {
  final String before, match, after;
  final int ordinal;
  const BookSnippet(this.before, this.match, this.after, this.ordinal);
}

/// Намереното в едно четиво.
class BookReadingHits {
  /// Индексът в списъка с главите на четеца — за `_goTo`.
  final int chapter;
  final String title;

  /// Заглавието на групата над него („Памет на 1 август"), или празно.
  final String group;
  final int count;
  final List<BookSnippet> snippets;
  const BookReadingHits(
      this.chapter, this.title, this.group, this.count, this.snippets);
}

class BookSearchResult {
  final String query;
  final List<BookReadingHits> readings;
  int get total => readings.fold(0, (a, r) => a + r.count);
  const BookSearchResult(this.query, this.readings);
}

/// Колко извадки се показват на четиво — останалите се казват с число.
const int kSnippetsPerReading = 3;

/// Подготвеният текст на тома — нормализиран и сгънат, ВЕДНЪЖ.
///
/// ⚠ Мерено на август (1,1 млн. знака, десктоп): нормализиране 636 ms,
/// сгъване 453 ms, а самото търсене — 26 ms. Затова подготовката се пази
/// за целия том и всяко следващо търсене е мигновено.
class BookTexts {
  /// (глава, заглавие, група, чист текст, сгънат текст)
  final List<(int, String, String, String, String)> items;
  const BookTexts(this.items);
}

/// Подготвя текстовете в ОТДЕЛЕН ИЗОЛАТ — на телефона това е секунди и
/// иначе би заковало екрана. Вход: (глава, заглавие, група, суров html).
Future<BookTexts> prepareBookTexts(
        List<(int, String, String, String)> readings) =>
    compute(_prepareIsolate, readings);

BookTexts _prepareIsolate(List<(int, String, String, String)> readings) {
  return BookTexts([
    for (final (ch, title, group, raw) in readings)
      () {
        final plain = bookReadingPlain(raw);
        return (ch, title, group, plain, _fastFold(plain));
      }(),
  ]);
}

/// Същото като `fold(s).text`, но наведнъж за целия низ — [fold] сваля
/// регистъра знак по знак и на 1 млн. знака е бавна.
///
/// ⚠ Резултатът ТРЯБВА да е идентичен с [fold], защото позициите в него се
/// превеждат обратно през `fold(plain).origIndex`. Затова при разлика в
/// дължината (рядък знак, който при сваляне на регистъра става два) се
/// пада на самата [fold].
String _fastFold(String s) {
  final lower = s.toLowerCase();
  if (lower.length != s.length) return fold(s).text;
  return lower.replaceAll(_accents, '');
}

final _accents = RegExp('[\u0300-\u036F]');

/// Търси [foldedQuery] в подготвения том. Бързо — върви в главния изолат.
BookSearchResult searchBook(String foldedQuery, BookTexts texts) {
  final out = <BookReadingHits>[];
  if (hasSearchText(foldedQuery)) {
    for (final (ch, title, group, plain, folded) in texts.items) {
      var count = 0, from = 0;
      final snippets = <BookSnippet>[];
      List<int>? orig; // картата към чистия текст — само при попадение
      while (true) {
        final mm = nextFoldedMatch(folded, foldedQuery, from);
        if (mm == null) break;
        final (at, len) = mm;
        if (snippets.length < kSnippetsPerReading) {
          orig ??= fold(plain).origIndex;
          snippets.add(_snippet(plain, orig[at], orig[at + len - 1] + 1, count));
        }
        count++;
        from = at + len;
      }
      if (count > 0) out.add(BookReadingHits(ch, title, group, count, snippets));
    }
  }
  return BookSearchResult(foldedQuery, out);
}

/// Извадка около [s, e) — по 60 знака встрани, отрязани до цяла дума.
BookSnippet _snippet(String t, int s, int e, int ordinal) {
  var a = (s - 60).clamp(0, t.length);
  var b = (e + 90).clamp(0, t.length);
  if (a > 0) {
    final sp = t.indexOf(' ', a);
    if (sp >= 0 && sp < s) a = sp + 1;
  }
  if (b < t.length) {
    final sp = t.lastIndexOf(' ', b);
    if (sp > e) b = sp;
  }
  return BookSnippet('${a > 0 ? '…' : ''}${t.substring(a, s)}',
      t.substring(s, e), '${t.substring(e, b)}${b < t.length ? '…' : ''}',
      ordinal);
}

// ── Екранът с резултатите ──────────────────────────────────────────────

/// Връща (глава, кое поред съвпадение) или null при „назад".
class BookSearchResultsScreen extends StatelessWidget {
  final BookSearchResult result;

  /// Сурово написаното — за заглавието.
  final String shownQuery;

  /// Глава, която да се маркира и до която да се плъзне списъкът —
  /// последно отвореното оттук. -1 = няма.
  final int lastChapter;

  const BookSearchResultsScreen({
    super.key,
    required this.result,
    required this.shownQuery,
    this.lastChapter = -1,
  });

  @override
  Widget build(BuildContext context) {
    final p = ReaderTheme.palette;
    final fg = AppBarTheme.of(context).foregroundColor ?? Colors.white;
    final rs = result.readings;
    final startAt = rs.indexWhere((r) => r.chapter == lastChapter);
    final ctrl = ScrollController();
    if (startAt > 0) {
      // Груба оценка — само за да не започва отгоре, когато човек се връща.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (ctrl.hasClients) {
          ctrl.jumpTo((startAt * 150.0).clamp(0, ctrl.position.maxScrollExtent));
        }
      });
    }
    return Scaffold(
      backgroundColor: AppColors.toolbar,
      appBar: AppBar(
        backgroundColor: AppColors.toolbar,
        foregroundColor: fg,
        titleSpacing: 0,
        title: Text(
          rs.isEmpty
              ? 'Няма намерени места'
              : 'Намерени: ${result.total} в ${rs.length} '
                  '${rs.length == 1 ? "четиво" : "четива"}',
          style: const TextStyle(fontSize: 17),
        ),
      ),
      body: SafeArea(
        top: false,
        child: Container(
          color: p.bg,
          child: rs.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('„$shownQuery" не се среща в текста.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: p.dim, fontSize: 16)),
                  ),
                )
              : ListView.builder(
                  controller: ctrl,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  itemCount: rs.length,
                  itemBuilder: (ctx, i) => _reading(ctx, rs[i], p,
                      marked: rs[i].chapter == lastChapter),
                ),
        ),
      ),
    );
  }

  Widget _reading(BuildContext context, BookReadingHits r, ReaderPalette p,
      {required bool marked}) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      decoration: marked
          ? BoxDecoration(
              color: p.here.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(6))
          : null,
      padding: marked ? const EdgeInsets.fromLTRB(8, 4, 8, 4) : EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (r.group.isNotEmpty)
            Text(r.group, style: TextStyle(color: p.dim, fontSize: 13)),
          InkWell(
            onTap: () => Navigator.pop(context, (r.chapter, 0)),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(r.title,
                        style: TextStyle(
                            color: p.heading,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            height: 1.2)),
                  ),
                  const SizedBox(width: 8),
                  Text('${r.count}',
                      style: TextStyle(color: p.dim, fontSize: 14)),
                ],
              ),
            ),
          ),
          for (final s in r.snippets)
            InkWell(
              onTap: () => Navigator.pop(context, (r.chapter, s.ordinal)),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 5, 0, 5),
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(text: s.before),
                    TextSpan(
                        text: s.match,
                        style: TextStyle(backgroundColor: p.hit)),
                    TextSpan(text: s.after),
                  ]),
                  style: TextStyle(color: p.ink, fontSize: 15, height: 1.35),
                ),
              ),
            ),
          if (r.count > r.snippets.length)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 2, 0, 4),
              child: Text(
                  'и още ${r.count - r.snippets.length} в това четиво',
                  style: TextStyle(
                      color: p.dim, fontSize: 13, fontStyle: FontStyle.italic)),
            ),
        ],
      ),
    );
  }
}
