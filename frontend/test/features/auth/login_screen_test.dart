import 'dart:async';

import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/network/dio_client.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/auth/presentation/login_screen.dart';
import 'package:edutrack_app/features/auth/presentation/widgets/website_links.dart';
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
    await tester.tap(find.text('Remember me'));
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
    final checkbox = tester.widget<Checkbox>(find.byType(Checkbox));
    expect(checkbox.value, isTrue);
  });

  group('the redesigned page (2026-11-06)', () {
    late List<Uri> opened;

    setUp(() {
      opened = [];
      WebsiteLinks.opener = (address) async => opened.add(address);
    });

    void useDesktop(WidgetTester tester) {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }

    testWidgets('says what it is and which account it wants', (tester) async {
      await tester.pumpWidget(wrap(const LoginScreen(), FakeAuthRepository()));
      await tester.pumpAndSettle();

      expect(find.text('Sign in to School365ai'), findsOneWidget);
      expect(find.text('Use the email and password your school set up for you.'), findsOneWidget);
      expect(find.text('Welcome Back'), findsNothing);
    });

    testWidgets('lets the browser fill in a saved email and password', (tester) async {
      await tester.pumpWidget(wrap(const LoginScreen(), FakeAuthRepository()));
      await tester.pumpAndSettle();

      final fields = tester.widgetList<TextField>(find.byType(TextField)).toList();

      expect(fields[0].autofillHints, contains(AutofillHints.email));
      expect(fields[1].autofillHints, contains(AutofillHints.password));
      expect(find.byType(AutofillGroup), findsOneWidget);
    });

    testWidgets('on a wide screen, explains who signs in where, beside a picture of the app', (tester) async {
      useDesktop(tester);
      await tester.pumpWidget(wrap(const LoginScreen(), FakeAuthRepository()));
      await tester.pumpAndSettle();

      expect(find.text('Smarter Schools. Brighter Futures.'), findsOneWidget);
      expect(find.text('Run your whole school day from one sign-in.'), findsOneWidget);
      expect(find.byKey(const Key('who-signs-in')), findsOneWidget);
      for (final who in ['School staff. ', 'Bus attendants. ', 'Parents. ']) {
        expect(find.textContaining(who, findRichText: true), findsOneWidget, reason: who);
      }
      expect(find.byType(Image), findsOneWidget);
      // The form itself is still reachable alongside the panel.
      expect(find.widgetWithText(TextFormField, 'Email'), findsOneWidget);
    });

    testWidgets('the logo takes you to the website', (tester) async {
      useDesktop(tester);
      await tester.pumpWidget(wrap(const LoginScreen(), FakeAuthRepository()));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Go to the School365ai website'), findsOneWidget);
      await tester.tap(find.byKey(const Key('login-logo')));
      await tester.pump();

      expect(opened.single.path, '/');
    });

    testWidgets('a new school can book a demo, and anyone stuck can ask on WhatsApp', (tester) async {
      useDesktop(tester);
      await tester.pumpWidget(wrap(const LoginScreen(), FakeAuthRepository()));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('login-book-demo')));
      await tester.tap(find.byKey(const Key('login-whatsapp-help')));
      await tester.pump();

      expect(opened.first.fragment, 'request-a-demo');
      expect(opened.last.toString(), startsWith('https://wa.me/919205313831?text='));
    });

    testWidgets("the bus attendant's way in is a real button", (tester) async {
      await tester.pumpWidget(wrap(const LoginScreen(), FakeAuthRepository()));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(OutlinedButton, 'Bus attendant? Sign in with your mobile number'), findsOneWidget);
    });

    testWidgets('on a phone, the form comes first, under the logo, with a word for parents', (tester) async {
      await tester.pumpWidget(wrap(const LoginScreen(), FakeAuthRepository()));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('who-signs-in')), findsNothing);
      expect(find.text('Smarter Schools. Brighter Futures.'), findsNothing);
      expect(find.byKey(const Key('login-logo')), findsOneWidget);
      expect(find.textContaining("Parent? You don't need to sign in."), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Email'), findsOneWidget);
    });
  });
}
