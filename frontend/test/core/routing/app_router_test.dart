import 'dart:async';

import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/network/dio_client.dart';
import 'package:edutrack_app/core/routing/app_router.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/dashboard/data/dashboard_repository.dart';
import 'package:edutrack_app/features/auth/data/models/authenticated_user.dart';
import 'package:edutrack_app/features/auth/presentation/login_screen.dart';
import 'package:edutrack_app/features/classes/data/school_class_repository.dart';
import 'package:edutrack_app/features/students/data/student_repository.dart';
import 'package:edutrack_app/features/users/data/user_repository.dart';
import 'package:edutrack_app/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_auth_repository.dart';
import '../../support/fake_auth_token_storage.dart';
import '../../support/fake_school_class_repository.dart';
import '../../support/fake_student_repository.dart';
import '../../support/fake_dashboard_repository.dart';
import '../../support/fake_user_repository.dart';

const _superAdmin = AuthenticatedUser(
  id: 1,
  name: 'Super Admin',
  email: 'admin@example.com',
  role: UserRole.superAdmin,
);

const _teacher = AuthenticatedUser(id: 2, name: 'A Teacher', email: 'teacher@example.com', role: UserRole.teacher);

void main() {
  testWidgets('an account holding a temporary password gets no further', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(
            FakeAuthRepository(
              sessionOnRestore: const AuthenticatedUser(
                id: 3,
                name: 'Priya Nair',
                email: 'priya@example.com',
                role: UserRole.teacher,
                mustChangePassword: true,
              ),
            ),
          ),
          dashboardRepositoryProvider.overrideWithValue(FakeDashboardRepository()),
        ],
        child: const EduTrackApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Your account was set up with a temporary password. Choose your own to continue.'),
      findsOneWidget,
    );
    // Outside the shell: no sidebar to reach past the screen.
    expect(find.text('Reports'), findsNothing);
  });

  testWidgets('an ordinary session is not sent to change its password', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(FakeAuthRepository(sessionOnRestore: _teacher)),
          dashboardRepositoryProvider.overrideWithValue(FakeDashboardRepository()),
        ],
        child: const EduTrackApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Change Password'), findsNothing);
  });

  testWidgets('a super admin sees the admin-only navigation', (tester) async {
    // Desktop width: below the breakpoint the shell puts the sidebar behind a
    // drawer, where none of its entries are on screen to find.
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(FakeAuthRepository(sessionOnRestore: _superAdmin)),
          // The dashboard fetches its figures on mount; without this the
          // screen sits on a spinner and pumpAndSettle never returns.
          dashboardRepositoryProvider.overrideWithValue(FakeDashboardRepository()),
        ],
        child: const EduTrackApp(),
      ),
    );
    await tester.pumpAndSettle();

    // Reports sits at the top of the sidebar and is admin-only, so it is
    // both on screen and a genuine test of the role gate. "Admin Users" is
    // further down a lazily-built list and may not be built at all.
    expect(find.text('Reports'), findsWidgets);
  });

  testWidgets('a teacher does not see the admin-only navigation', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(FakeAuthRepository(sessionOnRestore: _teacher)),
          dashboardRepositoryProvider.overrideWithValue(FakeDashboardRepository()),
        ],
        child: const EduTrackApp(),
      ),
    );
    await tester.pumpAndSettle();

    // A teacher marks their own register rather than pulling a school-wide
    // report, so the entry is not offered at all.
    expect(find.text('Reports'), findsNothing);
  });

  testWidgets('a non-super-admin is redirected away from /users back to the dashboard', (tester) async {
    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(FakeAuthRepository(sessionOnRestore: _teacher)),
        userRepositoryProvider.overrideWithValue(FakeUserRepository()),
        dashboardRepositoryProvider.overrideWithValue(FakeDashboardRepository()),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const EduTrackApp()));
    await tester.pumpAndSettle();

    // Navigate the router directly to /users; the redirect should bounce it
    // straight back to the dashboard for a non-SUPER_ADMIN user.
    container.read(routerProvider).go('/users');
    await tester.pumpAndSettle();

    expect(find.text('Admin Users'), findsNothing);
    expect(find.text('Dashboard'), findsWidgets);
  });

  testWidgets('a failed login shows its error message without losing the login screen', (tester) async {
    // Regression test: AuthNotifier.login() used to set state to
    // AsyncLoading() before the real result, which made the router's
    // redirect (isLoading -> /splash) bounce LoginScreen out and back in on
    // every login attempt. That tore down the widget listening for the
    // error before the failure ever arrived, so the message was silently
    // lost. See CLAUDE.md rule 7 - never a blank/silent failure state.
    //
    // A `loginGate` forces a real frame boundary between the loading and
    // error states (matching real network latency) - without it, a fake
    // repository resolves too fast for the router to ever act on the
    // transient loading state, and the bug wouldn't reproduce here.
    final gate = Completer<void>();
    final fake = FakeAuthRepository(
      loginGate: gate,
      failLoginWith: const Failure(code: 'UNAUTHENTICATED', message: 'These credentials do not match our records.'),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(fake),
          authTokenStorageProvider.overrideWithValue(FakeAuthTokenStorage()),
        ],
        child: const EduTrackApp(),
      ),
    );
    await tester.pumpAndSettle();

    // The app now lands unauthenticated visitors on the public marketing
    // homepage, not directly on the login screen - go there via its Login
    // button first.
    await tester.tap(find.widgetWithText(OutlinedButton, 'Login'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextFormField, 'Email'), 'admin@example.com');
    await tester.enterText(find.widgetWithText(TextFormField, 'Password'), 'wrong-password');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Sign In'));
    await tester.pump();

    // While the login request is in flight, the login screen must not be
    // swapped out for the splash screen.
    expect(find.byType(LoginScreen), findsOneWidget);

    gate.complete();
    await tester.pumpAndSettle();

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.text('These credentials do not match our records.'), findsOneWidget);
  });

  testWidgets('a fresh logged-out visit to / shows the marketing homepage, not a login bounce', (tester) async {
    // Regression test: the redirect used to send every non-'/splash'
    // location to '/splash' while the session was still restoring, then
    // (since '/splash' itself isn't a public path) fall through to
    // '/login' once loading finished - meaning a first-time, logged-out
    // visitor to '/' would never actually see the marketing homepage, only
    // ever the login screen. Public destinations must render immediately
    // regardless of the still-resolving session.
    final gate = Completer<void>();
    final fake = FakeAuthRepository(restoreGate: gate);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(fake),
          authTokenStorageProvider.overrideWithValue(FakeAuthTokenStorage()),
        ],
        child: const EduTrackApp(),
      ),
    );
    await tester.pump();

    // While the session is still resolving, the marketing homepage must
    // already be showing - not a splash screen bouncing toward /login.
    expect(find.text('Run Your School Smarter, Together.'), findsOneWidget);

    gate.complete();
    await tester.pumpAndSettle();

    expect(find.text('Run Your School Smarter, Together.'), findsOneWidget);
  });

  testWidgets('a deep-linked route survives session restore instead of bouncing to the dashboard', (tester) async {
    // Regression test: a hard reload on e.g. /students used to always land
    // on /dashboard. The redirect gated every non-public destination behind
    // '/splash' while the session was still restoring, and once it
    // resolved, "location == '/splash' -> go to /dashboard" fired
    // unconditionally - the original /students target was never carried
    // through the gate, so a real user reloading mid-session always lost
    // their place. See AppRouter's redirect - the splash detour now carries
    // the original destination as a `from` query param and returns to it
    // once the session resolves.
    final gate = Completer<void>();
    const teacher = AuthenticatedUser(id: 3, name: 'A Teacher', email: 'teacher@example.com', role: UserRole.teacher);
    final fake = FakeAuthRepository(sessionOnRestore: teacher, restoreGate: gate);
    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(fake),
        authTokenStorageProvider.overrideWithValue(FakeAuthTokenStorage()),
        studentRepositoryProvider.overrideWithValue(FakeStudentRepository()),
        schoolClassRepositoryProvider.overrideWithValue(FakeSchoolClassRepository()),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const EduTrackApp()));
    await tester.pump();

    // Simulate the browser already being at /students when the session
    // (still restoring) starts resolving - exactly what a hard reload on
    // that route looks like.
    container.read(routerProvider).go('/students');
    await tester.pump();

    gate.complete();
    await tester.pumpAndSettle();

    expect(find.text('Student Management'), findsWidgets);
    expect(find.text('Dashboard'), findsNothing);
  });
}
