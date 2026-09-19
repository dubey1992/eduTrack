import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import 'models/permissions_matrix.dart';

final permissionsApiProvider = Provider<PermissionsApi>((ref) => PermissionsApi(ref.watch(dioClientProvider)));

class PermissionsApi {
  PermissionsApi(this._dio);

  final Dio _dio;

  Future<PermissionsMatrix> get() async {
    final response = await _dio.get('/settings/permissions');
    return PermissionsMatrix.fromJson(response.data as Map<String, dynamic>);
  }

  /// [changes] holds only the cells to move; the rest of the matrix is left
  /// as it is.
  Future<PermissionsMatrix> save(LevelGrid changes) async {
    final response = await _dio.put(
      '/settings/permissions',
      data: {
        'matrix': {
          for (final role in changes.entries)
            role.key: {for (final cell in role.value.entries) cell.key: cell.value.apiValue},
        },
      },
    );

    return PermissionsMatrix.fromJson(response.data as Map<String, dynamic>);
  }

  Future<PermissionsMatrix> reset() async {
    final response = await _dio.post('/settings/permissions/reset');
    return PermissionsMatrix.fromJson(response.data as Map<String, dynamic>);
  }
}
