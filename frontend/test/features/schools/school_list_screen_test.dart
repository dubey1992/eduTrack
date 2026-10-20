import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/schools/data/models/school.dart';
import 'package:edutrack_app/features/schools/data/school_repository.dart';
import 'package:edutrack_app/features/schools/presentation/school_list_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_school_repository.dart';
import '../../support/paginated_table.dart';

const _school = School(
  id: 1,
  name: 'Sunrise Public School',
  registrationNumber: null,
  email: 'admin@sunriseschool.edu',
  phone: '+91 98765 43210',
  address: '12 School Road',
  city: 'New Delhi',
  state: 'Delhi',
  country: 'India',
  postalCode: '110001',
  currencyCode: 'INR',
  timezone: 'UTC',
  logoUrl: null,
  status: SchoolStatus.active,
);

Widget wrap(FakeSchoolRepository fake) {
  return ProviderScope(
    overrides: [schoolRepositoryProvider.overrideWithValue(fake)],
    child: MaterialApp(
      theme: AppTheme.light(),
      home: const Scaffold(body: SchoolListScreen()),
    ),
  );
}

void main() {
  testWidgets('shows an empty state when there are no schools', (tester) async {
    await tester.pumpWidget(wrap(FakeSchoolRepository()));
    await tester.pumpAndSettle();

    expect(find.text('No schools yet.'), findsOneWidget);
  });

  testWidgets('shows each school on the mobile layout', (tester) async {
    await tester.pumpWidget(wrap(FakeSchoolRepository(schools: [_school])));
    await tester.pumpAndSettle();

    expect(find.text('Sunrise Public School'), findsOneWidget);
    expect(find.textContaining('New Delhi, India'), findsOneWidget);
  });

  testWidgets('deactivating a school updates its status badge', (tester) async {
    await tester.pumpWidget(wrap(FakeSchoolRepository(schools: [_school])));
    await tester.pumpAndSettle();

    expect(find.text('Active'), findsOneWidget);

    await tester.tap(find.text('Deactivate'));
    await tester.pumpAndSettle();

    expect(find.text('Inactive'), findsOneWidget);
  });

  testWidgets('shows an error state with a working retry when loading fails', (tester) async {
    final fake = FakeSchoolRepository(
      schools: [_school],
      failListPageWith: const Failure(code: 'SCHOOL_LIST_FAILED', message: 'Could not load schools.'),
    );
    await tester.pumpWidget(wrap(fake));
    await tester.pumpAndSettle();

    expect(find.text('Could not load schools.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Sunrise Public School'), findsNothing);

    fake.failListPageWith = null;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.text('Sunrise Public School'), findsOneWidget);
    expect(find.text('Could not load schools.'), findsNothing);
  });

  testWidgets('a full page of schools scrolls above the pagination bar on desktop', (tester) async {
    useShortDesktopWindow(tester);
    final schools = [
      for (var n = 1; n <= 20; n++)
        School(
          id: n,
          name: 'School $n',
          registrationNumber: null,
          email: 'admin$n@school.edu',
          phone: '+91 98765 43210',
          address: '12 School Road',
          city: 'New Delhi',
          state: 'Delhi',
          country: 'India',
          postalCode: '110001',
          currencyCode: 'INR',
          timezone: 'UTC',
          logoUrl: null,
          status: SchoolStatus.active,
        ),
    ];
    await tester.pumpWidget(wrap(FakeSchoolRepository(schools: schools)));
    await tester.pumpAndSettle();

    await expectLastRowScrollsAbovePagination(tester, find.text('School 20'));
  });

  group('finding a school', () {
    testWidgets('typing asks the server, rather than filtering rows in hand', (tester) async {
      // The list holds a page of twenty. Filtering those would hide every
      // match on page four - see CLAUDE.md on server-side search.
      final fake = FakeSchoolRepository(schools: [_aSchool(1, 'Abbey Road'), _aSchool(2, 'Beacon Hill')]);
      await tester.pumpWidget(wrap(fake));
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextField, 'Search schools'), 'beacon');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      expect(fake.lastQuery, 'beacon');
      expect(find.text('Beacon Hill'), findsOneWidget);
      expect(find.text('Abbey Road'), findsNothing);
    });

    testWidgets('it waits for somebody to stop typing', (tester) async {
      final fake = FakeSchoolRepository(schools: [_aSchool(1, 'Abbey Road')]);
      await tester.pumpWidget(wrap(fake));
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextField, 'Search schools'), 'a');
      await tester.pump(const Duration(milliseconds: 50));
      await tester.enterText(find.widgetWithText(TextField, 'Search schools'), 'ab');
      await tester.pump(const Duration(milliseconds: 50));

      // Nothing asked yet - a request per keystroke would be a request per
      // keystroke, and the answer somebody wants is for what they finished.
      expect(fake.lastQuery, isNull);

      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      expect(fake.lastQuery, 'ab');
    });

    testWidgets('clearing it asks for everything again', (tester) async {
      final fake = FakeSchoolRepository(schools: [_aSchool(1, 'Abbey Road'), _aSchool(2, 'Beacon Hill')]);
      await tester.pumpWidget(wrap(fake));
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextField, 'Search schools'), 'beacon');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Clear'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      expect(fake.lastQuery, isNull);
      expect(find.text('Abbey Road'), findsOneWidget);
    });

    testWidgets('the status filter narrows to one kind', (tester) async {
      final fake = FakeSchoolRepository(
        schools: [
          _aSchool(1, 'Abbey Road'),
          _aSchool(2, 'Closed Campus', status: SchoolStatus.inactive),
        ],
      );
      await tester.pumpWidget(wrap(fake));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(DropdownButtonFormField<String?>, 'Status'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Inactive').last);
      await tester.pumpAndSettle();

      expect(fake.lastStatus, 'inactive');
      expect(find.text('Closed Campus'), findsOneWidget);
      expect(find.text('Abbey Road'), findsNothing);
    });

    testWidgets('All puts the filter back', (tester) async {
      final fake = FakeSchoolRepository(schools: [_aSchool(1, 'Abbey Road')]);
      await tester.pumpWidget(wrap(fake));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(DropdownButtonFormField<String?>, 'Status'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Active').last);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(DropdownButtonFormField<String?>, 'Status'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('All').last);
      await tester.pumpAndSettle();

      expect(fake.lastStatus, isNull);
    });
  });
}

School _aSchool(int id, String name, {SchoolStatus status = SchoolStatus.active}) {
  return School(
    id: id,
    name: name,
    registrationNumber: null,
    email: 'school$id@example.invalid',
    phone: '+91 9000000000',
    address: '1 Road',
    city: 'Pune',
    state: 'MH',
    country: 'India',
    postalCode: '411001',
    currencyCode: 'INR',
    timezone: 'Asia/Kolkata',
    logoUrl: null,
    status: status,
  );
}
