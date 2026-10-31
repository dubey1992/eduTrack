import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import 'models/setup_guide.dart';

final setupGuideApiProvider = Provider<SetupGuideApi>((ref) => SetupGuideApi(ref.watch(dioClientProvider)));

final setupGuideRepositoryProvider = Provider<SetupGuideRepository>(
  (ref) => SetupGuideRepository(ref.watch(setupGuideApiProvider)),
);

class SetupGuideApi {
  SetupGuideApi(this._dio);

  final Dio _dio;

  Future<SetupGuide> show() async => _guide(await _dio.get('/setup-guide'));

  Future<SetupGuide> close() async => _guide(await _dio.post('/setup-guide/close'));

  Future<SetupGuide> reopen() async => _guide(await _dio.post('/setup-guide/reopen'));

  Future<List<DepartmentPreset>> departmentPresets() async {
    final response = await _dio.get('/departments/quick-setup');
    return [
      for (final row in (response.data as Map<String, dynamic>)['departments'] as List)
        DepartmentPreset.fromJson(row as Map<String, dynamic>),
    ];
  }

  Future<QuickDepartmentsResult> addDepartments(List<String> names) async {
    final response = await _dio.post('/departments/quick-setup', data: {'names': names});
    return QuickDepartmentsResult.fromJson(response.data as Map<String, dynamic>);
  }

  SetupGuide _guide(Response<dynamic> response) => SetupGuide.fromJson(response.data as Map<String, dynamic>);
}

class SetupGuideRepository {
  SetupGuideRepository(this._api);

  final SetupGuideApi _api;

  Future<SetupGuide> show() => _guarded(_api.show);

  Future<SetupGuide> close() => _guarded(_api.close);

  Future<SetupGuide> reopen() => _guarded(_api.reopen);

  Future<List<DepartmentPreset>> departmentPresets() => _guarded(_api.departmentPresets);

  Future<QuickDepartmentsResult> addDepartments(List<String> names) => _guarded(() => _api.addDepartments(names));

  Future<T> _guarded<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }
}
