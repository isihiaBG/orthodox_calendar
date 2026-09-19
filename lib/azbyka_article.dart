// azbyka_article.dart
//
// Статиите от azbyka.ru — понятия и пояснения, свързани с празниците.
//
// ⚠ Живеят в таблица `articles` на `lives.db` — до житията, но ОТДЕЛНО от
// тях: те не са жития и нямат светия, дата или песнопения. Слъгът им носи
// представка, за да не може да се сблъска с чужд.
//
// ⚠⚠ РАЗПОЗНАВА СЕ НА ДВЕ МЕСТА: `lookupBySlug` (отваряне, отметки) И
// `_slugForFingerprint` в quote_locator.dart (споделен цитат). Липсва ли
// второто, цитат от статия се запазва и споделя, но при отсрещния телефон
// умира с „Това четиво го няма в календара" — капанът е платен вече два
// пъти: веднъж при справочните статии, веднъж при словата.
library;

import 'package:sqflite/sqflite.dart';

import 'database_helper.dart';
import 'saint_expandable_tile.dart';

const String kArticleSlugPrefix = 'azb-';

bool isArticleSlug(String slug) => slug.startsWith(kArticleSlugPrefix);

/// Статията по слъг („azb-grex"), готова за четеца.
Future<SaintTexts?> loadArticle(String slug) async {
  if (!isArticleSlug(slug)) return null;
  final db = await DatabaseHelper.database;
  try {
    final r = await db.rawQuery(
      'SELECT title_bg, body, source FROM lives.articles WHERE slug = ? LIMIT 1',
      [slug.substring(kArticleSlugPrefix.length)],
    );
    if (r.isEmpty) return null;
    return SaintTexts(
      name: r.first['title_bg'] as String,
      lifeHtml: r.first['body'] as String,
      slug: slug,
      // ⚠ Адресът на оригинала — четецът го изписва накрая. Сайтът изисква
      // коректно цитиране на всяка взета статия.
      source: (r.first['source'] as String?) ?? '',
    );
  } on DatabaseException {
    // Стар билд без тази таблица — по-добре нищо, отколкото срив.
    return null;
  }
}

/// Слъговете на всички статии — за разгъването на отпечатък при
/// споделен цитат.
Future<List<String>> articleSlugs() async {
  final db = await DatabaseHelper.database;
  try {
    final rows = await db.rawQuery('SELECT slug FROM lives.articles');
    return [for (final r in rows) '$kArticleSlugPrefix${r['slug']}'];
  } on DatabaseException {
    return const [];
  }
}
