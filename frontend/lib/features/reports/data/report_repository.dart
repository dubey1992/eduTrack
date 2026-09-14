import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import 'models/report.dart';
import 'report_api.dart';

final reportRepositoryProvider = Provider<ReportRepository>(
  (ref) => ReportRepository(ref.watch(reportApiProvider)),
);

class ReportRepository {
  ReportRepository(this._api);

  final ReportApi _api;

  Future<ReportResult> fetch(
    ReportKind kind, {
    int? schoolId,
    String? from,
    String? to,
    int? classSectionId,
    int? departmentId,
  }) async {
    try {
      return await _api.fetch(
        kind,
        schoolId: schoolId,
        from: from,
        to: to,
        classSectionId: classSectionId,
        departmentId: departmentId,
      );
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }

  Future<List<int>> downloadCsv(
    ReportKind kind, {
    int? schoolId,
    String? from,
    String? to,
    int? classSectionId,
    int? departmentId,
  }) async {
    try {
      return await _api.downloadCsv(
        kind,
        schoolId: schoolId,
        from: from,
        to: to,
        classSectionId: classSectionId,
        departmentId: departmentId,
      );
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }
}
