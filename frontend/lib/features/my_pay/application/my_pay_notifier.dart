import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../payroll/data/models/payroll.dart';
import '../data/my_pay_repository.dart';

/// The person's own payslips, newest month first, a page at a time.
class MyPayslips {
  const MyPayslips({required this.items, required this.hasMore, required this.page});

  final List<Payslip> items;
  final bool hasMore;
  final int page;
}

/// No automatic retry: the screens have their own.
final myPayslipsProvider = AsyncNotifierProvider.autoDispose<MyPayslipsNotifier, MyPayslips>(
  MyPayslipsNotifier.new,
  retry: (retryCount, error) => null,
);

/// One payslip with its lines, for the detail screen.
final myPayslipProvider = FutureProvider.autoDispose.family<Payslip, int>(
  (ref, id) => ref.read(myPayRepositoryProvider).payslip(id),
  retry: (retryCount, error) => null,
);

class MyPayslipsNotifier extends AsyncNotifier<MyPayslips> {
  static const perPage = 12;

  @override
  Future<MyPayslips> build() => _page(1, const []);

  Future<MyPayslips> _page(int page, List<Payslip> before) async {
    final response = await ref.read(myPayRepositoryProvider).myPayslips(page: page, perPage: perPage);

    return MyPayslips(
      items: [...before, ...response.items],
      hasMore: response.currentPage < response.lastPage,
      page: response.currentPage,
    );
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(build);
  }

  Future<void> retry() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(build);
  }

  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || !current.hasMore) return;

    state = await AsyncValue.guard(() => _page(current.page + 1, current.items));
  }
}
