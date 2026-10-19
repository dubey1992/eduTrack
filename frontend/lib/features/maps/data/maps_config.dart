import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';

/// Whether this installation can draw a map, and the key to draw it with
/// (docs/maps.md, M1).
///
/// The key is not in the build. It comes from the server, so it can be
/// rotated without shipping a new one and development and production can
/// differ from a single build. It is public either way - any map on the web
/// publishes its key - and what protects it is the referrer and package
/// restrictions set on it in Google Cloud.
class MapsConfig {
  const MapsConfig.withKey(this.browserKey);

  /// No key, which is what every screen falls back to until one is set up.
  const MapsConfig.none() : browserKey = '';

  factory MapsConfig.fromJson(Map<String, dynamic> json) {
    final key = json['browser_key'];

    if (json['available'] != true || key is! String) return const MapsConfig.none();

    return MapsConfig.withKey(key.trim());
  }

  final String browserKey;

  /// **A getter rather than a field the server sets.** "Available, and here
  /// is no key" is a state nothing should be able to build: the widget would
  /// try to draw a map that cannot load, and the screen would show a broken
  /// frame instead of the sentence explaining why.
  bool get available => browserKey.isNotEmpty;
}

final mapsConfigRepositoryProvider = Provider<MapsConfigRepository>(
  (ref) => MapsConfigRepository(ref.watch(dioClientProvider)),
);

class MapsConfigRepository {
  MapsConfigRepository(this._dio);

  final Dio _dio;

  /// **Never throws.** A map is an improvement on a screen, never the screen
  /// itself: the schools list, the stop list and the trip still work without
  /// one. Anything that goes wrong here is the same as having no key.
  Future<MapsConfig> fetch() async {
    try {
      final response = await _dio.get('/maps/config');
      final body = response.data;

      if (body is! Map<String, dynamic>) return const MapsConfig.none();

      return MapsConfig.fromJson(body);
    } catch (_) {
      return const MapsConfig.none();
    }
  }
}

/// Asked once per sign-in and held, because the answer is the same for every
/// map on every screen and does not change while somebody is signed in.
final mapsConfigProvider = FutureProvider<MapsConfig>((ref) => ref.watch(mapsConfigRepositoryProvider).fetch());
