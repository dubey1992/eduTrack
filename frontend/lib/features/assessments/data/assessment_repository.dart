import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import '../../../core/network/paginated_response.dart';
import 'assessment_api.dart';
import 'models/assessment.dart';
import 'models/assessment_sheet.dart';

final assessmentRepositoryProvider = Provider<AssessmentRepository>(
  (ref) => AssessmentRepository(ref.watch(assessmentApiProvider)),
);

class AssessmentRepository {
  AssessmentRepository(this._api);

  final AssessmentApi _api;

  Future<PaginatedResponse<Assessment>> listPage({
    int? schoolId,
    int? academicTermId,
    int? classSectionId,
    int? subjectId,
    String? status,
    String? type,
    required int page,
    required int perPage,
  }) {
    return _call(
      () => _api.list(
        schoolId: schoolId,
        academicTermId: academicTermId,
        classSectionId: classSectionId,
        subjectId: subjectId,
        status: status,
        type: type,
        page: page,
        perPage: perPage,
      ),
    );
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
  }) {
    return _call(
      () => _api.create(
        classSectionId: classSectionId,
        subjectId: subjectId,
        academicTermId: academicTermId,
        syllabusTopicId: syllabusTopicId,
        gradeScaleId: gradeScaleId,
        type: type,
        title: title,
        maxMarks: maxMarks,
        passMarks: passMarks,
        weightage: weightage,
        assessmentDate: assessmentDate,
      ),
    );
  }

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
  }) {
    return _call(
      () => _api.update(
        assessmentId,
        academicTermId: academicTermId,
        gradeScaleId: gradeScaleId,
        type: type,
        title: title,
        maxMarks: maxMarks,
        passMarks: passMarks,
        weightage: weightage,
        assessmentDate: assessmentDate,
      ),
    );
  }

  Future<void> delete(int assessmentId) => _call(() => _api.delete(assessmentId));

  Future<AssessmentSheet> sheet(int assessmentId) => _call(() => _api.sheet(assessmentId));

  Future<AssessmentSheet> saveMarks(int assessmentId, List<SheetEntry> entries) {
    return _call(() => _api.saveMarks(assessmentId, entries));
  }

  Future<T> _call<T>(Future<T> Function() request) async {
    try {
      return await request();
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }
}
