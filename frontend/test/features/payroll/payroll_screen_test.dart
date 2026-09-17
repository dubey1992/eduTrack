import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/auth/data/models/authenticated_user.dart';
import 'package:edutrack_app/features/payroll/data/models/payroll.dart';
import 'package:edutrack_app/features/payroll/data/payroll_repository.dart';
import 'package:edutrack_app/features/payroll/presentation/my_payslips_screen.dart';
import 'package:edutrack_app/features/payroll/presentation/payroll_screen.dart';
import 'package:edutrack_app/features/schools/data/school_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_auth_repository.dart';
import '../../support/fake_payroll_repository.dart';
import '../../support/fake_school_repository.dart';

AuthenticatedUser actor(UserRole role) =>
    AuthenticatedUser(id: 9, name: 'Meena Iyer', email: 'meena@example.com', role: role);

Widget wrap(FakePayrollRepository fake, {UserRole role = UserRole.accountant, Widget screen = const PayrollScreen()}) {
  return ProviderScope(
    retry: (retryCount, error) => null,
    overrides: [
      payrollRepositoryProvider.overrideWithValue(fake),
      schoolRepositoryProvider.overrideWithValue(FakeSchoolRepository()),
      authRepositoryProvider.overrideWithValue(FakeAuthRepository(sessionOnRestore: actor(role))),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(body: screen),
    ),
  );
}

void useDesktop(WidgetTester tester) {
  tester.view.physicalSize = const Size(1500, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// A draft for September 2026 with one payslip, already in the fake.
Future<FakePayrollRepository> withDraft({List<EmployeeSalary>? employees}) async {
  final fake = FakePayrollRepository(employees: employees);
  await fake.generate(year: 2026, month: 9);
  fake.calls.clear();

  return fake;
}

Future<void> openFirstRun(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(TextButton, 'Open'));
  await tester.pumpAndSettle();
}

// formatCurrency puts a non-breaking space after the code, so a figure never
// wraps away from its currency.
void main() {
  group('who sees what', () {
    testWidgets('an accountant can run payroll and edit salaries', (tester) async {
      useDesktop(tester);
      await tester.pumpWidget(wrap(FakePayrollRepository(employees: [fakeEmployee()])));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(FilledButton, 'Run Payroll'), findsOneWidget);
      expect(find.text('No payroll has been run yet.'), findsOneWidget);

      await tester.tap(find.text('Salaries'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextButton, 'Set Salary'), findsOneWidget);
    });

    testWidgets('a super admin reads payroll and is offered nothing to change', (tester) async {
      useDesktop(tester);
      final fake = await withDraft();
      await tester.pumpWidget(wrap(fake, role: UserRole.superAdmin));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(FilledButton, 'Run Payroll'), findsNothing);

      await openFirstRun(tester);
      expect(find.text('Regenerate'), findsNothing);
      expect(find.text('Finalize'), findsNothing);
      expect(find.text('Delete Draft'), findsNothing);

      await tester.tap(find.byTooltip('Back to runs'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Salaries'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextButton, 'View'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Edit Salary'), findsNothing);
    });
  });

  group('a run', () {
    testWidgets('generating a draft opens it', (tester) async {
      useDesktop(tester);
      final fake = FakePayrollRepository();
      await tester.pumpWidget(wrap(fake));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Run Payroll'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Generate Draft'));
      await tester.pumpAndSettle();

      expect(fake.calls, contains('generate'));
      expect(find.textContaining('Draft payroll generated for'), findsOneWidget);
      expect(find.textContaining('Payroll · '), findsOneWidget);
      expect(find.text('Rahul Verma\nTCH-1'), findsOneWidget);
    });

    testWidgets('a draft names who is missing a salary', (tester) async {
      useDesktop(tester);
      final fake = await withDraft(
        employees: [
          fakeEmployee(basic: '30000'),
          fakeEmployee(id: 2, name: 'Asha Rao', employeeId: 'STF-1'),
        ],
      );
      await tester.pumpWidget(wrap(fake));
      await tester.pumpAndSettle();
      await openFirstRun(tester);

      expect(find.text('1 employees are not on this run'), findsOneWidget);
      expect(find.text('Asha Rao (STF-1): No salary has been set.'), findsOneWidget);
    });

    testWidgets('finalizing asks first, then paying everyone settles the run', (tester) async {
      useDesktop(tester);
      final fake = await withDraft();
      await tester.pumpWidget(wrap(fake));
      await tester.pumpAndSettle();
      await openFirstRun(tester);

      await tester.tap(find.widgetWithText(FilledButton, 'Finalize'));
      await tester.pumpAndSettle();
      expect(find.text('Finalize September 2026?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Finalize').last);
      await tester.pumpAndSettle();

      expect(fake.calls, contains('finalize'));
      expect(find.text('September 2026 payroll finalized.'), findsOneWidget);
      expect(find.text('Regenerate'), findsNothing);

      await tester.tap(find.widgetWithText(FilledButton, 'Mark All Paid'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Mark All Paid').last);
      await tester.pumpAndSettle();

      expect(fake.calls, contains('payRun'));
      expect(find.text('Payslips marked paid.'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Mark All Paid'), findsNothing);
    });

    testWidgets("a refusal shows the server's reason and changes nothing", (tester) async {
      useDesktop(tester);
      final fake = FakePayrollRepository(
        failWith: {'finalize': const Failure(code: 'PAYROLL_RUN_EMPTY', message: 'There are no payslips to finalize.')},
      );
      await fake.generate(year: 2026, month: 9);
      await tester.pumpWidget(wrap(fake));
      await tester.pumpAndSettle();
      await openFirstRun(tester);

      await tester.tap(find.widgetWithText(FilledButton, 'Finalize'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Finalize').last);
      await tester.pumpAndSettle();

      expect(find.text('There are no payslips to finalize.'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Finalize'), findsOneWidget);
    });

    testWidgets('a draft can be deleted after confirming', (tester) async {
      useDesktop(tester);
      final fake = await withDraft();
      await tester.pumpWidget(wrap(fake));
      await tester.pumpAndSettle();
      await openFirstRun(tester);

      await tester.tap(find.text('Delete Draft'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete Draft'));
      await tester.pumpAndSettle();

      expect(fake.calls, contains('deleteRun'));
      expect(find.text('No payroll has been run yet.'), findsOneWidget);
    });
  });

  group('a payslip', () {
    Future<void> openPayslip(WidgetTester tester) async {
      await openFirstRun(tester);
      await tester.tap(find.widgetWithText(TextButton, 'View'));
      await tester.pumpAndSettle();
    }

    testWidgets('an adjustment is added to a draft with its reason, and can be removed', (tester) async {
      useDesktop(tester);
      final fake = await withDraft();
      await tester.pumpWidget(wrap(fake));
      await tester.pumpAndSettle();
      await openPayslip(tester);

      expect(find.text('INR 30,000.00'), findsWidgets);

      await tester.tap(find.widgetWithText(FilledButton, 'Add Adjustment'));
      await tester.pumpAndSettle();
      // The reason is required - it is printed on the payslip.
      await tester.enterText(find.widgetWithText(TextFormField, 'Name'), 'Exam duty');
      await tester.enterText(find.widgetWithText(TextFormField, 'Amount'), '1500');
      await tester.tap(find.widgetWithText(FilledButton, 'Add Adjustment').last);
      await tester.pumpAndSettle();
      expect(find.text('Say why - it goes on the payslip'), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextFormField, 'Reason'), 'Board exams');
      await tester.tap(find.widgetWithText(FilledButton, 'Add Adjustment').last);
      await tester.pumpAndSettle();

      expect(find.text('Adjustment added.'), findsOneWidget);
      expect(find.text('Adjustment - Board exams'), findsOneWidget);
      expect(find.text('INR 31,500.00'), findsWidgets);

      await tester.tap(find.byTooltip('Remove adjustment'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
      await tester.pumpAndSettle();

      expect(find.text('Adjustment - Board exams'), findsNothing);
      expect(fake.calls, containsAll(['addAdjustment', 'removeAdjustment']));
    });

    testWidgets('a finalized payslip is paid and emailed, not adjusted', (tester) async {
      useDesktop(tester);
      final fake = await withDraft();
      await fake.finalize(1);
      await tester.pumpWidget(wrap(fake));
      await tester.pumpAndSettle();
      await openPayslip(tester);

      expect(find.widgetWithText(FilledButton, 'Add Adjustment'), findsNothing);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Email Payslip'));
      await tester.pumpAndSettle();
      expect(find.text('Payslip emailed to the employee.'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Mark Paid'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextFormField, 'Reference (optional)'), 'NEFT-1');
      await tester.tap(find.widgetWithText(FilledButton, 'Mark Paid').last);
      await tester.pumpAndSettle();

      expect(find.text('Payslip marked paid.'), findsOneWidget);
      expect(find.textContaining('(NEFT-1)'), findsOneWidget);
    });
  });

  group('salaries', () {
    Future<void> openSalaries(WidgetTester tester) async {
      await tester.tap(find.text('Salaries'));
      await tester.pumpAndSettle();
    }

    testWidgets('a salary is set with components and the totals follow', (tester) async {
      useDesktop(tester);
      final fake = FakePayrollRepository(employees: [fakeEmployee()]);
      await tester.pumpWidget(wrap(fake));
      await tester.pumpAndSettle();
      await openSalaries(tester);

      await tester.tap(find.widgetWithText(TextButton, 'Set Salary'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Save Salary'));
      await tester.pumpAndSettle();
      expect(find.text('Enter the monthly basic salary'), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextFormField, 'Basic salary (monthly, INR)'), '30000');
      await tester.tap(find.text('Add earning'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextFormField, 'Name').first, 'HRA');
      await tester.enterText(find.widgetWithText(TextFormField, 'Amount').first, '6000');
      await tester.tap(find.text('Add deduction'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextFormField, 'Name').last, 'PF');
      await tester.enterText(find.widgetWithText(TextFormField, 'Amount').last, '1800');
      await tester.pumpAndSettle();

      expect(find.text('INR 36,000.00'), findsOneWidget);
      expect(find.text('INR 34,200.00'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Save Salary'));
      await tester.pumpAndSettle();

      expect(find.text('Salary saved for Rahul Verma.'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Edit Salary'), findsOneWidget);
      expect(fake.employees.single.salary!.components.map((c) => c.name), ['HRA', 'PF']);
    });

    testWidgets("the server's field errors land on the right component", (tester) async {
      useDesktop(tester);
      final fake = FakePayrollRepository(
        employees: [fakeEmployee()],
        failWith: {
          'saveSalary': const Failure(
            code: 'VALIDATION_ERROR',
            message: 'The given data was invalid.',
            details: {
              'errors': {
                'components.0.name': ['"HRA" appears twice as an earning.'],
              },
            },
          ),
        },
      );
      await tester.pumpWidget(wrap(fake));
      await tester.pumpAndSettle();
      await openSalaries(tester);
      await tester.tap(find.widgetWithText(TextButton, 'Set Salary'));
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextFormField, 'Basic salary (monthly, INR)'), '30000');
      await tester.tap(find.text('Add earning'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextFormField, 'Name'), 'HRA');
      await tester.enterText(find.widgetWithText(TextFormField, 'Amount'), '6000');
      await tester.tap(find.widgetWithText(FilledButton, 'Save Salary'));
      await tester.pumpAndSettle();

      expect(find.text('"HRA" appears twice as an earning.'), findsOneWidget);
      expect(find.byType(AlertDialog), findsOneWidget, reason: 'the dialog stays open to be fixed');
    });

    testWidgets('only employees without a salary, on request', (tester) async {
      useDesktop(tester);
      final fake = FakePayrollRepository(
        employees: [
          fakeEmployee(basic: '30000'),
          fakeEmployee(id: 2, name: 'Asha Rao', employeeId: 'STF-1'),
        ],
      );
      await tester.pumpWidget(wrap(fake));
      await tester.pumpAndSettle();
      await openSalaries(tester);

      expect(find.text('Rahul Verma\nTCH-1'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilterChip, 'No salary yet'));
      await tester.pumpAndSettle();

      expect(find.text('Rahul Verma\nTCH-1'), findsNothing);
      expect(find.text('Asha Rao\nSTF-1'), findsOneWidget);
    });
  });

  group('on a phone', () {
    void usePhone(WidgetTester tester) {
      tester.view.physicalSize = const Size(400, 860);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }

    testWidgets('runs, a run, its payslip and the salaries all fit without overflowing', (tester) async {
      usePhone(tester);
      final fake = await withDraft(
        employees: [
          fakeEmployee(basic: '30000'),
          fakeEmployee(id: 2, name: 'Asha Rao', employeeId: 'STF-1'),
        ],
      );
      await tester.pumpWidget(wrap(fake));
      await tester.pumpAndSettle();

      expect(find.text('September 2026'), findsOneWidget);
      await tester.tap(find.text('September 2026'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Payroll · September 2026'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Below the figures and the missing-salary warning: the view scrolls.
      await tester.scrollUntilVisible(find.text('Rahul Verma'), 200, scrollable: find.byType(Scrollable).first);
      await tester.ensureVisible(find.text('Rahul Verma'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rahul Verma'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.text('Payslip · September 2026'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.widgetWithText(TextButton, 'Close'));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(find.byTooltip('Back to runs'), -200, scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Back to runs'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Salaries'));
      await tester.pumpAndSettle();
      expect(find.text('Asha Rao'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Asha Rao'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add earning'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextFormField, 'Amount'), '123456789');
      await tester.pumpAndSettle();
      expect(find.text('Edit Salary'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('my payslips', () {
    testWidgets('says plainly when there are none yet', (tester) async {
      useDesktop(tester);
      await tester.pumpWidget(wrap(await withDraft(), role: UserRole.teacher, screen: const MyPayslipsScreen()));
      await tester.pumpAndSettle();

      // A draft exists, but a draft is not shown to the employee.
      expect(find.text('No payslips yet. They appear once payroll is finalized.'), findsOneWidget);
    });

    testWidgets('lists finalized payslips and opens one read-only', (tester) async {
      useDesktop(tester);
      final fake = await withDraft();
      await fake.finalize(1);
      await tester.pumpWidget(wrap(fake, role: UserRole.teacher, screen: const MyPayslipsScreen()));
      await tester.pumpAndSettle();

      expect(find.text('September 2026'), findsOneWidget);
      expect(find.textContaining('Net pay INR 30,000.00'), findsOneWidget);

      await tester.tap(find.text('September 2026'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(OutlinedButton, 'Download PDF'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Mark Paid'), findsNothing);
      expect(find.widgetWithText(OutlinedButton, 'Email Payslip'), findsNothing);
    });
  });
}
