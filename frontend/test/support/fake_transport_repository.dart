import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/network/paginated_response.dart';
import 'package:edutrack_app/features/transport/data/models/driver.dart';
import 'package:edutrack_app/features/transport/data/models/transport_route.dart';
import 'package:edutrack_app/features/transport/data/models/transport_status.dart';
import 'package:edutrack_app/features/transport/data/models/transport_trip.dart';
import 'package:edutrack_app/features/transport/data/models/vehicle.dart';
import 'package:edutrack_app/features/transport/data/transport_repository.dart';

import 'fake_pagination.dart';

/// In-memory vehicles/drivers/routes/stops/riders. Mutations keep the
/// cross-references (route.vehicleName, vehicle.routeName, counts) roughly
/// consistent so screens can assert on what they'd really show.
class FakeTransportRepository implements TransportRepository {
  FakeTransportRepository({
    List<Vehicle>? vehicles,
    List<Driver>? drivers,
    List<TransportRoute>? routes,
    List<RouteStudent>? routeStudents,
    List<TransportTrip>? trips,
    this.ridersForNewTrip = const [],
    this.failWith,
  }) : _vehicles = vehicles ?? [],
       _drivers = drivers ?? [],
       _routes = routes ?? [],
       _routeStudents = routeStudents ?? [],
       _trips = trips ?? [];

  final List<Vehicle> _vehicles;
  final List<Driver> _drivers;
  final List<TransportRoute> _routes;
  final List<RouteStudent> _routeStudents;
  final List<TransportTrip> _trips;

  /// The riders a trip started through this fake gets (the real API takes
  /// them from the route's assignments).
  List<TripRider> ridersForNewTrip;

  List<TransportTrip> get trips => List.unmodifiable(_trips);

  /// When set, every call throws it.
  Failure? failWith;

  /// The last mutation (create/update/stop) - list calls are recorded
  /// separately so a refresh after a mutation doesn't hide what was sent.
  Map<String, Object?>? lastCall;
  Map<String, Object?>? lastListCall;
  int? lastDeletedVehicleId;
  int? lastDeletedDriverId;
  int? lastDeletedRouteId;
  int? lastDeletedStopId;

  List<Vehicle> get vehicles => List.unmodifiable(_vehicles);
  List<Driver> get drivers => List.unmodifiable(_drivers);
  List<TransportRoute> get routes => List.unmodifiable(_routes);

  void _check() {
    if (failWith != null) throw failWith!;
  }

  // ── vehicles ────────────────────────────────────────────────────────

  @override
  Future<PaginatedResponse<Vehicle>> listVehicles({
    int? schoolId,
    TransportStatus? status,
    required int page,
    required int perPage,
  }) async {
    _check();
    lastListCall = {
      'op': 'listVehicles',
      'school_id': schoolId,
      'status': status?.apiValue,
      'page': page,
      'per_page': perPage,
    };
    final items = _vehicles
        .where((v) => schoolId == null || v.schoolId == schoolId)
        .where((v) => status == null || v.status == status);
    return paginateFake(items.toList(), page: page, perPage: perPage);
  }

  @override
  Future<List<Vehicle>> activeVehicles({int? schoolId}) async {
    _check();
    return _vehicles.where((v) => v.isActive && (schoolId == null || v.schoolId == schoolId)).toList();
  }

  @override
  Future<Vehicle> createVehicle({
    int? schoolId,
    required String name,
    required String registrationNumber,
    required int capacity,
  }) async {
    _check();
    lastCall = {
      'op': 'createVehicle',
      'school_id': schoolId,
      'name': name,
      'registration_number': registrationNumber,
      'capacity': capacity,
    };
    final vehicle = Vehicle(
      id: _vehicles.length + 1,
      schoolId: schoolId ?? 1,
      schoolName: 'Test School',
      name: name,
      registrationNumber: registrationNumber,
      capacity: capacity,
      status: TransportStatus.active,
      routeId: null,
      routeName: null,
    );
    _vehicles.add(vehicle);
    return vehicle;
  }

  @override
  Future<Vehicle> updateVehicle(
    int vehicleId, {
    String? name,
    String? registrationNumber,
    int? capacity,
    TransportStatus? status,
  }) async {
    _check();
    lastCall = {
      'op': 'updateVehicle',
      'id': vehicleId,
      'name': name,
      'registration_number': registrationNumber,
      'capacity': capacity,
      'status': status?.apiValue,
    };
    final index = _vehicles.indexWhere((v) => v.id == vehicleId);
    final e = _vehicles[index];
    final updated = Vehicle(
      id: e.id,
      schoolId: e.schoolId,
      schoolName: e.schoolName,
      name: name ?? e.name,
      registrationNumber: registrationNumber ?? e.registrationNumber,
      capacity: capacity ?? e.capacity,
      status: status ?? e.status,
      routeId: e.routeId,
      routeName: e.routeName,
    );
    _vehicles[index] = updated;
    return updated;
  }

  @override
  Future<void> deleteVehicle(int vehicleId) async {
    _check();
    lastDeletedVehicleId = vehicleId;
    _vehicles.removeWhere((v) => v.id == vehicleId);
  }

  // ── drivers ─────────────────────────────────────────────────────────

  @override
  Future<PaginatedResponse<Driver>> listDrivers({
    int? schoolId,
    TransportStatus? status,
    required int page,
    required int perPage,
  }) async {
    _check();
    lastListCall = {
      'op': 'listDrivers',
      'school_id': schoolId,
      'status': status?.apiValue,
      'page': page,
      'per_page': perPage,
    };
    final items = _drivers
        .where((d) => schoolId == null || d.schoolId == schoolId)
        .where((d) => status == null || d.status == status);
    return paginateFake(items.toList(), page: page, perPage: perPage);
  }

  @override
  Future<List<Driver>> activeDrivers({int? schoolId}) async {
    _check();
    return _drivers.where((d) => d.isActive && (schoolId == null || d.schoolId == schoolId)).toList();
  }

  @override
  Future<Driver> createDriver({
    int? schoolId,
    required String name,
    String? mobile,
    required String licenceNumber,
    String? licenceExpiry,
  }) async {
    _check();
    lastCall = {
      'op': 'createDriver',
      'school_id': schoolId,
      'name': name,
      'mobile': mobile,
      'licence_number': licenceNumber,
      'licence_expiry': licenceExpiry,
    };
    final driver = Driver(
      id: _drivers.length + 1,
      schoolId: schoolId ?? 1,
      schoolName: 'Test School',
      name: name,
      mobile: mobile,
      licenceNumber: licenceNumber,
      licenceExpiry: licenceExpiry,
      status: TransportStatus.active,
      routeId: null,
      routeName: null,
    );
    _drivers.add(driver);
    return driver;
  }

  @override
  Future<Driver> updateDriver(
    int driverId, {
    String? name,
    String? mobile,
    String? licenceNumber,
    String? licenceExpiry,
    TransportStatus? status,
  }) async {
    _check();
    lastCall = {
      'op': 'updateDriver',
      'id': driverId,
      'name': name,
      'mobile': mobile,
      'licence_number': licenceNumber,
      'licence_expiry': licenceExpiry,
      'status': status?.apiValue,
    };
    final index = _drivers.indexWhere((d) => d.id == driverId);
    final e = _drivers[index];
    final updated = Driver(
      id: e.id,
      schoolId: e.schoolId,
      schoolName: e.schoolName,
      name: name ?? e.name,
      mobile: mobile,
      licenceNumber: licenceNumber ?? e.licenceNumber,
      licenceExpiry: licenceExpiry,
      status: status ?? e.status,
      routeId: e.routeId,
      routeName: e.routeName,
    );
    _drivers[index] = updated;
    return updated;
  }

  @override
  Future<void> deleteDriver(int driverId) async {
    _check();
    lastDeletedDriverId = driverId;
    _drivers.removeWhere((d) => d.id == driverId);
  }

  // ── routes ──────────────────────────────────────────────────────────

  @override
  Future<PaginatedResponse<TransportRoute>> listRoutes({
    int? schoolId,
    TransportStatus? status,
    required int page,
    required int perPage,
  }) async {
    _check();
    lastListCall = {
      'op': 'listRoutes',
      'school_id': schoolId,
      'status': status?.apiValue,
      'page': page,
      'per_page': perPage,
    };
    final items = _routes
        .where((r) => schoolId == null || r.schoolId == schoolId)
        .where((r) => status == null || r.status == status);
    return paginateFake(items.toList(), page: page, perPage: perPage);
  }

  @override
  Future<List<TransportRoute>> activeRoutes({int? schoolId}) async {
    _check();
    return _routes.where((r) => r.isActive && (schoolId == null || r.schoolId == schoolId)).toList();
  }

  @override
  Future<TransportRoute> getRoute(int routeId) async {
    _check();
    return _routes.firstWhere((r) => r.id == routeId);
  }

  @override
  Future<TransportRoute> createRoute({int? schoolId, required String name, int? vehicleId, int? driverId}) async {
    _check();
    lastCall = {
      'op': 'createRoute',
      'school_id': schoolId,
      'name': name,
      'vehicle_id': vehicleId,
      'driver_id': driverId,
    };
    final vehicle = vehicleId == null ? null : _vehicles.firstWhere((v) => v.id == vehicleId);
    final driver = driverId == null ? null : _drivers.firstWhere((d) => d.id == driverId);
    final route = TransportRoute(
      id: _routes.length + 1,
      schoolId: schoolId ?? 1,
      schoolName: 'Test School',
      name: name,
      label: vehicle == null ? name : '${vehicle.name} - $name',
      status: TransportStatus.active,
      vehicleId: vehicleId,
      vehicleName: vehicle?.name,
      vehicleRegistrationNumber: vehicle?.registrationNumber,
      capacity: vehicle?.capacity,
      driverId: driverId,
      driverName: driver?.name,
      driverMobile: driver?.mobile,
      stopsCount: 0,
      studentsCount: 0,
    );
    _routes.add(route);
    return route;
  }

  @override
  Future<TransportRoute> updateRoute(
    int routeId, {
    String? name,
    required int? vehicleId,
    required int? driverId,
    TransportStatus? status,
  }) async {
    _check();
    lastCall = {
      'op': 'updateRoute',
      'id': routeId,
      'name': name,
      'vehicle_id': vehicleId,
      'driver_id': driverId,
      'status': status?.apiValue,
    };
    final index = _routes.indexWhere((r) => r.id == routeId);
    final e = _routes[index];
    final vehicle = vehicleId == null ? null : _vehicles.firstWhere((v) => v.id == vehicleId);
    final driver = driverId == null ? null : _drivers.firstWhere((d) => d.id == driverId);
    final newName = name ?? e.name;
    final updated = TransportRoute(
      id: e.id,
      schoolId: e.schoolId,
      schoolName: e.schoolName,
      name: newName,
      label: vehicle == null ? newName : '${vehicle.name} - $newName',
      status: status ?? e.status,
      vehicleId: vehicleId,
      vehicleName: vehicle?.name,
      vehicleRegistrationNumber: vehicle?.registrationNumber,
      capacity: vehicle?.capacity,
      driverId: driverId,
      driverName: driver?.name,
      driverMobile: driver?.mobile,
      stopsCount: e.stopsCount,
      studentsCount: e.studentsCount,
      stops: e.stops,
    );
    _routes[index] = updated;
    return updated;
  }

  @override
  Future<void> deleteRoute(int routeId) async {
    _check();
    lastDeletedRouteId = routeId;
    _routes.removeWhere((r) => r.id == routeId);
  }

  @override
  Future<PaginatedResponse<RouteStudent>> listRouteStudents(
    int routeId, {
    required int page,
    required int perPage,
  }) async {
    _check();
    lastListCall = {'op': 'listRouteStudents', 'route_id': routeId, 'page': page, 'per_page': perPage};
    return paginateFake(_routeStudents, page: page, perPage: perPage);
  }

  // ── stops ───────────────────────────────────────────────────────────

  TransportRoute _replaceStops(int routeId, List<TransportStop> stops) {
    final index = _routes.indexWhere((r) => r.id == routeId);
    final e = _routes[index];
    final sorted = [...stops]..sort((a, b) => a.sequenceNumber.compareTo(b.sequenceNumber));
    final updated = TransportRoute(
      id: e.id,
      schoolId: e.schoolId,
      schoolName: e.schoolName,
      name: e.name,
      label: e.label,
      status: e.status,
      vehicleId: e.vehicleId,
      vehicleName: e.vehicleName,
      vehicleRegistrationNumber: e.vehicleRegistrationNumber,
      capacity: e.capacity,
      driverId: e.driverId,
      driverName: e.driverName,
      driverMobile: e.driverMobile,
      stopsCount: sorted.length,
      studentsCount: e.studentsCount,
      stops: sorted,
    );
    _routes[index] = updated;
    return updated;
  }

  @override
  Future<TransportStop> createStop(
    int routeId, {
    required String name,
    required int sequenceNumber,
    String? pickupTime,
    String? dropTime,
  }) async {
    _check();
    lastCall = {
      'op': 'createStop',
      'route_id': routeId,
      'name': name,
      'sequence_number': sequenceNumber,
      'pickup_time': pickupTime,
      'drop_time': dropTime,
    };
    final route = _routes.firstWhere((r) => r.id == routeId);
    final stop = TransportStop(
      id: 100 + route.stops.length + 1,
      routeId: routeId,
      name: name,
      sequenceNumber: sequenceNumber,
      pickupTime: pickupTime,
      dropTime: dropTime,
      studentsCount: 0,
    );
    _replaceStops(routeId, [...route.stops, stop]);
    return stop;
  }

  @override
  Future<TransportStop> updateStop(
    int stopId, {
    String? name,
    int? sequenceNumber,
    String? pickupTime,
    String? dropTime,
  }) async {
    _check();
    lastCall = {
      'op': 'updateStop',
      'id': stopId,
      'name': name,
      'sequence_number': sequenceNumber,
      'pickup_time': pickupTime,
      'drop_time': dropTime,
    };
    final route = _routes.firstWhere((r) => r.stops.any((s) => s.id == stopId));
    final e = route.stops.firstWhere((s) => s.id == stopId);
    final updated = TransportStop(
      id: e.id,
      routeId: e.routeId,
      name: name ?? e.name,
      sequenceNumber: sequenceNumber ?? e.sequenceNumber,
      pickupTime: pickupTime,
      dropTime: dropTime,
      studentsCount: e.studentsCount,
    );
    _replaceStops(route.id, [for (final s in route.stops) s.id == stopId ? updated : s]);
    return updated;
  }

  @override
  Future<void> deleteStop(int stopId) async {
    _check();
    lastDeletedStopId = stopId;
    final route = _routes.firstWhere((r) => r.stops.any((s) => s.id == stopId));
    _replaceStops(route.id, route.stops.where((s) => s.id != stopId).toList());
  }

  // ── trips ───────────────────────────────────────────────────────────

  static const _now = '2026-09-10T08:00:00.000000Z';

  @override
  Future<PaginatedResponse<TransportTrip>> listTrips({
    int? schoolId,
    int? routeId,
    String? date,
    TripStatus? status,
    required int page,
    required int perPage,
  }) async {
    _check();
    lastListCall = {
      'op': 'listTrips',
      'school_id': schoolId,
      'route_id': routeId,
      'date': date,
      'status': status?.apiValue,
      'page': page,
      'per_page': perPage,
    };
    final items =
        _trips
            .where((t) => routeId == null || t.routeId == routeId)
            .where((t) => date == null || t.tripDate == date)
            .where((t) => status == null || t.status == status)
            .toList()
          ..sort((a, b) => b.id.compareTo(a.id));
    return paginateFake(items, page: page, perPage: perPage);
  }

  @override
  Future<TransportTrip> getTrip(int tripId) async {
    _check();
    return _trips.firstWhere((t) => t.id == tripId);
  }

  @override
  Future<TransportTrip> startTrip({required int routeId, required TripDirection direction}) async {
    _check();
    lastCall = {'op': 'startTrip', 'route_id': routeId, 'direction': direction.apiValue};
    final route = _routes.firstWhere((r) => r.id == routeId);
    final trip = TransportTrip(
      id: _trips.length + 1,
      schoolId: route.schoolId,
      routeId: route.id,
      routeName: route.name,
      routeLabel: route.label,
      vehicleId: route.vehicleId ?? 0,
      vehicleName: route.vehicleName ?? '',
      vehicleRegistrationNumber: route.vehicleRegistrationNumber ?? '',
      driverId: route.driverId ?? 0,
      driverName: route.driverName ?? '',
      driverMobile: route.driverMobile,
      tripDate: '2026-09-10',
      direction: direction,
      status: TripStatus.inProgress,
      currentStopId: null,
      currentStopName: null,
      startedByName: 'Mohan',
      startedAt: _now,
      endedAt: null,
      ridersCount: ridersForNewTrip.length,
      pendingCount: ridersForNewTrip.length,
      boardedCount: 0,
      droppedCount: 0,
      absentCount: 0,
      stopsLeft: route.stops.length,
      stops: [
        for (final s in route.stops)
          TripStop(
            id: s.id,
            name: s.name,
            sequenceNumber: s.sequenceNumber,
            pickupTime: s.pickupTime,
            dropTime: s.dropTime,
            reached: false,
          ),
      ],
      riders: ridersForNewTrip,
      events: [
        TripEvent(
          id: 1,
          type: TripEventType.started,
          stopId: null,
          stopName: null,
          studentId: null,
          studentName: null,
          recordedByName: 'Mohan',
          recordedAt: _now,
          note: 'Trip started with ${ridersForNewTrip.length} students expected',
        ),
      ],
    );
    _trips.add(trip);
    return trip;
  }

  TransportTrip _replaceTrip(TransportTrip updated) {
    final index = _trips.indexWhere((t) => t.id == updated.id);
    _trips[index] = updated;
    return updated;
  }

  TransportTrip _withEvent(TransportTrip trip, TripEventType type, {TripStop? stop, TripRider? rider, String? note}) {
    return trip.copyWith(
      events: [
        ...trip.events,
        TripEvent(
          id: trip.events.length + 1,
          type: type,
          stopId: stop?.id,
          stopName: stop?.name,
          studentId: rider?.studentId,
          studentName: rider?.name,
          recordedByName: 'Mohan',
          recordedAt: _now,
          note: note,
        ),
      ],
    );
  }

  static TransportTrip _recount(TransportTrip trip) {
    int count(TripRiderStatus s) => trip.riders.where((r) => r.status == s).length;
    return trip.copyWith(
      pendingCount: count(TripRiderStatus.pending),
      boardedCount: count(TripRiderStatus.boarded),
      droppedCount: count(TripRiderStatus.dropped),
      absentCount: count(TripRiderStatus.absent),
    );
  }

  @override
  Future<TransportTrip> reachStop(int tripId, int stopId) async {
    _check();
    lastCall = {'op': 'reachStop', 'trip_id': tripId, 'stop_id': stopId};
    final trip = _trips.firstWhere((t) => t.id == tripId);
    final stop = trip.stops.firstWhere((s) => s.id == stopId);
    final stops = [
      for (final s in trip.stops)
        s.id == stopId
            ? TripStop(
                id: s.id,
                name: s.name,
                sequenceNumber: s.sequenceNumber,
                pickupTime: s.pickupTime,
                dropTime: s.dropTime,
                reached: true,
              )
            : s,
    ];
    final updated = trip.copyWith(
      currentStopId: stop.id,
      currentStopName: stop.name,
      stops: stops,
      stopsLeft: stops.where((s) => !s.reached).length,
    );
    return _replaceTrip(_withEvent(updated, TripEventType.stopReached, stop: stop));
  }

  @override
  Future<TransportTrip> updateRider(int tripId, int studentId, TripRiderStatus status) async {
    _check();
    lastCall = {'op': 'updateRider', 'trip_id': tripId, 'student_id': studentId, 'status': status.apiValue};
    final trip = _trips.firstWhere((t) => t.id == tripId);
    final rider = trip.riders.firstWhere((r) => r.studentId == studentId);
    final changed = rider.copyWith(
      status: status,
      boardedAt: status == TripRiderStatus.boarded ? _now : null,
      droppedAt: status == TripRiderStatus.dropped ? _now : null,
    );
    final updated = _recount(
      trip.copyWith(riders: [for (final r in trip.riders) r.studentId == studentId ? changed : r]),
    );
    final type = switch (status) {
      TripRiderStatus.boarded => TripEventType.boarded,
      TripRiderStatus.dropped => TripEventType.dropped,
      _ => TripEventType.absent,
    };
    final currentStop = trip.stops.where((s) => s.id == trip.currentStopId).firstOrNull;
    return _replaceTrip(_withEvent(updated, type, stop: currentStop, rider: changed));
  }

  @override
  Future<TransportTrip> endTrip(int tripId) async {
    _check();
    lastCall = {'op': 'endTrip', 'trip_id': tripId};
    final trip = _trips.firstWhere((t) => t.id == tripId);
    final onBoard = trip.riders.where((r) => r.status == TripRiderStatus.boarded).length;
    if (onBoard > 0) {
      throw Failure(
        code: 'TRIP_RIDERS_ON_BOARD',
        message:
            '$onBoard ${onBoard == 1 ? 'student is' : 'students are'} still on board. Drop them off before ending the trip.',
      );
    }
    final riders = [
      for (final r in trip.riders) r.status == TripRiderStatus.pending ? r.copyWith(status: TripRiderStatus.absent) : r,
    ];
    final updated = _recount(trip.copyWith(status: TripStatus.completed, endedAt: _now, riders: riders));
    return _replaceTrip(_withEvent(updated, TripEventType.completed, note: 'Trip completed'));
  }

  @override
  Future<TransportTrip> cancelTrip(int tripId) async {
    _check();
    lastCall = {'op': 'cancelTrip', 'trip_id': tripId};
    final trip = _trips.firstWhere((t) => t.id == tripId);
    final updated = trip.copyWith(status: TripStatus.cancelled, endedAt: _now);
    return _replaceTrip(_withEvent(updated, TripEventType.cancelled, note: 'Trip cancelled'));
  }
}
