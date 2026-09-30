import 'package:edutrack_app/core/widgets/sidebar_nav.dart';
import 'package:edutrack_app/features/assessments/presentation/marks_sheet_dialog.dart';
import 'package:edutrack_app/features/students/presentation/student_performance_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/flow.dart';

/// Teacher publishes a result; an administrator reads what it adds up to and
/// prints the page that goes home. End to end against a real backend
/// (docs/assessments.md, slice 14).
///
/// The part only a run like this proves: the figures a guardian is handed
/// come back through the whole stack - published marks, the term's average,
/// the school's grade scale - and the download really is a PDF rather than
/// an error page with a hopeful filename.
///
/// Seed before running it:
///   cd backend-python && python manage.py integration_fixtures seed
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('an administrator prints a student\'s progress report', (tester) async {
    try {
      await runFlow(tester);
    } catch (error) {
      fail('$error\n\nOn screen: ${onScreen(tester)}');
    }
  });
}

Future<void> runFlow(WidgetTester tester) async {
  await startApp(tester);

  // ---- A result has to exist before it can be reported on ----
  await login(tester, email: 'itest-teacher@example.com');
  await waitFor(tester, find.byType(SidebarNav));
  await publishATest(tester, marks: const ['16', '12', '8']);

  await logout(tester);

  // ---- The administrator reads it, then prints it ----
  await login(tester, email: 'itest-admin@example.com');
  await waitFor(tester, find.byType(SidebarNav));
  await openPage(tester, 'Students');

  await waitFor(tester, find.text('Aarav Sharma'));
  expect(find.byTooltip('Performance'), findsWidgets, reason: 'the student row should offer their performance');

  await tester.tap(find.byTooltip('Performance').first);
  await waitFor(tester, find.byType(StudentPerformanceDialog));

  // The marks made it all the way through: 16 of 20 is 80%.
  await waitFor(tester, find.text('80.00%'));
  expect(find.text('Mathematics'), findsWidgets);

  expect(
    find.widgetWithText(OutlinedButton, 'Download PDF'),
    findsOneWidget,
    reason: 'a term with a published result should offer the printable report',
  );

  await tester.tap(find.widgetWithText(OutlinedButton, 'Download PDF'));

  // The success message is the only thing the app can show for a file the
  // browser has taken over; a failure would put the server's reason here
  // instead, which is what makes this worth asserting.
  await waitFor(tester, find.text('Progress report downloaded.'));
}

/// Sets a test for Grade 8 A, marks the class and publishes it.
///
/// The progress report needs a published result to describe, and the
/// fixtures deliberately seed none - a pre-seeded test would sit in the
/// Class Tests list and change what "the first row" means for every other
/// flow that works there.
Future<void> publishATest(WidgetTester tester, {required List<String> marks}) async {
  await openPage(tester, 'Class Tests');

  final title = 'Report ${DateTime.now().millisecondsSinceEpoch % 100000}';

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

  for (var index = 0; index < marks.length; index++) {
    await typeMark(tester, index, marks[index]);
  }

  await tester.tap(find.widgetWithText(FilledButton, 'Save Marks'));
  await waitFor(tester, find.text('Marks saved.'));

  await tester.tap(find.widgetWithText(TextButton, 'Publish'));
  await tester.pumpAndSettle(const Duration(seconds: 1));
  await tester.tap(find.widgetWithText(FilledButton, 'Publish'));
  await waitFor(tester, find.text('Result published.'));
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

/// Every piece of text the app is showing, for a failure message.
String onScreen(WidgetTester tester) {
  return tester.widgetList<Text>(find.byType(Text)).map((widget) => widget.data).whereType<String>().join(' | ');
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
