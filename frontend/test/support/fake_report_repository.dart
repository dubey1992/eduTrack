import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/features/reports/data/models/report.dart';
import 'package:edutrack_app/features/reports/data/report_repository.dart';

class FakeReportRepository implements ReportRepository {
  FakeReportRepository({ReportResult? result, this.failWith, this.resultsByKind = const {}})
    : _result = result ?? studentAttendanceResult;

  final ReportResult _result;

  /// A different answer for particular reports, for tests that switch.
  final Map<ReportKind, ReportResult> resultsByKind;
  Failure? failWith;

  ReportKind? lastKind;
  String? lastFrom;
  String? lastTo;
  int? lastSchoolId;
  bool? lastCompare;
  int? lastBelow;
  ExportFormat? lastFormat;
  int downloadCalls = 0;

  @override
  Future<ReportResult> fetch(
    ReportKind kind, {
    int? schoolId,
    String? from,
    String? to,
    int? classSectionId,
    int? departmentId,
    bool compare = false,
    int? below,
  }) async {
    if (failWith != null) throw failWith!;

    lastKind = kind;
    lastFrom = from;
    lastTo = to;
    lastSchoolId = schoolId;
    lastCompare = compare;
    lastBelow = below;

    return resultsByKind[kind] ?? _result;
  }

  @override
  Future<List<int>> download(
    ReportKind kind,
    ExportFormat format, {
    int? schoolId,
    String? from,
    String? to,
    int? classSectionId,
    int? departmentId,
    bool compare = false,
    int? below,
  }) async {
    if (failWith != null) throw failWith!;

    downloadCalls++;
    lastKind = kind;
    lastFormat = format;
    lastCompare = compare;

    return 'Admission No.,Student\nSTU-0042,Arjun Kumar\n'.codeUnits;
  }
}

/// Five working days, one student present for three of them.
final studentAttendanceResult = ReportResult(
  range: const ReportRange(from: '2026-09-07', to: '2026-09-11', workingDays: 5),
  rows: [
    {
      'student_id': 1,
      'admission_number': 'STU-0042',
      'name': 'Arjun Kumar',
      'class_section': 'Grade 8 A',
      'working_days': 5,
      'present': 3,
      'absent': 1,
      'leave': 0,
      'not_marked': 1,
      'attendance_rate': 60.0,
    },
    {
      'student_id': 2,
      'admission_number': 'STU-0043',
      'name': 'Meera Singh',
      'class_section': 'Grade 8 A',
      'working_days': 5,
      'present': 5,
      'absent': 0,
      'leave': 0,
      'not_marked': 0,
      'attendance_rate': 100.0,
    },
  ],
  totals: const {'students': 2, 'working_days': 5, 'present': 8, 'absent': 1, 'attendance_rate': 80.0},
);

/// A period the school never opened - every rate is null, not zero.
final closedWeekResult = ReportResult(
  range: const ReportRange(from: '2026-09-12', to: '2026-09-13', workingDays: 0),
  rows: [
    {
      'student_id': 1,
      'admission_number': 'STU-0042',
      'name': 'Arjun Kumar',
      'class_section': 'Grade 8 A',
      'working_days': 0,
      'present': 0,
      'absent': 0,
      'leave': 0,
      'not_marked': 0,
      'attendance_rate': null,
    },
  ],
  totals: const {'students': 1, 'working_days': 0, 'attendance_rate': null},
);

final emptyResult = ReportResult(
  range: const ReportRange(from: '2026-09-07', to: '2026-09-11', workingDays: 5),
  rows: const [],
  totals: const {'students': 0, 'working_days': 5},
);

/// A group report: two branches with different working days, combined.
///
/// North ran five days and had one student present for all of them; South ran
/// four (a local holiday) and had one present for two. Eight present marks
/// against nine possible - 88.9% - which is *not* the average of 100% and
/// 50%.
final groupResult = ReportResult(
  range: const ReportRange(from: '2026-09-07', to: '2026-09-11', workingDays: null),
  branches: const [
    ReportBranch(
      schoolId: 2,
      schoolName: "St Mary's North",
      range: ReportRange(from: '2026-09-07', to: '2026-09-11', workingDays: 5),
      totals: {'students': 1, 'working_days': 5, 'present': 5, 'attendance_rate': 100.0},
    ),
    ReportBranch(
      schoolId: 3,
      schoolName: "St Mary's South",
      range: ReportRange(from: '2026-09-07', to: '2026-09-11', workingDays: 4),
      totals: {'students': 1, 'working_days': 4, 'present': 2, 'attendance_rate': 50.0},
    ),
  ],
  rows: [
    {
      'school_id': 2,
      'school_name': "St Mary's North",
      'admission_number': 'N-1',
      'name': 'Aarav Sharma',
      'class_section': 'Grade 5 A',
      'present': 5,
      'absent': 0,
      'leave': 0,
      'not_marked': 0,
      'attendance_rate': 100.0,
    },
    {
      'school_id': 3,
      'school_name': "St Mary's South",
      'admission_number': 'S-1',
      'name': 'Ishaan Patel',
      'class_section': 'Grade 5 A',
      'present': 2,
      'absent': 2,
      'leave': 0,
      'not_marked': 0,
      'attendance_rate': 50.0,
    },
  ],
  totals: const {'branches': 2, 'students': 2, 'present': 7, 'absent': 2, 'attendance_rate': 77.8},
);

/// Student attendance compared with the week before: Arjun up from 33.3%,
/// Meera new since then.
final comparedResult = ReportResult(
  range: const ReportRange(from: '2026-09-07', to: '2026-09-11', workingDays: 5),
  comparison: const ReportComparison(
    range: ReportRange(from: '2026-09-02', to: '2026-09-06', workingDays: 3),
    totals: {'students': 1, 'working_days': 3, 'present': 1, 'attendance_rate': 33.3},
  ),
  rows: [
    {
      ...studentAttendanceResult.rows[0],
      'previous': {'attendance_rate': 33.3},
    },
    {
      ...studentAttendanceResult.rows[1],
      'previous': {'attendance_rate': null},
    },
  ],
  totals: studentAttendanceResult.totals,
);

/// Two employees, one of them paid in two currencies over the range.
final payrollResult = ReportResult(
  range: const ReportRange(from: '2026-08-01', to: '2026-09-11', workingDays: 30),
  rows: const [
    {
      'staff_profile_id': 1,
      'employee_id': 'EMP-T',
      'name': 'Tara Teacher',
      'department': 'Science',
      'currency_code': 'INR',
      'payslips': 2,
      'paid_days': 39.5,
      'gross': '68400.00',
      'deductions': '3600.00',
      'net': '64800.00',
      'paid': '30000.00',
      'unpaid': '34800.00',
    },
    {
      'staff_profile_id': 1,
      'employee_id': 'EMP-T',
      'name': 'Tara Teacher',
      'department': 'Science',
      'currency_code': 'USD',
      'payslips': 1,
      'paid_days': 21.0,
      'gross': '400.00',
      'deductions': '0.00',
      'net': '400.00',
      'paid': '0.00',
      'unpaid': '400.00',
    },
  ],
  totals: const {
    'employees': 1,
    'payslips': 3,
    'months': ['2026-08', '2026-09'],
    'by_currency': [
      {
        'currency_code': 'INR',
        'gross': '68400.00',
        'deductions': '3600.00',
        'net': '64800.00',
        'paid': '30000.00',
        'unpaid': '34800.00',
      },
      {
        'currency_code': 'USD',
        'gross': '400.00',
        'deductions': '0.00',
        'net': '400.00',
        'paid': '0.00',
        'unpaid': '400.00',
      },
    ],
  },
);
