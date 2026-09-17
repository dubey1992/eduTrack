import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/flow.dart';

/// End-to-end regression for Phase 9: drives the REAL compiled app (no
/// mocked repositories) against a REAL backend, in a real visible browser
/// window - a teacher applies for leave and the HOD of their department
/// approves it, which writes the leave onto staff attendance.
///
/// See support/flow.dart for the fixtures and how to run it.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a teacher applies for leave and an HOD approves it, syncing attendance', (tester) async {
    await startApp(tester);

    // ---- Teacher applies for leave ----
    await login(tester, email: 'itest-teacher@example.com');
    expect(find.text('Dashboard'), findsWidgets);

    await openPage(tester, 'Staff Leave');

    await tester.tap(find.text('Apply Leave'));
    await tester.pumpAndSettle();

    // Leave type stays at the default (Casual), From/To stay at today - a
    // valid single-day request - only the required reason needs filling in.
    await tester.enterText(find.widgetWithText(TextFormField, 'Reason'), 'Integration test leave request');
    await tester.tap(find.widgetWithText(FilledButton, 'Submit Request'));
    await tester.pumpAndSettle(const Duration(seconds: 3));

    expect(find.text('Leave request submitted.'), findsOneWidget);
    expect(statusBadge('Pending'), findsOneWidget);

    await logout(tester);

    // ---- HOD reviews and approves it ----
    await login(tester, email: 'itest-hod@example.com');

    await openPage(tester, 'Staff Leave');

    expect(find.text('Approve'), findsOneWidget);
    await tester.tap(find.text('Approve'));
    await tester.pumpAndSettle(const Duration(seconds: 3));

    expect(find.text('Leave request approved.'), findsOneWidget);
    expect(statusBadge('Approved'), findsOneWidget);
    expect(statusBadge('Pending'), findsNothing);
  });
}
