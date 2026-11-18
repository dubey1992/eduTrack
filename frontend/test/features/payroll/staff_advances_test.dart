import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/features/payroll/data/models/staff_advance.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_payroll_repository.dart';
import 'payroll_screen_test.dart' show useDesktop, wrap;

/// Advances paid to staff, recovered from payslips (docs/dashboard.md, D4).

Future<void> _openAdvances(
  WidgetTester tester,
  FakePayrollRepository fake, {
  UserRole role = UserRole.accountant,
}) async {
  useDesktop(tester);
  await tester.pumpWidget(wrap(fake, role: role));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Advances'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows how far each advance is repaid, and what a draft still holds', (tester) async {
    final fake = FakePayrollRepository(employees: [fakeEmployee()])
      ..advancesStored.add(fakeAdvance(recovered: '1000.00', pending: '1000.00'));
    await _openAdvances(tester, fake);

    expect(find.text('Rahul Verma · TCH-1'), findsOneWidget);
    expect(find.textContaining('recovered,'), findsOneWidget);
    expect(find.textContaining('a month from October 2026'), findsOneWidget);
    expect(find.textContaining('more on a draft payroll, counted once it is finalized'), findsOneWidget);
    // Partly recovered: it stays, so it cannot be cancelled.
    expect(find.byKey(const Key('advance-cancel-1')), findsNothing);
  });

  testWidgets('the filter asks the server for the right advances', (tester) async {
    final fake = FakePayrollRepository(employees: [fakeEmployee()])
      ..advancesStored.addAll([fakeAdvance(), fakeAdvance(id: 2, status: 'repaid', recovered: '3000.00')]);
    await _openAdvances(tester, fake);

    expect(find.byKey(const Key('advance-1')), findsOneWidget);
    expect(find.byKey(const Key('advance-2')), findsNothing);

    await tester.tap(find.byKey(const Key('advance-filter-repaid')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('advance-1')), findsNothing);
    expect(find.byKey(const Key('advance-2')), findsOneWidget);
  });

  testWidgets('recording one sends what was typed and lists it', (tester) async {
    final fake = FakePayrollRepository(employees: [fakeEmployee()]);
    await _openAdvances(tester, fake);
    expect(find.text('No advances here.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('advance-record')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('advance-employee')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rahul Verma · TCH-1').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('advance-amount')), '3000');
    await tester.enterText(find.byKey(const Key('advance-monthly')), '1000');
    await tester.enterText(find.byKey(const Key('advance-reason')), 'Medical emergency');
    await tester.tap(find.byKey(const Key('advance-save')));
    await tester.pumpAndSettle();

    expect(fake.lastAdvance, containsPair('staff_profile_id', 1));
    expect(fake.lastAdvance, containsPair('amount', '3000'));
    expect(fake.lastAdvance, containsPair('monthly_recovery', '1000'));
    expect(fake.lastAdvance, containsPair('payment_mode', 'cash'));
    expect(find.textContaining('Advance recorded'), findsOneWidget);
    expect(find.byKey(const Key('advance-1')), findsOneWidget);
  });

  testWidgets('the form says what is missing before anything is sent', (tester) async {
    final fake = FakePayrollRepository(employees: [fakeEmployee()]);
    await _openAdvances(tester, fake);

    await tester.tap(find.byKey(const Key('advance-record')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('advance-amount')), '1000');
    await tester.enterText(find.byKey(const Key('advance-monthly')), '2000');
    await tester.tap(find.byKey(const Key('advance-save')));
    await tester.pumpAndSettle();

    expect(find.text('Choose the employee.'), findsOneWidget);
    expect(find.text('Not more than the advance.'), findsOneWidget);
    expect(find.text('Say what the advance is for.'), findsOneWidget);
    expect(fake.lastAdvance, isNull);
  });

  testWidgets("the server's refusal is shown and the dialog stays open", (tester) async {
    final fake = FakePayrollRepository(
      employees: [fakeEmployee()],
      failWith: {
        'recordAdvance': const Failure(
          code: 'VALIDATION_ERROR',
          message: 'An advance that has not been paid yet cannot be recorded.',
        ),
      },
    );
    await _openAdvances(tester, fake);

    await tester.tap(find.byKey(const Key('advance-record')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('advance-employee')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rahul Verma · TCH-1').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('advance-amount')), '3000');
    await tester.enterText(find.byKey(const Key('advance-monthly')), '1000');
    await tester.enterText(find.byKey(const Key('advance-reason')), 'Medical emergency');
    await tester.tap(find.byKey(const Key('advance-save')));
    await tester.pumpAndSettle();

    expect(find.text('An advance that has not been paid yet cannot be recorded.'), findsOneWidget);
    expect(find.text('Record an advance'), findsOneWidget);
  });

  testWidgets('an untouched advance can be cancelled, with a reason', (tester) async {
    final fake = FakePayrollRepository(employees: [fakeEmployee()])..advancesStored.add(fakeAdvance());
    await _openAdvances(tester, fake);

    await tester.tap(find.byKey(const Key('advance-cancel-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Cancel advance'));
    await tester.pumpAndSettle();
    expect(find.text('Say why it is being cancelled.'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('advance-cancel-reason')), 'Entered twice');
    await tester.tap(find.widgetWithText(FilledButton, 'Cancel advance'));
    await tester.pumpAndSettle();

    expect(fake.calls, contains('cancelAdvance'));
    expect(fake.advancesStored.single.status, StaffAdvanceStatus.cancelled);
    expect(find.text('Advance cancelled.'), findsOneWidget);
  });

  testWidgets('a Super Admin reads advances but records and cancels nothing', (tester) async {
    final fake = FakePayrollRepository(employees: [fakeEmployee()])..advancesStored.add(fakeAdvance());
    await _openAdvances(tester, fake, role: UserRole.superAdmin);

    expect(find.byKey(const Key('advance-1')), findsOneWidget);
    expect(find.byKey(const Key('advance-record')), findsNothing);
    expect(find.byKey(const Key('advance-cancel-1')), findsNothing);
  });

  test('progress is what finalized payslips took back, of the whole', () {
    expect(fakeAdvance(recovered: '1500.00').progress, 0.5);
    expect(fakeAdvance(amount: '0.00').progress, 0);
  });
}
