import 'package:edutrack_app/core/widgets/sidebar_nav.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/flow.dart';

/// School Admin: sign in -> Grade Scales -> build a scale whose bands leave a
/// hole in the range and be refused on the field -> fix it and save. End to
/// end against a real backend (docs/assessments.md).
///
/// The refusal is the point. A scale that does not cover 0 to 100 leaves some
/// mark with no grade at all, and that is only discovered when results are
/// published unless the form refuses it here.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('an administrator builds a grade scale', (tester) async {
    await startApp(tester);
    await login(tester, email: 'itest-admin@example.com');

    await waitFor(tester, find.byType(SidebarNav));
    await openPage(tester, 'Grade Scales');

    await tester.tap(find.widgetWithText(FilledButton, 'Add Grade Scale'));
    await tester.pumpAndSettle(const Duration(seconds: 1));

    await tester.enterText(find.widgetWithText(TextFormField, 'Name (e.g. Secondary)'), 'Secondary');
    await fillBand(tester, 0, label: 'Pass', from: '33', to: '100');

    // One band starting at 33 leaves 0 to 32 with no grade.
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle(const Duration(seconds: 3));
    // The exact sentence: the form's own hint also mentions starting at 0.
    expect(find.text('The lowest band must start at 0, so every mark has a grade.'), findsOneWidget);

    // Add the band underneath it, and the same scale is accepted.
    await tester.tap(find.widgetWithText(TextButton, 'Add band'));
    await tester.pumpAndSettle();
    await fillBand(tester, 1, label: 'Fail', from: '0', to: '32');

    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle(const Duration(seconds: 3));

    expect(find.text('Grade scale created.'), findsOneWidget);
    expect(find.text('Pass  33 - 100'), findsWidgets);
    expect(find.text('Default'), findsWidgets);
  });
}

/// Fills the band row at [index]. The rows share their field labels, so each
/// one is reached by position rather than by label.
Future<void> fillBand(
  WidgetTester tester,
  int index, {
  required String label,
  required String from,
  required String to,
}) async {
  await tester.enterText(find.widgetWithText(TextFormField, 'Grade').at(index), label);
  await tester.enterText(find.widgetWithText(TextFormField, 'From %').at(index), from);
  await tester.enterText(find.widgetWithText(TextFormField, 'To %').at(index), to);
  await tester.pumpAndSettle();
}

/// Pumps until [finder] matches, giving a real request time to answer.
Future<void> waitFor(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 40 && finder.evaluate().isEmpty; attempt++) {
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await tester.pump();
  }
  await tester.pumpAndSettle();
  expect(finder, findsWidgets);
}
