import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/flow.dart';

/// HOD: login -> teaching reports -> review (CLAUDE.md §16), with the teacher
/// filing the report first, end to end against a real backend. Needs today to
/// be a working day at the school. See support/flow.dart for the fixtures.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a teacher files a report for a period and their HOD reviews it', (tester) async {
    await startApp(tester);

    // ---- Teacher files the report for today's period ----
    await login(tester, email: 'itest-teacher@example.com');
    await openPage(tester, 'Teaching Reports');

    // The teacher has more than one period today, so the button is the one
    // on the Physics line - the period this report is about.
    await tester.tap(
      onSameLineAs(
        tester,
        // The period's line reads "Period 1 · Physics" as one piece of
        // text, so the subject is looked for inside it.
        find.textContaining('Physics'),
        find.widgetWithText(FilledButton, 'Submit Report'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Topic taught'), "Newton's laws of motion");
    // The row behind the dialog has a button with the same text.
    await tester.tap(find.widgetWithText(FilledButton, 'Submit Report').last);
    await tester.pumpAndSettle(const Duration(seconds: 3));

    expect(find.text('Report submitted.'), findsOneWidget);
    expect(statusBadge('Submitted'), findsOneWidget);

    await logout(tester);

    // ---- HOD reviews it ----
    await login(tester, email: 'itest-hod@example.com');
    await openPage(tester, 'Teaching Reports');

    expect(find.text("Newton's laws of motion"), findsOneWidget);
    expect(statusBadge('Pending Review'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Mark Reviewed'));
    await tester.pumpAndSettle(const Duration(seconds: 3));

    expect(find.text('Report reviewed.'), findsOneWidget);
    expect(statusBadge('Reviewed'), findsOneWidget);
    expect(statusBadge('Pending Review'), findsNothing);
  });
}
