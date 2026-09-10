import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import '../../../core/network/paginated_response.dart';
import 'models/driver.dart';
import 'models/transport_route.dart';
import 'models/transport_status.dart';
import 'models/vehicle.dart';
import 'transport_api.dart';

final transportRepositoryProvider = Provider<TransportRepository>(
  (ref) => TransportRepository(ref.watch(transportApiProvider)),
);

class TransportRepository {
  TransportRepository(this._api);

  final TransportApi _api;

  /// Pickers ask for the biggest page the API allows - a school never has
  /// anywhere near 100 buses, drivers or routes.
  static const pickerPageSize = 100;

  Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }

  // ── vehicles ────────────────────────────────────────────────────────

  Future<PaginatedResponse<Vehicle>> listVehicles({
    int? schoolId,
    TransportStatus? status,
    required int page,
    required int perPage,
  }) => _guard(() => _api.listVehicles(schoolId: schoolId, status: status, page: page, perPage: perPage));

  Future<List<Vehicle>> activeVehicles({int? schoolId}) => _guard(() async {
    final page = await _api.listVehicles(schoolId: schoolId, status: TransportStatus.active, perPage: pickerPageSize);
    return page.items;
  });

  Future<Vehicle> createVehicle({
    int? schoolId,
    required String name,
    required String registrationNumber,
    required int capacity,
  }) => _guard(
    () =>
        _api.createVehicle(schoolId: schoolId, name: name, registrationNumber: registrationNumber, capacity: capacity),
  );

  Future<Vehicle> updateVehicle(
    int vehicleId, {
    String? name,
    String? registrationNumber,
    int? capacity,
    TransportStatus? status,
  }) => _guard(
    () => _api.updateVehicle(
      vehicleId,
      name: name,
      registrationNumber: registrationNumber,
      capacity: capacity,
      status: status,
    ),
  );

  Future<void> deleteVehicle(int vehicleId) => _guard(() => _api.deleteVehicle(vehicleId));

  // ── drivers ─────────────────────────────────────────────────────────

  Future<PaginatedResponse<Driver>> listDrivers({
    int? schoolId,
    TransportStatus? status,
    required int page,
    required int perPage,
  }) => _guard(() => _api.listDrivers(schoolId: schoolId, status: status, page: page, perPage: perPage));

  Future<List<Driver>> activeDrivers({int? schoolId}) => _guard(() async {
    final page = await _api.listDrivers(schoolId: schoolId, status: TransportStatus.active, perPage: pickerPageSize);
    return page.items;
  });

  Future<Driver> createDriver({
    int? schoolId,
    required String name,
    String? mobile,
    required String licenceNumber,
    String? licenceExpiry,
  }) => _guard(
    () => _api.createDriver(
      schoolId: schoolId,
      name: name,
      mobile: mobile,
      licenceNumber: licenceNumber,
      licenceExpiry: licenceExpiry,
    ),
  );

  Future<Driver> updateDriver(
    int driverId, {
    String? name,
    String? mobile,
    String? licenceNumber,
    String? licenceExpiry,
    TransportStatus? status,
  }) => _guard(
    () => _api.updateDriver(
      driverId,
      name: name,
      mobile: mobile,
      licenceNumber: licenceNumber,
      licenceExpiry: licenceExpiry,
      status: status,
    ),
  );

  Future<void> deleteDriver(int driverId) => _guard(() => _api.deleteDriver(driverId));

  // ── routes ──────────────────────────────────────────────────────────

  Future<PaginatedResponse<TransportRoute>> listRoutes({
    int? schoolId,
    TransportStatus? status,
    required int page,
    required int perPage,
  }) => _guard(() => _api.listRoutes(schoolId: schoolId, status: status, page: page, perPage: perPage));

  Future<List<TransportRoute>> activeRoutes({int? schoolId}) => _guard(() async {
    final page = await _api.listRoutes(schoolId: schoolId, status: TransportStatus.active, perPage: pickerPageSize);
    return page.items;
  });

  Future<TransportRoute> getRoute(int routeId) => _guard(() => _api.getRoute(routeId));

  Future<TransportRoute> createRoute({int? schoolId, required String name, int? vehicleId, int? driverId}) =>
      _guard(() => _api.createRoute(schoolId: schoolId, name: name, vehicleId: vehicleId, driverId: driverId));

  Future<TransportRoute> updateRoute(
    int routeId, {
    String? name,
    required int? vehicleId,
    required int? driverId,
    TransportStatus? status,
  }) => _guard(() => _api.updateRoute(routeId, name: name, vehicleId: vehicleId, driverId: driverId, status: status));

  Future<void> deleteRoute(int routeId) => _guard(() => _api.deleteRoute(routeId));

  Future<PaginatedResponse<RouteStudent>> listRouteStudents(int routeId, {required int page, required int perPage}) =>
      _guard(() => _api.listRouteStudents(routeId, page: page, perPage: perPage));

  // ── stops ───────────────────────────────────────────────────────────

  Future<TransportStop> createStop(
    int routeId, {
    required String name,
    required int sequenceNumber,
    String? pickupTime,
    String? dropTime,
  }) => _guard(
    () => _api.createStop(
      routeId,
      name: name,
      sequenceNumber: sequenceNumber,
      pickupTime: pickupTime,
      dropTime: dropTime,
    ),
  );

  Future<TransportStop> updateStop(
    int stopId, {
    String? name,
    int? sequenceNumber,
    String? pickupTime,
    String? dropTime,
  }) => _guard(
    () =>
        _api.updateStop(stopId, name: name, sequenceNumber: sequenceNumber, pickupTime: pickupTime, dropTime: dropTime),
  );

  Future<void> deleteStop(int stopId) => _guard(() => _api.deleteStop(stopId));
}
