/// The four reports, in one shape.
///
/// Every report is a range, a list of rows and a set of totals; only the
/// columns differ. Modelling them as generic rows keeps one screen, one
/// notifier and one CSV path instead of four of each - and the column
/// headings come from the server, so the screen and the export can never
/// disagree about what a column means.
enum ReportKind {
  studentAttendance('student-attendance', 'Student attendance', 'Present, absent and the rate for each student.'),
  staffAttendance(
    'staff-attendance',
    'Staff attendance & leave',
    'Attendance, half days and leave for each staff member.',
  ),
  teachingCoverage(
    'teaching-coverage',
    'Teaching & syllabus',
    'Periods taught against the timetable, and syllabus covered.',
  ),
  transportUsage('transport-usage', 'Transport usage', 'Trips run per route, and the children on them.');

  const ReportKind(this.apiPath, this.label, this.description);

  final String apiPath;
  final String label;
  final String description;
}

class ReportRange {
  const ReportRange({required this.from, required this.to, required this.workingDays});

  factory ReportRange.fromJson(Map<String, dynamic> json) {
    return ReportRange(
      from: json['from'] as String,
      to: json['to'] as String,
      // Absent on a group range, and rightly so: working days belong to one
      // school's calendar, and two schools' cannot be added together.
      workingDays: json['working_days'] as int?,
    );
  }

  final String from;
  final String to;

  /// The days the school actually ran - the denominator behind every rate in
  /// the report, and the reason a holiday cannot drag a percentage down.
  ///
  /// Null for a whole group, where each branch has its own.
  final int? workingDays;
}

/// One branch's slice of a group report.
class ReportBranch {
  const ReportBranch({required this.schoolId, required this.schoolName, required this.range, required this.totals});

  factory ReportBranch.fromJson(Map<String, dynamic> json) {
    return ReportBranch(
      schoolId: json['school_id'] as int,
      schoolName: json['school_name'] as String,
      range: ReportRange.fromJson(json['range'] as Map<String, dynamic>),
      totals: (json['totals'] as Map<String, dynamic>?) ?? const {},
    );
  }

  final int schoolId;
  final String schoolName;
  final ReportRange range;
  final Map<String, dynamic> totals;
}

/// One report's result: the rows as the API returned them, plus its totals.
class ReportResult {
  const ReportResult({required this.range, required this.rows, required this.totals, this.branches = const []});

  factory ReportResult.fromJson(Map<String, dynamic> json) {
    return ReportResult(
      range: ReportRange.fromJson(json['range'] as Map<String, dynamic>),
      rows: (json['rows'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>(),
      totals: (json['totals'] as Map<String, dynamic>?) ?? const {},
      branches: (json['branches'] as List<dynamic>? ?? const [])
          .cast<Map<String, dynamic>>()
          .map(ReportBranch.fromJson)
          .toList(growable: false),
    );
  }

  final ReportRange range;
  final List<Map<String, dynamic>> rows;
  final Map<String, dynamic> totals;

  /// One entry per branch when a group was reported on as a whole; empty for
  /// a single school.
  final List<ReportBranch> branches;

  bool get isGroup => branches.isNotEmpty;

  bool get isEmpty => rows.isEmpty;
}

/// How one column of a report is shown.
class ReportColumn {
  const ReportColumn(this.key, this.label, {this.numeric = false, this.isRate = false});

  final String key;
  final String label;
  final bool numeric;

  /// Rendered as a percentage, and as a dash when null - a missing rate is
  /// "nobody counted", not "nobody came".
  final bool isRate;
}

/// The columns each report shows, in order. Kept beside the enum so a report
/// gains a column in one place.
const Map<ReportKind, List<ReportColumn>> reportColumns = {
  ReportKind.studentAttendance: [
    ReportColumn('admission_number', 'Admission No.'),
    ReportColumn('name', 'Student'),
    ReportColumn('class_section', 'Class'),
    ReportColumn('present', 'Present', numeric: true),
    ReportColumn('absent', 'Absent', numeric: true),
    ReportColumn('leave', 'Leave', numeric: true),
    ReportColumn('not_marked', 'Not marked', numeric: true),
    ReportColumn('attendance_rate', 'Attendance', numeric: true, isRate: true),
  ],
  ReportKind.staffAttendance: [
    ReportColumn('employee_id', 'Employee ID'),
    ReportColumn('name', 'Name'),
    ReportColumn('department', 'Department'),
    ReportColumn('present', 'Present', numeric: true),
    ReportColumn('half_day', 'Half days', numeric: true),
    ReportColumn('absent', 'Absent', numeric: true),
    ReportColumn('leave', 'Leave', numeric: true),
    ReportColumn('attendance_rate', 'Attendance', numeric: true, isRate: true),
  ],
  ReportKind.teachingCoverage: [
    ReportColumn('subject', 'Subject'),
    ReportColumn('department', 'Department'),
    ReportColumn('periods_scheduled', 'Scheduled', numeric: true),
    ReportColumn('periods_reported', 'Reported', numeric: true),
    ReportColumn('periods_missing', 'Missing', numeric: true),
    ReportColumn('coverage_rate', 'Coverage', numeric: true, isRate: true),
    ReportColumn('syllabus_completion', 'Syllabus', numeric: true, isRate: true),
  ],
  ReportKind.transportUsage: [
    ReportColumn('route', 'Route'),
    ReportColumn('vehicle', 'Vehicle'),
    ReportColumn('days_run', 'Days run', numeric: true),
    ReportColumn('days_not_run', 'Days missed', numeric: true),
    ReportColumn('trips_completed', 'Completed', numeric: true),
    ReportColumn('trips_cancelled', 'Cancelled', numeric: true),
    ReportColumn('riders_boarded', 'Boarded', numeric: true),
    ReportColumn('riders_absent', 'Absent', numeric: true),
  ],
};
