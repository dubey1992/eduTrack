import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import 'dashboard_api.dart';
import 'models/dashboard.dart';

final dashboardRepositoryProvider = Provider<DashboardRepository>(
  (ref) => DashboardRepository(ref.watch(dashboardApiProvider)),
);

class DashboardRepository {
  DashboardRepository(this._api);

  final DashboardApi _api;

  Future<Dashboard> fetch({int? schoolId}) async {
    try {
      return await _api.fetch(schoolId: schoolId);
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }
}
