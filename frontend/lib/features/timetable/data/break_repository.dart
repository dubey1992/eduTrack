import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import 'break_api.dart';
import 'models/school_break.dart';

final breakRepositoryProvider = Provider<BreakRepository>((ref) => BreakRepository(ref.watch(breakApiProvider)));

class BreakRepository {
  BreakRepository(this._api);

  final BreakApi _api;

  Future<List<SchoolBreak>> list({int? schoolId}) async {
    try {
      return await _api.list(schoolId: schoolId);
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }

  Future<SchoolBreak> create({
    int? schoolId,
    required String name,
    required String dayShape,
    required String startTime,
    required String endTime,
    bool makeRoom = false,
  }) async {
    try {
      return await _api.create(
        schoolId: schoolId,
        name: name,
        dayShape: dayShape,
        startTime: startTime,
        endTime: endTime,
        makeRoom: makeRoom,
      );
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }

  Future<SchoolBreak> update(
    int breakId, {
    String? name,
    String? startTime,
    String? endTime,
    bool makeRoom = false,
  }) async {
    try {
      return await _api.update(breakId, name: name, startTime: startTime, endTime: endTime, makeRoom: makeRoom);
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }

  Future<void> delete(int breakId) async {
    try {
      await _api.delete(breakId);
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }
}
