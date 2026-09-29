import 'package:edutrack_app/core/widgets/sidebar_nav.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/flow.dart';

/// School Admin: sign in -> Academic Years -> Terms -> add Term 1 -> try to
/// add a second term that overlaps it and be refused -> move its start and
/// have it accepted. End to end against a real backend (docs/assessments.md).
///
/// The overlap is the point of the flow. It is the rule that keeps a mark
/// from belonging to two terms at once, and it is enforced in the backend,
/// so only a run like this one proves the message reaches the field.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('an administrator sets out the terms of the year', (tester) async {
    await startApp(tester);
    await login(tester, email: 'itest-admin@example.com');

    // Signing in against a real backend takes as long as it takes; the
    // sidebar is what says it finished.
    await waitFor(tester, find.byType(SidebarNav));
    await openPage(tester, 'Academic Years');

    // Next year rather than this one, and by name rather than by position:
    // the fixtures give the current year a term covering every day of it,
    // so nothing can be added there without overlapping it. A year whose
    // terms have not been set out yet is the case this flow is about.
    await openTermsFor(tester, '2027-28');
    expect(find.textContaining('Terms ·'), findsOneWidget);

    await addTerm(tester, name: 'Term 1', order: '1', start: '04/01/2027', end: '08/31/2027');
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(find.text('Term 1'), findsWidgets);

    // A second term over the same days is refused, and the reason lands on
    // the field it is about rather than in a banner.
    await addTerm(tester, name: 'Term 2', order: '2', start: '08/01/2027', end: '12/31/2027');
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(find.textContaining('overlap Term 1'), findsOneWidget);

    // Moved to start the day after Term 1 ends, the same term is accepted.
    await pickDate(tester, 'Start date', '09/01/2027');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle(const Duration(seconds: 3));

    expect(find.text('Term added.'), findsOneWidget);
    expect(find.text('Term 2'), findsWidgets);
  });
}

/// Opens the Add Term form and fills it in, leaving it submitted.
Future<void> addTerm(
  WidgetTester tester, {
  required String name,
  required String order,
  required String start,
  required String end,
}) async {
  await tester.tap(find.widgetWithText(TextButton, 'Add Term'));
  await tester.pumpAndSettle(const Duration(seconds: 1));

  await tester.enterText(find.widgetWithText(TextFormField, 'Name (e.g. Term 1)'), name);
  await tester.enterText(find.widgetWithText(TextFormField, 'Order within the year'), order);
  await pickDate(tester, 'Start date', start);
  await pickDate(tester, 'End date', end);

  await tester.tap(find.widgetWithText(FilledButton, 'Save'));
  await tester.pumpAndSettle(const Duration(seconds: 3));
}

/// Opens the Terms dialog of one named year.
///
/// The button is the one on that year's line, which is how a person finds
/// it: the table has a Terms button per row and they all read the same.
Future<void> openTermsFor(WidgetTester tester, String year) async {
  await tester.tap(onSameLineAs(tester, find.text(year), find.widgetWithText(TextButton, 'Terms')));
  await tester.pumpAndSettle(const Duration(seconds: 2));
}

/// Types the date into the picker's input mode. Tapping day cells would
/// depend on which month the calendar happens to open on.
Future<void> pickDate(WidgetTester tester, String label, String text) async {
  await tester.tap(find.text(label), warnIfMissed: false);
  await tester.pumpAndSettle();

  // Scoped to the picker: the row behind the dialog has an Edit icon too,
  // and an unscoped finder matches both.
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
