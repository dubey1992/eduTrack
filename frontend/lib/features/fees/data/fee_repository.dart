import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import '../../../core/utils/date_format.dart';
import 'models/fee_head.dart';
import 'models/fee_structure.dart';

final feeRepositoryProvider = Provider<FeeRepository>((ref) => FeeRepository(ref.watch(dioClientProvider)));

/// Fee set-up: the heads a school charges and what each class and bus route
/// pays under them (docs/fees.md, F1).
///
/// [schoolId] only matters to a Super Admin or a Group Admin choosing a
/// school; the server ignores it for everyone else and uses their own.
class FeeRepository {
  FeeRepository(this._dio);

  final Dio _dio;

  Future<T> _call<T>(Future<T> Function() request) async {
    try {
      return await request();
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }

  // -- heads ------------------------------------------------------------------

  /// Every head the school has, Transport first. Not paginated: a school has
  /// at most fifty.
  Future<List<FeeHead>> heads({int? schoolId}) {
    return _call(() async {
      final response = await _dio.get('/fees/heads', queryParameters: {'school_id': ?schoolId});
      final rows = (response.data as Map<String, dynamic>)['data'] as List;
      return [for (final row in rows) FeeHead.fromJson(row as Map<String, dynamic>)];
    });
  }

  Future<FeeHead> createHead({required String name, int? schoolId}) {
    return _call(() async {
      final response = await _dio.post('/fees/heads', data: {'name': name, 'school_id': ?schoolId});
      return FeeHead.fromJson(response.data as Map<String, dynamic>);
    });
  }

  Future<FeeHead> updateHead(int id, {String? name, bool? isActive}) {
    return _call(() async {
      final response = await _dio.patch('/fees/heads/$id', data: {'name': ?name, 'is_active': ?isActive});
      return FeeHead.fromJson(response.data as Map<String, dynamic>);
    });
  }

  Future<void> deleteHead(int id) => _call(() => _dio.delete('/fees/heads/$id'));

  // -- structures -------------------------------------------------------------

  /// Every class and route fee of one academic year. Not paginated: bounded
  /// by the school's heads times its classes and routes.
  Future<List<FeeStructure>> structures({required int academicYearId, int? schoolId}) {
    return _call(() async {
      final response = await _dio.get(
        '/fees/structures',
        queryParameters: {'academic_year_id': academicYearId, 'school_id': ?schoolId},
      );
      final rows = (response.data as Map<String, dynamic>)['data'] as List;
      return [for (final row in rows) FeeStructure.fromJson(row as Map<String, dynamic>)];
    });
  }

  /// A new fee, saved as a draft. Exactly one of [schoolClassId] and
  /// [transportRouteId].
  Future<FeeStructure> createStructure({
    required int academicYearId,
    int? schoolClassId,
    int? transportRouteId,
    required int feeHeadId,
    required String amount,
    required FeeFrequency frequency,
    required List<InstallmentDraft> installments,
  }) {
    return _call(() async {
      final response = await _dio.post(
        '/fees/structures',
        data: {
          'academic_year_id': academicYearId,
          'school_class_id': ?schoolClassId,
          'transport_route_id': ?transportRouteId,
          'fee_head_id': feeHeadId,
          'amount': amount,
          'frequency': frequency.wire,
          'installments': _installments(installments),
        },
      );
      return FeeStructure.fromJson(response.data as Map<String, dynamic>);
    });
  }

  /// The amount, frequency and installments. Which class or route, and
  /// which head, never change - delete the draft and add it again instead.
  Future<FeeStructure> updateStructure(
    int id, {
    required String amount,
    required FeeFrequency frequency,
    required List<InstallmentDraft> installments,
  }) {
    return _call(() async {
      final response = await _dio.put(
        '/fees/structures/$id',
        data: {'amount': amount, 'frequency': frequency.wire, 'installments': _installments(installments)},
      );
      return FeeStructure.fromJson(response.data as Map<String, dynamic>);
    });
  }

  /// Drafts only - the server refuses a published fee.
  Future<void> deleteStructure(int id) => _call(() => _dio.delete('/fees/structures/$id'));

  Future<FeeStructure> publishStructure(int id) {
    return _call(() async {
      final response = await _dio.post('/fees/structures/$id/publish');
      return FeeStructure.fromJson(response.data as Map<String, dynamic>);
    });
  }

  /// Publishes every draft of the year. Returns how many were published.
  Future<int> publishAll({required int academicYearId, int? schoolId}) {
    return _call(() async {
      final response = await _dio.post(
        '/fees/structures/publish',
        data: {'academic_year_id': academicYearId, 'school_id': ?schoolId},
      );
      return (response.data as Map<String, dynamic>)['published'] as int? ?? 0;
    });
  }

  /// Installments to start from, worked out by the server from the
  /// frequency, the year's dates and its terms. Nothing is saved.
  Future<List<InstallmentDraft>> installmentPlan({
    required int academicYearId,
    required FeeFrequency frequency,
    required String amount,
    int dueDay = 10,
  }) {
    return _call(() async {
      final response = await _dio.get(
        '/fees/installment-plan',
        queryParameters: {
          'academic_year_id': academicYearId,
          'frequency': frequency.wire,
          'amount': amount,
          'due_day': dueDay,
        },
      );
      final rows = (response.data as Map<String, dynamic>)['installments'] as List;
      return [for (final row in rows) InstallmentDraft.fromJson(row as Map<String, dynamic>)];
    });
  }

  List<Map<String, String>> _installments(List<InstallmentDraft> installments) => [
    for (final installment in installments)
      {'label': installment.label, 'due_date': apiDate(installment.dueDate), 'amount': installment.amount},
  ];
}
