import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_bg.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[Locale('bg')];

  /// No description provided for @appTitle.
  ///
  /// In bg, this message translates to:
  /// **'Православен Календар'**
  String get appTitle;

  /// No description provided for @noData.
  ///
  /// In bg, this message translates to:
  /// **'Няма данни за този ден'**
  String get noData;

  /// No description provided for @fastPeriod_0.
  ///
  /// In bg, this message translates to:
  /// **'Блажи се'**
  String get fastPeriod_0;

  /// No description provided for @fastPeriod_1.
  ///
  /// In bg, this message translates to:
  /// **'Постен ден'**
  String get fastPeriod_1;

  /// No description provided for @fastPeriod_2.
  ///
  /// In bg, this message translates to:
  /// **'Велик пост'**
  String get fastPeriod_2;

  /// No description provided for @fastPeriod_3.
  ///
  /// In bg, this message translates to:
  /// **'Петров пост'**
  String get fastPeriod_3;

  /// No description provided for @fastPeriod_4.
  ///
  /// In bg, this message translates to:
  /// **'Богородичен пост'**
  String get fastPeriod_4;

  /// No description provided for @fastPeriod_5.
  ///
  /// In bg, this message translates to:
  /// **'Рождественски пост'**
  String get fastPeriod_5;

  /// No description provided for @fastType_0.
  ///
  /// In bg, this message translates to:
  /// **''**
  String get fastType_0;

  /// No description provided for @fastType_1.
  ///
  /// In bg, this message translates to:
  /// **'без месо'**
  String get fastType_1;

  /// No description provided for @fastType_2.
  ///
  /// In bg, this message translates to:
  /// **'риба'**
  String get fastType_2;

  /// No description provided for @fastType_3.
  ///
  /// In bg, this message translates to:
  /// **'хайвер'**
  String get fastType_3;

  /// No description provided for @fastType_4.
  ///
  /// In bg, this message translates to:
  /// **'олио'**
  String get fastType_4;

  /// No description provided for @fastType_5.
  ///
  /// In bg, this message translates to:
  /// **'храна с олио след вечерня'**
  String get fastType_5;

  /// No description provided for @fastType_6.
  ///
  /// In bg, this message translates to:
  /// **'без олио'**
  String get fastType_6;

  /// No description provided for @fastType_7.
  ///
  /// In bg, this message translates to:
  /// **'сухоядение'**
  String get fastType_7;

  /// No description provided for @fastType_8.
  ///
  /// In bg, this message translates to:
  /// **'хляб, смокини и вино'**
  String get fastType_8;

  /// No description provided for @fastType_9.
  ///
  /// In bg, this message translates to:
  /// **'пълно въздържание'**
  String get fastType_9;

  /// No description provided for @weekDay_1.
  ///
  /// In bg, this message translates to:
  /// **'Понеделник'**
  String get weekDay_1;

  /// No description provided for @weekDay_2.
  ///
  /// In bg, this message translates to:
  /// **'Вторник'**
  String get weekDay_2;

  /// No description provided for @weekDay_3.
  ///
  /// In bg, this message translates to:
  /// **'Сряда'**
  String get weekDay_3;

  /// No description provided for @weekDay_4.
  ///
  /// In bg, this message translates to:
  /// **'Четвъртък'**
  String get weekDay_4;

  /// No description provided for @weekDay_5.
  ///
  /// In bg, this message translates to:
  /// **'Петък'**
  String get weekDay_5;

  /// No description provided for @weekDay_6.
  ///
  /// In bg, this message translates to:
  /// **'Събота'**
  String get weekDay_6;

  /// No description provided for @weekDay_7.
  ///
  /// In bg, this message translates to:
  /// **'Неделя'**
  String get weekDay_7;

  /// No description provided for @month_1.
  ///
  /// In bg, this message translates to:
  /// **'януари'**
  String get month_1;

  /// No description provided for @month_2.
  ///
  /// In bg, this message translates to:
  /// **'февруари'**
  String get month_2;

  /// No description provided for @month_3.
  ///
  /// In bg, this message translates to:
  /// **'март'**
  String get month_3;

  /// No description provided for @month_4.
  ///
  /// In bg, this message translates to:
  /// **'април'**
  String get month_4;

  /// No description provided for @month_5.
  ///
  /// In bg, this message translates to:
  /// **'май'**
  String get month_5;

  /// No description provided for @month_6.
  ///
  /// In bg, this message translates to:
  /// **'юни'**
  String get month_6;

  /// No description provided for @month_7.
  ///
  /// In bg, this message translates to:
  /// **'юли'**
  String get month_7;

  /// No description provided for @month_8.
  ///
  /// In bg, this message translates to:
  /// **'август'**
  String get month_8;

  /// No description provided for @month_9.
  ///
  /// In bg, this message translates to:
  /// **'септември'**
  String get month_9;

  /// No description provided for @month_10.
  ///
  /// In bg, this message translates to:
  /// **'октомври'**
  String get month_10;

  /// No description provided for @month_11.
  ///
  /// In bg, this message translates to:
  /// **'ноември'**
  String get month_11;

  /// No description provided for @month_12.
  ///
  /// In bg, this message translates to:
  /// **'декември'**
  String get month_12;

  /// No description provided for @tone.
  ///
  /// In bg, this message translates to:
  /// **'Глас'**
  String get tone;

  /// No description provided for @saints.
  ///
  /// In bg, this message translates to:
  /// **'Светии'**
  String get saints;

  /// No description provided for @readings.
  ///
  /// In bg, this message translates to:
  /// **'Евангелие и Апостол'**
  String get readings;

  /// No description provided for @troparia.
  ///
  /// In bg, this message translates to:
  /// **'Тропари и Кондаци'**
  String get troparia;

  /// No description provided for @theofan.
  ///
  /// In bg, this message translates to:
  /// **'Мисли от Теофан Затворник'**
  String get theofan;

  /// No description provided for @optina.
  ///
  /// In bg, this message translates to:
  /// **'Изречения от Оптинските старци'**
  String get optina;

  /// No description provided for @menuMain.
  ///
  /// In bg, this message translates to:
  /// **'ОСНОВНИ'**
  String get menuMain;

  /// No description provided for @menuOther.
  ///
  /// In bg, this message translates to:
  /// **'ДРУГИ'**
  String get menuOther;

  /// No description provided for @menuCalendar.
  ///
  /// In bg, this message translates to:
  /// **'Календар'**
  String get menuCalendar;

  /// No description provided for @menuPrayerbook.
  ///
  /// In bg, this message translates to:
  /// **'Молитвослов'**
  String get menuPrayerbook;

  /// No description provided for @menuBible.
  ///
  /// In bg, this message translates to:
  /// **'Библия'**
  String get menuBible;

  /// No description provided for @menuMenologion.
  ///
  /// In bg, this message translates to:
  /// **'Месецослов'**
  String get menuMenologion;

  /// No description provided for @menuHolidays.
  ///
  /// In bg, this message translates to:
  /// **'Празници'**
  String get menuHolidays;

  /// No description provided for @menuCommemoration.
  ///
  /// In bg, this message translates to:
  /// **'Дни за поменване'**
  String get menuCommemoration;

  /// No description provided for @menuFasts.
  ///
  /// In bg, this message translates to:
  /// **'Пости'**
  String get menuFasts;

  /// No description provided for @menuReference.
  ///
  /// In bg, this message translates to:
  /// **'Справочник'**
  String get menuReference;

  /// No description provided for @menuSettings.
  ///
  /// In bg, this message translates to:
  /// **'Настройки'**
  String get menuSettings;

  /// No description provided for @menuRate.
  ///
  /// In bg, this message translates to:
  /// **'Оцени приложението'**
  String get menuRate;

  /// No description provided for @menuAbout.
  ///
  /// In bg, this message translates to:
  /// **'За приложението'**
  String get menuAbout;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['bg'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'bg':
      return AppLocalizationsBg();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
