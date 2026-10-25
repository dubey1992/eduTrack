import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/network/paginated_response.dart';
import 'package:edutrack_app/features/schools/data/models/school.dart';
import 'package:edutrack_app/features/schools/data/models/working_week.dart';
import 'package:edutrack_app/features/schools/data/models/timezone_option.dart';
import 'package:edutrack_app/features/schools/data/school_repository.dart';

import 'fake_pagination.dart';

class FakeSchoolRepository implements SchoolRepository {
  /// The School Admin the last create() was asked for - null when none.
  Map<String, String?>? lastCreateAdmin;

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

  /// What the list was last narrowed by, so a test can check the screen
  /// asked the server rather than filtering rows it already had.
  String? lastQuery;
  String? lastStatus;

  @override
  Future<PaginatedResponse<School>> listPage({
    required int page,
    required int perPage,
    String? q,
    String? status,
  }) async {
    if (failListPageWith != null) throw failListPageWith!;

    lastQuery = q;
    lastStatus = status;

    // Narrowed here only so a screen test can see fewer rows come back.
    // The real one is a query; see SchoolService.scoped.
    var rows = _schools;

    if (q != null && q.isNotEmpty) {
      rows = rows.where((school) => school.name.toLowerCase().contains(q.toLowerCase())).toList();
    }

    if (status != null) {
      rows = rows.where((school) => school.status.apiValue == status).toList();
    }

    return paginateFake(rows, page: page, perPage: perPage);
  }

  /// What the map calls to open a pin that is not on the list's page.
  int finds = 0;
  int? lastFound;
  Failure? failFindWith;

  @override
  Future<School> find(int schoolId) async {
    finds++;
    lastFound = schoolId;

    if (failFindWith != null) throw failFindWith!;

    return _schools.firstWhere((school) => school.id == schoolId);
  }

  @override
  Future<School> create({
    required String name,
    int? parentSchoolId,
    int? earlyAccessRequestId,
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
    required WorkingWeek workingDays,
    String? latitude,
    String? longitude,
    String? adminFirstName,
    String? adminLastName,
    String? adminEmail,
    String? adminPassword,
  }) async {
    lastCreateAdmin = adminFirstName == null
        ? null
        : {'first_name': adminFirstName, 'last_name': adminLastName, 'email': adminEmail, 'password': adminPassword};
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
    WorkingWeek? workingDays,
    String? latitude,
    String? longitude,
    bool changeParent = false,
    int? parentSchoolId,
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
