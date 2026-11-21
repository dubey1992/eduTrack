import 'package:edutrack_app/features/payroll/data/models/payroll.dart';
import 'package:edutrack_app/features/payroll/presentation/payslip_dialog.dart';
import 'package:flutter_test/flutter_test.dart';

/// The small print under each payslip line.
void main() {
  String cash(String value) => 'INR $value';

  PayslipLine line({String amount = '36000.00', String? full, bool adjustment = false, String? note}) => PayslipLine(
    id: 1,
    type: PayComponentType.earning,
    name: 'Basic salary',
    amount: amount,
    fullAmount: full,
    isAdjustment: adjustment,
    note: note,
  );

  test('a salary line cut for days not paid says what it was cut from', () {
    expect(lineDetail(line(amount: '30000.00', full: '36000.00'), cash), 'Pro-rated from INR 36000.00');
  });

  test('a salary line paid in full says nothing, as on the PDF', () {
    expect(lineDetail(line(full: '36000.00'), cash), isNull);
  });

  test('an advance recovery - no full-month figure - shows its note, and never fails', () {
    expect(lineDetail(line(note: 'INR 1,500.00 left after this'), cash), 'INR 1,500.00 left after this');
    expect(lineDetail(line(), cash), isNull);
  });

  test('an adjustment says so, with its reason', () {
    expect(lineDetail(line(adjustment: true, note: 'Exam duty'), cash), 'Adjustment - Exam duty');
    expect(lineDetail(line(adjustment: true), cash), 'Adjustment');
  });
}
