class AppSettings {
  // true = стар стил (Юлиански), false = нов стил (Григориански)
  static bool isOldStyle = true;
  // true = стар стил е водещ (вляво), false = нов стил е водещ
  static bool oldStyleFirst = true;
  // Текуща страница
  static int currentPage = 0;
  // Днешната дата (по нов стил) — постоянно маркирана
  static DateTime? today;
  // Временен flash при навигация до дата
  static DateTime? flashDate;
}
