import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/flow.dart';

/// Super Admin: login -> schools -> payment -> receipt (CLAUDE.md §16), end
/// to end against a real backend. A payment is recorded from the Payments
/// page, where the school is picked; the receipt is an on-screen dialog. See
/// support/flow.dart for the fixtures.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets("a super admin records a school's payment and opens its receipt", (tester) async {
    await startApp(tester);
    await login(tester, email: 'itest-root@example.com');

    await openPage(tester, 'Schools');
    // The list builds only the rows on screen, so a platform with many
    // schools need not show this one - the page loading is the check.
    expect(find.widgetWithText(FilledButton, 'Add School'), findsOneWidget);

    await openPage(tester, 'Payments');
    await tester.tap(find.widgetWithText(FilledButton, 'Add Payment'));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    await pickFromDropdown<int>(tester, 'School', 'Academy Integration Test School (INR)');
    await tester.enterText(find.widgetWithText(TextFormField, 'Amount'), '25000');
    await tester.enterText(find.widgetWithText(TextFormField, 'Reference number (optional)'), 'E2E-REF-1');
    // Payment type, date, mode and status keep their defaults: Setup Fee,
    // today, Bank Transfer, Paid.
    await tester.tap(find.widgetWithText(FilledButton, 'Save Payment'));
    await tester.pumpAndSettle(const Duration(seconds: 3));

    expect(find.text('Payment recorded.'), findsOneWidget);

    // Newest payment date first, then newest id: today's payment leads.
    // The actions are the table's last column, which scrolls sideways.
    await tester.ensureVisible(find.widgetWithText(TextButton, 'Receipt').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Receipt').first);
    await tester.pumpAndSettle(const Duration(seconds: 2));

    final receipt = find.byType(AlertDialog);
    expect(find.descendant(of: receipt, matching: find.text('Payment Receipt')), findsOneWidget);
    expect(find.descendant(of: receipt, matching: find.text('Academy Integration Test School')), findsOneWidget);
    expect(find.descendant(of: receipt, matching: find.text('E2E-REF-1')), findsOneWidget);
    expect(find.descendant(of: receipt, matching: find.textContaining('RCPT-')), findsOneWidget);

    await tester.tap(find.descendant(of: receipt, matching: find.byType(FilledButton)));
    await tester.pumpAndSettle(const Duration(seconds: 3));

    expect(find.text('Receipt emailed to the school admins.'), findsOneWidget);
  });
}
