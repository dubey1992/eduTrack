import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/features/fees/data/models/fee_credit.dart';
import 'package:edutrack_app/features/fees/data/models/student_fees.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_fee_repository.dart';
import 'fee_collection_test.dart' show field, inDialog, tapText;
import 'student_fees_screen_test.dart' show money, useDesktop, wrap;

/// A student's credit (docs/fees.md, F6): the card on the statement, its
/// history, refunds, what credit paid on each line, and a payment for more
/// than is owed.

/// Asha's statement, holding [credit] in rupees, with the May tuition paid
/// in part from credit.
StudentFeeStatement withCredit({String credit = '1500.00', String owedOnMay = '2000.00'}) {
  final statement = fakeStatement();
  return StudentFeeStatement(
    student: statement.student,
    academicYearId: statement.academicYearId,
    academicYearName: statement.academicYearName,
    currencyCode: statement.currencyCode,
    dues: [
      for (final due in statement.dues)
        if (due.id == 2)
          FeeDue(
            id: due.id,
            feeHeadName: due.feeHeadName,
            feeHeadId: due.feeHeadId,
            label: due.label,
            dueDate: due.dueDate,
            amount: due.amount,
            discountAmount: due.discountAmount,
            paidAmount: '600.00',
            balance: owedOnMay,
            status: FeeDueStatus.partial,
            isOverdue: false,
            paidFromCredit: '600.00',
          )
        else
          due,
    ],
    totals: statement.totals,
    credit: [FeeCreditBalance(currencyCode: 'INR', balance: credit)],
  );
}

Future<FakeFeeRepository> open(WidgetTester tester, StudentFeeStatement statement, {UserRole? role}) async {
  useDesktop(tester);
  final fees = FakeFeeRepository()..statements = {7: statement};
  await tester.pumpWidget(wrap(fees, at: '/student-fees?student=7', role: role ?? UserRole.accountant));
  await tester.pumpAndSettle();
  return fees;
}

void main() {
  group('the statement', () {
    testWidgets('shows the credit held, and what credit paid on a line', (tester) async {
      await open(tester, withCredit());

      expect(money('1,500.00'), findsWidgets);
      expect(find.text('In credit - it pays the next fees charged, oldest first.'), findsOneWidget);
      expect(find.textContaining('600.00 from credit'), findsOneWidget);
      expect(find.text('History'), findsOneWidget);
      expect(find.text('Refund'), findsOneWidget);
    });

    testWidgets('says nothing of credit when there is none', (tester) async {
      await open(tester, fakeStatement());

      expect(find.textContaining('In credit'), findsNothing);
      expect(find.text('Refund'), findsNothing);
      expect(find.textContaining('from credit'), findsNothing);
    });

    testWidgets('someone who only reads fees sees the history but cannot refund', (tester) async {
      await open(tester, withCredit(), role: UserRole.superAdmin);

      expect(find.text('History'), findsOneWidget);
      expect(find.text('Refund'), findsNothing);
    });

    testWidgets('the history lists each movement, in and out', (tester) async {
      final fees = await open(tester, withCredit());
      fees.creditEntries = [
        FeeCreditEntry(
          id: 2,
          kind: 'applied',
          kindLabel: 'Paid an installment',
          amount: '-600.00',
          currencyCode: 'INR',
          entryDate: DateTime(2026, 7, 15),
          dueLabel: 'Tuition - May 2026',
        ),
        FeeCreditEntry(
          id: 1,
          kind: 'released',
          kindLabel: 'Released from an installment that stopped applying',
          amount: '2100.00',
          currencyCode: 'INR',
          entryDate: DateTime(2026, 7, 15),
          dueLabel: 'Transport - Bus 2',
        ),
      ];

      await tapText(tester, 'History');

      expect(find.text('Credit history - Asha Rao'), findsOneWidget);
      expect(find.text('Paid an installment'), findsOneWidget);
      expect(find.text('Released from an installment that stopped applying'), findsOneWidget);
      expect(find.textContaining(RegExp(r'^- .*600\.00$')), findsOneWidget);
      expect(find.textContaining(RegExp(r'^\+ .*2,100\.00$')), findsOneWidget);
      expect(fees.creditHistoryRequests.single, (studentId: 7, page: 1));
    });

    testWidgets('an empty history says so', (tester) async {
      await open(tester, withCredit());

      await tapText(tester, 'History');

      expect(find.text('No credit has moved on this account yet.'), findsOneWidget);
    });

    testWidgets('a history that cannot be read offers a retry', (tester) async {
      final fees = await open(tester, withCredit());
      fees.failWith = const Failure(code: 'SERVER_ERROR', message: 'Something went wrong.');

      await tapText(tester, 'History');

      expect(find.text('Retry'), findsOneWidget);
    });
  });

  group('a refund', () {
    testWidgets('starts at the whole credit and sends what was entered', (tester) async {
      final fees = await open(tester, withCredit());
      await tapText(tester, 'Refund');

      expect(find.text('Refund credit - Asha Rao'), findsOneWidget);
      expect(tester.widget<TextFormField>(field('Amount refunded')).controller!.text, '1500.00');

      await tester.enterText(field('Amount refunded'), '1000');
      await tester.enterText(field('Reason'), 'Left the school');
      await tester.tap(find.widgetWithText(FilledButton, 'Record refund'));
      await tester.pumpAndSettle();

      expect(fees.refunds.single['amount'], '1000.00');
      expect(fees.refunds.single['currency_code'], 'INR');
      expect(fees.refunds.single['payment_mode'], 'cash');
      expect(fees.refunds.single['reason'], 'Left the school');
      expect(find.text('Refund credit - Asha Rao'), findsNothing);
      expect(find.textContaining('Refund of'), findsOneWidget);
    });

    testWidgets('more than the credit, no reason, or a cheque without its number is caught first', (tester) async {
      final fees = await open(tester, withCredit());
      await tapText(tester, 'Refund');

      await tester.enterText(field('Amount refunded'), '1500.01');
      await tester.tap(find.widgetWithText(FilledButton, 'Record refund'));
      await tester.pumpAndSettle();

      expect(find.textContaining('is held in credit.'), findsOneWidget);
      expect(find.text('Say why the money is refunded.'), findsOneWidget);

      await tester.enterText(field('Amount refunded'), '0');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Record refund'));
      await tester.pumpAndSettle();
      expect(find.text('Enter an amount above zero.'), findsOneWidget);

      await tester.tap(inDialog(find.text('Cash')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cheque').last);
      await tester.pumpAndSettle();
      await tester.enterText(field('Amount refunded'), '100');
      await tester.enterText(field('Reason'), 'Left the school');
      await tester.tap(find.widgetWithText(FilledButton, 'Record refund'));
      await tester.pumpAndSettle();
      expect(find.text('Enter the cheque number.'), findsOneWidget);

      expect(fees.refunds, isEmpty);
    });

    testWidgets('a refusal from the server is shown and the dialog stays open', (tester) async {
      final fees = await open(tester, withCredit());
      fees.failRefundWith = const Failure(
        code: 'VALIDATION_ERROR',
        message: 'The given data was invalid.',
        details: {
          'errors': {
            'amount': ['Asha Rao has only INR 1,200.00 in credit.'],
          },
        },
      );
      await tapText(tester, 'Refund');

      await tester.enterText(field('Reason'), 'Left the school');
      await tester.tap(find.widgetWithText(FilledButton, 'Record refund'));
      await tester.pumpAndSettle();

      expect(find.text('Asha Rao has only INR 1,200.00 in credit.'), findsOneWidget);
      expect(find.text('Refund credit - Asha Rao'), findsOneWidget);
    });

    testWidgets('Cancel leaves the credit alone', (tester) async {
      final fees = await open(tester, withCredit());
      await tapText(tester, 'Refund');

      await tester.tap(inDialog(find.text('Cancel')));
      await tester.pumpAndSettle();

      expect(fees.refunds, isEmpty);
      expect(find.text('Refund credit - Asha Rao'), findsNothing);
    });
  });

  group('paying more than is owed', () {
    testWidgets('says the rest will be held as credit, and the receipt shows it', (tester) async {
      final fees = await open(tester, fakeStatement());
      fees.paymentCreditAmount = '500.00';
      await tapText(tester, 'Record Payment');

      await tester.enterText(field('Amount received'), '2500');
      await tester.pump();
      expect(find.textContaining('more than is owed - it will be held as credit for the next fees.'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Record payment'));
      await tester.pumpAndSettle();

      expect(fees.payments.single['amount'], '2500.00');
      expect(find.text('Held as credit for the next fees'), findsOneWidget);
    });

    testWidgets('paying exactly what is owed says nothing of credit', (tester) async {
      await open(tester, fakeStatement());
      await tapText(tester, 'Record Payment');

      await tester.tap(find.text('Pay everything owed'));
      await tester.pump();

      expect(find.textContaining('held as credit'), findsNothing);
    });

    testWidgets('a student who owes nothing can still pay - into credit', (tester) async {
      final settled = fakeStatement();
      await open(
        tester,
        StudentFeeStatement(
          student: settled.student,
          academicYearId: settled.academicYearId,
          academicYearName: settled.academicYearName,
          currencyCode: settled.currencyCode,
          dues: const [],
          totals: const FeeTotals(charged: '0.00', paid: '0.00', discount: '0.00', balance: '0.00', overdue: '0.00'),
        ),
      );

      await tapText(tester, 'Record Payment');

      expect(find.textContaining('A payment now is held as credit for the next fees.'), findsOneWidget);
    });
  });
}
