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
