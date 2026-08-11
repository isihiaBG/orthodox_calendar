// reference_book_screen.dart
//
// "Справочник" — разгъващи се полета, а във всяко тях списък от четива
// (указания, пояснения, речник). Едно от четирите тела на
// reference_pager.dart: няма собствен Scaffold и лента, а за разлика от
// другите три НЯМА и година — хедърът му е само заглавието.
//
// Съдържанието идва от отделна база, assets/db/reference.db, произвеждана
// от tools/reference_gen/build.py. Текстовете в нея засега са ПРИМЕРНИ —
// структурата е готова, за да може съдържанието да влезе после, без нищо
// тук да се пипа.
//
// Четивата се отварят с общия четец в режим "служба" — той рендира HTML
// без орнаментираната буквица, което е и желаното: указанията не са жития.

import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'database_helper.dart';
import 'reader_screen.dart';
import 'section_header.dart';
import 'reference_text.dart';
import 'saint_expandable_tile.dart' show SaintTexts, lookupBySlug;

const String _bodyFamily = 'CharisSIL';

class _RefArticle {
  final int id;
  final String title;
  final String body;
  const _RefArticle({required this.id, required this.title, required this.body});
}

class _RefGroup {
  final int id;
  final String title;
  final List<_RefArticle> articles;
  const _RefGroup({required this.id, required this.title, required this.articles});
}

class ReferenceBookSection extends StatefulWidget {
  final double baseFont;

  const ReferenceBookSection({super.key, required this.baseFont});

  @override
  State<ReferenceBookSection> createState() => _ReferenceBookSectionState();
}

class _ReferenceBookSectionState extends State<ReferenceBookSection> {
  double _fs(double delta) => widget.baseFont + delta;

  List<_RefGroup>? _groups;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final db = await DatabaseHelper.referenceDatabase;
      final groupRows =
          await db.query('ref_groups', orderBy: 'position ASC, id ASC');
      final articleRows =
          await db.query('ref_articles', orderBy: 'position ASC, id ASC');

      final byGroup = <int, List<_RefArticle>>{};
      for (final r in articleRows) {
        byGroup.putIfAbsent(r['group_id'] as int, () => []).add(_RefArticle(
              id: r['id'] as int,
              title: r['title'] as String,
              body: r['body'] as String,
            ));
      }

      final groups = [
        for (final g in groupRows)
          _RefGroup(
            id: g['id'] as int,
            title: g['title'] as String,
            articles: byGroup[g['id'] as int] ?? const [],
          )
      ];

      if (!mounted) return;
      setState(() {
        _groups = groups;
        _loading = false;
      });
    } catch (e) {
      debugPrint('[reference] грешка при зареждане: $e');
      if (!mounted) return;
      setState(() {
        _error = 'Справочникът не можа да се зареди.';
        _loading = false;
      });
    }
  }

  Future<void> _openArticle(_RefArticle article) async {
    // Запушалката се пресмята ПРИ ОТВАРЯНЕ, а не при сглобяването на
    // базата — иначе изречението щеше да остарее до дни.
    final body = await expandPlaceholders(article.body);
    if (!mounted) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ReaderScreen.sluzhba(
        texts: SaintTexts(
          name: article.title,
          sluzhba: body,
          // Слъгът е нужен на четеца за отметките — префиксът пази
          // справочните четива настрани от тези на светиите.
          slug: '$kReferenceSlugPrefix${article.id}',
        ),
        lookup: lookupBySlug,
        lifeTitle: article.title,
      ),
    ));
  }

  /// Ред към четиво. Без подчертаване — че се отива някъде, се вижда от
  /// стрелката отдясно (така е и другаде в приложението).
  Widget _articleRow(_RefArticle article) {
    return InkWell(
      onTap: () => _openArticle(article),
      child: Padding(
        // Отстъпът отляво е по-голям от този на заглавието на полето —
        // редовете вътре да личат като подчинени, а не като още заглавия.
        padding: const EdgeInsets.fromLTRB(30, 10, 8, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                article.title,
                style: TextStyle(
                  fontFamily: _bodyFamily,
                  fontSize: _fs(0),
                  color: AppColors.textPrimary,
                  height: 1.35,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right,
                size: _fs(6), color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }

  Widget _groupTile(_RefGroup group) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.backgroundCard,
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        // ExpansionTile тегли своите разделители от темата — тук ги гасим,
        // за да не рисува светли линии върху картата.
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          // ExpansionTile боядисва ЦЕЛИЯ си правоъгълник (заглавие +
          // разгънатото съдържание) с този цвят, затова светлият нюанс се
          // задава тук, а редовете вътре се връщат към по-тъмния фон на
          // картата със собствен Container по-долу. Иначе двете части се
          // сливаха в едно сиво петно.
          backgroundColor: AppColors.expansionHeader,
          collapsedBackgroundColor: AppColors.expansionHeader,
          tilePadding: const EdgeInsets.symmetric(horizontal: 14),
          childrenPadding: EdgeInsets.zero,
          iconColor: AppColors.textPrimary,
          collapsedIconColor: AppColors.textSecondary,
          title: Text(
            group.title,
            style: TextStyle(
              fontFamily: _bodyFamily,
              fontSize: _fs(2),
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
              height: 1.3,
            ),
          ),
          children: [
            Container(
              width: double.infinity,
              color: AppColors.backgroundCard,
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [for (final a in group.articles) _articleRow(a)],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            title: 'Справочник',
            background: AppColors.sectionBook,
            baseFont: widget.baseFont,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.only(top: 40),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 40),
                    child: Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontFamily: _bodyFamily,
                          fontSize: _fs(0),
                          color: AppColors.textMuted),
                    ),
                  )
                else
                  for (final g in _groups ?? const <_RefGroup>[]) _groupTile(g),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
