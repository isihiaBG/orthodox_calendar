// Изписва кратките бележки като JSON — за check_notes.py.
import 'dart:convert';
import 'package:orthodox_calendar/day_notes.dart';

void main() {
  final out = <Map<String, String>>[];
  void add(String key, List<DayNote> ns) {
    for (final n in ns) {
      out.add({'day': key, 'kind': n.kind.name, 'slug': n.slug,
               'passage': n.passage, 'text': n.text});
    }
  }
  kFixedDayNotes.forEach(add);
  kPaschaDayNotes.forEach((k, v) => add('pascha$k', v));
  print(jsonEncode(out));
}
