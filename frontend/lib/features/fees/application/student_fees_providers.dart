import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/paginated_response.dart';
import '../data/fee_repository.dart';
import '../data/models/fee_receipt.dart';
import '../data/models/student_fees.dart';

/// One page of the Student Fees list, as the filters stand.
typedef BalanceQuery = ({
  int? schoolId,
  int academicYearId,
  int? schoolClassId,
  String search,
  bool owingOnly,
  bool overdueOnly,
  int page,
  int perPage,
});

// No automatic retry: a refusal is an answer, and the screens offer their
// own Try again (the reason is in site_page_notifiers.dart).

final studentBalancesProvider = FutureProvider.autoDispose.family<PaginatedResponse<StudentBalance>, BalanceQuery>(
  (ref, query) => ref
      .read(feeRepositoryProvider)
      .balances(
        academicYearId: query.academicYearId,
        schoolId: query.schoolId,
        schoolClassId: query.schoolClassId,
        search: query.search,
        owingOnly: query.owingOnly,
        overdueOnly: query.overdueOnly,
        page: query.page,
        perPage: query.perPage,
      ),
  retry: (retryCount, error) => null,
);

/// One student's account. A null year is the server's choice: the current
/// one.
final studentStatementProvider = FutureProvider.autoDispose
    .family<StudentFeeStatement, ({int studentId, int? academicYearId})>(
      (ref, query) => ref.read(feeRepositoryProvider).statement(query.studentId, academicYearId: query.academicYearId),
      retry: (retryCount, error) => null,
    );

/// One page of the Receipts list, as the filters stand.
typedef ReceiptQuery = ({int? schoolId, String search, PaymentMode? mode, bool? cancelled, int page, int perPage});

final feeReceiptsProvider = FutureProvider.autoDispose.family<PaginatedResponse<FeeReceipt>, ReceiptQuery>(
  (ref, query) => ref
      .read(feeRepositoryProvider)
      .receipts(
        schoolId: query.schoolId,
        search: query.search,
        mode: query.mode,
        cancelled: query.cancelled,
        page: query.page,
        perPage: query.perPage,
      ),
  retry: (retryCount, error) => null,
);

final feeReceiptActionsProvider = Provider<FeeReceiptActions>(FeeReceiptActions.new);

/// Taking money and undoing it. Each one reads again what it changed - the
/// student's statement, the balances list, the receipts list - so no screen
/// shows a balance from before the payment. Failures go to whoever asked.
class FeeReceiptActions {
  FeeReceiptActions(this._ref);

  final Ref _ref;

  FeeRepository get _repository => _ref.read(feeRepositoryProvider);

  void _refresh() {
    _ref.invalidate(studentStatementProvider);
    _ref.invalidate(studentBalancesProvider);
    _ref.invalidate(feeReceiptsProvider);
  }

  Future<({FeeReceipt receipt, bool emailQueued})> recordPayment({
    required int studentId,
    required DateTime receiptDate,
    required String amount,
    required PaymentMode mode,
    String? reference,
    String? note,
    List<PaymentAllocation>? allocations,
    bool emailToGuardian = false,
  }) async {
    final result = await _repository.recordPayment(
      studentId: studentId,
      receiptDate: receiptDate,
      amount: amount,
      mode: mode,
      reference: reference,
      note: note,
      allocations: allocations,
      emailToGuardian: emailToGuardian,
    );
    _refresh();
    return result;
  }

  Future<FeeReceipt> cancel(int receiptId, {required String reason}) async {
    final receipt = await _repository.cancelReceipt(receiptId, reason: reason);
    _refresh();
    return receipt;
  }

  Future<void> email(int receiptId) => _repository.emailReceipt(receiptId);

  Future<List<int>> pdf(int receiptId) => _repository.receiptPdf(receiptId);

  Future<List<int>> statementPdf(int studentId, {int? academicYearId}) =>
      _repository.statementPdf(studentId, academicYearId: academicYearId);
}

/// One page of the Discounts list.
typedef ConcessionQuery = ({int? schoolId, int? academicYearId, bool includeRevoked, int page, int perPage});

final feeConcessionsProvider = FutureProvider.autoDispose.family<PaginatedResponse<FeeConcession>, ConcessionQuery>(
  (ref, query) => ref
      .read(feeRepositoryProvider)
      .concessions(
        schoolId: query.schoolId,
        academicYearId: query.academicYearId,
        includeRevoked: query.includeRevoked,
        page: query.page,
        perPage: query.perPage,
      ),
  retry: (retryCount, error) => null,
);

final feeAdjustmentActionsProvider = Provider<FeeAdjustmentActions>(FeeAdjustmentActions.new);

/// Discounts and waivers (F4). Each changes what students owe, so it reads
/// the statement, the balances and the discounts list again.
class FeeAdjustmentActions {
  FeeAdjustmentActions(this._ref);

  final Ref _ref;

  FeeRepository get _repository => _ref.read(feeRepositoryProvider);

  void _refresh() {
    _ref.invalidate(studentStatementProvider);
    _ref.invalidate(studentBalancesProvider);
    _ref.invalidate(feeConcessionsProvider);
  }

  Future<FeeConcession> addDiscount({
    required int studentId,
    required int academicYearId,
    int? feeHeadId,
    required bool percent,
    required String value,
    required String reason,
  }) async {
    final concession = await _repository.createConcession(
      studentId: studentId,
      academicYearId: academicYearId,
      feeHeadId: feeHeadId,
      percent: percent,
      value: value,
      reason: reason,
    );
    _refresh();
    return concession;
  }

  Future<FeeConcession> revokeDiscount(int id) async {
    final concession = await _repository.revokeConcession(id);
    _refresh();
    return concession;
  }

  Future<FeeDue> waive(int dueId, {required String reason}) async {
    final due = await _repository.waiveDue(dueId, reason: reason);
    _refresh();
    return due;
  }
}
