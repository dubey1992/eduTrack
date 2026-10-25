import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import 'models/teacher_day.dart';

final todayApiProvider = Provider<TodayApi>((ref) => TodayApi(ref.watch(dioClientProvider)));

final todayRepositoryProvider = Provider<TodayRepository>((ref) => TodayRepository(ref.watch(todayApiProvider)));

class TodayApi {
  TodayApi(this._dio);

  final Dio _dio;

  /// Always the signed-in teacher's own day; the endpoint takes no teacher.
  Future<Map<String, dynamic>> today() async {
    final response = await _dio.get('/timetable/today');
    return response.data as Map<String, dynamic>;
  }
}

/// The teacher's day, for the Today screen (docs/teacher-app.md, T1).
class TodayRepository {
  TodayRepository(this._api);

  final TodayApi _api;

  Future<TeacherDay> today() async {
    try {
      return TeacherDay.fromJson(await _api.today());
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }
}
