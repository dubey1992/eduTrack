import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import 'models/syllabus_checklist.dart';
import 'syllabus_progress_api.dart';

final syllabusProgressRepositoryProvider = Provider<SyllabusProgressRepository>(
  (ref) => SyllabusProgressRepository(ref.watch(syllabusProgressApiProvider)),
);

class SyllabusProgressRepository {
  SyllabusProgressRepository(this._api);

  final SyllabusProgressApi _api;

  Future<SyllabusChecklist> checklist({required int classSectionId, required int subjectId}) async {
    try {
      return await _api.checklist(classSectionId: classSectionId, subjectId: subjectId);
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }

  Future<SyllabusChecklist> toggle({
    required int syllabusTopicId,
    required int classSectionId,
    required bool completed,
  }) async {
    try {
      return await _api.toggle(syllabusTopicId: syllabusTopicId, classSectionId: classSectionId, completed: completed);
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }
}
