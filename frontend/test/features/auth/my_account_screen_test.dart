import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/storage/key_value_store.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/auth/data/models/authenticated_user.dart';
import 'package:edutrack_app/features/auth/presentation/my_account_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_auth_repository.dart';
import '../../support/in_memory_key_value_store.dart';

const _admin = AuthenticatedUser(id: 1, name: 'Priya Sharma', email: 'priya@example.com', role: UserRole.schoolAdmin);

/// Settings > My Account (2026-11-21): the account's actions that used to be
/// icons in the top bar.
void main() {
  Future<FakeAuthRepository> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final fake = FakeAuthRepository(sessionOnRestore: _admin);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(fake),
          keyValueStoreProvider.overrideWithValue(InMemoryKeyValueStore()),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: MyAccountScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return fake;
  }

  testWidgets('offers the devices, a new password and logging out', (tester) async {
    await pump(tester);

    expect(find.byKey(const Key('account-devices')), findsOneWidget);
    expect(find.byKey(const Key('account-password')), findsOneWidget);
    expect(find.byKey(const Key('account-logout')), findsOneWidget);
  });

  testWidgets('a new password opens its dialog', (tester) async {
    await pump(tester);

    await tester.tap(
      find.descendant(of: find.byKey(const Key('account-password')), matching: find.byType(OutlinedButton)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Choose a new password for your account.'), findsOneWidget);
  });

  testWidgets('logging out asks first, and goes on yes', (tester) async {
    final fake = await pump(tester);

    await tester.tap(
      find.descendant(of: find.byKey(const Key('account-logout')), matching: find.byType(OutlinedButton)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Log out?'), findsOneWidget);
    expect(fake.loggedOutCalled, isFalse);

    await tester.tap(find.widgetWithText(FilledButton, 'Log out'));
    await tester.pumpAndSettle();
    expect(fake.loggedOutCalled, isTrue);
  });
}
