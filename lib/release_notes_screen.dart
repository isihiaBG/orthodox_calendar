// release_notes_screen.dart
//
// „История на промените" (от „За приложението", 26.10.2026). Отгоре —
// версиите от въвеждането на номерацията (0.9.<билд>) с кратко описание,
// най-новото първо; отдолу — „По-ранна история" по етапи, назад до началото.
//
// ⚠ ИЗВОРЪТ Е assets/release_notes.json — същият, от който публикуването
// (tools/release/publish_app.py) прави „Какво ново" в update.json. Един
// текст, две места; не се преписва. Вграден е в пакета, тъй че екранът
// работи без интернет.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:url_launcher/url_launcher.dart';

import 'app_theme.dart';

const String _body = 'CharisSIL';
const String _changelogUrl =
    'https://github.com/isihiaBG/orthodox_calendar/blob/main/'
    '%D0%98%D1%81%D1%82%D0%BE%D1%80%D0%B8%D1%8F%20%D0%BD%D0%B0%20%D0%BF%D1%80%D0%BE%D0%BC%D0%B5%D0%BD%D0%B8%D1%82%D0%B5%20(ChangeLog).md';

const _months = [
  'януари', 'февруари', 'март', 'април', 'май', 'юни', 'юли', 'август',
  'септември', 'октомври', 'ноември', 'декември',
];

class ReleaseNotesScreen extends StatelessWidget {
  const ReleaseNotesScreen({super.key});

  static Future<Map<String, dynamic>> _load() async =>
      jsonDecode(await rootBundle.loadString('assets/release_notes.json'))
          as Map<String, dynamic>;

  /// „26 октомври 2026" → „26.10.2026" — кратко, до номера на версията.
  static String _shortDate(String d) {
    final p = d.split(' ');
    final m = p.length == 3 ? _months.indexOf(p[1]) + 1 : 0;
    return m > 0 ? '${p[0].padLeft(2, '0')}.${m.toString().padLeft(2, '0')}.${p[2]}' : d;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.toolbar,
      body: SafeArea(
        bottom: false,
        child: Container(
          color: AppColors.background,
          child: FutureBuilder<Map<String, dynamic>>(
            future: _load(),
            builder: (context, snap) {
              final slivers = <Widget>[
                const SliverAppBar(
                  backgroundColor: AppColors.toolbar,
                  floating: true,
                  snap: true,
                  title: Text('История на промените'),
                ),
              ];
              final d = snap.data;
              if (d != null) {
                slivers.add(SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                      22, 18, 22, 40 + MediaQuery.of(context).padding.bottom),
                  sliver: SliverList.list(children: _content(context, d)),
                ));
              } else if (snap.hasError) {
                slivers.add(const SliverFillRemaining(
                  child: Center(
                      child: Text('Историята не можа да се прочете.',
                          style: TextStyle(color: AppColors.textSecondary))),
                ));
              }
              return CustomScrollView(slivers: slivers);
            },
          ),
        ),
      ),
    );
  }

  List<Widget> _content(BuildContext context, Map<String, dynamic> d) {
    final out = <Widget>[];
    final versions = (d['versions'] as List).cast<Map<String, dynamic>>();
    for (var i = 0; i < versions.length; i++) {
      final v = versions[i];
      out.add(_entry(
        title: 'Версия 0.9.${v['build']}',
        aside: _shortDate(v['date'] as String? ?? ''),
        items: (v['items'] as List).cast<String>(),
        first: i == 0,
      ));
    }
    out.add(_ornament('По-ранна история'));
    for (final e in (d['earlier'] as List).cast<Map<String, dynamic>>()) {
      out.add(_entry(
        title: e['period'] as String,
        items: (e['items'] as List).cast<String>(),
        period: true,
      ));
    }
    out.add(const SizedBox(height: 18));
    out.add(Center(
      child: TextButton.icon(
        onPressed: () => launchUrl(Uri.parse(_changelogUrl),
            mode: LaunchMode.externalApplication),
        icon: const Icon(Icons.open_in_new, size: 16),
        label: const Text('Пълната история в GitHub'),
        style: TextButton.styleFrom(foregroundColor: AppColors.sectionTitle),
      ),
    ));
    return out;
  }

  /// Една версия или един етап: заглавие (с дата вдясно) и кратки редове.
  Widget _entry({
    required String title,
    String? aside,
    required List<String> items,
    bool first = false,
    bool period = false,
  }) {
    return Padding(
      padding: EdgeInsets.only(top: first ? 4 : 22),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic, children: [
          Expanded(
            child: Text(title,
                style: TextStyle(
                  fontFamily: _body,
                  fontSize: period ? 17 : 18,
                  fontWeight: FontWeight.w700,
                  color: period ? AppColors.sectionTitle : AppColors.textPrimary,
                  letterSpacing: period ? 0.4 : 0,
                )),
          ),
          if (aside != null && aside.isNotEmpty)
            Text(aside,
                style: const TextStyle(
                    fontSize: 13, color: AppColors.textMuted, letterSpacing: 0.4)),
        ]),
        const SizedBox(height: 8),
        for (final it in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Padding(
                padding: EdgeInsets.only(top: 1, right: 10),
                child: Text('•',
                    style: TextStyle(color: AppColors.sectionTitle, fontSize: 16)),
              ),
              Expanded(
                child: Text(it,
                    style: const TextStyle(
                        fontFamily: _body,
                        fontSize: 16,
                        height: 1.4,
                        color: AppColors.textSecondary)),
              ),
            ]),
          ),
      ]),
    );
  }

  /// Разделителят пред „По-ранна история" — тънки линии и надпис.
  Widget _ornament(String text) {
    Widget line() => Expanded(
        child: Container(height: 1, color: AppColors.sectionDivider));
    return Padding(
      padding: const EdgeInsets.only(top: 40, bottom: 4),
      child: Row(children: [
        line(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(text.toUpperCase(),
              style: const TextStyle(
                  fontSize: 12,
                  letterSpacing: 2,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textMuted)),
        ),
        line(),
      ]),
    );
  }
}
