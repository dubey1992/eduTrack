import 'package:edutrack_app/core/widgets/sidebar_nav.dart';
import 'package:edutrack_app/features/students/presentation/student_history_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/flow.dart';

/// School Admin: sign in -> Students -> admit a student -> open their class
/// history and find the year already recorded. End to end against a real
/// backend (docs/promotion.md).
///
/// Nobody asks for the history to be written: admitting the student is what
/// writes it. That is the part only a run like this one proves, because a
/// unit test can always call the thing that does the writing.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a student admitted today already has this year in their history', (tester) async {
    await startApp(tester);
    await login(tester, email: 'itest-admin@example.com');

    await waitFor(tester, find.byType(SidebarNav));
    await openPage(tester, 'Students');

    final admissionNumber = 'HIST-${DateTime.now().millisecondsSinceEpoch % 100000}';

    await tester.tap(find.widgetWithText(FilledButton, 'Add Student'));
    await tester.pumpAndSettle(const Duration(seconds: 1));

    await tester.enterText(find.widgetWithText(TextFormField, 'First name'), 'Historic');
    await tester.enterText(find.widgetWithText(TextFormField, 'Last name'), 'Student');
    await tester.enterText(find.widgetWithText(TextFormField, 'Admission ID'), admissionNumber);
    await tester.enterText(find.widgetWithText(TextFormField, 'Roll number (optional)'), '42');
    await tester.enterText(find.widgetWithText(TextFormField, 'Parent / Guardian'), 'Historic Guardian');
    await pickFromDropdown<int>(tester, 'Class', 'Grade 8 A');

    await tester.tap(find.widgetWithText(FilledButton, 'Save Student'));
    await tester.pumpAndSettle(const Duration(seconds: 3));

    // Find the student that was just admitted, and open their history.
    // The search box is a plain TextField, not a form field.
    await tester.enterText(find.widgetWithText(TextField, 'Search by name / admission ID'), admissionNumber);
    await tester.pumpAndSettle(const Duration(seconds: 2));
    await waitFor(tester, find.text(admissionNumber));

    await tester.tap(find.byTooltip('Class history').first);
    await waitFor(tester, find.byType(StudentHistoryDialog));

    expect(find.textContaining('History · Historic Student'), findsOneWidget);
    expect(find.descendant(of: find.byType(StudentHistoryDialog), matching: find.text('Grade 8 A')), findsOneWidget);
    expect(find.textContaining('Roll 42'), findsOneWidget);
    expect(find.text('Studying'), findsOneWidget);
  });
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
