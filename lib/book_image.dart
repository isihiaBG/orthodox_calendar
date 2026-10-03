// book_image.dart
//
// Картинките в книгите от „Месецослов" — подадени от САМИЯ .epub.
//
// Защо изобщо е нужно: в тома `<img src="../Images/…png">` сочи с
// относителен път ВЪТРЕ в архива. flutter_html не знае нищо за архива и
// подкарва такъв адрес като мрежов — тоест никога не го намира. Затова
// пътят се разрешава тук спрямо главата, която го съдържа, и байтовете се
// вадят направо от zip-а (`EpubBook.readBytes`).
//
// Липсва ли файлът, не се рисува НИЩО — орнамент, който го няма, не бива да
// оставя счупена иконка насред заглавната страница.

import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';

import 'epub_source.dart';
import 'reader_theme.dart';

class BookImageExtension extends HtmlExtension {
  final EpubBook book;

  /// Пътят на главата, в която стои картинката — спрямо него се разрешават
  /// относителните адреси („../Images/x.png" от „OEBPS/Text/гл.xhtml"
  /// сочи „OEBPS/Images/x.png").
  final String chapterHref;

  const BookImageExtension({required this.book, required this.chapterHref});

  @override
  Set<String> get supportedTags => {'img'};

  @override
  InlineSpan build(ExtensionContext context) {
    final src = context.attributes['src'];
    if (src == null || src.isEmpty) return const TextSpan(text: '');

    final bytes = book.readBytes(_resolve(chapterHref, src));
    if (bytes == null) return const TextSpan(text: '');

    // `data-w` — колко от реда заема картинката в ОРИГИНАЛА (книгите от
    // .docx в „Читалня"). Без него — естествената ширина, но никога
    // по-широка от страницата (томовете на „Месецослов").
    var frac = double.tryParse(context.attributes['data-w'] ?? '');
    // В ИЗПРАВЕНО илюстрациите заемат цялата ширина (указание на автора) —
    // телефонът е тесен и дялът от оригиналния ред ги правеше дребни.
    // Орнаментите (`data-tint="1"`) пазят пропорцията си; в легнало — всички.
    // ⚠ `data-tint="wide"` (орнаментите на посвещението) се оцветява, но се
    // РАЗПЪВА като илюстрация — такъв е одобреният им вид в изправено.
    final bc = context.buildContext;
    if (frac != null &&
        context.attributes['data-tint'] != '1' &&
        bc != null &&
        MediaQuery.orientationOf(bc) == Orientation.portrait) {
      frac = 1.0;
    }
    // `data-scale` — ръчно указание на автора за отделна илюстрация (по-
    // дребна или по-едра от правилото) — умножава дела от реда.
    final scale = double.tryParse(context.attributes['data-scale'] ?? '');
    if (frac != null && scale != null) frac *= scale;
    // `data-tint` — едноцветен орнамент. В тъмна тема кафявото му се губи
    // върху почти черната страница, затова се оцветява в топло светло злато;
    // в светла остава оригиналът.
    final tint = (context.attributes['data-tint'] == '1' ||
            context.attributes['data-tint'] == 'wide') &&
        ReaderTheme.dark;
    Widget paint(Widget child) => tint
        ? ColorFiltered(
            colorFilter:
                const ColorFilter.mode(Color(0xFFC9B48A), BlendMode.srcIn),
            child: child)
        : child;
    final image = paint(Image.memory(bytes, fit: BoxFit.scaleDown));
    // Корицата (`data-cover`) — от край до край, без въздух около нея
    // (указание на автора). Полетата на страницата ги маха book_reader
    // (`_pageGroups`); тук — само собственият отстъп на картинката.
    // ⚠ И в ЛЕГНАЛО — цялата ширина, макар корицата да става по-висока от
    // екрана и да се превърта (изрично от автора; таванът по височината
    // на екрана беше пробван и отхвърлен). Пропорцията се пази.
    if (context.attributes['data-cover'] == '1') {
      return WidgetSpan(
        child: SizedBox(
          width: double.infinity,
          child: Image.memory(bytes, fit: BoxFit.fitWidth),
        ),
      );
    }
    return WidgetSpan(
      // Орнаментите в тези томове са разделители — стоят на собствен ред и
      // по средата.
      child: Align(
        alignment: Alignment.center,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: frac == null
              ? image
              // ⚠ НЕ LayoutBuilder — вътре в реда на текста той гърми при
              // мерене (не дава вградени размери).
              : FractionallySizedBox(
                  widthFactor: frac.clamp(0.05, 1.0),
                  child: paint(Image.memory(bytes, fit: BoxFit.contain)),
                ),
        ),
      ),
    );
  }

  /// Разрешава относителен адрес спрямо пътя на главата.
  ///
  /// Адресът е URL-кодиран („%2B" за „+", „%28" за скоба) — имената на
  /// файловете в тези томове носят точно такива знаци.
  static String _resolve(String chapterHref, String src) {
    final decoded = Uri.decodeFull(src);
    final dir = chapterHref.contains('/')
        ? chapterHref.substring(0, chapterHref.lastIndexOf('/'))
        : '';
    final parts = <String>[];
    for (final seg in '$dir/$decoded'.split('/')) {
      if (seg.isEmpty || seg == '.') continue;
      if (seg == '..') {
        if (parts.isNotEmpty) parts.removeLast();
        continue;
      }
      parts.add(seg);
    }
    return parts.join('/');
  }
}
