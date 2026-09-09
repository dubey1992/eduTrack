import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import 'hod_report_api.dart';
import 'models/hod_department_report.dart';

final hodReportRepositoryProvider = Provider<HodReportRepository>(
  (ref) => HodReportRepository(ref.watch(hodReportApiProvider)),
);

class HodReportRepository {
  HodReportRepository(this._api);

  final HodReportApi _api;

  Future<HodDepartmentReport> departmentReport({
    int? schoolId,
    int? departmentId,
    required String month,
    required int page,
    required int perPage,
  }) async {
    try {
      return await _api.departmentReport(
        schoolId: schoolId,
        departmentId: departmentId,
        month: month,
        page: page,
        perPage: perPage,
      );
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }
}
