import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import 'models/syllabus_topic.dart';
import 'syllabus_topic_api.dart';

final syllabusTopicRepositoryProvider = Provider<SyllabusTopicRepository>(
  (ref) => SyllabusTopicRepository(ref.watch(syllabusTopicApiProvider)),
);

class SyllabusTopicRepository {
  SyllabusTopicRepository(this._api);

  final SyllabusTopicApi _api;

  Future<List<SyllabusTopic>> list({required int subjectId}) async {
    try {
      return await _api.list(subjectId: subjectId);
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }

  Future<SyllabusTopic> create({
    int? schoolId,
    required int subjectId,
    required String title,
    required int sequenceNumber,
  }) async {
    try {
      return await _api.create(schoolId: schoolId, subjectId: subjectId, title: title, sequenceNumber: sequenceNumber);
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }

  Future<SyllabusTopic> update(int topicId, {String? title, int? sequenceNumber}) async {
    try {
      return await _api.update(topicId, title: title, sequenceNumber: sequenceNumber);
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }

  Future<void> delete(int topicId) async {
    try {
      await _api.delete(topicId);
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }
}
