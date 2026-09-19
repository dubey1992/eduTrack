import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/flow.dart';

/// Staff: login -> header name chip -> My Profile -> change their name and
/// home address -> the header follows, end to end against a real backend
/// (docs/profile.md). A member of staff rather than an admin on purpose: the
/// point of the feature is that every role can do this for themselves.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a member of staff updates their own name and address', (tester) async {
    await startApp(tester);
    await login(tester, email: 'itest-staff@example.com');

    await tester.tap(find.byTooltip('My profile'));
    await tester.pumpAndSettle(const Duration(seconds: 2));
    await waitFor(tester, find.byKey(const Key('profile-first-name')));

    expect(find.text('My Profile'), findsWidgets);

    await tester.enterText(find.byKey(const Key('profile-first-name')), 'Priya');
    await tester.enterText(find.byKey(const Key('profile-address')), '7 Canal Road, Pune');
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('profile-save')));
    await waitFor(tester, find.text('Profile updated.'));

    // The session was re-read, so the name in the header changed with it.
    await waitFor(tester, find.textContaining('Priya'));
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
