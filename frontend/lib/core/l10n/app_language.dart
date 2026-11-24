import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/key_value_store.dart';

/// Which language a phone app shows (docs/mobile-apps-review.md, M11,
/// decided 2026-11-24): the phone's own, unless the person picked one in
/// their profile. Kept on the phone only - nothing about it reaches the
/// server - and kept across sign-out: it belongs to the phone, not to a
/// session.
enum AppLanguage {
  /// Follow the phone: Hindi when the phone is in Hindi, else English.
  phone(null, null),
  english('en', Locale('en')),
  hindi('hi', Locale('hi'));

  const AppLanguage(this.code, this.locale);

  /// What is saved; null for [phone], which saves nothing.
  final String? code;

  /// The locale to force, or null to let the phone decide.
  final Locale? locale;

  static AppLanguage fromCode(String? code) =>
      values.firstWhere((language) => language.code != null && language.code == code, orElse: () => phone);
}

class AppLanguageController extends Notifier<AppLanguage> {
  static const key = 'app.language';

  @override
  AppLanguage build() {
    _load();
    return AppLanguage.phone;
  }

  KeyValueStore get _store => ref.read(keyValueStoreProvider);

  Future<void> _load() async {
    try {
      state = AppLanguage.fromCode(await _store.read(key));
    } on Exception catch (error) {
      debugPrint('Language: could not read the choice from the phone: $error');
    }
  }

  Future<void> choose(AppLanguage language) async {
    state = language;
    try {
      final code = language.code;
      code == null ? await _store.delete(key) : await _store.write(key, code);
    } on Exception catch (error) {
      debugPrint('Language: could not save the choice on the phone: $error');
    }
  }
}

final appLanguageProvider = NotifierProvider<AppLanguageController, AppLanguage>(AppLanguageController.new);

/// Whether this app offers the language setting. The phone apps switch it
/// on (main_driver/main_teacher/main_family); the web office, which shares
/// the profile screen, stays English for now (M11).
final languagePickerEnabledProvider = Provider<bool>((ref) => false);
