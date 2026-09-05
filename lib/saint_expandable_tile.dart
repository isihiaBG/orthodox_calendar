// saint_expandable_tile.dart
//
// Разгъващ се булет на светия за дневния изглед — LAZY версия,
// интегрирана към реалната архитектура на приложението:
//
//  - Дневната заявка НЕ тегли текстовете (те са до 130 KB на житие!),
//    а само два евтини флага: has_prayers, has_life.
//  - Пълните текстове се зареждат чак при тап върху секция, през
//    подадената loadTexts() функция.
//  - В свито състояние редът изглежда точно както досега (подава се
//    готов collapsedRow). Триъгълниче вдясно има само ако има текстове.
//  - Разгънато: до две секции с chevron — "Тропар и кондак" и "Житие".

import 'package:flutter/material.dart';

import 'app_settings.dart';
import 'app_theme.dart';
import 'database_helper.dart';
import 'dmitry_life.dart';
import 'lives_index.dart';
import 'reader_screen.dart';
import 'reference_text.dart';

/// Едно песнопение — ред от таблицата `lives.hymns`.
///
/// Дотогава тропарите и кондаците стояха в осем колони на `texts`
/// (tropar, tropar2, kondak, kondak2 + преводите), тоест най-много по два
/// от вид. Това отрязваше 93 тропара и 57 кондака у 77 светии, а молитвите
/// и величанията не се показваха изобщо. Прп. Иоан Рилски например има три
/// тропара и пет кондака, като третият тропар е тъкмо онзи, който БПЦ пее
/// като негов основен.
class Hymn {
  /// tropar | kondak | molitva | velichanie | other
  final String kind;

  /// Заглавието, както стои в богослужебната книга: "Тропарь", "Ин
  /// тропарь", "2-я Молитва". ⚠ Църковнославянско е и ТАКА ОСТАВА — то е
  /// част от славянския блок, не негов превод. Преводът отдолу е с курсив.
  final String kindRu;

  /// "глас 4" или празно (молитвите и величанията нямат глас).
  final String glas;

  /// Църковнославянският текст, без заглавната част.
  final String csl;

  /// Българският превод. Празен при молитвите и величанията — azbyka не
  /// дава руски превод за тях, тъй че няма от какво да се преведат.
  final String bg;

  const Hymn({
    required this.kind,
    this.kindRu = '',
    this.glas = '',
    this.csl = '',
    this.bg = '',
  });

  factory Hymn.fromMap(Map<String, dynamic> m) => Hymn(
        kind: (m['kind'] ?? '') as String,
        kindRu: (m['kind_ru'] ?? '') as String,
        glas: (m['glas'] ?? '') as String,
        csl: (m['csl'] ?? '') as String,
        bg: (m['bg'] ?? '') as String,
      );

  /// Редът над текста: "Ин тропарь, глас 4". Празен, ако няма заглавие —
  /// такива са осемте стари превода без църковнославянски оригинал.
  String get heading {
    if (kindRu.isEmpty) return '';
    return glas.isEmpty ? kindRu : '$kindRu, $glas';
  }
}

/// Текстовете на един светия (ред от таблицата saints с новите колони).
class SaintTexts {
  final String name;

  /// Песнопенията по реда на страницата — тропари, кондаци, молитви,
  /// величания. Празен списък, ако светията няма нито едно.
  final List<Hymn> hymns;
  final String lifeHtml;
  final String sluzhba;
  final String source; // URL за атрибуция под житието
  final String slug;

  /// ЦЪРКОВНАТА дата на паметта — за името на споделяния PDF.
  ///
  /// ⚠ null при ПОДВИЖНИТЕ памети. Те нямат дата в месецослова: падат се
  /// според Пасхата и се менят всяка година, тъй че „Памет на 14.фев."
  /// пред тях би било невярно. Признакът идва от колоната `saints.movable`,
  /// която генераторът пълни по СПИСЪКА, от който е дошъл записът — виж
  /// `build_saints()` в tools/calendar_gen/build.py.
  ///
  /// ⚠ При НОВ СТИЛ това е самата гражданска дата; при СТАР — тя минус 13.
  /// (Бележка на потребителя, 01.09.2026: новостилната дата СЪВПАДА с
  /// църковната и не бива да се превръща втори път.)
  final DateTime? memoryDate;

  const SaintTexts({
    required this.name,
    this.hymns = const [],
    this.lifeHtml = '',
    this.sluzhba = '',
    this.source = '',
    this.slug = '',
    this.memoryDate,
  });

  factory SaintTexts.fromMap(Map<String, dynamic> m,
          {List<Hymn> hymns = const [], DateTime? memoryDate}) =>
      SaintTexts(
        name: (m['name'] ?? '') as String,
        hymns: hymns,
        lifeHtml: (m['life'] ?? '') as String,
        sluzhba: (m['sluzhba'] ?? '') as String,
        source: (m['source'] ?? '') as String,
        slug: (m['slug'] ?? '') as String,
        memoryDate: memoryDate,
      );

  /// Църковната дата на паметта от ред на `saints`, или null за подвижните.
  ///
  /// ⚠ ЕДНО МЯСТО за превръщането — инак всеки викащ пише „минус 13" по
  /// своему и рано или късно го прилага и в новостилния календар, където
  /// гражданската дата ВЕЧЕ Е църковната.
  static DateTime? churchDateOf(Object? civilDate, Object? movable) {
    if (civilDate == null) return null;
    if (movable is int && movable != 0) return null;
    final d = DateTime.tryParse(civilDate.toString());
    if (d == null) return null;
    return AppSettings.isOldStyle
        ? d.subtract(const Duration(days: 13))
        : d;
  }

  bool hasKind(String kind) => hymns.any((h) => h.kind == kind);

  bool get hasPrayers => hymns.isNotEmpty;
  bool get hasLife => lifeHtml.isNotEmpty;
  bool get hasSluzhba => sluzhba.isNotEmpty;
}

/// Търсене по слъг — за saint:// линковете в житията.
typedef SaintLookup = Future<SaintTexts?> Function(String slug);

/// Реализацията на SaintLookup — за saint:// линковете в житията, а и за
/// всяко друго място, нуждаещо се от пълните текстове по слъг (напр.
/// HolidaysScreen). Стои ТУК, до SaintTexts, а не в някой екран, за да е
/// достъпна отвсякъде без кръстосани зависимости между екраните.
///
/// ТУК Е ПЕЧАЛБАТА ОТ ОТДЕЛНАТА БАЗА: тръгва се от lives.texts, не от
/// календара. Иначе линк към светия без календарен ред казваше "няма
/// запис" — а такива са стотици: светогорците, които се честват само на
/// подвижния съборен ден, и всички, към които житията препращат, без да
/// са в тазгодишния календар.
///
/// Календарът се закача отляво САМО за името: ако светията има ред в
/// него, показваме българското име; ако няма — падаме към името от
/// lives (то е руското от azbyka и затова се превежда).
Future<SaintTexts?> lookupBySlug(String slug) async {
  // Справочните статии живеят в СВОЯ база (reference.db), не в lives.db.
  // Проверката е тук, а не при извикващите, за да важи за всеки път, който
  // разрешава слъг — включително списъка с отметки в четеца, който знае
  // само слъга на запазеното четиво.
  if (isReferenceSlug(slug)) return loadReferenceArticle(slug);
  // Бележките на свт. Теофан — също своя база (teofan.db), по същата
  // причина: слъгът трябва да се разрешава и от списъка с отметки.
  if (isTeofanNoteSlug(slug)) return loadTeofanNote(slug);

  final db = await DatabaseHelper.database;
  final r = await db.rawQuery('''
    SELECT COALESCE(NULLIF(s.name, ''), l.name) AS name,
           l.life, l.sluzhba, l.source, l.slug
    FROM lives.texts l
    LEFT JOIN saints s ON s.slug = l.slug
    WHERE l.slug = ?
    LIMIT 1
  ''', [slug]);
  if (r.isEmpty) return null;
  return SaintTexts.fromMap(r.first, hymns: await loadHymns(slug));
}

/// Песнопенията на един светия, по реда на страницата.
///
/// Отделна заявка, а не JOIN към texts: редовете са много на един светия
/// и JOIN-ът би размножил житието (до 130 KB) по веднъж за всяко.
Future<List<Hymn>> loadHymns(String slug) async {
  final db = await DatabaseHelper.database;
  final rows = await db.rawQuery('''
    SELECT kind, kind_ru, glas, csl, bg
    FROM lives.hymns
    WHERE slug = ?
    ORDER BY ord
  ''', [slug]);
  return rows.map(Hymn.fromMap).toList();
}

/// Едно четиво по Димитрий Ростовски — ред от saint_dmitry_refs
/// (assets/db/lives.db), виж CLAUDE.md за архитектурата (slug вместо
/// saints.id, защото последният се преномерира при всяко прегенериране).
class DmitryRef {
  /// Номерът на статията в azbyka.ru — ключ в assets/lives_index.json.
  final int num;

  /// main (основно сказание) | slovo (проповед) | sub (втори епизод от
  /// същото събитие/спътник, споменат в общ ред) — виж CLAUDE.md.
  final String kind;

  const DmitryRef({required this.num, required this.kind});
}

/// От низа, който заявката връща: "num:kind,num:kind" — същия принцип
/// като hymn_counts, за да не се добавя JOIN, който би размножил реда.
List<DmitryRef> parseDmitryRefs(String? packed) {
  if (packed == null || packed.isEmpty) return const [];
  final out = <DmitryRef>[];
  for (final pair in packed.split(',')) {
    final i = pair.indexOf(':');
    if (i <= 0) continue;
    final num = int.tryParse(pair.substring(0, i));
    if (num == null) continue;
    out.add(DmitryRef(num: num, kind: pair.substring(i + 1)));
  }
  // По РЕДА, в който четивата стоят в самата книга — не по вид. "main"
  // не значи непременно "първо в книгата": на Рождество Христово напр.
  // книгата подрежда встъпителна част (sub), после сказанието (main),
  // после отделен епизод (sub) — sortирането по kind разбъркваше реда и
  // объркваше кой ред носи генеричния етикет.
  out.sort((a, b) => a.num.compareTo(b.num));
  return out;
}

/// Кой раздел се отваря при тап върху секция.
enum _Section { prayers, life, sluzhba }

/// Имената на видовете за етикета: (единствено число, множествено).
///
/// Непознат вид пада към последния ред. Така утрешна добавка в данните
/// (икос, светилен, задостойник…) минава сама, без промяна тук: тя ще се
/// класифицира като `other` от 14_extract_hymns.py и ще се изпише
/// „песнопение". Добави ѝ ред само ако искаш собственото ѝ име.
const Map<String, (String, String)> _kindNames = {
  'tropar': ('тропар', 'тропари'),
  'kondak': ('кондак', 'кондаци'),
  'molitva': ('молитва', 'молитви'),
  'velichanie': ('величание', 'величания'),
  // ⚠ Акатистът е ЕДНО произведение от 25 части (13 кондака и 12 икоса), а
  // не сбор от песнопения. Затова влиза в таблицата като ЕДИН ред и
  // етикетът го назовава поименно — инак излизаше „26 кондака".
  'akatist': ('акатист', 'акатисти'),
  'other': ('песнопение', 'песнопения'),
};

/// Редът на изброяване — както стоят на страницата и в книгите:
/// тропар, кондак, молитва, величание. Вид извън списъка отива накрая.
const List<String> _kindOrder = [
  'tropar',
  'kondak',
  'molitva',
  'velichanie',
  // ⚠ Акатистът е НАКРАЯ: той е най-обширният и в книгите стои подир
  // кратките песнопения.
  'akatist',
  'other',
];

/// Етикетът на секцията с песнопенията: „Тропар и кондак", „Тропари,
/// кондаци и молитви", „Молитва". Празен низ = няма нищо.
///
/// [counts] е вид → брой. Строи се от данните, а не от изброени случаи:
/// в базата днес има десет различни комбинации, а утре може да дойде
/// друга. Числото на всяка дума следва броя ѝ — три тропара дават
/// „тропари".
///
/// ⚠ Дотогава етикетът знаеше само за тропар и кондак и връщаше празно
/// за всичко друго. Трима светии имат САМО молитви (св. Фотина
/// Самарянка, св. Юрий Новицки, мчци Хрисант и Дария) — за тях секцията
/// не се показваше изобщо и молитвите им оставаха недостъпни. Още 307
/// имат молитва или величание, скрити зад етикет „Тропар и кондак".
String prayersLabel(Map<String, int> counts) {
  final parts = <String>[];
  final kinds = counts.keys.toList()
    ..sort((a, b) {
      final ia = _kindOrder.indexOf(a), ib = _kindOrder.indexOf(b);
      return (ia < 0 ? _kindOrder.length : ia)
          .compareTo(ib < 0 ? _kindOrder.length : ib);
    });
  for (final k in kinds) {
    final n = counts[k] ?? 0;
    if (n <= 0) continue;
    final names = _kindNames[k] ?? _kindNames['other']!;
    parts.add(n == 1 ? names.$1 : names.$2);
  }
  if (parts.isEmpty) return '';
  // „а", „а и б", „а, б и в" — последното се съединява с „и".
  final joined = parts.length == 1
      ? parts.first
      : '${parts.sublist(0, parts.length - 1).join(', ')} и ${parts.last}';
  return joined[0].toUpperCase() + joined.substring(1);
}

/// Броевете по вид от низа, който заявките връщат: "tropar:3,kondak:5".
///
/// Кодирани са в едно поле, за да не се добавя по колона за всеки нов
/// вид — заявката е `group_concat` и не знае какви видове има.
Map<String, int> parseHymnCounts(String? packed) {
  final out = <String, int>{};
  if (packed == null || packed.isEmpty) return out;
  for (final pair in packed.split(',')) {
    final i = pair.indexOf(':');
    if (i <= 0) continue;
    final n = int.tryParse(pair.substring(i + 1));
    if (n != null && n > 0) out[pair.substring(0, i)] = n;
  }
  return out;
}

/// Същото, но от заредените текстове (ползва се в четеца за заглавието).
String prayersTitleFor(SaintTexts t) {
  final counts = <String, int>{};
  for (final h in t.hymns) {
    counts[h.kind] = (counts[h.kind] ?? 0) + 1;
  }
  return prayersLabel(counts);
}

/// "Житие" пасва само при светия с жизнеописание. При най-големите
/// господски/богородични празници (rank 1), икони, предпразненства,
/// попразненства, събори и възпоменания думата не пасва граматически —
/// там е по-подходящо "Сказание".
/// ⚠ СКОБИТЕ СЕ МАХАТ, преди да се търсят ключовите думи.
///
/// В скоби стоят ДОБАВЕНИ БЕЛЕЖКИ — година († 435), второ име (Ѝя), а от
/// 23.08.2026 и „(Паметта му се пренася от 29.II)" за тримата светии на 29
/// февруари (виж `extract_rules.LEAP_FIXED`). Последната съдържа „памет" и
/// тримата излизаха „Сказание", вместо „Житие", каквото им се полага.
///
/// ⚠ Признакът е СТРУКТУРЕН, а не граматически. Изкушението е да се изключи
/// само определената форма („паметта"), но тя е особеност на ЕДНА
/// формулировка: преработи ли се бележката, бъгът се връща. Скобата, обратно,
/// винаги значи „това не е част от обозначението".
///
/// Мерено срещу всичките 1633 имена в семето: махането на скобите мени
/// етикета за ТОЧНО тези три записа и за нито един друг.
final RegExp _parenNote = RegExp(r'\s*\([^)]*\)');

String lifeLabelFor({required int rank, required String name}) {
  final n = name.replaceAll(_parenNote, '').toLowerCase();
  if (rank == 1) return 'Сказание';
  //if (n.contains('икона')) return 'Сказание';
  const keywords = ['икона', 
                    'празненство', 'предпразн', 'попразн', 'отдание', 
                    'събор', 'памет', 'възпомен',
                    'открива', 'намира'];
  if (keywords.any(n.contains)) return 'Сказание';
  return 'Житие';
}

class SaintExpandableTile extends StatefulWidget {
  /// Редът, както се рендва сега (SVG знак + име) — не се променя визуално.
  final Widget collapsedRow;

  /// Евтините флагове от дневната заявка.
  final bool hasLife;
  final bool hasSluzhba;

  /// Колко песнопения от кой вид има светията — за етикета на секцията.
  /// Празна карта = няма нито едно.
  final Map<String, int> hymnCounts;

  /// "Житие" или "Сказание" — виж lifeLabelFor().
  final String lifeLabel;

  /// Четивата по Димитрий Ростовски за този светия — 0 или повече (виж
  /// DmitryRef). Идват готови от заявката, не се зареждат лениво —
  /// самите заглавия (за sub/slovo редовете) се разрешават през
  /// LivesIndex чак при рисуване на разгънатата секция.
  final List<DmitryRef> dmitryRefs;

  /// Зарежда пълните текстове от базата — вика се чак при тап.
  final Future<SaintTexts?> Function() loadTexts;

  /// Търсене по слъг за вътрешните линкове (подава се на четеца).
  final SaintLookup lookup;

  /// Колко хоризонтално място да заема стрелката. null = естествената ѝ
  /// широчина (дневният изглед). По-малка стойност я издърпва вдясно и
  /// оставя повече място на текста — ползва се в екрана с празниците,
  /// където по-широкият ред иначе би се пренасял на трети ред.
  final double? arrowSlotWidth;

  const SaintExpandableTile({
    super.key,
    required this.collapsedRow,
    required this.hasLife,
    required this.hasSluzhba,
    this.hymnCounts = const {},
    this.lifeLabel = 'Житие',
    this.dmitryRefs = const [],
    required this.loadTexts,
    required this.lookup,
    this.arrowSlotWidth,
  });

  @override
  State<SaintExpandableTile> createState() => _SaintExpandableTileState();
}

class _SaintExpandableTileState extends State<SaintExpandableTile> {
  bool _expanded = false;

  String get _prayersLabel => prayersLabel(widget.hymnCounts);

  bool get _hasAnything =>
      _prayersLabel.isNotEmpty ||
      widget.hasLife ||
      widget.hasSluzhba ||
      widget.dmitryRefs.isNotEmpty;

  void _toggle() {
    if (!_hasAnything) return;
    setState(() => _expanded = !_expanded);
  }

  Future<void> _open(_Section section) async {
    final texts = await widget.loadTexts();
    if (!mounted || texts == null) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) {
        if (section == _Section.prayers) {
          return ReaderScreen.prayers(texts: texts, lookup: widget.lookup);
        } else if (section == _Section.sluzhba) {
          return ReaderScreen.sluzhba(texts: texts, lookup: widget.lookup);
        }
        return ReaderScreen.life(
            texts: texts, lookup: widget.lookup, lifeTitle: widget.lifeLabel);
      },
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: _toggle,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: widget.collapsedRow),
              if (_hasAnything)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  // ВАЖНО: и двете измерения са ИЗРИЧНИ. OverflowBox се
                  // оразмерява по МАКСИМУМА на входящите ограничения, а тук
                  // височината идва неограничена (редът живее в скролируем
                  // Column) — без явната height той приема безкрайна
                  // височина и чупи цялото подреждане на екрана.
                  child: SizedBox(
                    width: widget.arrowSlotWidth ?? 20,
                    height: 20,
                    // Иконата се рисува в ПЪЛЕН размер, но заема само
                    // arrowSlotWidth хоризонтално място — излишъкът излиза
                    // надясно, в отстъпа на екрана.
                    child: OverflowBox(
                      maxWidth: 20,
                      maxHeight: 20,
                      // centerLeft (не centerRight!): иконата тръгва от
                      // ЛЕВИЯ ръб на слота и стърчи НАДЯСНО, в отстъпа на
                      // екрана. С centerRight тя стърчеше наляво и лягаше
                      // върху текста.
                      alignment: Alignment.centerLeft,
                      child: AnimatedRotation(
                        turns: _expanded ? 0.25 : 0.0, // ▸ → ▾
                        duration: const Duration(milliseconds: 180),
                        child: Icon(
                          Icons.arrow_right,
                          size: 20,
                          color: Theme.of(context).hintColor,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeInOut,
          alignment: Alignment.topCenter,
          child: !_expanded
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(left: 32, bottom: 4),
                  child: Column(
                    children: [
                      if (_prayersLabel.isNotEmpty)
                        _SectionRow(
                          icon: Icons.music_note_outlined,
                          label: _prayersLabel,
                          onTap: () => _open(_Section.prayers),
                        ),
                      if (widget.hasLife)
                        _SectionRow(
                          icon: Icons.menu_book_outlined,
                          label: widget.lifeLabel,
                          onTap: () => _open(_Section.life),
                        ),
                      if (widget.hasSluzhba)
                        _SectionRow(
                          icon: Icons.local_library_outlined,
                          label: 'Служба',
                          onTap: () => _open(_Section.sluzhba),
                        ),
                      for (final entry in widget.dmitryRefs.asMap().entries)
                        _DmitryRow(
                          ref: entry.value,
                          mainLabel: widget.lifeLabel,
                          isFirst: entry.key == 0,
                        ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}

class _SectionRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _SectionRow({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(
          children: [
            Icon(icon, size: 18, color: AppColors.sectionTitle), 
            const SizedBox(width: 10),
            Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
            Icon(Icons.chevron_right, size: 20, color: theme.hintColor),
          ],
        ),
      ),
    );
  }
}

/// Един ред за четиво по Димитрий Ростовски. Заглавието следва
/// ПОЗИЦИЯТА след сортирането по книжен ред (num), НЕ полето `kind` —
/// първият ред (`isFirst`) носи генеричния етикет Житие/Сказание (viж
/// lifeLabelFor — подаден отвън като mainLabel, за да не се смята
/// повторно) + "по Димитрий Ростовски"; ВСЕКИ СЛЕДВАЩ показва СВОЕТО
/// СОБСТВЕНО заглавие от книгата. Причината `kind=='main'` не върши тази
/// работа: книгата понякога подрежда встъпителна част (sub) ПРЕДИ
/// сказанието (напр. Рождество Христово) — тогава "main" не е първият
/// ред по книжен ред, а решено е първото МЯСТО в списъка да носи
/// генеричния етикет, не конкретният вид.
class _DmitryRow extends StatelessWidget {
  final DmitryRef ref;
  final String mainLabel;
  final bool isFirst;

  const _DmitryRow(
      {required this.ref, required this.mainLabel, required this.isFirst});

  Future<String> _label() async {
    if (isFirst) return '$mainLabel по Димитрий Ростовски';
    final index = await LivesIndex.load();
    return index[ref.num.toString()]?.title ?? 'Слово по Димитрий Ростовски';
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _label(),
      builder: (context, snap) {
        final fallback =
            isFirst ? '$mainLabel по Димитрий Ростовски' : 'Слово по Димитрий Ростовски';
        return _SectionRow(
          icon: Icons.import_contacts_outlined,
          label: snap.data ?? fallback,
          onTap: () => openDmitryLife(context, ref.num),
        );
      },
    );
  }
}
