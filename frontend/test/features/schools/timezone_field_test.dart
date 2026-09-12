import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/schools/data/models/school.dart';
import 'package:edutrack_app/features/schools/data/models/timezone_option.dart';
import 'package:edutrack_app/features/schools/data/school_repository.dart';
import 'package:edutrack_app/features/schools/presentation/edit_school_dialog.dart';
import 'package:edutrack_app/features/schools/presentation/widgets/timezone_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_school_repository.dart';

const _school = School(
  id: 7,
  name: 'Bright Future School',
  registrationNumber: null,
  email: 'admin@brightfuture.edu',
  phone: '+91 9876543210',
  address: '45 Park Avenue',
  city: 'Pune',
  state: 'Maharashtra',
  country: 'India',
  postalCode: '411001',
  currencyCode: 'INR',
  timezone: 'UTC',
  logoUrl: null,
  status: SchoolStatus.active,
);

/// Enough zones to prove the filtering: two share a region, two share an
/// offset, and none of the interesting ones start with the term searched for.
const _zones = [
  TimezoneOption(name: 'UTC', region: 'Other', label: 'UTC (GMT+00:00)', offsetMinutes: 0),
  TimezoneOption(name: 'Africa/Lagos', region: 'Africa', label: 'Africa/Lagos (GMT+01:00)', offsetMinutes: 60),
  TimezoneOption(name: 'Asia/Kolkata', region: 'Asia', label: 'Asia/Kolkata (GMT+05:30)', offsetMinutes: 330),
  TimezoneOption(name: 'Asia/Colombo', region: 'Asia', label: 'Asia/Colombo (GMT+05:30)', offsetMinutes: 330),
  TimezoneOption(name: 'Pacific/Auckland', region: 'Pacific', label: 'Pacific/Auckland (GMT+12:00)', offsetMinutes: 720),
];

Widget wrap(FakeSchoolRepository fake, {School school = _school}) {
  return ProviderScope(
    overrides: [schoolRepositoryProvider.overrideWithValue(fake)],
    child: MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showDialog(context: context, builder: (_) => EditSchoolDialog(school: school)),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
}

Future<void> openForm(WidgetTester tester, FakeSchoolRepository fake, {School school = _school}) async {
  await tester.pumpWidget(wrap(fake, school: school));
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.byType(TimezoneField));
}

/// Opens the picker and types a search term into it.
Future<void> search(WidgetTester tester, String term) async {
  await tester.tap(find.byType(TimezoneField));
  await tester.pumpAndSettle();
  await tester.enterText(find.widgetWithText(TextField, 'Search'), term);
  await tester.pumpAndSettle();
}

Future<void> save(WidgetTester tester) async {
  await tester.tap(find.text('Save'));
  await tester.pumpAndSettle();
}

String savedTimezone(List<School> schools) => schools.firstWhere((s) => s.id == _school.id).timezone;

/// The timezone picker on the school form. It decides what "today" means for
/// everything the school records, so it has to be searchable (there are
/// several hundred zones), has to survive a zone the server no longer lists,
/// and must not block the form when the reference list cannot be fetched.
void main() {
  testWidgets('shows the school current zone on the form', (tester) async {
    final fake = FakeSchoolRepository(schools: [_school])..timezones = _zones;
    await openForm(tester, fake);

    expect(find.text('UTC (GMT+00:00)'), findsOneWidget);
  });

  testWidgets('opening the picker lists every zone', (tester) async {
    final fake = FakeSchoolRepository(schools: [_school])..timezones = _zones;
    await openForm(tester, fake);

    await tester.tap(find.byType(TimezoneField));
    await tester.pumpAndSettle();

    expect(find.text('Asia/Kolkata (GMT+05:30)'), findsOneWidget);
    expect(find.text('Pacific/Auckland (GMT+12:00)'), findsOneWidget);
  });

  testWidgets('searching by city narrows the list to the matching zone', (tester) async {
    final fake = FakeSchoolRepository(schools: [_school])..timezones = _zones;
    await openForm(tester, fake);

    await search(tester, 'kolkata');

    // "Asia/Kolkata (GMT+05:30)" does not *start* with the term, so this only
    // passes because the filter matches anywhere in the label.
    expect(find.text('Asia/Kolkata (GMT+05:30)'), findsOneWidget);
    expect(find.text('Pacific/Auckland (GMT+12:00)'), findsNothing);
    expect(find.text('Africa/Lagos (GMT+01:00)'), findsNothing);
  });

  testWidgets('searching by offset finds every zone at that offset', (tester) async {
    final fake = FakeSchoolRepository(schools: [_school])..timezones = _zones;
    await openForm(tester, fake);

    await search(tester, '+05:30');

    expect(find.text('Asia/Kolkata (GMT+05:30)'), findsOneWidget);
    expect(find.text('Asia/Colombo (GMT+05:30)'), findsOneWidget);
    expect(find.text('Pacific/Auckland (GMT+12:00)'), findsNothing);
  });

  testWidgets('searching by region works and ignores case', (tester) async {
    final fake = FakeSchoolRepository(schools: [_school])..timezones = _zones;
    await openForm(tester, fake);

    await search(tester, 'PACIFIC');

    expect(find.text('Pacific/Auckland (GMT+12:00)'), findsOneWidget);
    expect(find.text('Asia/Kolkata (GMT+05:30)'), findsNothing);
  });

  testWidgets('a search that matches nothing says so', (tester) async {
    final fake = FakeSchoolRepository(schools: [_school])..timezones = _zones;
    await openForm(tester, fake);

    await search(tester, 'atlantis');

    expect(find.text('No timezone matches that search.'), findsOneWidget);
  });

  testWidgets('picking a searched zone saves it', (tester) async {
    final fake = FakeSchoolRepository(schools: [_school])..timezones = _zones;
    await openForm(tester, fake);

    await search(tester, 'kolkata');
    await tester.tap(find.text('Asia/Kolkata (GMT+05:30)'));
    await tester.pumpAndSettle();

    // The form now shows the new zone, and saving sends it.
    expect(find.text('Asia/Kolkata (GMT+05:30)'), findsOneWidget);
    await save(tester);

    expect(savedTimezone(await fake.list()), 'Asia/Kolkata');
  });

  testWidgets('abandoning a search leaves the chosen zone untouched', (tester) async {
    // The field is read-only, so a half-typed search can never be mistaken
    // for what the form will save.
    final fake = FakeSchoolRepository(schools: [_school])..timezones = _zones;
    await openForm(tester, fake);

    await search(tester, 'kolka');
    // The school form has a Cancel too; the picker's is the one on top.
    await tester.tap(find.text('Cancel').last);
    await tester.pumpAndSettle();

    expect(find.text('UTC (GMT+00:00)'), findsOneWidget);
    await save(tester);

    expect(savedTimezone(await fake.list()), 'UTC');
  });

  testWidgets('the zone already chosen is ticked in the list', (tester) async {
    final fake = FakeSchoolRepository(schools: [_school])..timezones = _zones;
    await openForm(tester, fake);

    await tester.tap(find.byType(TimezoneField));
    await tester.pumpAndSettle();

    final selected = tester.widget<ListTile>(find.widgetWithText(ListTile, 'UTC (GMT+00:00)'));
    expect(selected.selected, isTrue);
    expect(find.byIcon(Icons.check), findsOneWidget);
  });

  testWidgets('leaves the zone alone when the form is saved untouched', (tester) async {
    final fake = FakeSchoolRepository(schools: [_school])..timezones = _zones;
    await openForm(tester, fake);

    await save(tester);

    expect(savedTimezone(await fake.list()), 'UTC');
  });

  testWidgets('keeps a zone the server no longer lists showing as itself', (tester) async {
    // The IANA database retires names occasionally. The school must not be
    // silently switched to something else just because its zone dropped off
    // the list.
    final fake = FakeSchoolRepository(schools: [_school])
      ..timezones = const [
        TimezoneOption(name: 'Asia/Kolkata', region: 'Asia', label: 'Asia/Kolkata (GMT+05:30)', offsetMinutes: 330),
      ];

    await openForm(tester, fake);

    expect(find.text('UTC'), findsOneWidget);
    await save(tester);

    expect(savedTimezone(await fake.list()), 'UTC');
  });

  testWidgets('falls back to a text box when the zone list cannot be fetched', (tester) async {
    final fake = FakeSchoolRepository(
      schools: [_school],
      failListTimezonesWith: const Failure(code: 'SERVER_ERROR', message: 'Something went wrong.'),
    );

    await openForm(tester, fake);

    // A failed reference fetch must not stop a Super Admin editing the
    // school; they can still type the zone, and the API validates it.
    final field = find.descendant(of: find.byType(TimezoneField), matching: find.byType(TextFormField));
    expect(field, findsOneWidget);

    await tester.enterText(field, 'Africa/Lagos');
    await save(tester);

    expect(savedTimezone(await fake.list()), 'Africa/Lagos');
  });
}
