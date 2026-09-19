import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/auth/data/models/authenticated_user.dart';
import 'package:edutrack_app/features/users/data/models/app_user.dart';
import 'package:edutrack_app/features/users/data/user_repository.dart';
import 'package:edutrack_app/features/users/presentation/edit_user_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_auth_repository.dart';
import '../../support/fake_user_repository.dart';

const _schoolAdmin = AuthenticatedUser(id: 5, name: 'Admin', email: 'admin@example.com', role: UserRole.schoolAdmin);

const _teacher = AppUser(
  id: 10,
  firstName: 'Asha',
  lastName: 'Verma',
  name: 'Asha Verma',
  email: 'asha.verma@example.com',
  mobile: null,
  role: UserRole.teacher,
  status: UserStatus.active,
);

// Opened via a real showDialog route (rather than placed directly as the
// Scaffold body) because EditUserDialog pops itself on success. A plain
// Navigator.pop() on a route-less body empties the app's entire (sole) route
// instead of just the dialog, which tears down the Scaffold - and the
// SnackBar it was about to show - before the test can observe either.
Widget wrap(FakeUserRepository fake, {AppUser user = _teacher, AuthenticatedUser actor = _schoolAdmin}) {
  return ProviderScope(
    overrides: [
      authRepositoryProvider.overrideWithValue(FakeAuthRepository(sessionOnRestore: actor)),
      userRepositoryProvider.overrideWithValue(fake),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showDialog(
              context: context,
              builder: (_) => EditUserDialog(user: user),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('shows a validation error when first name is cleared', (tester) async {
    await tester.pumpWidget(wrap(FakeUserRepository(users: [_teacher])));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextFormField, 'First name'), '');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('First name is required'), findsOneWidget);
  });

  testWidgets('submits successfully and closes the dialog', (tester) async {
    final fake = FakeUserRepository(users: [_teacher]);
    await tester.pumpWidget(wrap(fake));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextFormField, 'First name'), 'Asha Marie');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final updated = await fake.list();
    expect(updated.firstWhere((u) => u.id == _teacher.id).firstName, 'Asha Marie');
    expect(find.byType(EditUserDialog), findsNothing);
    expect(find.text('User updated.'), findsOneWidget);
  });

  testWidgets('shows the failure message and keeps the dialog open on error', (tester) async {
    final fake = FakeUserRepository(
      users: [_teacher],
      failUpdateWith: const Failure(code: 'USER_EMAIL_TAKEN', message: 'That email is already in use.'),
    );
    await tester.pumpWidget(wrap(fake));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('That email is already in use.'), findsOneWidget);
    expect(find.byType(EditUserDialog), findsOneWidget);
  });

  group('Bus Attendants', () {
    const attendant = AppUser(
      id: 131,
      firstName: 'Meera',
      lastName: 'Sharma',
      name: 'Meera Sharma',
      email: 'attendant-1a2b@no-email.invalid',
      hasEmail: false,
      mobile: '+91 9876543210',
      role: UserRole.busAttendant,
      status: UserStatus.active,
    );
    const superAdmin = AuthenticatedUser(id: 1, name: 'Root', email: 'root@example.com', role: UserRole.superAdmin);

    testWidgets('nobody can be made a Bus Attendant by an edit, even by a Super Admin', (tester) async {
      await tester.pumpWidget(wrap(FakeUserRepository(users: [_teacher]), actor: superAdmin));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(DropdownButtonFormField<UserRole>, 'Teacher'));
      await tester.pumpAndSettle();

      expect(find.text('Accountant'), findsWidgets);
      expect(find.text('Bus Attendant'), findsNothing);
    });

    testWidgets('an attendant\'s role is shown but cannot be changed, and there is no password', (tester) async {
      await tester.pumpWidget(
        wrap(
          FakeUserRepository(users: [attendant]),
          user: attendant,
          actor: superAdmin,
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.byType(DropdownButtonFormField<UserRole>), findsNothing);
      expect(find.text('Bus Attendant'), findsOneWidget);
      expect(find.text('A Bus Attendant signs in differently, so this role cannot be changed.'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'New password'), findsNothing);
    });

    testWidgets('the placeholder address is never shown, and an empty email is left alone', (tester) async {
      final fake = FakeUserRepository(users: [attendant]);
      await tester.pumpWidget(wrap(fake, user: attendant));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.textContaining('no-email.invalid'), findsNothing);
      expect(find.widgetWithText(TextFormField, 'Email (optional)'), findsOneWidget);

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final saved = (await fake.list()).single;
      expect(saved.email, attendant.email); // not sent, so unchanged
      expect(saved.role, UserRole.busAttendant);
      expect(find.text('User updated.'), findsOneWidget);
    });
  });
}
