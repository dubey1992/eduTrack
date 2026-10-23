import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/marketing/presentation/privacy_policy_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The page Play asks for, and the one a parent reads (docs/driver-app.md,
/// D6.1). These pin the promises the app actually has to keep - if one of
/// them stops being true, the page is a lie and this test is where that
/// gets noticed.
void main() {
  Future<void> pumpScreen(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(theme: AppTheme.light(), home: const PrivacyPolicyScreen()));
    await tester.pumpAndSettle();
  }

  testWidgets('needs no account to read', (tester) async {
    await pumpScreen(tester);

    expect(find.text('Privacy Policy'), findsWidgets);
  });

  testWidgets('says location is only taken while a trip runs', (tester) async {
    await pumpScreen(tester);

    expect(find.textContaining('does not ask for background location'), findsOneWidget);
    expect(find.textContaining('Sharing starts when a trip starts'), findsOneWidget);
  });

  testWidgets('says how long positions are kept', (tester) async {
    await pumpScreen(tester);

    expect(find.textContaining('deleted after 30 days'), findsOneWidget);
  });

  testWidgets("says a guardian's number is never recorded", (tester) async {
    await pumpScreen(tester);

    expect(find.textContaining('phone number itself is never recorded'), findsOneWidget);
  });

  testWidgets('names the third parties that do receive something', (tester) async {
    await pumpScreen(tester);

    for (final service in ['Google Maps.', 'Google Fonts.', 'Hosting.']) {
      expect(find.textContaining(service), findsOneWidget, reason: service);
    }
  });

  testWidgets('carries a date, so a change to it is visible', (tester) async {
    await pumpScreen(tester);

    expect(find.text('Last updated ${PrivacyPolicyScreen.lastUpdated}'), findsOneWidget);
  });
}
