import 'package:edutrack_app/core/models/module_access.dart';
import 'package:edutrack_app/core/models/permission_level.dart';
import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/routing/app_nav.dart';
import 'package:edutrack_app/core/routing/app_router.dart';
import 'package:edutrack_app/core/storage/key_value_store.dart';
import 'package:edutrack_app/core/widgets/sidebar_nav.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/auth/data/models/authenticated_user.dart';
import 'package:edutrack_app/features/dashboard/data/dashboard_repository.dart';
import 'package:edutrack_app/features/my_trip/data/location_source.dart';
import 'package:edutrack_app/features/my_trip/data/my_trip_api.dart';
import 'package:edutrack_app/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_auth_repository.dart';
import '../../support/fake_dashboard_repository.dart';
import '../../support/in_memory_key_value_store.dart';
import '../../support/my_trip_fixtures.dart';
import '../../support/session_users.dart';

/// A Bus Attendant as the server describes them: transport and leave to
/// manage, nothing else.
AuthenticatedUser _attendant({Map<String, bool> modules = const {}}) => sessionUser(
  UserRole.busAttendant,
  name: 'Asha Attendant',
  permissions: {
    ...allModulesAt(PermissionLevel.none),
    AppModules.transport: PermissionLevel.manage,
    AppModules.leave: PermissionLevel.manage,
  },
  modules: modules,
);

NavItem _item(String path) => AppNav.findByPath(path)!;

const _officeTransport = ['/transport/vehicles', '/transport/drivers', '/transport/routes', '/transport/trips'];

void main() {
  group('the sidebar', () {
    test('gives an attendant My Trip, and none of the office transport screens', () {
      final attendant = _attendant();

      expect(_item('/my-trip').allows(attendant), isTrue);
      for (final path in _officeTransport) {
        expect(_item(path).allows(attendant), isFalse, reason: path);
      }
    });

    test("keeps an attendant's own self-service", () {
      final attendant = _attendant();

      for (final path in ['/dashboard', '/leaves', '/my-payslips', '/inbox']) {
        expect(_item(path).allows(attendant), isTrue, reason: path);
      }
      for (final path in ['/students', '/attendance', '/staff', '/reports', '/communication']) {
        expect(_item(path).allows(attendant), isFalse, reason: path);
      }
    });

    test('My Trip is for attendants only - the office runs trips from Trips', () {
      final manager = sessionUser(UserRole.transportManager, permissions: allModulesAt(PermissionLevel.manage));
      final admin = sessionUser(UserRole.schoolAdmin);

      expect(_item('/my-trip').allows(manager), isFalse);
      expect(_item('/my-trip').allows(admin), isFalse);
      expect(_item('/transport/trips').allows(manager), isTrue);
    });

    test('My Trip goes when the school switches transport off', () {
      expect(_item('/my-trip').allows(_attendant(modules: {AppModules.transport: false})), isFalse);
    });
  });

  group('the router', () {
    late FakeMyTripApi api;

    setUp(() => api = FakeMyTripApi());

    Future<GoRouterProbe> pumpApp(WidgetTester tester, AuthenticatedUser? user) async {
      tester.view.physicalSize = const Size(1400, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authRepositoryProvider.overrideWithValue(FakeAuthRepository(sessionOnRestore: user)),
            dashboardRepositoryProvider.overrideWithValue(FakeDashboardRepository()),
            myTripApiProvider.overrideWithValue(api),
            keyValueStoreProvider.overrideWithValue(InMemoryKeyValueStore()),
            locationSourceProvider.overrideWithValue(FakeLocationSource(access: LocationAccess.denied)),
          ],
          child: const EduTrackApp(),
        ),
      );
      await tester.pumpAndSettle();
      return GoRouterProbe(tester);
    }

    testWidgets('an attendant lands on My Trip, not the dashboard', (tester) async {
      final router = await pumpApp(tester, _attendant());
      router.go('/login');
      await tester.pumpAndSettle();

      expect(router.path, '/my-trip');
      expect(find.text('North Loop'), findsOneWidget);
    });

    testWidgets('an attendant is turned back from the office transport screens', (tester) async {
      final router = await pumpApp(tester, _attendant());

      for (final path in _officeTransport) {
        router.go(path);
        await tester.pumpAndSettle();
        expect(router.path, '/my-trip', reason: path);
      }
    });

    testWidgets("an attendant's sidebar shows My Trip but not Vehicles, Drivers, Routes or Trips", (tester) async {
      final router = await pumpApp(tester, _attendant());
      router.go('/my-trip');
      await tester.pumpAndSettle();

      Finder inSidebar(String label) => find.descendant(of: find.byType(SidebarNav), matching: find.text(label));

      expect(inSidebar('My Trip'), findsOneWidget);
      for (final label in ['Dashboard', 'Staff Leave', 'My Inbox']) {
        expect(inSidebar(label), findsOneWidget, reason: label);
      }
      for (final label in ['Vehicles', 'Drivers', 'Routes', 'Trips', 'Students', 'Timetable']) {
        expect(inSidebar(label), findsNothing, reason: label);
      }
    });

    testWidgets('an attendant whose school has transport off is not bounced in a loop', (tester) async {
      final router = await pumpApp(tester, _attendant(modules: {AppModules.transport: false}));
      router.go('/my-trip');
      await tester.pumpAndSettle();

      expect(router.path, '/my-trip');
    });

    testWidgets('anybody else still lands on the dashboard, and cannot open My Trip', (tester) async {
      final router = await pumpApp(tester, sessionUser(UserRole.schoolAdmin));
      router.go('/login');
      await tester.pumpAndSettle();
      expect(router.path, '/dashboard');

      router.go('/my-trip');
      await tester.pumpAndSettle();
      expect(router.path, '/dashboard');
    });

    testWidgets('signed out, My Trip asks for a sign-in and the attendant sign-in is open', (tester) async {
      final router = await pumpApp(tester, null);

      router.go('/my-trip');
      await tester.pumpAndSettle();
      expect(router.path, '/login');

      router.go('/attendant-login');
      await tester.pumpAndSettle();
      expect(router.path, '/attendant-login');
    });
  });
}

/// The app's router, read off the running app.
class GoRouterProbe {
  GoRouterProbe(this._tester);

  final WidgetTester _tester;

  ProviderContainer get _container => ProviderScope.containerOf(_tester.element(find.byType(MaterialApp)));

  void go(String location) => _container.read(routerProvider).go(location);

  String get path => _container.read(routerProvider).routerDelegate.currentConfiguration.uri.path;
}
