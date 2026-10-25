import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/network/maintenance_notifier.dart';
import 'package:edutrack_app/core/routing/teacher_router.dart';
import 'package:edutrack_app/core/storage/key_value_store.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/auth/presentation/login_screen.dart';
import 'package:edutrack_app/features/auth/presentation/teacher_splash_screen.dart';
import 'package:edutrack_app/features/errors/presentation/maintenance_screen.dart';
import 'package:edutrack_app/features/profile/data/profile_repository.dart';
import 'package:edutrack_app/features/profile/presentation/profile_screen.dart';
import 'package:edutrack_app/features/today/data/today_repository.dart';
import 'package:edutrack_app/features/today/presentation/today_screen.dart';
import 'package:edutrack_app/main_teacher.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../support/fake_auth_repository.dart';
import '../../support/fake_profile_repository.dart';
import '../../support/fake_today_repository.dart';
import '../../support/in_memory_key_value_store.dart';
import '../../support/session_users.dart';

/// What the teacher app has screens for (docs/teacher-app.md, T0).
///
/// As with the driver router, most of these are about absence: this build
/// carries the sign-in, Today and the teacher's own profile, and none of
/// the office.
void main() {
  Widget teacherApp(FakeAuthRepository auth, {bool maintenance = false}) {
    return ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(auth),
        keyValueStoreProvider.overrideWithValue(InMemoryKeyValueStore()),
        profileRepositoryProvider.overrideWithValue(FakeProfileRepository()),
        todayRepositoryProvider.overrideWithValue(FakeTodayRepository()),
        if (maintenance) maintenanceProvider.overrideWith(_Down.new),
      ],
      child: const TeacherApp(),
    );
  }

  Future<void> pump(WidgetTester tester, FakeAuthRepository auth, {Size size = const Size(480, 2000)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(teacherApp(auth));
    await tester.pump(teacherOpeningBeat + const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
  }

  group('the screens it carries', () {
    Iterable<String> pathsOf(ProviderContainer container) {
      return container.read(teacherRouterProvider).configuration.routes.whereType<GoRoute>().map((route) => route.path);
    }

    test('are the sign-in, Today and the profile', () {
      final container = ProviderContainer(overrides: [authRepositoryProvider.overrideWithValue(FakeAuthRepository())]);
      addTearDown(container.dispose);

      expect(
        pathsOf(container),
        containsAll(['/splash', '/login', '/forgot-password', '/today', '/profile', '/maintenance', '/not-teacher']),
      );
    });

    test('and none of the office, nor the bus', () {
      final container = ProviderContainer(overrides: [authRepositoryProvider.overrideWithValue(FakeAuthRepository())]);
      addTearDown(container.dispose);

      for (final elsewhere in [
        '/',
        '/dashboard',
        '/students',
        '/payroll',
        '/schools',
        '/my-trip',
        '/attendant-login',
      ]) {
        expect(pathsOf(container), isNot(contains(elsewhere)), reason: elsewhere);
      }
    });

    test('every reachable address is a route, and the other way round', () {
      final container = ProviderContainer(overrides: [authRepositoryProvider.overrideWithValue(FakeAuthRepository())]);
      addTearDown(container.dispose);

      // The driver router's lesson: a screen that is routed but not in the
      // reachable set is bounced back to home the moment it opens.
      expect(pathsOf(container).toSet(), containsAll(teacherPaths));
    });
  });

  group('where it opens', () {
    testWidgets('on the splash first, which says what it is doing', (tester) async {
      tester.view.physicalSize = const Size(480, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(teacherApp(FakeAuthRepository()));
      await tester.pump();

      expect(find.byType(TeacherSplashScreen), findsOneWidget);
      expect(find.text('Getting your day ready…'), findsOneWidget);

      // Past the beat, so the held timer does not outlive the test.
      await tester.pump(teacherOpeningBeat + const Duration(milliseconds: 100));
      await tester.pumpAndSettle();
      expect(find.byType(TeacherSplashScreen), findsNothing);
    });

    testWidgets('signed out: on the sign-in, without the bus crew\'s way in', (tester) async {
      await pump(tester, FakeAuthRepository());

      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.textContaining('Welcome Back'), findsOneWidget);
      expect(find.textContaining('Bus attendant?'), findsNothing);
    });

    testWidgets('signed in as a teacher: on Today, framed with the two tabs', (tester) async {
      await pump(tester, FakeAuthRepository(sessionOnRestore: sessionUser(UserRole.teacher, name: 'Asha Rao')));

      expect(find.byType(TodayScreen), findsOneWidget);
      expect(find.text('Good day, Asha'), findsOneWidget);
      expect(find.byKey(const Key('teacher-nav')), findsOneWidget);
      expect(find.byKey(const Key('teacher-nav-today')), findsOneWidget);
      expect(find.byKey(const Key('teacher-nav-profile')), findsOneWidget);
      expect(find.text('Asha Rao'), findsOneWidget, reason: 'the header says who is signed in');
    });

    testWidgets('an HOD is a teacher here too', (tester) async {
      await pump(tester, FakeAuthRepository(sessionOnRestore: sessionUser(UserRole.hod)));

      expect(find.byType(TodayScreen), findsOneWidget);
    });

    testWidgets('and reaches their own profile and comes back', (tester) async {
      await pump(tester, FakeAuthRepository(sessionOnRestore: sessionUser(UserRole.teacher)));

      await tester.tap(find.byKey(const Key('teacher-nav-profile')));
      await tester.pumpAndSettle();
      expect(find.byType(ProfileScreen), findsOneWidget);

      await tester.tap(find.byKey(const Key('teacher-nav-today')));
      await tester.pumpAndSettle();
      expect(find.byType(TodayScreen), findsOneWidget);
    });

    testWidgets('on a tablet the screen keeps a readable column instead of stretching', (tester) async {
      await pump(
        tester,
        FakeAuthRepository(sessionOnRestore: sessionUser(UserRole.teacher)),
        size: const Size(1600, 2560),
      );

      final width = tester.getSize(find.byType(TodayScreen)).width;
      expect(width, greaterThan(480));
      expect(width, lessThanOrEqualTo(640));
    });

    for (final (role, label) in [
      (UserRole.schoolAdmin, 'a school admin'),
      (UserRole.busAttendant, 'bus crew'),
      (UserRole.staff, 'office staff'),
    ]) {
      testWidgets('signed in as $label: told this app is for teachers, with a way out', (tester) async {
        final auth = FakeAuthRepository(sessionOnRestore: sessionUser(role));
        await pump(tester, auth);

        expect(find.text('This app is for teachers'), findsOneWidget);
        expect(find.byType(TodayScreen), findsNothing);

        await tester.tap(find.byKey(const Key('not-teacher-sign-out')));
        await tester.pumpAndSettle();
        expect(find.byType(LoginScreen), findsOneWidget);
      });
    }

    testWidgets('with the API down it waits, over everything else', (tester) async {
      tester.view.physicalSize = const Size(480, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        teacherApp(FakeAuthRepository(sessionOnRestore: sessionUser(UserRole.teacher)), maintenance: true),
      );
      await tester.pump(teacherOpeningBeat + const Duration(milliseconds: 100));
      await tester.pumpAndSettle();

      expect(find.byType(MaintenanceScreen), findsOneWidget);
    });
  });
}

/// The API reported down, from the first frame.
class _Down extends MaintenanceNotifier {
  @override
  bool build() => true;
}
