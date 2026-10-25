import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure.dart';
import '../../attendance/data/attendance_repository.dart';
import '../../attendance/data/models/attendance_status.dart';
import '../../auth/application/auth_notifier.dart';
import '../data/models/saved_register.dart';
import '../data/register_store.dart';
import 'register_queue.dart';

/// Where a register stands, which decides what the screen offers.
enum RegisterMode {
  /// Being taken: marks can be set and submitted.
  taking,

  /// The server has it; shown as it stands, with Correct.
  submitted,

  /// Correcting a submitted day; saved straight to the server.
  correcting,

  /// Saved on the phone, waiting for signal.
  waiting,

  /// A holiday - no register to take.
  closed,
}

class RegisterStudent {
  const RegisterStudent({required this.id, required this.name, required this.rollNumber});

  final int id;
  final String name;
  final String? rollNumber;
}

class RegisterSheet {
  const RegisterSheet({
    required this.mode,
    required this.students,
    required this.marks,
    this.offline = false,
    this.holidayName,
    this.refusal,
  });

  final RegisterMode mode;
  final List<RegisterStudent> students;
  final Map<int, AttendanceStatus> marks;

  /// Opened from the phone's saved class list, with no signal.
  final bool offline;
  final String? holidayName;

  /// Why the server turned the last submission down, if it did.
  final String? refusal;

  int count(AttendanceStatus status) => marks.values.where((mark) => mark == status).length;

  int get unmarked => students.where((student) => !marks.containsKey(student.id)).length;

  bool get complete => students.isNotEmpty && unmarked == 0;

  bool get editable => mode == RegisterMode.taking || mode == RegisterMode.correcting;

  RegisterSheet copyWith({RegisterMode? mode, Map<int, AttendanceStatus>? marks, String? refusal}) => RegisterSheet(
    mode: mode ?? this.mode,
    students: students,
    marks: marks ?? this.marks,
    offline: offline,
    holidayName: holidayName,
    refusal: refusal ?? this.refusal,
  );
}

/// Which register: a class section on a day (`yyyy-MM-dd`).
typedef RegisterKey = ({int sectionId, String date, String label});

final registerSheetProvider = AsyncNotifierProvider.autoDispose
    .family<RegisterSheetNotifier, RegisterSheet, RegisterKey>(
      RegisterSheetNotifier.new,
      retry: (retryCount, error) => null,
    );

/// One class's register on one day, on the phone (docs/teacher-app.md, T2).
class RegisterSheetNotifier extends AsyncNotifier<RegisterSheet> {
  RegisterSheetNotifier(this.key);

  final RegisterKey key;

  @override
  Future<RegisterSheet> build() => _load();

  Future<RegisterSheet> _load() async {
    await ref.read(registerQueueProvider.notifier).ready;
    final queue = ref.read(registerQueueProvider);
    final saved = queue.waitingFor(key.sectionId, key.date);
    final refused = queue.unsentFor(key.sectionId, key.date);

    try {
      final register = await ref
          .read(attendanceRepositoryProvider)
          .register(classSectionId: key.sectionId, date: key.date);
      final students = [
        for (final s in register.students) RegisterStudent(id: s.studentId, name: s.name, rollNumber: s.rollNumber),
      ];

      // Kept for the next time there is no signal.
      await ref.read(registerStoreProvider).saveRoster(key.sectionId, [
        for (final s in register.students)
          CachedStudent(studentId: s.studentId, name: s.name, rollNumber: s.rollNumber),
      ]);

      if (register.holiday != null) {
        return RegisterSheet(
          mode: RegisterMode.closed,
          students: students,
          marks: const {},
          holidayName: register.holiday!.name,
        );
      }

      if (register.submitted) {
        return RegisterSheet(
          mode: RegisterMode.submitted,
          students: students,
          marks: {
            for (final s in register.students)
              if (s.status != null) s.studentId: s.status!,
          },
        );
      }

      if (saved != null) {
        return RegisterSheet(mode: RegisterMode.waiting, students: students, marks: saved.marks);
      }

      return RegisterSheet(
        mode: RegisterMode.taking,
        students: students,
        // A register the server turned down is taken again from the start,
        // with its reason shown above - the reason usually means the marks
        // need another look anyway.
        marks: const {},
        refusal: refused?.reason,
      );
    } on Failure catch (failure) {
      if (failure.code != 'NETWORK_ERROR') rethrow;

      final cached = await ref.read(registerStoreProvider).readRoster(key.sectionId);
      if (cached == null) {
        throw const Failure(
          code: 'NETWORK_ERROR',
          message:
              'No connection, and this class has not been opened on this phone before. '
              'Open the register once with signal; after that it works without.',
        );
      }

      final students = [
        for (final s in cached) RegisterStudent(id: s.studentId, name: s.name, rollNumber: s.rollNumber),
      ];

      return RegisterSheet(
        mode: saved != null ? RegisterMode.waiting : RegisterMode.taking,
        students: students,
        marks: saved?.marks ?? const {},
        offline: true,
      );
    }
  }

  Future<void> reload() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_load);
  }

  void setMark(int studentId, AttendanceStatus status) {
    final sheet = state.value;
    if (sheet == null || !sheet.editable) return;

    state = AsyncData(sheet.copyWith(marks: {...sheet.marks, studentId: status}));
  }

  void markAllPresent() {
    final sheet = state.value;
    if (sheet == null || !sheet.editable) return;

    state = AsyncData(
      sheet.copyWith(
        marks: {for (final student in sheet.students) student.id: sheet.marks[student.id] ?? AttendanceStatus.present},
      ),
    );
  }

  void startCorrecting() {
    final sheet = state.value;
    if (sheet == null || sheet.mode != RegisterMode.submitted) return;

    state = AsyncData(sheet.copyWith(mode: RegisterMode.correcting));
  }

  /// Saves the register on the phone and sends it. Returns where it ended
  /// up: [RegisterMode.submitted] if the server has it, [RegisterMode.waiting]
  /// if it is kept for signal, [RegisterMode.taking] (with the refusal) if
  /// the server turned it down.
  Future<RegisterMode> submit() async {
    final sheet = state.value;
    if (sheet == null || !sheet.complete) return sheet?.mode ?? RegisterMode.taking;
    final me = (await ref.read(authNotifierProvider.future))?.id;
    if (me == null) return sheet.mode;

    await ref
        .read(registerQueueProvider.notifier)
        .submit(
          SavedRegister(
            clientId: newRegisterClientId(),
            userId: me,
            classSectionId: key.sectionId,
            classSection: key.label,
            date: key.date,
            marks: sheet.marks,
            savedAt: DateTime.now(),
          ),
        );

    final queue = ref.read(registerQueueProvider);
    if (queue.waitingFor(key.sectionId, key.date) != null) {
      state = AsyncData(sheet.copyWith(mode: RegisterMode.waiting));
      return RegisterMode.waiting;
    }

    final refused = queue.unsentFor(key.sectionId, key.date);
    if (refused != null) {
      state = AsyncData(sheet.copyWith(refusal: refused.reason));
      return RegisterMode.taking;
    }

    state = AsyncData(sheet.copyWith(mode: RegisterMode.submitted));
    return RegisterMode.submitted;
  }

  /// A correction goes straight to the server - it changes what parents may
  /// already have been told, so it is not left waiting on a phone. Throws
  /// the server's [Failure].
  Future<void> saveCorrection() async {
    final sheet = state.value;
    if (sheet == null || sheet.mode != RegisterMode.correcting) return;

    await ref
        .read(attendanceRepositoryProvider)
        .update(
          classSectionId: key.sectionId,
          attendanceDate: key.date,
          records: [
            for (final entry in sheet.marks.entries) {'student_id': entry.key, 'status': entry.value.apiValue},
          ],
        );
    state = AsyncData(sheet.copyWith(mode: RegisterMode.submitted));
  }
}
