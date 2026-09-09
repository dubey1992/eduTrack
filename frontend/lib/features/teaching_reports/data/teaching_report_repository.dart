import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import '../../../core/network/paginated_response.dart';
import 'models/teaching_report.dart';
import 'models/teaching_report_summary.dart';
import 'teaching_report_api.dart';

final teachingReportRepositoryProvider = Provider<TeachingReportRepository>(
  (ref) => TeachingReportRepository(ref.watch(teachingReportApiProvider)),
);

class TeachingReportRepository {
  TeachingReportRepository(this._api);

  final TeachingReportApi _api;

  Future<TeachingReport> store({
    required int timetableEntryId,
    required String reportDate,
    required String topicTaught,
    String? homework,
    String? remarks,
  }) async {
    try {
      return await _api.store(
        timetableEntryId: timetableEntryId,
        reportDate: reportDate,
        topicTaught: topicTaught,
        homework: homework,
        remarks: remarks,
      );
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }

  Future<PaginatedResponse<TeachingReport>> list({
    int? schoolId,
    int? teacherId,
    String? reportDate,
    required int page,
    required int perPage,
  }) async {
    try {
      return await _api.list(
        schoolId: schoolId,
        teacherId: teacherId,
        reportDate: reportDate,
        page: page,
        perPage: perPage,
      );
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }

  Future<TeachingReportSummary> summary({int? schoolId, required String date}) async {
    try {
      return await _api.summary(schoolId: schoolId, date: date);
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }

  Future<TeachingReport> review(int reportId) async {
    try {
      return await _api.review(reportId);
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }
}
