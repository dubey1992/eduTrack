import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/auth/presentation/forgot_password_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_auth_repository.dart';

Widget wrap(FakeAuthRepository fake) {
  return ProviderScope(
    overrides: [authRepositoryProvider.overrideWithValue(fake)],
    child: MaterialApp(theme: AppTheme.light(), home: const ForgotPasswordScreen()),
  );
}

void main() {
  testWidgets('validates the email field', (tester) async {
    await tester.pumpWidget(wrap(FakeAuthRepository()));

    await tester.tap(find.widgetWithText(ElevatedButton, 'Send Reset Link'));
    await tester.pump();

    expect(find.text('Enter a valid email'), findsOneWidget);
  });

  testWidgets('shows a generic confirmation message after submitting', (tester) async {
    await tester.pumpWidget(wrap(FakeAuthRepository()));

    await tester.enterText(find.widgetWithText(TextFormField, 'Email'), 'test@example.com');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Send Reset Link'));
    await tester.pumpAndSettle();

    expect(
      find.text('If an account exists for that email, a password reset link has been sent.'),
      findsOneWidget,
    );
  });
}
