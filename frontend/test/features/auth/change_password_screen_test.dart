import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/auth/data/models/authenticated_user.dart';
import 'package:edutrack_app/features/auth/presentation/change_password_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../support/fake_auth_repository.dart';

/// Where an imported account lands with its temporary password.
void main() {
  Widget wrap(FakeAuthRepository fake) {
    return ProviderScope(
      overrides: [authRepositoryProvider.overrideWithValue(fake)],
      child: MaterialApp.router(
        // The error message is painted from the app's own colour extension,
        // which only exists on the real theme.
        theme: AppTheme.light(),
        routerConfig: GoRouter(
          initialLocation: '/change-password',
          routes: [
            GoRoute(path: '/change-password', builder: (context, state) => const ChangePasswordScreen()),
            GoRoute(
              path: '/dashboard',
              builder: (context, state) => const Scaffold(body: Text('Dashboard')),
            ),
          ],
        ),
      ),
    );
  }

  /// A session that is being held on this screen.
  FakeAuthRepository holding() {
    return FakeAuthRepository(
      sessionOnRestore: const AuthenticatedUser(
        id: 1,
        name: 'Priya Nair',
        email: 'priya@example.com',
        role: UserRole.teacher,
        mustChangePassword: true,
      ),
    );
  }

  Future<void> fill(WidgetTester tester, {String current = 'Temp#1234', String password = 'new-password-1'}) async {
    await tester.enterText(find.widgetWithText(TextFormField, 'Current password'), current);
    await tester.enterText(find.widgetWithText(TextFormField, 'New password'), password);
    await tester.enterText(find.widgetWithText(TextFormField, 'Confirm new password'), password);
  }

  testWidgets('explains why an imported account is being held here', (tester) async {
    await tester.pumpWidget(wrap(holding()));
    await tester.pumpAndSettle();

    expect(
      find.text('Your account was set up with a temporary password. Choose your own to continue.'),
      findsOneWidget,
    );
    // Nowhere to go back to while the change is being required.
    expect(find.byType(BackButton), findsNothing);
  });

  testWidgets('asks for a password when the person is only visiting', (tester) async {
    final fake = FakeAuthRepository(
      sessionOnRestore: const AuthenticatedUser(
        id: 1,
        name: 'Priya Nair',
        email: 'priya@example.com',
        role: UserRole.teacher,
      ),
    );

    await tester.pumpWidget(wrap(fake));
    await tester.pumpAndSettle();

    expect(find.text('Choose a new password for your account.'), findsOneWidget);
    expect(find.text('Sign out instead'), findsNothing);
  });

  testWidgets('requires the current password', (tester) async {
    await tester.pumpWidget(wrap(holding()));
    await tester.pumpAndSettle();

    await fill(tester, current: '');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Change Password'));
    await tester.pump();

    expect(find.text('Enter your current password'), findsOneWidget);
  });

  testWidgets('requires the confirmation to match', (tester) async {
    await tester.pumpWidget(wrap(holding()));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextFormField, 'Current password'), 'Temp#1234');
    await tester.enterText(find.widgetWithText(TextFormField, 'New password'), 'new-password-1');
    await tester.enterText(find.widgetWithText(TextFormField, 'Confirm new password'), 'new-password-2');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Change Password'));
    await tester.pump();

    expect(find.text('Passwords do not match'), findsOneWidget);
  });

  testWidgets('sends both passwords and moves on', (tester) async {
    final fake = holding();

    await tester.pumpWidget(wrap(fake));
    await tester.pumpAndSettle();

    await fill(tester);
    await tester.tap(find.widgetWithText(ElevatedButton, 'Change Password'));
    await tester.pumpAndSettle();

    expect(fake.changedFrom, 'Temp#1234');
    expect(fake.changedTo, 'new-password-1');
    expect(find.text('Dashboard'), findsOneWidget);
  });

  testWidgets('shows what the server said and stays put', (tester) async {
    final fake = holding()
      ..failChangeWith = const Failure(code: 'VALIDATION_ERROR', message: 'That is not your current password.');

    await tester.pumpWidget(wrap(fake));
    await tester.pumpAndSettle();

    await fill(tester);
    await tester.tap(find.widgetWithText(ElevatedButton, 'Change Password'));
    await tester.pumpAndSettle();

    expect(find.text('That is not your current password.'), findsOneWidget);
    expect(find.text('Dashboard'), findsNothing);
  });

  testWidgets('offers a way out for somebody who cannot sign in', (tester) async {
    final fake = holding();

    await tester.pumpWidget(wrap(fake));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Sign out instead'));
    await tester.pumpAndSettle();

    expect(fake.loggedOutCalled, isTrue);
  });

  testWidgets('every password field hides what is typed', (tester) async {
    await tester.pumpWidget(wrap(holding()));
    await tester.pumpAndSettle();

    final fields = tester.widgetList<EditableText>(find.byType(EditableText));

    expect(fields.length, 3);
    expect(fields.every((field) => field.obscureText), isTrue);
    expect(find.byIcon(Icons.visibility_outlined), findsNWidgets(3));
  });
}
