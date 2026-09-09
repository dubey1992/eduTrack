import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/period.dart';
import '../data/period_repository.dart';

/// A school's period definitions - the family argument is a constructor
/// field here (Riverpod 3's family notifiers don't receive it through
/// build()), not an override parameter. [schoolId] only matters for a
/// SUPER_ADMIN actor picking a specific school - a SCHOOL_ADMIN is already
/// scoped to their own school server-side, so pass `null` for them.
final periodListNotifierProvider = AsyncNotifierProvider.autoDispose.family<PeriodListNotifier, List<Period>, int?>(
  PeriodListNotifier.new,
);

class PeriodListNotifier extends AsyncNotifier<List<Period>> {
  PeriodListNotifier(this.schoolId);

  final int? schoolId;

  @override
  Future<List<Period>> build() {
    return ref.read(periodRepositoryProvider).list(schoolId: schoolId);
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => ref.read(periodRepositoryProvider).list(schoolId: schoolId));
  }

  Future<void> create({required int periodNumber, required String startTime, required String endTime}) async {
    await ref
        .read(periodRepositoryProvider)
        .create(schoolId: schoolId, periodNumber: periodNumber, startTime: startTime, endTime: endTime);
    await refresh();
  }

  // Named editPeriod(), not update() - AsyncNotifier already declares an
  // `update(cb)` state-transform method with an incompatible signature.
  Future<void> editPeriod(Period period, {int? periodNumber, String? startTime, String? endTime}) async {
    await ref
        .read(periodRepositoryProvider)
        .update(period.id, periodNumber: periodNumber, startTime: startTime, endTime: endTime);
    await refresh();
  }

  Future<void> delete(Period period) async {
    await ref.read(periodRepositoryProvider).delete(period.id);
    await refresh();
  }
}
