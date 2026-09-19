import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import 'models/module_setting.dart';
import 'module_settings_api.dart';

final moduleSettingsRepositoryProvider = Provider<ModuleSettingsRepository>(
  (ref) => ModuleSettingsRepository(ref.watch(moduleSettingsApiProvider)),
);

/// Turns transport failures into the app's [Failure], so a card shows the
/// server's own sentence (and which control it is about) rather than an
/// exception.
class ModuleSettingsRepository {
  ModuleSettingsRepository(this._api);

  final ModuleSettingsApi _api;

  Future<T> _call<T>(Future<T> Function() request) async {
    try {
      return await request();
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }

  Future<List<ModuleSetting>> list({int? schoolId}) => _call(() => _api.list(schoolId: schoolId));

  Future<ModuleSetting> update(
    String module, {
    int? schoolId,
    bool? platformEnabled,
    bool? schoolEnabled,
    Map<String, Object?>? settings,
  }) {
    return _call(
      () => _api.update(
        module,
        schoolId: schoolId,
        platformEnabled: platformEnabled,
        schoolEnabled: schoolEnabled,
        settings: settings,
      ),
    );
  }
}
