import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/paged_list.dart';
import '../data/models/leave_type.dart';
import '../data/models/staff_leave.dart';
import '../data/staff_leave_repository.dart';
import 'staff_leave_summary_notifier.dart';

final staffLeaveListNotifierProvider = AsyncNotifierProvider<StaffLeaveListNotifier, PagedList<StaffLeave>>(
  StaffLeaveListNotifier.new,
);

class StaffLeaveListNotifier extends AsyncNotifier<PagedList<StaffLeave>> {
  int? _schoolId;
  int? _departmentId;
  String? _status;
  int _page = 1;
  int _perPage = 20;

  @override
  Future<PagedList<StaffLeave>> build() => _fetch();

  Future<PagedList<StaffLeave>> _fetch() async {
    final response = await ref
        .read(staffLeaveRepositoryProvider)
        .list(schoolId: _schoolId, departmentId: _departmentId, status: _status, page: _page, perPage: _perPage);

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
    _departmentId = null;
    _page = 1;
    await refresh();
  }

  Future<void> setDepartmentFilter(int? departmentId) async {
    _departmentId = departmentId;
    _page = 1;
    await refresh();
  }

  Future<void> setStatusFilter(String? status) async {
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

  /// Returns the created leave so the caller can tell whether it needs
  /// review or - for the School Admin who heads the school - was
  /// auto-approved immediately (see the backend's StaffLeaveService::apply()).
  Future<StaffLeave> applyLeave({
    required LeaveType leaveType,
    required String startDate,
    required String endDate,
    required String reason,
  }) async {
    final created = await ref
        .read(staffLeaveRepositoryProvider)
        .apply(leaveType: leaveType, startDate: startDate, endDate: endDate, reason: reason);
    _page = 1;
    await refresh();
    ref.invalidate(staffLeaveSummaryNotifierProvider);
    return created;
  }

  Future<void> approve(StaffLeave leave, {String? remarks}) async {
    final updated = await ref.read(staffLeaveRepositoryProvider).approve(leave.id, remarks: remarks);
    _replace(updated);
    ref.invalidate(staffLeaveSummaryNotifierProvider);
  }

  Future<void> reject(StaffLeave leave, {String? remarks}) async {
    final updated = await ref.read(staffLeaveRepositoryProvider).reject(leave.id, remarks: remarks);
    _replace(updated);
    ref.invalidate(staffLeaveSummaryNotifierProvider);
  }

  void _replace(StaffLeave updated) {
    state = state.whenData(
      (page) => page.withItems([for (final existing in page.items) existing.id == updated.id ? updated : existing]),
    );
  }
}
