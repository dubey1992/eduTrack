import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/schools/data/school_repository.dart';
import 'package:edutrack_app/features/schools/presentation/add_school_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_map.dart';
import '../../support/fake_school_repository.dart';

// Opened via a real showDialog route (rather than placed directly as the
// Scaffold body) because AddSchoolDialog pops itself on success. A plain
// Navigator.pop() on a route-less body empties the app's entire (sole) route
// instead of just the dialog, which tears down the Scaffold - and the
// SnackBar it was about to show - before the test can observe either.
Widget wrap(FakeSchoolRepository fake) {
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
            onPressed: () => showDialog(context: context, builder: (_) => const AddSchoolDialog()),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
}

/// Fills every required field with a valid value so a single targeted change
/// (or omission) is the only thing under test.
Future<void> _fillValidForm(WidgetTester tester) async {
  await tester.enterText(find.widgetWithText(TextFormField, 'School name'), 'Bright Future School');
  await tester.enterText(find.widgetWithText(TextFormField, 'Email'), 'admin@brightfuture.edu');
  await tester.enterText(find.widgetWithText(TextFormField, 'Phone'), '9876543210');
  await tester.enterText(find.widgetWithText(TextFormField, 'Address'), '45 Park Avenue');
  await tester.enterText(find.widgetWithText(TextFormField, 'City'), 'Pune');
  await tester.enterText(find.widgetWithText(TextFormField, 'State'), 'Maharashtra');
  await tester.enterText(find.widgetWithText(TextFormField, 'Country'), 'India');
  await tester.enterText(find.widgetWithText(TextFormField, 'Postal code'), '411001');
  await tester.enterText(find.byKey(const Key('school-admin-first-name')), 'Meena');
  await tester.enterText(find.byKey(const Key('school-admin-last-name')), 'Iyer');
}

Future<void> _open(WidgetTester tester) async {
  // Tall enough that the School Admin section at the foot of the form is
  // on screen without scrolling.
  tester.view.physicalSize = const Size(1400, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows a validation error for an invalid email', (tester) async {
    await tester.pumpWidget(wrap(FakeSchoolRepository()));
    await _open(tester);

    await _fillValidForm(tester);
    await tester.enterText(find.widgetWithText(TextFormField, 'Email'), 'not-an-email');
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    expect(find.text('Enter a valid email'), findsOneWidget);
    expect(find.byType(AddSchoolDialog), findsOneWidget);
  });

  testWidgets('submits successfully and closes the dialog', (tester) async {
    final fake = FakeSchoolRepository();
    await tester.pumpWidget(wrap(fake));
    await _open(tester);

    await _fillValidForm(tester);
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    final schools = await fake.list();
    expect(schools.any((s) => s.name == 'Bright Future School'), isTrue);
    expect(find.byType(AddSchoolDialog), findsNothing);
    expect(
      find.text('School and School Admin created. A link to set their password was emailed to admin@brightfuture.edu.'),
      findsOneWidget,
    );
  });

  testWidgets('shows the failure message and keeps the dialog open on error', (tester) async {
    final fake = FakeSchoolRepository(
      failCreateWith: const Failure(code: 'SCHOOL_EMAIL_TAKEN', message: 'That email is already registered.'),
    );
    await tester.pumpWidget(wrap(fake));
    await _open(tester);

    await _fillValidForm(tester);
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    expect(find.text('That email is already registered.'), findsOneWidget);
    expect(find.byType(AddSchoolDialog), findsOneWidget);
  });

  group('the School Admin', () {
    testWidgets('is asked for by default, and sent with the school', (tester) async {
      final fake = FakeSchoolRepository();
      await tester.pumpWidget(wrap(fake));
      await _open(tester);

      expect(find.text('Create the School Admin now'), findsOneWidget);
      await _fillValidForm(tester);
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();

      expect(fake.lastCreateAdmin, {'first_name': 'Meena', 'last_name': 'Iyer', 'email': null, 'password': null});
      expect(find.byType(AddSchoolDialog), findsNothing);
    });

    testWidgets('needs both names while it is on', (tester) async {
      final fake = FakeSchoolRepository();
      await tester.pumpWidget(wrap(fake));
      await _open(tester);

      await _fillValidForm(tester);
      await tester.enterText(find.byKey(const Key('school-admin-first-name')), '');
      await tester.enterText(find.byKey(const Key('school-admin-last-name')), '');
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();

      expect(find.text('First name is required'), findsOneWidget);
      expect(find.text('Last name is required'), findsOneWidget);
      expect(find.byType(AddSchoolDialog), findsOneWidget);
    });

    testWidgets('may have an email and a password of its own', (tester) async {
      final fake = FakeSchoolRepository();
      await tester.pumpWidget(wrap(fake));
      await _open(tester);

      await _fillValidForm(tester);
      await tester.enterText(find.byKey(const Key('school-admin-email')), 'meena@brightfuture.edu');
      await tester.enterText(find.widgetWithText(TextFormField, 'Admin password (optional)'), 'AGoodPassword2026');
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();

      expect(fake.lastCreateAdmin!['email'], 'meena@brightfuture.edu');
      expect(fake.lastCreateAdmin!['password'], 'AGoodPassword2026');
      expect(find.text('School and School Admin created.'), findsOneWidget);
    });

    testWidgets('refuses a malformed email and a weak password before sending', (tester) async {
      final fake = FakeSchoolRepository();
      await tester.pumpWidget(wrap(fake));
      await _open(tester);

      await _fillValidForm(tester);
      await tester.enterText(find.byKey(const Key('school-admin-email')), 'meena');
      await tester.enterText(find.widgetWithText(TextFormField, 'Admin password (optional)'), 'short1');
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();

      expect(find.text('Enter a valid email'), findsOneWidget);
      expect(find.text('At least 8 characters'), findsOneWidget);
      expect(fake.lastCreateAdmin, isNull);
    });

    testWidgets('can be switched off, and then only the school is created', (tester) async {
      final fake = FakeSchoolRepository();
      await tester.pumpWidget(wrap(fake));
      await _open(tester);

      await _fillValidForm(tester);
      await tester.tap(find.byKey(const Key('school-create-admin')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('school-admin-first-name')), findsNothing);
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();

      expect(fake.lastCreateAdmin, isNull);
      expect(find.text('School created.'), findsOneWidget);
    });

    testWidgets("shows the server's word on the admin email beside the field", (tester) async {
      final fake = FakeSchoolRepository(
        failCreateWith: const Failure(
          code: 'VALIDATION_ERROR',
          message: 'The given data was invalid.',
          details: {
            'errors': {
              'admin_email': [
                'An account already signs in with this email. Enter a different email for the School Admin.',
              ],
            },
          },
        ),
      );
      await tester.pumpWidget(wrap(fake));
      await _open(tester);

      await _fillValidForm(tester);
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();

      expect(find.textContaining('An account already signs in with this email'), findsOneWidget);
      expect(find.text('Check the School Admin details below.'), findsOneWidget);
      expect(find.byType(AddSchoolDialog), findsOneWidget);
    });
  });
}
