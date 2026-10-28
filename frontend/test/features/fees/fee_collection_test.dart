import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/models/module_access.dart';
import 'package:edutrack_app/core/models/permission_level.dart';
import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/auth/data/models/authenticated_user.dart';
import 'package:edutrack_app/features/fees/data/fee_repository.dart';
import 'package:edutrack_app/features/fees/data/models/fee_receipt.dart';
import 'package:edutrack_app/features/fees/data/models/student_fees.dart';
import 'package:edutrack_app/features/fees/presentation/fee_receipts_screen.dart';
import 'package:edutrack_app/features/schools/data/school_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../support/fake_auth_repository.dart';
import '../../support/fake_fee_repository.dart';
import '../../support/fake_school_repository.dart';
import 'student_fees_screen_test.dart' show useDesktop, wrap;

/// Taking money (docs/fees.md, F3): recording a payment from a student's
/// statement, the receipt it produces, and the Receipts list.

Finder field(String label) => find.widgetWithText(TextFormField, label);

Finder inDialog(Finder finder) => find.descendant(of: find.byType(AlertDialog), matching: finder);

Future<void> tapText(WidgetTester tester, String text) async {
  await tester.ensureVisible(find.text(text).last);
  await tester.tap(find.text(text).last);
  await tester.pumpAndSettle();
}

/// Asha's statement, with one payment already made against it.
StudentFeeStatement withReceipt() {
  final statement = fakeStatement();
  return StudentFeeStatement(
    student: statement.student,
    academicYearId: statement.academicYearId,
    academicYearName: statement.academicYearName,
    currencyCode: statement.currencyCode,
    dues: statement.dues,
    totals: statement.totals,
    receipts: [
      ReceiptSummary(
        id: 70,
        receiptNumber: 'RCPT-2026-27-00070',
        receiptDate: DateTime(2026, 4, 9),
        amount: '2000.00',
        paymentModeLabel: 'Cash',
        isCancelled: false,
      ),
    ],
  );
}

Future<FakeFeeRepository> openStatement(WidgetTester tester, {UserRole role = UserRole.accountant}) async {
  useDesktop(tester);
  final fees = FakeFeeRepository()..statements = {7: withReceipt()};
  await tester.pumpWidget(wrap(fees, at: '/student-fees?student=7', role: role));
  await tester.pumpAndSettle();
  return fees;
}

Widget wrapReceipts(FakeFeeRepository fees, {UserRole role = UserRole.accountant}) {
  final router = GoRouter(
    initialLocation: '/fee-receipts',
    routes: [
      GoRoute(
        path: '/fee-receipts',
        builder: (context, state) => const Scaffold(body: FeeReceiptsScreen()),
      ),
      GoRoute(
        path: '/student-fees',
        builder: (context, state) => const Scaffold(body: Text('Student page')),
      ),
    ],
  );

  return ProviderScope(
    retry: (retryCount, error) => null,
    overrides: [
      feeRepositoryProvider.overrideWithValue(fees),
      schoolRepositoryProvider.overrideWithValue(FakeSchoolRepository()),
      authRepositoryProvider.overrideWithValue(
        FakeAuthRepository(
          sessionOnRestore: AuthenticatedUser(id: 9, name: 'Meena', email: 'm@example.com', role: role),
        ),
      ),
    ],
    child: MaterialApp.router(theme: AppTheme.light(), routerConfig: router),
  );
}

void main() {
  group('recording a payment', () {
    testWidgets('goes to what is owed oldest first unless installments are chosen', (tester) async {
      final fees = await openStatement(tester);

      await tapText(tester, 'Record Payment');
      expect(find.text('Record payment - Asha Rao'), findsOneWidget);

      await tester.tap(find.text('Pay everything owed'));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Record payment'));
      await tester.pumpAndSettle();

      expect(fees.payments.single['amount'], '2000.00');
      expect(fees.payments.single['allocations'], isNull);
      expect(fees.payments.single['payment_mode'], 'cash');
      // The receipt, straight away, with what to do next.
      expect(find.text('Receipt RCPT-2026-27-00070'), findsOneWidget);
      expect(find.text('Still owed'), findsOneWidget);
      expect(find.text('Paid now'), findsOneWidget);
      expect(find.text('Download PDF'), findsOneWidget);
    });

    testWidgets('choosing installments sends exactly what was ticked', (tester) async {
      final fees = await openStatement(tester);
      await tapText(tester, 'Record Payment');

      await tester.tap(find.text('Choose the installments it pays'));
      await tester.pumpAndSettle();
      await tester.tap(inDialog(find.byType(Checkbox)).first);
      await tester.pump();
      await tester.enterText(inDialog(find.widgetWithText(TextField, 'Pay')).first, '500');
      await tester.pump();
      expect(find.textContaining('Paying'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Record payment'));
      await tester.pumpAndSettle();

      final allocations = fees.payments.single['allocations']! as List<PaymentAllocation>;
      expect(allocations.single.dueId, 2);
      expect(allocations.single.amount, '500.00');
      expect(fees.payments.single['amount'], '500.00');
    });

    testWidgets('nothing to pay is refused before the server is asked', (tester) async {
      final fees = await openStatement(tester);
      await tapText(tester, 'Record Payment');

      await tester.tap(find.widgetWithText(FilledButton, 'Record payment'));
      await tester.pumpAndSettle();

      expect(find.text('Enter an amount above zero.'), findsOneWidget);
      expect(fees.payments, isEmpty);
    });

    testWidgets('a cheque needs its number', (tester) async {
      final fees = await openStatement(tester);
      await tapText(tester, 'Record Payment');

      await tester.tap(inDialog(find.byType(DropdownButtonFormField<PaymentMode>)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cheque').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pay everything owed'));
      await tester.tap(find.widgetWithText(FilledButton, 'Record payment'));
      await tester.pumpAndSettle();

      expect(find.text('Enter the cheque number.'), findsOneWidget);
      expect(fees.payments, isEmpty);

      await tester.enterText(field('Cheque number'), '004512');
      await tester.tap(find.widgetWithText(FilledButton, 'Record payment'));
      await tester.pumpAndSettle();

      expect(fees.payments.single['reference'], '004512');
      expect(fees.payments.single['payment_mode'], 'cheque');
    });

    testWidgets('what the server refuses is said in the dialog, which stays open', (tester) async {
      final fees = await openStatement(tester);
      fees.failPaymentWith = const Failure(
        code: 'VALIDATION_ERROR',
        message: 'The given data was invalid.',
        details: {
          'errors': {
            'amount': ['This is more than Asha Rao owes (INR 2,000.00). Advance payments are not taken.'],
          },
        },
      );
      await tapText(tester, 'Record Payment');

      await tester.enterText(field('Amount received'), '5000');
      await tester.tap(find.widgetWithText(FilledButton, 'Record payment'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Advance payments are not taken'), findsOneWidget);
      expect(find.text('Record payment - Asha Rao'), findsOneWidget);
    });

    testWidgets('a role that only reads is not offered it', (tester) async {
      useDesktop(tester);
      final fees = FakeFeeRepository()..statements = {7: withReceipt()};
      await tester.pumpWidget(wrap(fees, at: '/student-fees?student=7', role: UserRole.superAdmin));
      await tester.pumpAndSettle();

      expect(find.text('Record Payment'), findsNothing);
      expect(find.byTooltip('Cancel receipt'), findsNothing);
      expect(find.byTooltip('Download receipt'), findsOneWidget);
    });
  });

  group('the statement', () {
    testWidgets('lists the payments made, each with its receipt', (tester) async {
      final fees = await openStatement(tester);

      expect(find.text('Payments'), findsOneWidget);
      expect(find.text('RCPT-2026-27-00070'), findsOneWidget);

      await tester.tap(find.byTooltip('Download receipt'));
      await tester.pumpAndSettle();
      expect(fees.pdfRequests, [70]);
    });
  });

  group('the Receipts list', () {
    testWidgets('shows every receipt, and filters reach the server', (tester) async {
      useDesktop(tester);
      final fees = FakeFeeRepository()..receiptRows = [fakeReceipt(), fakeReceipt(id: 71, mode: PaymentMode.upi)];
      await tester.pumpWidget(wrapReceipts(fees));
      await tester.pumpAndSettle();

      expect(find.text('RCPT-2026-27-00070'), findsOneWidget);
      expect(find.text('RCPT-2026-27-00071'), findsOneWidget);

      await tester.tap(find.text('Cancelled').first);
      await tester.pumpAndSettle();
      expect(fees.receiptQueries.last['cancelled'], isTrue);
      expect(find.text('No receipt matches these filters.'), findsOneWidget);
    });

    testWidgets('cancelling asks why, and keeps the receipt marked cancelled', (tester) async {
      useDesktop(tester);
      final fees = FakeFeeRepository()..receiptRows = [fakeReceipt()];
      await tester.pumpWidget(wrapReceipts(fees));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Cancel receipt'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Cancel receipt'));
      await tester.pumpAndSettle();
      expect(find.text('Say why the receipt is being cancelled.'), findsOneWidget);
      expect(fees.cancelled, isEmpty);

      await tester.enterText(find.widgetWithText(TextFormField, 'Reason'), 'Cheque bounced');
      await tester.tap(find.widgetWithText(FilledButton, 'Cancel receipt'));
      await tester.pumpAndSettle();

      expect(fees.cancelled.single, (id: 70, reason: 'Cheque bounced'));
      expect(find.text('Receipt RCPT-2026-27-00070 cancelled. What it paid is owed again.'), findsOneWidget);
      expect(find.text('Cancelled: Cheque bounced'), findsOneWidget);
    });

    testWidgets('emailing to a guardian with no address says so', (tester) async {
      useDesktop(tester);
      final fees = FakeFeeRepository()
        ..receiptRows = [fakeReceipt()]
        ..failEmailWith = const Failure(
          code: 'VALIDATION_ERROR',
          message: 'The given data was invalid.',
          details: {
            'errors': {
              'guardian_email': ['This student has no guardian email address.'],
            },
          },
        );
      await tester.pumpWidget(wrapReceipts(fees));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Email to guardian'));
      await tester.pumpAndSettle();

      expect(find.text('This student has no guardian email address.'), findsOneWidget);
    });

    testWidgets('nothing collected yet says where payments are recorded', (tester) async {
      useDesktop(tester);
      await tester.pumpWidget(wrapReceipts(FakeFeeRepository()));
      await tester.pumpAndSettle();

      expect(find.textContaining('Payments are recorded from a student'), findsOneWidget);
    });

    testWidgets('a super admin chooses a school first', (tester) async {
      useDesktop(tester);
      final fees = FakeFeeRepository()..receiptRows = [fakeReceipt()];
      await tester.pumpWidget(wrapReceipts(fees, role: UserRole.superAdmin));
      await tester.pumpAndSettle();

      expect(find.text('Choose a school to see its receipts.'), findsOneWidget);
    });
  });

  test('a payment mode reads back from the server unchanged', () {
    for (final mode in PaymentMode.values) {
      expect(PaymentMode.fromWire(mode.wire), mode);
    }
    expect(PaymentMode.cheque.needsReference, isTrue);
    expect(PaymentMode.cash.needsReference, isFalse);
  });

  // The matrix decides who may take money; widening it is how a school would
  // let a front-desk clerk do it.
  test('the default matrix gives fees only to the admin and the accountant', () {
    expect(ModuleAccess.defaultLevel(AppModules.fees, UserRole.accountant), PermissionLevel.manage);
    expect(ModuleAccess.defaultLevel(AppModules.fees, UserRole.teacher), PermissionLevel.none);
  });
}
