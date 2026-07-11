import 'package:flutter/material.dart';

class AppColors {
  // AppBar
  static const appBarWeekday   = Color(0xFF2C3B4D);  // индиго
  static const appBarSunday    = Color(0xFF7b002c);  // винено червено
  static const appBarSundayBg  = Color(0x887b002c);  // бордо 25% opacity

  // Фонове
  static const background        = Color(0xFF1E1510);
  static const backgroundCard    = Color(0xFF2A1F14);
  static const toolbar           = Color(0xFF1A1A1A);

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

  // ─── Highlight на днешния ден ─────────────────────────────────────────
  // Обикновен ден — днес
  static const todayBg       = Color(0x33BBBBBA); //Color.fromARGB(51, 187, 187, 186);
  static const todayFlash    = Color(0x859E9984); //Color.fromARGB(133, 158, 153, 132);

  // Неделя — днес
  static const sundayTodayBg = Color(0xff7b002c);
  static const sundayFlash   = Color(0xB8944B65); // Color.fromARGB(184, 148, 75, 101);

  // ─── Постна ивица (месечен изглед) ────────────────────────────────────
  // Ивицата се оцветява чрез придвижване на фона на реда към fastStripeTint.
  // Така се адаптира към всяка тема и неделите остават различими.
  static const fastStripeTint   = Color(0xFF808080); // сивото, към което се придвижва
  static const fastStripeAmount = 0.48;               // сила на придвижването (0.0–1.0)
  static const fastStripeAmountToday = 0.57;    // по-слабо посивяване за днешния ден

  // ─── Датепикър ────────────────────────────────────────────────────────
  // Цветовете на стандартния Material датепикър, обвързани с темата
  // на приложението. При смяна на скин — само тук се променят.
  static const datePickerPrimary    = appBarWeekday;   // избрана дата / акцент
  static const datePickerOnPrimary  = textPrimary;     // текст върху избрана дата
  static const datePickerSurface    = backgroundCard;  // фон на календара
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
