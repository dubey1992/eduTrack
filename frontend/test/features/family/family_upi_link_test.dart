import 'package:edutrack_app/features/family/data/models/family_fees.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_family_repositories.dart';

/// What "Pay with any UPI app" asks for (docs/mobile-apps-review.md, 6.4).
void main() {
  Instalment line(int id, DateTime due, double balance) => Instalment(
    id: id,
    label: 'Term $id',
    dueDate: due,
    amount: 5000,
    discount: 0,
    paid: 5000 - balance,
    balance: balance,
    status: balance == 0 ? InstalmentStatus.paid : InstalmentStatus.due,
  );

  FamilyFees withNothingOverdue(List<Instalment> lines, {double balance = 0}) => FamilyFees(
    yearName: '2026-27',
    currencyCode: 'INR',
    totals: FeeTotals(charged: 15000, discount: 0, paid: 15000 - balance, balance: balance, overdue: 0),
    instalments: lines,
    receipts: const [],
    credit: 0,
    howToPay: const HowToPay(upiId: 'greenfield@okaxis'),
  );

  test('everything overdue comes first', () {
    expect(familyFees().amountToPayNow, 3500);
  });

  test('with nothing overdue, the next instalment still owing - the earliest, not the first listed', () {
    final fees = withNothingOverdue([
      line(3, DateTime(2027, 1, 10), 5000),
      line(1, DateTime(2026, 6, 10), 0),
      line(2, DateTime(2026, 12, 10), 1200),
    ], balance: 6200);

    expect(fees.amountToPayNow, 1200);
  });

  test('all paid asks for nothing, and offers no link', () {
    final fees = withNothingOverdue([line(1, DateTime(2026, 6, 10), 0)]);

    expect(fees.amountToPayNow, isNull);
    expect(fees.upiPayLink, isNull);
  });

  test('without a payee or a note, the link still carries the ID and the amount', () {
    final fees = withNothingOverdue([line(2, DateTime(2026, 12, 10), 1200)], balance: 1200);

    expect(fees.upiPayLink.toString(), 'upi://pay?pa=greenfield@okaxis&am=1200.00&cu=INR');
  });
}
