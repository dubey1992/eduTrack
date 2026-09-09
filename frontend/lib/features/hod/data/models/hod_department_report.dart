import '../../../../core/network/paginated_response.dart';

/// Derived server-side (see backend HodReportService): "review" when the
/// teacher has reports awaiting HOD review or filed fewer reports than
/// classes taught this month, otherwise "on_track".
enum HodTeacherStatus {
  onTrack('on_track', 'On Track'),
  review('review', 'Review');

  const HodTeacherStatus(this.apiValue, this.label);

  final String apiValue;
  final String label;

  static HodTeacherStatus fromApi(String value) => values.firstWhere((s) => s.apiValue == value);
}

class HodReportDepartment {
  const HodReportDepartment({required this.id, required this.name});

  factory HodReportDepartment.fromJson(Map<String, dynamic> json) {
    return HodReportDepartment(id: json['id'] as int, name: json['name'] as String);
  }

  final int id;
  final String name;
}

class HodTeacherRow {
  const HodTeacherRow({
    required this.staffProfileId,
    required this.userId,
    required this.teacherName,
    required this.employeeId,
    required this.departmentId,
    required this.departmentName,
    required this.attendancePercent,
    required this.leaveDays,
    required this.lateMarks,
    required this.classesAssigned,
    required this.classesTaught,
    required this.reportsSubmitted,
    required this.reportsPendingReview,
    required this.syllabusPercent,
    required this.status,
  });

  factory HodTeacherRow.fromJson(Map<String, dynamic> json) {
    return HodTeacherRow(
      staffProfileId: json['staff_profile_id'] as int,
      userId: json['user_id'] as int,
      teacherName: json['teacher_name'] as String,
      employeeId: json['employee_id'] as String?,
      departmentId: json['department_id'] as int?,
      departmentName: json['department_name'] as String?,
      attendancePercent: (json['attendance_percent'] as num).toDouble(),
      leaveDays: (json['leave_days'] as num).toDouble(),
      lateMarks: json['late_marks'] as int,
      classesAssigned: json['classes_assigned'] as int,
      classesTaught: json['classes_taught'] as int,
      reportsSubmitted: json['reports_submitted'] as int,
      reportsPendingReview: json['reports_pending_review'] as int,
      syllabusPercent: json['syllabus_percent'] as int,
      status: HodTeacherStatus.fromApi(json['status'] as String),
    );
  }

  final int staffProfileId;
  final int userId;
  final String teacherName;
  final String? employeeId;
  final int? departmentId;
  final String? departmentName;
  final double attendancePercent;
  final double leaveDays;
  final int lateMarks;
  final int classesAssigned;
  final int classesTaught;
  final int reportsSubmitted;
  final int reportsPendingReview;
  final int syllabusPercent;
  final HodTeacherStatus status;
}

/// One month of a department's (or a whole school's) teaching performance
/// - the department-wide KPIs plus one paginated page of teacher rows (see
/// `GET /hod/department-report`).
class HodDepartmentReport {
  const HodDepartmentReport({
    required this.month,
    required this.schoolId,
    required this.departments,
    required this.workingDays,
    required this.teacherCount,
    required this.avgAttendancePercent,
    required this.leaveDays,
    required this.lateMarks,
    required this.teachers,
    required this.currentPage,
    required this.lastPage,
    required this.total,
    required this.perPage,
  });

  factory HodDepartmentReport.fromJson(Map<String, dynamic> json) {
    final page = PaginatedResponse.fromJson(json, HodTeacherRow.fromJson);

    return HodDepartmentReport(
      month: json['month'] as String,
      schoolId: json['school_id'] as int,
      departments: (json['departments'] as List)
          .cast<Map<String, dynamic>>()
          .map(HodReportDepartment.fromJson)
          .toList(),
      workingDays: json['working_days'] as int,
      teacherCount: json['teacher_count'] as int,
      avgAttendancePercent: (json['avg_attendance_percent'] as num).toDouble(),
      leaveDays: (json['leave_days'] as num).toDouble(),
      lateMarks: json['late_marks'] as int,
      teachers: page.items,
      currentPage: page.currentPage,
      lastPage: page.lastPage,
      total: page.total,
      perPage: page.perPage,
    );
  }

  final String month;
  final int schoolId;
  final List<HodReportDepartment> departments;
  final int workingDays;
  final int teacherCount;
  final double avgAttendancePercent;
  final double leaveDays;
  final int lateMarks;
  final List<HodTeacherRow> teachers;
  final int currentPage;
  final int lastPage;
  final int total;
  final int perPage;
}
