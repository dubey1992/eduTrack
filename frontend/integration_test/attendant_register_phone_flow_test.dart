import 'package:edutrack_app/core/widgets/phone_number_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/flow.dart';

/// Bus Attendant: login screen -> "Bus attendant?" -> register this phone with
/// the setup code from the school office -> My Trip shows their route, end to
/// end against a real backend (docs/maps.md). The fixtures give the attendant
/// the mobile +91 90000 77777, no email, the setup code 24681357 and the route
/// "ITest Route".
///
/// Stops at the route card on purpose: starting a trip needs a school day,
/// and this flow has to pass on any day. Running a trip is covered by the
/// widget tests and by the transport trip flow.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a bus attendant registers their phone and lands on My Trip', (tester) async {
    await startApp(tester);

    await tester.tap(find.text('Bus attendant? Sign in with your mobile number'));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // A phone that has never been registered opens on the register form.
    expect(find.text('Register this phone'), findsWidgets);

    final mobile = find.descendant(of: find.byType(PhoneNumberField), matching: find.byType(TextFormField));
    await tester.enterText(mobile.last, '9000077777');
    await tester.enterText(find.byKey(const Key('attendant-setup-code')), '24681357');
    await tester.enterText(find.byKey(const Key('attendant-new-passcode')), '4827');
    await tester.enterText(find.byKey(const Key('attendant-confirm-passcode')), '4827');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Register and sign in'));
    await waitFor(tester, find.text('ITest Route'));

    // Their own route, and none of the admin transport screens.
    expect(find.text('Vehicles'), findsNothing);
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
