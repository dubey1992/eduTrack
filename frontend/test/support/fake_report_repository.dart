import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/features/reports/data/models/report.dart';
import 'package:edutrack_app/features/reports/data/report_repository.dart';

class FakeReportRepository implements ReportRepository {
  FakeReportRepository({ReportResult? result, this.failWith}) : _result = result ?? studentAttendanceResult;

  final ReportResult _result;
  Failure? failWith;

  ReportKind? lastKind;
  String? lastFrom;
  String? lastTo;
  int? lastSchoolId;
  int downloadCalls = 0;

  @override
  Future<ReportResult> fetch(
    ReportKind kind, {
    int? schoolId,
    String? from,
    String? to,
    int? classSectionId,
    int? departmentId,
  }) async {
    if (failWith != null) throw failWith!;

    lastKind = kind;
    lastFrom = from;
    lastTo = to;
    lastSchoolId = schoolId;

    return _result;
  }

  @override
  Future<List<int>> downloadCsv(
    ReportKind kind, {
    int? schoolId,
    String? from,
    String? to,
    int? classSectionId,
    int? departmentId,
  }) async {
    if (failWith != null) throw failWith!;

    downloadCalls++;
    lastKind = kind;

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
