import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import '../../transport/data/models/transport_trip.dart';
import 'models/location_point.dart';
import 'models/trip_mark.dart';

final myTripApiProvider = Provider<MyTripApi>((ref) => MyTripApi(ref.watch(dioClientProvider)));

/// The bus attendant's endpoints. Answers come back as the raw JSON, so the
/// repository can keep a copy on the phone for when there is no signal.
class MyTripApi {
  MyTripApi(this._dio);

  final Dio _dio;

  Future<Map<String, dynamic>> myRoutes() async {
    final response = await _dio.get('/transport/my-routes');
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> trip(int tripId) async {
    final response = await _dio.get('/transport/trips/$tripId');
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> startTrip({required int routeId, required TripDirection direction}) async {
    final response = await _dio.post('/transport/trips', data: {'route_id': routeId, 'direction': direction.apiValue});
    return response.data as Map<String, dynamic>;
  }

  /// `{results: [...], trip: {...}}`.
  Future<Map<String, dynamic>> sync(int tripId, List<TripMark> marks) async {
    final response = await _dio.post(
      '/transport/trips/$tripId/sync',
      data: {'operations': marks.map((m) => m.toSyncJson()).toList()},
    );
    return response.data as Map<String, dynamic>;
  }

  /// `{accepted, refused}`.
  Future<Map<String, dynamic>> sendLocations(int tripId, List<LocationPoint> points) async {
    final response = await _dio.post(
      '/transport/trips/$tripId/locations',
      data: {'points': points.map((p) => p.toApiJson()).toList()},
    );
    return response.data as Map<String, dynamic>;
  }
}
