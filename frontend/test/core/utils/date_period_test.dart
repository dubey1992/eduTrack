import 'package:edutrack_app/core/utils/date_period.dart';
import 'package:flutter_test/flutter_test.dart';

/// The ranges behind All / Today / This week / This month
/// (docs/teacher-app.md, "Filters by period").
void main() {
  final wednesday = DateTime(2026, 10, 28, 15, 40);

  test('All is no range at all', () {
    expect(DatePeriod.all.rangeFrom(wednesday), isNull);
  });

  test('Today is the one day, whatever the time', () {
    expect(DatePeriod.day.rangeFrom(wednesday), (from: '2026-10-28', to: '2026-10-28'));
  });

  test('This week runs Monday to Sunday', () {
    expect(DatePeriod.week.rangeFrom(wednesday), (from: '2026-10-26', to: '2026-11-01'));
  });

  test('a Monday and a Sunday are in their own week', () {
    expect(DatePeriod.week.rangeFrom(DateTime(2026, 10, 26)), (from: '2026-10-26', to: '2026-11-01'));
    expect(DatePeriod.week.rangeFrom(DateTime(2026, 11, 1)), (from: '2026-10-26', to: '2026-11-01'));
  });

  test('This month is the calendar month, to its last day', () {
    expect(DatePeriod.month.rangeFrom(wednesday), (from: '2026-10-01', to: '2026-10-31'));
    expect(DatePeriod.month.rangeFrom(DateTime(2026, 12, 9)), (from: '2026-12-01', to: '2026-12-31'));
    expect(DatePeriod.month.rangeFrom(DateTime(2028, 2, 3)), (from: '2028-02-01', to: '2028-02-29'));
  });

  test('an empty list says which period it is about', () {
    expect(DatePeriod.all.emptyPhrase('reports'), 'No reports yet.');
    expect(DatePeriod.week.emptyPhrase('reports'), 'No reports this week.');
  });
}
