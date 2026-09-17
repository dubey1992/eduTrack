import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/features/dashboard/data/dashboard_repository.dart';
import 'package:edutrack_app/features/dashboard/data/models/dashboard.dart';

class FakeDashboardRepository implements DashboardRepository {
  FakeDashboardRepository({Dashboard? dashboard, this.failWith}) : _dashboard = dashboard ?? defaultDashboard;

  Dashboard _dashboard;
  Failure? failWith;
  int fetchCalls = 0;
  int? lastSchoolId;

  set dashboard(Dashboard value) => _dashboard = value;

  @override
  Future<Dashboard> fetch({int? schoolId}) async {
    if (failWith != null) throw failWith!;

    fetchCalls++;
    lastSchoolId = schoolId;

    return _dashboard;
  }
}

/// A school admin's dashboard on an ordinary working day.
const defaultDashboard = Dashboard(
  role: 'SCHOOL_ADMIN',
  asOf: '2026-09-14',
  isWorkingDay: true,
  holiday: null,
  schoolId: 1,
  cards: [
    DashboardCard(key: 'students', label: 'Students', value: '842', hint: 'on the roll', tone: 'neutral'),
    DashboardCard(key: 'staff', label: 'Teachers & staff', value: '68', hint: 'on the payroll', tone: 'neutral'),
    DashboardCard(
      key: 'attendance',
      label: 'Attendance today',
      value: '94.8%',
      hint: 'of students present',
      tone: 'neutral',
    ),
  ],
  attendanceTrend: [
    TrendPoint(date: '2026-09-10', label: '10 Sep', attendanceRate: 95),
    TrendPoint(date: '2026-09-11', label: '11 Sep', attendanceRate: 71.4),
    TrendPoint(date: '2026-09-14', label: '14 Sep', attendanceRate: null),
  ],
  attention: [AttentionNote(key: 'attendance', message: 'No attendance has been marked yet today.')],
);

/// The Super Admin looking across every school: no single school's opening
/// hours apply, so nothing should claim "the school" is shut.
const platformDashboard = Dashboard(
  role: 'SUPER_ADMIN',
  asOf: '2026-09-14',
  isWorkingDay: false,
  holiday: null,
  schoolId: null,
  cards: [DashboardCard(key: 'schools', label: 'Schools', value: '7', hint: '7 active', tone: 'neutral')],
  attendanceTrend: [],
  attention: [],
);

/// A Super Admin's platform view with money in three currencies - the card
/// that used to wrap mid-amount.
const moneyDashboard = Dashboard(
  role: 'SUPER_ADMIN',
  asOf: '2026-09-17',
  isWorkingDay: false,
  holiday: null,
  schoolId: null,
  cards: [
    DashboardCard(key: 'schools', label: 'Schools', value: '60', hint: '44 active', tone: 'neutral'),
    DashboardCard(
      key: 'collected',
      label: 'Collected',
      value: 'INR 2,002,000.00 + NGN 45,000.01 + USD 1,234.50',
      hint: 'money received',
      tone: 'neutral',
    ),
    DashboardCard(key: 'outstanding', label: 'Payments owing', value: '14', hint: 'pending or part paid', tone: 'warning'),
  ],
  attendanceTrend: [],
  attention: [],
);

/// The same school on a holiday: nothing marked, and that is expected.
const holidayDashboard = Dashboard(
  role: 'SCHOOL_ADMIN',
  asOf: '2026-09-21',
  isWorkingDay: false,
  holiday: 'Founders Day',
  schoolId: 1,
  cards: [DashboardCard(key: 'students', label: 'Students', value: '842', hint: 'on the roll', tone: 'neutral')],
  attendanceTrend: [],
  attention: [],
);
