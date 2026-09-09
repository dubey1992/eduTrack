import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/network/paginated_response.dart';
import 'package:edutrack_app/features/schools/data/models/school.dart';
import 'package:edutrack_app/features/schools/data/school_repository.dart';

import 'fake_pagination.dart';

class FakeSchoolRepository implements SchoolRepository {
  FakeSchoolRepository({List<School>? schools, this.failCreateWith}) : _schools = schools ?? [];

  final List<School> _schools;
  Failure? failCreateWith;
  int listCallCount = 0;

  @override
  Future<List<School>> list() async {
    listCallCount++;
    return List.unmodifiable(_schools);
  }

  @override
  Future<PaginatedResponse<School>> listPage({required int page, required int perPage}) async {
    return paginateFake(_schools, page: page, perPage: perPage);
  }

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
  Future<School> update(
    int schoolId, {
    String? name,
    String? registrationNumber,
    String? email,
    String? phone,
    String? address,
    String? city,
    String? state,
    String? country,
    String? postalCode,
    String? currencyCode,
  }) async {
    final index = _schools.indexWhere((s) => s.id == schoolId);
    final existing = _schools[index];
    final updated = School(
      id: existing.id,
      name: name ?? existing.name,
      registrationNumber: registrationNumber,
      email: email ?? existing.email,
      phone: phone ?? existing.phone,
      address: address ?? existing.address,
      city: city ?? existing.city,
      state: state ?? existing.state,
      country: country ?? existing.country,
      postalCode: postalCode ?? existing.postalCode,
      currencyCode: currencyCode ?? existing.currencyCode,
      logoUrl: existing.logoUrl,
      status: existing.status,
    );
    _schools[index] = updated;
    return updated;
  }

  @override
  Future<School> setActive(int schoolId, bool active) async {
    final index = _schools.indexWhere((s) => s.id == schoolId);
    final updated = _schools[index].copyWith(status: active ? SchoolStatus.active : SchoolStatus.inactive);
    _schools[index] = updated;
    return updated;
  }
}
