import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/holidays/data/holiday_repository.dart';
import 'package:edutrack_app/features/holidays/data/models/holiday.dart';
import 'package:edutrack_app/features/holidays/presentation/edit_holiday_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_holiday_repository.dart';

const _diwali = Holiday(
  id: 1,
  schoolId: 1,
  schoolName: 'Sunrise Public School',
  name: 'Diwali Break',
  type: HolidayType.religious,
  startDate: '2026-11-09',
  endDate: '2026-11-11',
  days: 3,
);

Widget wrap(FakeHolidayRepository fake) {
  return ProviderScope(
    overrides: [holidayRepositoryProvider.overrideWithValue(fake)],
    child: MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showDialog(
              context: context,
              builder: (_) => const EditHolidayDialog(holiday: _diwali),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
}

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('pre-fills the existing name, type and dates', (tester) async {
    await tester.pumpWidget(wrap(FakeHolidayRepository(holidays: [_diwali])));
    await _open(tester);

    expect(find.text('Diwali Break'), findsOneWidget);
    expect(find.text('Religious'), findsOneWidget);
    expect(find.text('11/09/2026'), findsOneWidget);
    expect(find.text('11/11/2026'), findsOneWidget);
  });

  testWidgets('shows a validation error when the name is cleared', (tester) async {
    await tester.pumpWidget(wrap(FakeHolidayRepository(holidays: [_diwali])));
    await _open(tester);

    await tester.enterText(find.widgetWithText(TextFormField, 'Holiday name'), '');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Name is required'), findsOneWidget);
  });

  testWidgets('saves the changes, closes the dialog and confirms', (tester) async {
    final fake = FakeHolidayRepository(holidays: [_diwali]);
    await tester.pumpWidget(wrap(fake));
    await _open(tester);

    await tester.enterText(find.widgetWithText(TextFormField, 'Holiday name'), 'Diwali');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(fake.lastUpdatePayload, {
      'name': 'Diwali',
      'type': 'religious',
      'start_date': '2026-11-09',
      'end_date': '2026-11-11',
    });
    expect(fake.holidays.single.name, 'Diwali');
    expect(find.byType(EditHolidayDialog), findsNothing);
    expect(find.text('Holiday updated.'), findsOneWidget);
  });

  testWidgets('shows the server failure and keeps the dialog open', (tester) async {
    final fake = FakeHolidayRepository(
      holidays: [_diwali],
      failUpdateWith: const Failure(
        code: 'HOLIDAY_OVERLAP',
        message: 'These dates overlap the existing holiday "Other".',
      ),
    );
    await tester.pumpWidget(wrap(fake));
    await _open(tester);

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('These dates overlap the existing holiday "Other".'), findsOneWidget);
    expect(find.byType(EditHolidayDialog), findsOneWidget);
  });
}
