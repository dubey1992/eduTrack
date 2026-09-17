import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/paged_list.dart';
import '../../../core/network/paginated_response.dart';
import '../../payments/data/models/payment.dart';
import '../data/models/payroll.dart';
import '../data/payroll_repository.dart';

PagedList<T> _paged<T>(PaginatedResponse<T> response) {
  return PagedList(
    items: response.items,
    currentPage: response.currentPage,
    lastPage: response.lastPage,
    total: response.total,
    perPage: response.perPage,
  );
}

// -- salaries -----------------------------------------------------------------

final salaryListNotifierProvider = AsyncNotifierProvider.autoDispose<SalaryListNotifier, PagedList<EmployeeSalary>>(
  SalaryListNotifier.new,
);

/// Who a school pays, and what. Filtered by school, a search, and "no salary
/// yet" - the employees a run cannot pay.
class SalaryListNotifier extends AsyncNotifier<PagedList<EmployeeSalary>> {
  int? _schoolId;
  String? _search;
  bool _missingOnly = false;
  int _page = 1;
  int _perPage = 20;

  bool get missingOnly => _missingOnly;

  @override
  Future<PagedList<EmployeeSalary>> build() => _fetch();

  Future<PagedList<EmployeeSalary>> _fetch() async {
    return _paged(
      await ref
          .read(payrollRepositoryProvider)
          .salaries(schoolId: _schoolId, search: _search, missingOnly: _missingOnly, page: _page, perPage: _perPage),
    );
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_fetch);
  }

  Future<void> setSchoolFilter(int? schoolId) => _refilter(() => _schoolId = schoolId);

  Future<void> setSearch(String search) => _refilter(() => _search = search.isEmpty ? null : search);

  Future<void> setMissingOnly(bool missingOnly) => _refilter(() => _missingOnly = missingOnly);

  Future<void> goToPage(int page) async {
    _page = page;
    await refresh();
  }

  Future<void> setPerPage(int perPage) => _refilter(() => _perPage = perPage);

  Future<void> _refilter(void Function() change) async {
    change();
    _page = 1;
    await refresh();
  }

  /// Saves a whole salary and folds the updated row back in place. With the
  /// "no salary yet" filter on, the row leaves the list instead.
  Future<void> save(
    EmployeeSalary employee, {
    required String basicSalary,
    required List<SalaryComponent> components,
  }) async {
    final updated = await ref
        .read(payrollRepositoryProvider)
        .saveSalary(employee.staffProfileId, basicSalary: basicSalary, components: components);

    if (_missingOnly) {
      await refresh();
      return;
    }

    state = state.whenData(
      (page) => page.withItems([
        for (final row in page.items) row.staffProfileId == updated.staffProfileId ? updated : row,
      ]),
    );
  }
}

// -- runs ---------------------------------------------------------------------

final payrollRunListNotifierProvider = AsyncNotifierProvider.autoDispose<PayrollRunListNotifier, PagedList<PayrollRun>>(
  PayrollRunListNotifier.new,
);

class PayrollRunListNotifier extends AsyncNotifier<PagedList<PayrollRun>> {
  int? _schoolId;
  int _page = 1;
  int _perPage = 20;

  @override
  Future<PagedList<PayrollRun>> build() => _fetch();

  Future<PagedList<PayrollRun>> _fetch() async {
    return _paged(await ref.read(payrollRepositoryProvider).runs(schoolId: _schoolId, page: _page, perPage: _perPage));
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

  Future<void> goToPage(int page) async {
    _page = page;
    await refresh();
  }

  Future<void> setPerPage(int perPage) async {
    _perPage = perPage;
    _page = 1;
    await refresh();
  }

  /// Generates a draft for a month and returns it, so the screen can open it.
  Future<PayrollRun> generate({required int year, required int month, int? schoolId}) async {
    final run = await ref.read(payrollRepositoryProvider).generate(year: year, month: month, schoolId: schoolId);
    _page = 1;
    await refresh();

    return run;
  }
}

// -- one run ------------------------------------------------------------------

/// A run and one page of its payslips, read together so the totals and the
/// rows never disagree after an action.
class PayrollRunView {
  const PayrollRunView({required this.run, required this.payslips});

  final PayrollRun run;
  final PagedList<Payslip> payslips;
}

final payrollRunNotifierProvider = AsyncNotifierProvider.autoDispose
    .family<PayrollRunNotifier, PayrollRunView, int>(PayrollRunNotifier.new);

class PayrollRunNotifier extends AsyncNotifier<PayrollRunView> {
  PayrollRunNotifier(this.runId);

  final int runId;
  String? _search;
  int _page = 1;
  int _perPage = 20;

  @override
  Future<PayrollRunView> build() => _fetch();

  Future<PayrollRunView> _fetch() async {
    final repository = ref.read(payrollRepositoryProvider);
    final run = await repository.run(runId);
    final payslips = await repository.runPayslips(runId, search: _search, page: _page, perPage: _perPage);

    return PayrollRunView(run: run, payslips: _paged(payslips));
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_fetch);
  }

  Future<void> setSearch(String search) async {
    _search = search.isEmpty ? null : search;
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

  Future<void> regenerate() => _act((repository) => repository.regenerate(runId));

  Future<void> finalize() => _act((repository) => repository.finalize(runId));

  Future<void> payAll({required DateTime paidOn, required PaymentMode mode, String? reference}) {
    return _act((repository) => repository.payRun(runId, paidOn: paidOn, mode: mode, reference: reference));
  }

  Future<void> delete() async {
    await ref.read(payrollRepositoryProvider).deleteRun(runId);
    ref.invalidate(payrollRunListNotifierProvider);
  }

  /// Something about one payslip changed - an adjustment, a payment - so the
  /// run's totals and that row both need re-reading.
  Future<void> payslipChanged() async {
    state = await AsyncValue.guard(_fetch);
    ref.invalidate(payrollRunListNotifierProvider);
  }

  /// An action the server answers with the updated run. Failures propagate to
  /// the caller, which shows them; the view is re-read either way.
  Future<void> _act(Future<PayrollRun> Function(PayrollRepository repository) action) async {
    try {
      await action(ref.read(payrollRepositoryProvider));
    } finally {
      state = await AsyncValue.guard(_fetch);
      ref.invalidate(payrollRunListNotifierProvider);
    }
  }
}

// -- my payslips --------------------------------------------------------------

final myPayslipsNotifierProvider = AsyncNotifierProvider.autoDispose<MyPayslipsNotifier, PagedList<Payslip>>(
  MyPayslipsNotifier.new,
);

class MyPayslipsNotifier extends AsyncNotifier<PagedList<Payslip>> {
  int _page = 1;
  int _perPage = 20;

  @override
  Future<PagedList<Payslip>> build() => _fetch();

  Future<PagedList<Payslip>> _fetch() async {
    return _paged(await ref.read(payrollRepositoryProvider).myPayslips(page: _page, perPage: _perPage));
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_fetch);
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
}
