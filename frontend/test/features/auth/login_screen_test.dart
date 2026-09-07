import 'dart:async';

import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/auth/presentation/login_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_auth_repository.dart';

Widget wrap(Widget child, FakeAuthRepository fake) {
  return ProviderScope(
    overrides: [authRepositoryProvider.overrideWithValue(fake)],
    child: MaterialApp(home: child),
  );
}

void main() {
  testWidgets('shows validation errors when submitting an empty form', (tester) async {
    await tester.pumpWidget(wrap(const LoginScreen(), FakeAuthRepository()));

    await tester.tap(find.widgetWithText(ElevatedButton, 'Sign In'));
    await tester.pump();

    expect(find.text('Email is required'), findsOneWidget);
    expect(find.text('Password is required'), findsOneWidget);
  });

  testWidgets('shows a loading spinner on the button while logging in', (tester) async {
    final gate = Completer<void>();
    await tester.pumpWidget(wrap(const LoginScreen(), FakeAuthRepository(loginGate: gate)));

    await tester.enterText(find.widgetWithText(TextFormField, 'Email'), 'test@example.com');
    await tester.enterText(find.widgetWithText(TextFormField, 'Password'), 'password');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Sign In'));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    gate.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('shows an error message when login fails', (tester) async {
    final fake = FakeAuthRepository(
      failLoginWith: const Failure(
        code: 'UNAUTHENTICATED',
        message: 'These credentials do not match our records.',
      ),
    );
    await tester.pumpWidget(wrap(const LoginScreen(), fake));

    await tester.enterText(find.widgetWithText(TextFormField, 'Email'), 'test@example.com');
    await tester.enterText(find.widgetWithText(TextFormField, 'Password'), 'wrong-password');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Sign In'));
    await tester.pumpAndSettle();

    expect(find.text('These credentials do not match our records.'), findsOneWidget);
  });
}
