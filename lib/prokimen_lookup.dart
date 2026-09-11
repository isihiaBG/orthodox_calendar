/// Кой прокимен се пада на дадено четиво.
///
/// ⚠⚠ ПРОКИМЕНЪТ ПРИНАДЛЕЖИ НА ПАМЕТТА, не на четивото — за разлика от
/// обръщението „Братя,", което е свойство на ЗАЧАЛОТО. Мерено: 110 зачала
/// носят прокимен, а 40 от тях имат РАЗЛИЧНИ прокимени според паметта
/// (Евр. зач. 318 носи осем). Затова тук има верига на приоритета, а не
/// карта по зачало.
///
/// ⚠ ЧИСТ DART нарочно — никакъв Flutter, за да се проверява с `dart run`
/// за части от секундата, както [bible_ref.dart].
library;

import 'prokimen.dart';

/// Прозорецът около Пасха, в който подвижните прокимени изместват
/// делничните: от началото на Триода до Неделя на Вси Светии.
///
/// ⚠⚠ БЕЗ НЕГО СЪВПАДЕНИЕТО ПО ЗАЧАЛО ЛЪЖЕ. Мерено върху 2026 г.: извън
/// прозореца **123 от 231** съвпадения са фалшиви — зачало от Пентикостара
/// случайно съвпада с редово четиво посред зимата.
const int kPaschaWindowBefore = -70;
const int kPaschaWindowAfter = 56;

/// Кой прокимен се чете, и защо — за да личи по кой път е намерен.
enum ProkimenSource { feast, movable, tone, weekday }

class ProkimenHit {
  final K prokimen;
  final ProkimenSource source;
  const ProkimenHit(this.prokimen, this.source);
}

/// Веригата на приоритета.
///
///   1. НЕПОДВИЖНА ПАМЕТ — църковната дата има запис в месецослова И
///      зачалото съвпада. Съвпадението на зачалото е потвърждението, че
///      четивото Е на тази памет, а не редовото за деня: мерено, при 204
///      от 323 дни с памет четивото все пак е редовото.
///   2. ПОДВИЖЕН ДЯЛ — само ВЪТРЕ в прозореца около Пасха и само когато
///      зачалото сочи ЕДИН дял (виж [kPaschaWindowBefore]).
///   3. НЕДЕЛЯ — възкресен прокимен по глас.
///   4. ДЕЛНИК — прокименът на деня от седмицата.
///
/// ⚠ Връща `null`, а не „нещо приблизително": по-добре без прокимен,
/// отколкото чужд. Същото правило като при повредените четива.
ProkimenHit? prokimenFor({
  required String churchMonthDay,
  required int weekday,
  required int? tone,
  required int? zachalo,
  required int? daysFromPascha,
}) {
  if (zachalo != null) {
    final feast = kProkimenFixed[churchMonthDay];
    if (feast != null && feast.isNotEmpty) {
      // ⚠ Зачалото се сверява срещу онова, което книгата дава за ТАЗИ
      // памет — записано е при извличането (виж 11_gen_prokimen_dart.py).
      for (final k in feast) {
        if (k.zachala.contains(zachalo)) {
          return ProkimenHit(k, ProkimenSource.feast);
        }
      }
    }
    if (daysFromPascha != null &&
        daysFromPascha >= kPaschaWindowBefore &&
        daysFromPascha <= kPaschaWindowAfter) {
      final movable = kProkimenPascha['$zachalo'];
      // ⚠ Само при ЕДИН кандидат. Сочи ли зачалото няколко подвижни дяла,
      // не се гадае — пада се към гласа или делника, които са безопасни.
      if (movable != null && movable.length == 1) {
        return ProkimenHit(movable.first, ProkimenSource.movable);
      }
    }
  }
  if (weekday == DateTime.sunday && tone != null) {
    final byTone = kProkimenTone['$tone'];
    if (byTone != null && byTone.isNotEmpty) {
      return ProkimenHit(byTone.first, ProkimenSource.tone);
    }
  }
  final daily = kProkimenWeekday['$weekday'];
  if (daily != null && daily.isNotEmpty) {
    return ProkimenHit(daily.first, ProkimenSource.weekday);
  }
  return null;
}
