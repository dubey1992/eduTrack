import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/storage/key_value_store.dart';
import 'package:edutrack_app/features/attendance/data/attendance_repository.dart';
import 'package:edutrack_app/features/attendance/data/models/attendance_register.dart';
import 'package:edutrack_app/features/attendance/data/models/attendance_status.dart';
import 'package:edutrack_app/features/auth/application/auth_notifier.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/holidays/data/models/holiday.dart';
import 'package:edutrack_app/features/my_register/data/models/saved_register.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

import '../../support/fake_attendance_repository.dart';
import '../../support/fake_auth_repository.dart';
import '../../support/in_memory_key_value_store.dart';
import '../../support/session_users.dart';

/// Grade 3 A, three students, on the school's Monday.
const sectionId = 622;
const day = '2026-10-26';

const teacherId = 7;

AttendanceRegister registerOf({bool submitted = false, Map<int, AttendanceStatus> marks = const {}}) {
  AttendanceRosterEntry student(int id, String name, String roll) =>
      AttendanceRosterEntry(studentId: id, name: name, rollNumber: roll, status: marks[id], remarks: null);

  return AttendanceRegister(
    classSectionId: sectionId,
    attendanceDate: day,
    submitted: submitted,
    students: [student(1, 'Aarav Shah', '1'), student(2, 'Diya Patel', '2'), student(3, 'Kabir Rao', '3')],
  );
}

final noSignal = Failure.network();

const alreadyTaken = Failure(code: 'ATTENDANCE_ALREADY_SUBMITTED', message: 'Attendance has already been submitted.');

SavedRegister savedRegister({
  String clientId = 'a1',
  int userId = teacherId,
  String date = day,
  Map<int, AttendanceStatus>? marks,
}) => SavedRegister(
  clientId: clientId,
  userId: userId,
  classSectionId: sectionId,
  classSection: 'Grade 3 A',
  date: date,
  marks: marks ?? const {1: AttendanceStatus.present, 2: AttendanceStatus.absent, 3: AttendanceStatus.present},
  savedAt: DateTime.utc(2026, 10, 26, 3, 30),
);

List<Override> registerOverrides(
  FakeAttendanceRepository attendance,
  InMemoryKeyValueStore store, {
  int userId = teacherId,
}) => [
  attendanceRepositoryProvider.overrideWithValue(attendance),
  keyValueStoreProvider.overrideWithValue(store),
  authRepositoryProvider.overrideWithValue(
    FakeAuthRepository(
      sessionOnRestore: sessionUser(UserRole.teacher, id: userId, name: 'Meera Joshi'),
    ),
  ),
];

/// A phone with [attendance] behind it, signed in as the teacher.
Future<ProviderContainer> signedInPhone(
  FakeAttendanceRepository attendance,
  InMemoryKeyValueStore store, {
  int userId = teacherId,
}) async {
  final container = ProviderContainer(overrides: registerOverrides(attendance, store, userId: userId));
  await container.read(authNotifierProvider.future);
  return container;
}

AttendanceRegister holidayRegister() => AttendanceRegister(
  classSectionId: sectionId,
  attendanceDate: day,
  submitted: false,
  students: registerOf().students,
  holiday: const HolidaySummary(id: 1, name: 'Diwali', type: HolidayType.religious),
);
