import 'package:edutrack_app/features/hod/presentation/widgets/month_stepper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('shows the month name and steps backwards', (tester) async {
    DateTime? picked;
    await tester.pumpWidget(
      wrap(MonthStepper(month: DateTime(2026, 8), maxMonth: DateTime(2026, 9), onChanged: (m) => picked = m)),
    );

    expect(find.text('August 2026'), findsOneWidget);

    await tester.tap(find.byTooltip('Previous month'));
    expect(picked, DateTime(2026, 7));
  });

  testWidgets('steps forward until the max month, then disables the next button', (tester) async {
    DateTime? picked;
    await tester.pumpWidget(
      wrap(MonthStepper(month: DateTime(2026, 8), maxMonth: DateTime(2026, 9), onChanged: (m) => picked = m)),
    );

    await tester.tap(find.byTooltip('Next month'));
    expect(picked, DateTime(2026, 9));

    await tester.pumpWidget(
      wrap(MonthStepper(month: DateTime(2026, 9), maxMonth: DateTime(2026, 9), onChanged: (m) => picked = m)),
    );
    final next = tester.widget<IconButton>(
      find.ancestor(of: find.byTooltip('Next month'), matching: find.byType(IconButton)),
    );
    expect(next.onPressed, isNull);
  });

  testWidgets('stepping back from January rolls into December of the previous year', (tester) async {
    DateTime? picked;
    await tester.pumpWidget(
      wrap(MonthStepper(month: DateTime(2026, 1), maxMonth: DateTime(2026, 9), onChanged: (m) => picked = m)),
    );

    await tester.tap(find.byTooltip('Previous month'));
    expect(picked, DateTime(2025, 12));
  });
}
