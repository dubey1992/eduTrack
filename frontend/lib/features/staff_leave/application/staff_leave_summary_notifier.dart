import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/staff_leave_summary.dart';
import '../data/staff_leave_repository.dart';

final staffLeaveSummaryNotifierProvider = AsyncNotifierProvider<StaffLeaveSummaryNotifier, StaffLeaveSummary>(
  StaffLeaveSummaryNotifier.new,
);

class StaffLeaveSummaryNotifier extends AsyncNotifier<StaffLeaveSummary> {
  @override
  Future<StaffLeaveSummary> build() {
    return ref.read(staffLeaveRepositoryProvider).summary();
  }
}
