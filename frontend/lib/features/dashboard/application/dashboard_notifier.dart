import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/dashboard_repository.dart';
import '../data/models/dashboard.dart';

final dashboardNotifierProvider = AsyncNotifierProvider<DashboardNotifier, Dashboard>(DashboardNotifier.new);

/// The landing screen's figures. Re-read on demand, since they describe
/// today and today keeps moving.
class DashboardNotifier extends AsyncNotifier<Dashboard> {
  int? _schoolId;

  int? get schoolId => _schoolId;

  @override
  Future<Dashboard> build() => _fetch();

  Future<Dashboard> _fetch() => ref.read(dashboardRepositoryProvider).fetch(schoolId: _schoolId);

  /// Re-reads the figures.
  ///
  /// [keepFigures] leaves the ones on screen until the new ones arrive -
  /// for the quiet re-read when somebody comes back to the dashboard. Going
  /// through a loading state there swapped the whole page for a spinner
  /// while they were reading it: the page collapsed, its scroll position
  /// went with it, and everything jumped back when the figures returned.
  /// Asked for by hand (Refresh) it does show the loader, as it should.
  Future<void> refresh({bool keepFigures = false}) async {
    if (!keepFigures || !state.hasValue) state = const AsyncLoading();
    state = await AsyncValue.guard(_fetch);
  }

  /// Another school's figures: never shown under the old one's while they
  /// load.
  Future<void> setSchoolFilter(int? schoolId) async {
    _schoolId = schoolId;
    await refresh();
  }
}
