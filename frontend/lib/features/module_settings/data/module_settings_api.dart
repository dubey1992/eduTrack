import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import 'models/module_setting.dart';

final moduleSettingsApiProvider = Provider<ModuleSettingsApi>((ref) => ModuleSettingsApi(ref.watch(dioClientProvider)));

class ModuleSettingsApi {
  ModuleSettingsApi(this._dio);

  final Dio _dio;

  /// [schoolId] is required of a Super Admin and ignored for a School Admin,
  /// whose own school is used.
  Future<List<ModuleSetting>> list({int? schoolId}) async {
    final response = await _dio.get('/settings/modules', queryParameters: {'school_id': ?schoolId});
    final rows = response.data as List;

    return [for (final row in rows) ModuleSetting.fromJson(row as Map<String, dynamic>)];
  }

  /// Sends only what was passed: a switch on its own, or the settings on
  /// their own, so a save never touches what the form did not mean to.
  Future<ModuleSetting> update(
    String module, {
    int? schoolId,
    bool? platformEnabled,
    bool? schoolEnabled,
    Map<String, Object?>? settings,
  }) async {
    final response = await _dio.put(
      '/settings/modules/$module',
      data: {
        'school_id': ?schoolId,
        'platform_enabled': ?platformEnabled,
        'school_enabled': ?schoolEnabled,
        'settings': ?settings,
      },
    );

    return ModuleSetting.fromJson(response.data as Map<String, dynamic>);
  }
}
