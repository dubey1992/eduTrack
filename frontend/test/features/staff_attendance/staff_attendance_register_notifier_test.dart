import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/features/staff_attendance/application/staff_attendance_register_notifier.dart';
import 'package:edutrack_app/features/staff_attendance/data/models/staff_attendance_register.dart';
import 'package:edutrack_app/features/staff_attendance/data/models/staff_attendance_status.dart';
import 'package:edutrack_app/features/staff_attendance/data/staff_attendance_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_staff_attendance_repository.dart';

const _params = StaffAttendanceRegisterParams(schoolId: 1, date: '2026-09-08');

StaffAttendanceRegister _unsubmittedRegister() {
  return const StaffAttendanceRegister(
    schoolId: 1,
    attendanceDate: '2026-09-08',
    submitted: false,
    staff: [
      StaffRosterEntry(
        staffProfileId: 1,
        employeeId: 'EMP-001',
        name: 'Priya Sharma',
        departmentName: 'Mathematics',
        status: null,
        checkIn: null,
        checkOut: null,
        workingHours: null,
        remarks: null,
      ),
      StaffRosterEntry(
        staffProfileId: 2,
        employeeId: 'EMP-002',
        name: 'Rahul Verma',
        departmentName: 'Science',
        status: null,
        checkIn: null,
        checkOut: null,
        workingHours: null,
        remarks: null,
      ),
    ],
  );
}

void main() {
  ProviderContainer makeContainer(FakeStaffAttendanceRepository fake) {
    return ProviderContainer(overrides: [staffAttendanceRepositoryProvider.overrideWithValue(fake)]);
  }

  test('build() loads the register for the given school and date', () async {
    final fake = FakeStaffAttendanceRepository(register: _unsubmittedRegister());
    final container = makeContainer(fake);
    addTearDown(container.dispose);

    final result = await container.read(staffAttendanceRegisterProvider(_params).future);

    expect(result.staff, hasLength(2));
    expect(fake.registerCallCount, 1);
  });

  test('setStatus() updates only the targeted staff member', () async {
    final fake = FakeStaffAttendanceRepository(register: _unsubmittedRegister());
    final container = makeContainer(fake);
    addTearDown(container.dispose);
    await container.read(staffAttendanceRegisterProvider(_params).future);

    container.read(staffAttendanceRegisterProvider(_params).notifier).setStatus(1, StaffAttendanceStatus.absent);

    final state = container.read(staffAttendanceRegisterProvider(_params)).value!;
    expect(state.staff.firstWhere((s) => s.staffProfileId == 1).status, StaffAttendanceStatus.absent);
    expect(state.staff.firstWhere((s) => s.staffProfileId == 2).status, isNull);
  });

  test('setCheckIn() and setCheckOut() update only the targeted staff member', () async {
    final fake = FakeStaffAttendanceRepository(register: _unsubmittedRegister());
    final container = makeContainer(fake);
    addTearDown(container.dispose);
    await container.read(staffAttendanceRegisterProvider(_params).future);
    final notifier = container.read(staffAttendanceRegisterProvider(_params).notifier);

    notifier.setCheckIn(1, '08:05');
    notifier.setCheckOut(1, '15:30');

    final state = container.read(staffAttendanceRegisterProvider(_params)).value!;
    expect(state.staff.firstWhere((s) => s.staffProfileId == 1).checkIn, '08:05');
    expect(state.staff.firstWhere((s) => s.staffProfileId == 1).checkOut, '15:30');
    expect(state.staff.firstWhere((s) => s.staffProfileId == 2).checkIn, isNull);
  });

  test('markAllPresent() marks every staff member present', () async {
    final fake = FakeStaffAttendanceRepository(register: _unsubmittedRegister());
    final container = makeContainer(fake);
    addTearDown(container.dispose);
    await container.read(staffAttendanceRegisterProvider(_params).future);

    container.read(staffAttendanceRegisterProvider(_params).notifier).markAllPresent();

    final state = container.read(staffAttendanceRegisterProvider(_params)).value!;
    expect(state.staff.every((s) => s.status == StaffAttendanceStatus.present), isTrue);
  });

  test('isComplete is false until every staff member has a status', () async {
    final fake = FakeStaffAttendanceRepository(register: _unsubmittedRegister());
    final container = makeContainer(fake);
    addTearDown(container.dispose);
    await container.read(staffAttendanceRegisterProvider(_params).future);
    final notifier = container.read(staffAttendanceRegisterProvider(_params).notifier);

    expect(notifier.isComplete, isFalse);

    notifier.setStatus(1, StaffAttendanceStatus.present);
    expect(notifier.isComplete, isFalse);

    notifier.setStatus(2, StaffAttendanceStatus.halfDay);
    expect(notifier.isComplete, isTrue);
  });

  test('submitOrUpdate() calls submit() for a not-yet-submitted day', () async {
    final fake = FakeStaffAttendanceRepository(register: _unsubmittedRegister());
    final container = makeContainer(fake);
    addTearDown(container.dispose);
    await container.read(staffAttendanceRegisterProvider(_params).future);
    final notifier = container.read(staffAttendanceRegisterProvider(_params).notifier);
    notifier.markAllPresent();

    await notifier.submitOrUpdate();

    expect(fake.lastSubmitPayload, isNotNull);
    expect(fake.lastUpdatePayload, isNull);
    expect(container.read(staffAttendanceRegisterProvider(_params)).value!.submitted, isTrue);
  });

  test('submitOrUpdate() calls update() once the day is already submitted', () async {
    final submittedRegister = StaffAttendanceRegister(
      schoolId: 1,
      attendanceDate: '2026-09-08',
      submitted: true,
      staff: _unsubmittedRegister().staff,
    );
    final fake = FakeStaffAttendanceRepository(register: submittedRegister);
    final container = makeContainer(fake);
    addTearDown(container.dispose);
    await container.read(staffAttendanceRegisterProvider(_params).future);
    final notifier = container.read(staffAttendanceRegisterProvider(_params).notifier);
    notifier.markAllPresent();

    await notifier.submitOrUpdate();

    expect(fake.lastUpdatePayload, isNotNull);
    expect(fake.lastSubmitPayload, isNull);
  });

  test('submitOrUpdate() does nothing while the roster is incomplete', () async {
    final fake = FakeStaffAttendanceRepository(register: _unsubmittedRegister());
    final container = makeContainer(fake);
    addTearDown(container.dispose);
    await container.read(staffAttendanceRegisterProvider(_params).future);
    final notifier = container.read(staffAttendanceRegisterProvider(_params).notifier);
    notifier.setStatus(1, StaffAttendanceStatus.present);

    await notifier.submitOrUpdate();

    expect(fake.lastSubmitPayload, isNull);
  });

  test('submitOrUpdate() lets a Failure propagate to the caller', () async {
    final fake = FakeStaffAttendanceRepository(
      register: _unsubmittedRegister(),
      failSubmitWith: const Failure(
        code: 'ATTENDANCE_ALREADY_SUBMITTED',
        message: 'Attendance has already been submitted.',
      ),
    );
    final container = makeContainer(fake);
    addTearDown(container.dispose);
    await container.read(staffAttendanceRegisterProvider(_params).future);
    final notifier = container.read(staffAttendanceRegisterProvider(_params).notifier);
    notifier.markAllPresent();

    await expectLater(
      notifier.submitOrUpdate(),
      throwsA(isA<Failure>().having((f) => f.code, 'code', 'ATTENDANCE_ALREADY_SUBMITTED')),
    );
  });
}
