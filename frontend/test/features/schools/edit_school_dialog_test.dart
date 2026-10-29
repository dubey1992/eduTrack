import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/schools/data/models/school.dart';
import 'package:edutrack_app/features/schools/data/school_repository.dart';
import 'package:edutrack_app/features/schools/presentation/edit_school_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_map.dart';
import '../../support/fake_school_repository.dart';

// Deliberately no internal space in the local number - PhoneNumberField
// splits this into dial code "+91" and local number "9876543210", and the
// validator counts the local number's literal string length, so an
// internal space (as in the more decorative "98765 43210" fixtures used
// elsewhere) would make the pre-filled value fail its own validator before
// the test ever touches it.
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

// Opened via a real showDialog route (rather than placed directly as the
// Scaffold body) because EditSchoolDialog pops itself on success. A plain
// Navigator.pop() on a route-less body empties the app's entire (sole) route
// instead of just the dialog, which tears down the Scaffold - and the
// SnackBar it was about to show - before the test can observe either.
Widget wrap(FakeSchoolRepository fake, {School school = _school}) {
  return ProviderScope(
    // The form now holds a map. Pinned to "no key" so the dialog's own
    // tests never reach the network to find out, and so what they see is
    // the state the product is in before a key is configured.
    overrides: [schoolRepositoryProvider.overrideWithValue(fake), ...mapIsUnavailable()],
    child: MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showDialog(
              context: context,
              builder: (_) => EditSchoolDialog(school: school),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('shows a validation error when school name is cleared', (tester) async {
    await tester.pumpWidget(wrap(FakeSchoolRepository(schools: [_school])));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextFormField, 'School name'), '');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('School name is required'), findsOneWidget);
  });

  testWidgets('submits successfully and closes the dialog', (tester) async {
    final fake = FakeSchoolRepository(schools: [_school]);
    await tester.pumpWidget(wrap(fake));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextFormField, 'School name'), 'Brighter Future School');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final schools = await fake.list();
    expect(schools.firstWhere((s) => s.id == _school.id).name, 'Brighter Future School');
    expect(find.byType(EditSchoolDialog), findsNothing);
    expect(find.text('School updated.'), findsOneWidget);
  });

  testWidgets('shows the failure message and keeps the dialog open on error', (tester) async {
    final fake = FakeSchoolRepository(
      schools: [_school],
      failUpdateWith: const Failure(code: 'SCHOOL_EMAIL_TAKEN', message: 'That email is already registered.'),
    );
    await tester.pumpWidget(wrap(fake));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('That email is already registered.'), findsOneWidget);
    expect(find.byType(EditSchoolDialog), findsOneWidget);
  });

  testWidgets('moving a school to Live sends the new category', (tester) async {
    final fake = FakeSchoolRepository(schools: [_school]);
    await tester.pumpWidget(wrap(fake));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('school-category')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Demo').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(fake.lastUpdateCategory, SchoolCategory.demo);
    expect(find.byType(EditSchoolDialog), findsNothing);
  });

  testWidgets("the server's refusal of a trial date shows on the date", (tester) async {
    final fake = FakeSchoolRepository(
      schools: [_school],
      failUpdateWith: const Failure(
        code: 'VALIDATION_ERROR',
        message: 'The given data was invalid.',
        details: {
          'errors': {
            'trial_ends_on': ['The trial cannot end before today.'],
          },
        },
      ),
    );
    final trial = School(
      id: _school.id,
      name: _school.name,
      registrationNumber: null,
      email: _school.email,
      phone: _school.phone,
      address: _school.address,
      city: _school.city,
      state: _school.state,
      country: _school.country,
      postalCode: _school.postalCode,
      currencyCode: _school.currencyCode,
      timezone: _school.timezone,
      logoUrl: null,
      status: SchoolStatus.active,
      category: SchoolCategory.trial,
      trialEndsOn: '2026-09-01',
    );
    tester.view.physicalSize = const Size(1400, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(wrap(fake, school: trial));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('The trial cannot end before today.'), findsOneWidget);
    expect(find.byType(EditSchoolDialog), findsOneWidget);
  });
}
