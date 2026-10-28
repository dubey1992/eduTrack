import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import '../../../core/network/paginated_response.dart';
import '../../../core/utils/date_format.dart';
import 'models/fee_head.dart';
import 'models/fee_receipt.dart';
import 'models/fee_structure.dart';
import 'models/student_fees.dart';

/// What publishing did: the students it charged and the dues it created.
typedef FeeCharge = ({int students, int duesCreated});

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

  /// Publishes one fee, which charges every student it applies to.
  Future<({FeeStructure structure, FeeCharge charged})> publishStructure(int id) {
    return _call(() async {
      final response = await _dio.post('/fees/structures/$id/publish');
      final json = response.data as Map<String, dynamic>;
      final charged = json['charged'] as Map<String, dynamic>? ?? const {};

      return (
        structure: FeeStructure.fromJson(json),
        charged: (students: charged['students'] as int? ?? 0, duesCreated: charged['dues_created'] as int? ?? 0),
      );
    });
  }

  /// Publishes every draft of the year: how many were published, and the
  /// students they charged.
  Future<({int published, FeeCharge charged})> publishAll({required int academicYearId, int? schoolId}) {
    return _call(() async {
      final response = await _dio.post(
        '/fees/structures/publish',
        data: {'academic_year_id': academicYearId, 'school_id': ?schoolId},
      );
      final json = response.data as Map<String, dynamic>;

      return (
        published: json['published'] as int? ?? 0,
        charged: (students: json['students'] as int? ?? 0, duesCreated: json['dues_created'] as int? ?? 0),
      );
    });
  }

  // -- what students owe (F2) -------------------------------------------------

  /// One student's fees for a year - the current one when [academicYearId]
  /// is null.
  Future<StudentFeeStatement> statement(int studentId, {int? academicYearId}) {
    return _call(() async {
      final response = await _dio.get(
        '/fees/students/$studentId',
        queryParameters: {'academic_year_id': ?academicYearId},
      );
      return StudentFeeStatement.fromJson(response.data as Map<String, dynamic>);
    });
  }

  // -- payments and receipts (F3) ---------------------------------------------

  /// Records money received. Without [allocations] the server spreads it
  /// over what the student owes, oldest first.
  Future<({FeeReceipt receipt, bool emailQueued})> recordPayment({
    required int studentId,
    required DateTime receiptDate,
    required String amount,
    required PaymentMode mode,
    String? reference,
    String? note,
    List<PaymentAllocation>? allocations,
    bool emailToGuardian = false,
  }) {
    return _call(() async {
      final response = await _dio.post(
        '/fees/receipts',
        data: {
          'student_id': studentId,
          'receipt_date': apiDate(receiptDate),
          'amount': amount,
          'payment_mode': mode.wire,
          if (reference != null && reference.isNotEmpty) 'reference': reference,
          if (note != null && note.isNotEmpty) 'note': note,
          if (allocations != null)
            'allocations': [
              for (final allocation in allocations) {'due_id': allocation.dueId, 'amount': allocation.amount},
            ],
          'email_to_guardian': emailToGuardian,
        },
      );
      final json = response.data as Map<String, dynamic>;
      return (receipt: FeeReceipt.fromJson(json), emailQueued: json['email_queued'] as bool? ?? false);
    });
  }

  Future<PaginatedResponse<FeeReceipt>> receipts({
    int? schoolId,
    int? studentId,
    String? search,
    PaymentMode? mode,
    bool? cancelled,
    int page = 1,
    int perPage = 20,
  }) {
    return _call(() async {
      final response = await _dio.get(
        '/fees/receipts',
        queryParameters: {
          'school_id': ?schoolId,
          'student_id': ?studentId,
          if (search != null && search.isNotEmpty) 'search': search,
          'payment_mode': ?mode?.wire,
          if (cancelled != null) 'status': cancelled ? 'cancelled' : 'valid',
          'page': page,
          'per_page': perPage,
        },
      );
      return PaginatedResponse.fromJson(response.data as Map<String, dynamic>, FeeReceipt.fromJson);
    });
  }

  Future<FeeReceipt> receipt(int id) {
    return _call(() async {
      final response = await _dio.get('/fees/receipts/$id');
      return FeeReceipt.fromJson(response.data as Map<String, dynamic>);
    });
  }

  /// The receipt as the PDF the school hands the family.
  Future<List<int>> receiptPdf(int id) {
    return _call(() async {
      final response = await _dio.get<List<int>>(
        '/fees/receipts/$id/pdf',
        options: Options(responseType: ResponseType.bytes),
      );
      return response.data ?? const [];
    });
  }

  /// Cancels a receipt: it keeps its number, and what it paid is owed again.
  Future<FeeReceipt> cancelReceipt(int id, {required String reason}) {
    return _call(() async {
      final response = await _dio.post('/fees/receipts/$id/cancel', data: {'reason': reason});
      return FeeReceipt.fromJson(response.data as Map<String, dynamic>);
    });
  }

  /// Sends the receipt to the student's guardian, in the background.
  Future<void> emailReceipt(int id) => _call(() => _dio.post('/fees/receipts/$id/email'));

  /// What each student owes for a year, a page at a time.
  Future<PaginatedResponse<StudentBalance>> balances({
    required int academicYearId,
    int? schoolId,
    int? schoolClassId,
    String? search,
    bool owingOnly = false,
    bool overdueOnly = false,
    int page = 1,
    int perPage = 20,
  }) {
    return _call(() async {
      final response = await _dio.get(
        '/fees/balances',
        queryParameters: {
          'academic_year_id': academicYearId,
          'school_id': ?schoolId,
          'school_class_id': ?schoolClassId,
          if (search != null && search.isNotEmpty) 'search': search,
          if (owingOnly) 'owing': 1,
          if (overdueOnly) 'overdue': 1,
          'page': page,
          'per_page': perPage,
        },
      );
      return PaginatedResponse.fromJson(response.data as Map<String, dynamic>, StudentBalance.fromJson);
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
