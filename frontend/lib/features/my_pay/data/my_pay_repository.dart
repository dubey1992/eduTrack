import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import '../../../core/network/paginated_response.dart';
import '../../payroll/data/models/payroll.dart';
import '../../payroll/data/payroll_api.dart';

final myPayRepositoryProvider = Provider<MyPayRepository>((ref) => MyPayRepository(ref.watch(payrollApiProvider)));

/// What the School365ai app does with pay (docs/teacher-app.md, T4): list
/// the person's own payslips, open one, email its PDF to themselves - or
/// fetch the PDF to share from the phone (docs/mobile-apps-review.md, 6.7). Never anybody else's - the server answers only for the
/// caller, and a draft is never theirs to see.
class MyPayRepository {
  MyPayRepository(this._api);

  final PayrollApi _api;

  Future<PaginatedResponse<Payslip>> myPayslips({required int page, required int perPage}) =>
      _call(() => _api.myPayslips(page: page, perPage: perPage));

  Future<Payslip> payslip(int payslipId) => _call(() => _api.payslip(payslipId));

  Future<String> emailMe(int payslipId) => _call(() => _api.emailMyPayslip(payslipId));

  /// The PDF of the caller's own finalized payslip - the server's
  /// view_payslip lets an employee have their own and nobody else's.
  Future<List<int>> pdf(int payslipId) => _call(() => _api.downloadPayslip(payslipId));

  Future<T> _call<T>(Future<T> Function() request) async {
    try {
      return await request();
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }
}
