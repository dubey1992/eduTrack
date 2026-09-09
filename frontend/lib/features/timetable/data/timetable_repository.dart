import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import 'models/day_of_week.dart';
import 'models/timetable_entry.dart';
import 'timetable_api.dart';

final timetableRepositoryProvider = Provider<TimetableRepository>(
  (ref) => TimetableRepository(ref.watch(timetableApiProvider)),
);

class TimetableRepository {
  TimetableRepository(this._api);

  final TimetableApi _api;

  Future<List<TimetableEntry>> grid({int? classSectionId, int? teacherId}) async {
    try {
      return await _api.grid(classSectionId: classSectionId, teacherId: teacherId);
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }

  Future<TimetableEntry> upsert({
    int? schoolId,
    required int classSectionId,
    required int periodId,
    required DayOfWeek dayOfWeek,
    required int subjectId,
    required int teacherId,
  }) async {
    try {
      return await _api.upsert(
        schoolId: schoolId,
        classSectionId: classSectionId,
        periodId: periodId,
        dayOfWeek: dayOfWeek,
        subjectId: subjectId,
        teacherId: teacherId,
      );
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }

  Future<void> delete(int entryId) async {
    try {
      await _api.delete(entryId);
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }
}
