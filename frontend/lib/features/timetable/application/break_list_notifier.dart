import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/break_repository.dart';
import '../data/models/school_break.dart';
import 'period_list_notifier.dart';

/// A school's breaks - lunch, short breaks. [schoolId] only matters for an
/// actor who picks the school; everybody else is scoped server-side.
final breakListNotifierProvider = AsyncNotifierProvider.autoDispose.family<BreakListNotifier, List<SchoolBreak>, int?>(
  BreakListNotifier.new,
);

class BreakListNotifier extends AsyncNotifier<List<SchoolBreak>> {
  BreakListNotifier(this.schoolId);

  final int? schoolId;

  @override
  Future<List<SchoolBreak>> build() => ref.read(breakRepositoryProvider).list(schoolId: schoolId);

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => ref.read(breakRepositoryProvider).list(schoolId: schoolId));
  }

  Future<void> create({
    required String name,
    required String dayShape,
    required String startTime,
    required String endTime,
    bool makeRoom = false,
  }) async {
    await ref
        .read(breakRepositoryProvider)
        .create(
          schoolId: schoolId,
          name: name,
          dayShape: dayShape,
          startTime: startTime,
          endTime: endTime,
          makeRoom: makeRoom,
        );
    await _afterChange(makeRoom);
  }

  // Named editBreak(), not update() - AsyncNotifier already has update(cb).
  Future<void> editBreak(
    SchoolBreak found, {
    String? name,
    String? startTime,
    String? endTime,
    bool makeRoom = false,
  }) async {
    await ref
        .read(breakRepositoryProvider)
        .update(found.id, name: name, startTime: startTime, endTime: endTime, makeRoom: makeRoom);
    await _afterChange(makeRoom);
  }

  Future<void> delete(SchoolBreak found) async {
    await ref.read(breakRepositoryProvider).delete(found.id);
    await refresh();
  }

  /// Making room moved the later periods, so their list is read again too.
  Future<void> _afterChange(bool movedPeriods) async {
    if (movedPeriods) ref.invalidate(periodListNotifierProvider(schoolId));
    await refresh();
  }
}
