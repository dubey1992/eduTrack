import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/auth/data/models/authenticated_user.dart';
import 'package:edutrack_app/features/transport/data/transport_repository.dart';
import 'package:edutrack_app/features/transport/presentation/driver_form_dialog.dart';
import 'package:edutrack_app/features/transport/presentation/manage_stops_dialog.dart';
import 'package:edutrack_app/features/transport/presentation/route_form_dialog.dart';
import 'package:edutrack_app/features/transport/presentation/vehicle_form_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_auth_repository.dart';
import '../../support/fake_transport_repository.dart';
import '../../support/transport_fixtures.dart';

const _schoolAdmin = AuthenticatedUser(id: 5, name: 'Admin', email: 'admin@example.com', role: UserRole.schoolAdmin);

/// Every dialog is opened through a real showDialog route so its own
/// Navigator.pop() closes just the dialog.
Widget wrap(FakeTransportRepository fake, Widget Function() dialog) {
  return ProviderScope(
    overrides: [
      transportRepositoryProvider.overrideWithValue(fake),
      authRepositoryProvider.overrideWithValue(FakeAuthRepository(sessionOnRestore: _schoolAdmin)),
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

      expect(find.text('Mar 31, 2029'), findsOneWidget);
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
      final fake = FakeTransportRepository(routes: [greenPark]);
      await tester.pumpWidget(wrap(fake, () => const ManageStopsDialog(routeId: 1, canManage: true)));
      await _open(tester);

      await tester.tap(find.text('Add Stop'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextFormField, 'Order on route'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Name is required'), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextFormField, 'Stop name'), 'Sector 12');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(fake.lastCall!['op'], 'createStop');
      expect(fake.lastCall!['sequence_number'], 3);
      expect(find.byType(StopFormDialog), findsNothing);
      expect(find.text('Sector 12'), findsOneWidget);

      await tester.tap(find.byTooltip('Delete stop').first);
      await tester.pumpAndSettle();
      expect(find.text('Remove stop?'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();
      expect(fake.lastDeletedStopId, isNull);

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
      await tester.tap(find.byTooltip('Delete stop').first);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(find.text('Students are still assigned to this stop.'), findsOneWidget);
      expect(find.text('Lake View'), findsOneWidget);
    });
  });
}
