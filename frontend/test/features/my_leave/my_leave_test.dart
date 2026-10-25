import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/models/module_access.dart';
import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/core/widgets/teacher_frame.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/my_leave/presentation/apply_leave_screen.dart';
import 'package:edutrack_app/features/my_leave/presentation/my_leave_screen.dart';
import 'package:edutrack_app/features/staff_leave/data/models/leave_status.dart';
import 'package:edutrack_app/features/staff_leave/data/models/leave_type.dart';
import 'package:edutrack_app/features/staff_leave/data/models/staff_leave.dart';
import 'package:edutrack_app/features/staff_leave/data/staff_leave_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../support/fake_auth_repository.dart';
import '../../support/fake_staff_leave_repository.dart';
import '../../support/session_users.dart';

/// "My leave" in the School365ai app (docs/teacher-app.md, T4).
StaffLeave leave({
  int id = 1,
  LeaveType type = LeaveType.casual,
  String start = '2026-10-28',
  String end = '2026-10-29',
  LeaveStatus status = LeaveStatus.pending,
  String? remarks,
}) {
  return StaffLeave(
    id: id,
    schoolId: 1,
    staffProfileId: 1,
    employeeId: 'GPS-TCH-01',
    staffName: 'Meera Joshi',
    departmentName: null,
    leaveType: type,
    startDate: start,
    endDate: end,
    reason: 'Family function.',
    status: status,
    appliedByName: 'Meera Joshi',
    reviewedByName: remarks == null ? null : 'Greenfield Admin',
    reviewRemarks: remarks,
  );
}

void main() {
  Widget app(FakeStaffLeaveRepository repository, {UserRole role = UserRole.teacher, bool leaveOn = true}) {
    final router = GoRouter(
      initialLocation: '/leave',
      routes: [
        GoRoute(
          path: '/leave',
          builder: (context, state) => const TeacherFrame(place: TeacherPlace.leave, child: MyLeaveScreen()),
        ),
        GoRoute(path: '/leave/apply', builder: (context, state) => const ApplyLeaveScreen()),
        GoRoute(
          path: '/today',
          builder: (context, state) => const Scaffold(body: Text('Today')),
        ),
        GoRoute(
          path: '/profile',
          builder: (context, state) => const Scaffold(body: Text('Me')),
        ),
      ],
    );

    return ProviderScope(
      overrides: [
        staffLeaveRepositoryProvider.overrideWithValue(repository),
        authRepositoryProvider.overrideWithValue(
          FakeAuthRepository(
            sessionOnRestore: sessionUser(
              role,
              name: 'Meera Joshi',
              modules: leaveOn ? const {} : const {AppModules.leave: false},
            ),
          ),
        ),
      ],
      child: MaterialApp.router(theme: AppTheme.teacherLight(), routerConfig: router),
    );
  }

  Future<void> open(WidgetTester tester, FakeStaffLeaveRepository repository, {bool leaveOn = true}) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(app(repository, leaveOn: leaveOn));
    await tester.pumpAndSettle();
  }

  Future<void> toApply(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('my-leave-apply')));
    await tester.pumpAndSettle();
  }

  group('the list', () {
    testWidgets('asks for my own requests only, and shows each with where it stands', (tester) async {
      final repository = FakeStaffLeaveRepository(
        leaves: [
          leave(id: 1),
          leave(id: 2, status: LeaveStatus.approved, remarks: 'Enjoy the wedding.'),
          leave(id: 3, type: LeaveType.halfDay, start: '2026-11-02', end: '2026-11-02', status: LeaveStatus.rejected),
        ],
      );
      await open(tester, repository);

      expect(repository.lastListMine, isTrue);
      expect(find.text('Pending'), findsOneWidget);
      expect(find.text('Approved'), findsOneWidget);
      expect(find.text('Rejected'), findsOneWidget);
      expect(find.text('10/28/2026 to 10/29/2026'), findsNWidgets(2));
      expect(find.text('11/02/2026 · half a day'), findsOneWidget);
      expect(find.text('Greenfield Admin: Enjoy the wedding.'), findsOneWidget);
    });

    testWidgets('with nothing yet, it says how to ask', (tester) async {
      await open(tester, FakeStaffLeaveRepository());

      expect(find.byKey(const Key('my-leave-empty')), findsOneWidget);
    });

    testWidgets('a failure shows the error with a retry', (tester) async {
      final repository = FakeStaffLeaveRepository()..failListWith = Failure.network();
      await open(tester, repository);

      expect(find.text('Retry'), findsOneWidget);

      repository.failListWith = null;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('my-leave-empty')), findsOneWidget);
    });

    testWidgets('the Leave tab is there when leave is on', (tester) async {
      await open(tester, FakeStaffLeaveRepository());

      expect(find.byKey(const Key('teacher-nav-leave')), findsOneWidget);
    });

    testWidgets('and gone when the school switched leave off', (tester) async {
      await open(tester, FakeStaffLeaveRepository(), leaveOn: false);

      expect(find.byKey(const Key('teacher-nav-leave')), findsNothing);
      expect(find.byKey(const Key('teacher-nav-today')), findsOneWidget);
    });
  });

  group('applying', () {
    testWidgets('a reason is required, and nothing is sent without one', (tester) async {
      final repository = FakeStaffLeaveRepository();
      await open(tester, repository);
      await toApply(tester);

      await tester.tap(find.byKey(const Key('apply-leave-submit')));
      await tester.pumpAndSettle();

      expect(find.text('Say why you need the leave.'), findsOneWidget);
      expect(repository.lastApplyPayload, isNull);
    });

    testWidgets('a half day is one date: the To field goes and both dates are the same', (tester) async {
      final repository = FakeStaffLeaveRepository();
      await open(tester, repository);
      await toApply(tester);

      expect(find.byKey(const Key('apply-leave-end')), findsOneWidget);
      await tester.tap(find.byKey(const Key('apply-leave-type')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Half Day').last);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('apply-leave-end')), findsNothing);
      expect(find.textContaining('check in for the half you work'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('apply-leave-reason')), 'Doctor in the afternoon.');
      await tester.tap(find.byKey(const Key('apply-leave-submit')));
      await tester.pumpAndSettle();

      final sent = repository.lastApplyPayload!;
      expect(sent['leave_type'], 'half_day');
      expect(sent['start_date'], sent['end_date']);
    });

    testWidgets('a request sent returns to the list, which now has it, and says so', (tester) async {
      final repository = FakeStaffLeaveRepository();
      await open(tester, repository);
      await toApply(tester);

      await tester.enterText(find.byKey(const Key('apply-leave-reason')), 'Family function.');
      await tester.tap(find.byKey(const Key('apply-leave-submit')));
      await tester.pumpAndSettle();

      expect(find.byType(ApplyLeaveScreen), findsNothing);
      expect(find.text('Leave requested. You will see here when it is decided.'), findsOneWidget);
      expect(find.text('Pending'), findsOneWidget);
    });

    testWidgets("an admin's own request approves itself, and the message says so", (tester) async {
      final repository = FakeStaffLeaveRepository(applyResultStatus: LeaveStatus.approved);
      await open(tester, repository);
      await toApply(tester);

      await tester.enterText(find.byKey(const Key('apply-leave-reason')), 'Conference.');
      await tester.tap(find.byKey(const Key('apply-leave-submit')));
      await tester.pumpAndSettle();

      expect(find.text('Leave approved automatically.'), findsOneWidget);
    });

    testWidgets("the server's refusal is shown on the form, which stays", (tester) async {
      final repository = FakeStaffLeaveRepository(
        failApplyWith: const Failure(code: 'LEAVE_OVERLAP', message: 'You already have leave on those dates.'),
      );
      await open(tester, repository);
      await toApply(tester);

      await tester.enterText(find.byKey(const Key('apply-leave-reason')), 'Family function.');
      await tester.tap(find.byKey(const Key('apply-leave-submit')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('apply-leave-error')), findsOneWidget);
      expect(find.text('You already have leave on those dates.'), findsOneWidget);
      expect(find.byType(ApplyLeaveScreen), findsOneWidget);
    });
  });
}
