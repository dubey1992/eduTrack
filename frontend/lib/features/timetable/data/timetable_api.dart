import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import 'models/day_of_week.dart';
import 'models/timetable_entry.dart';

final timetableApiProvider = Provider<TimetableApi>((ref) => TimetableApi(ref.watch(dioClientProvider)));

class TimetableApi {
  TimetableApi(this._dio);

  final Dio _dio;

  Future<List<TimetableEntry>> grid({int? classSectionId, int? teacherId}) async {
    final response = await _dio.get(
      '/timetable',
      queryParameters: {'class_section_id': ?classSectionId, 'teacher_id': ?teacherId},
    );
    return (response.data as List).cast<Map<String, dynamic>>().map(TimetableEntry.fromJson).toList();
  }

  Future<TimetableEntry> upsert({
    int? schoolId,
    required int classSectionId,
    required int periodId,
    required DayOfWeek dayOfWeek,
    required int subjectId,
    required int teacherId,
  }) async {
    final response = await _dio.post(
      '/timetable',
      data: {
        'school_id': schoolId,
        'class_section_id': classSectionId,
        'period_id': periodId,
        'day_of_week': dayOfWeek.apiValue,
        'subject_id': subjectId,
        'teacher_id': teacherId,
      },
    );
    return TimetableEntry.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> delete(int entryId) async {
    await _dio.delete('/timetable/$entryId');
  }
}
