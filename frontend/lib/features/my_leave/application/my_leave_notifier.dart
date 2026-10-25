import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../staff_leave/data/models/leave_type.dart';
import '../../staff_leave/data/models/staff_leave.dart';
import '../../staff_leave/data/staff_leave_repository.dart';

/// The person's own leave requests, newest first, a page at a time.
class MyLeave {
  const MyLeave({required this.items, required this.hasMore, required this.page});

  final List<StaffLeave> items;
  final bool hasMore;
  final int page;
}

/// No automatic retry: the screen has its own.
final myLeaveProvider = AsyncNotifierProvider.autoDispose<MyLeaveNotifier, MyLeave>(
  MyLeaveNotifier.new,
  retry: (retryCount, error) => null,
);

/// "My leave" in the School365ai app (docs/teacher-app.md, T4).
///
/// Always the caller's own requests (`mine=1`), whatever else their role
/// lets them see on the website - an HOD's department, an admin's school.
/// Applying goes through the same endpoint and the same rules as the web:
/// notice, overlap and closed days are the server's to refuse.
class MyLeaveNotifier extends AsyncNotifier<MyLeave> {
  static const perPage = 20;

  @override
  Future<MyLeave> build() => _page(1, const []);

  Future<MyLeave> _page(int page, List<StaffLeave> before) async {
    final response = await ref.read(staffLeaveRepositoryProvider).list(mine: true, page: page, perPage: perPage);

    return MyLeave(
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

  /// Throws the server's [Failure] - too little notice, an overlap, only
  /// closed days - for the form to show. On success the list starts again
  /// from the top, where the new request now is.
  Future<StaffLeave> apply({
    required LeaveType leaveType,
    required String startDate,
    required String endDate,
    required String reason,
  }) async {
    final leave = await ref
        .read(staffLeaveRepositoryProvider)
        .apply(leaveType: leaveType, startDate: startDate, endDate: endDate, reason: reason);
    state = await AsyncValue.guard(build);
    return leave;
  }
}
