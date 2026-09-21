import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/network/dio_client.dart';
import '../../../core/network/paginated_response.dart';
import 'models/academic_term.dart';

final academicTermApiProvider = Provider<AcademicTermApi>((ref) => AcademicTermApi(ref.watch(dioClientProvider)));

class AcademicTermApi {
  AcademicTermApi(this._dio);

  final Dio _dio;

  static final _date = DateFormat('yyyy-MM-dd');

  Future<PaginatedResponse<AcademicTerm>> list({int? academicYearId, int? schoolId, int? perPage}) async {
    final response = await _dio.get(
      '/academic-terms',
      queryParameters: {'academic_year_id': ?academicYearId, 'school_id': ?schoolId, 'per_page': ?perPage},
    );

    return PaginatedResponse.fromJson(response.data as Map<String, dynamic>, AcademicTerm.fromJson);
  }

  Future<AcademicTerm> create({
    required int academicYearId,
    required String name,
    required int sequenceNumber,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final response = await _dio.post(
      '/academic-terms',
      data: {
        // The school is taken from the year server-side, so it is not sent.
        'academic_year_id': academicYearId,
        'name': name,
        'sequence_number': sequenceNumber,
        'start_date': _date.format(startDate),
        'end_date': _date.format(endDate),
      },
    );

    return AcademicTerm.fromJson(response.data as Map<String, dynamic>);
  }

  Future<AcademicTerm> update(
    int termId, {
    String? name,
    int? sequenceNumber,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final response = await _dio.patch(
      '/academic-terms/$termId',
      data: {
        'name': ?name,
        'sequence_number': ?sequenceNumber,
        'start_date': ?(startDate == null ? null : _date.format(startDate)),
        'end_date': ?(endDate == null ? null : _date.format(endDate)),
      },
    );

    return AcademicTerm.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> delete(int termId) async {
    await _dio.delete('/academic-terms/$termId');
  }
}
