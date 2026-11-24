import 'package:flutter/widgets.dart';

import '../../l10n/app_localizations.dart';
import '../../l10n/app_localizations_en.dart';

export '../../l10n/app_localizations.dart';

/// The phone apps' words in the person's language (docs/mobile-apps-review.md,
/// M11): `Text(context.l10n.languageTitle)`.
///
/// English wherever no translations are set up above the widget - the web
/// office, which stays English for now, and widget tests that pump a bare
/// MaterialApp - so a shared screen never breaks for want of them.
extension AppL10n on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this) ?? _english;
}

final AppLocalizations _english = AppLocalizationsEn();
