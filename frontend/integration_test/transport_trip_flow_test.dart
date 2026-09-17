import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/flow.dart';

/// Transport: login -> trip -> board/drop -> end (CLAUDE.md §16), end to end
/// against a real backend. The fixture route has a bus, a driver, one stop
/// and two riders; today has to be a working day at the school. See
/// support/flow.dart.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a transport manager runs a pickup: one child boards and is dropped, one is absent', (tester) async {
    await startApp(tester);
    await login(tester, email: 'itest-transport@example.com');

    await openPage(tester, 'Trips');
    await pickFromDropdown<int>(tester, 'Route', 'ITest Bus - ITest Route');

    expect(find.text('No trip in progress for this route.'), findsOneWidget);

    // Set explicitly: the default follows the school's clock.
    await tester.tap(find.text('Pickup').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Start Trip'));
    await tester.pumpAndSettle(const Duration(seconds: 3));

    expect(find.text('Pickup trip started.'), findsOneWidget);
    // On the live trip and again in its Trip History row.
    expect(statusBadge('En Route'), findsWidgets);
    expect(find.widgetWithText(FilledButton, 'Board'), findsNWidgets(2));

    // The first rider boards...
    await tester.tap(find.widgetWithText(FilledButton, 'Board').first);
    await tester.pumpAndSettle(const Duration(seconds: 3));
    expect(find.textContaining(' boarded.'), findsOneWidget);

    // ...the other never turns up...
    await tester.tap(find.widgetWithText(TextButton, 'Absent'));
    await tester.pumpAndSettle(const Duration(seconds: 3));
    expect(find.textContaining(' absent.'), findsOneWidget);

    // ...and the first is dropped at school.
    await tester.tap(find.widgetWithText(FilledButton, 'Drop'));
    await tester.pumpAndSettle(const Duration(seconds: 3));
    expect(find.textContaining(' dropped.'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'End Trip'));
    await tester.pumpAndSettle();
    expect(find.text('End trip?'), findsOneWidget);
    // The dialog's button carries the same text as the one behind it.
    await tester.tap(find.widgetWithText(FilledButton, 'End Trip').last);
    await tester.pumpAndSettle(const Duration(seconds: 3));

    expect(find.text('Trip completed.'), findsOneWidget);
    expect(find.text('Last trip completed.'), findsOneWidget);
  });
}
