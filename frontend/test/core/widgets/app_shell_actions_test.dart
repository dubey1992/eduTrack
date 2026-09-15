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

const _admin = AuthenticatedUser(id: 1, name: 'Priya Sharma', email: 'priya@example.com', role: UserRole.schoolAdmin);

/// The two header actions that sit one pixel apart: change password, and the
/// one that throws away the session.
void main() {
  Widget wrap(FakeAuthRepository fake) {
    return ProviderScope(
      overrides: [authRepositoryProvider.overrideWithValue(fake)],
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

  group('logging out', () {
    testWidgets('asks before throwing the session away', (tester) async {
      final fake = FakeAuthRepository(sessionOnRestore: _admin);
      await pumpShell(tester, fake);

      await tester.tap(find.byTooltip('Log out'));
      await tester.pumpAndSettle();

      expect(find.text('Log out?'), findsOneWidget);
      expect(find.text('You will need to sign in again to get back to your school.'), findsOneWidget);
      // Nothing has happened yet.
      expect(fake.loggedOutCalled, isFalse);
    });

    testWidgets('does not log out when the answer is no', (tester) async {
      final fake = FakeAuthRepository(sessionOnRestore: _admin);
      await pumpShell(tester, fake);

      await tester.tap(find.byTooltip('Log out'));
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

      await tester.tap(find.byTooltip('Log out'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Log out'));
      await tester.pumpAndSettle();

      expect(fake.loggedOutCalled, isTrue);
    });

    testWidgets('dismissing the question counts as no', (tester) async {
      final fake = FakeAuthRepository(sessionOnRestore: _admin);
      await pumpShell(tester, fake);

      await tester.tap(find.byTooltip('Log out'));
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

      await tester.tap(find.byTooltip('Change password'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Change Password'), findsWidgets);
      expect(find.text('Choose a new password for your account.'), findsOneWidget);
      // Still on the page they were on - that is the point of the change.
      expect(find.text('The page behind'), findsOneWidget);
    });

    testWidgets('carries all three fields, each hiding what is typed', (tester) async {
      await pumpShell(tester, FakeAuthRepository(sessionOnRestore: _admin));

      await tester.tap(find.byTooltip('Change password'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(TextFormField, 'Current password'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'New password'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Confirm new password'), findsOneWidget);
      expect(find.byIcon(Icons.visibility_outlined), findsNWidgets(3));
    });

    testWidgets('validates before sending anything', (tester) async {
      final fake = FakeAuthRepository(sessionOnRestore: _admin);
      await pumpShell(tester, fake);

      await tester.tap(find.byTooltip('Change password'));
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

      await tester.tap(find.byTooltip('Change password'));
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

      await tester.tap(find.byTooltip('Change password'));
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

      await tester.tap(find.byTooltip('Change password'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(fake.changedTo, isNull);
    });
  });
}
