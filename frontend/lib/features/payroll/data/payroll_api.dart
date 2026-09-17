import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import '../../../core/network/paginated_response.dart';
import '../../../core/utils/date_format.dart';
import '../../payments/data/models/payment.dart';
import 'models/payroll.dart';

final payrollApiProvider = Provider<PayrollApi>((ref) => PayrollApi(ref.watch(dioClientProvider)));

/// The Python backend's /payroll endpoints - see docs/payroll.md.
class PayrollApi {
  PayrollApi(this._dio);

  final Dio _dio;

  // -- salaries --------------------------------------------------------------

  Future<PaginatedResponse<EmployeeSalary>> salaries({
    int? schoolId,
    String? search,
    bool missingOnly = false,
    int? page,
    int? perPage,
  }) async {
    final response = await _dio.get(
      '/payroll/salaries',
      queryParameters: {
        'school_id': ?schoolId,
        'search': ?search,
        if (missingOnly) 'salary': 'missing',
        'page': ?page,
        'per_page': ?perPage,
      },
    );

    return PaginatedResponse.fromJson(response.data as Map<String, dynamic>, EmployeeSalary.fromJson);
  }

  Future<EmployeeSalary> saveSalary(
    int staffProfileId, {
    required String basicSalary,
    required List<SalaryComponent> components,
  }) async {
    final response = await _dio.put(
      '/payroll/salaries/$staffProfileId',
      data: {
        'basic_salary': basicSalary,
        'components': [for (final component in components) component.toJson()],
      },
    );

    return EmployeeSalary.fromJson(response.data as Map<String, dynamic>);
  }

  // -- runs ------------------------------------------------------------------

  Future<PaginatedResponse<PayrollRun>> runs({int? schoolId, int? page, int? perPage}) async {
    final response = await _dio.get(
      '/payroll/runs',
      queryParameters: {'school_id': ?schoolId, 'page': ?page, 'per_page': ?perPage},
    );

    return PaginatedResponse.fromJson(response.data as Map<String, dynamic>, PayrollRun.fromJson);
  }

  Future<PayrollRun> generate({required int year, required int month, int? schoolId}) async {
    final response = await _dio.post('/payroll/runs', data: {'year': year, 'month': month, 'school_id': ?schoolId});

    return PayrollRun.fromJson(response.data as Map<String, dynamic>);
  }

  Future<PayrollRun> run(int runId) async {
    final response = await _dio.get('/payroll/runs/$runId');
    return PayrollRun.fromJson(response.data as Map<String, dynamic>);
  }

  Future<PaginatedResponse<Payslip>> runPayslips(int runId, {String? search, int? page, int? perPage}) async {
    final response = await _dio.get(
      '/payroll/runs/$runId/payslips',
      queryParameters: {'search': ?search, 'page': ?page, 'per_page': ?perPage},
    );

    return PaginatedResponse.fromJson(response.data as Map<String, dynamic>, Payslip.fromJson);
  }

  Future<PayrollRun> regenerate(int runId) => _runAction(runId, 'regenerate');

  Future<PayrollRun> finalize(int runId) => _runAction(runId, 'finalize');

  Future<void> deleteRun(int runId) => _dio.delete('/payroll/runs/$runId');

  Future<PayrollRun> payRun(int runId, {required DateTime paidOn, required PaymentMode mode, String? reference}) async {
    final response = await _dio.post('/payroll/runs/$runId/pay', data: _payment(paidOn, mode, reference));
    return PayrollRun.fromJson(response.data as Map<String, dynamic>);
  }

  Future<PayrollRun> _runAction(int runId, String action) async {
    final response = await _dio.post('/payroll/runs/$runId/$action');
    return PayrollRun.fromJson(response.data as Map<String, dynamic>);
  }

  // -- payslips --------------------------------------------------------------

  Future<Payslip> payslip(int payslipId) async {
    final response = await _dio.get('/payroll/payslips/$payslipId');
    return Payslip.fromJson(response.data as Map<String, dynamic>);
  }

  Future<Payslip> addAdjustment(
    int payslipId, {
    required PayComponentType type,
    required String name,
    required String amount,
    required String note,
  }) async {
    final response = await _dio.post(
      '/payroll/payslips/$payslipId/adjustments',
      data: {'type': type.apiValue, 'name': name, 'amount': amount, 'note': note},
    );

    return Payslip.fromJson(response.data as Map<String, dynamic>);
  }

  Future<Payslip> removeAdjustment(int payslipId, int lineId) async {
    final response = await _dio.delete('/payroll/payslips/$payslipId/adjustments/$lineId');
    return Payslip.fromJson(response.data as Map<String, dynamic>);
  }

  Future<Payslip> payPayslip(
    int payslipId, {
    required DateTime paidOn,
    required PaymentMode mode,
    String? reference,
  }) async {
    final response = await _dio.post('/payroll/payslips/$payslipId/pay', data: _payment(paidOn, mode, reference));
    return Payslip.fromJson(response.data as Map<String, dynamic>);
  }

  Future<Payslip> emailPayslip(int payslipId) async {
    final response = await _dio.post('/payroll/payslips/$payslipId/email');
    return Payslip.fromJson(response.data as Map<String, dynamic>);
  }

  /// The PDF as bytes, fetched through the authenticated client rather than
  /// by opening a URL - a token does not belong in a link.
  Future<List<int>> downloadPayslip(int payslipId) async {
    final response = await _dio.get<List<int>>(
      '/payroll/payslips/$payslipId/pdf',
      options: Options(responseType: ResponseType.bytes),
    );

    return response.data ?? const [];
  }

  Future<PaginatedResponse<Payslip>> myPayslips({int? page, int? perPage}) async {
    final response = await _dio.get('/payroll/my-payslips', queryParameters: {'page': ?page, 'per_page': ?perPage});
    return PaginatedResponse.fromJson(response.data as Map<String, dynamic>, Payslip.fromJson);
  }

  Map<String, dynamic> _payment(DateTime paidOn, PaymentMode mode, String? reference) {
    return {'paid_on': apiDate(paidOn), 'payment_mode': mode.apiValue, 'payment_reference': reference};
  }
}
