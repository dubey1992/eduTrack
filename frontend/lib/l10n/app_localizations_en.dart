// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get languageTitle => 'Language';

  @override
  String get languagePhone => 'Phone\'s language';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageHindi => 'हिन्दी';

  @override
  String get languageChanged => 'Language changed.';

  @override
  String get cancel => 'Cancel';

  @override
  String get retry => 'Retry';

  @override
  String get errorNoConnection => 'Could not reach the server. Check your connection and try again.';

  @override
  String get errorTimeout => 'The server is taking longer than usual to answer. Try again in a moment.';

  @override
  String get errorUnknown => 'Something went wrong. Please try again.';
}
