import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import '../../../core/network/paginated_response.dart';
import '../../payments/data/models/payment.dart';
import 'models/payroll.dart';
import 'payroll_api.dart';

final payrollRepositoryProvider = Provider<PayrollRepository>(
  (ref) => PayrollRepository(ref.watch(payrollApiProvider)),
);

/// Turns transport failures into the app's [Failure], so screens show the
/// server's own message ("The September 2026 run is finalized and can no
/// longer be changed.") rather than an exception.
class PayrollRepository {
  PayrollRepository(this._api);

  final PayrollApi _api;

  Future<T> _call<T>(Future<T> Function() request) async {
    try {
      return await request();
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }

  Future<PaginatedResponse<EmployeeSalary>> salaries({
    int? schoolId,
    String? search,
    bool missingOnly = false,
    required int page,
    required int perPage,
  }) {
    return _call(
      () => _api.salaries(schoolId: schoolId, search: search, missingOnly: missingOnly, page: page, perPage: perPage),
    );
  }

  Future<EmployeeSalary> saveSalary(
    int staffProfileId, {
    required String basicSalary,
    required List<SalaryComponent> components,
  }) {
    return _call(() => _api.saveSalary(staffProfileId, basicSalary: basicSalary, components: components));
  }

  Future<PaginatedResponse<PayrollRun>> runs({int? schoolId, required int page, required int perPage}) {
    return _call(() => _api.runs(schoolId: schoolId, page: page, perPage: perPage));
  }

  Future<PayrollRun> generate({required int year, required int month, int? schoolId}) {
    return _call(() => _api.generate(year: year, month: month, schoolId: schoolId));
  }

  Future<PayrollRun> run(int runId) => _call(() => _api.run(runId));

  Future<PaginatedResponse<Payslip>> runPayslips(int runId, {String? search, required int page, required int perPage}) {
    return _call(() => _api.runPayslips(runId, search: search, page: page, perPage: perPage));
  }

  Future<PayrollRun> regenerate(int runId) => _call(() => _api.regenerate(runId));

  Future<PayrollRun> finalize(int runId) => _call(() => _api.finalize(runId));

  Future<void> deleteRun(int runId) => _call(() => _api.deleteRun(runId));

  Future<PayrollRun> payRun(int runId, {required DateTime paidOn, required PaymentMode mode, String? reference}) {
    return _call(() => _api.payRun(runId, paidOn: paidOn, mode: mode, reference: reference));
  }

  Future<Payslip> payslip(int payslipId) => _call(() => _api.payslip(payslipId));

  Future<Payslip> addAdjustment(
    int payslipId, {
    required PayComponentType type,
    required String name,
    required String amount,
    required String note,
  }) {
    return _call(() => _api.addAdjustment(payslipId, type: type, name: name, amount: amount, note: note));
  }

  Future<Payslip> removeAdjustment(int payslipId, int lineId) => _call(() => _api.removeAdjustment(payslipId, lineId));

  Future<Payslip> payPayslip(int payslipId, {required DateTime paidOn, required PaymentMode mode, String? reference}) {
    return _call(() => _api.payPayslip(payslipId, paidOn: paidOn, mode: mode, reference: reference));
  }

  Future<Payslip> emailPayslip(int payslipId) => _call(() => _api.emailPayslip(payslipId));

  Future<List<int>> downloadPayslip(int payslipId) => _call(() => _api.downloadPayslip(payslipId));

  Future<PaginatedResponse<Payslip>> myPayslips({required int page, required int perPage}) {
    return _call(() => _api.myPayslips(page: page, perPage: perPage));
  }
}
