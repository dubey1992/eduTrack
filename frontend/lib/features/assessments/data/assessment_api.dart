import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/network/dio_client.dart';
import '../../../core/network/paginated_response.dart';
import 'models/assessment.dart';
import 'models/assessment_sheet.dart';

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

  Future<AssessmentSheet> sheet(int assessmentId) async {
    final response = await _dio.get('/assessments/$assessmentId/marks');

    return AssessmentSheet.fromJson(response.data as Map<String, dynamic>);
  }

  /// The whole sheet in one write. A class of forty entered on a phone in a
  /// staffroom cannot afford forty round trips, and a half-saved sheet is
  /// worse than an unsaved one.
  Future<AssessmentSheet> saveMarks(int assessmentId, List<SheetEntry> entries) async {
    final response = await _dio.put(
      '/assessments/$assessmentId/marks',
      data: {
        'marks': [for (final entry in entries) entry.toJson()],
      },
    );

    return AssessmentSheet.fromJson(response.data as Map<String, dynamic>);
  }

  /// The marks sheet as a spreadsheet, with the class already on it. A token
  /// does not belong in a link, so this goes through the authenticated
  /// client and comes back as bytes.
  Future<List<int>> marksTemplate(int assessmentId) async {
    final response = await _dio.get<List<int>>(
      '/assessments/$assessmentId/marks/template',
      options: Options(responseType: ResponseType.bytes),
    );

    return response.data ?? const [];
  }

  Future<AssessmentSheet> uploadMarks(int assessmentId, {required String fileName, required List<int> bytes}) async {
    final form = FormData.fromMap({'file': MultipartFile.fromBytes(bytes, filename: fileName)});

    final response = await _dio.post('/assessments/$assessmentId/marks/import', data: form);

    return AssessmentSheet.fromJson(response.data as Map<String, dynamic>);
  }

  Future<Assessment> publish(int assessmentId) async {
    final response = await _dio.post('/assessments/$assessmentId/publish');

    return Assessment.fromJson(response.data as Map<String, dynamic>);
  }

  Future<Assessment> reopen(int assessmentId) async {
    final response = await _dio.post('/assessments/$assessmentId/reopen');

    return Assessment.fromJson(response.data as Map<String, dynamic>);
  }

  /// What the file would save. Nothing is written.
  Future<MarksPreview> previewMarks(int assessmentId, {required String fileName, required List<int> bytes}) async {
    final form = FormData.fromMap({'file': MultipartFile.fromBytes(bytes, filename: fileName)});

    final response = await _dio.post('/assessments/$assessmentId/marks/preview', data: form);

    return MarksPreview.fromJson(response.data as Map<String, dynamic>);
  }
}
