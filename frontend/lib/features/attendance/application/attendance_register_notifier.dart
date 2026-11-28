import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure.dart';
import '../../../core/network/connection_status.dart';
import '../../auth/application/auth_notifier.dart';
import '../../my_register/application/register_queue.dart';
import '../../my_register/data/models/saved_register.dart';
import '../../my_register/data/register_store.dart';
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
  Future<AttendanceRegister> build() async {
    final offlineWork = ref.read(offlineWorkProvider);
    SavedRegister? waiting;
    if (offlineWork) {
      await ref.read(registerQueueProvider.notifier).ready;
      waiting = ref.read(registerQueueProvider).waitingFor(params.classSectionId, params.date);
    }

    final AttendanceRegister register;
    try {
      register = await ref
          .read(attendanceRepositoryProvider)
          .register(classSectionId: params.classSectionId, date: params.date);
    } on Failure catch (failure) {
      // No connection: the class list kept on this computer, so the register
      // can still be taken and sent later (docs/offline-web.md, O3).
      final offline = failure.code == 'NETWORK_ERROR' && offlineWork ? await _fromSavedList(waiting) : null;
      if (offline == null) rethrow;
      return offline;
    }

    if (offlineWork) await _keepClassList(register);
    if (waiting == null || register.submitted || register.holiday != null) return register;

    // Taken here while offline and not yet sent: its marks, not blanks.
    return AttendanceRegister(
      classSectionId: register.classSectionId,
      attendanceDate: register.attendanceDate,
      submitted: false,
      waitingToSend: true,
      students: [
        for (final entry in register.students)
          entry.copyWith(status: waiting.marks[entry.studentId], remarks: waiting.remarks[entry.studentId]),
      ],
    );
  }

  /// The same short list the Staff app keeps - name and roll number - and
  /// cleared with it at sign-out.
  Future<void> _keepClassList(AttendanceRegister register) async {
    try {
      await ref.read(registerStoreProvider).saveRoster(params.classSectionId, [
        for (final s in register.students)
          CachedStudent(studentId: s.studentId, name: s.name, rollNumber: s.rollNumber),
      ]);
    } catch (error) {
      debugPrint('The class list could not be kept for offline use: $error');
    }
  }

  Future<AttendanceRegister?> _fromSavedList(SavedRegister? waiting) async {
    final saved = await ref.read(registerStoreProvider).readRoster(params.classSectionId);
    if (saved == null) return null;

    return AttendanceRegister(
      classSectionId: params.classSectionId,
      attendanceDate: params.date,
      submitted: false,
      fromSavedList: true,
      waitingToSend: waiting != null,
      students: [
        for (final s in saved)
          AttendanceRosterEntry(
            studentId: s.studentId,
            name: s.name,
            rollNumber: s.rollNumber,
            status: waiting?.marks[s.studentId],
            remarks: waiting?.remarks[s.studentId],
          ),
      ],
    );
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
      holiday: current.holiday,
      fromSavedList: current.fromSavedList,
      waitingToSend: current.waitingToSend,
      students: [for (final entry in current.students) transform(entry)],
    );
  }

  /// True once every roster student has a status - the Submit/Update button
  /// stays disabled until then, matching the prototype's expectation that a
  /// day is submitted for the whole class at once, not a partial roster.
  bool get isComplete => state.value?.students.every((s) => s.status != null) ?? false;

  /// Sends the register. With no connection a new register is saved on this
  /// computer and sent when the line is back (docs/offline-web.md, O3) - the
  /// answer is then [RegisterSendOutcome.savedOffline]. Changing a register
  /// already submitted needs the server, and says so.
  Future<RegisterSendOutcome> submitOrUpdate({String? classLabel}) async {
    final current = state.value;
    if (current == null || !isComplete) return RegisterSendOutcome.sent;

    final records = [
      for (final entry in current.students)
        {
          'student_id': entry.studentId,
          'status': entry.status!.apiValue,
          if (entry.remarks != null && entry.remarks!.isNotEmpty) 'remarks': entry.remarks,
        },
    ];

    final repository = ref.read(attendanceRepositoryProvider);
    try {
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
      return RegisterSendOutcome.sent;
    } on Failure catch (failure) {
      final me = ref.read(authNotifierProvider).value?.id;
      if (failure.code != 'NETWORK_ERROR' || !ref.read(offlineWorkProvider) || me == null) rethrow;
      if (current.submitted) {
        throw const Failure(
          code: 'NETWORK_ERROR',
          message: 'Changing a register already submitted needs the connection. Try again when it is back.',
        );
      }

      await ref
          .read(registerQueueProvider.notifier)
          .submit(
            SavedRegister(
              clientId: newRegisterClientId(),
              userId: me,
              classSectionId: current.classSectionId,
              classSection: classLabel ?? 'Class register',
              date: current.attendanceDate,
              marks: {for (final entry in current.students) entry.studentId: entry.status!},
              remarks: {
                for (final entry in current.students)
                  if (entry.remarks != null && entry.remarks!.isNotEmpty) entry.studentId: entry.remarks!,
              },
              savedAt: DateTime.now(),
            ),
          );
      state = AsyncData(
        AttendanceRegister(
          classSectionId: current.classSectionId,
          attendanceDate: current.attendanceDate,
          submitted: false,
          fromSavedList: current.fromSavedList,
          waitingToSend: true,
          students: current.students,
        ),
      );
      return RegisterSendOutcome.savedOffline;
    }
  }
}

/// What became of a Submit.
enum RegisterSendOutcome {
  /// The server has it.
  sent,

  /// No connection: kept on this computer, sent when the line is back.
  savedOffline,
}
