import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/auth/data/models/authenticated_user.dart';
import 'package:edutrack_app/features/holidays/data/holiday_repository.dart';
import 'package:edutrack_app/features/holidays/data/models/holiday.dart';
import 'package:edutrack_app/features/holidays/presentation/edit_holiday_dialog.dart';
import 'package:edutrack_app/features/holidays/presentation/holiday_list_screen.dart';
import 'package:edutrack_app/features/schools/data/school_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_auth_repository.dart';
import '../../support/fake_holiday_repository.dart';
import '../../support/fake_school_repository.dart';

const _schoolAdmin = AuthenticatedUser(id: 9, name: 'Admin', email: 'admin@example.com', role: UserRole.schoolAdmin);
const _teacher = AuthenticatedUser(id: 20, name: 'Priya Sharma', email: 'priya@example.com', role: UserRole.teacher);

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

const _independence = Holiday(
  id: 2,
  schoolId: 1,
  schoolName: 'Sunrise Public School',
  name: 'Independence Day',
  type: HolidayType.national,
  startDate: '2026-08-15',
  endDate: '2026-08-15',
  days: 1,
);

Widget wrap(FakeHolidayRepository fake, {AuthenticatedUser actor = _schoolAdmin}) {
  return ProviderScope(
    overrides: [
      holidayRepositoryProvider.overrideWithValue(fake),
      schoolRepositoryProvider.overrideWithValue(FakeSchoolRepository()),
      authRepositoryProvider.overrideWithValue(FakeAuthRepository(sessionOnRestore: actor)),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      home: const Scaffold(body: HolidayListScreen()),
    ),
  );
}

void useDesktop(WidgetTester tester) {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('lists holidays in date order with type, dates and length (cards on narrow screens)', (tester) async {
    await tester.pumpWidget(wrap(FakeHolidayRepository(holidays: [_diwali, _independence])));
    await tester.pumpAndSettle();

    expect(find.byType(DataTable), findsNothing);
    expect(find.text('Independence Day'), findsOneWidget);
    expect(find.text('Diwali Break'), findsOneWidget);
    expect(find.text('National'), findsOneWidget);
    expect(find.text('Religious'), findsOneWidget);
    expect(find.text('Aug 15, 2026 · 1 day'), findsOneWidget);
    expect(find.text('Nov 9, 2026 – Nov 11, 2026 · 3 days'), findsOneWidget);

    final independenceY = tester.getTopLeft(find.text('Independence Day')).dy;
    final diwaliY = tester.getTopLeft(find.text('Diwali Break')).dy;
    expect(independenceY, lessThan(diwaliY));
  });

  testWidgets('renders a table with an Actions column for an admin on desktop', (tester) async {
    useDesktop(tester);
    await tester.pumpWidget(wrap(FakeHolidayRepository(holidays: [_diwali])));
    await tester.pumpAndSettle();

    expect(find.byType(DataTable), findsOneWidget);
    expect(find.text('Actions'), findsOneWidget);
    expect(find.text('Nov 9, 2026 – Nov 11, 2026'), findsOneWidget);
    expect(find.text('3 days'), findsOneWidget);
    expect(find.byTooltip('Edit'), findsOneWidget);
    expect(find.byTooltip('Delete'), findsOneWidget);
  });

  testWidgets('a school admin sees the add, edit and delete controls', (tester) async {
    await tester.pumpWidget(wrap(FakeHolidayRepository(holidays: [_diwali])));
    await tester.pumpAndSettle();

    expect(find.text('Add Holiday'), findsOneWidget);
    expect(find.byTooltip('Edit'), findsOneWidget);
    expect(find.byTooltip('Delete'), findsOneWidget);
  });

  testWidgets('a teacher can view the calendar but gets no management controls', (tester) async {
    await tester.pumpWidget(wrap(FakeHolidayRepository(holidays: [_diwali]), actor: _teacher));
    await tester.pumpAndSettle();

    expect(find.text('Add Holiday'), findsNothing);
    expect(find.byTooltip('Edit'), findsNothing);
    expect(find.byTooltip('Delete'), findsNothing);
    expect(find.text('Diwali Break'), findsOneWidget);
  });

  testWidgets('shows the empty state when the calendar has nothing on it', (tester) async {
    await tester.pumpWidget(wrap(FakeHolidayRepository()));
    await tester.pumpAndSettle();

    expect(find.text('No holidays on the calendar yet.'), findsOneWidget);
  });

  testWidgets('shows the error state with a Retry button when loading fails', (tester) async {
    final fake = FakeHolidayRepository(
      holidays: [_diwali],
      failListPageWith: const Failure(code: 'NETWORK_ERROR', message: 'Could not reach the server.'),
    );
    await tester.pumpWidget(wrap(fake));
    await tester.pumpAndSettle();

    expect(find.text('Could not reach the server.'), findsOneWidget);

    fake.failListPageWith = null;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.text('Diwali Break'), findsOneWidget);
  });

  testWidgets('the edit action opens the edit dialog pre-filled', (tester) async {
    await tester.pumpWidget(wrap(FakeHolidayRepository(holidays: [_diwali])));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Edit'));
    await tester.pumpAndSettle();

    expect(find.byType(EditHolidayDialog), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Holiday name'), findsOneWidget);
    expect(find.text('Diwali Break'), findsWidgets);
  });

  testWidgets('deleting asks for confirmation, then removes the holiday', (tester) async {
    final fake = FakeHolidayRepository(holidays: [_diwali, _independence]);
    await tester.pumpWidget(wrap(fake));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Delete').first);
    await tester.pumpAndSettle();
    expect(find.text('Delete holiday?'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(fake.lastDeletedId, isNull);

    await tester.tap(find.byTooltip('Delete').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(fake.lastDeletedId, 2);
    expect(find.text('Independence Day was deleted.'), findsOneWidget);
    expect(find.text('Independence Day'), findsNothing);
    expect(find.text('Diwali Break'), findsOneWidget);
  });
}
