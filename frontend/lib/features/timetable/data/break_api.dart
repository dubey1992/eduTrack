import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import 'models/school_break.dart';

final breakApiProvider = Provider<BreakApi>((ref) => BreakApi(ref.watch(dioClientProvider)));

class BreakApi {
  BreakApi(this._dio);

  final Dio _dio;

  Future<List<SchoolBreak>> list({int? schoolId}) async {
    final response = await _dio.get('/breaks', queryParameters: {'school_id': ?schoolId});
    return (response.data as List).cast<Map<String, dynamic>>().map(SchoolBreak.fromJson).toList();
  }

  /// [makeRoom] moves every later period and break of that day back so this
  /// one fits.
  Future<SchoolBreak> create({
    int? schoolId,
    required String name,
    required String dayShape,
    required String startTime,
    required String endTime,
    bool makeRoom = false,
  }) async {
    final response = await _dio.post(
      '/breaks',
      data: {
        'school_id': schoolId,
        'name': name,
        'day_shape': dayShape,
        'start_time': startTime,
        'end_time': endTime,
        'make_room': makeRoom,
      },
    );
    return SchoolBreak.fromJson(response.data as Map<String, dynamic>);
  }

  Future<SchoolBreak> update(
    int breakId, {
    String? name,
    String? startTime,
    String? endTime,
    bool makeRoom = false,
  }) async {
    final response = await _dio.patch(
      '/breaks/$breakId',
      data: {'name': ?name, 'start_time': ?startTime, 'end_time': ?endTime, 'make_room': makeRoom},
    );
    return SchoolBreak.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> delete(int breakId) async {
    await _dio.delete('/breaks/$breakId');
  }
}
