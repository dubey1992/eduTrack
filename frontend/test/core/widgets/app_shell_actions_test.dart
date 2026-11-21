import 'package:edutrack_app/core/storage/key_value_store.dart';
import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/core/widgets/app_shell.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/auth/data/models/authenticated_user.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../support/fake_auth_repository.dart';
import '../../support/in_memory_key_value_store.dart';

const _admin = AuthenticatedUser(id: 1, name: 'Priya Sharma', email: 'priya@example.com', role: UserRole.schoolAdmin);

/// The two header actions that sit one pixel apart: change password, and the
/// one that throws away the session.
void main() {
  Widget wrap(FakeAuthRepository fake) {
    return ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(fake),
        // Signing out clears what the phone keeps; this stands in for it.
        keyValueStoreProvider.overrideWithValue(InMemoryKeyValueStore()),
      ],
      child: MaterialApp.router(
        theme: AppTheme.light(),
        routerConfig: GoRouter(
          initialLocation: '/students',
          routes: [
            ShellRoute(
              builder: (context, state, child) => AppShell(child: child),
              routes: [
                GoRoute(
                  path: '/students',
                  builder: (context, state) => const Scaffold(body: Text('The page behind')),
                ),
                GoRoute(
                  path: '/profile',
                  builder: (context, state) => const Scaffold(body: Text('The profile page')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> pumpShell(WidgetTester tester, FakeAuthRepository fake) async {
    // Desktop: below the breakpoint the header actions move behind a drawer.
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(wrap(fake));
    await tester.pumpAndSettle();
  }

  /// The account's actions live behind the name in the top bar (2026-11-21).
  Future<void> chooseFromAccountMenu(WidgetTester tester, String key) async {
    await tester.tap(find.byKey(const Key('header-profile-chip')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key(key)));
    await tester.pumpAndSettle();
  }

  group('the top bar (2026-11-21)', () {
    testWidgets('carries no account icons - they are in the menu behind the name', (tester) async {
      await pumpShell(tester, FakeAuthRepository(sessionOnRestore: _admin));

      expect(find.byTooltip('Log out'), findsNothing);
      expect(find.byTooltip('Change password'), findsNothing);
      expect(find.byTooltip('Signed-in devices'), findsNothing);

      await tester.tap(find.byKey(const Key('header-profile-chip')));
      await tester.pumpAndSettle();

      for (final label in ['My profile', 'Signed-in devices', 'Change password', 'Log out']) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
    });

    testWidgets("the school's logo sits in the corner for someone at a school", (tester) async {
      // A teacher: a School Admin without a logo would be asked for one first.
      const atSchool = AuthenticatedUser(
        id: 1,
        name: 'Priya Sharma',
        email: 'priya@example.com',
        role: UserRole.teacher,
        schoolId: 4,
        schoolName: 'Green Valley School',
      );
      await pumpShell(tester, FakeAuthRepository(sessionOnRestore: atSchool));

      expect(find.byKey(const Key('header-school-logo')), findsOneWidget);
      expect(find.byTooltip('Green Valley School'), findsOneWidget);

      // A school's screens ask the (fake) server for the year and retry
      // after a pause; let that pause run out before the test ends.
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(minutes: 1));
    });

    testWidgets('and none for the platform staff, who belong to no school', (tester) async {
      await pumpShell(tester, FakeAuthRepository(sessionOnRestore: _admin));

      expect(find.byKey(const Key('header-school-logo')), findsNothing);
    });
  });

  group('logging out', () {
    testWidgets('asks before throwing the session away', (tester) async {
      final fake = FakeAuthRepository(sessionOnRestore: _admin);
      await pumpShell(tester, fake);

      await chooseFromAccountMenu(tester, 'account-menu-logout');
      await tester.pumpAndSettle();

      expect(find.text('Log out?'), findsOneWidget);
      expect(find.text('You will need to sign in again to get back to your school.'), findsOneWidget);
      // Nothing has happened yet.
      expect(fake.loggedOutCalled, isFalse);
    });

    testWidgets('does not log out when the answer is no', (tester) async {
      final fake = FakeAuthRepository(sessionOnRestore: _admin);
      await pumpShell(tester, fake);

      await chooseFromAccountMenu(tester, 'account-menu-logout');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Stay signed in'));
      await tester.pumpAndSettle();

      expect(fake.loggedOutCalled, isFalse);
      expect(find.text('Log out?'), findsNothing);
      expect(find.text('The page behind'), findsOneWidget);
    });

    testWidgets('logs out when the answer is yes', (tester) async {
      final fake = FakeAuthRepository(sessionOnRestore: _admin);
      await pumpShell(tester, fake);

      await chooseFromAccountMenu(tester, 'account-menu-logout');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Log out'));
      await tester.pumpAndSettle();

      expect(fake.loggedOutCalled, isTrue);
    });

    testWidgets('dismissing the question counts as no', (tester) async {
      final fake = FakeAuthRepository(sessionOnRestore: _admin);
      await pumpShell(tester, fake);

      await chooseFromAccountMenu(tester, 'account-menu-logout');
      await tester.pumpAndSettle();

      // Tapping the barrier outside the dialog.
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();

      expect(find.text('Log out?'), findsNothing);
      expect(fake.loggedOutCalled, isFalse);
    });
  });

  group('changing a password', () {
    testWidgets('opens a dialog rather than navigating away', (tester) async {
      await pumpShell(tester, FakeAuthRepository(sessionOnRestore: _admin));

      await chooseFromAccountMenu(tester, 'account-menu-password');
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Change Password'), findsWidgets);
      expect(find.text('Choose a new password for your account.'), findsOneWidget);
      // Still on the page they were on - that is the point of the change.
      expect(find.text('The page behind'), findsOneWidget);
    });

    testWidgets('carries all three fields, each hiding what is typed', (tester) async {
      await pumpShell(tester, FakeAuthRepository(sessionOnRestore: _admin));

      await chooseFromAccountMenu(tester, 'account-menu-password');
      await tester.pumpAndSettle();

      expect(find.widgetWithText(TextFormField, 'Current password'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'New password'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Confirm new password'), findsOneWidget);
      expect(find.byIcon(Icons.visibility_outlined), findsNWidgets(3));
    });

    testWidgets('validates before sending anything', (tester) async {
      final fake = FakeAuthRepository(sessionOnRestore: _admin);
      await pumpShell(tester, fake);

      await chooseFromAccountMenu(tester, 'account-menu-password');
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextFormField, 'New password'), 'new-password-1');
      await tester.enterText(find.widgetWithText(TextFormField, 'Confirm new password'), 'different-1');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Change Password'));
      await tester.pumpAndSettle();

      expect(find.text('Enter your current password'), findsOneWidget);
      expect(find.text('Passwords do not match'), findsOneWidget);
      expect(fake.changedTo, isNull);
      expect(find.byType(AlertDialog), findsOneWidget);
    });

    testWidgets('closes and says so once the password is changed', (tester) async {
      final fake = FakeAuthRepository(sessionOnRestore: _admin);
      await pumpShell(tester, fake);

      await chooseFromAccountMenu(tester, 'account-menu-password');
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextFormField, 'Current password'), 'old-password-1');
      await tester.enterText(find.widgetWithText(TextFormField, 'New password'), 'new-password-1');
      await tester.enterText(find.widgetWithText(TextFormField, 'Confirm new password'), 'new-password-1');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Change Password'));
      await tester.pumpAndSettle();

      expect(fake.changedFrom, 'old-password-1');
      expect(fake.changedTo, 'new-password-1');
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Password changed.'), findsOneWidget);
      expect(find.text('The page behind'), findsOneWidget);
    });

    testWidgets('keeps the dialog open and shows what the server said', (tester) async {
      final fake = FakeAuthRepository(sessionOnRestore: _admin)
        ..failChangeWith = const Failure(code: 'VALIDATION_ERROR', message: 'That is not your current password.');
      await pumpShell(tester, fake);

      await chooseFromAccountMenu(tester, 'account-menu-password');
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextFormField, 'Current password'), 'wrong');
      await tester.enterText(find.widgetWithText(TextFormField, 'New password'), 'new-password-1');
      await tester.enterText(find.widgetWithText(TextFormField, 'Confirm new password'), 'new-password-1');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Change Password'));
      await tester.pumpAndSettle();

      expect(find.text('That is not your current password.'), findsOneWidget);
      expect(find.byType(AlertDialog), findsOneWidget);
    });

    testWidgets('Cancel closes it without changing anything', (tester) async {
      final fake = FakeAuthRepository(sessionOnRestore: _admin);
      await pumpShell(tester, fake);

      await chooseFromAccountMenu(tester, 'account-menu-password');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(fake.changedTo, isNull);
    });
  });

  group('the profile chip', () {
    testWidgets('shows the user with their initials when there is no photo', (tester) async {
      await pumpShell(tester, FakeAuthRepository(sessionOnRestore: _admin));

      final chip = find.byKey(const Key('header-profile-chip'));
      expect(find.descendant(of: chip, matching: find.text('Priya Sharma')), findsOneWidget);
      expect(find.descendant(of: chip, matching: find.text('PS')), findsOneWidget);
      expect(find.byTooltip('Your account'), findsOneWidget);
    });

    testWidgets('opens My Profile, titled as such without a sidebar entry', (tester) async {
      await pumpShell(tester, FakeAuthRepository(sessionOnRestore: _admin));

      await chooseFromAccountMenu(tester, 'account-menu-profile');

      expect(find.text('The profile page'), findsOneWidget);
      expect(find.text('My Profile'), findsOneWidget);
      expect(find.text('Your details, sign-in email and photo'), findsOneWidget);
    });

    testWidgets('on a phone the app bar carries the way to My Profile', (tester) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(wrap(FakeAuthRepository(sessionOnRestore: _admin)));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('header-profile-button')));
      await tester.pumpAndSettle();

      expect(find.text('The profile page'), findsOneWidget);
    });
  });
}
