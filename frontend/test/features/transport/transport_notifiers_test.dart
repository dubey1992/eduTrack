import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/features/transport/application/driver_page_notifier.dart';
import 'package:edutrack_app/features/transport/application/route_detail_notifier.dart';
import 'package:edutrack_app/features/transport/application/route_page_notifier.dart';
import 'package:edutrack_app/features/transport/application/route_students_notifier.dart';
import 'package:edutrack_app/features/transport/application/vehicle_page_notifier.dart';
import 'package:edutrack_app/features/transport/data/models/transport_status.dart';
import 'package:edutrack_app/features/transport/data/transport_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_transport_repository.dart';
import '../../support/transport_fixtures.dart';

void main() {
  ProviderContainer makeContainer(FakeTransportRepository fake) {
    final container = ProviderContainer(
      overrides: [transportRepositoryProvider.overrideWithValue(fake)],
      retry: (retryCount, error) => null,
    );
    addTearDown(container.dispose);
    return container;
  }

  group('VehiclePageNotifier', () {
    test('loads, creates, toggles status and deletes', () async {
      final fake = FakeTransportRepository(vehicles: [bus04]);
      final container = makeContainer(fake);
      final notifier = container.read(vehiclePageNotifierProvider.notifier);

      expect((await container.read(vehiclePageNotifierProvider.future)).items.single.name, 'Bus 04');

      await notifier.createVehicle(schoolId: null, name: 'Bus 11', registrationNumber: 'MH12 ZZ 0001', capacity: 45);
      expect(container.read(vehiclePageNotifierProvider).value!.items.map((v) => v.name), ['Bus 04', 'Bus 11']);
      expect(fake.lastCall!['capacity'], 45);

      await notifier.updateVehicle(bus04, status: TransportStatus.inactive);
      expect(container.read(vehiclePageNotifierProvider).value!.items.first.status, TransportStatus.inactive);

      await notifier.deleteVehicle(bus04);
      expect(fake.lastDeletedVehicleId, 1);
      expect(container.read(vehiclePageNotifierProvider).value!.items.map((v) => v.name), ['Bus 11']);
    });

    test('a failure surfaces the Failure and keeps the list', () async {
      final fake = FakeTransportRepository(vehicles: [bus04]);
      final container = makeContainer(fake);
      await container.read(vehiclePageNotifierProvider.future);
      fake.failWith = const Failure(code: 'HAS_DEPENDENT_RECORDS', message: 'This vehicle is still serving a route.');

      await expectLater(
        container.read(vehiclePageNotifierProvider.notifier).deleteVehicle(bus04),
        throwsA(isA<Failure>().having((f) => f.code, 'code', 'HAS_DEPENDENT_RECORDS')),
      );
      expect(container.read(vehiclePageNotifierProvider).value!.items, hasLength(1));
    });
  });

  group('DriverPageNotifier', () {
    test('loads, creates, updates and deletes', () async {
      final fake = FakeTransportRepository(drivers: [sanjay]);
      final container = makeContainer(fake);
      final notifier = container.read(driverPageNotifierProvider.notifier);

      expect((await container.read(driverPageNotifierProvider.future)).items.single.name, 'Sanjay Patel');

      await notifier.createDriver(
        schoolId: null,
        name: 'New Driver',
        mobile: null,
        licenceNumber: 'DL-1',
        licenceExpiry: null,
      );
      expect(container.read(driverPageNotifierProvider).value!.items, hasLength(2));

      await notifier.updateDriver(
        sanjay,
        name: 'Sanjay P.',
        mobile: sanjay.mobile,
        licenceNumber: sanjay.licenceNumber,
        licenceExpiry: null,
      );
      final updated = container.read(driverPageNotifierProvider).value!.items.first;
      expect(updated.name, 'Sanjay P.');
      expect(updated.licenceExpiry, isNull);

      await notifier.deleteDriver(sanjay);
      expect(fake.lastDeletedDriverId, 1);
    });
  });

  group('RoutePageNotifier', () {
    test('creates a route with a vehicle and driver, updates and deletes', () async {
      final fake = FakeTransportRepository(vehicles: [bus09Spare], drivers: [expiredRamesh], routes: [greenPark]);
      final container = makeContainer(fake);
      final notifier = container.read(routePageNotifierProvider.notifier);
      await container.read(routePageNotifierProvider.future);

      await notifier.createRoute(schoolId: null, name: 'Lake Road', vehicleId: 2, driverId: 2, attendantUserId: 44);
      final created = container.read(routePageNotifierProvider).value!.items.last;
      expect(created.label, 'Bus 09 - Lake Road');
      expect(created.capacity, 30);
      expect(created.driverName, 'Ramesh Rao');
      expect(fake.lastCall!['attendant_user_id'], 44);
      expect(created.attendantUserId, 44);

      await notifier.updateRoute(
        created,
        vehicleId: null,
        driverId: null,
        attendantUserId: null,
        status: TransportStatus.inactive,
      );
      final updated = container.read(routePageNotifierProvider).value!.items.last;
      expect(updated.vehicleId, isNull);
      expect(updated.label, 'Lake Road');
      expect(updated.status, TransportStatus.inactive);
      expect(fake.lastCall!['attendant_user_id'], isNull);
      expect(updated.attendantUserId, isNull);

      await notifier.deleteRoute(updated);
      expect(fake.lastDeletedRouteId, updated.id);
      expect(container.read(routePageNotifierProvider).value!.items.map((r) => r.name), ['Green Park']);
    });
  });

  group('RouteDetailNotifier', () {
    test('adds, edits and deletes stops and keeps them in sequence order', () async {
      final fake = FakeTransportRepository(routes: [greenPark]);
      final container = makeContainer(fake);
      container.listen(routeDetailProvider(1), (_, _) {});
      final notifier = container.read(routeDetailProvider(1).notifier);
      expect((await container.read(routeDetailProvider(1).future)).stops.map((s) => s.name), [
        'Lake View',
        'Central Park',
      ]);

      await notifier.addStop(name: 'Depot', sequenceNumber: 0, pickupTime: '07:00', dropTime: null);
      expect(container.read(routeDetailProvider(1)).value!.stops.map((s) => s.name), [
        'Depot',
        'Lake View',
        'Central Park',
      ]);
      expect(fake.lastCall!['pickup_time'], '07:00');

      await notifier.editStop(
        centralPark,
        name: 'Central Park Gate',
        sequenceNumber: 2,
        pickupTime: null,
        dropTime: '15:40',
      );
      expect(container.read(routeDetailProvider(1)).value!.stops.last.name, 'Central Park Gate');

      await notifier.deleteStop(lakeView);
      expect(fake.lastDeletedStopId, 101);
      expect(container.read(routeDetailProvider(1)).value!.stopsCount, 2);
    });
  });

  group('RouteStudentsNotifier', () {
    test('pages through the riders', () async {
      final fake = FakeTransportRepository(routes: [greenPark], routeStudents: [arjunRider]);
      final container = makeContainer(fake);
      container.listen(routeStudentsProvider(1), (_, _) {});

      final page = await container.read(routeStudentsProvider(1).future);
      expect(page.items.single.name, 'Arjun Kumar');

      await container.read(routeStudentsProvider(1).notifier).goToPage(2);
      expect(fake.lastListCall!['page'], 2);
    });
  });
}
