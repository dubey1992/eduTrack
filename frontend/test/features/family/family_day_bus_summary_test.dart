import 'package:edutrack_app/features/family/data/models/family_day.dart';
import 'package:edutrack_app/features/family/data/models/family_fees.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_family_repositories.dart';

/// Two things the M6 emulator walk-through caught.
void main() {
  BusTrip trip(String direction, String status, String? rider) =>
      BusTrip(direction: direction, status: status, riderStatus: rider, boardedAt: null, droppedAt: null);

  group('the Home bus line', () {
    test('a pickup still running with the child on board is on its way to school', () {
      expect(trip('pickup', 'in_progress', 'boarded').summary, 'On the bus to school');
    });

    test('a pickup that has ended with the child still marked on board has reached school', () {
      expect(trip('pickup', 'completed', 'boarded').summary, 'Reached school');
    });

    test('a drop that has ended with the child unmarked says only that the trip ended', () {
      expect(trip('drop', 'completed', 'boarded').summary, 'Trip ended');
    });

    test('the rest is as before', () {
      expect(trip('drop', 'in_progress', 'boarded').summary, 'On the bus home');
      expect(trip('pickup', 'completed', 'dropped').summary, 'Reached school');
      expect(trip('pickup', 'cancelled', 'boarded').summary, 'Trip cancelled');
    });
  });

  group('fees the school waived', () {
    test('count what was still owed on the waived instalment', () {
      final base = familyFees();
      final fees = FamilyFees(
        yearName: base.yearName,
        currencyCode: base.currencyCode,
        totals: base.totals,
        instalments: [
          ...base.instalments,
          Instalment(
            id: 9,
            label: 'March',
            dueDate: DateTime(2027, 3, 10),
            amount: 2000,
            discount: 500,
            paid: 0,
            balance: 0,
            status: InstalmentStatus.waived,
          ),
        ],
        receipts: base.receipts,
        credit: 0,
        howToPay: base.howToPay,
      );

      expect(fees.waived, 1500);
      expect(familyFees().waived, 0);
    });
  });
}
