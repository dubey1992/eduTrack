import 'package:edutrack_app/core/widgets/sidebar_nav.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/flow.dart';

/// Teacher: sign in -> Class Tests -> set a test for the class they teach,
/// with a date outside the term first so the refusal is seen. End to end
/// against a real backend (docs/assessments.md).
///
/// The refusal is the point. Every id in the form is valid on its own; it is
/// the combination that is wrong, and only the server can say so.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a teacher sets a class test', (tester) async {
    await startApp(tester);
    await login(tester, email: 'itest-teacher@example.com');

    await waitFor(tester, find.byType(SidebarNav));
    await openPage(tester, 'Class Tests');

    await tester.tap(find.widgetWithText(FilledButton, 'New Test'));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    final title = 'E2E test ${DateTime.now().millisecondsSinceEpoch % 100000}';

    await pickFromDropdown<int>(tester, 'Class', 'Grade 8 A');
    await pickFromDropdown<int>(tester, 'Subject', 'Mathematics');
    await pickFromDropdown<int>(tester, 'Term', 'E2E Term');
    await tester.enterText(find.widgetWithText(TextFormField, 'Title'), title);
    await tester.enterText(find.widgetWithText(TextFormField, 'Out of'), '20');

    // A date the term does not cover: valid on its own, wrong here.
    await pickDate(tester, '01/01/2030');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle(const Duration(seconds: 3));
    expect(find.textContaining('must fall inside'), findsOneWidget);

    // Inside the term, the same test is accepted.
    await pickDate(tester, '07/15/2026');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle(const Duration(seconds: 3));

    expect(find.text('Test created.'), findsOneWidget);
    expect(find.text(title), findsWidgets);
    expect(find.text('Draft'), findsWidgets);
  });
}

/// Types the date into the picker's input mode. Tapping day cells would
/// depend on which month the calendar happens to open on.
Future<void> pickDate(WidgetTester tester, String text) async {
  await tester.tap(find.text('Date'), warnIfMissed: false);
  await tester.pumpAndSettle();

  await tester.tap(find.descendant(of: find.byType(DatePickerDialog), matching: find.byIcon(Icons.edit_outlined)));
  await tester.pumpAndSettle();

  final field = find.descendant(of: find.byType(InputDatePickerFormField), matching: find.byType(TextFormField));
  await tester.enterText(field, text);
  await tester.tap(find.text('OK'));
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
