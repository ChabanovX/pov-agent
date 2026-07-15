import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';

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
  AppLocalizations(String locale) : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate = _AppLocalizationsDelegate();

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
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates = <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[Locale('en')];

  /// Application title used by the operating system.
  ///
  /// In en, this message translates to:
  /// **'Camera Assistant'**
  String get appTitle;

  /// Label and page title for the camera tab.
  ///
  /// In en, this message translates to:
  /// **'Camera'**
  String get cameraTabLabel;

  /// Label and page title for the AI assistant tab.
  ///
  /// In en, this message translates to:
  /// **'Assistant'**
  String get assistantTabLabel;

  /// Placeholder message centered on the camera tab.
  ///
  /// In en, this message translates to:
  /// **'Camera placeholder'**
  String get cameraPlaceholderTitle;

  /// Placeholder message centered on the AI assistant tab.
  ///
  /// In en, this message translates to:
  /// **'Assistant placeholder'**
  String get assistantPlaceholderTitle;

  /// Message shown when the user has manually disabled the camera.
  ///
  /// In en, this message translates to:
  /// **'Camera is off.'**
  String get cameraDisabledMessage;

  /// Button and accessibility label for enabling the camera.
  ///
  /// In en, this message translates to:
  /// **'Enable camera'**
  String get cameraEnableAction;

  /// Accessibility label for disabling the camera.
  ///
  /// In en, this message translates to:
  /// **'Disable camera'**
  String get cameraDisableAction;

  /// Accessibility label for switching between front and rear cameras.
  ///
  /// In en, this message translates to:
  /// **'Switch camera'**
  String get cameraSwitchAction;

  /// Guidance shown when camera permission is denied.
  ///
  /// In en, this message translates to:
  /// **'Camera access is disabled. Allow camera access in Settings, then retry.'**
  String get cameraPermissionDeniedMessage;

  /// Message shown when the device has no supported camera.
  ///
  /// In en, this message translates to:
  /// **'No supported camera is available on this device.'**
  String get cameraUnavailableMessage;

  /// Fallback message shown when camera startup fails.
  ///
  /// In en, this message translates to:
  /// **'The camera could not be started.'**
  String get cameraFailureMessage;

  /// Generic scaffolded feature page title.
  ///
  /// In en, this message translates to:
  /// **'{featureName}'**
  String featurePageTitle(String featureName);

  /// Message shown when a load-once list has no items.
  ///
  /// In en, this message translates to:
  /// **'Nothing here yet.'**
  String get emptyStateMessage;

  /// Button label for retrying a failed operation.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retryAction;
}

class _AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>['en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
