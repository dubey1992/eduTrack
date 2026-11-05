import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import 'models/dashboard.dart';

final dashboardApiProvider = Provider<DashboardApi>((ref) => DashboardApi(ref.watch(dioClientProvider)));

class DashboardApi {
  DashboardApi(this._dio);

  final Dio _dio;

  /// [academicYearId] moves the Results card to that year's last term; every
  /// other figure is today's whatever the year.
  Future<Dashboard> fetch({int? schoolId, int? academicYearId}) async {
    final response = await _dio.get(
      '/dashboard',
      queryParameters: {'school_id': ?schoolId, 'academic_year_id': ?academicYearId},
    );

    return Dashboard.fromJson(response.data as Map<String, dynamic>);
  }
}
