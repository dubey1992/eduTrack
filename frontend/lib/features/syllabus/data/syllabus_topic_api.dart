import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import 'models/syllabus_topic.dart';

final syllabusTopicApiProvider = Provider<SyllabusTopicApi>((ref) => SyllabusTopicApi(ref.watch(dioClientProvider)));

class SyllabusTopicApi {
  SyllabusTopicApi(this._dio);

  final Dio _dio;

  /// The subject's topics - only those a class follows, when
  /// [classSectionId] or the period's [timetableEntryId] names one.
  Future<List<SyllabusTopic>> list({required int subjectId, int? classSectionId, int? timetableEntryId}) async {
    final response = await _dio.get(
      '/syllabus-topics',
      queryParameters: {
        'subject_id': subjectId,
        'class_section_id': ?classSectionId,
        'timetable_entry_id': ?timetableEntryId,
      },
    );
    return (response.data as List).cast<Map<String, dynamic>>().map(SyllabusTopic.fromJson).toList();
  }

  Future<SyllabusTopic> create({
    int? schoolId,
    required int subjectId,
    required String title,
    required int sequenceNumber,
    int? classLevel,
  }) async {
    final response = await _dio.post(
      '/syllabus-topics',
      data: {
        'school_id': schoolId,
        'subject_id': subjectId,
        'class_level': classLevel,
        'title': title,
        'sequence_number': sequenceNumber,
      },
    );
    return SyllabusTopic.fromJson(response.data as Map<String, dynamic>);
  }

  /// With [setClass], [classLevel] is sent even when null - null being
  /// "every class".
  Future<SyllabusTopic> update(
    int topicId, {
    String? title,
    int? sequenceNumber,
    bool setClass = false,
    int? classLevel,
  }) async {
    final response = await _dio.patch(
      '/syllabus-topics/$topicId',
      data: {'title': ?title, 'sequence_number': ?sequenceNumber, if (setClass) 'class_level': classLevel},
    );
    return SyllabusTopic.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> delete(int topicId) async {
    await _dio.delete('/syllabus-topics/$topicId');
  }
}
