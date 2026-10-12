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

import 'dart:typed_data';

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
    // ⚠⚠ РАЗМЕРЪТ СЕ ЗАДЕЛЯ ПРЕДИ ДЕКОДИРАНЕТО (12.10.2026). `Image.memory`
    // е с височина 0, докато картинката не се декодира (асинхронно), и
    // после израства — всичко под нея се измества. Плъзгането при четене
    // на глас смяташе целта върху „плоските" корица и икони и на заглавната
    // недоскролваше (докладвано от автора). Размерът се чете от заглавката
    // на файла — без декодиране.
    final dims = encodedImageSize(bytes);
    Widget sized(Widget img) => dims == null
        ? img
        : AspectRatio(aspectRatio: dims.$1 / dims.$2, child: img);
    final image = paint(dims == null
        ? Image.memory(bytes, fit: BoxFit.scaleDown)
        // Естествената ширина като таван — като при `scaleDown`.
        : ConstrainedBox(
            constraints: BoxConstraints(maxWidth: dims.$1.toDouble()),
            child: sized(Image.memory(bytes, fit: BoxFit.contain))));
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
          child: sized(Image.memory(bytes, fit: BoxFit.fitWidth)),
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
                  child: paint(sized(Image.memory(bytes, fit: BoxFit.contain))),
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

/// Ширината и височината на картинка в пиксели, прочетени от ЗАГЛАВКАТА на
/// файла (PNG, JPEG, WebP, GIF) — без декодиране. `null`, ако форматът не е
/// познат или файлът е повреден; тогава картинката се рисува по старому.
(int, int)? encodedImageSize(Uint8List b) {
  int be16(int i) => (b[i] << 8) | b[i + 1];
  int le16(int i) => b[i] | (b[i + 1] << 8);
  int be32(int i) => (b[i] << 24) | (b[i + 1] << 16) | (b[i + 2] << 8) | b[i + 3];
  bool tag(int i, String t) {
    if (i + t.length > b.length) return false;
    for (var k = 0; k < t.length; k++) {
      if (b[i + k] != t.codeUnitAt(k)) return false;
    }
    return true;
  }

  (int, int)? ok(int w, int h) => w > 0 && h > 0 ? (w, h) : null;
  try {
    if (b.length > 24 && b[0] == 0x89 && tag(1, 'PNG')) {
      return ok(be32(16), be32(20));
    }
    if (b.length > 10 && (tag(0, 'GIF87a') || tag(0, 'GIF89a'))) {
      return ok(le16(6), le16(8));
    }
    if (b.length > 30 && tag(0, 'RIFF') && tag(8, 'WEBP')) {
      if (tag(12, 'VP8 ')) return ok(le16(26) & 0x3FFF, le16(28) & 0x3FFF);
      if (tag(12, 'VP8L')) {
        final w = 1 + (b[21] | ((b[22] & 0x3F) << 8));
        final h = 1 + ((b[22] >> 6) | (b[23] << 2) | ((b[24] & 0x0F) << 10));
        return ok(w, h);
      }
      if (tag(12, 'VP8X')) {
        final w = 1 + (b[24] | (b[25] << 8) | (b[26] << 16));
        final h = 1 + (b[27] | (b[28] << 8) | (b[29] << 16));
        return ok(w, h);
      }
      return null;
    }
    if (b.length > 4 && b[0] == 0xFF && b[1] == 0xD8) {
      var i = 2;
      while (i + 9 < b.length) {
        if (b[i] != 0xFF) {
          i++;
          continue;
        }
        final m = b[i + 1];
        if (m == 0xFF) {
          i++;
          continue;
        }
        // SOF0–SOF15 без DHT (C4), JPG (C8) и DAC (CC).
        if (m >= 0xC0 && m <= 0xCF && m != 0xC4 && m != 0xC8 && m != 0xCC) {
          return ok(be16(i + 7), be16(i + 5));
        }
        if (m == 0xD8 || m == 0x01 || (m >= 0xD0 && m <= 0xD7)) {
          i += 2;
          continue;
        }
        i += 2 + be16(i + 2);
      }
    }
  } catch (_) {}
  return null;
}
