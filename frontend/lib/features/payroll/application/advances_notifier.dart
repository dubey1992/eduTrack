import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/paged_list.dart';
import '../../payments/data/models/payment.dart';
import '../data/models/staff_advance.dart';
import '../data/payroll_repository.dart';
import 'payroll_notifiers.dart';

/// Advances paid to staff, one page at a time (docs/dashboard.md, D4).
final advanceListNotifierProvider = AsyncNotifierProvider.autoDispose<AdvanceListNotifier, PagedList<StaffAdvance>>(
  AdvanceListNotifier.new,
);

class AdvanceListNotifier extends AsyncNotifier<PagedList<StaffAdvance>> {
  int? _schoolId;

  /// Null is every advance; otherwise one [StaffAdvanceStatus].
  StaffAdvanceStatus? _status = StaffAdvanceStatus.active;
  int _page = 1;
  int _perPage = 20;

  StaffAdvanceStatus? get status => _status;

  @override
  Future<PagedList<StaffAdvance>> build() => _fetch();

  Future<PagedList<StaffAdvance>> _fetch() async {
    final response = await ref
        .read(payrollRepositoryProvider)
        .advances(schoolId: _schoolId, status: _status?.apiValue, page: _page, perPage: _perPage);

    return PagedList(
      items: response.items,
      currentPage: response.currentPage,
      lastPage: response.lastPage,
      total: response.total,
      perPage: response.perPage,
    );
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_fetch);
  }

  Future<void> setSchoolFilter(int? schoolId) async {
    _schoolId = schoolId;
    _page = 1;
    await refresh();
  }

  Future<void> setStatus(StaffAdvanceStatus? status) async {
    _status = status;
    _page = 1;
    await refresh();
  }

  Future<void> goToPage(int page) async {
    _page = page;
    await refresh();
  }

  Future<void> setPerPage(int perPage) async {
    _perPage = perPage;
    _page = 1;
    await refresh();
  }

  /// Logs an advance. A draft payroll is not touched until it is
  /// regenerated, so the run list is refreshed too.
  Future<StaffAdvance> record({
    required int staffProfileId,
    required String amount,
    required DateTime paidOn,
    required PaymentMode mode,
    String? reference,
    required String monthlyRecovery,
    DateTime? recoveryStarts,
    required String reason,
  }) async {
    final advance = await ref
        .read(payrollRepositoryProvider)
        .recordAdvance(
          staffProfileId: staffProfileId,
          amount: amount,
          paidOn: paidOn,
          mode: mode,
          reference: reference,
          monthlyRecovery: monthlyRecovery,
          recoveryStarts: recoveryStarts,
          reason: reason,
        );
    _page = 1;
    await refresh();

    return advance;
  }

  /// Cancels an advance nothing has been recovered from yet. A draft that
  /// was going to recover it no longer does, so its totals change too.
  Future<StaffAdvance> cancel(StaffAdvance advance, {required String reason}) async {
    final cancelled = await ref.read(payrollRepositoryProvider).cancelAdvance(advance.id, reason: reason);
    ref.invalidate(payrollRunListNotifierProvider);
    await refresh();

    return cancelled;
  }
}
