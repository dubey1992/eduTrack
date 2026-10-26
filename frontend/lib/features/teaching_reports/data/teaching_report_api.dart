import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import '../../../core/network/paginated_response.dart';
import 'models/teaching_report.dart';
import 'models/teaching_report_summary.dart';

final teachingReportApiProvider = Provider<TeachingReportApi>((ref) => TeachingReportApi(ref.watch(dioClientProvider)));

class TeachingReportApi {
  TeachingReportApi(this._dio);

  final Dio _dio;

  Future<TeachingReport> store({
    required int timetableEntryId,
    required String reportDate,
    required String topicTaught,
    int? syllabusTopicId,
    String? homework,
    String? remarks,
  }) async {
    final response = await _dio.post(
      '/teaching-reports',
      data: {
        'timetable_entry_id': timetableEntryId,
        'report_date': reportDate,
        'topic_taught': topicTaught,
        'syllabus_topic_id': ?syllabusTopicId,
        'homework': homework,
        'remarks': remarks,
      },
    );
    return TeachingReport.fromJson(response.data as Map<String, dynamic>);
  }

  Future<PaginatedResponse<TeachingReport>> list({
    int? schoolId,
    int? teacherId,
    String? reportDate,
    bool mine = false,
    bool toReview = false,
    String? dateFrom,
    String? dateTo,
    int? page,
    int? perPage,
  }) async {
    final response = await _dio.get(
      '/teaching-reports',
      queryParameters: {
        'school_id': ?schoolId,
        'teacher_id': ?teacherId,
        'report_date': ?reportDate,
        if (mine) 'mine': 1,
        if (toReview) 'to_review': 1,
        'date_from': ?dateFrom,
        'date_to': ?dateTo,
        'page': ?page,
        'per_page': ?perPage,
      },
    );
    return PaginatedResponse.fromJson(response.data as Map<String, dynamic>, TeachingReport.fromJson);
  }

  Future<TeachingReport> get(int reportId) async {
    final response = await _dio.get('/teaching-reports/$reportId');
    return TeachingReport.fromJson(response.data as Map<String, dynamic>);
  }

  Future<TeachingReportSummary> summary({int? schoolId, required String date}) async {
    final response = await _dio.get(
      '/teaching-reports/summary',
      queryParameters: {'school_id': ?schoolId, 'date': date},
    );
    return TeachingReportSummary.fromJson(response.data as Map<String, dynamic>);
  }

  Future<TeachingReport> review(int reportId, {String? note}) async {
    final response = await _dio.patch(
      '/teaching-reports/$reportId/review',
      data: note == null || note.isEmpty ? null : {'note': note},
    );
    return TeachingReport.fromJson(response.data as Map<String, dynamic>);
  }

  Future<TeachingReport> sendBack(int reportId, {required String note}) async {
    final response = await _dio.patch('/teaching-reports/$reportId/return', data: {'note': note});
    return TeachingReport.fromJson(response.data as Map<String, dynamic>);
  }

  Future<TeachingReport> resubmit(
    int reportId, {
    required String topicTaught,
    String? homework,
    String? remarks,
  }) async {
    final response = await _dio.patch(
      '/teaching-reports/$reportId',
      data: {'topic_taught': topicTaught, 'homework': homework, 'remarks': remarks},
    );
    return TeachingReport.fromJson(response.data as Map<String, dynamic>);
  }
}
