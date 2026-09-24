import 'package:edutrack_app/core/widgets/sidebar_nav.dart';
import 'package:edutrack_app/features/assessments/presentation/marks_sheet_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/flow.dart';

/// Teacher: set a test, mark the class, publish it, and find the sheet
/// closed. Then an administrator takes it back. End to end against a real
/// backend (docs/assessments.md).
///
/// The part only a run like this proves: publishing freezes each grade from
/// the school's own scale, and the sheet stops accepting marks afterwards.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a teacher publishes a result and an administrator reopens it', (tester) async {
    await startApp(tester);
    await login(tester, email: 'itest-teacher@example.com');

    await waitFor(tester, find.byType(SidebarNav));
    await openPage(tester, 'Class Tests');

    final title = 'Published ${DateTime.now().millisecondsSinceEpoch % 100000}';

    await tester.tap(find.widgetWithText(FilledButton, 'New Test'));
    await tester.pumpAndSettle(const Duration(seconds: 2));
    await pickFromDropdown<int>(tester, 'Class', 'Grade 8 A');
    await pickFromDropdown<int>(tester, 'Subject', 'Mathematics');
    await pickFromDropdown<int>(tester, 'Term', 'E2E Term');
    await tester.enterText(find.widgetWithText(TextFormField, 'Title'), title);
    await tester.enterText(find.widgetWithText(TextFormField, 'Out of'), '20');
    await pickDate(tester, '07/15/2026');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle(const Duration(seconds: 3));

    await tester.tap(find.widgetWithText(TextButton, 'Marks').first);
    await waitFor(tester, find.byType(MarksSheetDialog));

    // Publishing waits until the whole class is accounted for.
    expect(tester.widget<TextButton>(find.widgetWithText(TextButton, 'Publish')).onPressed, isNull);

    await typeMark(tester, 0, '19');
    await typeMark(tester, 1, '8');
    await tester.tap(find.widgetWithText(FilterChip, 'Absent').at(2));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save Marks'));
    await waitFor(tester, find.text('Marks saved.'));

    await tester.tap(find.widgetWithText(TextButton, 'Publish'));
    await tester.pumpAndSettle(const Duration(seconds: 1));
    await tester.tap(find.widgetWithText(FilledButton, 'Publish'));
    await waitFor(tester, find.text('Result published.'));

    // The sheet is closed now, and reads as a result.
    await tester.tap(find.widgetWithText(TextButton, 'Marks').first);
    await waitFor(tester, find.byType(MarksSheetDialog));
    expect(find.text('Save Marks'), findsNothing);
    expect(find.text('95%'), findsOneWidget, reason: '19 of 20');
    await tester.tap(find.widgetWithText(TextButton, 'Done'));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // A teacher cannot take it back; the administrator can.
    expect(find.text('Reopen'), findsNothing);
    await logout(tester);
    await login(tester, email: 'itest-admin@example.com');
    await waitFor(tester, find.byType(SidebarNav));
    await openPage(tester, 'Class Tests');

    await tester.tap(find.widgetWithText(TextButton, 'Reopen').first);
    await tester.pumpAndSettle(const Duration(seconds: 1));
    await tester.tap(find.widgetWithText(FilledButton, 'Reopen'));
    await waitFor(tester, find.textContaining('is a draft again'));

    expect(find.text('Draft'), findsWidgets);
  });
}

/// Types into the marks box of one row. The box is tapped first: on the web
/// build a keystroke into a field without focus is dropped.
Future<void> typeMark(WidgetTester tester, int index, String value) async {
  final box = find.descendant(of: find.byType(MarksSheetDialog), matching: find.byType(TextField)).at(index);

  await tester.tap(box);
  await tester.pumpAndSettle();
  await tester.enterText(box, value);
  await tester.pumpAndSettle();
}

/// Types the date into the picker's input mode.
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
