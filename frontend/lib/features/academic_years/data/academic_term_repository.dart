import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import 'academic_term_api.dart';
import 'models/academic_term.dart';

final academicTermRepositoryProvider = Provider<AcademicTermRepository>(
  (ref) => AcademicTermRepository(ref.watch(academicTermApiProvider)),
);

class AcademicTermRepository {
  AcademicTermRepository(this._api);

  final AcademicTermApi _api;

  /// Every term of one year. A year holds a handful of terms, so this asks for
  /// them in one page rather than paging a list nobody would page.
  Future<List<AcademicTerm>> listForYear(int academicYearId) {
    return _call(() async {
      final page = await _api.list(academicYearId: academicYearId, perPage: 100);
      return page.items;
    });
  }

  Future<AcademicTerm> create({
    required int academicYearId,
    required String name,
    required int sequenceNumber,
    required DateTime startDate,
    required DateTime endDate,
  }) {
    return _call(
      () => _api.create(
        academicYearId: academicYearId,
        name: name,
        sequenceNumber: sequenceNumber,
        startDate: startDate,
        endDate: endDate,
      ),
    );
  }

  Future<AcademicTerm> update(int termId, {String? name, int? sequenceNumber, DateTime? startDate, DateTime? endDate}) {
    return _call(
      () => _api.update(termId, name: name, sequenceNumber: sequenceNumber, startDate: startDate, endDate: endDate),
    );
  }

  Future<void> delete(int termId) => _call(() => _api.delete(termId));

  Future<T> _call<T>(Future<T> Function() request) async {
    try {
      return await request();
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }
}
