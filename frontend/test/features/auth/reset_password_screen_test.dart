import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/auth/presentation/reset_password_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../support/fake_auth_repository.dart';

Widget wrap(FakeAuthRepository fake) {
  return ProviderScope(
    overrides: [authRepositoryProvider.overrideWithValue(fake)],
    child: MaterialApp.router(
      routerConfig: GoRouter(
        initialLocation: '/reset-password',
        routes: [
          GoRoute(
            path: '/reset-password',
            builder: (context, state) =>
                const ResetPasswordScreen(email: 'test@example.com', token: 'a-valid-token'),
          ),
          GoRoute(
            path: '/login',
            builder: (context, state) => const Scaffold(body: Text('Login Screen')),
          ),
        ],
      ),
    ),
  );
}

void main() {
  testWidgets('requires matching passwords', (tester) async {
    await tester.pumpWidget(wrap(FakeAuthRepository()));

    await tester.enterText(find.widgetWithText(TextFormField, 'New password'), 'password123');
    await tester.enterText(find.widgetWithText(TextFormField, 'Confirm password'), 'different123');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Reset Password'));
    await tester.pump();

    expect(find.text('Passwords do not match'), findsOneWidget);
  });

  testWidgets('navigates to login after a successful reset', (tester) async {
    await tester.pumpWidget(wrap(FakeAuthRepository()));

    await tester.enterText(find.widgetWithText(TextFormField, 'New password'), 'password123');
    await tester.enterText(find.widgetWithText(TextFormField, 'Confirm password'), 'password123');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Reset Password'));
    await tester.pumpAndSettle();

    expect(find.text('Login Screen'), findsOneWidget);
  });
}
