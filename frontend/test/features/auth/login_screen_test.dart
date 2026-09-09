import 'dart:async';

import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/network/dio_client.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/auth/presentation/login_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_auth_repository.dart';
import '../../support/fake_auth_token_storage.dart';

Widget wrap(Widget child, FakeAuthRepository fake, {FakeAuthTokenStorage? tokenStorage}) {
  return ProviderScope(
    overrides: [
      authRepositoryProvider.overrideWithValue(fake),
      authTokenStorageProvider.overrideWithValue(tokenStorage ?? FakeAuthTokenStorage()),
    ],
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
      failLoginWith: const Failure(code: 'UNAUTHENTICATED', message: 'These credentials do not match our records.'),
    );
    await tester.pumpWidget(wrap(const LoginScreen(), fake));

    await tester.enterText(find.widgetWithText(TextFormField, 'Email'), 'test@example.com');
    await tester.enterText(find.widgetWithText(TextFormField, 'Password'), 'wrong-password');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Sign In'));
    await tester.pumpAndSettle();

    expect(find.text('These credentials do not match our records.'), findsOneWidget);
  });

  testWidgets('the password field is obscured by default and toggles visible on tap', (tester) async {
    await tester.pumpWidget(wrap(const LoginScreen(), FakeAuthRepository()));

    final passwordEditable = find.descendant(
      of: find.widgetWithText(TextFormField, 'Password'),
      matching: find.byType(EditableText),
    );
    expect(tester.widget<EditableText>(passwordEditable).obscureText, isTrue);

    await tester.tap(find.byIcon(Icons.visibility_outlined));
    await tester.pump();

    expect(tester.widget<EditableText>(passwordEditable).obscureText, isFalse);
    expect(find.byIcon(Icons.visibility_off_outlined), findsOneWidget);
  });

  testWidgets('checking Remember me saves the email for next time', (tester) async {
    final tokenStorage = FakeAuthTokenStorage();
    await tester.pumpWidget(wrap(const LoginScreen(), FakeAuthRepository(), tokenStorage: tokenStorage));

    await tester.enterText(find.widgetWithText(TextFormField, 'Email'), 'admin@example.com');
    await tester.enterText(find.widgetWithText(TextFormField, 'Password'), 'password');
    await tester.tap(find.widgetWithText(CheckboxListTile, 'Remember me'));
    await tester.tap(find.widgetWithText(ElevatedButton, 'Sign In'));
    await tester.pumpAndSettle();

    expect(await tokenStorage.readRememberedEmail(), 'admin@example.com');
  });

  testWidgets('leaving Remember me unchecked does not save the email', (tester) async {
    final tokenStorage = FakeAuthTokenStorage();
    await tester.pumpWidget(wrap(const LoginScreen(), FakeAuthRepository(), tokenStorage: tokenStorage));

    await tester.enterText(find.widgetWithText(TextFormField, 'Email'), 'admin@example.com');
    await tester.enterText(find.widgetWithText(TextFormField, 'Password'), 'password');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Sign In'));
    await tester.pumpAndSettle();

    expect(await tokenStorage.readRememberedEmail(), isNull);
  });

  testWidgets('a remembered email pre-fills the form and checks Remember me', (tester) async {
    final tokenStorage = FakeAuthTokenStorage();
    await tokenStorage.saveRememberedEmail('returning.admin@example.com');

    await tester.pumpWidget(wrap(const LoginScreen(), FakeAuthRepository(), tokenStorage: tokenStorage));
    await tester.pumpAndSettle();

    expect(find.text('returning.admin@example.com'), findsOneWidget);
    final checkbox = tester.widget<CheckboxListTile>(find.widgetWithText(CheckboxListTile, 'Remember me'));
    expect(checkbox.value, isTrue);
  });

  testWidgets('shows the brand panel with its feature checklist on a wide screen', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(wrap(const LoginScreen(), FakeAuthRepository()));
    await tester.pumpAndSettle();

    expect(find.text('Smarter Schools. Brighter Futures.'), findsOneWidget);
    expect(find.text('Easy to use'), findsOneWidget);
    // The form itself is still reachable alongside the brand panel.
    expect(find.widgetWithText(TextFormField, 'Email'), findsOneWidget);
  });

  testWidgets('hides the brand panel on a narrow (mobile) screen', (tester) async {
    await tester.pumpWidget(wrap(const LoginScreen(), FakeAuthRepository()));
    await tester.pumpAndSettle();

    expect(find.text('Smarter Schools. Brighter Futures.'), findsNothing);
    expect(find.widgetWithText(TextFormField, 'Email'), findsOneWidget);
  });
}
