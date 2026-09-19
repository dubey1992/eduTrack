import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/auth/data/models/authenticated_user.dart';
import 'package:edutrack_app/features/schools/data/school_repository.dart';
import 'package:edutrack_app/features/transport/data/transport_repository.dart';
import 'package:edutrack_app/features/transport/presentation/driver_list_screen.dart';
import 'package:edutrack_app/features/transport/presentation/manage_stops_dialog.dart';
import 'package:edutrack_app/features/transport/presentation/route_list_screen.dart';
import 'package:edutrack_app/features/transport/presentation/route_students_dialog.dart';
import 'package:edutrack_app/features/transport/presentation/vehicle_list_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_auth_repository.dart';
import '../../support/fake_school_repository.dart';
import '../../support/fake_transport_repository.dart';
import '../../support/transport_fixtures.dart';

const _schoolAdmin = AuthenticatedUser(id: 9, name: 'Admin', email: 'admin@example.com', role: UserRole.schoolAdmin);
const _teacher = AuthenticatedUser(id: 20, name: 'Priya Sharma', email: 'priya@example.com', role: UserRole.teacher);
const _transportManager = AuthenticatedUser(
  id: 30,
  name: 'Mohan',
  email: 'mohan@example.com',
  role: UserRole.transportManager,
);

Widget wrap(Widget screen, FakeTransportRepository fake, {AuthenticatedUser actor = _schoolAdmin}) {
  return ProviderScope(
    overrides: [
      transportRepositoryProvider.overrideWithValue(fake),
      schoolRepositoryProvider.overrideWithValue(FakeSchoolRepository()),
      authRepositoryProvider.overrideWithValue(FakeAuthRepository(sessionOnRestore: actor)),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(body: screen),
    ),
  );
}

void useDesktop(WidgetTester tester) {
  tester.view.physicalSize = const Size(1800, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  group('VehicleListScreen', () {
    testWidgets('shows vehicles in a table with route, status and admin actions on desktop', (tester) async {
      useDesktop(tester);
      await tester.pumpWidget(wrap(const VehicleListScreen(), FakeTransportRepository(vehicles: [bus04, bus09Spare])));
      await tester.pumpAndSettle();

      expect(find.byType(DataTable), findsOneWidget);
      expect(find.text('Add Vehicle'), findsOneWidget);
      expect(find.text('Bus 04'), findsOneWidget);
      expect(find.text('40 seats'), findsOneWidget);
      expect(find.text('Green Park'), findsOneWidget);
      expect(find.text('Unassigned'), findsOneWidget);
      expect(find.text('Deactivate'), findsNWidgets(2));
      expect(find.byTooltip('Delete'), findsNWidgets(2));
    });

    testWidgets('a teacher sees the list read-only, in cards on mobile', (tester) async {
      await tester.pumpWidget(
        wrap(const VehicleListScreen(), FakeTransportRepository(vehicles: [bus04]), actor: _teacher),
      );
      await tester.pumpAndSettle();

      expect(find.byType(DataTable), findsNothing);
      expect(find.text('Bus 04'), findsOneWidget);
      expect(find.text('Add Vehicle'), findsNothing);
      expect(find.text('Deactivate'), findsNothing);
      expect(find.byTooltip('Delete'), findsNothing);
    });

    testWidgets('deactivate toggles the status in place', (tester) async {
      final fake = FakeTransportRepository(vehicles: [bus09Spare]);
      await tester.pumpWidget(wrap(const VehicleListScreen(), fake));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Deactivate'));
      await tester.pumpAndSettle();

      expect(fake.lastCall!['status'], 'inactive');
      expect(find.text('Bus 09 is now inactive.'), findsOneWidget);
      expect(find.text('Activate'), findsOneWidget);
      expect(find.text('Inactive'), findsOneWidget);
    });

    testWidgets('delete asks for confirmation, then removes the vehicle', (tester) async {
      final fake = FakeTransportRepository(vehicles: [bus09Spare]);
      await tester.pumpWidget(wrap(const VehicleListScreen(), fake));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Delete'));
      await tester.pumpAndSettle();
      expect(find.text('Delete vehicle?'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();
      expect(fake.lastDeletedVehicleId, isNull);

      await tester.tap(find.byTooltip('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(fake.lastDeletedVehicleId, 2);
      expect(find.text('Bus 09 was deleted.'), findsOneWidget);
      expect(find.text('No vehicles added yet.'), findsOneWidget);
    });

    testWidgets('a dependent-records failure on delete is shown and the row stays', (tester) async {
      final fake = FakeTransportRepository(vehicles: [bus04]);
      await tester.pumpWidget(wrap(const VehicleListScreen(), fake));
      await tester.pumpAndSettle();

      fake.failWith = const Failure(code: 'HAS_DEPENDENT_RECORDS', message: 'This vehicle is still serving a route.');
      await tester.tap(find.byTooltip('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(find.text('This vehicle is still serving a route.'), findsOneWidget);
      expect(find.text('Bus 04'), findsOneWidget);
    });

    testWidgets('shows the empty state', (tester) async {
      await tester.pumpWidget(wrap(const VehicleListScreen(), FakeTransportRepository()));
      await tester.pumpAndSettle();

      expect(find.text('No vehicles added yet.'), findsOneWidget);
    });

    // A separate test: a second ProviderScope pumped into the same tree
    // keeps the first container (and its fake), so it can't be reused.
    testWidgets('shows the error state with a working Retry', (tester) async {
      final failing = FakeTransportRepository(
        vehicles: [bus04],
        failWith: const Failure(code: 'NETWORK_ERROR', message: 'Could not reach the server.'),
      );
      await tester.pumpWidget(wrap(const VehicleListScreen(), failing));
      await tester.pumpAndSettle();
      expect(find.text('Could not reach the server.'), findsOneWidget);

      failing.failWith = null;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('Bus 04'), findsOneWidget);
    });
  });

  group('DriverListScreen', () {
    testWidgets('flags an expired licence and shows mobile, route and status', (tester) async {
      useDesktop(tester);
      await tester.pumpWidget(
        wrap(const DriverListScreen(), FakeTransportRepository(drivers: [sanjay, expiredRamesh])),
      );
      await tester.pumpAndSettle();

      expect(find.text('Sanjay Patel'), findsOneWidget);
      expect(find.text('+91 9876543210'), findsOneWidget);
      expect(find.text('MH-12-20190012345 · exp. 03/31/2029'), findsOneWidget);
      expect(find.text('Licence expired'), findsOneWidget);
      expect(find.text('Green Park'), findsOneWidget);
      expect(find.text('Unassigned'), findsOneWidget);
    });

    testWidgets('a transport manager can view but not manage drivers', (tester) async {
      await tester.pumpWidget(
        wrap(const DriverListScreen(), FakeTransportRepository(drivers: [sanjay]), actor: _transportManager),
      );
      await tester.pumpAndSettle();

      expect(find.text('Sanjay Patel'), findsOneWidget);
      expect(find.text('Add Driver'), findsNothing);
      expect(find.byTooltip('Edit'), findsNothing);
    });
  });

  group('RouteListScreen', () {
    testWidgets('shows vehicle, driver, stop and occupancy per route with a Full badge', (tester) async {
      useDesktop(tester);
      const fullRoute = greenParkFull;
      await tester.pumpWidget(
        wrap(const RouteListScreen(), FakeTransportRepository(routes: [fullRoute, lakeRoadNoVehicle])),
      );
      await tester.pumpAndSettle();

      expect(find.text('Green Park'), findsOneWidget);
      expect(find.text('Bus 04'), findsOneWidget);
      expect(find.text('Sanjay Patel'), findsOneWidget);
      expect(find.text('40 / 40'), findsOneWidget);
      expect(find.text('Full'), findsOneWidget);
      expect(find.text('No vehicle'), findsOneWidget);
      expect(find.text('No driver'), findsOneWidget);
      expect(find.text('Add Route'), findsOneWidget);
    });

    testWidgets('shows each route\'s Bus Attendant, or that it has none', (tester) async {
      useDesktop(tester);
      await tester.pumpWidget(
        wrap(const RouteListScreen(), FakeTransportRepository(routes: [greenParkWithAttendant, lakeRoadNoVehicle])),
      );
      await tester.pumpAndSettle();

      expect(find.text('Attendant'), findsOneWidget);
      expect(find.text('Meera Sharma'), findsOneWidget);
      expect(find.text('No attendant'), findsOneWidget);
    });

    testWidgets('the mobile cards name the attendant too', (tester) async {
      tester.view.physicalSize = const Size(900, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        wrap(const RouteListScreen(), FakeTransportRepository(routes: [greenParkWithAttendant, lakeRoadNoVehicle])),
      );
      await tester.pumpAndSettle();

      expect(find.text('Attendant: Meera Sharma'), findsOneWidget);
      expect(find.text('Attendant: None'), findsOneWidget);
    });

    testWidgets('deactivating a route keeps its attendant', (tester) async {
      useDesktop(tester);
      final fake = FakeTransportRepository(routes: [greenParkWithAttendant]);
      await tester.pumpWidget(wrap(const RouteListScreen(), fake));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Deactivate'));
      await tester.pumpAndSettle();

      expect(fake.lastCall!['op'], 'updateRoute');
      expect(fake.lastCall!['attendant_user_id'], 131);
      expect(fake.lastCall!['status'], 'inactive');
    });

    testWidgets('a school admin opens the stops manager and the students list', (tester) async {
      useDesktop(tester);
      await tester.pumpWidget(
        wrap(const RouteListScreen(), FakeTransportRepository(routes: [greenPark], routeStudents: [arjunRider])),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(TextButton, 'Stops'));
      await tester.pumpAndSettle();
      expect(find.byType(ManageStopsDialog), findsOneWidget);
      expect(find.text('Add Stop'), findsOneWidget);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(TextButton, 'Students'));
      await tester.pumpAndSettle();
      expect(find.byType(RouteStudentsDialog), findsOneWidget);
      expect(find.text('STU-0042 · Arjun Kumar'), findsOneWidget);
      expect(find.text('Lake View · Grade 8 A · Raj Kumar (+91 9999999999)'), findsOneWidget);
    });

    testWidgets('a teacher can open stops read-only but never sees Students, edit or delete', (tester) async {
      useDesktop(tester);
      await tester.pumpWidget(
        wrap(const RouteListScreen(), FakeTransportRepository(routes: [greenPark]), actor: _teacher),
      );
      await tester.pumpAndSettle();

      expect(find.widgetWithText(TextButton, 'Stops'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Students'), findsNothing);
      expect(find.text('Add Route'), findsNothing);
      expect(find.byTooltip('Delete'), findsNothing);

      await tester.tap(find.widgetWithText(TextButton, 'Stops'));
      await tester.pumpAndSettle();
      expect(find.text('Lake View'), findsOneWidget);
      expect(find.text('Add Stop'), findsNothing);
    });

    testWidgets('a transport manager sees Students but no management actions', (tester) async {
      useDesktop(tester);
      await tester.pumpWidget(
        wrap(const RouteListScreen(), FakeTransportRepository(routes: [greenPark]), actor: _transportManager),
      );
      await tester.pumpAndSettle();

      expect(find.widgetWithText(TextButton, 'Students'), findsOneWidget);
      expect(find.text('Add Route'), findsNothing);
      expect(find.text('Deactivate'), findsNothing);
    });

    testWidgets('an empty students list says so', (tester) async {
      useDesktop(tester);
      await tester.pumpWidget(wrap(const RouteListScreen(), FakeTransportRepository(routes: [lakeRoadNoVehicle])));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(TextButton, 'Students'));
      await tester.pumpAndSettle();
      expect(find.text('No students are assigned to this route yet.'), findsOneWidget);
    });
  });
}
