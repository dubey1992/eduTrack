import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/attendance_repository.dart';
import '../data/models/attendance_register.dart';
import '../data/models/attendance_status.dart';

class AttendanceRegisterParams {
  const AttendanceRegisterParams({required this.classSectionId, required this.date});

  final int classSectionId;

  /// yyyy-MM-dd.
  final String date;

  @override
  bool operator ==(Object other) =>
      other is AttendanceRegisterParams && other.classSectionId == classSectionId && other.date == date;

  @override
  int get hashCode => Object.hash(classSectionId, date);
}

final attendanceRegisterProvider = AsyncNotifierProvider.autoDispose
    .family<AttendanceRegisterNotifier, AttendanceRegister, AttendanceRegisterParams>(AttendanceRegisterNotifier.new);

/// Holds one class section's register for one day - the roster plus
/// whatever's been marked locally, up until it's submitted/updated. The
/// family argument is a constructor field here (Riverpod 3's family
/// notifiers don't receive it through `build()`), not an override parameter.
class AttendanceRegisterNotifier extends AsyncNotifier<AttendanceRegister> {
  AttendanceRegisterNotifier(this.params);

  final AttendanceRegisterParams params;

  @override
  Future<AttendanceRegister> build() {
    return ref.read(attendanceRepositoryProvider).register(classSectionId: params.classSectionId, date: params.date);
  }

  void setStatus(int studentId, AttendanceStatus status) {
    final current = state.value;
    if (current == null) return;

    state = AsyncData(
      _withStudents(current, (entry) => entry.studentId == studentId ? entry.copyWith(status: status) : entry),
    );
  }

  void markAllPresent() {
    final current = state.value;
    if (current == null) return;

    state = AsyncData(_withStudents(current, (entry) => entry.copyWith(status: AttendanceStatus.present)));
  }

  AttendanceRegister _withStudents(
    AttendanceRegister current,
    AttendanceRosterEntry Function(AttendanceRosterEntry) transform,
  ) {
    return AttendanceRegister(
      classSectionId: current.classSectionId,
      attendanceDate: current.attendanceDate,
      submitted: current.submitted,
      students: [for (final entry in current.students) transform(entry)],
    );
  }

  /// True once every roster student has a status - the Submit/Update button
  /// stays disabled until then, matching the prototype's expectation that a
  /// day is submitted for the whole class at once, not a partial roster.
  bool get isComplete => state.value?.students.every((s) => s.status != null) ?? false;

  Future<void> submitOrUpdate() async {
    final current = state.value;
    if (current == null || !isComplete) return;

    final records = [
      for (final entry in current.students)
        {
          'student_id': entry.studentId,
          'status': entry.status!.apiValue,
          if (entry.remarks != null && entry.remarks!.isNotEmpty) 'remarks': entry.remarks,
        },
    ];

    final repository = ref.read(attendanceRepositoryProvider);
    final result = current.submitted
        ? await repository.update(
            classSectionId: current.classSectionId,
            attendanceDate: current.attendanceDate,
            records: records,
          )
        : await repository.submit(
            classSectionId: current.classSectionId,
            attendanceDate: current.attendanceDate,
            records: records,
          );

    state = AsyncData(result);
  }
}
