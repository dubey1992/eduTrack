import 'package:edutrack_app/features/communication/data/models/message.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/flow.dart';

/// Admin: login -> Communication -> Send Message -> a class's guardians,
/// end to end against a real backend (docs/communication.md, "Messages
/// written by hand"). The fixtures give the three students of Grade 8 A a
/// guardian mobile number, so the preview counts them and the send is
/// accepted and queued for the worker.
///
/// A group rather than one student on purpose: the one-student path goes
/// through a search field whose suggestions only show while the field has
/// focus, and a browser driven in the background never gives it any. That
/// path is covered by the widget tests and was checked by hand in a browser.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets("a school admin messages a class's guardians", (tester) async {
    await startApp(tester);
    await login(tester, email: 'itest-admin@example.com');

    await openPage(tester, 'Communication');

    await tester.tap(find.widgetWithText(FilledButton, 'Send Message'));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    await pickFromDropdown<NoticeAudience>(tester, 'Audience', 'A class section');
    await pickFromDropdown<int>(tester, 'Class', 'Grade 8 A');

    await tester.enterText(find.widgetWithText(TextFormField, 'Subject'), 'PTA meeting');
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Message'),
      'The parent-teacher meeting is on Friday at 3 PM.',
    );

    // The dialog says who it reaches before anything is sent; the count is
    // a real request, so it is given time to answer.
    await waitFor(tester, find.textContaining('Reaches 3 people'));

    await tester.tap(find.widgetWithText(FilledButton, 'Send'));
    await waitFor(tester, find.text('Queued for 3 people.'));
  });
}

/// Pumps until [finder] matches, giving a real request time to answer.
Future<void> waitFor(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 30 && finder.evaluate().isEmpty; attempt++) {
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await tester.pump();
  }
  await tester.pumpAndSettle();
  expect(finder, findsWidgets);
}
