import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/features/schools/data/models/school.dart';
import 'package:edutrack_app/features/schools/data/school_repository.dart';

class FakeSchoolRepository implements SchoolRepository {
  FakeSchoolRepository({List<School>? schools, this.failCreateWith}) : _schools = schools ?? [];

  final List<School> _schools;
  Failure? failCreateWith;

  @override
  Future<List<School>> list() async => List.unmodifiable(_schools);

  @override
  Future<School> create({
    required String name,
    String? registrationNumber,
    required String email,
    required String phone,
    required String address,
    required String city,
    required String state,
    required String country,
    required String postalCode,
    required String currencyCode,
  }) async {
    if (failCreateWith != null) throw failCreateWith!;

    final school = School(
      id: _schools.length + 1,
      name: name,
      registrationNumber: registrationNumber,
      email: email,
      phone: phone,
      address: address,
      city: city,
      state: state,
      country: country,
      postalCode: postalCode,
      currencyCode: currencyCode,
      logoUrl: null,
      status: SchoolStatus.active,
    );
    _schools.add(school);
    return school;
  }

  @override
  Future<School> setActive(int schoolId, bool active) async {
    final index = _schools.indexWhere((s) => s.id == schoolId);
    final updated = _schools[index].copyWith(status: active ? SchoolStatus.active : SchoolStatus.inactive);
    _schools[index] = updated;
    return updated;
  }
}
