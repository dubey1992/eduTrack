import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'family_app_test.dart' show pumpFamilyApp, revealOnMore;

/// "Your privacy" in the Family app (docs/mobile-apps-review.md, 4.5).
void main() {
  testWidgets('More is the way in', (tester) async {
    await pumpFamilyApp(tester, goTo: '/more');
    await revealOnMore(tester, find.byKey(const Key('family-more-privacy')));

    await tester.tap(find.byKey(const Key('family-more-privacy')));
    await tester.pumpAndSettle();

    expect(find.text('Your privacy'), findsOneWidget);
  });

  testWidgets('says who sees the number and when the bus can be followed', (tester) async {
    await pumpFamilyApp(tester, goTo: '/privacy');

    expect(find.text('Who can see your phone number'), findsOneWidget);
    expect(find.textContaining('not teachers of other classes'), findsOneWidget);
    expect(find.textContaining('only while your child\'s own trip is running'), findsOneWidget);
    expect(find.text('This app never asks for your phone\'s location.'), findsOneWidget);
  });

  testWidgets('leads to the notification choices', (tester) async {
    await pumpFamilyApp(tester, goTo: '/privacy');
    await tester.scrollUntilVisible(find.byKey(const Key('family-privacy-open-notifications')), 200);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('family-privacy-open-notifications')));
    await tester.pumpAndSettle();

    expect(find.text('Notifications'), findsWidgets);
  });
}
