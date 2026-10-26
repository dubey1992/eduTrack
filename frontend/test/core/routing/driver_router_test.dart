import 'package:edutrack_app/core/widgets/driver_mark.dart';
import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/network/maintenance_notifier.dart';
import 'package:edutrack_app/core/routing/driver_router.dart';
import 'package:edutrack_app/core/storage/key_value_store.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/auth/presentation/attendant_login_screen.dart';
import 'package:edutrack_app/features/auth/presentation/driver_landing_screen.dart';
import 'package:edutrack_app/features/auth/presentation/driver_splash_screen.dart';
import 'package:edutrack_app/features/my_trip/data/location_source.dart';
import 'package:edutrack_app/features/my_trip/data/trip_service.dart';
import 'package:edutrack_app/features/my_trip/data/my_trip_api.dart';
import 'package:edutrack_app/features/my_trip/data/phone_dialer.dart';
import 'package:edutrack_app/features/my_trip/presentation/battery_help_screen.dart';
import 'package:edutrack_app/features/my_trip/presentation/my_trip_screen.dart';
import 'package:edutrack_app/features/my_trip/presentation/navigate_screen.dart';
import 'package:edutrack_app/features/profile/presentation/profile_screen.dart';
import 'package:edutrack_app/main_driver.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:edutrack_app/features/profile/data/profile_repository.dart';

import '../../support/fake_auth_repository.dart';
import '../../support/fake_profile_repository.dart';
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
        tripServiceProvider.overrideWithValue(FakeTripService()),
        phoneDialerProvider.overrideWithValue(FakePhoneDialer()),
        profileRepositoryProvider.overrideWithValue(FakeProfileRepository()),
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
        containsAll(['/start', '/sign-in', '/my-trip', '/profile', '/splash', '/maintenance', '/not-crew']),
      );
    });

    test('and not the homepage, the dashboard, or any screen of the school', () {
      // Hiding them would not be the same thing: an app named for the
      // driver should not contain a payroll screen at all.
      final container = ProviderContainer(overrides: [authRepositoryProvider.overrideWithValue(FakeAuthRepository())]);
      addTearDown(container.dispose);

      // '/profile' is not in this list: a crew member's own details are
      // theirs wherever they work, and the app has a tab for them. Every
      // other entry here belongs to the office.
      for (final office in ['/', '/dashboard', '/login', '/students', '/payroll', '/reports', '/schools']) {
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

      // Still there a full animation loop in, which is the point of the
      // beat: the bus reaches the stop before the screen changes.
      await tester.pump(const Duration(milliseconds: 2200));
      expect(find.byType(DriverSplashScreen), findsOneWidget);

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
      // The shuttle, not the graduation cap the app first had.
      expect(find.byType(DriverMark), findsOneWidget);
    });

    testWidgets('nothing on the bus is selectable, because a long press belongs to SOS', (tester) async {
      // The portal wraps its screens in a SelectionArea so an administrator
      // can copy a phone number. On the bus nobody copies anything, and the
      // cost is real: it claims every long press, so holding the SOS button
      // highlighted the label and opened a Copy bar instead of calling for
      // help (docs/driver-app.md, D5.2).
      await pump(tester, FakeAuthRepository());

      expect(find.byType(SelectionArea), findsNothing);
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

    testWidgets('the crew can reach their own profile and come back', (tester) async {
      // Two places, which is the whole app: the trip they are running and
      // their own details (docs/driver-app.md).
      await pump(tester, FakeAuthRepository(sessionOnRestore: sessionUser(UserRole.busAttendant)));

      expect(find.byKey(const Key('crew-nav')), findsOneWidget);

      await tester.tap(find.byKey(const Key('crew-nav-profile')));
      await tester.pumpAndSettle();

      expect(find.byType(ProfileScreen), findsOneWidget);
      expect(find.byType(MyTripScreen), findsNothing);

      await tester.tap(find.byKey(const Key('crew-nav-trip')));
      await tester.pumpAndSettle();

      expect(find.byType(MyTripScreen), findsOneWidget);
    });

    testWidgets('and a crew member really lands on the battery help when they ask for it', (tester) async {
      await pump(tester, FakeAuthRepository(sessionOnRestore: sessionUser(UserRole.busAttendant)));

      tester.element(find.byType(MyTripScreen)).go('/battery');
      await tester.pumpAndSettle();

      expect(find.byType(BatteryHelpScreen), findsOneWidget);
      expect(find.byType(MyTripScreen), findsNothing, reason: 'it bounced straight back before');
    });

    testWidgets('and on the navigate screen, with the stop it was given', (tester) async {
      await pump(tester, FakeAuthRepository(sessionOnRestore: sessionUser(UserRole.busAttendant)));

      tester
          .element(find.byType(MyTripScreen))
          .push('/navigate', extra: const NavigateTo(latitude: 12.9716, longitude: 77.5946, stopName: 'Main Gate'));
      await tester.pumpAndSettle();

      expect(find.byType(NavigateScreen), findsOneWidget);
      expect(find.text('Main Gate'), findsOneWidget);
    });

    testWidgets('and an address with no stop behind it lands on the trip rather than crashing', (tester) async {
      await pump(tester, FakeAuthRepository(sessionOnRestore: sessionUser(UserRole.busAttendant)));

      tester.element(find.byType(MyTripScreen)).go('/navigate');
      await tester.pumpAndSettle();

      expect(find.byType(MyTripScreen), findsOneWidget);
    });

    testWidgets('on a tablet the trip keeps a readable column instead of stretching', (tester) async {
      // A tablet is a real place for this app - mounted in a bus, or the
      // attendant's. Stretched edge to edge, a child's name sits at one
      // side and the Boarded button at the other (docs/driver-app.md).
      tester.view.physicalSize = const Size(1600, 2560);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(driverApp(FakeAuthRepository(sessionOnRestore: sessionUser(UserRole.busAttendant))));
      await tester.pump(openingBeat + const Duration(milliseconds: 100));
      await tester.pumpAndSettle();

      final trip = tester.getSize(find.byType(MyTripScreen));
      expect(trip.width, lessThanOrEqualTo(640));
      // And it is not squeezed to a phone's width either.
      expect(trip.width, greaterThan(400));
    });

    testWidgets('and the bar offers those two and nothing else', (tester) async {
      await pump(tester, FakeAuthRepository(sessionOnRestore: sessionUser(UserRole.busAttendant)));

      expect(find.byType(NavigationDestination), findsNWidgets(2));
      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Profile'), findsOneWidget);
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
          tripServiceProvider.overrideWithValue(FakeTripService()),
          phoneDialerProvider.overrideWithValue(FakePhoneDialer()),
          profileRepositoryProvider.overrideWithValue(FakeProfileRepository()),
          maintenanceProvider.overrideWith(_Down.new),
        ],
        child: const DriverApp(),
      ),
    );
    await tester.pump(openingBeat + const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    expect(find.byType(MyTripScreen), findsNothing);
  });
  testWidgets('a driver is crew too: on the trip, like an attendant', (tester) async {
    // A driver is an employee who signs in exactly as an attendant does
    // (docs/driver-app.md, D10); the gate asks "is crew", not "is attendant".
    await pump(tester, FakeAuthRepository(sessionOnRestore: sessionUser(UserRole.driver, name: 'Suresh Pawar')));

    expect(find.byType(MyTripScreen), findsOneWidget);
    expect(find.text('This app is for the bus crew'), findsNothing);
  });
}

/// Stuck down, with no Dio behind it.
class _Down extends MaintenanceNotifier {
  @override
  bool build() => true;
}
