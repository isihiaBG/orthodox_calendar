// slova_volume.dart
//
// Томът „Слова" в „Месецослов" — словата и поученията на свт. Димитрий
// Ростовски, наредени по ЦЪРКОВНАТА година: от 1 септември (новолетието)
// до 31 август. Затова и корицата му стои между август и септември.
//
// ⚠ Текстовете НЕ се дублират: томът е само СЪДЪРЖАНИЕ, а четивата са
// същите, които дневният изглед показва в „Слова за деня" (lives_plus.db).
// Подвижните (неделите, Триодът, Пентикостарът) стоят на мястото си в
// ТАЗИ година — виж [LivesPlusDb.dmitryChronology].
//
// Отворено оттук, словото получава опашка „предишно / следващо" по същата
// хронология, като в томовете; отворено от календара — не (указание на
// потребителя: там то стои само, без съседи).

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_settings.dart';
import 'app_theme.dart';
import 'lives_plus.dart';
import 'molitvoslov_book.dart' show glideToRow;
import 'reader_footer.dart';
import 'reader_screen.dart';
import 'saint_expandable_tile.dart';

const List<String> _kMonths = [
  'януари', 'февруари', 'март', 'април', 'май', 'юни', 'юли', 'август',
  'септември', 'октомври', 'ноември', 'декември',
];
const List<String> _kShort = [
  'яну', 'фев', 'мар', 'апр', 'май', 'юни', 'юли', 'авг', 'сеп', 'окт', 'ное', 'дек',
];

/// Последно отвореното слово от тома — за синия ред и плъзгането до него.
class SlovaVolumeLast {
  SlovaVolumeLast._();
  static const String _key = 'slova_volume_last';
  static String? value;

  static Future<void> load() async {
    value = (await SharedPreferences.getInstance()).getString(_key);
  }

  static Future<void> set(String id) async {
    value = id;
    await (await SharedPreferences.getInstance()).setString(_key, id);
  }
}

/// Отваря [i]-тото слово от хронологията, с опашка към съседите.
Future<void> openVolumeSlovo(
    NavigatorState nav, List<DmitrySlovoDay> all, int i, {bool replace = false}) async {
  final s = all[i].slovo;
  final texts = await LivesPlusDb.load(s.slug);
  if (texts == null) return;
  SlovaVolumeLast.set(s.id);
  final route = MaterialPageRoute<void>(
    builder: (_) => ReaderScreen.life(
      texts: texts,
      lookup: lookupBySlug,
      lifeTitle: s.title,
      typeLabel: 'Слово',
      footer: (dim) => ReaderFooter(
        color: dim,
        left: i == 0
            ? null
            : FooterAction(
                icon: Icons.chevron_left,
                label: 'предишно',
                onTap: () => openVolumeSlovo(nav, all, i - 1, replace: true)),
        right: i == all.length - 1
            ? null
            : FooterAction(
                icon: Icons.chevron_right,
                label: 'следващо',
                onTap: () => openVolumeSlovo(nav, all, i + 1, replace: true)),
      ),
    ),
  );
  if (replace) {
    await nav.pushReplacement(route);
  } else {
    await nav.push(route);
  }
}

class SlovaVolume extends StatefulWidget {
  const SlovaVolume({super.key});

  @override
  State<SlovaVolume> createState() => _SlovaVolumeState();
}

class _SlovaVolumeState extends State<SlovaVolume> {
  List<DmitrySlovoDay>? _all;
  Object? _error;
  final ScrollController _scroll = ScrollController();
  final GlobalKey _lastKey = GlobalKey();

  static const double _kHeadH = 52, _kRowH = 58;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      await SlovaVolumeLast.load();
      final all = await LivesPlusDb.dmitryChronology(oldStyle: AppSettings.isOldStyle);
      if (!mounted) return;
      setState(() => _all = all);
      _reveal();
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  /// Плъзга видимо до последно отвореното — както в останалите съдържания.
  void _reveal() {
    final all = _all;
    final last = SlovaVolumeLast.value;
    if (all == null || last == null) return;
    final i = all.indexWhere((e) => e.slovo.id == last);
    if (i < 0) return;
    var months = 0;
    int? m;
    for (var k = 0; k <= i; k++) {
      if (all[k].church.month != m) {
        m = all[k].church.month;
        months++;
      }
    }
    final y = 8 + months * _kHeadH + i * _kRowH;
    WidgetsBinding.instance.addPostFrameCallback(
        (_) => glideToRow(_scroll, _lastKey, y, () => mounted));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        titleSpacing: 0,
        title: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Слова и поучения', style: TextStyle(fontSize: 18)),
          Text('свт. Димитрий Ростовски',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
        ]),
      ),
      // ⚠ Отстъп отстрани от изреза (в легнало камерата е на единия ръб и
      // текстът се пъхаше под нея). Горе/долу се пазят от лентата и системата.
      body: SafeArea(top: false, bottom: false, child: _body()),
    );
  }

  Widget _body() {
    if (_error != null) {
      return Center(
        child: Text('Грешка при четене на словата:\n$_error',
            style: const TextStyle(color: AppColors.textSecondary)),
      );
    }
    final all = _all;
    if (all == null) return const Center(child: CircularProgressIndicator());
    final rows = <Widget>[];
    int? month;
    for (var i = 0; i < all.length; i++) {
      final e = all[i];
      if (e.church.month != month) {
        month = e.church.month;
        rows.add(_monthHeader(month));
      }
      rows.add(_row(all, i));
    }
    return ListView(
      controller: _scroll,
      padding: const EdgeInsets.only(top: 8, bottom: 72),
      children: rows,
    );
  }

  /// Заглавие на месеца — ЦЪРКОВНИЯТ месец, в синьото на секциите.
  Widget _monthHeader(int m) => Container(
        height: _kHeadH,
        alignment: Alignment.bottomLeft,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.sectionDivider))),
        child: Text(_kMonths[m - 1].toUpperCase(),
            style: const TextStyle(
                color: AppColors.sectionTitle,
                fontSize: 14,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.0)),
      );

  Widget _row(List<DmitrySlovoDay> all, int i) {
    final e = all[i];
    final isLast = e.slovo.id == SlovaVolumeLast.value;
    return Material(
      key: isLast ? _lastKey : null,
      color: isLast ? AppColors.rowSelected : Colors.transparent,
      child: InkWell(
        onTap: () async {
          await openVolumeSlovo(Navigator.of(context), all, i);
          if (mounted) setState(() {});
        },
        child: Container(
          constraints: const BoxConstraints(minHeight: _kRowH),
          padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
          decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.sectionDivider, width: 0.5))),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Денят — колонка вляво, като в календара: числото едро, месецът
            // дребно под него. Църковната дата — по нея е и подредбата.
            SizedBox(
              width: 44,
              child: Column(children: [
                Text('${e.church.day}',
                    style: const TextStyle(
                        color: AppColors.textPrimary, fontSize: 18, height: 1.1)),
                Text(_kShort[e.church.month - 1],
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
              ]),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(e.slovo.title,
                    style: const TextStyle(color: AppColors.textPrimary, fontSize: 16, height: 1.25)),
              ),
            ),
            const SizedBox(width: 4),
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: Icon(Icons.chevron_right, color: AppColors.textMuted),
            ),
          ]),
        ),
      ),
    );
  }
}
