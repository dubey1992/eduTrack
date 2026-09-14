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

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_fetch);
  }

  Future<void> setSchoolFilter(int? schoolId) async {
    _schoolId = schoolId;
    await refresh();
  }
}
