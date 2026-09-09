import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/auth/data/models/authenticated_user.dart';
import 'package:edutrack_app/features/departments/data/department_repository.dart';
import 'package:edutrack_app/features/departments/data/models/department.dart';
import 'package:edutrack_app/features/hod/data/hod_report_repository.dart';
import 'package:edutrack_app/features/hod/data/models/hod_department_report.dart';
import 'package:edutrack_app/features/hod/presentation/hod_report_screen.dart';
import 'package:edutrack_app/features/schools/data/models/school.dart';
import 'package:edutrack_app/features/schools/data/school_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

import '../../support/fake_auth_repository.dart';
import '../../support/fake_department_repository.dart';
import '../../support/fake_hod_report_repository.dart';
import '../../support/fake_school_repository.dart';

const _hod = AuthenticatedUser(id: 30, name: 'Rohit Verma', email: 'rohit@example.com', role: UserRole.hod);
const _schoolAdmin = AuthenticatedUser(id: 9, name: 'Admin', email: 'admin@example.com', role: UserRole.schoolAdmin);
const _superAdmin = AuthenticatedUser(id: 1, name: 'Root', email: 'root@example.com', role: UserRole.superAdmin);

const _priya = HodTeacherRow(
  staffProfileId: 11,
  userId: 20,
  teacherName: 'Priya Sharma',
  employeeId: 'EMP-020',
  departmentId: 1,
  departmentName: 'Mathematics',
  attendancePercent: 37.5,
  leaveDays: 3.5,
  lateMarks: 1,
  classesAssigned: 4,
  classesTaught: 3,
  reportsSubmitted: 2,
  reportsPendingReview: 1,
  syllabusPercent: 33,
  status: HodTeacherStatus.review,
);

const _rakesh = HodTeacherRow(
  staffProfileId: 12,
  userId: 21,
  teacherName: 'Rakesh Joshi',
  employeeId: 'EMP-021',
  departmentId: 1,
  departmentName: 'Mathematics',
  attendancePercent: 100,
  leaveDays: 0,
  lateMarks: 0,
  classesAssigned: 2,
  classesTaught: 2,
  reportsSubmitted: 2,
  reportsPendingReview: 0,
  syllabusPercent: 50,
  status: HodTeacherStatus.onTrack,
);

HodDepartmentReport report({List<HodTeacherRow> teachers = const [_priya, _rakesh], int total = 2, int lastPage = 1}) {
  return HodDepartmentReport(
    month: '2026-08',
    schoolId: 1,
    departments: const [HodReportDepartment(id: 1, name: 'Mathematics')],
    workingDays: 4,
    teacherCount: 2,
    avgAttendancePercent: 68.8,
    leaveDays: 3.5,
    lateMarks: 1,
    teachers: teachers,
    currentPage: 1,
    lastPage: lastPage,
    total: total,
    perPage: 20,
  );
}

const _mathematics = Department(
  id: 1,
  schoolId: 1,
  schoolName: 'Sunrise Public School',
  name: 'Mathematics',
  hodUserId: 30,
  hodName: 'Rohit Verma',
);

Widget wrap(AuthenticatedUser actor, FakeHodReportRepository fake) {
  return ProviderScope(
    overrides: [
      authRepositoryProvider.overrideWithValue(FakeAuthRepository(sessionOnRestore: actor)),
      schoolRepositoryProvider.overrideWithValue(
        FakeSchoolRepository(
          schools: const [
            School(
              id: 1,
              name: 'Sunrise Public School',
              registrationNumber: 'SPS-001',
              email: 'office@sunrise.example.com',
              phone: '+911234567890',
              address: '1 School Road',
              city: 'Pune',
              state: 'Maharashtra',
              country: 'India',
              postalCode: '411001',
              currencyCode: 'INR',
              logoUrl: null,
              status: SchoolStatus.active,
            ),
          ],
        ),
      ),
      departmentRepositoryProvider.overrideWithValue(FakeDepartmentRepository(departments: [_mathematics])),
      hodReportRepositoryProvider.overrideWithValue(fake),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      home: const Scaffold(body: HodReportScreen()),
    ),
  );
}

String currentMonth() => DateFormat('yyyy-MM').format(DateTime.now());

void useDesktop(WidgetTester tester) {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('shows KPI cards and a teacher table with derived status badges on desktop', (tester) async {
    useDesktop(tester);
    final fake = FakeHodReportRepository(report: report());
    await tester.pumpWidget(wrap(_schoolAdmin, fake));
    await tester.pumpAndSettle();

    expect(find.text('Working Days'), findsOneWidget);
    expect(find.text('4'), findsWidgets);
    expect(find.text('68.8%'), findsOneWidget);
    expect(find.text('3.5'), findsOneWidget);
    expect(find.text('Late Marks'), findsOneWidget);

    expect(find.byType(DataTable), findsOneWidget);
    expect(find.text('Priya Sharma'), findsOneWidget);
    expect(find.text('37.5%'), findsOneWidget);
    expect(find.text('3.5 days'), findsOneWidget);
    expect(find.text('2 (1 pending)'), findsOneWidget);
    expect(find.text('33%'), findsOneWidget);
    expect(find.text('Review'), findsOneWidget);
    expect(find.text('Rakesh Joshi'), findsOneWidget);
    expect(find.text('100%'), findsOneWidget);
    expect(find.text('0 days'), findsOneWidget);
    expect(find.text('On Track'), findsOneWidget);

    expect(fake.lastRequest!['month'], currentMonth());
    expect(fake.lastRequest!['department_id'], isNull);
  });

  testWidgets('renders teacher cards instead of a table on narrow screens', (tester) async {
    final fake = FakeHodReportRepository(report: report());
    await tester.pumpWidget(wrap(_schoolAdmin, fake));
    await tester.pumpAndSettle();

    expect(find.byType(DataTable), findsNothing);
    expect(find.text('Priya Sharma'), findsOneWidget);
    expect(find.text('Attendance 37.5%'), findsOneWidget);
    expect(find.text('Reports 2 (1 pending)'), findsOneWidget);
    expect(find.text('Review'), findsOneWidget);
    expect(find.text('On Track'), findsOneWidget);
  });

  testWidgets('a school admin gets a department picker and can filter by department', (tester) async {
    final fake = FakeHodReportRepository(report: report());
    await tester.pumpWidget(wrap(_schoolAdmin, fake));
    await tester.pumpAndSettle();

    expect(find.text('All Departments'), findsOneWidget);
    expect(find.textContaining('Department: '), findsNothing);

    await tester.tap(find.text('All Departments'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mathematics').last);
    await tester.pumpAndSettle();

    expect(fake.lastRequest!['department_id'], 1);
  });

  testWidgets('an HOD sees their department label and no department picker', (tester) async {
    final fake = FakeHodReportRepository(report: report());
    await tester.pumpWidget(wrap(_hod, fake));
    await tester.pumpAndSettle();

    expect(find.text('Department: Mathematics'), findsOneWidget);
    expect(find.text('All Departments'), findsNothing);
    expect(find.byType(DropdownButtonFormField<int?>), findsNothing);
    expect(fake.lastRequest!['department_id'], isNull);
  });

  testWidgets('stepping to the previous month refetches that month', (tester) async {
    final fake = FakeHodReportRepository(report: report());
    await tester.pumpWidget(wrap(_hod, fake));
    await tester.pumpAndSettle();

    final now = DateTime.now();
    final previous = DateFormat('yyyy-MM').format(DateTime(now.year, now.month - 1));

    await tester.tap(find.byTooltip('Previous month'));
    await tester.pumpAndSettle();

    expect(fake.lastRequest!['month'], previous);
    expect(find.text(DateFormat.yMMMM().format(DateTime(now.year, now.month - 1))), findsOneWidget);
  });

  testWidgets('the next-month button is disabled on the current month', (tester) async {
    final fake = FakeHodReportRepository(report: report());
    await tester.pumpWidget(wrap(_hod, fake));
    await tester.pumpAndSettle();

    final next = tester.widget<IconButton>(
      find.ancestor(of: find.byTooltip('Next month'), matching: find.byType(IconButton)),
    );
    expect(next.onPressed, isNull);
  });

  testWidgets('a super admin must pick a school before anything is fetched', (tester) async {
    final fake = FakeHodReportRepository(report: report());
    await tester.pumpWidget(wrap(_superAdmin, fake));
    await tester.pumpAndSettle();

    expect(find.text('Pick a school to view its report.'), findsOneWidget);
    expect(fake.callCount, 0);

    await tester.tap(find.text('All Schools'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sunrise Public School').last);
    await tester.pumpAndSettle();

    expect(fake.lastRequest!['school_id'], 1);
    expect(find.text('Pick a school to view its report.'), findsNothing);
    expect(find.text('Priya Sharma'), findsOneWidget);
  });

  testWidgets('shows an empty state when the scope has no teachers', (tester) async {
    final fake = FakeHodReportRepository(report: report(teachers: const [], total: 0));
    await tester.pumpWidget(wrap(_hod, fake));
    await tester.pumpAndSettle();

    expect(find.text('No teachers found for this selection.'), findsOneWidget);
    expect(find.text('Working Days'), findsOneWidget);
  });

  testWidgets('shows the failure message with a Retry button on error', (tester) async {
    final fake = FakeHodReportRepository(
      report: report(),
      failWith: const Failure(code: 'FORBIDDEN', message: 'You are not authorized to perform this action.'),
    );
    await tester.pumpWidget(wrap(_hod, fake));
    await tester.pumpAndSettle();

    expect(find.text('You are not authorized to perform this action.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);

    fake.failWith = null;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.text('Priya Sharma'), findsOneWidget);
  });

  testWidgets('shows pagination controls and requests the next page', (tester) async {
    useDesktop(tester);
    final fake = FakeHodReportRepository(report: report(total: 45, lastPage: 3));
    await tester.pumpWidget(wrap(_hod, fake));
    await tester.pumpAndSettle();

    expect(find.text('Page 1 of 3'), findsOneWidget);

    await tester.ensureVisible(find.byTooltip('Next page'));
    await tester.tap(find.byTooltip('Next page'));
    await tester.pumpAndSettle();

    expect(fake.lastRequest!['page'], 2);
  });
}
