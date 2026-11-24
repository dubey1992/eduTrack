import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_family_repositories.dart';
import 'family_app_test.dart' show pumpFamilyApp;

/// Attendance below the school's early-warning line, on the Family app's
/// attendance screen (docs/mobile-apps-review.md, M8, 5.4).
void main() {
  testWidgets('while it stands, the screen says the figure and the line', (tester) async {
    final data = FakeFamilyRepository(month: attendanceMonth(belowLine: (rate: 66.7, line: 75, days: 30)));
    await pumpFamilyApp(tester, data: data, goTo: '/attendance');

    expect(find.byKey(const Key('family-below-line')), findsOneWidget);
    expect(
      find.textContaining("Attendance is 66.7% over the last 30 school days, below the school's 75% line"),
      findsOneWidget,
    );
  });

  testWidgets('a whole number reads as one', (tester) async {
    final data = FakeFamilyRepository(month: attendanceMonth(belowLine: (rate: 70.0, line: 75, days: 30)));
    await pumpFamilyApp(tester, data: data, goTo: '/attendance');

    expect(find.textContaining('Attendance is 70% over'), findsOneWidget);
  });

  testWidgets('above the line, nothing is shown', (tester) async {
    await pumpFamilyApp(tester, goTo: '/attendance');

    expect(find.byKey(const Key('family-below-line')), findsNothing);
  });
}
