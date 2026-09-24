import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/network/paginated_response.dart';
import 'package:edutrack_app/features/students/data/models/student.dart';
import 'package:edutrack_app/features/students/data/models/student_enrollment.dart';
import 'package:edutrack_app/features/students/data/student_repository.dart';

import 'fake_pagination.dart';

class FakeStudentRepository implements StudentRepository {
  FakeStudentRepository({
    List<Student>? students,
    List<StudentEnrollment>? enrollments,
    this.failCreateWith,
    this.failUpdateWith,
    this.failSetActiveWith,
    this.failListWith,
    this.failSetTransportWith,
    this.failWith = const {},
  }) : _students = students ?? [],
       _enrollments = enrollments ?? [];

  final List<Student> _students;
  final List<StudentEnrollment> _enrollments;

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
    required int page,
    required int perPage,
  }) async {
    searchCalls.add(search);
    if (failListWith != null) throw failListWith!;
    return paginateFake(
      _filtered(schoolId: schoolId, search: search),
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
  Future<List<StudentEnrollment>> enrollments(int studentId) async {
    calls.add('enrollments');
    final failure = failWith['enrollments'];
    if (failure != null) throw failure;

    return List.unmodifiable(_enrollments);
  }
}
