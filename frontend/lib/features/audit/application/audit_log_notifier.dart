import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/paged_list.dart';
import '../data/audit_log_repository.dart';
import '../data/models/audit_entry.dart';

/// What the audit trail is narrowed to. The list and the CSV export both
/// read it, so the file always matches what is on screen.
class AuditLogFilter {
  const AuditLogFilter({this.schoolId, this.module, this.from, this.to});

  final int? schoolId;

  /// A module's API value, e.g. `staff_attendance`.
  final String? module;

  /// yyyy-MM-dd.
  final String? from;

  /// yyyy-MM-dd.
  final String? to;
}

final auditLogNotifierProvider = AsyncNotifierProvider<AuditLogNotifier, PagedList<AuditEntry>>(AuditLogNotifier.new);

class AuditLogNotifier extends AsyncNotifier<PagedList<AuditEntry>> {
  AuditLogFilter _filter = const AuditLogFilter();
  int _page = 1;
  int _perPage = 20;

  AuditLogFilter get filter => _filter;

  @override
  Future<PagedList<AuditEntry>> build() => _fetch();

  Future<PagedList<AuditEntry>> _fetch() async {
    final response = await ref
        .read(auditLogRepositoryProvider)
        .list(
          schoolId: _filter.schoolId,
          module: _filter.module,
          from: _filter.from,
          to: _filter.to,
          page: _page,
          perPage: _perPage,
        );

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

  Future<void> setSchoolFilter(int? schoolId) {
    _filter = AuditLogFilter(schoolId: schoolId, module: _filter.module, from: _filter.from, to: _filter.to);
    return _firstPage();
  }

  Future<void> setModuleFilter(String? module) {
    _filter = AuditLogFilter(schoolId: _filter.schoolId, module: module, from: _filter.from, to: _filter.to);
    return _firstPage();
  }

  /// Both ends or neither - a range is picked as a whole.
  Future<void> setDateRange({String? from, String? to}) {
    _filter = AuditLogFilter(schoolId: _filter.schoolId, module: _filter.module, from: from, to: to);
    return _firstPage();
  }

  Future<void> goToPage(int page) async {
    _page = page;
    await refresh();
  }

  Future<void> setPerPage(int perPage) {
    _perPage = perPage;
    return _firstPage();
  }

  Future<void> _firstPage() async {
    _page = 1;
    await refresh();
  }
}
