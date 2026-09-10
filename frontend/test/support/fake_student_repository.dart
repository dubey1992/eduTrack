import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/network/paginated_response.dart';
import 'package:edutrack_app/features/students/data/models/student.dart';
import 'package:edutrack_app/features/students/data/student_repository.dart';

import 'fake_pagination.dart';

class FakeStudentRepository implements StudentRepository {
  FakeStudentRepository({
    List<Student>? students,
    this.failCreateWith,
    this.failUpdateWith,
    this.failSetActiveWith,
    this.failListWith,
    this.failSetTransportWith,
  }) : _students = students ?? [];

  final List<Student> _students;
  Failure? failCreateWith;
  Failure? failUpdateWith;
  Failure? failSetActiveWith;
  Failure? failListWith;
  Failure? failSetTransportWith;

  List<Student> get students => List.unmodifiable(_students);

  List<Student> _filtered({int? schoolId}) {
    return schoolId == null ? _students : _students.where((s) => s.schoolId == schoolId).toList();
  }

  @override
  Future<List<Student>> list({int? schoolId, int? classSectionId, String? search}) async {
    if (failListWith != null) throw failListWith!;
    return List.unmodifiable(_filtered(schoolId: schoolId));
  }

  @override
  Future<PaginatedResponse<Student>> listPage({
    int? schoolId,
    int? classSectionId,
    String? search,
    required int page,
    required int perPage,
  }) async {
    if (failListWith != null) throw failListWith!;
    return paginateFake(
      _filtered(schoolId: schoolId),
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
      address: address,
      status: StudentStatus.active,
    );
    _students.add(student);
    return student;
  }

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
    String? address,
  }) async {
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
}
