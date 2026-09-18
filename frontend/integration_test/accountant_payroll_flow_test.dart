import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/intl.dart';

import 'support/flow.dart';

/// Payroll (Phase 19), end to end against the Python backend: an accountant
/// sets a teacher's salary, runs this month's payroll, finalizes it and pays
/// the teacher, who then finds the payslip under My Payslips. See
/// docs/payroll.md, and support/flow.dart for the fixtures.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets("an accountant pays a teacher and the teacher reads the payslip", (tester) async {
    final month = DateFormat('MMMM yyyy').format(DateTime.now());

    await startApp(tester);

    // ---- The accountant sets the teacher's salary ----
    await login(tester, email: 'itest-accountant@example.com');
    await openPage(tester, 'Payroll');

    await tester.tap(find.text('Salaries'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Search name / employee ID'), 'Tara');
    await tester.pumpAndSettle(const Duration(seconds: 2));

    await tester.tap(find.widgetWithText(TextButton, 'Set Salary'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Basic salary (monthly, INR)'), '30000');
    await tester.tap(find.text('Add earning'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Name'), 'HRA');
    await tester.enterText(find.widgetWithText(TextFormField, 'Amount'), '6000');
    await tester.tap(find.widgetWithText(FilledButton, 'Save Salary'));
    await tester.pumpAndSettle(const Duration(seconds: 3));

    expect(find.text('Salary saved for Tara Teacher.'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Edit Salary'), findsOneWidget);

    // ---- Runs this month's payroll ----
    await tester.tap(find.text('Runs'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Run Payroll'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Generate Draft'));
    await tester.pumpAndSettle(const Duration(seconds: 3));

    expect(find.text('Draft payroll generated for $month.'), findsOneWidget);
    expect(find.text('Tara Teacher\nITEST-TEACHER'), findsOneWidget);
    // The others have no salary, and the draft says so rather than dropping them.
    expect(find.textContaining('employees are not on this run'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Finalize'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Finalize').last);
    await tester.pumpAndSettle(const Duration(seconds: 3));

    expect(find.text('$month payroll finalized.'), findsOneWidget);

    // ---- Pays the teacher ----
    await tester.tap(find.widgetWithText(TextButton, 'View'));
    await tester.pumpAndSettle(const Duration(seconds: 2));
    await tester.tap(find.widgetWithText(FilledButton, 'Mark Paid'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Reference (optional)'), 'E2E-NEFT');
    await tester.tap(find.widgetWithText(FilledButton, 'Mark Paid').last);
    await tester.pumpAndSettle(const Duration(seconds: 3));

    expect(find.text('Payslip marked paid.'), findsOneWidget);
    expect(find.textContaining('(E2E-NEFT)'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Close'));
    await tester.pumpAndSettle();

    // ---- The finalized month is in the payroll summary (Phase 20) ----
    await openPage(tester, 'Reports');
    await tester.tap(find.widgetWithText(ChoiceChip, 'Payroll summary'));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    expect(find.text('ITEST-TEACHER'), findsOneWidget);
    expect(find.text('Net pay (INR)'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilterChip, 'Compare with previous period'));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    expect(find.text('Previous period'), findsOneWidget);
    // Nothing was paid before this month, so the teacher's line is new.
    expect(find.text('(new)'), findsOneWidget);

    await logout(tester);

    // ---- The teacher reads their payslip ----
    await login(tester, email: 'itest-teacher@example.com');
    await openPage(tester, 'My Payslips');

    expect(find.text(month), findsOneWidget);
    await tester.tap(find.text(month));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    expect(find.text('Payslip · $month'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Download PDF'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Mark Paid'), findsNothing);
  });
}
