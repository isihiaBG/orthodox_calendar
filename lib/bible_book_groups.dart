// bible_book_groups.dart
//
// Дяловете, на които се делят книгите на Писанието.
//
// ⚠ Изнесени тук, защото ги ползват ДВА екрана: указателят (`bible_contents`)
// ги рисува като закотвени заглавия, а изборът на обхват за търсене
// (`bible_scope_screen`) — като разгъващи се групи с отметки. Преписани на
// две места, те щяха да се разминат при първата книга, добавена в единия.

class BibleBookGroup {
  final String title;
  final List<String> codes;
  const BibleBookGroup(this.title, this.codes);
}

/// ⚠ ЗАЩО ДЯЛОВЕ, А НЕ ЕДИН СПИСЪК. 50 книги, излети наведнъж, се четат като
/// стена: окото няма за какво да се хване и всяко търсене минава през
/// изброяване отгоре надолу. Дяловете са и естествената подредба на
/// Писанието — не са измислени за приложението.
///
/// ⚠ Книга, която НЕ Е в нито един дял, пак се показва — накрая, без
/// заглавие (виж `_grouped`). Така никоя не може да изчезне мълчаливо,
/// забрави ли се тук. Днес такава е 3 Ездра: в славянската Библия тя стои
/// подир пророците, извън дяловете, и точно така я подрежда и източникът.
const List<BibleBookGroup> kNtGroups = [
  BibleBookGroup('Евангелия', ['Mt', 'Mk', 'Lk', 'Jn']),
  // ⚠ „Деяния" стои БЕЗ заглавие на дял — то е една книга и заглавие над
  // единствен ред само би шумяло. Празният низ значи „без заглавие".
  BibleBookGroup('', ['Act']),
  BibleBookGroup('Съборни послания',
      ['Jac', '1Pet', '2Pet', '1Jn', '2Jn', '3Jn', 'Juda']),
  BibleBookGroup('Посланията на апостол Павел', [
    'Rom', '1Cor', '2Cor', 'Gal', 'Eph', 'Phil', 'Col',
    '1Thes', '2Thes', '1Tim', '2Tim', 'Tit', 'Phlm', 'Hebr',
  ]),
  BibleBookGroup('Пророческа книга', ['Apok']),
];

const List<BibleBookGroup> kOtGroups = [
  BibleBookGroup('Петокнижие', ['Gen', 'Ex', 'Lev', 'Num', 'Deut']),
  BibleBookGroup('Исторически книги', [
    'Nav', 'Judg', 'Rth', '1Sam', '2Sam', '1King', '2King',
    '1Chron', '2Chron', 'Ezr', '2Ezr', 'Nehem', 'Tov', 'Judf', 'Est',
    '1Mac', '2Mac', '3Mac',
  ]),
  BibleBookGroup('Учителни книги',
      ['Job', 'Ps', 'Prov', 'Eccl', 'Song', 'Solom', 'Sir']),
  BibleBookGroup('Пророчески книги', [
    'Is', 'Jer', 'Lam', 'pJer', 'Bar', 'Ezek', 'Dan', 'Hos', 'Joel', 'Am',
    'Avd', 'Jona', 'Mic', 'Naum', 'Habak', 'Sofon', 'Hag', 'Zah', 'Mal',
  ]),
];
