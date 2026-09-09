import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/features/attendance/application/attendance_register_notifier.dart';
import 'package:edutrack_app/features/attendance/data/attendance_repository.dart';
import 'package:edutrack_app/features/attendance/data/models/attendance_register.dart';
import 'package:edutrack_app/features/attendance/data/models/attendance_status.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_attendance_repository.dart';

const _params = AttendanceRegisterParams(classSectionId: 1, date: '2026-09-08');

AttendanceRegister _unsubmittedRegister() {
  return const AttendanceRegister(
    classSectionId: 1,
    attendanceDate: '2026-09-08',
    submitted: false,
    students: [
      AttendanceRosterEntry(studentId: 1, name: 'Arjun Kumar', rollNumber: '1', status: null, remarks: null),
      AttendanceRosterEntry(studentId: 2, name: 'Aarav Mehta', rollNumber: '2', status: null, remarks: null),
    ],
  );
}

void main() {
  ProviderContainer makeContainer(FakeAttendanceRepository fake) {
    return ProviderContainer(overrides: [attendanceRepositoryProvider.overrideWithValue(fake)]);
  }

  test('build() loads the register for the given class section and date', () async {
    final fake = FakeAttendanceRepository(register: _unsubmittedRegister());
    final container = makeContainer(fake);
    addTearDown(container.dispose);

    final result = await container.read(attendanceRegisterProvider(_params).future);

    expect(result.students, hasLength(2));
    expect(fake.registerCallCount, 1);
  });

  test('setStatus() updates only the targeted student', () async {
    final fake = FakeAttendanceRepository(register: _unsubmittedRegister());
    final container = makeContainer(fake);
    addTearDown(container.dispose);
    await container.read(attendanceRegisterProvider(_params).future);

    container.read(attendanceRegisterProvider(_params).notifier).setStatus(1, AttendanceStatus.absent);

    final state = container.read(attendanceRegisterProvider(_params)).value!;
    expect(state.students.firstWhere((s) => s.studentId == 1).status, AttendanceStatus.absent);
    expect(state.students.firstWhere((s) => s.studentId == 2).status, isNull);
  });

  test('markAllPresent() marks every student present', () async {
    final fake = FakeAttendanceRepository(register: _unsubmittedRegister());
    final container = makeContainer(fake);
    addTearDown(container.dispose);
    await container.read(attendanceRegisterProvider(_params).future);

    container.read(attendanceRegisterProvider(_params).notifier).markAllPresent();

    final state = container.read(attendanceRegisterProvider(_params)).value!;
    expect(state.students.every((s) => s.status == AttendanceStatus.present), isTrue);
  });

  test('isComplete is false until every student has a status', () async {
    final fake = FakeAttendanceRepository(register: _unsubmittedRegister());
    final container = makeContainer(fake);
    addTearDown(container.dispose);
    await container.read(attendanceRegisterProvider(_params).future);
    final notifier = container.read(attendanceRegisterProvider(_params).notifier);

    expect(notifier.isComplete, isFalse);

    notifier.setStatus(1, AttendanceStatus.present);
    expect(notifier.isComplete, isFalse);

    notifier.setStatus(2, AttendanceStatus.absent);
    expect(notifier.isComplete, isTrue);
  });

  test('submitOrUpdate() calls submit() for a not-yet-submitted day', () async {
    final fake = FakeAttendanceRepository(register: _unsubmittedRegister());
    final container = makeContainer(fake);
    addTearDown(container.dispose);
    await container.read(attendanceRegisterProvider(_params).future);
    final notifier = container.read(attendanceRegisterProvider(_params).notifier);
    notifier.markAllPresent();

    await notifier.submitOrUpdate();

    expect(fake.lastSubmitPayload, isNotNull);
    expect(fake.lastUpdatePayload, isNull);
    expect(container.read(attendanceRegisterProvider(_params)).value!.submitted, isTrue);
  });

  test('submitOrUpdate() calls update() once the day is already submitted', () async {
    final submittedRegister = AttendanceRegister(
      classSectionId: 1,
      attendanceDate: '2026-09-08',
      submitted: true,
      students: _unsubmittedRegister().students,
    );
    final fake = FakeAttendanceRepository(register: submittedRegister);
    final container = makeContainer(fake);
    addTearDown(container.dispose);
    await container.read(attendanceRegisterProvider(_params).future);
    final notifier = container.read(attendanceRegisterProvider(_params).notifier);
    notifier.markAllPresent();

    await notifier.submitOrUpdate();

    expect(fake.lastUpdatePayload, isNotNull);
    expect(fake.lastSubmitPayload, isNull);
  });

  test('submitOrUpdate() does nothing while the roster is incomplete', () async {
    final fake = FakeAttendanceRepository(register: _unsubmittedRegister());
    final container = makeContainer(fake);
    addTearDown(container.dispose);
    await container.read(attendanceRegisterProvider(_params).future);
    final notifier = container.read(attendanceRegisterProvider(_params).notifier);
    notifier.setStatus(1, AttendanceStatus.present);

    await notifier.submitOrUpdate();

    expect(fake.lastSubmitPayload, isNull);
  });

  test('submitOrUpdate() lets a Failure propagate to the caller', () async {
    final fake = FakeAttendanceRepository(
      register: _unsubmittedRegister(),
      failSubmitWith: const Failure(
        code: 'ATTENDANCE_ALREADY_SUBMITTED',
        message: 'Attendance has already been submitted.',
      ),
    );
    final container = makeContainer(fake);
    addTearDown(container.dispose);
    await container.read(attendanceRegisterProvider(_params).future);
    final notifier = container.read(attendanceRegisterProvider(_params).notifier);
    notifier.markAllPresent();

    await expectLater(
      notifier.submitOrUpdate(),
      throwsA(isA<Failure>().having((f) => f.code, 'code', 'ATTENDANCE_ALREADY_SUBMITTED')),
    );
  });
}
