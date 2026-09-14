import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/auth/data/models/authenticated_user.dart';
import 'package:edutrack_app/features/holidays/data/holiday_repository.dart';
import 'package:edutrack_app/features/holidays/presentation/add_holiday_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:edutrack_app/core/utils/date_format.dart';
import 'package:intl/intl.dart';

import '../../support/fake_auth_repository.dart';
import '../../support/fake_holiday_repository.dart';

const _schoolAdmin = AuthenticatedUser(id: 5, name: 'Admin', email: 'admin@example.com', role: UserRole.schoolAdmin);

/// Opened through a real showDialog route (behind an "Open" button) so the
/// dialog's own Navigator.pop() on success closes just the dialog.
Widget wrap(FakeHolidayRepository fake) {
  return ProviderScope(
    overrides: [
      holidayRepositoryProvider.overrideWithValue(fake),
      authRepositoryProvider.overrideWithValue(FakeAuthRepository(sessionOnRestore: _schoolAdmin)),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showDialog(context: context, builder: (_) => const AddHolidayDialog()),
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
  testWidgets('shows a validation error when the name is left empty', (tester) async {
    await tester.pumpWidget(wrap(FakeHolidayRepository()));
    await _open(tester);

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Name is required'), findsOneWidget);
  });

  testWidgets('defaults to today as a single-day National holiday and submits it', (tester) async {
    final fake = FakeHolidayRepository();
    await tester.pumpWidget(wrap(fake));
    await _open(tester);

    expect(find.text('National'), findsOneWidget);
    // The app shows dates in US order; the wire still uses ISO below.
    final today = formatDate(DateTime.now());
    expect(find.text(today), findsNWidgets(2));

    await tester.enterText(find.widgetWithText(TextFormField, 'Holiday name'), 'Sports Day');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final expectedDate = DateFormat('yyyy-MM-dd').format(DateTime.now());
    expect(fake.lastCreatePayload, {
      'school_id': null,
      'name': 'Sports Day',
      'type': 'national',
      'start_date': expectedDate,
      'end_date': expectedDate,
    });
    expect(find.byType(AddHolidayDialog), findsNothing);
    expect(find.text('Holiday added.'), findsOneWidget);
  });

  testWidgets('the type can be changed before saving', (tester) async {
    final fake = FakeHolidayRepository();
    await tester.pumpWidget(wrap(fake));
    await _open(tester);

    await tester.enterText(find.widgetWithText(TextFormField, 'Holiday name'), 'Summer Break');
    await tester.tap(find.text('National'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vacation').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(fake.lastCreatePayload!['type'], 'vacation');
  });

  testWidgets('shows the server failure and keeps the dialog open', (tester) async {
    final fake = FakeHolidayRepository(
      failCreateWith: const Failure(
        code: 'HOLIDAY_OVERLAP',
        message: 'These dates overlap the existing holiday "Diwali Break".',
      ),
    );
    await tester.pumpWidget(wrap(fake));
    await _open(tester);

    await tester.enterText(find.widgetWithText(TextFormField, 'Holiday name'), 'Clash');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('These dates overlap the existing holiday "Diwali Break".'), findsOneWidget);
    expect(find.byType(AddHolidayDialog), findsOneWidget);
  });
}
