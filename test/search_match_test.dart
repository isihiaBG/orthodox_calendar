import 'package:flutter_test/flutter_test.dart';
import 'package:orthodox_calendar/search_match.dart';

void main() {
  test('ключови думи, не фраза', () {
    final q = searchTerms('  содом   гомор ');
    expect(q, ['содом', 'гомор']);
    const text = 'жителите на Содомски и Гоморски градове';
    expect(containsAllTerms(text, q), isTrue);
    final m = matchRanges(text, q);
    expect(m.map((r) => text.substring(r.start, r.end)).toList(),
        ['Содом', 'Гомор']);
  });

  test('липсваща дума значи ненамерено', () {
    expect(containsAllTerms('Содом и Гомора', searchTerms('содом ниневия')),
        isFalse);
  });

  test('застъпени съвпадения се сливат', () {
    final m = matchRanges('Содом', searchTerms('сод одом'));
    expect(m.length, 1);
    expect('Содом'.substring(m.first.start, m.first.end), 'Содом');
  });

  test('празна заявка не намира нищо', () {
    expect(searchTerms('   '), isEmpty);
    expect(containsAllTerms('каквото и да е', searchTerms('  ')), isFalse);
    expect(matchRanges('текст', const []), isEmpty);
  });

  test('повтарящо се съвпадение се намира на всяко място', () {
    // „на" стои на 0 („на"), 3 (в „нас") и 7 („на") — три места.
    final m = matchRanges('на нас на них', searchTerms('на'));
    expect(m.length, 3);
    expect(m.first.start, 0);
    expect(m.last.start, 7);
  });
}
