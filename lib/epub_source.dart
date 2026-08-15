// epub_source.dart
//
// Четене на .epub НАЖИВО — томовете си остават книги, не се превръщат в
// база данни.
//
// Защо така: житията по св. Димитрий Ростовски са 12 тома, 19 MB, всеки с
// по ~118 глави и стотици бележки. Превръщането им в таблици би загубило
// точно това, което ги прави книга (реда, съдържанието, бележките на място)
// и би удвоило работата при всяка поправка в превода. Затова .epub-ът е
// източникът, а конвейерът в tools/Translate_lives/ си остава единственият,
// който го произвежда.
//
// Устройство на един .epub — това е обикновен ZIP:
//
//   META-INF/container.xml     сочи къде е .opf
//   OEBPS/content.opf          манифест (какви файлове има) + spine (в какъв
//                              ред се четат)
//   OEBPS/toc.ncx              съдържанието, йерархично
//   OEBPS/Text/*.xhtml         главите и бележките
//
// Архивът се чете ВЕДНЪЖ и се държи в паметта (1,6 MB на том), защото
// главите се отварят една след друга и повторното разархивиране при всяко
// прелистване е излишно. Чете се ПРАВО от пакета — за разлика от базите тук
// няма копие на диска (виж EpubBook.open защо и какво струваше то).
//
// ТУК НЕ СЕ РИСУВА НИЩО. Този файл само вади текст и структура; как
// изглежда книгата решава четецът.

import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;

/// Един запис от съдържанието. Може да има подзаписи — в житията първото
/// ниво са дните („Памет на 1 септември"), второто са самите жития.
class EpubTocEntry {
  final String title;

  /// Пътят вътре в архива, вече разрешен спрямо мястото на toc.ncx.
  /// Празен низ значи заглавие без собствена страница (само групиращо).
  final String href;

  /// Котвата след „#", ако записът сочи към средата на файл.
  final String? anchor;

  final List<EpubTocEntry> children;

  const EpubTocEntry({
    required this.title,
    required this.href,
    this.anchor,
    this.children = const [],
  });

  /// Всички записи в реда на четене — за търсене и за „следваща глава".
  Iterable<EpubTocEntry> flattened() sync* {
    yield this;
    for (final c in children) {
      yield* c.flattened();
    }
  }
}

/// Отворена книга: архивът, редът на главите и съдържанието.
class EpubBook {
  final String assetPath;
  final String title;

  /// Пътищата на главите в реда, в който се четат (spine на .opf).
  final List<String> spine;

  final List<EpubTocEntry> toc;

  final Archive _archive;

  EpubBook._({
    required this.assetPath,
    required this.title,
    required this.spine,
    required this.toc,
    required Archive archive,
  }) : _archive = archive;

  /// Суровият XHTML на една глава. null, ако пътят го няма в архива.
  String? readFile(String path) {
    final f = _archive.findFile(path);
    if (f == null) return null;
    return utf8.decode(f.content as List<int>, allowMalformed: true);
  }

  /// Байтовете на файл (за изображения).
  Uint8List? readBytes(String path) {
    final f = _archive.findFile(path);
    if (f == null) return null;
    return Uint8List.fromList(f.content as List<int>);
  }

  int indexInSpine(String href) => spine.indexOf(href);

  // ── Отваряне ────────────────────────────────────────────────────────────

  /// Разчита .epub-а ПРАВО от assets, без копие на диска.
  ///
  /// ⚠ Дотук книгата се копираше в getApplicationSupportDirectory() и се
  /// четеше оттам, „защото от bundle-а няма произволен достъп до файл".
  /// Това беше излишно: `ZipDecoder.decodeBytes` работи с байтове, а те
  /// идват от `rootBundle.load` наготово — файлът се записваше само за да
  /// бъде прочетен обратно.
  ///
  /// Копието обаче се правеше САМО ако още го няма („if (!await
  /// file.exists())"), тъй че щом веднъж се запишеше, нов билд с поправен
  /// том вече не стигаше до четеца. Симптомът е коварен: приложението
  /// показва стария текст, а файлът в assets/ е верният, и единственият
  /// лек е изчистване на данните. (Загубени над час на 15.08.2026 по
  /// заглавната страница на житията.)
  ///
  /// Оттук нататък източникът е един — пакетът, — и такова разминаване не
  /// може да се получи. Пътьом отпадат и 19 MB второ копие на устройството.
  static Future<EpubBook> open(String assetPath) async {
    final data = await rootBundle.load(assetPath);
    final archive = ZipDecoder().decodeBytes(data.buffer.asUint8List());
    return _parse(assetPath, archive);
  }

  static EpubBook _parse(String assetPath, Archive archive) {
    // 1. container.xml → пътят до .opf. Не се предполага „OEBPS/content.opf":
    //    той е конвенция, не правило, и различните производители го местят.
    final container = _text(archive, 'META-INF/container.xml');
    final opfPath = container == null
        ? null
        : RegExp(r'full-path="([^"]+)"').firstMatch(container)?.group(1);
    if (opfPath == null) {
      throw StateError('$assetPath: няма META-INF/container.xml с full-path');
    }
    final opfDir = p.dirname(opfPath);
    final opf = _text(archive, opfPath);
    if (opf == null) throw StateError('$assetPath: липсва $opfPath');

    // 2. Манифестът: id → път. Spine-ът сочи по id, не по път.
    final byId = <String, String>{};
    for (final m in RegExp(r'<item\b([^>]*)/?>').allMatches(opf)) {
      final attrs = m.group(1)!;
      final id = RegExp(r'\bid="([^"]+)"').firstMatch(attrs)?.group(1);
      final href = RegExp(r'\bhref="([^"]+)"').firstMatch(attrs)?.group(1);
      if (id != null && href != null) {
        byId[id] = _join(opfDir, Uri.decodeComponent(href));
      }
    }

    // 3. Spine: редът на четене.
    final spine = <String>[];
    for (final m in RegExp(r'<itemref\b([^>]*)/?>').allMatches(opf)) {
      final idref =
          RegExp(r'\bidref="([^"]+)"').firstMatch(m.group(1)!)?.group(1);
      final path = idref == null ? null : byId[idref];
      if (path != null) spine.add(path);
    }

    final title = RegExp(r'<dc:title[^>]*>(.*?)</dc:title>', dotAll: true)
            .firstMatch(opf)
            ?.group(1)
            ?.trim() ??
        p.basenameWithoutExtension(assetPath);

    // 4. Съдържанието. EPUB 2 го държи в .ncx, EPUB 3 — в nav.xhtml; нашите
    //    томове носят .ncx, затова започваме с него.
    final ncxPath = byId.values.firstWhere(
      (v) => v.toLowerCase().endsWith('.ncx'),
      orElse: () => '',
    );
    final toc = ncxPath.isEmpty
        ? <EpubTocEntry>[]
        : _parseNcx(_text(archive, ncxPath) ?? '', p.dirname(ncxPath));

    return EpubBook._(
      assetPath: assetPath,
      title: _unescape(title),
      spine: spine,
      toc: toc,
      archive: archive,
    );
  }

  /// Разчита toc.ncx, като ПАЗИ вложеността.
  ///
  /// Върви по низа и следи дълбочината сам, вместо да ползва XML разбор:
  /// файлът е плосък текст без изненади, а пълният разбор би довлякъл
  /// зависимост за нещо, което е двайсетина реда.
  static List<EpubTocEntry> _parseNcx(String ncx, String ncxDir) {
    final navMap = RegExp(r'<navMap.*?</navMap>', dotAll: true).firstMatch(ncx);
    if (navMap == null) return [];
    final body = navMap.group(0)!;

    final roots = <EpubTocEntry>[];
    // Стек от списъци: на всяко ниво се трупат децата му.
    final stack = <List<EpubTocEntry>>[roots];
    final pending = <_PendingNav>[];

    final token = RegExp(
      r'<navPoint\b|</navPoint>|<text>(.*?)</text>|<content\b[^>]*src="([^"]+)"',
      dotAll: true,
    );

    for (final m in token.allMatches(body)) {
      final s = m.group(0)!;
      if (s.startsWith('<navPoint')) {
        pending.add(_PendingNav());
        stack.add(<EpubTocEntry>[]);
      } else if (s.startsWith('</navPoint>')) {
        if (pending.isEmpty) continue;
        final nav = pending.removeLast();
        final children = stack.removeLast();
        stack.last.add(EpubTocEntry(
          title: _unescape(nav.title.trim()),
          href: nav.href,
          anchor: nav.anchor,
          children: children,
        ));
      } else if (s.startsWith('<text>')) {
        // Първият <text> след <navPoint> е заглавието му. По-нататъшните
        // принадлежат на вложените точки и вече имат свой pending.
        if (pending.isNotEmpty && pending.last.title.isEmpty) {
          pending.last.title = m.group(1) ?? '';
        }
      } else {
        if (pending.isEmpty) continue;
        final src = Uri.decodeComponent(m.group(2)!);
        final hash = src.indexOf('#');
        pending.last.href =
            _join(ncxDir, hash < 0 ? src : src.substring(0, hash));
        pending.last.anchor = hash < 0 ? null : src.substring(hash + 1);
      }
    }
    return roots;
  }

  static String? _text(Archive a, String path) {
    final f = a.findFile(path);
    if (f == null) return null;
    return utf8.decode(f.content as List<int>, allowMalformed: true);
  }

  /// Пътищата в .epub са относителни спрямо файла, който ги сочи.
  static String _join(String dir, String href) =>
      dir.isEmpty || dir == '.' ? href : p.normalize(p.join(dir, href));

  static String _unescape(String s) => s
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&#39;', "'");
}

class _PendingNav {
  String title = '';
  String href = '';
  String? anchor;
}
