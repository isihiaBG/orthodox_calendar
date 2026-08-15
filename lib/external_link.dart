// external_link.dart
//
// Отваряне на ВЪНШНА препратка — общо за трите четеца (жития, книги и мини
// четеца в дневния изглед).
//
// Защо изобщо съществува:
//
// Библейските препратки в томовете са записани по правилата на XHTML, тъй
// че знакът „&" вътре в атрибут стои като `&amp;`:
//
//     href="https://azbyka.ru/biblia/?Ps.111:2&amp;bg~utfcs"
//
// Обикновен четец разчита файла като XML, връща го към `&` и отваря верния
// адрес — там Писанието излиза на български с успореден църковнославянски.
// При нас обаче `&amp;` стигаше до браузъра неразкодирано и azbyka.ru
// виждаше параметър на име `amp;bg~utfcs` вместо `bg~utfcs`. Резултатът:
// препратката се отваряше САМО на църковнославянски, при това ВИНАГИ, тъй
// че приличаше на прищявка на сайта, а не на наша грешка. (15.08.2026 —
// намерено, след като потребителят сравни със страничен четец.)
//
// Разкодирането тук е предпазно: направено е така, че двойно приложено да
// не вреди. Ако някой ден flutter_html започне да подава вече разкодиран
// адрес, редът просто няма какво да замени.

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Връща адреса такъв, какъвто трябва да отиде към браузъра.
///
/// ⚠ Редът е важен: `&amp;` се заменя ПОСЛЕДНО. Обратното превръща
/// `&amp;amp;` в `&`, вместо в `&amp;`.
String decodeHref(String url) => url
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&amp;', '&');

/// Отваря външна препратка, след като покаже адреса на потребителя.
///
/// Питането не е формалност: приложението чете офлайн, а тук изведнъж се
/// излиза навън. Човек трябва да види КЪДЕ отива, преди да реши — същото
/// прави и всеки сериозен четец на книги.
Future<void> openExternal(BuildContext context, String rawUrl) async {
  final url = decodeHref(rawUrl);
  final uri = Uri.tryParse(url);
  if (uri == null) return;

  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Външна препратка'),
      content: SelectableText(
        url,
        style: const TextStyle(fontSize: 14, height: 1.4),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Отказ'),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Отвори'),
        ),
      ],
    ),
  );
  if (ok != true) return;
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}
