import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/network/paginated_response.dart';
import 'package:edutrack_app/features/schools/data/models/school.dart';
import 'package:edutrack_app/features/schools/data/models/timezone_option.dart';
import 'package:edutrack_app/features/schools/data/school_repository.dart';

import 'fake_pagination.dart';

class FakeSchoolRepository implements SchoolRepository {
  FakeSchoolRepository({
    List<School>? schools,
    this.failCreateWith,
    this.failUpdateWith,
    this.failListPageWith,
    this.failListTimezonesWith,
  }) : _schools = schools ?? [];

  final List<School> _schools;
  Failure? failCreateWith;
  Failure? failUpdateWith;
  Failure? failListPageWith;
  Failure? failListTimezonesWith;
  int listCallCount = 0;

  /// A couple of real zones is enough for the picker; the full list comes
  /// from PHP's database and is not worth restating here.
  List<TimezoneOption> timezones = const [
    TimezoneOption(name: 'UTC', region: 'Other', label: 'UTC (GMT+00:00)', offsetMinutes: 0),
    TimezoneOption(name: 'Asia/Kolkata', region: 'Asia', label: 'Asia/Kolkata (GMT+05:30)', offsetMinutes: 330),
  ];

  @override
  Future<List<TimezoneOption>> listTimezones() async {
    if (failListTimezonesWith != null) throw failListTimezonesWith!;

    return timezones;
  }

  @override
  Future<List<School>> list() async {
    listCallCount++;
    return List.unmodifiable(_schools);
  }

  @override
  Future<PaginatedResponse<School>> listPage({required int page, required int perPage}) async {
    if (failListPageWith != null) throw failListPageWith!;
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
    required String timezone,
    String? latitude,
    String? longitude,
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
      timezone: timezone,
      latitude: latitude,
      longitude: longitude,
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
    String? timezone,
    String? latitude,
    String? longitude,
  }) async {
    if (failUpdateWith != null) throw failUpdateWith!;

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
      timezone: timezone ?? existing.timezone,
      latitude: latitude ?? existing.latitude,
      longitude: longitude ?? existing.longitude,
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
