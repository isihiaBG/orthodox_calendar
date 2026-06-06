import 'package:flutter/material.dart';

class AppColors {
  // AppBar
  static const appBarWeekday   = Color(0xFF2C3B4D);  // индиго
  static const appBarSunday    = Color(0xFF7b002c);  // винено червено
  static const appBarSundayBg  = Color(0x447b002c);  // бордо 25% opacity

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
  static const textPrimary        = Color(0xFFFFFFFF);
  static const textSecondary      = Color(0xB3FFFFFF);  // white70
  static const textMuted          = Color(0x80FFFFFF);  // white54
  static const fastText           = Color(0xB3FFFFFF);
  static const sectionTitleSunday = Color.fromARGB(255, 179, 127, 145);
  static const monthTitleSunday   = Color.fromARGB(255, 179, 127, 145);

  // Знаци на светии
  static const signRedHex  = '#CC0000';
  static const signRed     = Color.fromARGB(255, 235, 152, 182);
  static const signWhite   = Color(0xFFFFFFFF);

  // ─── Highlight на днешния ден ─────────────────────────────────────────
  // Обикновен ден — днес
  static const todayBg       = Color.fromARGB(51, 187, 187, 186);  // топло жълто ~20%
  static const todayFlash    = Color.fromARGB(135, 253, 228, 169);  // по-наситено за flash

  // Неделя — днес
  static const sundayTodayBg = Color(0x887b002c);  // по-наситено бордо
  static const sundayFlash   = Color(0xBB7b002c);  // наситено бордо за flash
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
