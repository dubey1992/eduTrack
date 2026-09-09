import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/schools/data/school_repository.dart';
import 'package:edutrack_app/features/schools/presentation/add_school_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_school_repository.dart';

// Opened via a real showDialog route (rather than placed directly as the
// Scaffold body) because AddSchoolDialog pops itself on success. A plain
// Navigator.pop() on a route-less body empties the app's entire (sole) route
// instead of just the dialog, which tears down the Scaffold - and the
// SnackBar it was about to show - before the test can observe either.
Widget wrap(FakeSchoolRepository fake) {
  return ProviderScope(
    overrides: [schoolRepositoryProvider.overrideWithValue(fake)],
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
}

void main() {
  testWidgets('shows a validation error for an invalid email', (tester) async {
    await tester.pumpWidget(wrap(FakeSchoolRepository()));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

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
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await _fillValidForm(tester);
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    final schools = await fake.list();
    expect(schools.any((s) => s.name == 'Bright Future School'), isTrue);
    expect(find.byType(AddSchoolDialog), findsNothing);
    expect(find.text('School created.'), findsOneWidget);
  });

  testWidgets('shows the failure message and keeps the dialog open on error', (tester) async {
    final fake = FakeSchoolRepository(
      failCreateWith: const Failure(code: 'SCHOOL_EMAIL_TAKEN', message: 'That email is already registered.'),
    );
    await tester.pumpWidget(wrap(fake));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await _fillValidForm(tester);
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    expect(find.text('That email is already registered.'), findsOneWidget);
    expect(find.byType(AddSchoolDialog), findsOneWidget);
  });
}
