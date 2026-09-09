import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/day_of_week.dart';
import '../data/models/timetable_entry.dart';
import '../data/timetable_repository.dart';

/// Exactly one of the two is set - a class section's whole week (the
/// prototype's "Timetable & Period Management" screen) or one teacher's
/// own schedule across every class section they teach ("My Schedule").
class TimetableGridParams {
  const TimetableGridParams.forClassSection(int this.classSectionId) : teacherId = null;

  const TimetableGridParams.forTeacher(int this.teacherId) : classSectionId = null;

  final int? classSectionId;
  final int? teacherId;

  @override
  bool operator ==(Object other) =>
      other is TimetableGridParams && other.classSectionId == classSectionId && other.teacherId == teacherId;

  @override
  int get hashCode => Object.hash(classSectionId, teacherId);
}

final timetableGridProvider = AsyncNotifierProvider.autoDispose
    .family<TimetableGridNotifier, List<TimetableEntry>, TimetableGridParams>(TimetableGridNotifier.new);

class TimetableGridNotifier extends AsyncNotifier<List<TimetableEntry>> {
  TimetableGridNotifier(this.params);

  final TimetableGridParams params;

  @override
  Future<List<TimetableEntry>> build() {
    return ref
        .read(timetableRepositoryProvider)
        .grid(classSectionId: params.classSectionId, teacherId: params.teacherId);
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref
          .read(timetableRepositoryProvider)
          .grid(classSectionId: params.classSectionId, teacherId: params.teacherId),
    );
  }

  /// Only valid for a class-section-scoped grid - a teacher-scoped "My
  /// Schedule" view is always read-only (see canEdit in TimetableScreen).
  Future<void> upsertCell({
    int? schoolId,
    required int periodId,
    required DayOfWeek dayOfWeek,
    required int subjectId,
    required int teacherId,
  }) async {
    final classSectionId = params.classSectionId;
    if (classSectionId == null) return;

    await ref
        .read(timetableRepositoryProvider)
        .upsert(
          schoolId: schoolId,
          classSectionId: classSectionId,
          periodId: periodId,
          dayOfWeek: dayOfWeek,
          subjectId: subjectId,
          teacherId: teacherId,
        );
    await refresh();
  }

  Future<void> deleteCell(TimetableEntry entry) async {
    await ref.read(timetableRepositoryProvider).delete(entry.id);
    await refresh();
  }
}
