import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/network/paginated_response.dart';
import 'package:edutrack_app/features/holidays/data/holiday_repository.dart';
import 'package:edutrack_app/features/holidays/data/models/holiday.dart';

import 'fake_pagination.dart';

class FakeHolidayRepository implements HolidayRepository {
  FakeHolidayRepository({
    List<Holiday>? holidays,
    this.failCreateWith,
    this.failUpdateWith,
    this.failDeleteWith,
    this.failListPageWith,
  }) : _holidays = holidays ?? [];

  final List<Holiday> _holidays;
  Failure? failCreateWith;
  Failure? failUpdateWith;
  Failure? failDeleteWith;
  Failure? failListPageWith;

  Map<String, Object?>? lastListRequest;
  Map<String, Object?>? lastCreatePayload;
  Map<String, Object?>? lastUpdatePayload;
  int? lastDeletedId;

  List<Holiday> get holidays => List.unmodifiable(_holidays);

  @override
  Future<PaginatedResponse<Holiday>> listPage({
    int? schoolId,
    String? dateFrom,
    String? dateTo,
    required int page,
    required int perPage,
  }) async {
    if (failListPageWith != null) throw failListPageWith!;
    lastListRequest = {
      'school_id': schoolId,
      'date_from': dateFrom,
      'date_to': dateTo,
      'page': page,
      'per_page': perPage,
    };

    final filtered = _holidays.where((h) {
      if (schoolId != null && h.schoolId != schoolId) return false;
      if (dateFrom != null && h.endDate.compareTo(dateFrom) < 0) return false;
      if (dateTo != null && h.startDate.compareTo(dateTo) > 0) return false;
      return true;
    }).toList()..sort((a, b) => a.startDate.compareTo(b.startDate));

    return paginateFake(filtered, page: page, perPage: perPage);
  }

  @override
  Future<Holiday> create({
    int? schoolId,
    required String name,
    required HolidayType type,
    required String startDate,
    required String endDate,
  }) async {
    if (failCreateWith != null) throw failCreateWith!;
    lastCreatePayload = {
      'school_id': schoolId,
      'name': name,
      'type': type.apiValue,
      'start_date': startDate,
      'end_date': endDate,
    };
    final holiday = Holiday(
      id: _holidays.length + 1,
      schoolId: schoolId ?? 1,
      schoolName: 'Test School',
      name: name,
      type: type,
      startDate: startDate,
      endDate: endDate,
      days: DateTime.parse(endDate).difference(DateTime.parse(startDate)).inDays + 1,
    );
    _holidays.add(holiday);
    return holiday;
  }

  @override
  Future<Holiday> update(int holidayId, {String? name, HolidayType? type, String? startDate, String? endDate}) async {
    if (failUpdateWith != null) throw failUpdateWith!;
    lastUpdatePayload = {'name': name, 'type': type?.apiValue, 'start_date': startDate, 'end_date': endDate};

    final index = _holidays.indexWhere((h) => h.id == holidayId);
    final existing = _holidays[index];
    final start = startDate ?? existing.startDate;
    final end = endDate ?? existing.endDate;
    final updated = Holiday(
      id: existing.id,
      schoolId: existing.schoolId,
      schoolName: existing.schoolName,
      name: name ?? existing.name,
      type: type ?? existing.type,
      startDate: start,
      endDate: end,
      days: DateTime.parse(end).difference(DateTime.parse(start)).inDays + 1,
    );
    _holidays[index] = updated;
    return updated;
  }

  @override
  Future<void> delete(int holidayId) async {
    if (failDeleteWith != null) throw failDeleteWith!;
    lastDeletedId = holidayId;
    _holidays.removeWhere((h) => h.id == holidayId);
  }
}
