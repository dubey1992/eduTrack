import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'family_app_test.dart' show pumpFamilyApp;

/// "How is this worked out?" under the Family app's figures
/// (docs/mobile-apps-review.md, 4.1): closed at first, one tap to read it.
void main() {
  Future<void> openWhy(WidgetTester tester, String key) async {
    final why = find.byKey(Key('family-why-$key'));
    await tester.scrollUntilVisible(why, 200, scrollable: find.byType(Scrollable).first);
    expect(
      find.descendant(of: why, matching: find.textContaining('out of')),
      findsNothing,
      reason: 'closed at first',
    );
    await tester.tap(find.descendant(of: why, matching: find.text('How is this worked out?')));
    await tester.pumpAndSettle();
  }

  testWidgets('attendance: present out of the days the register was marked', (tester) async {
    await pumpFamilyApp(tester, goTo: '/attendance');
    await openWhy(tester, 'attendance');

    expect(find.textContaining('Days present out of the days the class register was marked'), findsOneWidget);
  });

  testWidgets('fees: what is left and what is overdue', (tester) async {
    await pumpFamilyApp(tester, goTo: '/fees');
    await openWhy(tester, 'fees');

    expect(find.textContaining('less any discount, less what the school has recorded as paid'), findsOneWidget);
  });

  testWidgets('results: the average of the published tests, missed tests left out', (tester) async {
    await pumpFamilyApp(tester, goTo: '/results');
    await openWhy(tester, 'results');

    expect(find.textContaining('A test the child missed is left out'), findsOneWidget);
  });

  testWidgets('a second tap closes it again', (tester) async {
    await pumpFamilyApp(tester, goTo: '/fees');
    await openWhy(tester, 'fees');
    await tester.tap(find.text('How is this worked out?'));
    await tester.pumpAndSettle();

    expect(find.textContaining('less any discount'), findsNothing);
  });
}
