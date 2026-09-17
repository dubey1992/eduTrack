import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/auth/data/models/authenticated_user.dart';
import 'package:edutrack_app/features/staff_leave/data/models/leave_status.dart';
import 'package:edutrack_app/features/staff_leave/data/models/leave_type.dart';
import 'package:edutrack_app/features/staff_leave/data/models/staff_leave.dart';
import 'package:edutrack_app/features/staff_leave/data/staff_leave_repository.dart';
import 'package:edutrack_app/features/staff_leave/presentation/staff_leave_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_auth_repository.dart';
import '../../support/fake_staff_leave_repository.dart';
import '../../support/paginated_table.dart';

const _teacher = AuthenticatedUser(id: 1, name: 'Priya Sharma', email: 'priya@example.com', role: UserRole.teacher);
const _schoolAdmin = AuthenticatedUser(id: 9, name: 'Admin', email: 'admin@example.com', role: UserRole.schoolAdmin);

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

Widget wrap(AuthenticatedUser actor, {FakeStaffLeaveRepository? staffLeave}) {
  return ProviderScope(
    overrides: [
      authRepositoryProvider.overrideWithValue(FakeAuthRepository(sessionOnRestore: actor)),
      staffLeaveRepositoryProvider.overrideWithValue(staffLeave ?? FakeStaffLeaveRepository(leaves: [_pendingLeave])),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      home: const Scaffold(body: StaffLeaveScreen()),
    ),
  );
}

void main() {
  testWidgets('an accountant applies for leave like any employee and reviews nobody', (tester) async {
    const accountant = AuthenticatedUser(
      id: 3,
      name: 'Meena Iyer',
      email: 'meena@example.com',
      role: UserRole.accountant,
    );
    await tester.pumpWidget(wrap(accountant));
    await tester.pumpAndSettle();

    expect(find.text('Apply Leave'), findsOneWidget);
    expect(find.text('Approve'), findsNothing);
    expect(find.text('Reject'), findsNothing);
  });

  testWidgets('a teacher sees the Apply Leave action but no approve/reject controls', (tester) async {
    await tester.pumpWidget(wrap(_teacher));
    await tester.pumpAndSettle();

    expect(find.text('Apply Leave'), findsOneWidget);
    expect(find.text('Approve'), findsNothing);
    expect(find.text('Reject'), findsNothing);
    expect(find.text('Priya Sharma'), findsWidgets);
  });

  testWidgets('a school admin sees both the Apply Leave action and approve/reject controls', (tester) async {
    await tester.pumpWidget(wrap(_schoolAdmin));
    await tester.pumpAndSettle();

    // A school admin gets a minimal auto-created StaffProfile (see
    // UserService::create() on the backend) so they can apply for their
    // own leave, in addition to reviewing everyone else's - self-review is
    // blocked server-side, not by hiding either action here.
    expect(find.text('Apply Leave'), findsOneWidget);
    expect(find.text('Approve'), findsOneWidget);
    expect(find.text('Reject'), findsOneWidget);
  });

  testWidgets('approving a leave request updates its status badge', (tester) async {
    final fake = FakeStaffLeaveRepository(leaves: [_pendingLeave]);
    await tester.pumpWidget(wrap(_schoolAdmin, staffLeave: fake));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Approve'));
    await tester.pumpAndSettle();

    expect(fake.lastApprovedId, 1);
    // One "Approved" is the status filter chip; the other is the leave's
    // status badge now that it's been reviewed.
    expect(find.text('Approved'), findsNWidgets(2));
    expect(find.text('Leave request approved.'), findsOneWidget);
  });

  testWidgets('rejecting a leave request updates its status badge', (tester) async {
    final fake = FakeStaffLeaveRepository(leaves: [_pendingLeave]);
    await tester.pumpWidget(wrap(_schoolAdmin, staffLeave: fake));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Reject'));
    await tester.pumpAndSettle();

    expect(fake.lastRejectedId, 1);
    // "Rejected" shows up three times here: the status filter chip, the
    // "Rejected" KPI card in the summary row, and the leave's own status
    // badge now that it's been reviewed.
    expect(find.text('Rejected'), findsNWidgets(3));
    expect(find.text('Leave request rejected.'), findsOneWidget);
  });

  testWidgets('a school admin applying for their own leave is told it was auto-approved', (tester) async {
    final fake = FakeStaffLeaveRepository(applyResultStatus: LeaveStatus.approved);
    await tester.pumpWidget(wrap(_schoolAdmin, staffLeave: fake));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Apply Leave'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextFormField, 'Reason'), 'Family function');
    await tester.tap(find.text('Submit Request'));
    await tester.pumpAndSettle();

    expect(fake.lastApplyPayload, isNotNull);
    expect(find.text('Leave request approved automatically.'), findsOneWidget);
  });
  testWidgets('a full page of leave scrolls above the pagination bar on desktop', (tester) async {
    useShortDesktopWindow(tester);
    final leaves = [
      for (var n = 1; n <= 20; n++)
        StaffLeave(
          id: n,
          schoolId: 1,
          staffProfileId: n,
          employeeId: 'EMP-$n',
          staffName: 'Staff Member $n',
          departmentName: 'Mathematics',
          leaveType: LeaveType.casual,
          startDate: '2026-09-15',
          endDate: '2026-09-16',
          reason: 'Family function.',
          status: LeaveStatus.approved,
          appliedByName: 'Staff Member $n',
          reviewedByName: null,
          reviewRemarks: null,
        ),
    ];
    await tester.pumpWidget(wrap(_schoolAdmin, staffLeave: FakeStaffLeaveRepository(leaves: leaves)));
    await tester.pumpAndSettle();

    await expectLastRowScrollsAbovePagination(tester, find.text('Staff Member 20'));
  });
}
