import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import 'models/school_pin.dart';

final schoolLocationsRepositoryProvider = Provider<SchoolLocationsRepository>(
  (ref) => SchoolLocationsRepository(ref.watch(dioClientProvider)),
);

/// Where the schools are (docs/maps.md, M1d).
///
/// **This one throws.** Unlike the map's key and its address search - both
/// conveniences that degrade quietly - an empty map that should have pins
/// on it is indistinguishable from a platform with no schools placed. So a
/// failure is shown and offered a retry, rather than drawn as emptiness.
class SchoolLocationsRepository {
  SchoolLocationsRepository(this._dio);

  final Dio _dio;

  Future<SchoolLocations> fetch() async {
    try {
      final response = await _dio.get('/schools/locations');
      final body = response.data;

      if (body is! Map<String, dynamic>) return const SchoolLocations.empty();

      return SchoolLocations.fromJson(body);
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }
}

/// Held for the screen rather than per build, and invalidated when a school
/// is added or edited - placing a school is the one thing that changes it.
final schoolLocationsProvider = FutureProvider<SchoolLocations>(
  (ref) => ref.watch(schoolLocationsRepositoryProvider).fetch(),
);
