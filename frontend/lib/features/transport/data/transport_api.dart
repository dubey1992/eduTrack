import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import '../../../core/network/paginated_response.dart';
import 'models/driver.dart';
import 'models/transport_route.dart';
import 'models/transport_status.dart';
import 'models/vehicle.dart';

final transportApiProvider = Provider<TransportApi>((ref) => TransportApi(ref.watch(dioClientProvider)));

/// Vehicles, drivers, routes and stops - one client for the whole
/// `/transport/*` namespace (they are always managed together).
class TransportApi {
  TransportApi(this._dio);

  final Dio _dio;

  // ── vehicles ────────────────────────────────────────────────────────

  Future<PaginatedResponse<Vehicle>> listVehicles({
    int? schoolId,
    TransportStatus? status,
    int? page,
    int? perPage,
  }) async {
    final response = await _dio.get(
      '/transport/vehicles',
      queryParameters: {'school_id': ?schoolId, 'status': ?status?.apiValue, 'page': ?page, 'per_page': ?perPage},
    );
    return PaginatedResponse.fromJson(response.data as Map<String, dynamic>, Vehicle.fromJson);
  }

  Future<Vehicle> createVehicle({
    int? schoolId,
    required String name,
    required String registrationNumber,
    required int capacity,
  }) async {
    final response = await _dio.post(
      '/transport/vehicles',
      data: {'school_id': schoolId, 'name': name, 'registration_number': registrationNumber, 'capacity': capacity},
    );
    return Vehicle.fromJson(response.data as Map<String, dynamic>);
  }

  Future<Vehicle> updateVehicle(
    int vehicleId, {
    String? name,
    String? registrationNumber,
    int? capacity,
    TransportStatus? status,
  }) async {
    final response = await _dio.patch(
      '/transport/vehicles/$vehicleId',
      data: {
        'name': ?name,
        'registration_number': ?registrationNumber,
        'capacity': ?capacity,
        'status': ?status?.apiValue,
      },
    );
    return Vehicle.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> deleteVehicle(int vehicleId) async {
    await _dio.delete('/transport/vehicles/$vehicleId');
  }

  // ── drivers ─────────────────────────────────────────────────────────

  Future<PaginatedResponse<Driver>> listDrivers({
    int? schoolId,
    TransportStatus? status,
    int? page,
    int? perPage,
  }) async {
    final response = await _dio.get(
      '/transport/drivers',
      queryParameters: {'school_id': ?schoolId, 'status': ?status?.apiValue, 'page': ?page, 'per_page': ?perPage},
    );
    return PaginatedResponse.fromJson(response.data as Map<String, dynamic>, Driver.fromJson);
  }

  Future<Driver> createDriver({
    int? schoolId,
    required String name,
    String? mobile,
    required String licenceNumber,
    String? licenceExpiry,
  }) async {
    final response = await _dio.post(
      '/transport/drivers',
      data: {
        'school_id': schoolId,
        'name': name,
        'mobile': mobile,
        'licence_number': licenceNumber,
        'licence_expiry': licenceExpiry,
      },
    );
    return Driver.fromJson(response.data as Map<String, dynamic>);
  }

  Future<Driver> updateDriver(
    int driverId, {
    String? name,
    String? mobile,
    String? licenceNumber,
    String? licenceExpiry,
    TransportStatus? status,
  }) async {
    final response = await _dio.patch(
      '/transport/drivers/$driverId',
      data: {
        'name': ?name,
        'mobile': mobile,
        'licence_number': ?licenceNumber,
        'licence_expiry': licenceExpiry,
        'status': ?status?.apiValue,
      },
    );
    return Driver.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> deleteDriver(int driverId) async {
    await _dio.delete('/transport/drivers/$driverId');
  }

  // ── routes ──────────────────────────────────────────────────────────

  Future<PaginatedResponse<TransportRoute>> listRoutes({
    int? schoolId,
    TransportStatus? status,
    int? page,
    int? perPage,
  }) async {
    final response = await _dio.get(
      '/transport/routes',
      queryParameters: {'school_id': ?schoolId, 'status': ?status?.apiValue, 'page': ?page, 'per_page': ?perPage},
    );
    return PaginatedResponse.fromJson(response.data as Map<String, dynamic>, TransportRoute.fromJson);
  }

  Future<TransportRoute> getRoute(int routeId) async {
    final response = await _dio.get('/transport/routes/$routeId');
    return TransportRoute.fromJson(response.data as Map<String, dynamic>);
  }

  Future<TransportRoute> createRoute({int? schoolId, required String name, int? vehicleId, int? driverId}) async {
    final response = await _dio.post(
      '/transport/routes',
      data: {'school_id': schoolId, 'name': name, 'vehicle_id': vehicleId, 'driver_id': driverId},
    );
    return TransportRoute.fromJson(response.data as Map<String, dynamic>);
  }

  /// [vehicleId]/[driverId] are always sent (null clears the attachment).
  Future<TransportRoute> updateRoute(
    int routeId, {
    String? name,
    required int? vehicleId,
    required int? driverId,
    TransportStatus? status,
  }) async {
    final response = await _dio.patch(
      '/transport/routes/$routeId',
      data: {'name': ?name, 'vehicle_id': vehicleId, 'driver_id': driverId, 'status': ?status?.apiValue},
    );
    return TransportRoute.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> deleteRoute(int routeId) async {
    await _dio.delete('/transport/routes/$routeId');
  }

  Future<PaginatedResponse<RouteStudent>> listRouteStudents(int routeId, {int? page, int? perPage}) async {
    final response = await _dio.get(
      '/transport/routes/$routeId/students',
      queryParameters: {'page': ?page, 'per_page': ?perPage},
    );
    return PaginatedResponse.fromJson(response.data as Map<String, dynamic>, RouteStudent.fromJson);
  }

  // ── stops ───────────────────────────────────────────────────────────

  Future<TransportStop> createStop(
    int routeId, {
    required String name,
    required int sequenceNumber,
    String? pickupTime,
    String? dropTime,
  }) async {
    final response = await _dio.post(
      '/transport/routes/$routeId/stops',
      data: {'name': name, 'sequence_number': sequenceNumber, 'pickup_time': pickupTime, 'drop_time': dropTime},
    );
    return TransportStop.fromJson(response.data as Map<String, dynamic>);
  }

  Future<TransportStop> updateStop(
    int stopId, {
    String? name,
    int? sequenceNumber,
    String? pickupTime,
    String? dropTime,
  }) async {
    final response = await _dio.patch(
      '/transport/stops/$stopId',
      data: {'name': ?name, 'sequence_number': ?sequenceNumber, 'pickup_time': pickupTime, 'drop_time': dropTime},
    );
    return TransportStop.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> deleteStop(int stopId) async {
    await _dio.delete('/transport/stops/$stopId');
  }
}
