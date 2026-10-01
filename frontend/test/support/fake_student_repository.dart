import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/network/paginated_response.dart';
import 'package:edutrack_app/features/students/data/models/student.dart';
import 'package:edutrack_app/features/students/data/models/student_enrollment.dart';
import 'package:edutrack_app/features/students/data/models/student_performance.dart';
import 'package:edutrack_app/features/students/data/student_repository.dart';

import 'fake_pagination.dart';

class FakeStudentRepository implements StudentRepository {
  FakeStudentRepository({
    List<Student>? students,
    List<StudentEnrollment>? enrollments,
    StudentPerformance? performance,
    this.failCreateWith,
    this.failUpdateWith,
    this.failSetActiveWith,
    this.failListWith,
    this.failSetTransportWith,
    this.failWith = const {},
  }) : _students = students ?? [],
       _enrollments = enrollments ?? [],
       _performance = performance ?? fakePerformance();

  final List<Student> _students;
  final List<StudentEnrollment> _enrollments;
  final StudentPerformance _performance;

  /// Which term each performance call asked for - null for "the one being
  /// lived", which is what the server picks.
  final List<int?> termCalls = [];

  /// Keyed by method name, for the methods added since: {'enrollments': ...}.
  final Map<String, Failure> failWith;

  /// The methods this fake has been asked for, in order.
  final List<String> calls = [];
  Failure? failCreateWith;
  Failure? failUpdateWith;
  Failure? failSetActiveWith;
  Failure? failListWith;
  Failure? failSetTransportWith;

  List<Student> get students => List.unmodifiable(_students);

  /// Every search term listPage has been asked for, in order. Searching is
  /// the server's job, so a test that wants to know the screen actually asked
  /// - and how many times - has to look here.
  final List<String?> searchCalls = [];

  /// Which status each list call asked for - null for "any".
  final List<String?> statusCalls = [];

  List<Student> _filtered({int? schoolId, String? search}) {
    var found = schoolId == null ? _students : _students.where((s) => s.schoolId == schoolId).toList();

    if (search != null && search.trim().isNotEmpty) {
      final term = search.trim().toLowerCase();
      found = found
          .where((s) => s.name.toLowerCase().contains(term) || s.admissionNumber.toLowerCase().contains(term))
          .toList();
    }

    return found.toList();
  }

  @override
  Future<List<Student>> list({int? schoolId, int? classSectionId, String? search}) async {
    if (failListWith != null) throw failListWith!;
    return List.unmodifiable(_filtered(schoolId: schoolId, search: search));
  }

  @override
  Future<PaginatedResponse<Student>> listPage({
    int? schoolId,
    int? classSectionId,
    String? search,
    String? status,
    required int page,
    required int perPage,
  }) async {
    searchCalls.add(search);
    statusCalls.add(status);
    if (failListWith != null) throw failListWith!;

    final rows = _filtered(schoolId: schoolId, search: search);

    return paginateFake(
      status == null ? rows : rows.where((student) => student.status.apiValue == status).toList(),
      page: page,
      perPage: perPage,
    );
  }

  @override
  Future<Student> create({
    int? schoolId,
    required int classSectionId,
    required String admissionNumber,
    required String firstName,
    required String lastName,
    String? rollNumber,
    required String guardianName,
    String? guardianMobile,
    String? guardianEmail,
    String? studentMobile,
    String? studentEmail,
    String? address,
  }) async {
    if (failCreateWith != null) throw failCreateWith!;

    final student = Student(
      id: _students.length + 1,
      schoolId: schoolId ?? 1,
      schoolName: 'Test School',
      classSectionId: classSectionId,
      classSectionName: 'Grade 8 A',
      admissionNumber: admissionNumber,
      firstName: firstName,
      lastName: lastName,
      name: '$firstName $lastName',
      rollNumber: rollNumber,
      guardianName: guardianName,
      guardianMobile: guardianMobile,
      guardianEmail: guardianEmail,
      studentMobile: studentMobile,
      studentEmail: studentEmail,
      address: address,
      status: StudentStatus.active,
    );
    _students.add(student);
    return student;
  }

  /// The arguments of the last update, as named by the API - so a test can
  /// tell a field cleared (null) from a field left alone.
  Map<String, Object?>? lastUpdate;

  @override
  Future<Student> update(
    int studentId, {
    int? classSectionId,
    String? admissionNumber,
    String? firstName,
    String? lastName,
    String? rollNumber,
    String? guardianName,
    String? guardianMobile,
    String? guardianEmail,
    String? studentMobile,
    String? studentEmail,
    String? address,
  }) async {
    lastUpdate = {
      'student_id': studentId,
      'class_section_id': classSectionId,
      'roll_number': rollNumber,
      'guardian_name': guardianName,
      'guardian_mobile': guardianMobile,
      'guardian_email': guardianEmail,
      'student_mobile': studentMobile,
      'student_email': studentEmail,
      'address': address,
    };
    if (failUpdateWith != null) throw failUpdateWith!;

    final index = _students.indexWhere((s) => s.id == studentId);
    final existing = _students[index];
    final updated = Student(
      id: existing.id,
      schoolId: existing.schoolId,
      schoolName: existing.schoolName,
      classSectionId: classSectionId ?? existing.classSectionId,
      classSectionName: existing.classSectionName,
      admissionNumber: admissionNumber ?? existing.admissionNumber,
      firstName: firstName ?? existing.firstName,
      lastName: lastName ?? existing.lastName,
      name: existing.name,
      rollNumber: rollNumber ?? existing.rollNumber,
      guardianName: guardianName ?? existing.guardianName,
      guardianMobile: guardianMobile ?? existing.guardianMobile,
      guardianEmail: guardianEmail ?? existing.guardianEmail,
      studentMobile: studentMobile ?? existing.studentMobile,
      studentEmail: studentEmail ?? existing.studentEmail,
      address: address ?? existing.address,
      status: existing.status,
      transport: existing.transport,
    );
    _students[index] = updated;
    return updated;
  }

  Map<String, Object?>? lastTransportCall;

  @override
  Future<Student> setTransport(int studentId, {required int? routeId, required int? stopId}) async {
    if (failSetTransportWith != null) throw failSetTransportWith!;
    lastTransportCall = {'student_id': studentId, 'route_id': routeId, 'stop_id': stopId};

    final index = _students.indexWhere((s) => s.id == studentId);
    final e = _students[index];
    final updated = Student(
      id: e.id,
      schoolId: e.schoolId,
      schoolName: e.schoolName,
      classSectionId: e.classSectionId,
      classSectionName: e.classSectionName,
      admissionNumber: e.admissionNumber,
      firstName: e.firstName,
      lastName: e.lastName,
      name: e.name,
      rollNumber: e.rollNumber,
      guardianName: e.guardianName,
      guardianMobile: e.guardianMobile,
      guardianEmail: e.guardianEmail,
      studentMobile: e.studentMobile,
      studentEmail: e.studentEmail,
      address: e.address,
      status: e.status,
      transport: routeId == null || stopId == null
          ? null
          : StudentTransport(
              routeId: routeId,
              routeName: 'Green Park',
              routeLabel: 'Bus 04 - Green Park',
              vehicleName: 'Bus 04',
              stopId: stopId,
              stopName: stopId == 101 ? 'Lake View' : 'Central Park',
            ),
    );
    _students[index] = updated;
    return updated;
  }

  @override
  Future<Student> setActive(int studentId, bool active) async {
    if (failSetActiveWith != null) throw failSetActiveWith!;

    final index = _students.indexWhere((s) => s.id == studentId);
    final updated = _students[index].copyWith(status: active ? StudentStatus.active : StudentStatus.inactive);
    _students[index] = updated;
    return updated;
  }

  @override
  Future<StudentPerformance> performance(int studentId, {int? academicTermId}) async {
    calls.add('performance');
    termCalls.add(academicTermId);
    final failure = failWith['performance'];
    if (failure != null) throw failure;

    return _performance;
  }

  /// Which term each progress report asked for, so a test can check the
  /// download is of the term on screen rather than of whatever the server
  /// would have picked.
  final List<int?> progressReportCalls = [];

  @override
  Future<List<int>> progressReport(int studentId, {int? academicTermId}) async {
    calls.add('progressReport');
    progressReportCalls.add(academicTermId);
    final failure = failWith['progressReport'];
    if (failure != null) throw failure;

    return const [37, 80, 68, 70];
  }

  @override
  Future<List<StudentEnrollment>> enrollments(int studentId) async {
    calls.add('enrollments');
    final failure = failWith['enrollments'];
    if (failure != null) throw failure;

    return List.unmodifiable(_enrollments);
  }
}

/// A term of marks without a server: two subjects, one of them weak, one
/// term to compare against, and a register beside it.
StudentPerformance fakePerformance({
  List<SubjectPerformance>? subjects,
  OverallPerformance? overall,
  PerformanceTerm? term,
  PerformanceTerm? previousTerm,
  List<PerformanceTerm>? terms,
  PerformanceAttendance? attendance,
  List<PerformanceInsight>? insights,
  List<PerformanceInsight>? recommendations,
  double? weakBelow = 40,

  /// Flags rather than null arguments: with `term ?? default` there is no
  /// way to ask for a school that has no term at all.
  bool withoutTerm = false,
  bool withoutPreviousTerm = false,
}) {
  return StudentPerformance(
    studentName: 'Arjun Kumar',
    classSectionName: 'Grade 8 A',
    term: withoutTerm ? null : (term ?? const PerformanceTerm(id: 2, name: 'Term 2', sequenceNumber: 2)),
    previousTerm: withoutTerm || withoutPreviousTerm
        ? null
        : (previousTerm ?? const PerformanceTerm(id: 1, name: 'Term 1', sequenceNumber: 1)),
    terms:
        terms ??
        const [
          PerformanceTerm(id: 2, name: 'Term 2', sequenceNumber: 2),
          PerformanceTerm(id: 1, name: 'Term 1', sequenceNumber: 1),
        ],
    subjects:
        subjects ??
        const [
          SubjectPerformance(
            subjectId: 1,
            subjectName: 'Mathematics',
            assessments: 3,
            absent: 1,
            averagePercentage: '34.00',
            grade: 'Pass',
            classAveragePercentage: '61.00',
            previousAveragePercentage: '48.00',
            change: '-14.00',
          ),
          SubjectPerformance(
            subjectId: 2,
            subjectName: 'Science',
            assessments: 2,
            absent: 0,
            averagePercentage: '78.00',
            grade: 'A2',
            classAveragePercentage: '66.00',
            previousAveragePercentage: '66.00',
            change: '12.00',
          ),
        ],
    overall:
        overall ??
        const OverallPerformance(
          subjects: 2,
          assessments: 5,
          absent: 1,
          averagePercentage: '56.00',
          classAveragePercentage: '63.50',
          previousAveragePercentage: '57.00',
          change: '-1.00',
        ),
    attendance:
        attendance ??
        const PerformanceAttendance(
          workingDays: 20,
          present: 14,
          absent: 4,
          leave: 1,
          notMarked: 1,
          attendanceRate: 70,
        ),
    recommendations: recommendations ?? const [],
    insights:
        insights ??
        const [
          PerformanceInsight(
            code: 'weak_subject',
            message: "Mathematics is at 34%, below the school's 40% mark.",
            subjectId: 1,
            subjectName: 'Mathematics',
            numbers: {'average': '34', 'threshold': '40'},
          ),
          PerformanceInsight(
            code: 'improving',
            message: 'Science is up 12 points since Term 1.',
            subjectId: 2,
            subjectName: 'Science',
            numbers: {'change': '12'},
          ),
        ],
    weakBelowPercentage: weakBelow,
  );
}
