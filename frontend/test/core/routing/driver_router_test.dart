import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/network/maintenance_notifier.dart';
import 'package:edutrack_app/core/routing/driver_router.dart';
import 'package:edutrack_app/core/storage/key_value_store.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/auth/presentation/attendant_login_screen.dart';
import 'package:edutrack_app/features/auth/presentation/driver_landing_screen.dart';
import 'package:edutrack_app/features/auth/presentation/driver_splash_screen.dart';
import 'package:edutrack_app/features/my_trip/data/location_source.dart';
import 'package:edutrack_app/features/my_trip/data/my_trip_api.dart';
import 'package:edutrack_app/features/my_trip/data/phone_dialer.dart';
import 'package:edutrack_app/features/my_trip/presentation/my_trip_screen.dart';
import 'package:edutrack_app/main_driver.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../support/fake_auth_repository.dart';
import '../../support/in_memory_key_value_store.dart';
import '../../support/my_trip_fixtures.dart';
import '../../support/session_users.dart';

/// What the app on the bus has screens for (docs/driver-app.md).
///
/// The point of most of these is the **absence**: the driver build carries
/// the crew's sign-in and the trip, and nothing of the office. A build that
/// opened on the marketing homepage is what prompted the file.
void main() {
  Widget driverApp(FakeAuthRepository auth) {
    return ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(auth),
        myTripApiProvider.overrideWithValue(FakeMyTripApi()),
        keyValueStoreProvider.overrideWithValue(InMemoryKeyValueStore()),
        locationSourceProvider.overrideWithValue(FakeLocationSource(access: LocationAccess.denied)),
        phoneDialerProvider.overrideWithValue(FakePhoneDialer()),
      ],
      child: const DriverApp(),
    );
  }

  Future<void> pump(WidgetTester tester, FakeAuthRepository auth) async {
    tester.view.physicalSize = const Size(480, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(driverApp(auth));
    // Past the opening beat the splash is held for, so these tests see the
    // screen the app settles on rather than the splash.
    await tester.pump(openingBeat + const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
  }

  group('the screens it carries', () {
    Iterable<String> pathsOf(ProviderContainer container) {
      return container.read(driverRouterProvider).configuration.routes.whereType<GoRoute>().map((route) => route.path);
    }

    test('are the crew sign-in and the trip', () {
      final container = ProviderContainer(overrides: [authRepositoryProvider.overrideWithValue(FakeAuthRepository())]);
      addTearDown(container.dispose);

      expect(
        pathsOf(container),
        containsAll(['/start', '/sign-in', '/my-trip', '/splash', '/maintenance', '/not-crew']),
      );
    });

    test('and not the homepage, the dashboard, or any screen of the school', () {
      // Hiding them would not be the same thing: an app named for the
      // driver should not contain a payroll screen at all.
      final container = ProviderContainer(overrides: [authRepositoryProvider.overrideWithValue(FakeAuthRepository())]);
      addTearDown(container.dispose);

      for (final office in ['/', '/dashboard', '/login', '/students', '/payroll', '/reports', '/profile']) {
        expect(pathsOf(container), isNot(contains(office)), reason: office);
      }
    });
  });

  group('where it opens', () {
    testWidgets('on the splash first, long enough to be seen', (tester) async {
      // Restoring a session off the phone takes milliseconds, so without a
      // held beat the splash is skipped in a single frame and the crew goes
      // from the Android launch icon straight to the landing. That is what
      // the first build did (docs/driver-app.md).
      await tester.pumpWidget(driverApp(FakeAuthRepository()));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(DriverSplashScreen), findsOneWidget);
      expect(find.byType(DriverLandingScreen), findsNothing);

      await tester.pump(openingBeat);
      await tester.pumpAndSettle();

      expect(find.byType(DriverLandingScreen), findsOneWidget);
    });

    testWidgets('signed out: on the landing, which says what the app is for', (tester) async {
      // The sign-in screen is a mobile number and four digits with no room
      // to explain itself, and the crew meets it in a yard rather than at a
      // desk (docs/driver-app.md).
      await pump(tester, FakeAuthRepository());

      expect(find.byType(DriverLandingScreen), findsOneWidget);
      expect(find.text('Your trip sheet, on this phone.'), findsOneWidget);
      expect(find.text('Join Early Access →'), findsNothing);
    });

    testWidgets('and the landing leads to the sign-in, which has no dead ends', (tester) async {
      await pump(tester, FakeAuthRepository());

      await tester.tap(find.byKey(const Key('landing-continue')));
      await tester.pumpAndSettle();

      expect(find.byType(AttendantLoginScreen), findsOneWidget);
      // No way out that goes nowhere: this build has no email sign-in.
      expect(find.text('Sign in with email instead'), findsNothing);
    });

    testWidgets('a phone nobody has set up is offered the setting up', (tester) async {
      await pump(tester, FakeAuthRepository());

      expect(find.widgetWithText(FilledButton, 'Set up this phone'), findsOneWidget);
    });

    testWidgets('signed in as crew: on the trip, because there is one screen', (tester) async {
      await pump(tester, FakeAuthRepository(sessionOnRestore: sessionUser(UserRole.busAttendant)));

      expect(find.byType(MyTripScreen), findsOneWidget);
    });

    testWidgets('and the only chrome is who you are and the way out', (tester) async {
      await pump(tester, FakeAuthRepository(sessionOnRestore: sessionUser(UserRole.busAttendant, name: 'Anil Kumar')));

      expect(find.text('Anil Kumar'), findsOneWidget);
      expect(find.byTooltip('Log out'), findsOneWidget);
      // No sidebar, no module list.
      expect(find.text('Dashboard'), findsNothing);
      expect(find.text('Students'), findsNothing);
    });

    testWidgets('signed in as anybody else: told so, rather than left on a blank screen', (tester) async {
      await pump(tester, FakeAuthRepository(sessionOnRestore: sessionUser(UserRole.schoolAdmin)));

      expect(find.text('This app is for the bus crew'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Sign out'), findsOneWidget);
    });
  });

  testWidgets('with the API down it waits, over everything else', (tester) async {
    tester.view.physicalSize = const Size(480, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(
            FakeAuthRepository(sessionOnRestore: sessionUser(UserRole.busAttendant)),
          ),
          myTripApiProvider.overrideWithValue(FakeMyTripApi()),
          keyValueStoreProvider.overrideWithValue(InMemoryKeyValueStore()),
          locationSourceProvider.overrideWithValue(FakeLocationSource(access: LocationAccess.denied)),
          phoneDialerProvider.overrideWithValue(FakePhoneDialer()),
          maintenanceProvider.overrideWith(_Down.new),
        ],
        child: const DriverApp(),
      ),
    );
    await tester.pump(openingBeat + const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    expect(find.byType(MyTripScreen), findsNothing);
  });
}

/// Stuck down, with no Dio behind it.
class _Down extends MaintenanceNotifier {
  @override
  bool build() => true;
}
