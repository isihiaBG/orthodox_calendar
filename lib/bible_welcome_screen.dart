// bible_welcome_screen.dart
//
// Въвеждащият екран на секцията „Библия" — три корици, от които се избира в
// кой дял да се влезе.
//
// Устроен е по ПЪЛНА аналогия с избора на том в „Месецослов"
// (library_screen.dart) и с избора на календар при пускане
// (welcome_screen.dart): и трите стъпват на един и същ [CoverPickerScaffold].
// Това не е спестено усилие, а нарочно — трите места правят едно и също нещо
// (избери едно от няколко, всяко с корица) и трябва да се държат еднакво под
// пръста.
//
// Работата му е двойна и втората не е по-малка от първата:
//
//   1. Избира с кой таб да се отвори съдържанието — Нов завет, Стар завет
//      или Псалтир.
//   2. Дава малко естетическа наслада в раздел, който иначе е само списъци и
//      текст. Приложението има какво да покаже точно тук.
//
// ⚠ Кориците са в assets/bible_covers/ — рисувани на ръка, НЕ производни.
// Папката е извън git (виж .gitignore); изтрие ли се, няма скрипт, който да
// я върне.

import 'package:flutter/material.dart';

import 'app_drawer.dart';
import 'app_theme.dart';
import 'bible_settings.dart';
import 'cover_flow.dart';
import 'cover_picker.dart';

/// Един дял от Писанието — корица, име и с кой таб да се отвори съдържанието.
class _Part {
  final String cover;
  final String name;

  /// Ред в [BibleContents] — 0 Нов завет, 1 Стар завет, 2 Псалтир.
  final int tab;

  /// Едноредово сведение под името. Числата са от `bible.db` и са преброени
  /// веднъж (`books`), а не се вадят живо: заради три реда текст не си струва
  /// да се отваря база на екран, който трябва да се появи мигновено.
  final String detail;

  const _Part({
    required this.cover,
    required this.name,
    required this.tab,
    required this.detail,
  });
}

/// ⚠ Редът в тестето е КАНОНИЧНИЯТ (Стар → Нов → Псалтир), не редът на
/// табовете (Нов → Стар → Псалтир). Двата не бива да се уеднаквяват:
///
///   • тестето се чете като книги на лавица и там Старият завет стои пръв —
///     така са номерувани и самите файлове с кориците;
///   • табовете са подредени по ЧЕСТОТА на четене, а не по канон, и това е
///     тяхната собствена, отдавна взета преценка.
///
/// Съответствието се пази в `tab`, тъй че никой от двата реда не се налага
/// над другия.
///
/// ⚠ Страничната печалба от този ред е, че Новият завет пада в СРЕДАТА —
/// тоест тестето се отваря право върху най-четения дял, без да се налага
/// начален индекс, който да спори с подредбата.
const List<_Part> _parts = [
  _Part(
    cover: 'assets/bible_covers/01_OldTestament.jpg',
    name: 'Стар завет',
    tab: 1,
    detail: '50 книги · 1101 глави',
  ),
  _Part(
    cover: 'assets/bible_covers/02_NewTestament.jpg',
    name: 'Нов завет',
    tab: 0,
    detail: '27 книги · 260 глави',
  ),
  _Part(
    cover: 'assets/bible_covers/03_Psaltir.jpg',
    name: 'Псалтир',
    tab: 2,
    detail: '151 псалма · 20 катизми',
  ),
];

/// Индексът, на който се отваря тестето, когато още нищо не е избирано —
/// Новият завет. Оттам нататък печели запомненото ([BibleLastPart]).

class BibleWelcomeScreen extends StatefulWidget {
  const BibleWelcomeScreen({super.key});

  @override
  State<BibleWelcomeScreen> createState() => _BibleWelcomeScreenState();
}

class _BibleWelcomeScreenState extends State<BibleWelcomeScreen> {
  final GlobalKey<CoverFlowState> _flow = GlobalKey<CoverFlowState>();

  late int _index = BibleLastPart.value;
  bool _dontShowAgain = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Трите се подготвят предварително — инак първото разлистване прескача
    // тъкмо докато човек гледа.
    for (final p in _parts) {
      precacheImage(AssetImage(p.cover), context);
    }
  }

  /// Връща избрания таб на повикващия, който отваря съдържанието.
  ///
  /// ⚠ Желанието „не показвай повече" се записва ТУК, заедно с избора, а не
  /// при всяко тапване на чекбокса. Инак се получава състояние „екранът е
  /// изключен, но човек не е избрал нищо" — той може да размисли и да се
  /// върне назад, а тогава изключването не бива да е влязло в сила.
  void _choose(int i) {
    if (_dontShowAgain) BibleWelcome.set(false);
    // ⚠ Запомня се ТУК и никъде другаде — виж [BibleLastPart].
    BibleLastPart.set(i);
    Navigator.of(context).pop(_parts[i].tab);
  }

  @override
  Widget build(BuildContext context) {
    return CoverPickerScaffold(
      title: 'Библия',
      covers: [for (final p in _parts) AssetImage(p.cover)],
      index: _index,
      onIndexChanged: (i) => setState(() => _index = i),
      onOpen: _choose,
      flowKey: _flow,
      // Хамбургер вместо стрелка „назад" — както във всяка друга секция.
      drawer: const AppDrawer(),
      // ⚠ Кориците на Писанието са 523×741 — по-широки от томовете, чието
      // съотношение контролът приема по подразбиране. Без това число трите
      // книги излизат издължени.
      aspect: 523 / 741,
      infoBuilder: (_, i) => _info(i),
      landscapeLabel: (i) => _parts[i].name,
      extra: _checkbox(),
    );
  }

  /// Долният панел — какво е избрано и копче да се влезе.
  ///
  /// ⚠ Стълбицата на кегела е същата като при избора на том: тиха надредна
  /// дума (13), едро име (30) и дребно сведение (14). Името е най-едрото,
  /// защото то е, което човек търси с поглед; надредната дума и числата под
  /// него само потвърждават избора и не бива да спорят с него.
  Widget _info(int i) {
    final p = _parts[i];
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Свещено Писание',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            p.name,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 30,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            p.detail,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: () => _choose(i),
            icon: const Icon(Icons.menu_book, size: 18),
            label: const Text('Отвори'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.sectionTitle,
              foregroundColor: Colors.white,
              padding:
                  const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  /// „Не показвай повече" — дословно същият, какъвто е при избора на календар.
  /// Виж `_checkbox` в welcome_screen.dart: двата екрана трябва да се
  /// изключват по един и същи начин, инак човек търси ключа два пъти.
  Widget _checkbox() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        onTap: () => setState(() => _dontShowAgain = !_dontShowAgain),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 22,
                height: 22,
                child: Checkbox(
                  value: _dontShowAgain,
                  onChanged: (v) =>
                      setState(() => _dontShowAgain = v ?? false),
                  side: const BorderSide(
                      color: AppColors.textSecondary, width: 1.4),
                  checkColor: Colors.white,
                  activeColor: AppColors.sectionTitle,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                'Не показвай повече',
                style:
                    TextStyle(color: AppColors.textSecondary, fontSize: 14),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
