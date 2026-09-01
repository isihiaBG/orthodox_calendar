// ГЕНЕРИРАН ФАЙЛ — не го редактирай на ръка.
// Прави се от tools/bible_bg/input/books.csv (виж README-то там).
//
// Картата код-на-книга → път в pravoslavieto.com, откъдето е взет
// СЪВРЕМЕННИЯТ БЪЛГАРСКИ текст на Писанието (останалите преводи идват от
// azbyka.ru).
//
// ⚠ Пътищата НЕ СЕ СГЛОБЯВАТ ПО ПРАВИЛО и затова стоят изброени: `2Car` е
// с главна буква, а другите три Царства — с малка. Няма закономерност;
// просто така е качено. Сглобен по схема, точно този адрес би сочил
// наникъде.
//
// ⚠ Една книга = ЕДИН файл (всички глави наведнъж), за разлика от
// azbyka.ru, където една страница = една глава. Затова връзката е към
// книгата, а не към главата.
library;

const Map<String, String> kPravoslavietoBookPaths = {
  'Mt': 'nz/mat',
  'Mk': 'nz/mark',
  'Lk': 'nz/luk',
  'Jn': 'nz/ioan',
  'Act': 'nz/deyan',
  'Jac': 'nz/iak',
  '1Pet': 'nz/1petr',
  '2Pet': 'nz/2petr',
  '1Jn': 'nz/1ioan',
  '2Jn': 'nz/2ioan',
  '3Jn': 'nz/3ioan',
  'Juda': 'nz/iud',
  'Rom': 'nz/rim',
  '1Cor': 'nz/1kor',
  '2Cor': 'nz/2kor',
  'Gal': 'nz/gal',
  'Eph': 'nz/efes',
  'Phil': 'nz/filip',
  'Col': 'nz/kol',
  '1Thes': 'nz/1sol',
  '2Thes': 'nz/2sol',
  '1Tim': 'nz/1tim',
  '2Tim': 'nz/2tim',
  'Tit': 'nz/tit',
  'Phlm': 'nz/filim',
  'Hebr': 'nz/evr',
  'Apok': 'nz/otkr',
  'Gen': 'sz/gen',
  'Ex': 'sz/ex',
  'Lev': 'sz/lev',
  'Num': 'sz/num',
  'Deut': 'sz/deut',
  'Nav': 'sz/nav',
  'Judg': 'sz/judg',
  'Rth': 'sz/ruth',
  '1Sam': 'sz/1car',
  '2Sam': 'sz/2Car',
  '1King': 'sz/3car',
  '2King': 'sz/4car',
  '1Chron': 'sz/1par',
  '2Chron': 'sz/2par',
  'Ezr': 'sz/ezd',
  '2Ezr': 'sz/2ezd',
  'Nehem': 'sz/neh',
  'Tov': 'sz/tov',
  'Judf': 'sz/judith',
  'Est': 'sz/est',
  '1Mac': 'sz/1mak',
  '2Mac': 'sz/2mak',
  '3Mac': 'sz/3mak',
  'Job': 'sz/job',
  'Ps': 'sz/ps',
  'Prov': 'sz/prov',
  'Eccl': 'sz/eccles',
  'Song': 'sz/song',
  'Solom': 'sz/wis',
  'Sir': 'sz/sir',
  'Is': 'sz/isaiah',
  'Jer': 'sz/ier',
  'Lam': 'sz/lam',
  'pJer': 'sz/epJer',
  'Bar': 'sz/bar',
  'Ezek': 'sz/ezek',
  'Dan': 'sz/dan',
  'Hos': 'sz/hos',
  'Joel': 'sz/joel',
  'Am': 'sz/amos',
  'Avd': 'sz/obad',
  'Jona': 'sz/jon',
  'Mic': 'sz/mic',
  'Naum': 'sz/nahum',
  'Habak': 'sz/hab',
  'Sofon': 'sz/zeph',
  'Hag': 'sz/hag',
  'Zah': 'sz/zech',
  'Mal': 'sz/mal',
  '3Ezr': 'sz/3ezd',
};
