import 'package:flutter/widgets.dart';
import 'package:hermes_android/l10n/app_localizations.dart';

/// Localization delegates for widget tests, mirroring the app's MaterialApp
/// configuration so widgets calling `context.l10n` resolve English strings.
const l10nTestDelegates = <LocalizationsDelegate<dynamic>>[
  ...AppLocalizations.localizationsDelegates,
];

/// Supported locales for widget tests (English default, matching
/// `flutter_test`'s en_US environment).
const l10nTestSupportedLocales = AppLocalizations.supportedLocales;
