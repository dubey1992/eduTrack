import 'dart:async';

import 'package:edutrack_app/features/my_inbox/data/my_inbox_repository.dart';
import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/network/dio_client.dart';
import 'package:edutrack_app/core/network/session_ended_notifier.dart';
import 'package:edutrack_app/core/routing/teacher_router.dart';
import 'package:edutrack_app/core/storage/key_value_store.dart';
import 'package:edutrack_app/core/widgets/teacher_mark.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/auth/data/models/authenticated_user.dart';
import 'package:edutrack_app/features/auth/presentation/teacher/teacher_change_password_screen.dart';
import 'package:edutrack_app/features/auth/presentation/teacher/teacher_forgot_password_screen.dart';
import 'package:edutrack_app/features/auth/presentation/teacher/teacher_sign_in_screen.dart';
import 'package:edutrack_app/features/auth/presentation/teacher/teacher_welcome_screen.dart';
import 'package:edutrack_app/features/auth/presentation/teacher_splash_screen.dart';
import 'package:edutrack_app/features/profile/data/profile_repository.dart';
import 'package:edutrack_app/features/check_in/data/check_in_repository.dart';
import 'package:edutrack_app/features/today/data/today_repository.dart';
import 'package:edutrack_app/features/today/presentation/today_screen.dart';
import 'package:edutrack_app/main_teacher.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_my_inbox_repository.dart';
import '../../support/fake_auth_repository.dart';
import '../../support/fake_auth_token_storage.dart';
import '../../support/fake_profile_repository.dart';
import '../../support/fake_check_in_repository.dart';
import '../../support/fake_today_repository.dart';
import '../../support/in_memory_key_value_store.dart';

/// The Teacher app's own splash, welcome, sign-in, password reset and forced
/// password change - phone screens, not the portal's page (docs/teacher-app.md).
///
/// Driven through the real app and router, so the redirects that move a
/// teacher between them are under test too.
const _teacher = AuthenticatedUser(id: 7, name: 'Asha Rao', email: 'asha@school.test', role: UserRole.teacher);

void main() {
  late FakeAuthTokenStorage storage;

  setUp(() => storage = FakeAuthTokenStorage());

  Widget app(FakeAuthRepository auth) {
    return ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(auth),
        authTokenStorageProvider.overrideWithValue(storage),
        keyValueStoreProvider.overrideWithValue(InMemoryKeyValueStore()),
        profileRepositoryProvider.overrideWithValue(FakeProfileRepository()),
        todayRepositoryProvider.overrideWithValue(FakeTodayRepository()),
        myInboxRepositoryProvider.overrideWithValue(FakeMyInboxRepository()),
        checkInRepositoryProvider.overrideWithValue(FakeCheckInRepository()),
      ],
      child: const TeacherApp(),
    );
  }

  Future<void> open(WidgetTester tester, FakeAuthRepository auth, {Size size = const Size(412, 915)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(app(auth));
    await tester.pump(teacherOpeningBeat + const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
  }

  Future<void> toSignIn(WidgetTester tester) async {
    await tester.ensureVisible(find.byKey(const Key('welcome-sign-in')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('welcome-sign-in')));
    await tester.pumpAndSettle();
  }

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  group('the splash', () {
    testWidgets('is the brand: the mark, the name and what it is doing', (tester) async {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(app(FakeAuthRepository()));
      await tester.pump(const Duration(milliseconds: 800));

      expect(find.byType(TeacherSplashScreen), findsOneWidget);
      expect(find.byKey(const Key('splash-mark')), findsOneWidget);
      expect(find.text('Your school day, in your pocket.'), findsOneWidget);
      expect(find.text('Getting your day ready…'), findsOneWidget);

      await tester.pump(teacherOpeningBeat);
      await tester.pumpAndSettle();
      expect(find.byType(TeacherSplashScreen), findsNothing);
    });

    testWidgets('offers to try again when the school cannot be reached', (tester) async {
      final auth = FakeAuthRepository(restoreGate: Completer<void>());
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(app(auth));
      await tester.pump(const Duration(seconds: 7));

      expect(find.byKey(const Key('splash-try-again')), findsOneWidget);
      expect(find.textContaining('Still trying to reach your school'), findsOneWidget);

      auth.restoreGate!.complete();
      await tester.pumpAndSettle();
    });
  });

  group('the welcome', () {
    testWidgets('says what the app does and leads to the sign-in', (tester) async {
      await open(tester, FakeAuthRepository());

      expect(find.byType(TeacherWelcomeScreen), findsOneWidget);
      expect(find.byType(TeacherMark), findsWidgets);
      for (final point in [
        'Check in at school',
        'Today at a glance',
        'Register and reports',
        "Your school's calendar",
      ]) {
        expect(find.text(point), findsOneWidget, reason: point);
      }

      await toSignIn(tester);
      expect(find.byType(TeacherSignInScreen), findsOneWidget);

      await tester.tap(find.byKey(const Key('auth-back')));
      await tester.pumpAndSettle();
      expect(find.byType(TeacherWelcomeScreen), findsOneWidget);
    });

    testWidgets('fits a small phone without overflowing', (tester) async {
      await open(tester, FakeAuthRepository(), size: const Size(320, 568));

      expect(tester.takeException(), isNull);
      await toSignIn(tester);
      expect(tester.takeException(), isNull);
    });
  });

  group('signing in', () {
    testWidgets('an empty form is refused field by field, without calling the server', (tester) async {
      final auth = FakeAuthRepository();
      await open(tester, auth);
      await toSignIn(tester);

      await tapVisible(tester, find.byKey(const Key('sign-in-submit')));

      expect(find.text('Enter your email.'), findsOneWidget);
      expect(find.text('Enter your password.'), findsOneWidget);
      expect(auth.loginEmail, isNull);
    });

    testWidgets('a malformed email is refused before it is sent', (tester) async {
      final auth = FakeAuthRepository();
      await open(tester, auth);
      await toSignIn(tester);

      await tester.enterText(find.byKey(const Key('sign-in-email')), 'asha.school.test');
      await tester.enterText(find.byKey(const Key('sign-in-password')), 'whatever1');
      await tapVisible(tester, find.byKey(const Key('sign-in-submit')));

      expect(find.text('That does not look like an email address.'), findsOneWidget);
      expect(auth.loginEmail, isNull);
    });

    testWidgets('a session the server ended signs out, and the sign-in says why', (tester) async {
      const teacher = AuthenticatedUser(id: 7, name: 'Asha', email: 'asha@school.test', role: UserRole.teacher);
      await open(tester, FakeAuthRepository(sessionOnRestore: teacher));
      expect(find.byType(TodayScreen), findsOneWidget);

      // What the network layer does when a request comes back 401.
      ProviderScope.containerOf(tester.element(find.byType(TeacherApp))).read(sessionEndedProvider.notifier).report();
      await tester.pumpAndSettle();

      expect(find.byType(TodayScreen), findsNothing);
      if (find.byType(TeacherSignInScreen).evaluate().isEmpty) await toSignIn(tester);
      expect(find.text(sessionEndedMessage), findsOneWidget);
    });

    testWidgets("the server's refusal is shown in a banner and the form stays", (tester) async {
      final auth = FakeAuthRepository(
        failLoginWith: const Failure(
          code: 'INVALID_CREDENTIALS',
          message: 'These credentials do not match our records.',
        ),
      );
      await open(tester, auth);
      await toSignIn(tester);

      await tester.enterText(find.byKey(const Key('sign-in-email')), 'asha@school.test');
      await tester.enterText(find.byKey(const Key('sign-in-password')), 'wrong-one-1');
      await tapVisible(tester, find.byKey(const Key('sign-in-submit')));

      expect(find.byKey(const Key('sign-in-error')), findsOneWidget);
      expect(find.text('These credentials do not match our records.'), findsOneWidget);
      expect(find.byType(TeacherSignInScreen), findsOneWidget);
    });

    testWidgets('a teacher lands on Today, and their email is remembered', (tester) async {
      final auth = FakeAuthRepository(loginAs: _teacher);
      await open(tester, auth);
      await toSignIn(tester);

      await tester.enterText(find.byKey(const Key('sign-in-email')), ' asha@school.test ');
      await tester.enterText(find.byKey(const Key('sign-in-password')), 'Correct-horse-1');
      await tapVisible(tester, find.byKey(const Key('sign-in-submit')));

      expect(auth.loginEmail, 'asha@school.test');
      expect(find.byType(TodayScreen), findsOneWidget);
      expect(await storage.readRememberedEmail(), 'asha@school.test');
    });

    testWidgets('a remembered email is filled in, and unticking forgets it', (tester) async {
      await storage.saveRememberedEmail('asha@school.test');
      final auth = FakeAuthRepository(loginAs: _teacher);
      await open(tester, auth);
      await toSignIn(tester);

      expect(find.text('asha@school.test'), findsOneWidget);

      await tapVisible(tester, find.byKey(const Key('sign-in-remember')));
      await tester.enterText(find.byKey(const Key('sign-in-password')), 'Correct-horse-1');
      await tapVisible(tester, find.byKey(const Key('sign-in-submit')));

      expect(await storage.readRememberedEmail(), isNull);
    });

    testWidgets('while the server is asked the button is busy and a second tap does nothing', (tester) async {
      final gate = Completer<void>();
      final auth = FakeAuthRepository(loginAs: _teacher, loginGate: gate);
      await open(tester, auth);
      await toSignIn(tester);

      await tester.enterText(find.byKey(const Key('sign-in-email')), 'asha@school.test');
      await tester.enterText(find.byKey(const Key('sign-in-password')), 'Correct-horse-1');
      await tester.ensureVisible(find.byKey(const Key('sign-in-submit')));
      await tester.tap(find.byKey(const Key('sign-in-submit')));
      await tester.pump();

      final button = tester.widget<FilledButton>(
        find.descendant(of: find.byKey(const Key('sign-in-submit')), matching: find.byType(FilledButton)),
      );
      expect(button.onPressed, isNull);
      expect(
        find.descendant(of: find.byKey(const Key('sign-in-submit')), matching: find.byType(CircularProgressIndicator)),
        findsOneWidget,
      );

      gate.complete();
      await tester.pumpAndSettle();
      expect(find.byType(TodayScreen), findsOneWidget);
    });

    testWidgets('somebody this app is not for is told where to go after signing in', (tester) async {
      await open(tester, FakeAuthRepository());
      await toSignIn(tester);

      await tester.enterText(find.byKey(const Key('sign-in-email')), 'office@school.test');
      await tester.enterText(find.byKey(const Key('sign-in-password')), 'Correct-horse-1');
      await tapVisible(tester, find.byKey(const Key('sign-in-submit')));

      // The fake signs in a Super Admin, who answers for every school.
      expect(find.text('Use the School365ai website'), findsOneWidget);
    });
  });

  group('a forgotten password', () {
    testWidgets('asks for the email, sends the link and says where it went', (tester) async {
      final auth = FakeAuthRepository();
      await open(tester, auth);
      await toSignIn(tester);
      await tapVisible(tester, find.byKey(const Key('sign-in-forgot')));

      expect(find.byType(TeacherForgotPasswordScreen), findsOneWidget);

      await tapVisible(tester, find.byKey(const Key('forgot-submit')));
      expect(find.text('Enter your email.'), findsOneWidget);
      expect(auth.forgotEmail, isNull);

      await tester.enterText(find.byKey(const Key('forgot-email')), 'asha+maths@school.test');
      await tapVisible(tester, find.byKey(const Key('forgot-submit')));

      expect(auth.forgotEmail, 'asha+maths@school.test');
      expect(find.byKey(const Key('forgot-sent')), findsOneWidget);
      expect(find.textContaining('asha+maths@school.test'), findsOneWidget);

      await tapVisible(tester, find.byKey(const Key('forgot-back-to-sign-in')));
      expect(find.byType(TeacherSignInScreen), findsOneWidget);
    });

    testWidgets('a failure is shown and the form stays', (tester) async {
      final auth = FakeAuthRepository(
        failForgotWith: const Failure(code: 'TOO_MANY_REQUESTS', message: 'Please wait before asking again.'),
      );
      await open(tester, auth);
      await toSignIn(tester);
      await tapVisible(tester, find.byKey(const Key('sign-in-forgot')));

      await tester.enterText(find.byKey(const Key('forgot-email')), 'asha@school.test');
      await tapVisible(tester, find.byKey(const Key('forgot-submit')));

      expect(find.byKey(const Key('forgot-error')), findsOneWidget);
      expect(find.text('Please wait before asking again.'), findsOneWidget);
      expect(find.byKey(const Key('forgot-sent')), findsNothing);
    });
  });

  group('a temporary password', () {
    const temporary = AuthenticatedUser(
      id: 7,
      name: 'Asha Rao',
      email: 'asha@school.test',
      role: UserRole.teacher,
      mustChangePassword: true,
    );

    testWidgets('holds the teacher on the change screen until they choose their own', (tester) async {
      final auth = FakeAuthRepository(sessionOnRestore: temporary)..sessionAfterChange = _teacher;
      await open(tester, auth);

      expect(find.byType(TeacherChangePasswordScreen), findsOneWidget);
      expect(find.byType(TodayScreen), findsNothing);

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'Temp-pass-123');
      await tester.enterText(fields.at(1), 'Chosen-pass-2026');
      await tester.enterText(fields.at(2), 'Chosen-pass-2026');
      await tapVisible(tester, find.text('Save password'));

      expect(auth.changedTo, 'Chosen-pass-2026');
      expect(find.byType(TodayScreen), findsOneWidget);
    });

    testWidgets('may sign out instead', (tester) async {
      final auth = FakeAuthRepository(sessionOnRestore: temporary);
      await open(tester, auth);

      await tapVisible(tester, find.byKey(const Key('change-password-sign-out')));

      expect(auth.loggedOutCalled, isTrue);
      expect(find.byType(TeacherWelcomeScreen), findsOneWidget);
    });
  });

  testWidgets('every signed-out screen holds up in dark mode', (tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

    await open(tester, FakeAuthRepository());
    expect(tester.takeException(), isNull);
    expect(Theme.of(tester.element(find.byType(TeacherWelcomeScreen))).brightness, Brightness.dark);

    await toSignIn(tester);
    expect(tester.takeException(), isNull);
  });
}
