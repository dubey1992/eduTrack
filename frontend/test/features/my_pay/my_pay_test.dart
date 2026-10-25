import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/models/module_access.dart';
import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/network/paginated_response.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/core/utils/currency_formatter.dart';
import 'package:edutrack_app/core/widgets/teacher_frame.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/my_pay/data/my_pay_repository.dart';
import 'package:edutrack_app/features/my_pay/presentation/my_payslip_detail_screen.dart';
import 'package:edutrack_app/features/my_pay/presentation/my_payslips_phone_screen.dart';
import 'package:edutrack_app/features/payments/data/models/payment.dart';
import 'package:edutrack_app/features/payroll/data/models/payroll.dart';
import 'package:edutrack_app/features/payroll/data/payroll_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../support/fake_auth_repository.dart';
import '../../support/session_users.dart';

/// "My pay" in the School365ai app (docs/teacher-app.md, T4).
Payslip payslip({int id = 7, String period = 'September 2026', bool paid = true, String shortfall = '0.00'}) {
  return Payslip(
    id: id,
    payrollRunId: 1,
    periodLabel: period,
    runStatus: paid ? PayrollRunStatus.paid : PayrollRunStatus.finalized,
    schoolName: 'Greenfield Public School',
    staffProfileId: 1,
    employeeName: 'Meera Joshi',
    employeeCode: 'GPS-TCH-01',
    currencyCode: 'INR',
    workingDays: 22,
    paidDays: 21.5,
    absentDays: 0,
    halfDays: 1,
    unmarkedDays: 0,
    grossEarnings: '36000.00',
    totalDeductions: '1800.00',
    netPay: '34200.00',
    shortfall: shortfall,
    status: paid ? PayslipStatus.paid : PayslipStatus.unpaid,
    paidOn: paid ? '2026-10-01' : null,
    paymentMode: paid ? PaymentMode.bankTransfer : null,
    lines: const [
      PayslipLine(id: 1, type: PayComponentType.earning, name: 'Basic', amount: '30000.00', isAdjustment: false),
      PayslipLine(id: 2, type: PayComponentType.earning, name: 'HRA', amount: '6000.00', isAdjustment: false),
      PayslipLine(id: 3, type: PayComponentType.deduction, name: 'PF', amount: '1800.00', isAdjustment: false),
    ],
  );
}

class FakeMyPayRepository implements MyPayRepository {
  FakeMyPayRepository({this.slips = const [], this.failEmailWith, this.failListWith});

  List<Payslip> slips;
  Failure? failEmailWith;
  Failure? failListWith;
  int? emailedId;

  @override
  Future<PaginatedResponse<Payslip>> myPayslips({required int page, required int perPage}) async {
    if (failListWith != null) throw failListWith!;
    return PaginatedResponse(items: slips, currentPage: 1, lastPage: 1, total: slips.length, perPage: perPage);
  }

  @override
  Future<Payslip> payslip(int payslipId) async => slips.firstWhere((slip) => slip.id == payslipId);

  @override
  Future<String> emailMe(int payslipId) async {
    if (failEmailWith != null) throw failEmailWith!;
    emailedId = payslipId;
    return 'Your payslip for September 2026 is on its way to meera@school.test.';
  }
}

void main() {
  Widget app(FakeMyPayRepository repository, {bool payrollOn = true, String start = '/pay'}) {
    final router = GoRouter(
      initialLocation: start,
      routes: [
        GoRoute(
          path: '/pay',
          builder: (context, state) => const TeacherFrame(place: TeacherPlace.pay, child: MyPayslipsPhoneScreen()),
        ),
        GoRoute(
          path: '/pay/:id',
          builder: (context, state) => MyPayslipDetailScreen(payslipId: int.parse(state.pathParameters['id']!)),
        ),
        GoRoute(
          path: '/today',
          builder: (context, state) => const Scaffold(body: Text('Today')),
        ),
        GoRoute(
          path: '/profile',
          builder: (context, state) => const Scaffold(body: Text('Me')),
        ),
      ],
    );

    return ProviderScope(
      overrides: [
        myPayRepositoryProvider.overrideWithValue(repository),
        authRepositoryProvider.overrideWithValue(
          FakeAuthRepository(
            sessionOnRestore: sessionUser(
              UserRole.teacher,
              name: 'Meera Joshi',
              modules: payrollOn ? const {} : const {AppModules.payroll: false},
            ),
          ),
        ),
      ],
      child: MaterialApp.router(theme: AppTheme.teacherLight(), routerConfig: router),
    );
  }

  Future<void> open(WidgetTester tester, FakeMyPayRepository repository, {bool payrollOn = true}) async {
    tester.view.physicalSize = const Size(412, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(app(repository, payrollOn: payrollOn));
    await tester.pumpAndSettle();
  }

  group('the list', () {
    testWidgets("one card a month, net pay in the school's currency, paid or not", (tester) async {
      await open(
        tester,
        FakeMyPayRepository(
          slips: [
            payslip(id: 8, period: 'October 2026', paid: false),
            payslip(id: 7),
          ],
        ),
      );

      expect(find.text('October 2026'), findsOneWidget);
      expect(find.text('September 2026'), findsOneWidget);
      expect(find.text(formatCurrency(34200, 'INR')), findsNWidgets(2));
      expect(find.text('Not paid yet'), findsOneWidget);
      expect(find.text('Paid'), findsOneWidget);
    });

    testWidgets('with no payslips yet, it says when one will appear', (tester) async {
      await open(tester, FakeMyPayRepository());

      expect(find.byKey(const Key('my-pay-empty')), findsOneWidget);
    });

    testWidgets('a failure offers a retry', (tester) async {
      final repository = FakeMyPayRepository(failListWith: Failure.network());
      await open(tester, repository);

      repository.failListWith = null;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('my-pay-empty')), findsOneWidget);
    });

    testWidgets('the Pay tab is there where the school runs payroll', (tester) async {
      await open(tester, FakeMyPayRepository());

      expect(find.byKey(const Key('teacher-nav-pay')), findsOneWidget);
    });

    testWidgets('and gone where it does not', (tester) async {
      await open(tester, FakeMyPayRepository(), payrollOn: false);

      expect(find.byKey(const Key('teacher-nav-pay')), findsNothing);
    });
  });

  group('one payslip', () {
    Future<void> openSlip(WidgetTester tester, FakeMyPayRepository repository) async {
      await open(tester, repository);
      await tester.tap(find.byKey(const Key('my-pay-7')));
      await tester.pumpAndSettle();
    }

    testWidgets('shows the net pay, how it was paid, the days, and every line', (tester) async {
      await openSlip(tester, FakeMyPayRepository(slips: [payslip()]));

      expect(find.byType(MyPayslipDetailScreen), findsOneWidget);
      expect(find.text(formatCurrency(34200, 'INR')), findsOneWidget);
      expect(find.text('Paid on 10/01/2026 by Bank Transfer'), findsOneWidget);
      expect(find.text('21.5'), findsOneWidget, reason: 'paid days, half a day kept');
      expect(find.text('Half days'), findsOneWidget);
      expect(find.text('Absent'), findsNothing, reason: 'a zero is not worth a row');
      expect(
        find.descendant(
          of: find.byKey(const Key('my-payslip-earnings')),
          matching: find.text(formatCurrency(6000, 'INR')),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: find.byKey(const Key('my-payslip-deductions')), matching: find.text('PF')),
        findsOneWidget,
      );
      expect(find.text('Total earnings'), findsOneWidget);
    });

    testWidgets('a month cut short by unpaid days says by how much', (tester) async {
      await openSlip(tester, FakeMyPayRepository(slips: [payslip(shortfall: '1363.64')]));

      expect(find.text('Unpaid days reduced this month by ${formatCurrency(1363.64, 'INR')}.'), findsOneWidget);
    });

    testWidgets('Email me the PDF sends it and says where', (tester) async {
      final repository = FakeMyPayRepository(slips: [payslip()]);
      await openSlip(tester, repository);

      await tester.ensureVisible(find.byKey(const Key('my-payslip-email')));
      await tester.tap(find.byKey(const Key('my-payslip-email')));
      await tester.pumpAndSettle();

      expect(repository.emailedId, 7);
      expect(find.textContaining('is on its way to meera@school.test'), findsOneWidget);
    });

    for (final (code, message) in [
      ('NO_EMAIL', 'Your account has no email address to send it to. Ask the office to add one.'),
      ('EMAILED_RECENTLY', 'This payslip was emailed to you a moment ago. Check your inbox and spam folder.'),
    ]) {
      testWidgets('a refusal ($code) is said on the screen', (tester) async {
        final repository = FakeMyPayRepository(
          slips: [payslip()],
          failEmailWith: Failure(code: code, message: message),
        );
        await openSlip(tester, repository);

        await tester.ensureVisible(find.byKey(const Key('my-payslip-email')));
        await tester.tap(find.byKey(const Key('my-payslip-email')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('my-payslip-email-problem')), findsOneWidget);
        expect(find.text(message), findsOneWidget);
      });
    }
  });

  test('the repository is the payroll API underneath, not a second client', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(myPayRepositoryProvider), isA<MyPayRepository>());
    expect(container.read(payrollApiProvider), isA<PayrollApi>());
  });
}
