import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/network/dio_client.dart';
import '../../../core/network/paginated_response.dart';
import 'models/assessment.dart';

final assessmentApiProvider = Provider<AssessmentApi>((ref) => AssessmentApi(ref.watch(dioClientProvider)));

class AssessmentApi {
  AssessmentApi(this._dio);

  final Dio _dio;

  static final _date = DateFormat('yyyy-MM-dd');

  Future<PaginatedResponse<Assessment>> list({
    int? schoolId,
    int? academicTermId,
    int? classSectionId,
    int? subjectId,
    String? status,
    String? type,
    int? page,
    int? perPage,
  }) async {
    final response = await _dio.get(
      '/assessments',
      queryParameters: {
        'school_id': ?schoolId,
        'academic_term_id': ?academicTermId,
        'class_section_id': ?classSectionId,
        'subject_id': ?subjectId,
        'status': ?status,
        'type': ?type,
        'page': ?page,
        'per_page': ?perPage,
      },
    );

    return PaginatedResponse.fromJson(response.data as Map<String, dynamic>, Assessment.fromJson);
  }

  Future<Assessment> create({
    required int classSectionId,
    required int subjectId,
    required int academicTermId,
    int? syllabusTopicId,
    int? gradeScaleId,
    required String type,
    required String title,
    required String maxMarks,
    String? passMarks,
    String? weightage,
    required DateTime assessmentDate,
  }) async {
    final response = await _dio.post(
      '/assessments',
      data: {
        // The school and the year come from the section server-side, so
        // neither is sent.
        'class_section_id': classSectionId,
        'subject_id': subjectId,
        'academic_term_id': academicTermId,
        'syllabus_topic_id': syllabusTopicId,
        'grade_scale_id': gradeScaleId,
        'type': type,
        'title': title,
        'max_marks': maxMarks,
        'pass_marks': passMarks,
        'weightage': weightage,
        'assessment_date': _date.format(assessmentDate),
      },
    );

    return Assessment.fromJson(response.data as Map<String, dynamic>);
  }

  /// The section and the subject are fixed at creation, so neither is sent.
  /// The nullable fields are sent as they are, including null, because
  /// clearing a pass mark is a thing somebody may mean.
  Future<Assessment> update(
    int assessmentId, {
    int? academicTermId,
    int? gradeScaleId,
    String? type,
    String? title,
    String? maxMarks,
    String? passMarks,
    String? weightage,
    DateTime? assessmentDate,
  }) async {
    final response = await _dio.patch(
      '/assessments/$assessmentId',
      data: {
        'academic_term_id': ?academicTermId,
        'grade_scale_id': gradeScaleId,
        'type': ?type,
        'title': ?title,
        'max_marks': ?maxMarks,
        'pass_marks': passMarks,
        'weightage': weightage,
        'assessment_date': ?(assessmentDate == null ? null : _date.format(assessmentDate)),
      },
    );

    return Assessment.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> delete(int assessmentId) async {
    await _dio.delete('/assessments/$assessmentId');
  }
}
