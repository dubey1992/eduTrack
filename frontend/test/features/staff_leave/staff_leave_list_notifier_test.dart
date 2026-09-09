import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/features/staff_leave/application/staff_leave_list_notifier.dart';
import 'package:edutrack_app/features/staff_leave/data/models/leave_status.dart';
import 'package:edutrack_app/features/staff_leave/data/models/leave_type.dart';
import 'package:edutrack_app/features/staff_leave/data/models/staff_leave.dart';
import 'package:edutrack_app/features/staff_leave/data/staff_leave_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_staff_leave_repository.dart';

const _pendingLeave = StaffLeave(
  id: 1,
  schoolId: 1,
  staffProfileId: 1,
  employeeId: 'EMP-001',
  staffName: 'Priya Sharma',
  departmentName: 'Mathematics',
  leaveType: LeaveType.casual,
  startDate: '2026-09-15',
  endDate: '2026-09-16',
  reason: 'Family function.',
  status: LeaveStatus.pending,
  appliedByName: 'Priya Sharma',
  reviewedByName: null,
  reviewRemarks: null,
);

void main() {
  ProviderContainer makeContainer(FakeStaffLeaveRepository fake) {
    return ProviderContainer(overrides: [staffLeaveRepositoryProvider.overrideWithValue(fake)]);
  }

  test('build() loads the first page of leave requests', () async {
    final fake = FakeStaffLeaveRepository(leaves: [_pendingLeave]);
    final container = makeContainer(fake);
    addTearDown(container.dispose);

    final result = await container.read(staffLeaveListNotifierProvider.future);

    expect(result.items, hasLength(1));
    expect(result.items.first.staffName, 'Priya Sharma');
  });

  test('applyLeave() submits the request and refreshes the list', () async {
    final fake = FakeStaffLeaveRepository();
    final container = makeContainer(fake);
    addTearDown(container.dispose);
    await container.read(staffLeaveListNotifierProvider.future);

    await container
        .read(staffLeaveListNotifierProvider.notifier)
        .applyLeave(leaveType: LeaveType.medical, startDate: '2026-09-20', endDate: '2026-09-21', reason: 'Fever.');

    expect(fake.lastApplyPayload, isNotNull);
    expect(fake.lastApplyPayload!['leave_type'], 'medical');
    final state = container.read(staffLeaveListNotifierProvider).value!;
    expect(state.items, hasLength(1));
  });

  test('approve() updates the matching leave in place', () async {
    final fake = FakeStaffLeaveRepository(leaves: [_pendingLeave]);
    final container = makeContainer(fake);
    addTearDown(container.dispose);
    await container.read(staffLeaveListNotifierProvider.future);

    await container.read(staffLeaveListNotifierProvider.notifier).approve(_pendingLeave);

    expect(fake.lastApprovedId, 1);
    final state = container.read(staffLeaveListNotifierProvider).value!;
    expect(state.items.first.status, LeaveStatus.approved);
  });

  test('reject() updates the matching leave in place', () async {
    final fake = FakeStaffLeaveRepository(leaves: [_pendingLeave]);
    final container = makeContainer(fake);
    addTearDown(container.dispose);
    await container.read(staffLeaveListNotifierProvider.future);

    await container.read(staffLeaveListNotifierProvider.notifier).reject(_pendingLeave, remarks: 'Not eligible.');

    expect(fake.lastRejectedId, 1);
    final state = container.read(staffLeaveListNotifierProvider).value!;
    expect(state.items.first.status, LeaveStatus.rejected);
    expect(state.items.first.reviewRemarks, 'Not eligible.');
  });

  test('applyLeave() lets a Failure propagate to the caller', () async {
    final fake = FakeStaffLeaveRepository(
      failApplyWith: const Failure(
        code: 'LEAVE_OVERLAP',
        message: 'This staff member already has an overlapping leave request.',
      ),
    );
    final container = makeContainer(fake);
    addTearDown(container.dispose);
    await container.read(staffLeaveListNotifierProvider.future);

    await expectLater(
      container
          .read(staffLeaveListNotifierProvider.notifier)
          .applyLeave(leaveType: LeaveType.casual, startDate: '2026-09-20', endDate: '2026-09-21', reason: 'x'),
      throwsA(isA<Failure>().having((f) => f.code, 'code', 'LEAVE_OVERLAP')),
    );
  });
}
