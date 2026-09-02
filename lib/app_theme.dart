import 'package:flutter/material.dart';

class AppColors {
  // AppBar
  static const appBarWeekday   = Color(0xFF2C3B4D);  // индиго
  static const appBarSunday    = Color(0xFF7b002c);  // винено червено
  static const appBarSundayBg  = Color(0x887b002c);  // бордо 25% opacity

  // Фонове
  static const toolbar           = Color(0xFF1A1A1A);
  // Фон на месечния/дневния изглед (делнични дни) — същият цвят като
  // toolbar/drawerBackground и splash екрана (android/.../colors.xml),
  // не отделен хардкоднат цвят, за да останат винаги в синхрон.
  static const background        = toolbar;
  // Предишният фон на дневния изглед (преди background да стане = toolbar) —
  // запазен нарочно само за неделите в дневния изглед (виж DayScreen.build).
  static const sundayBackground  = Color(0xFF1E1510);
  // Леко по-светла от background/toolbar (elevation overlay стил, а не
  // отделен хардкоднат нюанс) — за карти/табелки с пояснителен текст и
  // "изгасената" (невдигната) част на SegmentedButton в настройките.
  static final backgroundCard    = Color.lerp(toolbar, Colors.white, 0.08)!;
  // Заглавната лента на разгъващо се поле (виж reference_book_screen.dart) —
  // със същия похват, само придвижена по-нататък към бялото, за да се
  // отличава от редовете вътре, щом полето се разгъне.
  static final expansionHeader   = Color.lerp(toolbar, Colors.white, 0.18)!;

  static const sectionTitle      = Color(0xFF8A9BB0);
  static const sectionDivider    = Color(0xFF2A2A2A);

  static const drawerBackground  = Color(0xFF1A1A1A);
  static const drawerIcon        = Color(0xFF8A8A8A);
  static const drawerDivider     = Color(0xFF2A2A2A);

  // Текст
  static const textPrimary        = Color(0xA0FFFFFF);
  static const textSecondary      = Color(0x80FFFFFF); // 0xB3A0A0A0 white70
  static const textMuted          = Color(0x60FFFFFF); // 0x80AAAAAA white54
  static const fastText           = Color(0x60FFFFFF);
  static const sectionTitleSunday = Color(0xFFB993A0); //Color.fromARGB(255, 179, 127, 145);
  static const monthTitleSunday   = Color(0xFFB993A0); //0xFFb37f91 Color.fromARGB(255, 179, 127, 145);
  static const monthTextSecondary = Color(0x80FFFFFF);
  static const moonColor          = Color(0x80FFFFFF);

  // Знаци на светии
  // signRedHex е семантичен маркер от базата данни ('red' или '#CC0000').
  // Конкретните цветове се определят от темата — не от базата данни.
  // При смяна на тема само signRed/signWhite се променят тук.
  static const signRedHex  = 'red'; // стойността в базата данни
  static const signRed     = Color(0xFFBB8C9C); //Color(0xFFeb98b6); // цвят за dark mode
  static const signWhite   = Color(0xFFAAAAAA); // цвят за тъмен фон

  // ─── Намереното при търсене ───────────────────────────────────────────
  // ЕДИН цвят за цялото приложение: списъка с резултати в екрана за
  // търсене и двата четеца. Четците имат светла и тъмна тема, тъй че
  // двойката стои тук цяла — ReaderPalette.hit/hitCurrent избира по своя
  // `dark` флаг. Останалите екрани са само тъмни и ползват *Dark.
  //
  // ⚠ Смяна на жълтото се прави ТУК, не в reader_theme.dart — инак
  // намереното свети различно в списъка и в отвореното житие.
  static const hitDark         = Color(0xFF6B5B1E);
  static const hitLight        = Color(0xFFFFF176);
  // Текущото съвпадение (онова, върху което стоят стрелките в четеца).
  static const hitCurrentDark  = Color(0xFFCC8A2E);
  static const hitCurrentLight = Color(0xFFFFA726);
  // Текстът ВЪРХУ маркираното. Обичайният textPrimary е полупрозрачно
  // бяло (0xA0FFFFFF) и върху жълтеникавия фон изсветлява до неразчетимо
  // — тук трябва плътен цвят.
  static const hitOnDark       = Color(0xFFF5EAC8);

  // ─── Highlight на днешния ден ─────────────────────────────────────────
  // Обикновен ден — днес
  static const todayBg       = Color(0x33BBBBBA); //Color.fromARGB(51, 187, 187, 186);
  static const todayFlash    = Color(0x859E9984); //Color.fromARGB(133, 158, 153, 132);

  // ─── Избран ред (списък с отметки, режим "избиране") ──────────────────
  // Индигото на лентата от дневния изглед, но изсветлено — на тъмния фон
  // самото appBarWeekday се сливаше и избраните редове се откриваха трудно.
  static const rowSelected = Color(0xFF44597A);

  // Неделя — днес
  static const sundayTodayBg = Color(0xff7b002c);
  static const sundayFlash   = Color(0xB8944B65); // Color.fromARGB(184, 148, 75, 101);

  // ─── Постна ивица (месечен изглед) ────────────────────────────────────
  // Ивицата се оцветява чрез придвижване на фона на реда към fastStripeTint.
  // Така се адаптира към всяка тема и неделите остават различими.
  static const fastStripeTint   = Color(0xFF808080); // сивото, към което се придвижва
  static const fastStripeAmount = 0.48;               // сила на придвижването (0.0–1.0)
  static const fastStripeAmountToday = 0.57;    // по-слабо посивяване за днешния ден

  // ─── Хедъри на справочните секции ─────────────────────────────────────
  // Четирите секции от главното меню (виж reference_pager.dart) се
  // различават по цвета на хедъра си — както делничният и неделният ден
  // в дневния изглед. Оцветява се САМО блокът със заглавието и годината;
  // горната лента остава toolbar навсякъде, пак както в дневния изглед.
  static const sectionHolidays = appBarSundayBg;        // както неделите в месечния
  static const sectionMemorial = appBarWeekday;         // както делничен ден
  static const sectionFasts    = Color(0xFF565F34);     // тъмно маслено зелено
  static const sectionBook     = Color(0xFF945503);     // тъмно оранжево

  // ─── Датепикър ────────────────────────────────────────────────────────
  // Цветовете на стандартния Material датепикър, обвързани с темата
  // на приложението. При смяна на скин — само тук се променят.
  static const datePickerPrimary    = appBarWeekday;   // избрана дата / акцент
  static const datePickerOnPrimary  = textPrimary;     // текст върху избрана дата
  static final datePickerSurface    = backgroundCard;  // фон на календара
  static const datePickerOnSurface  = textPrimary;     // текст на датите
  static const datePickerBackground = background;      // фон на диалога
  static final datePickerButtons    = Color.lerp(      // цвят на ОК/ОТКАЗ бутоните
                sectionTitle, Colors.grey, 0)!;     // Изсветляване на sectionTitle с 20%
}

// ─── Размери на шрифтове ──────────────────────────────────────────────────
class AppFonts {
  // Месечен изглед — хедър
  static const monthHeaderLabel  = 13.0;
  static const monthHeaderMonth  = 18.0;

  // Месечен изглед — списък
  static const monthDayNumber    = 16.0;
  static const monthWeekDay      = 16.0;
  static const monthSundayName   = 16.0;
  static const monthSaintName    = 15.0;
  static const monthRefDate      = 16.0;
  static const monthRefMonth     = 14.0;
}

class AppSizes {
  static const toolbarHeight = 40.0;      // височина на toolbar
  static const monthHeaderHeight = 50.0;  // височина на month header
}

class AppIcons {
  static const tipikonCircleCross   = 'assets/icons/tipikon_01_CircleCross.svg';
  static const tipikonSemiCircle    = 'assets/icons/tipikon_02_SemiCircleCross.svg';
  static const tipikonCross         = 'assets/icons/tipikon_03_Cross.svg';
  static const tipikonThreeDots     = 'assets/icons/tipikon_04_ThreeDots.svg';

  /// „Запази цитат" — сърце с плюс, за контекстното меню при маркиране.
  ///
  /// ⚠ Собствена, защото `heart_plus` няма в Material. Рисувана е черна и
  /// се оцветява при изписване (`ColorFilter`), тъй че следва темата на
  /// четеца — както знаците на Типикона по-горе следват `signRed`.
  static const addToFavorites       = 'assets/icons/icon_AddToFavorites.svg';
  
  static (String?, Color?) forRank(int rank) {
    switch (rank) {
      case 1: return (tipikonCircleCross, AppColors.signRed);   // Велик господски
      case 2: return (tipikonSemiCircle,  AppColors.signRed);   // Бдение
      case 3: return (tipikonCross,       AppColors.signRed);   // Полиелей
      case 4: return (tipikonThreeDots,   AppColors.signRed);   // Славословна
      case 5: return (tipikonThreeDots,   AppColors.signWhite); // Шестерична
      default: return (null, null);                             // Обикновена
    }
  }
}
