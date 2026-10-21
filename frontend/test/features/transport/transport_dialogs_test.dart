import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/auth/data/models/authenticated_user.dart';
import 'package:edutrack_app/features/staff/data/staff_repository.dart';
import 'package:edutrack_app/features/transport/data/models/bus_stop.dart';
import 'package:edutrack_app/features/transport/data/transport_repository.dart';
import 'package:edutrack_app/features/transport/presentation/driver_form_dialog.dart';
import 'package:edutrack_app/features/transport/presentation/manage_stops_dialog.dart';
import 'package:edutrack_app/features/transport/presentation/route_form_dialog.dart';
import 'package:edutrack_app/features/transport/presentation/vehicle_form_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_map.dart';
import '../../support/attendant_fixtures.dart';
import '../../support/fake_auth_repository.dart';
import '../../support/fake_staff_repository.dart';
import '../../support/fake_transport_repository.dart';
import '../../support/transport_fixtures.dart';

const _schoolAdmin = AuthenticatedUser(id: 5, name: 'Admin', email: 'admin@example.com', role: UserRole.schoolAdmin);

/// Every dialog is opened through a real showDialog route so its own
/// Navigator.pop() closes just the dialog.
Widget wrap(FakeTransportRepository fake, Widget Function() dialog, {FakeStaffRepository? staff}) {
  return ProviderScope(
    overrides: [
      transportRepositoryProvider.overrideWithValue(fake),
      // Bus Attendants are staff: the route form's picker reads them there.
      staffRepositoryProvider.overrideWithValue(staff ?? FakeStaffRepository()),
      authRepositoryProvider.overrideWithValue(FakeAuthRepository(sessionOnRestore: _schoolAdmin)),
      // The stops dialog and the stop form both hold a map now. Pinned to
      // "no key" so this file keeps testing the stops and never reaches the
      // network to find out whether one is configured.
      ...mapIsUnavailable(),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showDialog(context: context, builder: (_) => dialog()),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
}

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

void main() {
  group('VehicleFormDialog', () {
    testWidgets('validates required fields and the capacity range', (tester) async {
      await tester.pumpWidget(wrap(FakeTransportRepository(), () => const VehicleFormDialog()));
      await _open(tester);

      await tester.enterText(find.widgetWithText(TextFormField, 'Seating capacity'), '0');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('Name is required'), findsOneWidget);
      expect(find.text('Registration number is required'), findsOneWidget);
      expect(find.text('Enter a capacity between 1 and 200'), findsOneWidget);
    });

    testWidgets('creates a vehicle, closes and confirms', (tester) async {
      final fake = FakeTransportRepository();
      await tester.pumpWidget(wrap(fake, () => const VehicleFormDialog()));
      await _open(tester);

      await tester.enterText(find.widgetWithText(TextFormField, 'Vehicle name'), 'Bus 04');
      await tester.enterText(find.widgetWithText(TextFormField, 'Registration number'), 'MH12 AB 1234');
      await tester.enterText(find.widgetWithText(TextFormField, 'Seating capacity'), '40');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(fake.lastCall, {
        'op': 'createVehicle',
        'school_id': null,
        'name': 'Bus 04',
        'registration_number': 'MH12 AB 1234',
        'capacity': 40,
      });
      expect(find.byType(VehicleFormDialog), findsNothing);
      expect(find.text('Vehicle added.'), findsOneWidget);
    });

    testWidgets('edits pre-fill and a server failure keeps the dialog open', (tester) async {
      final fake = FakeTransportRepository(vehicles: [bus04]);
      await tester.pumpWidget(wrap(fake, () => const VehicleFormDialog(vehicle: bus04)));
      await _open(tester);

      expect(find.text('Edit Vehicle'), findsOneWidget);
      expect(find.text('MH12 AB 1234'), findsOneWidget);

      fake.failWith = const Failure(
        code: 'VALIDATION_ERROR',
        message: 'The registration number has already been taken.',
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('The registration number has already been taken.'), findsOneWidget);
      expect(find.byType(VehicleFormDialog), findsOneWidget);
    });
  });

  group('DriverFormDialog', () {
    testWidgets('validates name and licence, then creates with an optional mobile and expiry', (tester) async {
      final fake = FakeTransportRepository();
      await tester.pumpWidget(wrap(fake, () => const DriverFormDialog()));
      await _open(tester);

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Name is required'), findsOneWidget);
      expect(find.text('Licence number is required'), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextFormField, 'Driver name'), 'Sanjay Patel');
      await tester.enterText(find.widgetWithText(TextFormField, 'Licence number'), 'MH-12-1');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(fake.lastCall!['op'], 'createDriver');
      expect(fake.lastCall!['name'], 'Sanjay Patel');
      expect(fake.lastCall!['mobile'], isNull);
      expect(fake.lastCall!['licence_expiry'], isNull);
      expect(find.text('Driver added.'), findsOneWidget);
    });

    testWidgets('edit pre-fills the licence expiry and can clear it', (tester) async {
      final fake = FakeTransportRepository(drivers: [sanjay]);
      await tester.pumpWidget(wrap(fake, () => const DriverFormDialog(driver: sanjay)));
      await _open(tester);

      expect(find.text('03/31/2029'), findsOneWidget);
      await tester.tap(find.byTooltip('Clear expiry'));
      await tester.pumpAndSettle();
      expect(find.text('Not set'), findsOneWidget);

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(fake.lastCall!['op'], 'updateDriver');
      expect(fake.lastCall!['licence_expiry'], isNull);
      expect(find.text('Driver updated.'), findsOneWidget);
    });
  });

  group('RouteFormDialog', () {
    testWidgets('offers only free active vehicles/drivers and creates the route', (tester) async {
      final fake = FakeTransportRepository(
        vehicles: [bus04, bus09Spare],
        drivers: [sanjay, expiredRamesh],
        routes: [greenPark],
      );
      await tester.pumpWidget(wrap(fake, () => const RouteFormDialog()));
      await _open(tester);

      await tester.enterText(find.widgetWithText(TextFormField, 'Route name'), 'Lake Road');
      await tester.tap(find.text('No vehicle yet'));
      await tester.pumpAndSettle();
      expect(find.text('Bus 04 · 40 seats'), findsNothing); // already on Green Park
      await tester.tap(find.text('Bus 09 · 30 seats').last);
      await tester.pumpAndSettle();

      await tester.tap(find.text('No driver yet'));
      await tester.pumpAndSettle();
      expect(find.text('Sanjay Patel'), findsNothing);
      await tester.tap(find.text('Ramesh Rao').last);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(fake.lastCall, {
        'op': 'createRoute',
        'school_id': null,
        'name': 'Lake Road',
        'vehicle_id': 2,
        'driver_id': 2,
        'attendant_user_id': null,
        'stops': null,
      });
      expect(find.text('Route added.'), findsOneWidget);
    });

    testWidgets('editing keeps the route\'s own vehicle selectable and shows the server error on failure', (
      tester,
    ) async {
      final fake = FakeTransportRepository(vehicles: [bus04], drivers: [sanjay], routes: [greenPark]);
      await tester.pumpWidget(wrap(fake, () => const RouteFormDialog(route: greenPark)));
      await _open(tester);

      expect(find.text('Edit Route'), findsOneWidget);
      expect(find.text('Bus 04 · 40 seats'), findsOneWidget);
      expect(find.text('Sanjay Patel'), findsOneWidget);

      fake.failWith = const Failure(
        code: 'VALIDATION_ERROR',
        message: 'That vehicle is already serving another route.',
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('That vehicle is already serving another route.'), findsOneWidget);
      expect(find.byType(RouteFormDialog), findsOneWidget);
    });
  });

  group('ManageStopsDialog', () {
    testWidgets('lists stops in order with times and counts; a viewer gets no controls', (tester) async {
      await tester.pumpWidget(
        wrap(FakeTransportRepository(routes: [greenPark]), () => const ManageStopsDialog(routeId: 1, canManage: false)),
      );
      await _open(tester);

      expect(find.text('Stops · Bus 04 - Green Park'), findsOneWidget);
      expect(find.text('Lake View'), findsOneWidget);
      expect(find.text('Pickup 07:30 · Drop 15:30 · 1 student'), findsOneWidget);
      expect(find.text('Pickup 07:45 · 0 students'), findsOneWidget);
      expect(find.text('Add Stop'), findsNothing);
      expect(find.byTooltip('Edit stop'), findsNothing);
    });

    testWidgets('an admin can add a stop with the next order pre-filled, and delete one', (tester) async {
      const sector12 = BusStop(
        id: 9,
        schoolId: 1,
        schoolName: 'Abbey Road School',
        name: 'Sector 12',
        latitude: '18.5204000',
        longitude: '73.8567000',
        landmark: null,
        status: 'active',
        routesCount: 0,
      );
      final fake = FakeTransportRepository(routes: [greenPark], busStops: [sector12]);
      await tester.pumpWidget(wrap(fake, () => const ManageStopsDialog(routeId: 1, canManage: true)));
      await _open(tester);

      await tester.tap(find.text('Add Stop'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextFormField, 'Order on route'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Pick a bus stop'), findsOneWidget);

      await tester.tap(find.byKey(const Key('bus-stop-field')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sector 12').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(fake.lastCall!['op'], 'createStop');
      expect(fake.lastCall!['sequence_number'], 3);
      expect(find.byType(StopFormDialog), findsNothing);
      expect(find.text('Sector 12'), findsOneWidget);

      await tester.ensureVisible(find.byTooltip('Delete stop').first);
      await tester.tap(find.byTooltip('Delete stop').first);
      await tester.pumpAndSettle();
      expect(find.text('Remove stop?'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();
      expect(fake.lastDeletedStopId, isNull);

      await tester.ensureVisible(find.byTooltip('Delete stop').first);
      await tester.tap(find.byTooltip('Delete stop').first);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(fake.lastDeletedStopId, 101);
      expect(find.text('Lake View was removed.'), findsOneWidget);
      expect(find.text('Lake View'), findsNothing);
    });

    testWidgets('a dependent-records failure on delete is shown', (tester) async {
      final fake = FakeTransportRepository(routes: [greenPark]);
      await tester.pumpWidget(wrap(fake, () => const ManageStopsDialog(routeId: 1, canManage: true)));
      await _open(tester);

      fake.failWith = const Failure(
        code: 'HAS_DEPENDENT_RECORDS',
        message: 'Students are still assigned to this stop.',
      );
      await tester.ensureVisible(find.byTooltip('Delete stop').first);
      await tester.tap(find.byTooltip('Delete stop').first);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(find.text('Students are still assigned to this stop.'), findsOneWidget);
      expect(find.text('Lake View'), findsOneWidget);
    });
  });

  group('RouteFormDialog - Bus attendant', () {
    FakeStaffRepository staff() => FakeStaffRepository(staff: [meeraAttendant, inactiveRaviAttendant, anitaTeacher]);

    testWidgets('offers only active Bus Attendants and sends the user id, not the profile id', (tester) async {
      final fake = FakeTransportRepository();
      await tester.pumpWidget(wrap(fake, () => const RouteFormDialog(), staff: staff()));
      await _open(tester);

      await tester.enterText(find.widgetWithText(TextFormField, 'Route name'), 'Lake Road');
      await tester.tap(find.text('No attendant'));
      await tester.pumpAndSettle();

      expect(find.text('Meera Sharma · +91 9876543210').last, findsOneWidget);
      expect(find.textContaining('Ravi Das'), findsNothing); // switched off
      expect(find.textContaining('Anita Rao'), findsNothing); // a teacher

      await tester.tap(find.text('Meera Sharma · +91 9876543210').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(fake.lastCall!['op'], 'createRoute');
      expect(fake.lastCall!['attendant_user_id'], 131);
      expect(find.text('Route added.'), findsOneWidget);
    });

    testWidgets('editing pre-selects the route\'s attendant, and "No attendant" clears it', (tester) async {
      final fake = FakeTransportRepository(vehicles: [bus04], drivers: [sanjay], routes: [greenParkWithAttendant]);
      await tester.pumpWidget(wrap(fake, () => const RouteFormDialog(route: greenParkWithAttendant), staff: staff()));
      await _open(tester);

      expect(find.text('Meera Sharma · +91 9876543210'), findsOneWidget);

      await tester.tap(find.text('Meera Sharma · +91 9876543210'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('No attendant').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(fake.lastCall!['op'], 'updateRoute');
      expect(fake.lastCall!['attendant_user_id'], isNull);
      expect(find.text('Route updated.'), findsOneWidget);
    });

    testWidgets('an attendant no longer active stays on the route, marked inactive', (tester) async {
      final fake = FakeTransportRepository(vehicles: [bus04], drivers: [sanjay], routes: [greenParkWithAttendant]);
      await tester.pumpWidget(
        wrap(
          fake,
          () => const RouteFormDialog(route: greenParkWithAttendant),
          staff: FakeStaffRepository(staff: [anitaTeacher]),
        ),
      );
      await _open(tester);

      expect(find.text('Meera Sharma (inactive)'), findsOneWidget);

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(fake.lastCall!['attendant_user_id'], 131);
    });

    testWidgets('says so when the school has no Bus Attendants yet', (tester) async {
      await tester.pumpWidget(wrap(FakeTransportRepository(), () => const RouteFormDialog()));
      await _open(tester);

      expect(find.text('No Bus Attendants yet - add one in Teachers & Staff.'), findsOneWidget);
    });

    testWidgets('the server\'s attendant error is shown under the picker', (tester) async {
      const message = 'The selected attendant is not an active Bus Attendant of this school.';
      final fake = FakeTransportRepository(vehicles: [bus04], drivers: [sanjay], routes: [greenParkWithAttendant]);
      await tester.pumpWidget(wrap(fake, () => const RouteFormDialog(route: greenParkWithAttendant), staff: staff()));
      await _open(tester);

      fake.failWith = const Failure(
        code: 'VALIDATION_ERROR',
        message: message,
        details: {
          'errors': {
            'attendant_user_id': [message],
          },
        },
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text(message), findsOneWidget);
      expect(find.byType(RouteFormDialog), findsOneWidget);
    });
  });

  group('StopFormDialog - a call at one of the school\'s bus stops', () {
    // A route stop names a place in the school's list. The name and the
    // position belong there, so this form stopped asking for them
    // (docs/maps.md); what it asks for is which place, where in the run,
    // and when the bus is there.
    BusStop place({int id = 9, String name = 'Sector 12'}) {
      return BusStop(
        id: id,
        schoolId: 1,
        schoolName: 'Abbey Road School',
        name: name,
        latitude: '18.5204000',
        longitude: '73.8567000',
        landmark: null,
        status: 'active',
        routesCount: 0,
      );
    }

    testWidgets('each stop says whether it has a location', (tester) async {
      await tester.pumpWidget(
        wrap(
          FakeTransportRepository(routes: [greenParkWithAttendant]),
          () => const ManageStopsDialog(routeId: 1, canManage: false),
        ),
      );
      await _open(tester);

      expect(find.text('Location set'), findsOneWidget); // Lake View
      expect(find.text('No location'), findsOneWidget); // Central Park
    });

    testWidgets('adding one offers the school\'s bus stops and sends the place', (tester) async {
      final fake = FakeTransportRepository(routes: [greenPark], busStops: [place()]);
      await tester.pumpWidget(wrap(fake, () => const ManageStopsDialog(routeId: 1, canManage: true)));
      await _open(tester);

      await tester.tap(find.text('Add Stop'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('bus-stop-field')), findsOneWidget);
      // No name and no position: they are the list's.
      expect(find.widgetWithText(TextFormField, 'Stop name'), findsNothing);

      await tester.tap(find.byKey(const Key('bus-stop-field')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sector 12').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(fake.lastCall!['op'], 'createStop');
      expect(fake.lastCall!['bus_stop_id'], 9);
    });

    testWidgets('without picking one it is refused before the server sees it', (tester) async {
      final fake = FakeTransportRepository(routes: [greenPark], busStops: [place()]);
      await tester.pumpWidget(wrap(fake, () => const ManageStopsDialog(routeId: 1, canManage: true)));
      await _open(tester);

      await tester.tap(find.text('Add Stop'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('Pick a bus stop'), findsOneWidget);
      expect(fake.lastCall, isNull);
    });

    testWidgets('a school with no bus stops yet is told where they come from', (tester) async {
      await tester.pumpWidget(
        wrap(FakeTransportRepository(routes: [greenPark]), () => const ManageStopsDialog(routeId: 1, canManage: true)),
      );
      await _open(tester);

      await tester.tap(find.text('Add Stop'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Transport > Bus Stops'), findsOneWidget);
    });

    testWidgets('a one-off made before the list existed is still edited here', (tester) async {
      // Every stop that existed before this is a one-off, and they are
      // still correct - a route still stops there.
      final fake = FakeTransportRepository(routes: [greenParkWithAttendant]);
      await tester.pumpWidget(wrap(fake, () => const ManageStopsDialog(routeId: 1, canManage: true)));
      await _open(tester);

      await tester.ensureVisible(find.byTooltip('Edit stop').first);
      await tester.tap(find.byTooltip('Edit stop').first);
      await tester.pumpAndSettle();

      expect(find.widgetWithText(TextFormField, 'Stop name'), findsOneWidget);
      expect(find.textContaining('A one-off'), findsOneWidget);
    });
  });
}
