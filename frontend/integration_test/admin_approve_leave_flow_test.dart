import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/flow.dart';

/// Admin: login -> leave -> approve (CLAUDE.md §16), end to end against a
/// real backend. The fixtures leave one pending request from the teacher, two
/// weeks ahead. See support/flow.dart.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets("a school admin approves a teacher's pending leave", (tester) async {
    await startApp(tester);
    await login(tester, email: 'itest-admin@example.com');

    await openPage(tester, 'Staff Leave');

    expect(find.text('Integration test: waiting for the admin'), findsOneWidget);
    expect(statusBadge('Pending'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Approve'));
    await tester.pumpAndSettle(const Duration(seconds: 3));

    expect(find.text('Leave request approved.'), findsOneWidget);
    expect(statusBadge('Approved'), findsOneWidget);
    expect(statusBadge('Pending'), findsNothing);

    // ---- The decision is in the audit trail (Phase 21) ----
    await openPage(tester, 'Audit Log');
    await tester.pumpAndSettle(const Duration(seconds: 2));

    expect(find.text('Staff leave approved'), findsWidgets);
  });
}
