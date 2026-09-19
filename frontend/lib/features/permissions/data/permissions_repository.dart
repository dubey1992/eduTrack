import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import 'models/permissions_matrix.dart';
import 'permissions_api.dart';

final permissionsRepositoryProvider = Provider<PermissionsRepository>(
  (ref) => PermissionsRepository(ref.watch(permissionsApiProvider)),
);

/// Turns transport failures into the app's [Failure], so the screen shows
/// the server's own sentence rather than an exception.
class PermissionsRepository {
  PermissionsRepository(this._api);

  final PermissionsApi _api;

  Future<T> _call<T>(Future<T> Function() request) async {
    try {
      return await request();
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }

  Future<PermissionsMatrix> get() => _call(_api.get);

  /// [changes] holds only the cells to move.
  Future<PermissionsMatrix> save(LevelGrid changes) => _call(() => _api.save(changes));

  Future<PermissionsMatrix> reset() => _call(_api.reset);
}
