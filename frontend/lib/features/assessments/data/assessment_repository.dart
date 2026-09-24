import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import '../../../core/network/paginated_response.dart';
import '../../imports/data/import_repository.dart';
import '../../imports/data/models/import_result.dart';
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

  Future<List<int>> marksTemplate(int assessmentId) => _call(() => _api.marksTemplate(assessmentId));

  /// A refused file throws [BulkImportFailure], carrying the rows that need
  /// fixing - the same shape the other uploads use, so the screen can list
  /// them with the same widget.
  Future<AssessmentSheet> uploadMarks(int assessmentId, {required String fileName, required List<int> bytes}) async {
    try {
      return await _api.uploadMarks(assessmentId, fileName: fileName, bytes: bytes);
    } on DioException catch (e) {
      final failure = failureFromDioException(e);

      if (failure.code == 'BULK_IMPORT_FAILED') {
        throw BulkImportFailure(
          message: failure.message,
          rows: (failure.details['rows'] as List? ?? const [])
              .cast<Map<String, dynamic>>()
              .map(ImportRowError.fromJson)
              .toList(growable: false),
        );
      }

      throw failure;
    }
  }

  Future<Assessment> publish(int assessmentId) => _call(() => _api.publish(assessmentId));

  Future<Assessment> reopen(int assessmentId) => _call(() => _api.reopen(assessmentId));

  /// A refused file throws [BulkImportFailure], the same as the upload does.
  Future<MarksPreview> previewMarks(int assessmentId, {required String fileName, required List<int> bytes}) async {
    try {
      return await _api.previewMarks(assessmentId, fileName: fileName, bytes: bytes);
    } on DioException catch (e) {
      final failure = failureFromDioException(e);

      if (failure.code == 'BULK_IMPORT_FAILED') {
        throw BulkImportFailure(
          message: failure.message,
          rows: (failure.details['rows'] as List? ?? const [])
              .cast<Map<String, dynamic>>()
              .map(ImportRowError.fromJson)
              .toList(growable: false),
        );
      }

      throw failure;
    }
  }

  Future<T> _call<T>(Future<T> Function() request) async {
    try {
      return await request();
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }
}
