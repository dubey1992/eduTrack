// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Hindi (`hi`).
class AppLocalizationsHi extends AppLocalizations {
  AppLocalizationsHi([String locale = 'hi']) : super(locale);

  @override
  String get languageTitle => 'भाषा';

  @override
  String get languagePhone => 'फ़ोन की भाषा';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageHindi => 'हिन्दी';

  @override
  String get languageChanged => 'भाषा बदल दी गई।';

  @override
  String get cancel => 'रद्द करें';

  @override
  String get retry => 'फिर से कोशिश करें';

  @override
  String get errorNoConnection => 'सर्वर से संपर्क नहीं हो सका। अपना इंटरनेट देखें और फिर से कोशिश करें।';

  @override
  String get errorTimeout => 'सर्वर जवाब देने में सामान्य से ज़्यादा समय ले रहा है। थोड़ी देर में फिर से कोशिश करें।';

  @override
  String get errorUnknown => 'कुछ गड़बड़ हो गई। कृपया फिर से कोशिश करें।';
}
