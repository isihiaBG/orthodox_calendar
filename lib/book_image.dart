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

    return WidgetSpan(
      // Орнаментите в тези томове са разделители — стоят на собствен ред и
      // по средата.
      child: Align(
        alignment: Alignment.center,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          // Естествената ѝ ширина, но никога по-широка от страницата.
          child: Image.memory(bytes, fit: BoxFit.scaleDown),
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
