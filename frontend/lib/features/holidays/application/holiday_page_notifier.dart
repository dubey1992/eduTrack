import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/paged_list.dart';
import '../data/holiday_repository.dart';
import '../data/models/holiday.dart';

final holidayPageNotifierProvider = AsyncNotifierProvider<HolidayPageNotifier, PagedList<Holiday>>(
  HolidayPageNotifier.new,
);

/// The paginated view behind the Holidays screen - same shape as
/// DepartmentPageNotifier, plus an optional date window filter.
class HolidayPageNotifier extends AsyncNotifier<PagedList<Holiday>> {
  int? _schoolId;
  String? _dateFrom;
  String? _dateTo;
  int _page = 1;
  int _perPage = 20;

  @override
  Future<PagedList<Holiday>> build() => _fetch();

  Future<PagedList<Holiday>> _fetch() async {
    final response = await ref
        .read(holidayRepositoryProvider)
        .listPage(schoolId: _schoolId, dateFrom: _dateFrom, dateTo: _dateTo, page: _page, perPage: _perPage);

    return PagedList(
      items: response.items,
      currentPage: response.currentPage,
      lastPage: response.lastPage,
      total: response.total,
      perPage: response.perPage,
    );
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_fetch);
  }

  Future<void> setSchoolFilter(int? schoolId) async {
    _schoolId = schoolId;
    _page = 1;
    await refresh();
  }

  Future<void> setDateWindow({String? from, String? to}) async {
    _dateFrom = from;
    _dateTo = to;
    _page = 1;
    await refresh();
  }

  Future<void> goToPage(int page) async {
    _page = page;
    await refresh();
  }

  Future<void> setPerPage(int perPage) async {
    _perPage = perPage;
    _page = 1;
    await refresh();
  }

  Future<void> createHoliday({
    int? schoolId,
    required String name,
    required HolidayType type,
    required String startDate,
    required String endDate,
  }) async {
    await ref
        .read(holidayRepositoryProvider)
        .create(schoolId: schoolId, name: name, type: type, startDate: startDate, endDate: endDate);
    _page = 1;
    await refresh();
  }

  Future<void> updateHoliday(
    Holiday holiday, {
    String? name,
    HolidayType? type,
    String? startDate,
    String? endDate,
  }) async {
    await ref
        .read(holidayRepositoryProvider)
        .update(holiday.id, name: name, type: type, startDate: startDate, endDate: endDate);
    await refresh();
  }

  Future<void> deleteHoliday(Holiday holiday) async {
    await ref.read(holidayRepositoryProvider).delete(holiday.id);
    await refresh();
  }
}
