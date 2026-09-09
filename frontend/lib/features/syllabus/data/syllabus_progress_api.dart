import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import 'models/syllabus_checklist.dart';

final syllabusProgressApiProvider = Provider<SyllabusProgressApi>(
  (ref) => SyllabusProgressApi(ref.watch(dioClientProvider)),
);

class SyllabusProgressApi {
  SyllabusProgressApi(this._dio);

  final Dio _dio;

  Future<SyllabusChecklist> checklist({required int classSectionId, required int subjectId}) async {
    final response = await _dio.get(
      '/syllabus-progress',
      queryParameters: {'class_section_id': classSectionId, 'subject_id': subjectId},
    );
    return SyllabusChecklist.fromJson(response.data as Map<String, dynamic>);
  }

  Future<SyllabusChecklist> toggle({
    required int syllabusTopicId,
    required int classSectionId,
    required bool completed,
  }) async {
    final response = await _dio.patch(
      '/syllabus-progress',
      data: {'syllabus_topic_id': syllabusTopicId, 'class_section_id': classSectionId, 'completed': completed},
    );
    return SyllabusChecklist.fromJson(response.data as Map<String, dynamic>);
  }
}
