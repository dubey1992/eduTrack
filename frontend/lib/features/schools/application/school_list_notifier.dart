import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/paged_list.dart';
import '../data/models/school.dart';
import '../data/school_repository.dart';

/// The unpaginated "every school" list - used as a picker source across the
/// app (the school filter dropdown, every "Add X" dialog's school picker),
/// where truncating to one page would silently hide real schools. The
/// Schools management screen itself uses [schoolPageNotifierProvider] below.
final schoolListNotifierProvider = AsyncNotifierProvider<SchoolListNotifier, List<School>>(SchoolListNotifier.new);

class SchoolListNotifier extends AsyncNotifier<List<School>> {
  @override
  Future<List<School>> build() {
    return ref.read(schoolRepositoryProvider).list();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => ref.read(schoolRepositoryProvider).list());
  }
}

final schoolPageNotifierProvider = AsyncNotifierProvider<SchoolPageNotifier, PagedList<School>>(SchoolPageNotifier.new);

/// The paginated view behind the Schools management screen.
class SchoolPageNotifier extends AsyncNotifier<PagedList<School>> {
  int _page = 1;
  int _perPage = 20;

  @override
  Future<PagedList<School>> build() => _fetch();

  Future<PagedList<School>> _fetch() async {
    final response = await ref.read(schoolRepositoryProvider).listPage(page: _page, perPage: _perPage);

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

  Future<void> createSchool({
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
    await ref
        .read(schoolRepositoryProvider)
        .create(
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
        );
    _page = 1;
    await refresh();
    // Keeps every school picker across the app in sync, since they read the
    // separate unpaginated provider above.
    ref.invalidate(schoolListNotifierProvider);
  }

  Future<void> updateSchool(
    School school, {
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
    final updated = await ref
        .read(schoolRepositoryProvider)
        .update(
          school.id,
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
        );

    this.state = this.state.whenData(
      (page) => page.withItems([for (final existing in page.items) existing.id == updated.id ? updated : existing]),
    );
    ref.invalidate(schoolListNotifierProvider);
  }

  Future<void> setActive(School school, bool active) async {
    final updated = await ref.read(schoolRepositoryProvider).setActive(school.id, active);

    state = state.whenData(
      (page) => page.withItems([for (final existing in page.items) existing.id == updated.id ? updated : existing]),
    );
    ref.invalidate(schoolListNotifierProvider);
  }
}
