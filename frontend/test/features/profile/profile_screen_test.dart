import 'dart:async';

import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/network/dio_client.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/auth/data/models/authenticated_user.dart';
import 'package:edutrack_app/features/profile/data/profile_repository.dart';
import 'package:edutrack_app/features/profile/presentation/profile_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_auth_repository.dart';
import '../../support/fake_photo_dio.dart';
import '../../support/fake_profile_repository.dart';

const _session = AuthenticatedUser(id: 12, name: 'Asha Rao', email: 'asha@example.com', role: UserRole.teacher);

Widget wrap(FakeProfileRepository fake) {
  return ProviderScope(
    retry: (retryCount, error) => null,
    overrides: [
      profileRepositoryProvider.overrideWithValue(fake),
      authRepositoryProvider.overrideWithValue(FakeAuthRepository(sessionOnRestore: _session)),
      // A photo that cannot be fetched: the avatar falls back to initials.
      dioClientProvider.overrideWithValue(fakePhotoDio()),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      home: const Scaffold(body: ProfileScreen()),
    ),
  );
}

void useDesktop(WidgetTester tester) {
  tester.view.physicalSize = const Size(1400, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void usePhone(WidgetTester tester) {
  tester.view.physicalSize = const Size(400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<void> pumpScreen(WidgetTester tester, FakeProfileRepository fake) async {
  useDesktop(tester);
  await tester.pumpWidget(wrap(fake));
  await tester.pumpAndSettle();
}

String fieldText(WidgetTester tester, Key key) => tester.widget<TextFormField>(find.byKey(key)).controller!.text;

/// The local number box inside the shared PhoneNumberField.
Finder mobileInput() {
  return find.descendant(of: find.byKey(const Key('profile-mobile')), matching: find.byType(TextFormField));
}

/// The password box inside the shared PasswordField.
Finder emailPasswordInput() {
  return find.descendant(of: find.byKey(const Key('change-email-password')), matching: find.byType(TextFormField));
}

FilledButton saveButton(WidgetTester tester) => tester.widget<FilledButton>(find.byKey(const Key('profile-save')));

Future<void> tapSave(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const Key('profile-save')));
  await tester.tap(find.byKey(const Key('profile-save')));
  await tester.pumpAndSettle();
}

Failure fieldFailure(String field, String message) {
  return Failure(
    code: 'VALIDATION_ERROR',
    message: message,
    details: {
      'errors': {
        field: [message],
      },
    },
  );
}

Future<void> openChangeEmail(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const Key('profile-change-email')));
  await tester.tap(find.byKey(const Key('profile-change-email')));
  await tester.pumpAndSettle();
}

Future<void> submitChangeEmail(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(FilledButton, 'Change email'));
  await tester.pumpAndSettle();
}

/// The user's own page: every role sees their details, email, photo and
/// security; only someone with a staff record sees an address and work card.
void main() {
  testWidgets('shows a spinner while the profile loads', (tester) async {
    useDesktop(tester);
    final fake = FakeProfileRepository()..getGate = Completer<void>();
    await tester.pumpWidget(wrap(fake));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byKey(const Key('profile-first-name')), findsNothing);

    fake.getGate!.complete();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('profile-first-name')), findsOneWidget);
  });

  testWidgets('a failed load shows the error and retries on request', (tester) async {
    final fake = FakeProfileRepository(failGetWith: Failure.network());
    await pumpScreen(tester, fake);

    expect(find.text('Could not reach the server. Check your connection and try again.'), findsOneWidget);
    expect(find.byKey(const Key('profile-first-name')), findsNothing);

    fake.failGetWith = null;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(fake.getCalls, 2);
    expect(fieldText(tester, const Key('profile-first-name')), 'Asha');
  });

  testWidgets('a teacher sees their details, address and work details', (tester) async {
    await pumpScreen(tester, FakeProfileRepository());

    expect(find.text('My Profile'), findsOneWidget);
    expect(fieldText(tester, const Key('profile-first-name')), 'Asha');
    expect(fieldText(tester, const Key('profile-last-name')), 'Rao');
    expect(tester.widget<TextFormField>(mobileInput()).controller!.text, '9876543210');
    expect(fieldText(tester, const Key('profile-address')), '12 Lake Road');
    expect(find.text('asha@example.com'), findsOneWidget);

    expect(find.text('Work details'), findsOneWidget);
    expect(find.text('EMP-042'), findsOneWidget);
    expect(find.text('Science'), findsOneWidget);
    expect(find.text('Senior Teacher'), findsOneWidget);
    expect(find.text('01/06/2024'), findsOneWidget);
    expect(find.text('Teacher'), findsOneWidget);
    expect(find.text('Green Valley School'), findsOneWidget);
    expect(find.text("These are kept by your school's administrators."), findsOneWidget);

    // No photo: initials, and no way to remove what is not there.
    expect(find.text('AR'), findsOneWidget);
    expect(find.byKey(const Key('profile-remove-photo')), findsNothing);
  });

  testWidgets('a Super Admin has no address and no work card', (tester) async {
    await pumpScreen(tester, FakeProfileRepository(profile: superAdminProfile()));

    expect(fieldText(tester, const Key('profile-first-name')), 'Platform');
    expect(find.byKey(const Key('profile-address')), findsNothing);
    expect(find.text('Work details'), findsNothing);
    expect(find.text("These are kept by your school's administrators."), findsNothing);
    expect(find.text('owner@example.com'), findsOneWidget);
    expect(find.text('Change password'), findsOneWidget);
    expect(find.text('Signed-in devices'), findsOneWidget);
  });

  testWidgets('Save waits for a change, then sends only the changed field', (tester) async {
    final fake = FakeProfileRepository();
    await pumpScreen(tester, fake);

    expect(saveButton(tester).onPressed, isNull);

    await tester.enterText(find.byKey(const Key('profile-last-name')), 'Rao-Iyer');
    await tester.pump();
    expect(saveButton(tester).onPressed, isNotNull);

    // Typing it back the way it was is not a change.
    await tester.enterText(find.byKey(const Key('profile-last-name')), 'Rao');
    await tester.pump();
    expect(saveButton(tester).onPressed, isNull);

    await tester.enterText(find.byKey(const Key('profile-last-name')), 'Rao-Iyer');
    await tester.pump();
    await tapSave(tester);

    expect(fake.lastUpdate, {'last_name': 'Rao-Iyer'});
    expect(find.text('Profile updated.'), findsOneWidget);
    // Saved: nothing differs any more.
    expect(saveButton(tester).onPressed, isNull);
  });

  testWidgets('clearing the mobile and address sends them empty', (tester) async {
    final fake = FakeProfileRepository();
    await pumpScreen(tester, fake);

    await tester.enterText(mobileInput(), '');
    await tester.enterText(find.byKey(const Key('profile-address')), '');
    await tester.pump();
    await tapSave(tester);

    expect(fake.lastUpdate, {'mobile': '', 'address': ''});
  });

  testWidgets('refuses bad values before they reach the server', (tester) async {
    final fake = FakeProfileRepository();
    await pumpScreen(tester, fake);

    await tester.enterText(find.byKey(const Key('profile-first-name')), '');
    await tester.enterText(find.byKey(const Key('profile-last-name')), 'x' * 101);
    await tester.enterText(find.byKey(const Key('profile-address')), 'y' * 501);
    await tester.pump();
    await tapSave(tester);

    expect(find.text('First name is required'), findsOneWidget);
    expect(find.text('Last name must be 100 characters or fewer'), findsOneWidget);
    expect(find.text('Home address must be 500 characters or fewer'), findsOneWidget);
    expect(fake.updateCalls, 0);
  });

  testWidgets('a mobile number too short for its country is refused', (tester) async {
    final fake = FakeProfileRepository();
    await pumpScreen(tester, fake);

    await tester.enterText(mobileInput(), '12345');
    await tester.pump();
    await tapSave(tester);

    expect(find.textContaining('numbers are 10 digits'), findsOneWidget);
    expect(fake.updateCalls, 0);
  });

  testWidgets('a field the server refuses shows its message under that field', (tester) async {
    final fake = FakeProfileRepository(
      failUpdateWith: fieldFailure('first_name', 'The first name field must not be greater than 100 characters.'),
    );
    await pumpScreen(tester, fake);

    await tester.enterText(find.byKey(const Key('profile-first-name')), 'Ashaa');
    await tester.pump();
    await tapSave(tester);

    final field = find.byKey(const Key('profile-first-name'));
    expect(
      find.descendant(of: field, matching: find.text('The first name field must not be greater than 100 characters.')),
      findsOneWidget,
    );
    expect(find.text('Profile updated.'), findsNothing);
  });

  testWidgets('a mobile the server refuses shows its message under the mobile field', (tester) async {
    final fake = FakeProfileRepository(
      failUpdateWith: fieldFailure('mobile', 'Enter the mobile as +<country code> <number>.'),
    );
    await pumpScreen(tester, fake);

    await tester.enterText(mobileInput(), '9876543211');
    await tester.pump();
    await tapSave(tester);

    expect(find.text('Enter the mobile as +<country code> <number>.'), findsOneWidget);
  });

  testWidgets('a refusal with no field is shown on the form', (tester) async {
    final fake = FakeProfileRepository(
      failUpdateWith: const Failure(code: 'NO_STAFF_RECORD', message: 'You have no staff record to add an address to.'),
    );
    await pumpScreen(tester, fake);

    await tester.enterText(find.byKey(const Key('profile-address')), '14 Hill Street');
    await tester.pump();
    await tapSave(tester);

    expect(find.text('You have no staff record to add an address to.'), findsOneWidget);
  });

  group('changing the sign-in email', () {
    testWidgets('both fields are required and the email must look like one', (tester) async {
      final fake = FakeProfileRepository();
      await pumpScreen(tester, fake);
      await openChangeEmail(tester);

      await submitChangeEmail(tester);
      expect(find.text('Enter the new email'), findsOneWidget);
      expect(find.text('Enter your current password'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('change-email-new')), 'not-an-email');
      await submitChangeEmail(tester);
      expect(find.text('Enter a valid email'), findsOneWidget);

      expect(fake.lastEmailChange, isNull);
      expect(find.byType(AlertDialog), findsOneWidget);
    });

    testWidgets('success closes the dialog, says so and shows the new email', (tester) async {
      final fake = FakeProfileRepository();
      await pumpScreen(tester, fake);
      await openChangeEmail(tester);

      await tester.enterText(find.byKey(const Key('change-email-new')), ' asha.rao@example.com ');
      await tester.enterText(emailPasswordInput(), 'secret-1');
      await submitChangeEmail(tester);

      expect(fake.lastEmailChange, (email: 'asha.rao@example.com', currentPassword: 'secret-1'));
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Email changed. Other devices have been signed out.'), findsOneWidget);
      expect(find.text('asha.rao@example.com'), findsOneWidget);
    });

    testWidgets('a wrong password is shown under the password and the dialog stays open', (tester) async {
      final fake = FakeProfileRepository(
        failEmailWith: fieldFailure('current_password', 'That is not your current password.'),
      );
      await pumpScreen(tester, fake);
      await openChangeEmail(tester);

      await tester.enterText(find.byKey(const Key('change-email-new')), 'asha.rao@example.com');
      await tester.enterText(emailPasswordInput(), 'wrong');
      await submitChangeEmail(tester);

      final dialog = find.byType(AlertDialog);
      expect(dialog, findsOneWidget);
      expect(find.descendant(of: dialog, matching: find.text('That is not your current password.')), findsOneWidget);
      expect(find.text('asha@example.com'), findsWidgets);
    });

    testWidgets('an address already taken is shown under the email field', (tester) async {
      final fake = FakeProfileRepository(failEmailWith: fieldFailure('email', 'The email has already been taken.'));
      await pumpScreen(tester, fake);
      await openChangeEmail(tester);

      await tester.enterText(find.byKey(const Key('change-email-new')), 'taken@example.com');
      await tester.enterText(emailPasswordInput(), 'secret-1');
      await submitChangeEmail(tester);

      expect(
        find.descendant(
          of: find.byKey(const Key('change-email-new')),
          matching: find.text('The email has already been taken.'),
        ),
        findsOneWidget,
      );

      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
    });
  });

  group('the photo', () {
    testWidgets('outside the web app the upload button is replaced by a note', (tester) async {
      await pumpScreen(tester, FakeProfileRepository());

      expect(find.text('Photos can be uploaded from the web app for now.'), findsOneWidget);
      expect(find.byKey(const Key('profile-upload-photo')), findsNothing);
    });

    testWidgets('removing it asks first, and Cancel keeps it', (tester) async {
      final fake = FakeProfileRepository(profile: teacherProfile(photoUrl: '/users/12/photo?v=old'));
      await pumpScreen(tester, fake);

      await tester.tap(find.byKey(const Key('profile-remove-photo')));
      await tester.pumpAndSettle();

      expect(find.text('Remove photo?'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(fake.removeCalls, 0);
      expect(find.byKey(const Key('profile-remove-photo')), findsOneWidget);
    });

    testWidgets('removing it once confirmed clears it and says so', (tester) async {
      final fake = FakeProfileRepository(profile: teacherProfile(photoUrl: '/users/12/photo?v=old'));
      await pumpScreen(tester, fake);

      await tester.tap(find.byKey(const Key('profile-remove-photo')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Remove photo'));
      await tester.pumpAndSettle();

      expect(fake.removeCalls, 1);
      expect(find.text('Photo removed.'), findsOneWidget);
      expect(find.byKey(const Key('profile-remove-photo')), findsNothing);
    });

    testWidgets('a failed removal is shown under the photo', (tester) async {
      final fake = FakeProfileRepository(profile: teacherProfile(photoUrl: '/users/12/photo?v=old'))
        ..failRemoveWith = Failure.network();
      await pumpScreen(tester, fake);

      await tester.tap(find.byKey(const Key('profile-remove-photo')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Remove photo'));
      await tester.pumpAndSettle();

      expect(find.text('Could not reach the server. Check your connection and try again.'), findsOneWidget);
      expect(find.byKey(const Key('profile-remove-photo')), findsOneWidget);
    });
  });

  testWidgets('Change password opens the shared password dialog', (tester) async {
    await pumpScreen(tester, FakeProfileRepository());

    await tester.ensureVisible(find.text('Change password'));
    await tester.tap(find.text('Change password'));
    await tester.pumpAndSettle();
    expect(find.text('Choose a new password for your account.'), findsOneWidget);
  });

  testWidgets('fits a phone: the cards stack and nothing overflows', (tester) async {
    usePhone(tester);
    await tester.pumpWidget(wrap(FakeProfileRepository()));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('profile-first-name')), findsOneWidget);
    expect(find.text('Work details'), findsOneWidget);
  });

  testWidgets('a bus attendant sees no placeholder email and no password or email changes', (tester) async {
    await pumpScreen(tester, FakeProfileRepository(profile: attendantProfile()));

    expect(find.text('No email on record'), findsOneWidget);
    expect(find.textContaining('Your school office keeps your email address'), findsOneWidget);
    expect(find.byKey(const Key('profile-change-email')), findsNothing);
    expect(find.text('Change password'), findsNothing);
    expect(find.text('Signed-in devices'), findsOneWidget);
    expect(find.textContaining('no-email.invalid'), findsNothing);
  });
}
