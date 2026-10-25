// share_app.dart
//
// „Сподели приложението" (главното меню и „За приложението") — системното
// споделяне с кратък текст и връзка към страницата за сваляне
// (docs/index.html, 25.10.2026).

import 'package:share_plus/share_plus.dart';

const String kAppPageUrl = 'https://isihiabg.github.io/orthodox_calendar/';

Future<void> shareApp() => Share.share(
      'Православен календар — жития на светиите, четива за деня, пости, '
      'Библия, молитвослов и книги, на български и без интернет.\n'
      '$kAppPageUrl',
      subject: 'Православен календар',
    );
