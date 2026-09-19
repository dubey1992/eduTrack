import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import 'models/profile.dart';
import 'profile_api.dart';

final profileRepositoryProvider = Provider<ProfileRepository>(
  (ref) => ProfileRepository(ref.watch(profileApiProvider)),
);

/// Turns transport failures into the app's [Failure], so the screen shows
/// the server's own message (and its field errors) rather than an exception.
class ProfileRepository {
  ProfileRepository(this._api);

  final ProfileApi _api;

  Future<T> _call<T>(Future<T> Function() request) async {
    try {
      return await request();
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }

  Future<Profile> get() => _call(_api.get);

  /// [changes] holds only the fields being changed, keyed by their API name.
  Future<Profile> update(Map<String, String> changes) => _call(() => _api.update(changes));

  Future<Profile> changeEmail({required String email, required String currentPassword}) {
    return _call(() => _api.changeEmail(email: email, currentPassword: currentPassword));
  }

  Future<Profile> uploadPhoto({required List<int> bytes, required String fileName}) {
    return _call(() => _api.uploadPhoto(bytes: bytes, fileName: fileName));
  }

  Future<Profile> removePhoto() => _call(_api.removePhoto);
}
