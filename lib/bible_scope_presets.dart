// bible_scope_presets.dart
//
// Запомнените набори книги за търсене.
//
// ⚠ ЗАЩО ИЗОБЩО. Отмятането на десетина книги е работа за минута, а човек, който
// търси по Евангелията, ще я върши всяка седмица. Запомненият набор превръща
// тази минута в два тапа — и точно затова записът и зареждането стоят до
// самото отмятане, а не в общите настройки.
//
// ⚠ Пази се в SharedPreferences като JSON списък, под ЕДИН ключ. Наборите са
// малко (човек няма да направи и двайсет), а един ключ значи един прочит и
// един запис — без нужда от индекс и без сираци, ако запис се провали по
// средата.

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'bible_search_settings.dart';

/// Един запомнен набор.
class BibleScopePreset {
  final String name;

  /// Кога е записан — показва се в списъка и по него се подрежда.
  final DateTime saved;

  final BibleScopePick pick;

  const BibleScopePreset({
    required this.name,
    required this.saved,
    required this.pick,
  });

  /// Колко „места" носи наборът — за реда в списъка.
  ///
  /// ⚠ Псалтирът на части се брои за ЕДНО, не за толкова, колкото са
  /// катизмите: за човека това е една книга, избрана отчасти, а не двайсет
  /// отделни неща.
  int get count => pick.books.length + (pick.kathismata.isEmpty ? 0 : 1);

  Map<String, dynamic> toJson() => {
        'name': name,
        'saved': saved.toIso8601String(),
        'pick': pick.encode(),
      };

  static BibleScopePreset? fromJson(Map<String, dynamic> j) {
    final name = j['name'];
    final saved = DateTime.tryParse(j['saved']?.toString() ?? '');
    if (name is! String || saved == null) return null;
    return BibleScopePreset(
      name: name,
      saved: saved,
      pick: BibleScopePick.decode(j['pick']?.toString()),
    );
  }
}

/// Как е подреден списъкът със запомнените набори.
enum BiblePresetSort { date, name }

class BibleScopePresets {
  BibleScopePresets._();

  static const _key = 'bible_scope_presets';

  static Future<List<BibleScopePreset>> all() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw);
      if (list is! List) return const [];
      return [
        for (final e in list)
          if (e is Map<String, dynamic>) ?BibleScopePreset.fromJson(e)
      ];
    } catch (_) {
      // ⚠ Повреден запис НЕ гърми и не се трие: връща се празен списък, а
      // редът остава на диска. Ако утре се окаже, че е четим (нова версия на
      // формата), нищо не е загубено — а човек и без това не може да поправи
      // JSON от телефона си.
      return const [];
    }
  }

  /// Подредени за показване.
  ///
  /// ⚠ По ДАТА подредбата е НАЙ-НОВОТО ОТГОРЕ, а по име — азбучно. Двете са
  /// различни очаквания: датата се гледа, за да се хване „онова отпреди малко",
  /// а името — за да се намери познато.
  static List<BibleScopePreset> sorted(
      List<BibleScopePreset> list, BiblePresetSort by) {
    final out = [...list];
    switch (by) {
      case BiblePresetSort.date:
        out.sort((a, b) => b.saved.compareTo(a.saved));
      case BiblePresetSort.name:
        out.sort((a, b) =>
            a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    }
    return out;
  }

  /// Има ли вече набор с това име (сравнението е БЕЗ оглед на регистъра и
  /// околните интервали — „Евангелия" и „евангелия " са едно и също за човека).
  static BibleScopePreset? findByName(
      List<BibleScopePreset> list, String name) {
    final n = name.trim().toLowerCase();
    for (final p in list) {
      if (p.name.trim().toLowerCase() == n) return p;
    }
    return null;
  }

  /// Записва — или ЗАМЕСТВА този със същото име.
  static Future<void> save(BibleScopePreset preset) async {
    final list = [...await all()];
    final existing = findByName(list, preset.name);
    if (existing != null) list.remove(existing);
    list.add(preset);
    await _write(list);
  }

  static Future<void> remove(BibleScopePreset preset) async {
    final list = [...await all()]
      ..removeWhere((p) =>
          p.name == preset.name && p.saved == preset.saved);
    await _write(list);
  }

  static Future<void> _write(List<BibleScopePreset> list) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _key, jsonEncode([for (final p in list) p.toJson()]));
  }

  /// Първото свободно име от вида „Селекция 3" — предлага се в полето.
  ///
  /// ⚠ Брои се до първата ДУПКА, а не се взима „последното + 1": изтрие ли се
  /// „Селекция 2", следващият запис заема нейното име вместо да прескача на 4.
  /// Инак номерата растат безкрайно и започват да изглеждат като брояч на
  /// нещо, каквото не са.
  static String suggestName(List<BibleScopePreset> list) {
    final taken = {
      for (final p in list) p.name.trim().toLowerCase(),
    };
    for (var i = 1;; i++) {
      final name = 'Селекция $i';
      if (!taken.contains(name.toLowerCase())) return name;
    }
  }
}
