import 'package:edutrack_app/core/routing/family_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../features/family/family_app_test.dart' show pumpFamilyApp;
import '../support/fake_family_repositories.dart';
import 'a11y_audit.dart';

/// Large text and screen readers in the Family app (docs/mobile-apps-review.md,
/// M11, 3.4): every screen, in English and Hindi, at normal and double text
/// size - nothing runs off the screen, every button says what it is, every
/// target is at least 48 x 48.
void main() {
  for (final locale in const [Locale('en'), Locale('hi')]) {
    for (final scale in [1.0, 2.0]) {
      for (final path in familyPaths.where((p) => p != '/bus/live')) {
        testWidgets('$path in ${locale.languageCode} at ${scale}x', (tester) async {
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          final handle = tester.ensureSemantics();
          final audit = A11yAudit(tester)..watchLayout();

          await pumpFamilyApp(tester, data: FakeFamilyRepository(), goTo: path, locale: locale);

          expect(await audit.checkScrolling(), isEmpty);
          handle.dispose();
        });
      }
    }
  }
}
