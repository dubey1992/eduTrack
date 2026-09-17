import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/flow.dart';

/// Teacher: login -> attendance -> submit (CLAUDE.md §16), end to end against
/// a real backend. Needs today to be a working day at the school. See
/// support/flow.dart for the fixtures.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets("a class teacher marks and submits today's register", (tester) async {
    await startApp(tester);
    await login(tester, email: 'itest-teacher@example.com');

    await openPage(tester, 'Student Attendance');
    await pickFromDropdown<int>(tester, 'Class', 'Grade 8 A');

    expect(find.text('Not yet submitted'), findsOneWidget);
    expect(find.text('Aarav Sharma'), findsOneWidget);

    // Everybody present, then one child absent - the chips show P / A / L and
    // carry the full word as a tooltip.
    await tester.tap(find.widgetWithText(TextButton, 'Mark All Present'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Absent').first);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Submit Attendance'));
    await tester.pumpAndSettle(const Duration(seconds: 3));

    expect(find.text('Attendance submitted.'), findsOneWidget);
    expect(find.text('Submitted'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Update Attendance'), findsOneWidget);
  });
}
