import 'package:edutrack_app/core/widgets/sidebar_nav.dart';
import 'package:edutrack_app/features/assessments/presentation/marks_sheet_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/flow.dart';

/// Teacher: sign in -> Class Tests -> set a test -> open its marks sheet ->
/// mark the class, one of them absent -> save -> reopen and find it back.
/// End to end against a real backend (docs/assessments.md).
///
/// Two things only a run like this proves: the whole class saves in one
/// write, and a mark the test cannot hold is refused by the row it came
/// from rather than by a banner at the top.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a teacher marks a class in one pass', (tester) async {
    await startApp(tester);
    await login(tester, email: 'itest-teacher@example.com');

    await waitFor(tester, find.byType(SidebarNav));
    await openPage(tester, 'Class Tests');

    final title = 'Marks ${DateTime.now().millisecondsSinceEpoch % 100000}';

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

    // Open the sheet for the test just set.
    await tester.tap(find.widgetWithText(TextButton, 'Marks').first);
    await waitFor(tester, find.byType(MarksSheetDialog));
    expect(find.textContaining('of 3 marked'), findsOneWidget);

    // A mark the test cannot hold, refused on its own row.
    await typeMark(tester, 0, '99');
    await tester.tap(find.widgetWithText(FilledButton, 'Save Marks'));
    await tester.pumpAndSettle(const Duration(seconds: 3));
    expect(find.textContaining('between 0 and 20'), findsOneWidget);

    // Marked properly, with one absence, and saved in one write.
    await typeMark(tester, 0, '17.5');
    await typeMark(tester, 1, '12');
    await tester.tap(find.widgetWithText(FilterChip, 'Absent').at(2));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Save Marks'));
    await tester.pumpAndSettle(const Duration(seconds: 3));
    expect(find.textContaining('could not be saved'), findsNothing, reason: 'the second save was refused too');
    expect(find.textContaining('between 0 and 20'), findsNothing, reason: 'the old row error is still showing');
    await waitFor(tester, find.text('Marks saved.'));

    expect(find.text('3 of 3 marked'), findsOneWidget);

    // Closed and reopened, the marks are what the server has.
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle(const Duration(seconds: 2));
    await tester.tap(find.widgetWithText(TextButton, 'Marks').first);
    await waitFor(tester, find.byType(MarksSheetDialog));

    expect(find.text('3 of 3 marked'), findsOneWidget);
    expect(find.widgetWithText(TextField, '17.5'), findsOneWidget);
  });
}

/// Types into the marks box of one row.
///
/// The box is tapped first: on the web build a programmatic enterText into a
/// field that does not hold focus is dropped, which is how a corrected mark
/// silently stayed at its old value.
Future<void> typeMark(WidgetTester tester, int index, String value) async {
  await tester.tap(markBox(index));
  await tester.pumpAndSettle();
  await tester.enterText(markBox(index), value);
  await tester.pumpAndSettle();
}

/// The marks box of one row, scoped to the dialog so nothing else on the
/// page can be mistaken for it.
Finder markBox(int index) {
  return find.descendant(of: find.byType(MarksSheetDialog), matching: find.byType(TextField)).at(index);
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
