import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/flow.dart';

/// Admin: login -> Students -> add a student (CLAUDE.md §16), end to end
/// against a real backend. See support/flow.dart for the fixtures.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a school admin admits a student into a class', (tester) async {
    // Unique per run, so a rerun without reseeding is not refused as a
    // duplicate admission number.
    final admissionNumber = 'E2E-${DateTime.now().millisecondsSinceEpoch % 1000000}';

    await startApp(tester);
    await login(tester, email: 'itest-admin@example.com');
    expect(find.text('Dashboard'), findsWidgets);

    await openPage(tester, 'Students');
    await tester.tap(find.widgetWithText(FilledButton, 'Add Student'));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    await tester.enterText(find.widgetWithText(TextFormField, 'First name'), 'Aanya');
    await tester.enterText(find.widgetWithText(TextFormField, 'Last name'), 'Iyer');
    await tester.enterText(find.widgetWithText(TextFormField, 'Admission ID'), admissionNumber);
    await tester.enterText(find.widgetWithText(TextFormField, 'Parent / Guardian'), 'Kavitha Iyer');
    await pickFromDropdown<int>(tester, 'Class', 'Grade 8 A');

    await tester.tap(find.widgetWithText(FilledButton, 'Save Student'));
    await tester.pumpAndSettle(const Duration(seconds: 3));

    expect(find.text('Student admitted.'), findsOneWidget);
    // Sorted by first name, so "Aanya" is on the first page.
    expect(find.text(admissionNumber), findsOneWidget);
    expect(find.text('Aanya Iyer'), findsOneWidget);
  });
}
