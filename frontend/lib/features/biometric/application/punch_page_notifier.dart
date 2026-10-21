import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/paged_list.dart';
import '../data/biometric_repository.dart';
import '../data/models/biometric_punch.dart';

final punchPageNotifierProvider = AsyncNotifierProvider<PunchPageNotifier, PagedList<BiometricPunch>>(
  PunchPageNotifier.new,
);

/// The device log (docs/biometric.md, B2).
class PunchPageNotifier extends AsyncNotifier<PagedList<BiometricPunch>> {
  int? _schoolId;
  int _page = 1;
  int _perPage = 20;
  String _q = '';
  String? _date;
  bool _unmatchedOnly = false;

  bool get unmatchedOnly => _unmatchedOnly;
  String? get date => _date;

  /// How many punches nobody can attribute, under the same filters. Beside
  /// the page rather than counted from it.
  int unmatchedTotal = 0;

  @override
  Future<PagedList<BiometricPunch>> build() => _fetch();

  Future<PagedList<BiometricPunch>> _fetch() async {
    final answer = await ref
        .read(biometricRepositoryProvider)
        .listPunches(
          schoolId: _schoolId,
          page: _page,
          perPage: _perPage,
          q: _q.isEmpty ? null : _q,
          date: _date,
          unmatchedOnly: _unmatchedOnly,
        );

    unmatchedTotal = answer.unmatchedTotal;

    final response = answer.page;

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

  Future<void> goToPage(int page) async {
    _page = page;
    await refresh();
  }

  Future<void> setPerPage(int perPage) async {
    _perPage = perPage;
    _page = 1;
    await refresh();
  }

  /// Back to page one, always: narrowing while on page four asks for a page
  /// that may no longer exist.
  Future<void> setSchoolFilter(int? schoolId) async {
    _schoolId = schoolId;
    _page = 1;
    await refresh();
  }

  Future<void> setSearch(String term) async {
    _q = term.trim();
    _page = 1;
    await refresh();
  }

  Future<void> setDate(String? date) async {
    _date = date;
    _page = 1;
    await refresh();
  }

  Future<void> setUnmatchedOnly(bool only) async {
    _unmatchedOnly = only;
    _page = 1;
    await refresh();
  }
}
