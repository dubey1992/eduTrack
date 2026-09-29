import 'package:edutrack_app/core/widgets/sidebar_nav.dart';
import 'package:edutrack_app/features/promotion/data/models/promotion_preview.dart';
import 'package:edutrack_app/features/students/presentation/student_history_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/flow.dart';

/// School Admin: sign in -> Class Promotion -> review Grade 8 A -> hold one
/// child back, finish another -> promote -> open a promoted student's class
/// history and find both years. End to end against a real backend
/// (docs/promotion.md).
///
/// This is the flow the plan asks for, and the one only a real run proves:
/// a promotion writes four kinds of row at once - the year that closed, the
/// year that opened, the student's own class pointer and the batch - and
/// every one of them has to agree afterwards. A unit test can call the
/// service that writes them; only this can press the button.
///
/// It uses the fixtures' Grade 8 A up, so seed before running it:
///   cd backend-python && python manage.py integration_fixtures seed
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('an administrator moves a class into next year', (tester) async {
    try {
      await runFlow(tester);
    } catch (error) {
      // A failure inside a helper reports "No element" and names no step, so
      // the screen it happened on is printed with it.
      fail('$error\n\nOn screen: ${onScreen(tester)}');
    }
  });
}

Future<void> runFlow(WidgetTester tester) async {
  await startApp(tester);
  await login(tester, email: 'itest-admin@example.com');

  await waitFor(tester, find.byType(SidebarNav));
  await openPage(tester, 'Class Promotion');

  // Step one: which class, into which year. The target class is left for
  // the backend to suggest, which is the ordinary case.
  expect(
    find.widgetWithText(DropdownButtonFormField<int?>, 'Class to promote'),
    findsOneWidget,
    reason: 'step one should offer the class picker',
  );
  await pickFromDropdown<int?>(tester, 'Class to promote', 'Grade 8 A');
  await pickFromDropdown<int?>(tester, 'Into academic year', '2027-28');

  expect(
    find.widgetWithText(FilledButton, 'Review students'),
    findsOneWidget,
    reason: 'both choices made, so the review button should be there',
  );
  await tester.tap(find.widgetWithText(FilledButton, 'Review students'));
  await tester.pumpAndSettle(const Duration(seconds: 3));

  // Step two: the roster, with a default for everybody and the suggested
  // target named.
  await waitFor(tester, find.text('Aarav Sharma'));
  expect(find.text('Grade 9 A'), findsWidgets, reason: 'the class above, suggested');
  expect(find.text('Promote: 3'), findsOneWidget);

  // One child held back, one finished. Their rows are found by the outcome
  // box, which carries the student id.
  await setOutcome(tester, 'Bina Kapoor', 'Retain');
  await setOutcome(tester, 'Chetan Rao', 'Graduate');

  expect(find.text('Promote: 1'), findsOneWidget);
  expect(find.text('Retain: 1'), findsOneWidget);
  expect(find.text('Graduate: 1'), findsOneWidget);

  // Step three: the counts spelled out before anything is written.
  expect(
    find.widgetWithText(FilledButton, 'Promote this class'),
    findsOneWidget,
    reason: 'a class that can be promoted should offer the button',
  );
  await tester.tap(find.widgetWithText(FilledButton, 'Promote this class'));
  await tester.pumpAndSettle(const Duration(seconds: 1));

  expect(find.text('Promote this class?'), findsOneWidget);
  expect(find.textContaining('1 promoted to Grade 9 A'), findsOneWidget);
  expect(find.textContaining('cannot be undone from here'), findsOneWidget);

  await tester.tap(find.widgetWithText(FilledButton, 'Promote'));
  await tester.pumpAndSettle(const Duration(seconds: 4));

  // What the run did, instead of the roster it was working on.
  await waitFor(tester, find.textContaining('has moved into 2027-28'));
  expect(find.text('Promoted: 1'), findsOneWidget);
  expect(find.text('Retained: 1'), findsOneWidget);
  expect(find.text('Graduated: 1'), findsOneWidget);

  // And the child's own record now covers both years.
  await openPage(tester, 'Students');
  await tester.enterText(find.widgetWithText(TextField, 'Search by name / admission ID'), 'Aarav');
  await tester.pumpAndSettle(const Duration(seconds: 2));
  await waitFor(tester, find.text('Aarav Sharma'));

  expect(find.byTooltip('Class history'), findsWidgets, reason: 'the student row should offer its history');
  await tester.tap(find.byTooltip('Class history').first);
  await waitFor(tester, find.byType(StudentHistoryDialog));

  final dialog = find.byType(StudentHistoryDialog);
  expect(find.descendant(of: dialog, matching: find.text('Grade 8 A')), findsOneWidget);
  expect(find.descendant(of: dialog, matching: find.text('Grade 9 A')), findsOneWidget);
  expect(find.descendant(of: dialog, matching: find.text('Promoted')), findsOneWidget);
  expect(find.descendant(of: dialog, matching: find.text('Studying')), findsOneWidget);
}

/// Every piece of text the app is showing, for a failure message.
String onScreen(WidgetTester tester) {
  return tester.widgetList<Text>(find.byType(Text)).map((widget) => widget.data).whereType<String>().join(' | ');
}

/// Sets one student's outcome on the review step.
Future<void> setOutcome(WidgetTester tester, String student, String outcome) async {
  final boxes = find.byWidgetPredicate((widget) => widget is DropdownButtonFormField<PromotionOutcome>);

  await tester.tap(onSameLineAs(tester, find.text(student), boxes));
  await tester.pumpAndSettle();

  expect(find.text(outcome), findsWidgets, reason: 'the menu should offer $outcome');
  await tester.tap(find.text(outcome).last);
  await tester.pumpAndSettle(const Duration(seconds: 1));
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
