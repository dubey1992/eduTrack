import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';

/// Looking a place up, through the server (docs/maps.md, M1).
///
/// Never Google directly: the key that does the asking lives on the server,
/// which also caches the answers and rate-limits the asking. From here it is
/// three ordinary endpoints of this API.
class PlaceSuggestion {
  const PlaceSuggestion({required this.placeId, required this.label, required this.detail});

  factory PlaceSuggestion.fromJson(Map<String, dynamic> json) {
    return PlaceSuggestion(
      placeId: json['place_id'] as String? ?? '',
      label: json['label'] as String? ?? '',
      detail: json['detail'] as String? ?? '',
    );
  }

  final String placeId;

  /// The road or building - what somebody scans the list for.
  final String label;

  /// The town and state under it, which is how two roads of the same name
  /// are told apart.
  final String detail;
}

class FoundPlace {
  const FoundPlace({required this.label, required this.address, required this.latitude, required this.longitude});

  factory FoundPlace.fromJson(Map<String, dynamic> json) {
    return FoundPlace(
      label: json['label'] as String? ?? '',
      address: json['address'] as String? ?? '',
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
    );
  }

  final String label;
  final String address;
  final double latitude;
  final double longitude;
}

final placesRepositoryProvider = Provider<PlacesRepository>((ref) => PlacesRepository(ref.watch(dioClientProvider)));

class PlacesRepository {
  PlacesRepository(this._dio);

  final Dio _dio;

  /// **Never throws, and an empty list is the only failure.** Searching is
  /// a convenience on top of two boxes somebody can always type into, so a
  /// search that cannot be done must not stop them placing the pin by hand.
  Future<List<PlaceSuggestion>> search(String query, {double? nearLatitude, double? nearLongitude}) async {
    try {
      final response = await _dio.get(
        '/maps/places/autocomplete',
        queryParameters: {
          'q': query,
          if (nearLatitude != null && nearLongitude != null) ...{'near_lat': nearLatitude, 'near_lng': nearLongitude},
        },
      );
      final body = response.data;

      if (body is! Map<String, dynamic>) return const [];

      return [
        for (final suggestion in body['suggestions'] as List? ?? const [])
          if (suggestion is Map<String, dynamic>) PlaceSuggestion.fromJson(suggestion),
      ];
    } catch (_) {
      return const [];
    }
  }

  /// Where a suggestion actually is. Null when it could not be found out -
  /// the pin stays where it was and nothing moves under the person.
  Future<FoundPlace?> find(String placeId) async {
    try {
      final response = await _dio.get('/maps/places/$placeId');
      final body = response.data;

      if (body is! Map<String, dynamic>) return null;

      return FoundPlace.fromJson(body);
    } catch (_) {
      return null;
    }
  }

  /// A label for a point somebody clicked. Empty is a real answer - the sea
  /// has no address - so an empty string and a failure are the same here,
  /// and the picker simply shows no label.
  Future<String> describe(double latitude, double longitude) async {
    try {
      final response = await _dio.get('/maps/geocode/reverse', queryParameters: {'lat': latitude, 'lng': longitude});
      final body = response.data;

      if (body is! Map<String, dynamic>) return '';

      return body['address'] as String? ?? '';
    } catch (_) {
      return '';
    }
  }
}
